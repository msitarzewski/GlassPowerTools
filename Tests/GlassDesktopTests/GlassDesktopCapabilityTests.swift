import Foundation
import Testing
import GlassConnectionKit
import GlassShell
import GlasSecretStore
@testable import GlassDesktop

/// A throwaway desktop model writing to its own directory, with the Keychain replaced so these
/// tests never touch the user's real credentials — the lesson of the UI-test pollution sweep.
@MainActor
private func makeRuntime() async throws -> (GlassDesktopRuntime, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("GlassDesktopTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let app = DesktopAppModel(storageDirectory: root, credentialAccess: .inMemory())
    // D26: a model with no library attached reads and writes nothing, and says so. Tests get an
    // in-memory catalog rather than the shell's, which is the whole point of the narrow protocol.
    await app.attach(store: GlassInMemoryServiceStore(defaultKind: .rdp))
    return (GlassDesktopRuntime(app: app), root)
}

private func host(_ name: String = "foxtrot", address: String = "198.51.100.9") throws -> HostProfile {
    try HostProfile(id: HostID(rawValue: UUID()), displayName: name, address: address)
}

@Suite("GlassDesktopCapability", .serialized)
@MainActor
struct GlassDesktopCapabilityTests {

    @Test("A desktop on screen is a row in Active, on its service's endpoint, until it closes")
    func openSessionsListsLiveDesktops() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        #expect(capability.openSessions().isEmpty)

        let connection = DesktopConnection(name: "alpha", host: "alpha.local", username: "casey")
        // A connect that fails at once, as one to a machine that isn't there does. The real one
        // dialled alpha.local — an mDNS lookup on the owner's network — until it was closed
        // (2026-10-24). A failed desktop is still on screen.
        var operations = DesktopSessionOperations()
        struct NoMachine: Error {}
        operations.connect = { _, _ in throw NoMachine() }
        operations.disconnect = { _ in }
        operations.save = { _, _, _ in }
        operations.recordConnection = { _, _, _ in }
        let session = DesktopSessionModel(connection: connection, app: runtime.app, operations: operations,
                                          wallpaperRoot: root.appendingPathComponent("wallpapers"))
        try? await session.connect(username: "casey", domain: nil, password: "x")
        let rows = capability.openSessions()
        #expect(rows.map(\.id) == [GlassDesktopCapability.sessionID(connectionID: connection.id)])
        #expect(rows.first?.title == "alpha")
        #expect(rows.first?.endpointIDs == [connection.id], "on its machine")
        #expect(rows.first?.subtitle?.hasPrefix("RDP") == true)

        await session.close().value
        #expect(capability.openSessions().isEmpty, "closed, it is gone")
    }

    /// 2026-10-11: a Mac starts its Screen Sharing daemon and agent for every connection to 5900.
    @Test("VNC is probed for availability every ten minutes, RDP every minute")
    func availabilityInterval() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let machine = try host()
        let vnc = DesktopConnection(name: "alpha", host: "198.51.100.9", port: 5900, username: "casey", protocol: .vnc)
        let rdp = DesktopConnection(name: "bravo", host: "198.51.100.9", username: "casey")
        try await runtime.app.save(vnc, password: nil)
        try await runtime.app.save(rdp, password: nil)
        func link(_ connection: DesktopConnection) -> HostServiceLink {
            HostServiceLink(endpointID: connection.id, kind: .rdp, displayName: connection.name)
        }
        #expect(capability.availabilityInterval(service: link(vnc), host: machine) == 600)
        #expect(capability.availabilityInterval(service: link(rdp), host: machine) == GlassAvailabilityMonitor.interval)
    }

    @Test("The capability owns .rdp and serves both protocols through the record's field")
    func servesBothProtocols() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        #expect(capability.kind == .rdp, "one service kind; the protocol is a field, so the catalog needs no .vnc case")
        let draft = capability.makeSetupDraft()
        #expect(draft.kind == .rdp)
    }

    @Test("A desktop is created complete: record and credential, under the shell's endpoint id")
    func createsAServiceComplete() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let machine = try host()
        let endpoint = EndpointID(rawValue: UUID())

        let draft = try #require(capability.makeSetupDraft() as? DesktopServiceDraft)
        draft.username = "casey"
        draft.password = "correct-horse"
        #expect(draft.validate(address: machine.address ?? "").isEmpty)
        try await draft.commit(endpointID: endpoint, host: machine, address: "198.51.100.9")

        let saved = try #require(runtime.connection(for: endpoint))
        #expect(saved.host == "198.51.100.9", "the address is the host's, passed in at commit")
        #expect(saved.port == 3389, "an untouched port follows the protocol")
        #expect(saved.hostID == machine.id)
        #expect(saved.protocol == .rdp)
    }

    /// The port default is the draft's; clearing the RDP-only fields is the *record's*
    /// (`DesktopConnection.validated()`). Both are pinned here because both are user-visible, and
    /// because a draft that stopped hiding those fields would otherwise silently rely on the
    /// record to save it.
    @Test("Screen Sharing moves the port to 5900, and the record keeps itself canonical")
    func vncTakesItsOwnDefaults() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let endpoint = EndpointID(rawValue: UUID())

        let draft = try #require(capability.makeSetupDraft() as? DesktopServiceDraft)
        draft.desktopProtocol = .vnc
        draft.protocolDidChange()
        draft.domain = "CORP"
        draft.audioEnabled = true
        draft.password = "hunter2"
        // No user name: a VNC server may be password-only, so it must not block the save.
        #expect(draft.validate(address: "198.51.100.9").isEmpty)
        #expect(!draft.showsRDPOnlyFields)
        try await draft.commit(endpointID: endpoint, host: try host(), address: "198.51.100.9")

        let saved = try #require(runtime.connection(for: endpoint))
        #expect(saved.port == 5900, "the protocol moves an untouched port")
        #expect(saved.protocol == .vnc)
        #expect(saved.domain.isEmpty, "a Windows domain has no meaning in RFB — the record clears it")
        #expect(!saved.audioEnabled, "and RFB has no audio channel")
        #expect(saved.authentication == .networkLevel)
        #expect(saved.certificateSHA256 == nil, "there is no TLS certificate to pin")
    }

    @Test("A Screen Sharing user name too long for the credential block is caught in the sheet")
    func vncUserNameLengthIsReportedBeforeCommit() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = try #require(GlassDesktopCapability(runtime: runtime).makeSetupDraft() as? DesktopServiceDraft)
        draft.desktopProtocol = .vnc
        draft.password = "hunter2"
        draft.username = String(repeating: "a", count: 64)
        // The record throws on this (ARD packs the account into a fixed block); the sheet should
        // say so on the field rather than failing the save with a thrown error.
        #expect(draft.validate(address: "198.51.100.9").contains { $0.field == "username" })
        draft.username = String(repeating: "a", count: 63)
        #expect(draft.validate(address: "198.51.100.9").isEmpty)
    }

    @Test("The sheet's Screen Sharing note follows the user name: a Mac account is encrypted, a password alone is not")
    func vncPrivacyNoteFollowsTheUserName() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = try #require(GlassDesktopCapability(runtime: runtime).makeSetupDraft() as? DesktopServiceDraft)
        draft.username = "alpha"
        #expect(!draft.vncSignsInWithMacAccount, "RDP has no such note")
        draft.desktopProtocol = .vnc
        #expect(draft.vncSignsInWithMacAccount)
        draft.username = "  "
        #expect(!draft.vncSignsInWithMacAccount, "blank once trimmed, as the record saves it")
    }

    @Test("A deliberate port survives a protocol change")
    func aTypedPortIsNotOverwritten() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = try #require(GlassDesktopCapability(runtime: runtime).makeSetupDraft() as? DesktopServiceDraft)
        draft.portText = "13389"
        draft.markTouched(.port)
        draft.desktopProtocol = .vnc
        draft.protocolDidChange()
        #expect(draft.resolvedPort == 13389)
    }

    @Test("Credentials follow D18, not glassDT's device-only default")
    func mobilityFollowsTheProjectDecision() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = try #require(GlassDesktopCapability(runtime: runtime).makeSetupDraft() as? DesktopServiceDraft)
        #expect(draft.mobility == .iCloudKeychain)
    }

    @Test("D25: removing the service deletes what this capability stored")
    func removeServiceDeletesTheRecord() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let machine = try host()
        let endpoint = EndpointID(rawValue: UUID())
        let draft = try #require(capability.makeSetupDraft() as? DesktopServiceDraft)
        draft.username = "casey"
        draft.password = "correct-horse"
        try await draft.commit(endpointID: endpoint, host: machine, address: "198.51.100.9")
        #expect(runtime.connection(for: endpoint) != nil)

        let link = HostServiceLink(endpointID: endpoint, kind: .rdp, displayName: "foxtrot", credentialID: nil)
        try await capability.removeService(link, host: machine)
        #expect(runtime.connection(for: endpoint) == nil, "the record goes with the host")
    }

    @Test("A link with no saved desktop behind it reports a failure rather than opening nothing")
    func openWithoutAConfigurationReportsIt() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        await runtime.loadIfNeeded()
        let link = HostServiceLink(endpointID: EndpointID(rawValue: UUID()), kind: .rdp,
                                   displayName: "ghost", credentialID: nil)
        var outcome: GlassCapabilityOutcome?
        capability.open(service: link, host: try host()) { outcome = $0 }
        guard case .failed = outcome else {
            Issue.record("expected a failure outcome, got \(String(describing: outcome))")
            return
        }
    }

    @Test("Connect does not report success merely because a window was asked for")
    func openHoldsTheReportUntilTheSessionSaysSomething() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let machine = try host()
        let endpoint = EndpointID(rawValue: UUID())
        let draft = try #require(capability.makeSetupDraft() as? DesktopServiceDraft)
        draft.username = "casey"
        draft.password = "correct-horse"
        try await draft.commit(endpointID: endpoint, host: machine, address: "198.51.100.9")

        var outcome: GlassCapabilityOutcome?
        let link = HostServiceLink(endpointID: endpoint, kind: .rdp, displayName: "foxtrot", credentialID: nil)
        capability.open(service: link, host: machine) { outcome = $0 }
        // The request is queued and the report held: nothing has connected yet.
        #expect(outcome == nil, "opening a window is not connecting")

        let requests = runtime.takeRequests()
        #expect(requests.count == 1)
        guard case let .connect(id, report) = requests[0] else {
            Issue.record("expected a connect request")
            return
        }
        #expect(id == endpoint)
        runtime.holdReport(report, for: id)

        // Only once the session reaches a real state is the outcome delivered, and exactly once.
        runtime.reportOutcome(.connected, for: endpoint)
        #expect(outcome == .connected)
        outcome = nil
        runtime.reportOutcome(.connected, for: endpoint)
        #expect(outcome == nil, "a held report is delivered once")
    }

    @Test("Editing a machine's address moves its desktops with it")
    func addressChangeFollowsToTheRecords() async throws {
        let (runtime, root) = try await makeRuntime()
        defer { try? FileManager.default.removeItem(at: root) }
        let capability = GlassDesktopCapability(runtime: runtime)
        let endpoint = EndpointID(rawValue: UUID())
        let draft = try #require(capability.makeSetupDraft() as? DesktopServiceDraft)
        draft.username = "casey"
        draft.password = "correct-horse"
        var machine = try host()
        try await draft.commit(endpointID: endpoint, host: machine, address: "198.51.100.9")

        machine.services = [HostServiceLink(endpointID: endpoint, kind: .rdp, displayName: "foxtrot", credentialID: nil)]
        capability.hostAddressDidChange(host: machine, address: "198.51.100.22")
        // The capability persists on a task of its own: until it lands, up to 30 s. A fixed 200 ms
        // stood for that (2026-10-24).
        for _ in 0..<3_000 where runtime.connection(for: endpoint)?.host != "198.51.100.22" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(runtime.connection(for: endpoint)?.host == "198.51.100.22")
    }
}
