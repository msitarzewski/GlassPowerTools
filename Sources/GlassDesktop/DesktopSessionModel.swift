import Foundation
import CoreGraphics
import ImageIO
import Observation
import GlassConnectionKit
import GlasSecretStore
import GlassRDPTransport
import GlassVNCTransport
import RDPKit

public struct DesktopTrustRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let attemptID: UUID
    public let certificate: GlassRDPCertificate
    public let connection: DesktopConnection
}

/// Protocol-specific connection parameters built from a validated connection and its credential.
enum DesktopTransportConfiguration: Sendable, Equatable {
    case rdp(GlassRDPConfiguration)
    case vnc(GlassVNCConfiguration)

    var rdp: GlassRDPConfiguration? { if case .rdp(let value) = self { value } else { nil } }
    var vnc: GlassVNCConfiguration? { if case .vnc(let value) = self { value } else { nil } }
}

// `@retroactive` is gone: the transport now lives in this package, so the conformance is no
// longer being added to someone else's type from outside.
extension GlassRDPConfiguration: Equatable {
    public static func == (lhs: GlassRDPConfiguration, rhs: GlassRDPConfiguration) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port && lhs.username == rhs.username && lhs.domain == rhs.domain
            && lhs.password == rhs.password && lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.requiresNLA == rhs.requiresNLA && lhs.approvedCertificateSHA256 == rhs.approvedCertificateSHA256
            && lhs.clipboardEnabled == rhs.clipboardEnabled && lhs.audioEnabled == rhs.audioEnabled
    }
}

/// Async I/O boundaries; production uses the real transport and family stores.
@MainActor
struct DesktopSessionOperations {
    var connect: @MainActor (any GlassDesktopTransport, DesktopTransportConfiguration) async throws -> Void = { transport, configuration in
        switch (transport, configuration) {
        case (let session as GlassRDPSession, .rdp(let value)): try await session.connect(value)
        case (let session as GlassVNCSession, .vnc(let value)): try await session.connect(value)
        default: throw GlassRDPError.invalidConfiguration
        }
    }
    var disconnect: @MainActor (any GlassDesktopTransport) async -> Void = { await $0.disconnect() }
    var resize: @MainActor (any GlassDesktopTransport, DesktopSize, Int) async throws -> Void = {
        try await $0.resize(width: $1.width, height: $1.height, desktopScale: $2)
    }
    var delay: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var save: @MainActor (DesktopAppModel, DesktopConnection, String) async throws -> Void = { try await $0.save($1, password: $2) }
    var recordConnection: @MainActor (DesktopAppModel, DesktopConnection, Date) async -> Void = {
        await $0.recordConnected($1.id, expectedConnection: $1, at: $2)
    }
    var approve: @MainActor (DesktopAppModel, String, EndpointID, DesktopConnection) async throws -> DesktopConnection = {
        try await $0.approveCertificate($1, for: $2, expectedConnection: $3)
    }
}

