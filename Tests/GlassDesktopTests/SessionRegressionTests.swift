//
//  SessionRegressionTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/SessionRegressionTests.swift` on 2026-09-27.
//  The tests and their assertions are unchanged. What was adapted is the fixture only:
//  glassDT's `GlassDesktopCore` + `GlassDesktopUI` are one module here (`GlassDesktop`), and the
//  saved desktop no longer lives in glassDT's `connections.json` next to a separate
//  `HostCatalogStore` — `DesktopRepository` keeps it on its service link in the shell's catalog
//  (D26), so the fixture attaches the model and the repository to one in-memory
//  `GlassServiceStore`. `DesktopRepository.load()` is synchronous now, so the reads lost their
//  `await`. Host names use `.example`.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
import GlassConnectionKit
import GlassShell
import GlasSecretStore
@testable import GlassRDPTransport
@testable import GlassVNCTransport
@testable import GlassDesktop

private actor SessionGate {
    private var entered = false
    private var opened = false
    private var entrance: [CheckedContinuation<Void, Never>] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        entrance.forEach { $0.resume() }; entrance.removeAll()
        if !opened { await withCheckedContinuation { waiting.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entrance.append($0) } }
    }
    func open() {
        opened = true
        waiting.forEach { $0.resume() }; waiting.removeAll()
    }
}

@MainActor
private final class SessionFixture {
    let directory: URL
    let store: GlassInMemoryServiceStore
    let repository: DesktopRepository
    let app: DesktopAppModel
    var connection: DesktopConnection
    var connected: [any GlassDesktopTransport] = []
    var configurations: [GlassRDPConfiguration] = []
    var vncConfigurations: [GlassVNCConfiguration] = []
    var sizes: [DesktopSize] = []
    var scaleFactors: [Int] = []
    init(credentialAccess: DesktopCredentialAccess? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("glassdt-session-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // D26: one catalog-backed store, read by the repository and the model alike.
        store = GlassInMemoryServiceStore(defaultKind: .rdp)
        repository = DesktopRepository(store: store)
        var value = DesktopConnection(name: "Server", host: "server.example", username: "alice")
        value.clipboardEnabled = true
        connection = value
        let access = credentialAccess ?? DesktopCredentialAccess(retrieve: { _, _, _ in
            RDPCredential(username: "alice", password: "test secret")
        }, save: { _, _, _ in }, delete: { _, _ in }, availability: { _, _ in .available }, migrate: { _, _, _ in })
        app = DesktopAppModel(storageDirectory: directory, credentialAccess: access,
                              notices: DesktopNotices(defaults: UserDefaults(suiteName: directory.lastPathComponent)!,
                                  delivery: .init(authorize: { false }, failure: { _ in false })))
    }
    func prepare() async throws {
        await app.attach(store: store)
        _ = try await repository.save(connection)
        await app.load()
        connection = try #require(app.connections.first)
    }
    func clean() {
        UserDefaults.standard.removePersistentDomain(forName: directory.lastPathComponent)
        try? FileManager.default.removeItem(at: directory)
    }
    var operations: DesktopSessionOperations {
        var value = DesktopSessionOperations()
        value.connect = { target, configuration in
            self.connected.append(target)
            if let rdp = configuration.rdp { self.configurations.append(rdp) }
            if let vnc = configuration.vnc { self.vncConfigurations.append(vnc) }
        }
        value.disconnect = { _ in }
        value.resize = { _, size, scale in self.sizes.append(size); self.scaleFactors.append(scale) }
        return value
    }
    func model(_ operations: DesktopSessionOperations? = nil) -> DesktopSessionModel {
        DesktopSessionModel(connection: connection, app: app, operations: operations ?? self.operations,
                            wallpaperRoot: directory.appendingPathComponent("wallpapers"))
    }
    func ready(_ model: DesktopSessionModel) async throws {
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        await model.receive(.state(.connected), attempt: model.attemptID, connection: connection)
        await model.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: UInt64(DesktopSize.maximumPixels))),
                            attempt: model.attemptID, connection: connection)
    }
    func challenge(_ model: DesktopSessionModel) async throws -> DesktopTrustRequest {
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        let certificate = GlassRDPCertificate(host: connection.host, port: connection.port,
            sha256: String(repeating: "a", count: 64), systemTrusted: false, isAccepted: false)
        await model.receive(.certificate(certificate), attempt: model.attemptID, connection: connection)
        await model.receive(.state(.failed("Certificate verification failed")), attempt: model.attemptID, connection: connection)
        return try #require(model.trustRequest)
    }
}

