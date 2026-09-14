import Foundation
import Testing
import GlassConnectionKit
@testable import GlassHostCatalog

@MainActor
struct HostCatalogDeletionOutboxTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func explicitDeletionSurvivesRestartAndPreservesPairedService() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = HostCatalogStore(fileURL: directory.appendingPathComponent("hosts.json"))
        let ssh = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal")
        let db = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "Database")
        let host = try await catalog.publish(service: ssh, hostName: "Host")
        try await catalog.pair(db, with: host.id)
        let journal = directory.appendingPathComponent("outbox.json")
        try HostCatalogDeletionOutbox(fileURL: journal).stage(endpointID: ssh.endpointID)
        let reopened = HostCatalogDeletionOutbox(fileURL: journal)
        try await reopened.flush(to: catalog, activeEndpointIDs: [])
        #expect(try reopened.pendingEndpointIDs().isEmpty)
        let remaining = try await catalog.snapshot()
        #expect(remaining.count == 1)
        #expect(remaining[0].services == [db])
    }

    @Test func rollbackCancelsIntentAndOmissionWithoutIntentDoesNothing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = HostCatalogStore(fileURL: directory.appendingPathComponent("hosts.json"))
        let service = HostServiceLink(endpointID: EndpointID(), kind: .rdp, displayName: "Desktop")
        _ = try await catalog.publish(service: service, hostName: "Host")
        let outbox = HostCatalogDeletionOutbox(fileURL: directory.appendingPathComponent("outbox.json"))
        try await outbox.flush(to: catalog, activeEndpointIDs: [])
        #expect(try await catalog.snapshot().count == 1)
        try outbox.stage(endpointID: service.endpointID)
        try await outbox.flush(to: catalog, activeEndpointIDs: [service.endpointID])
        #expect(try outbox.pendingEndpointIDs().isEmpty)
        #expect(try await catalog.snapshot().first?.services == [service])
    }

    @Test func failedSharedWriteRetainsIntentForRetry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostFile = directory.appendingPathComponent("hosts.json")
        try Data("broken catalog".utf8).write(to: hostFile)
        let catalog = HostCatalogStore(fileURL: hostFile)
        let endpoint = EndpointID()
        let journal = directory.appendingPathComponent("outbox.json")
        let outbox = HostCatalogDeletionOutbox(fileURL: journal)
        try outbox.stage(endpointID: endpoint)
        do {
            try await outbox.flush(to: catalog, activeEndpointIDs: [])
            Issue.record("Corrupt shared catalog must fail without losing the deletion intent")
        } catch { }
        #expect(try HostCatalogDeletionOutbox(fileURL: journal).pendingEndpointIDs() == [endpoint])
        try FileManager.default.removeItem(at: hostFile)
        try await outbox.flush(to: catalog, activeEndpointIDs: [])
        #expect(try outbox.pendingEndpointIDs().isEmpty)
    }
}