@MainActor @Observable
public final class DesktopSessionModel {
    public private(set) var connection: DesktopConnection
    public private(set) var state = GlassRDPState.disconnected
    public private(set) var shouldClosePresentation = false
    private var hadDesktop = false
    private var closeTask: Task<Void, Never>?
    public private(set) var frame: GlassRDPFrame?
    public private(set) var capabilities: GlassRDPDisplayCapabilities?
    /// Displays inside the remote framebuffer, when the host publishes a layout. Fewer than two
    /// means there is nothing to choose between.
    public private(set) var screens: [GlassRemoteScreen] = []
    /// Nil shows the whole framebuffer. Otherwise the identifier of the single display on screen.
    public var selectedScreenID: UInt32? {
        didSet { if selectedScreenID != oldValue { updateCursorImage() } }
    }
    /// The server's latest copy, in every form it offered; the session view puts it on the local
    /// clipboard (D42a).
    public private(set) var remoteClipboard: GlassClipboardContent?
    public var presentation = PresentationSettings()
    public var matchWindow = true { didSet { if matchWindow != oldValue { cancelResize() } } }
    public var needsCredentials = false
    public var trustRequest: DesktopTrustRequest?
    public var errorMessage: String?
    public var rendererError: String?
    public private(set) var wallpaperURL: URL?
    public private(set) var isSubmittingCredentials = false
    public private(set) var isApprovingCertificate = false
    public private(set) var cursor = GlassRDPCursor.systemDefault
    public var pointerPosition: DesktopPoint? { didSet { updateCursorImage() } }
    public private(set) var cursorImage: CGImage?
    public private(set) var cursorBitmap: DesktopCursorBitmap?
    public private(set) var cursorVisible = true
    public private(set) var transport: any GlassDesktopTransport
    private let app: DesktopAppModel
    private let operations: DesktopSessionOperations
    private var eventTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private(set) var resizeTask: Task<Void, Never>?
    private(set) var historyTask: Task<Void, Never>?
    private var didScheduleConnectionHistory = false
    private var attemptIsTerminal = true
    private var started = false
    private var closed = false
    private(set) var attemptID = UUID()
    private var issuedTrustRequest: DesktopTrustRequest?
    private struct AttemptCredential {
        let attemptID: UUID
        let connection: DesktopConnection
        let credential: RDPCredential
        func matches(_ request: DesktopTrustRequest) -> Bool {
            attemptID == request.attemptID && connection.id == request.connection.id
                && connection.host == request.connection.host && connection.port == request.connection.port
                && connection.authentication == request.connection.authentication
                && connection.certificateSHA256 == request.connection.certificateSHA256
        }
    }
    // Solely in memory, scoped to this attempt and exact endpoint. SecureBytes
    // owns the password buffer; no transient value is written to the repository.
    private var attemptCredential: AttemptCredential?
    private var resizeRevision = UUID()
    private var lastRequestedSize: DesktopSize?
    private var lastRequestedScaleFactor: Int?
    /// Times this attempt has asked for the window again because the server changed the desktop's
    /// size on its own. Bounded, so a host that will not take the window's size is asked a few
    /// times and then left alone rather than asked on every frame.
    private var serverSizeCorrections = 0
    static let maximumServerSizeCorrections = 3
    /// Pixels per point of the display this window is on, reported by the view.
    private var displayScale: Double = 1
    /// How a touch screen drives the remote pointer.
    public var pointerMode = DesktopPointerMode.trackpad
    /// Whether the software keyboard has been asked for. Neither protocol reports remote text focus,
    /// so this is always the user's explicit choice rather than something detected.
    public var wantsKeyboard = false
    /// How many remote pixels to request per point. RDP only; VNC hosts choose their own resolution.
    public var sourceScale: DesktopSourceScale = .automatic {
        didSet {
            guard sourceScale != oldValue, connection.protocol == .rdp else { return }
            requestCurrentWindowSize()
        }
    }
    // The view reports its content size during layout, before the session starts. A new connection
    // opens at that size when Match Window Size is on, instead of connecting at the saved
    // resolution and leaving the desktop letterboxed until a resize round trip completes.
    private var windowSize: DesktopSize?
    private var windowPoints: (width: Double, height: Double)?
    private let audio = DesktopAudioPlayer()
    private let wallpaperRoot: URL
    private var wallpaperStore: DesktopWallpaperStore
    private var wallpaperRevision = UUID()

    public convenience init(connection: DesktopConnection, app: DesktopAppModel) {
        self.init(connection: connection, app: app, operations: DesktopSessionOperations())
    }

    init(connection: DesktopConnection, app: DesktopAppModel, operations: DesktopSessionOperations,
         wallpaperRoot: URL = URL.cachesDirectory.appendingPathComponent("glassDT/Wallpapers", isDirectory: true)) {
        self.connection = connection
        self.app = app
        self.operations = operations
        self.transport = Self.makeTransport(for: connection)
        self.wallpaperRoot = wallpaperRoot
        self.wallpaperStore = DesktopWallpaperStore(root: wallpaperRoot)
    }

    isolated deinit {
        eventTask?.cancel(); frameTask?.cancel(); resizeTask?.cancel(); historyTask?.cancel()
        let transport = transport, store = wallpaperStore
        Task { await transport.disconnect() }
        Task { await store.removeAll() }
    }

    public var desktopSize: DesktopSize {
        if let frame { .init(width: frame.width, height: frame.height) } else { connection.desktop }
    }