@Suite("Remote session lifecycle")
@MainActor
struct SessionRegressionTests {
    @Test func closingDuringDisconnectCannotStartAnOldAttempt() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.disconnect = { _ in await gate.wait() }
        let model = fixture.model(operations)
        let starting = Task { try await model.connect(username: "alice", domain: nil, password: "test secret") }
        await gate.waitUntilEntered()
        let cleanup = model.close()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await starting.value }
        await cleanup.value
        #expect(fixture.connected.isEmpty)
        #expect(model.state == .disconnected)
        #expect(!model.needsCredentials)
    }

    @Test func attemptsOwnDistinctTransportsAndRejectOldEvents() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.connect = { target, _ in
            fixture.connected.append(target)
            if fixture.connected.count == 1 { await gate.wait() }
        }
        let model = fixture.model(operations)
        let first = Task { try await model.connect(username: "alice", domain: nil, password: "test secret") }
        await gate.waitUntilEntered()
        let oldID = model.attemptID
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        let currentID = model.attemptID
        await model.receive(.state(.connected), attempt: currentID, connection: fixture.connection)
        await model.receive(.state(.failed("old failure")), attempt: oldID, connection: fixture.connection)
        await model.receive(.clipboard("old clipboard"), attempt: oldID, connection: fixture.connection)
        await gate.open()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fixture.connected.count == 2)
        #expect(fixture.connected[0] !== fixture.connected[1])
        #expect(model.transport === fixture.connected[1])
        #expect(model.state == .connected)
        #expect(model.remoteClipboard == nil)
        #expect(model.errorMessage == nil)
        await model.close().value
    }

    @Test func terminalStateClearsFrameCapabilitiesAndClipboard() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        let id = model.attemptID
        let frame = try GlassRDPFrame(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]), sequence: 1)
        model.receive(frame, attempt: id)
        await model.receive(.clipboard("current clipboard"), attempt: id, connection: fixture.connection)
        #expect(model.frame != nil && model.capabilities != nil && model.remoteClipboard != nil)
        await model.receive(.state(.failed("network lost")), attempt: id, connection: fixture.connection)
        model.receive(frame, attempt: id)
        await model.receive(.clipboard("late clipboard"), attempt: id, connection: fixture.connection)
        #expect(model.frame == nil)
        #expect(model.capabilities == nil)
        #expect(model.remoteClipboard == nil)
        #expect(model.errorMessage == "network lost")
        await model.close().value
    }

    @Test func inputReadyThenFailedHandoffDoesNotRecordSuccessfulHistory() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        #expect(model.historyTask == nil)
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        await model.receive(.state(.failed("Redirected authentication failed")), attempt: model.attemptID, connection: fixture.connection)
        #expect(model.historyTask == nil)
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        await model.close().value
    }

    @Test(arguments: [false, true])
    func successfulHistoryRequiresFrameAndReadyInEitherOrderAndRecordsOnce(_ frameFirst: Bool) async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        var calls = 0
        var operations = fixture.operations
        let record = operations.recordConnection
        operations.recordConnection = { app, snapshot, date in
            calls += 1
            await record(app, snapshot, date)
        }
        let model = fixture.model(operations)
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        let id = model.attemptID
        let frame = try GlassRDPFrame(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]), sequence: 1)
        if frameFirst { model.receive(frame, attempt: id) }
        else { await model.receive(.state(.connected), attempt: id, connection: fixture.connection) }
        #expect(model.historyTask == nil)
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        if frameFirst { await model.receive(.state(.connected), attempt: id, connection: fixture.connection) }
        else { model.receive(frame, attempt: id) }
        let pending = try #require(model.historyTask)
        await pending.value
        let firstDate = try #require(try fixture.repository.load().first?.lastConnectedAt)
        model.receive(frame, attempt: id)
        await model.receive(.state(.connected), attempt: id, connection: fixture.connection)
        await model.historyTask?.value
        #expect(calls == 1)
        #expect(try fixture.repository.load().first?.lastConnectedAt == firstDate)
        await model.close().value
    }

    @Test func staleAndFailedAttemptFramesNeverRecordHistory() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        let old = model.attemptID
        try await model.connect(username: "alice", domain: nil, password: "test secret")
        let current = model.attemptID
        await model.receive(.state(.connected), attempt: current, connection: fixture.connection)
        let frame = try GlassRDPFrame(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]), sequence: 1)
        model.receive(frame, attempt: old)
        #expect(model.frame == nil && model.historyTask == nil)
        await model.receive(.state(.failed("Handoff failed")), attempt: current, connection: fixture.connection)
        model.receive(frame, attempt: current)
        await model.receive(.state(.connected), attempt: current, connection: fixture.connection)
        model.receive(frame, attempt: current)
        #expect(model.frame == nil && model.historyTask == nil)
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        await model.close().value
    }

    @Test func canceledQueuedHistoryCannotWriteAfterDisconnect() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        let record = operations.recordConnection
        operations.recordConnection = { app, snapshot, date in
            await gate.wait()
            await record(app, snapshot, date)
        }
        let model = fixture.model(operations)
        try await fixture.ready(model)
        let frame = try GlassRDPFrame(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]), sequence: 1)
        model.receive(frame, attempt: model.attemptID)
        let pending = try #require(model.historyTask)
        await gate.waitUntilEntered()
        await model.disconnect()
        await gate.open()
        await pending.value
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        #expect(fixture.app.errorMessage == nil)
        await model.close().value
    }

    @Test func queuedHistoryDoesNotApplyToEditedEndpoint() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        let record = operations.recordConnection
        operations.recordConnection = { app, snapshot, date in
            await gate.wait()
            await record(app, snapshot, date)
        }
        let model = fixture.model(operations)
        try await fixture.ready(model)
        let frame = try GlassRDPFrame(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]), sequence: 1)
        model.receive(frame, attempt: model.attemptID)
        let pending = try #require(model.historyTask)
        await gate.waitUntilEntered()
        var edited = try #require(try fixture.repository.load().first)
        let old = edited
        edited.host = "different.example"
        _ = try await fixture.repository.save(edited, replacing: old)
        await gate.open()
        await pending.value
        #expect(try fixture.repository.load().first?.lastConnectedAt == nil)
        #expect(fixture.app.errorMessage == nil)
        await model.close().value
    }

    @Test func delayedHistoryCannotRegressANewerSuccessfulSession() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let newer = Date(timeIntervalSince1970: 200)
        _ = try await fixture.repository.recordConnection(fixture.connection.id, at: newer, expectedConnection: fixture.connection)
        _ = try await fixture.repository.recordConnection(fixture.connection.id, at: Date(timeIntervalSince1970: 100), expectedConnection: fixture.connection)
        #expect(try fixture.repository.load().first?.lastConnectedAt == newer)
    }

    @Test(arguments: [false, true])
    func certificateApprovalReusesUnsavedCredentialsWithoutReadingOldKeychain(_ hasOldCredential: Bool) async throws {
        var reads = 0
        var saves = 0
        let access = DesktopCredentialAccess(retrieve: { _, _, _ in
            reads += 1
            if hasOldCredential { return RDPCredential(username: "alice", password: "old saved password") }
            throw SecretStoreError.notFound
        }, save: { _, _, _ in saves += 1 }, delete: { _, _ in },
           availability: { _, _ in hasOldCredential ? .available : .missing }, migrate: { _, _, _ in })
        let fixture = try SessionFixture(credentialAccess: access)
        defer { fixture.clean() }
        fixture.connection.domain = "SESSION-DOMAIN"
        try await fixture.prepare()
        let model = fixture.model()
        await model.submitCredentials(username: "temporary-user", password: "one-use password", remember: false)
        let certificate = GlassRDPCertificate(host: fixture.connection.host, port: fixture.connection.port,
            sha256: String(repeating: "a", count: 64), systemTrusted: false, isAccepted: false)
        await model.receive(.certificate(certificate), attempt: model.attemptID, connection: fixture.connection)
        await model.receive(.state(.failed("Certificate verification failed")), attempt: model.attemptID, connection: fixture.connection)
        let request = try #require(model.trustRequest)
        model.dismissTrustRequest(request)
        await model.approveCertificate(request)
        #expect(fixture.configurations.count == 2)
        #expect(fixture.configurations.allSatisfy {
            $0.username == "temporary-user" && $0.domain == "SESSION-DOMAIN" && $0.password == "one-use password"
        })
        #expect(fixture.configurations.last?.approvedCertificateSHA256 == certificate.sha256)
        #expect(reads == 0 && saves == 0)
        #expect(!model.needsCredentials)
        #expect(try fixture.repository.load().first?.username == "alice")
        await model.close().value
    }

    @Test func lateFailureDuringTrustApprovalCannotDiscardEnteredCredentials() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        let approve = operations.approve
        operations.approve = { app, fingerprint, id, snapshot in
            await gate.wait()
            return try await approve(app, fingerprint, id, snapshot)
        }
        let model = fixture.model(operations)
        await model.submitCredentials(username: "temporary-user", password: "one-use password", remember: false)
        let certificate = GlassRDPCertificate(host: fixture.connection.host, port: fixture.connection.port,
            sha256: String(repeating: "a", count: 64), systemTrusted: false, isAccepted: false)
        let attempt = model.attemptID
        await model.receive(.certificate(certificate), attempt: attempt, connection: fixture.connection)
        let request = try #require(model.trustRequest)
        let approval = Task { await model.approveCertificate(request) }
        await gate.waitUntilEntered()
        await model.receive(.state(.failed("Certificate verification failed")), attempt: attempt, connection: fixture.connection)
        await gate.open()
        await approval.value
        #expect(fixture.configurations.count == 2)
        #expect(fixture.configurations.last?.username == "temporary-user")
        #expect(fixture.configurations.last?.password == "one-use password")
        #expect(try fixture.repository.load().first?.certificateSHA256 == certificate.sha256)
        await model.close().value
    }

    @Test func endpointChangedDuringTrustReviewCannotReceiveTransientCredentials() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let request = try await fixture.challenge(model)
        var edited = try #require(try fixture.repository.load().first)
        let old = edited
        edited.host = "different.example"
        _ = try await fixture.repository.save(edited, replacing: old)
        await model.approveCertificate(request)
        #expect(fixture.configurations.count == 1)
        #expect(model.errorMessage != nil)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        await model.close().value
    }

    @Test func credentialSheetStaysVisibleDuringSaveAndAfterFailure() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.save = { _, _, _ in
            await gate.wait()
            throw SecretStoreError.unableToSave
        }
        let model = fixture.model(operations)
        await model.requestCredentials()
        let submission = Task { await model.submitCredentials(username: "alice", password: "test secret", remember: true) }
        await gate.waitUntilEntered()
        #expect(model.needsCredentials && model.isSubmittingCredentials)
        #expect(fixture.configurations.isEmpty)
        await gate.open()
        await submission.value
        #expect(model.needsCredentials && !model.isSubmittingCredentials)
        #expect(model.errorMessage != nil)
        #expect(fixture.configurations.isEmpty)
        await model.close().value
    }

    @Test func credentialSheetCancelWhileSavingCannotConnectAfterSaveCompletes() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.save = { _, _, _ in await gate.wait() }
        let model = fixture.model(operations)
        await model.requestCredentials()
        let submission = Task { await model.submitCredentials(username: "alice", password: "test secret", remember: true) }
        await gate.waitUntilEntered()
        let oldAttempt = model.attemptID
        await model.cancelCredentialEntry().value
        await gate.open()
        await submission.value
        #expect(model.attemptID != oldAttempt)
        #expect(!model.needsCredentials && !model.isSubmittingCredentials)
        #expect(fixture.configurations.isEmpty)
        #expect(model.state == .disconnected)
        await model.close().value
    }

    @Test func certificatePresentationWaitsForActualCredentialSheetDismissal() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let request = try await fixture.challenge(model)
        var presenter = DesktopSessionAlertPresentation()
        presenter.credentialSheetRequested()
        presenter.presentCurrent(trust: request, displayError: nil, credentialsRequested: true)
        #expect(presenter.active == nil)
        // The Boolean becoming false only begins native dismissal.
        presenter.presentCurrent(trust: request, displayError: nil, credentialsRequested: false)
        #expect(presenter.active == nil)
        presenter.credentialSheetDidDismiss()
        presenter.presentCurrent(trust: request, displayError: nil, credentialsRequested: false)
        #expect(presenter.active == .trust(request))
        await model.close().value
    }

    @Test func cancelledChallengeDuringSheetDismissalNeverPresents() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let request = try await fixture.challenge(model)
        var presenter = DesktopSessionAlertPresentation()
        presenter.credentialSheetRequested()
        presenter.presentCurrent(trust: request, displayError: nil)
        model.cancelTrustRequest(request)
        presenter.credentialSheetDidDismiss()
        presenter.presentCurrent(trust: model.trustRequest, displayError: nil)
        #expect(presenter.active == nil)
        await model.approveCertificate(request)
        #expect(fixture.configurations.count == 1)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        await model.close().value
    }

    @Test func displayAlertKeepsSnapshotUntilPendingTrustCanPresent() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        var presenter = DesktopSessionAlertPresentation()
        presenter.presentCurrent(trust: nil, displayError: "Display unavailable")
        let request = try await fixture.challenge(model)
        presenter.presentCurrent(trust: request, displayError: "Display unavailable")
        #expect(presenter.active == .display("Display unavailable"))
        #expect(presenter.dismiss() == .display("Display unavailable"))
        #expect(model.trustRequest == request)
        presenter.presentCurrent(trust: model.trustRequest, displayError: nil)
        #expect(presenter.active == .trust(request))
        await model.close().value
    }

    @Test func staleAlertDismissalAndCancelCannotClearNewerChallenge() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let old = try await fixture.challenge(model)
        var presenter = DesktopSessionAlertPresentation()
        presenter.presentCurrent(trust: old, displayError: nil)
        let current = try await fixture.challenge(model)
        presenter.presentCurrent(trust: current, displayError: nil)
        #expect(presenter.dismiss() == .trust(old))
        model.dismissTrustRequest(old)
        model.cancelTrustRequest(old)
        #expect(model.trustRequest == current)
        await model.approveCertificate(old)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        presenter.presentCurrent(trust: model.trustRequest, displayError: nil)
        #expect(presenter.active == .trust(current))
        model.cancelTrustRequest(current)
        await model.approveCertificate(current)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        await model.close().value
    }

    @Test func dismissedPendingChallengeIsNeverReintroducedByAlertQueue() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        var presenter = DesktopSessionAlertPresentation()
        presenter.presentCurrent(trust: nil, displayError: "Display unavailable")
        let request = try await fixture.challenge(model)
        presenter.presentCurrent(trust: request, displayError: nil)
        model.cancelTrustRequest(request)
        presenter.dismiss()
        presenter.presentCurrent(trust: model.trustRequest, displayError: nil)
        #expect(presenter.active == nil)
        await model.close().value
    }

    @Test func dismissedAlertStillApprovesItsCapturedSnapshot() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let request = try await fixture.challenge(model)
        model.dismissTrustRequest()
        #expect(model.trustRequest == nil)
        await model.approveCertificate(request)
        #expect(try fixture.repository.load().first?.certificateSHA256 == request.certificate.sha256)
        #expect(model.attemptID != request.attemptID)
        #expect(fixture.connected.count == 2)
        await model.close().value
    }

    @Test func cancelledTrustRequestCannotApprove() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        let request = try await fixture.challenge(model)
        model.cancelTrustRequest()
        await model.approveCertificate(request)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        #expect(fixture.connected.count == 1)
        await model.close().value
    }

    @Test func closingDuringApprovalCannotReconnectOrMutateSessionSnapshot() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.approve = { _, fingerprint, _, snapshot in
            await gate.wait()
            var result = snapshot
            result.certificateSHA256 = fingerprint
            return result
        }
        let model = fixture.model(operations)
        let request = try await fixture.challenge(model)
        let approval = Task { await model.approveCertificate(request) }
        await gate.waitUntilEntered()
        await model.close().value
        await gate.open()
        await approval.value
        #expect(fixture.connected.count == 1)
        #expect(model.connection.certificateSHA256 == nil)
        #expect(model.state == .disconnected)
    }

    @Test func closingDuringCredentialSaveCannotConnect() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.save = { _, _, _ in await gate.wait() }
        let model = fixture.model(operations)
        let submission = Task { await model.submitCredentials(username: "alice", password: "test secret", remember: true) }
        await gate.waitUntilEntered()
        await model.close().value
        await gate.open()
        await submission.value
        #expect(fixture.connected.isEmpty)
        #expect(!model.needsCredentials && !model.isSubmittingCredentials)
        #expect(model.state == .disconnected)
    }

    @Test func lateCredentialPromptCannotReopenClosedWindowState() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.disconnect = { _ in await gate.wait() }
        let model = fixture.model(operations)
        let prompt = Task { await model.requestCredentials() }
        await gate.waitUntilEntered()
        let cleanup = model.close()
        await gate.open()
        await prompt.value
        await cleanup.value
        #expect(!model.needsCredentials)
    }

    @Test func manualResolutionCancelsPendingWindowResize() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.delay = { _ in await gate.wait() }
        let model = fixture.model(operations)
        try await fixture.ready(model)
        model.resize(width: 800, height: 600)
        let pending = try #require(model.resizeTask)
        await gate.waitUntilEntered()
        let chosen = DesktopSize(width: 1280, height: 800)
        await model.setSourceSize(chosen)
        await gate.open()
        await pending.value
        #expect(fixture.sizes == [chosen])
        #expect(!model.matchWindow)
        await model.close().value
    }

    @Test func togglingMatchWindowOffCancelsPendingAutomaticResize() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.delay = { _ in await gate.wait() }
        let model = fixture.model(operations)
        try await fixture.ready(model)
        model.resize(width: 800, height: 600)
        let pending = try #require(model.resizeTask)
        await gate.waitUntilEntered()
        model.matchWindow = false
        await gate.open()
        await pending.value
        #expect(fixture.sizes.isEmpty)
        await model.close().value
    }

    @Test func returningToAcknowledgedSizeCancelsAnIntermediateRequest() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.delay = { _ in await gate.wait() }
        let model = fixture.model(operations)
        try await fixture.ready(model)
        let acknowledged = DesktopSize(width: 800, height: 600)
        await model.setSourceSize(acknowledged)
        model.matchWindow = true
        model.resize(width: 1000, height: 700)
        let pending = try #require(model.resizeTask)
        await gate.waitUntilEntered()
        model.resize(width: 800, height: 600)
        await gate.open()
        await pending.value
        #expect(fixture.sizes == [acknowledged])
        await model.close().value
    }

    @Test func queuedActionsAfterCloseStayClosedUntilViewStartsAgain() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        await model.close().value
        await model.reconnect()
        await model.requestCredentials()
        await model.submitCredentials(username: "alice", password: "test secret", remember: false)
        #expect(fixture.connected.isEmpty)
        #expect(!model.needsCredentials)
        await model.start()
        #expect(fixture.connected.count == 1)
        await model.close().value
    }

    @Test func taskCancellationDuringStartDoesNotConnect() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let gate = SessionGate()
        var operations = fixture.operations
        operations.disconnect = { _ in await gate.wait() }
        let model = fixture.model(operations)
        let starting = Task { try await model.connect(username: "alice", domain: nil, password: "test secret") }
        await gate.waitUntilEntered()
        starting.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(fixture.connected.isEmpty)
        #expect(model.state == .disconnected)
        await model.close().value
    }

    @Test func wallpaperReplacementValidatesBeforeDiscardingPreviousImage() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let valid = fixture.directory.appendingPathComponent("valid.png")
        try makeWallpaper(at: valid)
        let invalid = fixture.directory.appendingPathComponent("invalid.png")
        try Data("invalid image".utf8).write(to: invalid)
        let model = fixture.model()
        await model.importWallpaper(from: valid)
        let original = try #require(model.wallpaperURL)
        #expect(FileManager.default.fileExists(atPath: original.path))
        await model.importWallpaper(from: invalid)
        #expect(model.wallpaperURL == original)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(model.errorMessage != nil)
        await model.importWallpaper(from: valid)
        let replacement = try #require(model.wallpaperURL)
        #expect(replacement != original)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        await model.close().value
        #expect(model.wallpaperURL == nil)
        #expect(!FileManager.default.fileExists(atPath: replacement.path))
        #expect(FileManager.default.fileExists(atPath: valid.path))
    }

    private func makeWallpaper(at url: URL) throws {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Test func edgeResizeUsesInverseAspectFitScale() {
    #expect(DesktopEdgeGeometry.density(source: .standard, viewport: CGSize(width: 1000, height: 1000)) == 1.92)
    #expect(DesktopEdgeGeometry.density(source: DesktopSize(width: 1080, height: 1920), viewport: CGSize(width: 1000, height: 500)) == 3.84)
    #expect(DesktopEdgeGeometry.density(source: .standard, viewport: .zero) == 1)
}

@MainActor @Test func normalSessionEndRequestsNativePresentationClosure() async throws {
    let fixture = try SessionFixture()
    defer { fixture.clean() }
    try await fixture.prepare()
    let model = fixture.model()
    try await fixture.ready(model)
    #expect(!model.shouldClosePresentation)
    await model.receive(.state(.disconnected), attempt: model.attemptID, connection: fixture.connection)
    #expect(model.shouldClosePresentation)
    #expect(model.failurePresentation == nil)
    await model.close().value
}

@MainActor @Test func failureOffersRecoveryAndOldDisconnectCannotCloseNewAttempt() async throws {
    let fixture = try SessionFixture()
    defer { fixture.clean() }
    try await fixture.prepare()
    let model = fixture.model()
    try await fixture.ready(model)
    model.receive(try GlassRDPFrame(width: 2, height: 1, bytesPerRow: 8, pixels: Data(count: 8), sequence: 1), attempt: model.attemptID)
    await model.historyTask?.value
    let oldID = model.attemptID
    await model.receive(.state(.failed("protocol detail")), attempt: oldID, connection: fixture.connection)
    #expect(!model.shouldClosePresentation)
    #expect(model.failurePresentation?.title == "Connection Lost")
    #expect(model.failurePresentation?.details == "protocol detail")
    #expect(model.failurePresentation?.message.contains("protocol detail") == false)
    await model.reconnect()
    await model.receive(.state(.disconnected), attempt: oldID, connection: fixture.connection)
    #expect(!model.shouldClosePresentation)
    #expect(model.failurePresentation == nil)
    await model.close().value
}

@MainActor @Test func explicitDisconnectClosesAndCleanupRunsOnce() async throws {
    let fixture = try SessionFixture()
    defer { fixture.clean() }
    try await fixture.prepare()
    var disconnects = 0
    var operations = fixture.operations
    operations.disconnect = { _ in disconnects += 1 }
    let model = fixture.model(operations)
    try await fixture.ready(model)
    let before = disconnects
    await model.disconnect()
    await model.close().value
    #expect(model.shouldClosePresentation)
    #expect(disconnects == before + 1)
}

@Suite("VNC session selection")
struct VNCSessionSelectionTests {
    @Test @MainActor func vncConnectionUsesVNCTransportAndPasswordOnlyAccount() async throws {
        let fixture = try SessionFixture(credentialAccess: DesktopCredentialAccess(retrieve: { _, _, _ in
            RDPCredential(username: DesktopConnection.passwordOnlyAccount, password: "vnc secret")
        }, save: { _, _, _ in }, delete: { _, _ in }, availability: { _, _ in .available }, migrate: { _, _, _ in }))
        defer { fixture.clean() }
        fixture.connection = DesktopConnection(name: "Mac", host: "mac.example", port: 5900, protocol: .vnc)
        fixture.connection.clipboardEnabled = true
        try await fixture.prepare()
        let model = fixture.model()
        await model.start()
        #expect(model.transport is GlassVNCSession)
        #expect(fixture.connected.count == 1)
        #expect(fixture.configurations.isEmpty)
        #expect(fixture.vncConfigurations == [GlassVNCConfiguration(host: "mac.example", port: 5900, username: "", password: "vnc secret", clipboardEnabled: true)])
        model.close()
    }

    @Test @MainActor func vncCredentialsRequirePasswordButNotUsername() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        fixture.connection = DesktopConnection(name: "Mac", host: "mac.example", port: 5900, protocol: .vnc)
        try await fixture.prepare()
        let model = fixture.model()
        await model.submitCredentials(username: "", password: "", remember: false)
        #expect(fixture.vncConfigurations.isEmpty)
        #expect(model.needsCredentials)
        await model.submitCredentials(username: " alice ", password: "pw", remember: false)
        #expect(fixture.vncConfigurations.last?.username == "alice")
        #expect(fixture.vncConfigurations.last?.password == "pw")
        model.close()
    }

    @Test @MainActor func rdpConnectionKeepsRDPTransport() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        #expect(model.transport is GlassRDPSession)
        #expect(fixture.vncConfigurations.isEmpty)
        model.close()
    }
}

