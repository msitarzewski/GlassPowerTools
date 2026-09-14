import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog

@Suite("Host pairing and persistent catalog")
struct HostCatalogTests {
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("glass-host-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("hosts.json")
    }

    @Test("Pairing preserves independent protocol credentials and endpoint identities")
    func pairingIndependence() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let host = try HostProfile(displayName: "Build machine", aliases: ["build.local"])
        let desktop = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop", credentialID: CredentialID())
        let terminal = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal", credentialID: CredentialID())
        try await store.upsert(host)
        try await store.pair(desktop, with: host.id)
        try await store.pair(terminal, with: host.id)
        let paired = try #require(await store.snapshot().first)
        #expect(paired.services == [desktop, terminal])
        #expect(desktop.credentialID != terminal.credentialID)
        try await store.unpair(endpointID: terminal.endpointID, from: host.id)
        #expect(try await store.snapshot().first?.services == [desktop])
        let reopened = HostCatalogStore(fileURL: url)
        #expect(try await reopened.snapshot().first?.services == [desktop])
    }

    @Test("Same endpoint cannot silently become paired with a second host")
    func duplicatePairingIsAtomic() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let a = try HostProfile(displayName: "A"), b = try HostProfile(displayName: "B")
        let link = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop")
        try await store.upsert(a)
        try await store.upsert(b)
        try await store.pair(link, with: a.id)
        let before = try Data(contentsOf: url)
        await #expect(throws: HostCatalogError.endpointAlreadyPaired(link.endpointID)) {
            try await store.pair(link, with: b.id)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("Independent writers do not lose concurrent additions")
    func concurrentWriters() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let store = HostCatalogStore(fileURL: url)
                    try await store.upsert(HostProfile(displayName: "Host \(index)"))
                }
            }
            try await group.waitForAll()
        }
        #expect(try await HostCatalogStore(fileURL: url).snapshot().count == 40)
    }

    @Test("Tombstones survive offline newer edits and retain references only as history")
    func tombstones() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        var host = try HostProfile(displayName: "A", services: [
            HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "Database", credentialID: CredentialID())
        ])
        try await store.upsert(host)
        try await store.delete(hostID: host.id)
        host.updatedAt = Date().addingTimeInterval(3600)
        try await store.merge([host])
        #expect(try await store.snapshot().isEmpty)
        let history = try #require(await store.snapshot(includeDeleted: true).first)
        #expect(history.deletedAt != nil)
        #expect(history.services == host.services)
        await #expect(throws: HostCatalogError.hostDeleted(host.id)) { try await store.upsert(host) }
    }

    @Test("Merge order is deterministic")
    func deterministicMerge() async throws {
        let firstURL = try location(), secondURL = try location()
        defer {
            try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent())
        }
        let a = HostCatalogStore(fileURL: firstURL), b = HostCatalogStore(fileURL: secondURL)
        let date = Date(timeIntervalSince1970: 1_000)
        let first = try HostProfile(displayName: "First", createdAt: date, updatedAt: date)
        var second = first
        second.displayName = "Second"
        second.lastWriterID = WriterID()
        try await a.merge([first]); try await a.merge([second])
        try await b.merge([second]); try await b.merge([first])
        #expect(try await a.snapshot() == b.snapshot())
        #expect(try Data(contentsOf: firstURL) == Data(contentsOf: secondURL))
    }

    @Test("Malformed and unknown-version files are preserved")
    func malformedPreserved() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = Data("{\"schemaVersion\":9,\"hosts\":[]}".utf8)
        try data.write(to: url)
        let store = HostCatalogStore(fileURL: url)
        await #expect(throws: HostCatalogError.unsupportedVersion(9)) {
            try await store.upsert(HostProfile(displayName: "New"))
        }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("Metadata encoding contains references but no credential material")
    func metadataContract() throws {
        let host = try HostProfile(displayName: "Example", services: [
            HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop", credentialID: CredentialID())
        ])
        let data = try JSONEncoder().encode(host)
        #expect(try JSONDecoder().decode(HostProfile.self, from: data) == host)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["password"] == nil)
        #expect(json["privateKey"] == nil)
        #expect(json["hostTrust"] == nil)
    }

    @Test("Malformed host metadata fails decoding")
    func validationOnDecode() throws {
        let host = try HostProfile(displayName: "Valid")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(host)) as? [String: Any])
        json["displayName"] = ""
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: HostProfileError.invalidName) { try JSONDecoder().decode(HostProfile.self, from: data) }
    }

    @Test("Publish has stable identity and concurrent republishing preserves explicit pairing")
    func publishAndMove() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let endpointID = EndpointID()
        let credentialID = CredentialID()
        let link = HostServiceLink(endpointID: endpointID, kind: .ssh, displayName: "Terminal", credentialID: credentialID)
        let initial = try await store.publish(service: link, hostName: "ssh.local", aliases: ["ssh.local"])
        #expect(initial.id.rawValue == endpointID.rawValue)
        let target = try HostProfile(displayName: "My workstation")
        try await store.upsert(target)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await HostCatalogStore(fileURL: url).move(endpointID: endpointID, to: target.id) }
            for _ in 0..<20 {
                group.addTask {
                    let publisher = HostCatalogStore(fileURL: url)
                    // A publisher that lacks the credential catalog must not erase its reference.
                    let metadata = HostServiceLink(endpointID: endpointID, kind: .ssh, displayName: "Renamed terminal")
                    try await publisher.publish(service: metadata, hostName: "ssh.local", aliases: ["ssh.local"])
                }
            }
            try await group.waitForAll()
        }
        let all = try await store.snapshot(includeDeleted: true)
        let paired = try #require(all.first(where: { $0.id == target.id }))
        #expect(paired.displayName == "My workstation")
        #expect(paired.services.count == 1)
        #expect(paired.services.first?.endpointID == endpointID)
        #expect(paired.services.first?.credentialID == credentialID)
        #expect(all.first(where: { $0.id == initial.id })?.deletedAt != nil)
    }

    @Test("Move preserves other services and missing-target failures preserve bytes")
    func moveIndependence() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let ssh = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal", credentialID: CredentialID())
        let db = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "DB", credentialID: CredentialID())
        let desktop = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop", credentialID: CredentialID())
        let source = try HostProfile(displayName: "Source", services: [ssh, db])
        let target = try HostProfile(displayName: "Target", services: [desktop])
        try await store.upsert(source); try await store.upsert(target)
        let before = try Data(contentsOf: url), missingID = HostID()
        await #expect(throws: HostCatalogError.hostNotFound(missingID)) {
            try await store.move(endpointID: ssh.endpointID, to: missingID)
        }
        #expect(try Data(contentsOf: url) == before)
        try await store.move(endpointID: ssh.endpointID, to: target.id)
        let all = try await store.snapshot()
        #expect(all.first(where: { $0.id == source.id })?.services == [db])
        #expect(all.first(where: { $0.id == target.id })?.services == [desktop, ssh])
    }

    @Test("Batch publication is atomic and identical replays preserve revisions")
    func batchPublication() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let first = HostPublication(service: HostServiceLink(endpointID: EndpointID(), kind: .ssh,
            displayName: "Terminal"), hostName: "Machine", aliases: ["machine.local"])
        let second = HostPublication(service: HostServiceLink(endpointID: EndpointID(), kind: .database,
            displayName: "Database"), hostName: "DB server")
        let initial = try await store.publish([first, second])
        #expect(initial.count == 2)
        let before = try Data(contentsOf: url)
        let repeated = try await store.publish([first, second], at: Date().addingTimeInterval(3600))
        #expect(repeated == initial)
        #expect(try Data(contentsOf: url) == before)
        let third = HostPublication(service: HostServiceLink(endpointID: EndpointID(), kind: .rdp,
            displayName: "Desktop"), hostName: "Another")
        let invalid = HostPublication(service: HostServiceLink(endpointID: EndpointID(), kind: .rdp,
            displayName: ""), hostName: "Invalid")
        await #expect(throws: HostProfileError.invalidName) { try await store.publish([third, invalid]) }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("New host timestamps survive millisecond serialization without drift")
    func timestampPrecision() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        for offset in 0..<128 {
            let date = Date(timeIntervalSince1970: 1_788_900_000.123456 + Double(offset) / 1_000_000)
            let profile = try HostProfile(displayName: "Precise", createdAt: date, updatedAt: date)
            #expect(try decoder.decode(HostProfile.self, from: encoder.encode(profile)) == profile)
        }
    }
    @Test("Detach preserves service identity, independent credentials and publication membership")
    func detachPreservesService() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let ssh = HostServiceLink(endpointID: EndpointID(), kind: .ssh,
            displayName: "Terminal", credentialID: CredentialID())
        let rdp = HostServiceLink(endpointID: EndpointID(), kind: .rdp,
            displayName: "Desktop", credentialID: CredentialID())
        let source = try HostProfile(displayName: "Workstation", aliases: ["work.local"], services: [ssh, rdp])
        try await store.upsert(source)
        let detached = try await store.detach(endpointID: ssh.endpointID)
        #expect(detached.id != source.id)
        #expect(detached.services == [ssh])
        #expect(try await store.snapshot().first(where: { $0.id == source.id })?.services == [rdp])
        let republished = try await store.publish(service: ssh, hostName: "work.local")
        #expect(republished == detached)
        let before = try Data(contentsOf: url)
        #expect(try await store.detach(endpointID: ssh.endpointID) == detached)
        #expect(try Data(contentsOf: url) == before)
        let absent = EndpointID()
        await #expect(throws: HostCatalogError.endpointNotFound(absent)) {
            try await store.detach(endpointID: absent)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("Explicit endpoint deletion preserves other pairs and retries idempotently")
    func removalRecovery() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HostCatalogStore(fileURL: url)
        let ssh = HostServiceLink(endpointID: EndpointID(), kind: .ssh,
            displayName: "Terminal", credentialID: CredentialID())
        let db = HostServiceLink(endpointID: EndpointID(), kind: .database,
            displayName: "Database", credentialID: CredentialID())
        let source = try HostProfile(displayName: "Server", services: [ssh, db])
        try await store.upsert(source)
        try await store.remove(endpointID: ssh.endpointID)
        #expect(try await store.snapshot().first?.services == [db])
        let before = try Data(contentsOf: url)
        try await HostCatalogStore(fileURL: url).remove(endpointID: ssh.endpointID)
        #expect(try Data(contentsOf: url) == before)
        try await store.remove(endpointID: db.endpointID)
        #expect(try await store.snapshot().isEmpty)
        let tombstone = try #require(await store.snapshot(includeDeleted: true).first)
        #expect(tombstone.id == source.id)
        #expect(tombstone.deletedAt != nil)
        #expect(tombstone.services.isEmpty)
    }

}