    /// The part of the framebuffer on screen: one selected display, or the whole image.
    public var visibleRegion: DesktopRegion {
        guard let frame else { return .whole(width: connection.desktop.width, height: connection.desktop.height) }
        guard let id = selectedScreenID, let screen = screens.first(where: { $0.id == id }),
              screen.x >= 0, screen.y >= 0, screen.width > 0, screen.height > 0,
              screen.x + screen.width <= frame.width, screen.y + screen.height <= frame.height else {
            return .whole(width: frame.width, height: frame.height)
        }
        return .init(origin: .init(x: screen.x, y: screen.y),
                     size: DesktopSize(width: screen.width, height: screen.height))
    }

    /// A display that disappeared, or a host that stopped publishing a layout, returns to the whole image.
    private func reconcileSelectedScreen() {
        guard let id = selectedScreenID else { return }
        if !screens.contains(where: { $0.id == id }) { selectedScreenID = nil }
    }
    public var isConnected: Bool { state == .connected }
    var failurePresentation: DesktopFailurePresentation? {
        guard case .failed(let detail) = state else { return nil }
        return .init(hadDesktop: hadDesktop, details: detail)
    }
    public var status: String {
        switch state {
        case .connecting: "Connecting…"
        case .connected: frame == nil ? "Waiting for desktop…" : "Connected"
        case .disconnected: "Disconnected"
        case .failed: "Connection Failed"
        }
    }

    private static func makeTransport(for connection: DesktopConnection) -> any GlassDesktopTransport {
        connection.protocol == .vnc ? GlassVNCSession() : GlassRDPSession()
    }

    private struct Attempt {
        let id: UUID
        let transport: any GlassDesktopTransport
        var connection: DesktopConnection
        let previousStop: Task<Void, Never>
    }

    private func beginAttempt(keepingCredentialPrompt: Bool = false) -> Attempt {
        let previous = transport, disconnect = operations.disconnect
        app.noteLive(self)
        attemptID = UUID()
        eventTask?.cancel(); eventTask = nil
        frameTask?.cancel(); frameTask = nil
        clearRemoteState()
        shouldClosePresentation = false
        hadDesktop = false
        didScheduleConnectionHistory = false
        attemptIsTerminal = false
        trustRequest = nil; issuedTrustRequest = nil; attemptCredential = nil
        needsCredentials = keepingCredentialPrompt
        isSubmittingCredentials = false; isApprovingCertificate = false
        errorMessage = nil
        state = .connecting
        started = true
        transport = Self.makeTransport(for: connection)
        let stopping = Task { await disconnect(previous) }
        return Attempt(id: attemptID, transport: transport, connection: connection, previousStop: stopping)
    }

    private func requireCurrent(_ id: UUID) throws {
        guard id == attemptID, !Task.isCancelled else { throw CancellationError() }
    }

    public func start() async {
        guard !started, !Task.isCancelled else { return }
        closed = false
        closeTask = nil
        await startSavedCredential(attempt: beginAttempt())
    }

    private func startSavedCredential(attempt: Attempt) async {
        do {
            let credential = try app.credential(for: attempt.connection)
            guard let password = credential.password.toUTF8String() else { throw CredentialMobilityError.invalidCredential }
            try requireCurrent(attempt.id)
            let username = credential.username == DesktopConnection.passwordOnlyAccount && attempt.connection.protocol == .vnc
                ? "" : credential.username
            try await establish(username: username, domain: credential.domain, password: password, attempt: attempt)
        } catch {
            await failedToStart(error, attempt: attempt, prompt: true)
        }
    }

    public func connect(username: String, domain: String?, password: String) async throws {
        guard !closed, !Task.isCancelled else { throw CancellationError() }
        let attempt = beginAttempt()
        do { try await establish(username: username, domain: domain, password: password, attempt: attempt) }
        catch { await failedToStart(error, attempt: attempt, prompt: false); throw error }
    }