@Suite("Initial desktop size")
@MainActor
struct InitialDesktopSizeTests {
    /// With Match Window Size on, the first connection asks for the window's size. Connecting at the
    /// saved resolution instead left the desktop letterboxed until a resize round trip completed.
    @Test func matchWindowSizeAppliesToTheFirstConnection() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        fixture.connection.desktop = DesktopSize(width: 1920, height: 1080)
        try await fixture.prepare()
        let model = fixture.model()
        #expect(model.matchWindow)
        model.resize(width: 1280, height: 800)
        try await fixture.ready(model)
        #expect(fixture.configurations.last?.width == 1280)
        #expect(fixture.configurations.last?.height == 800)
        model.close()
    }

    @Test func savedResolutionIsUsedWhenMatchWindowSizeIsOff() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        fixture.connection.desktop = DesktopSize(width: 1920, height: 1080)
        try await fixture.prepare()
        let model = fixture.model()
        model.matchWindow = false
        model.resize(width: 1280, height: 800)
        try await fixture.ready(model)
        #expect(fixture.configurations.last?.width == 1920)
        #expect(fixture.configurations.last?.height == 1080)
        model.close()
    }

    /// A window that never reported a size falls back to the saved resolution.
    @Test func unknownWindowSizeFallsBackToTheSavedResolution() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        fixture.connection.desktop = DesktopSize(width: 2560, height: 1440)
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        #expect(fixture.configurations.last?.width == 2560)
        #expect(fixture.configurations.last?.height == 1440)
        model.close()
    }
}