    private func establish(username: String, domain: String?, password: String, attempt: Attempt) async throws {
        await attempt.previousStop.value
        try requireCurrent(attempt.id)
        let value = try attempt.connection.validated()
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration: DesktopTransportConfiguration
        switch value.protocol {
        case .rdp:
            // Honour Match Window Size from the first frame. Falling back to the saved resolution
            // keeps behaviour unchanged when the view has not reported a size yet.
            let initial = matchWindow ? (windowSize ?? value.desktop) : value.desktop
            // **The scale goes with the size, from the first frame.** The size alone gave a Retina
            // window a 4K desktop laid out at 100% — a login screen of tiny type — until the
            // display channel's first monitor layout carried the 200% (2026-09-22, a GNOME server). The
            // client core data has a field for it (MS-RDPBCGR 2.2.1.3.2), so it is asked for at
            // connect. The first monitor layout still repeats it, for a server that only reads
            // the display channel: `lastRequestedScaleFactor` stays nil until that layout is sent.
            configuration = .rdp(GlassRDPConfiguration(host: value.host, port: value.port,
                username: account, domain: domain, password: password,
                width: initial.width, height: initial.height,
                requiresNLA: value.authentication == .networkLevel,
                approvedCertificateSHA256: value.certificateSHA256,
                clipboardEnabled: value.clipboardEnabled, audioEnabled: value.audioEnabled,
                desktopScaleFactor: currentScaleFactor))
            // The server is already being asked for this size, so no immediate second request.
            lastRequestedSize = initial
            lastRequestedScaleFactor = nil
        case .vnc:
            guard !password.isEmpty else { throw RDPCredentialValidationError.missingUsernameOrPassword }
            configuration = .vnc(GlassVNCConfiguration(host: value.host, port: value.port, username: account,
                                                       password: password, clipboardEnabled: value.clipboardEnabled))
        }
        attemptCredential = AttemptCredential(attemptID: attempt.id, connection: value,
            credential: RDPCredential(username: account.isEmpty ? DesktopConnection.passwordOnlyAccount : account,
                                      domain: domain, password: password))
        observe(attempt: attempt)
        try await operations.connect(attempt.transport, configuration)
        do { try requireCurrent(attempt.id) }
        catch { await operations.disconnect(attempt.transport); throw error }
    }

    private func failedToStart(_ error: Error, attempt: Attempt, prompt: Bool) async {
        guard attempt.id == attemptID else { return }
        if error is CancellationError || Task.isCancelled {
            await disconnect()
            return
        }
        clearRemoteState()
        attemptIsTerminal = true
        attemptCredential = nil
        if case SecretStoreError.notFound = error { state = .disconnected }
        else { errorMessage = error.localizedDescription; state = .failed(error.localizedDescription) }
        started = false
        needsCredentials = prompt
    }

    public func submitCredentials(username: String, password: String, remember: Bool) async {
        guard !closed, !isSubmittingCredentials, !Task.isCancelled else { return }
        var attempt = beginAttempt(keepingCredentialPrompt: true)
        isSubmittingCredentials = true
        defer { if attempt.id == attemptID { isSubmittingCredentials = false } }
        do {
            let validated = try attempt.connection.validated()
            let submitted: (username: String, domain: String?, password: String)
            if validated.protocol == .vnc {
                let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !password.isEmpty, account.utf8.count <= 63 else { throw RDPCredentialValidationError.missingUsernameOrPassword }
                submitted = (account, nil, password)
            } else {
                guard let value = try RDPCredentials.validated(username: username,
                    domain: validated.domain.isEmpty ? nil : validated.domain, password: password) else {
                    throw RDPCredentialValidationError.missingUsernameOrPassword
                }
                submitted = (value.username, value.domain, value.password)
            }
            if remember {
                var updated = validated
                updated.username = submitted.username
                try requireCurrent(attempt.id)
                try await operations.save(app, updated, password)
                try requireCurrent(attempt.id)
                guard let stored = app.connections.first(where: { $0.id == updated.id }) else { throw DesktopError.missingConnection }
                connection = stored
                attempt.connection = stored
            }
            try requireCurrent(attempt.id)
            needsCredentials = false
            try await establish(username: submitted.username,
                                domain: submitted.domain?.isEmpty == false ? submitted.domain : nil,
                                password: submitted.password, attempt: attempt)
        } catch { await failedToStart(error, attempt: attempt, prompt: true) }
    }