@Suite("Remote displays")
@MainActor
struct RemoteScreenTests {
    private func screens() -> [GlassRemoteScreen] {
        [GlassRemoteScreen(id: 1, x: 0, y: 0, width: 2000, height: 1200, isPrimary: true),
         GlassRemoteScreen(id: 2, x: 2000, y: 0, width: 1000, height: 600, isPrimary: false)]
    }

    @Test func selectingADisplayCropsToItAndInvalidSelectionsFallBack() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        let id = model.attemptID
        model.receive(try GlassRDPFrame(width: 3000, height: 1600, bytesPerRow: 3000 * 4,
                                        pixels: Data(count: 3000 * 1600 * 4), sequence: 1), attempt: id)
        await model.receive(.screens(screens()), attempt: id, connection: fixture.connection)
        #expect(model.screens.count == 2)
        #expect(model.visibleRegion == .whole(width: 3000, height: 1600))

        model.selectedScreenID = 2
        #expect(model.visibleRegion == DesktopRegion(origin: .init(x: 2000, y: 0),
                                                     size: DesktopSize(width: 1000, height: 600)))
        // A display that disappears returns the window to the whole image.
        await model.receive(.screens([screens()[0]]), attempt: id, connection: fixture.connection)
        #expect(model.selectedScreenID == nil)
        #expect(model.visibleRegion == .whole(width: 3000, height: 1600))
        model.close()
    }

    @Test func screensClearOnDisconnect() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        let id = model.attemptID
        await model.receive(.screens(screens()), attempt: id, connection: fixture.connection)
        #expect(!model.screens.isEmpty)
        await model.receive(.state(.disconnected), attempt: id, connection: fixture.connection)
        #expect(model.screens.isEmpty)
        #expect(model.selectedScreenID == nil)
        model.close()
    }
}

@Suite("Source detail scale")
@MainActor
struct SourceScaleTests {
    @Test func retinaWindowsRequestMorePixelsAndCarryTheScaleFactor() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        model.resize(width: 1280, height: 800, displayScale: 2)
        try await fixture.ready(model)
        // The first connection already asks for the scaled size, so nothing is letterboxed.
        #expect(fixture.configurations.last?.width == 2560)
        #expect(fixture.configurations.last?.height == 1600)
        let id = model.attemptID
        await model.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: 16_777_216)),
                            attempt: id, connection: fixture.connection)
        model.resize(width: 1280, height: 800, displayScale: 2)
        await model.resizeTask?.value
        #expect(fixture.sizes.last == DesktopSize(width: 2560, height: 1600))
        #expect(fixture.scaleFactors.last == 200)
        model.close()
    }

    @Test func standardDetailKeepsTheWindowSizeAndNeutralScale() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        model.sourceScale = .standard
        model.resize(width: 1280, height: 800, displayScale: 2)
        try await fixture.ready(model)
        #expect(fixture.configurations.last?.width == 1280)
        let id = model.attemptID
        await model.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: 16_777_216)),
                            attempt: id, connection: fixture.connection)
        model.resize(width: 1280, height: 800, displayScale: 2)
        await model.resizeTask?.value
        #expect(fixture.sizes.last == DesktopSize(width: 1280, height: 800))
        #expect(fixture.scaleFactors.last == 100)
        model.close()
    }

    /// A scaled request the server cannot accept falls back to the window's own size.
    @Test func scaledRequestFallsBackWhenTheServerCannotAcceptIt() async throws {
        let fixture = try SessionFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let model = fixture.model()
        try await fixture.ready(model)
        let id = model.attemptID
        await model.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: 2_100_000)),
                            attempt: id, connection: fixture.connection)
        model.resize(width: 1280, height: 800, displayScale: 2)
        await model.resizeTask?.value
        #expect(fixture.sizes.last == DesktopSize(width: 1280, height: 800))
        model.close()
    }

    /// VNC hosts choose their own resolution, so no scaled request is ever made for them.
    @Test func vncSessionsNeverScaleTheRequest() async throws {
        let fixture = try SessionFixture(credentialAccess: DesktopCredentialAccess(retrieve: { _, _, _ in
            RDPCredential(username: DesktopConnection.passwordOnlyAccount, password: "pw")
        }, save: { _, _, _ in }, delete: { _, _ in }, availability: { _, _ in .available }, migrate: { _, _, _ in }))
        defer { fixture.clean() }
        fixture.connection = DesktopConnection(name: "Mac", host: "mac.example", port: 5900, protocol: .vnc)
        try await fixture.prepare()
        let model = fixture.model()
        model.resize(width: 1280, height: 800, displayScale: 2)
        try await fixture.ready(model)
        #expect(fixture.vncConfigurations.count == 1)
        model.resize(width: 1290, height: 800, displayScale: 2)
        await model.resizeTask?.value
        // The request follows the window in points, never the display's pixel density.
        #expect(fixture.sizes.last == DesktopSize(width: 1290, height: 800))
        #expect(fixture.scaleFactors.last == 100)
        model.close()
    }
}