    public func approveCertificate(_ request: DesktopTrustRequest) async {
        guard !closed, !isApprovingCertificate, issuedTrustRequest == request, request.attemptID == attemptID,
              let fingerprint = request.certificate.sha256,
              request.certificate.host == request.connection.host, request.certificate.port == request.connection.port,
              attemptCredential?.matches(request) == true, !Task.isCancelled else { return }
        isApprovingCertificate = true
        issuedTrustRequest = nil
        trustRequest = nil
        defer { if request.attemptID == attemptID { isApprovingCertificate = false } }
        do {
            try requireCurrent(request.attemptID)
            let updated = try await operations.approve(app, fingerprint, request.connection.id, request.connection)
            try requireCurrent(request.attemptID)
            guard let retained = attemptCredential, retained.matches(request),
                  let password = retained.credential.password.toUTF8String() else { throw CancellationError() }
            connection = updated
            let next = beginAttempt()
            do {
                try await establish(username: retained.credential.username, domain: retained.credential.domain,
                                    password: password, attempt: next)
            } catch { await failedToStart(error, attempt: next, prompt: true) }
        } catch is CancellationError {
            if request.attemptID == attemptID { await disconnect() }
        } catch {
            guard request.attemptID == attemptID else { return }
            attemptCredential = nil
            errorMessage = error.localizedDescription
        }
    }

    public func dismissTrustRequest(_ displayed: DesktopTrustRequest? = nil) {
        guard displayed == nil || trustRequest == displayed else { return }
        trustRequest = nil
    }
    public func cancelTrustRequest(_ displayed: DesktopTrustRequest? = nil) {
        guard displayed == nil || issuedTrustRequest == displayed else { return }
        issuedTrustRequest = nil
        attemptCredential = nil
        if displayed == nil || trustRequest == displayed { trustRequest = nil }
    }

    /// Invalidation is synchronous, including when the caller closes a window.
    private func stopCurrent() -> any GlassDesktopTransport {
        let previous = transport
        attemptID = UUID()
        started = false
        eventTask?.cancel(); eventTask = nil
        frameTask?.cancel(); frameTask = nil
        clearRemoteState()
        attemptIsTerminal = true
        trustRequest = nil; issuedTrustRequest = nil; attemptCredential = nil
        needsCredentials = false
        isSubmittingCredentials = false; isApprovingCertificate = false
        state = .disconnected
        return previous
    }

    public func disconnect() async {
        await close().value
    }

    @discardableResult
    public func close() -> Task<Void, Never> {
        if let closeTask { return closeTask }
        closed = true
        app.noteClosed(self)
        shouldClosePresentation = true
        let previous = stopCurrent(), disconnect = operations.disconnect
        wallpaperRevision = UUID()
        wallpaperURL = nil
        let previousStore = wallpaperStore
        wallpaperStore = DesktopWallpaperStore(root: wallpaperRoot)
        let stopping = Task { await disconnect(previous) }
        let cleanup = Task { await previousStore.removeAll(); await stopping.value }
        closeTask = cleanup
        return cleanup
    }

    public func reconnect() async {
        guard !closed, !Task.isCancelled else { return }
        await startSavedCredential(attempt: beginAttempt())
    }

    /// Explicit dismissal invalidates any pending validation/save operation.
    /// A completed save may remain committed, but it cannot start a connection.
    @discardableResult public func cancelCredentialEntry() -> Task<Void, Never> {
        let previous = stopCurrent(), disconnect = operations.disconnect
        return Task { await disconnect(previous) }
    }

    public func requestCredentials() async {
        guard !closed, !Task.isCancelled else { return }
        let previous = stopCurrent(), requestID = attemptID
        await operations.disconnect(previous)
        guard requestID == attemptID, !Task.isCancelled else { return }
        needsCredentials = true
    }

    private func cancelResize() {
        resizeRevision = UUID()
        resizeTask?.cancel(); resizeTask = nil
    }

    public func resize(width: Double, height: Double, displayScale scale: Double = 1) {
        if scale.isFinite, scale > 0 { displayScale = scale }
        windowPoints = (width, height)
        let size = scaledWindowSize(width: width, height: height)
        if (try? size.validate()) != nil { windowSize = size }
        guard matchWindow else { return }
        scheduleResize(size, matchingWindow: true, delay: .milliseconds(250))
    }

    /// The remote size for this window at the chosen scale. Falls back to the window's own size when
    /// the scaled request would exceed the supported bounds.
    private func scaledWindowSize(width: Double, height: Double) -> DesktopSize {
        let factor = connection.protocol == .rdp ? sourceScale.factor(displayScale: displayScale) : 1
        let scaled = DesktopSize.fitting(width: width * factor, height: height * factor)
        if (try? scaled.validate()) != nil, capabilitiesAllow(scaled) { return scaled }
        return DesktopSize.fitting(width: width, height: height)
    }

    private func capabilitiesAllow(_ size: DesktopSize) -> Bool {
        guard let capabilities else { return true }
        return capabilities.supports(width: size.width, height: size.height)
    }

    private var currentScaleFactor: Int {
        connection.protocol == .rdp ? sourceScale.desktopScaleFactor(displayScale: displayScale) : 100
    }

    /// Re-asks for the current window at the current scale, used when the scale setting changes.
    private func requestCurrentWindowSize() {
        guard matchWindow, let points = windowPoints else { return }
        scheduleResize(scaledWindowSize(width: points.width, height: points.height),
                       matchingWindow: true, delay: .milliseconds(50))
    }

    public func requestEdgeResize(_ size: DesktopSize) {
        matchWindow = false
        scheduleResize(size, matchingWindow: false, delay: .milliseconds(100))
    }

    private func scheduleResize(_ size: DesktopSize, matchingWindow: Bool, delay: Duration) {
        // Every new geometry supersedes pending work, including a return to the
        // already acknowledged size or a request outside negotiated limits.
        cancelResize()
        guard isConnected, let capabilities,
              size != lastRequestedSize || currentScaleFactor != lastRequestedScaleFactor,
              capabilities.supports(width: size.width, height: size.height) else { return }
        let attempt = attemptID, revision = resizeRevision, target = transport, pause = operations.delay
        resizeTask = Task { [weak self] in
            do {
                try await pause(delay)
                guard let self, !Task.isCancelled, attempt == attemptID, revision == resizeRevision,
                      matchWindow == matchingWindow else { return }
                try await performResize(size, target: target, attempt: attempt, revision: revision)
            } catch is CancellationError {} catch {
                guard let self, attempt == attemptID, revision == resizeRevision else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    public func setSourceSize(_ size: DesktopSize) async {
        guard !closed, !Task.isCancelled else { return }
        matchWindow = false
        cancelResize()
        let attempt = attemptID, revision = resizeRevision, target = transport
        do { try await performResize(size, target: target, attempt: attempt, revision: revision) }
        catch is CancellationError {} catch {
            if attempt == attemptID, revision == resizeRevision { errorMessage = error.localizedDescription }
        }
    }

    private func performResize(_ size: DesktopSize, target: any GlassDesktopTransport, attempt: UUID, revision: UUID) async throws {
        try requireCurrent(attempt)
        guard revision == resizeRevision else { throw CancellationError() }
        try size.validate()
        guard isConnected, let capabilities, capabilities.supports(width: size.width, height: size.height) else {
            throw GlassRDPError.unsupported("The server has not offered this desktop size.")
        }
        let scaleFactor = currentScaleFactor
        try await operations.resize(target, size, scaleFactor)
        try requireCurrent(attempt)
        guard revision == resizeRevision else { throw CancellationError() }
        lastRequestedSize = size
        lastRequestedScaleFactor = scaleFactor
    }

    public func releaseInput() {
        let target = transport
        Task { await target.releaseInputs() }
    }

    private func sendInput(_ operation: @escaping @Sendable (any GlassDesktopTransport) async throws -> Void) {
        guard isConnected else { return }
        let attempt = attemptID, target = transport
        Task { [weak self] in
            guard let self, attempt == attemptID, isConnected else { return }
            do { try await operation(target) }
            catch {
                await target.releaseInputs()
                if attempt == attemptID { errorMessage = error.localizedDescription }
            }
        }
    }

    public func sendText(_ text: String) { sendInput { try await $0.sendText(text) } }
    /// Shares a local copy with the remote clipboard, or, with clipboard sharing off, types its text.
    public func pasteClipboard(_ content: GlassClipboardContent) {
        let clipboardEnabled = connection.clipboardEnabled
        sendInput { target in
            if clipboardEnabled { try await target.sendClipboard(content) }
            else if let text = content.text { try await target.sendText(text) }
        }
    }
    public func sendKey(_ code: UInt16, extended: Bool = false) {
        sendInput { target in
            try await target.keyboard(scancode: code, extended: extended, isDown: true)
            try await target.keyboard(scancode: code, extended: extended, isDown: false)
        }
    }
    public func sendSecureAttention() {
        sendInput { target in
            try await target.keyboard(scancode: 0x1d, isDown: true)
            try await target.keyboard(scancode: 0x38, isDown: true)
            try await target.keyboard(scancode: 0x53, extended: true, isDown: true)
            try await target.keyboard(scancode: 0x53, extended: true, isDown: false)
            try await target.keyboard(scancode: 0x38, isDown: false)
            try await target.keyboard(scancode: 0x1d, isDown: false)
        }
    }

    public func importWallpaper(from url: URL) async {
        guard !closed, !Task.isCancelled else { return }
        let revision = UUID(), store = wallpaperStore
        wallpaperRevision = revision
        do {
            let candidate = try await store.prepare(from: url)
            guard !Task.isCancelled, wallpaperRevision == revision, wallpaperStore === store else {
                try? await store.discard(candidate)
                return
            }
            let previous = wallpaperURL
            wallpaperURL = candidate
            if let previous { try await store.discard(previous) }
        } catch {
            if wallpaperRevision == revision { errorMessage = error.localizedDescription }
        }
    }

    private func clearRemoteState() {
        historyTask?.cancel(); historyTask = nil
        cancelResize()
        audio.stop()
        frame = nil; capabilities = nil; remoteClipboard = nil
        screens = []; selectedScreenID = nil
        cursor = .systemDefault; cursorBitmap = nil; cursorImage = nil
        pointerPosition = nil; cursorVisible = true
        lastRequestedSize = nil
        lastRequestedScaleFactor = nil
        serverSizeCorrections = 0
    }

    private func updateCursorImage() {
        guard let bitmap = cursorBitmap, let frame else { cursorImage = nil; return }
        let point = pointerPosition ?? .init(x: frame.width / 2, y: frame.height / 2)
        do {
            let data = try bitmap.compositedPixels(over: frame, pointerX: point.x, pointerY: point.y)
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                    bitsPerPixel: 32, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw DesktopCursorError.invalidMasks
            }
            cursorImage = image
        } catch { errorMessage = error.localizedDescription; cursorImage = nil }
    }

    private func observe(attempt: Attempt) {
        let target = attempt.transport, id = attempt.id, snapshot = attempt.connection
        eventTask = Task { [weak self] in
            for await event in target.events {
                guard let self, !Task.isCancelled, attemptID == id else { break }
                await receive(event, attempt: id, connection: snapshot)
            }
        }
        frameTask = Task { [weak self] in
            for await value in target.frames {
                guard let self, !Task.isCancelled, attemptID == id else { break }
                receive(value, attempt: id)
            }
        }
    }

    // Internal event reducers are shared by real streams and deterministic tests.
    func receive(_ event: GlassRDPEvent, attempt id: UUID, connection snapshot: DesktopConnection) async {
        guard id == attemptID else { return }
        switch event {
        case .state(let value):
            let wasConnected = isConnected
            state = value
            if value == .connected { recordFirstDesktopIfReady(snapshot: snapshot) }
            else if case .failed(let message) = value {
                attemptIsTerminal = true
                clearRemoteState(); errorMessage = message; started = false
                if issuedTrustRequest == nil && !isApprovingCertificate {
                    attemptCredential = nil
                    await app.notices.connectionFailed(attempt: id)
                }
            } else if value == .disconnected {
                if wasConnected || hadDesktop { shouldClosePresentation = true }
                attemptIsTerminal = true
                clearRemoteState(); trustRequest = nil; issuedTrustRequest = nil; attemptCredential = nil; started = false
            }
        case .certificate(let certificate):
            guard !certificate.isAccepted, certificate.host == snapshot.host, certificate.port == snapshot.port else { return }
            let request = DesktopTrustRequest(id: UUID(), attemptID: id, certificate: certificate, connection: snapshot)
            issuedTrustRequest = request; trustRequest = request
        case .displayCapabilities(let value):
            if state == .connecting || isConnected { capabilities = value }
        case .cursor(let value):
            guard isConnected else { return }
            cursor = value
            switch value {
            case .hidden: cursorVisible = false
            case .systemDefault: cursorBitmap = nil; cursorImage = nil; cursorVisible = true
            case .position(let x, let y): pointerPosition = .init(x: x, y: y)
            case .image(let raw):
                do { cursorBitmap = try DesktopCursorDecoder.decode(raw); cursorVisible = true; updateCursorImage() }
                catch { errorMessage = error.localizedDescription }
            }
        case .screens(let value):
            guard state == .connecting || isConnected else { return }
            screens = value
            reconcileSelectedScreen()
        case .clipboard(let value): if isConnected, snapshot.clipboardEnabled { remoteClipboard = value }
        case .audio(let sample):
            guard isConnected, snapshot.audioEnabled else { return }
            do { try audio.play(sample) } catch { errorMessage = error.localizedDescription }
        }
    }

    func receive(_ value: GlassRDPFrame, attempt id: UUID) {
        guard id == attemptID, !attemptIsTerminal, state == .connecting || isConnected else { return }
        let previous = frame
        frame = value
        hadDesktop = true
        updateCursorImage()
        recordFirstDesktopIfReady(snapshot: connection)
        followServerSizeChange(from: previous, to: value)
    }

    /// **The server can change its own size.** GNOME's login screen takes the window's size, and
    /// the session that starts after logging in comes up at 640 × 480 — a desktop this client never
    /// asked for, that stayed until the user nudged the window by a pixel (2026-09-22, a GNOME server).
    /// `scheduleResize` drops a request for the size already asked for, which is right while the
    /// server keeps that size and wrong the moment it does not. A frame at a size other than the
    /// one requested, arriving after a frame at some other size again, is the server having changed
    /// its mind — and the window is asked for once more, forgetting that it was asked for before.
    /// A server that keeps its new size sends no further change and is not asked again; one that
    /// keeps changing is asked `maximumServerSizeCorrections` times per attempt.
    private func followServerSizeChange(from previous: GlassRDPFrame?, to value: GlassRDPFrame) {
        guard matchWindow, isConnected, let requested = lastRequestedSize,
              value.width != requested.width || value.height != requested.height,
              previous.map({ $0.width != value.width || $0.height != value.height }) ?? true,
              serverSizeCorrections < Self.maximumServerSizeCorrections else { return }
        serverSizeCorrections += 1
        lastRequestedSize = nil
        requestCurrentWindowSize()
    }

    private func recordFirstDesktopIfReady(snapshot: DesktopConnection) {
        guard !attemptIsTerminal, isConnected, frame != nil, !didScheduleConnectionHistory else { return }
        didScheduleConnectionHistory = true
        let id = attemptID, receivedAt = Date(), record = operations.recordConnection
        historyTask = Task { [weak self] in
            guard let self, !Task.isCancelled, attemptID == id, !attemptIsTerminal,
                  isConnected, frame != nil else { return }
            await record(app, snapshot, receivedAt)
        }
    }
}

/// Session-owned, bounded image files. Validation happens before publication or
/// deletion of a previous reference. The actor keeps file I/O off the main actor.
actor DesktopWallpaperStore {
    let directory: URL
    private var owned = Set<URL>()
    init(root: URL) { directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true) }

    func prepare(from sourceURL: URL) throws -> URL {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: DesktopWallpaperBounds.maximumBytes + 1) ?? Data()
        guard data.count <= DesktopWallpaperBounds.maximumBytes else { throw RendererError.wallpaperTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw RendererError.invalidWallpaper
        }
        try DesktopWallpaperBounds.validate(properties)
        guard CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
            throw RendererError.invalidWallpaper
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(sourceURL.pathExtension)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        owned.insert(destination)
        return destination
    }

    func discard(_ url: URL) throws {
        guard owned.contains(url) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
        owned.remove(url)
    }

    func removeAll() {
        for url in owned { try? discard(url) }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Remote pixels per local point for an aspect-fitted source desktop.
enum DesktopEdgeGeometry {
    static func density(source: DesktopSize, viewport: CGSize) -> Double {
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0 else { return 1 }
        return max(Double(source.width) / viewport.width, Double(source.height) / viewport.height)
    }
}
