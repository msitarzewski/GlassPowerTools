import Foundation
import CoreGraphics
import ImageIO
import Observation
import GlassConnectionKit
import GlassLayers
import GlasSecretStore
import GlassRDPTransport
import GlassShell
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
            && lhs.graphicsMode == rhs.graphicsMode
    }
}

extension GlassRDPGraphicsMode {
    /// The saved choice, as the transport takes it (B-F32).
    init(_ mode: DesktopGraphicsMode) {
        switch mode {
        case .automatic: self = .automatic
        case .h264: self = .h264
        case .withoutH264: self = .withoutH264
        }
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
    /// A copy to the remote clipboard; tests see when it goes.
    var sendClipboard: @MainActor (any GlassDesktopTransport, GlassClipboardContent) async throws -> Void = {
        try await $0.sendClipboard($1)
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
    /// The desktop's own window (W30): what it shows and how. Display windows have their own
    /// (`viewports`); `presentation`, `selectedScreenID`, `windowSettings` and `pointerMode` below
    /// are this one's, as they were the session's before a desktop could have several windows.
    public let primaryViewport: DesktopViewport
    /// The windows open onto this session; it ends when the last one closes.
    public private(set) var viewports: [DesktopViewport] = []
    /// Nil shows the whole framebuffer. Otherwise the identifier of the single display on screen.
    public var selectedScreenID: UInt32? {
        get { primaryViewport.selectedScreenID }
        set { primaryViewport.selectedScreenID = newValue }
    }
    /// The server's latest copy, in every form it offered; the session view puts it on the local
    /// clipboard (D42a).
    public private(set) var remoteClipboard: GlassClipboardContent?
    /// Whether the remote side's clipboard is open. An RDP server opens it with Monitor Ready, once
    /// the remote session is signed in — on Windows when its clipboard process starts, seconds after
    /// the desktop appears; VNC needs no such step. Until then a copy waits (`pendingClipboard`).
    public private(set) var remoteClipboardIsOpen = false
    /// The latest copy made here before the remote clipboard opened: sent when it does. Only the
    /// latest, as a clipboard holds one thing.
    private var pendingClipboard: GlassClipboardContent?
    /// The attempt the "still waiting" notice was scheduled for: said once per connection.
    private var clipboardWaitNoticeAttempt: UUID?
    /// How long a copy waits before the desktop says why it has not gone across.
    static let clipboardWaitNotice: Duration = .seconds(20)
    /// What the desktop's window draws with. Its mode, opacity, key colour, tolerance and edge
    /// softness are the window's settings resolved over All Desktops' (`apply`, W25); its zoom, pan
    /// and tilt are the window's own.
    public var presentation: PresentationSettings {
        get { primaryViewport.presentation }
        set { primaryViewport.presentation = newValue }
    }
    /// The desktop's window's own settings over All Desktops' (W25), kept on this device for the
    /// desktop it shows (`DesktopWindowSettingsStore`), so its window has them again the next time.
    public var windowSettings: GlassWindowOverrides {
        get { primaryViewport.windowSettings }
        set { primaryViewport.windowSettings = newValue }
    }
    /// What the connection trades for bytes (W30), from the desktop's own window's settings. VNC
    /// acts on it; RDP ignores it.
    public var streamQuality = GlassDesktopStreamQuality.automatic {
        didSet {
            guard streamQuality != oldValue else { return }
            let target = transport, value = streamQuality
            Task { await target.setStreamQuality(value) }
            for connection in displayConnections.values { connection.setQuality(value) }
        }
    }
    /// What a Mac's Retina displays are sent at (W38), from the desktop's own window's settings: the
    /// connection's, and each display window's own connection's.
    public var retinaDisplays = GlassDesktopRetinaDisplays.oneX {
        didSet {
            guard retinaDisplays != oldValue else { return }
            let target = transport, value = retinaDisplays
            Task { await target.setRetinaDisplays(value) }
            for connection in displayConnections.values { connection.setRetinaDisplays(value) }
            updateDisplayConnections()
        }
    }
    /// How a Mac shares its screen, from the desktop's own window's settings: taken when the
    /// connection opens, since High Performance makes the Mac a virtual display of the window's size.
    public var macScreenSharing = GlassDesktopMacScreenSharing.standard
    /// What a High Performance session is doing; nil in Standard mode.
    public private(set) var highPerformanceStatus: GlassDesktopHighPerformanceStatus?
    /// Display windows' own connections (W38), by window (`DesktopViewport.id`): where a Mac's
    /// displays are of mixed density, each display window that shows one display fetches it on a
    /// connection of its own, at that display's 1x (`DesktopDisplayConnection`).
    public private(set) var displayConnections: [UUID: DesktopDisplayConnection] = [:]
    /// Why display windows show their displays from the desktop's connection after all: the first
    /// display connection that failed before showing anything, for this connection.
    public private(set) var displayConnectionFailure: String?
    /// What the link is doing, about once a second, while connected (VNC).
    public private(set) var linkStatistics: GlassDesktopLinkStatistics?
    /// One window, or a window for each display (W30), from the desktop's own window's settings.
    public var displayWindows = DesktopDisplayWindows.standard
    /// Displays whose windows the desktop's window should open now (`DesktopSessionView`), taken
    /// with `takeDisplayWindowRequests`.
    public private(set) var displayWindowRequests: [UInt32] = []
    /// Display windows closed by hand during this session, which `displayWindows` does not reopen.
    private var dismissedDisplays: Set<UInt32> = []
    private var appliedDisplayWindows = false
    private var requestedRegions: [GlassRemoteRegion]??
    /// Whether this device can open a second window; nil asks the device, at the point of use
    /// (rules 43, 55). A test sets it.
    var canOpenDisplayWindows: Bool?
    #if DEBUG
    /// Screenshots only (`App/GlassDemoMode.swift`): Desktop Settings ▸ This Window opens over the window.
    var demoOpensSettings = false
    /// Screenshots only: and on its Connection page (W30).
    var demoOpensConnection = false
    #endif
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
    /// The desktop's window's pointer; each display window has its own (`DesktopViewport`).
    public var pointerMode: DesktopPointerMode {
        get { primaryViewport.pointerMode }
        set { primaryViewport.pointerMode = newValue }
    }
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
        self.primaryViewport = DesktopViewport(key: DesktopWindowKey(endpoint: connection.id), store: app.windowSettings)
        self.transport = Self.makeTransport(for: connection)
        self.wallpaperRoot = wallpaperRoot
        self.wallpaperStore = DesktopWallpaperStore(root: wallpaperRoot)
        primaryViewport.session = self
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

    /// The part of the framebuffer on screen in the desktop's window: one selected display, or the whole image.
    public var visibleRegion: DesktopRegion { region(for: primaryViewport) }

    /// The part of the framebuffer a window shows: its display, or the whole image.
    public func region(for viewport: DesktopViewport) -> DesktopRegion {
        guard let frame else { return .whole(width: connection.desktop.width, height: connection.desktop.height) }
        return DesktopDisplayLayout.region(screenID: viewport.selectedScreenID, screens: screens,
                                           framebuffer: DesktopSize(width: frame.width, height: frame.height))
    }

    /// A display that disappeared, or a host that stopped publishing a layout, returns the
    /// desktop's window to the whole image. A display's own window keeps its display, and shows the
    /// whole image (`region(for:)`) until the display is back.
    private func reconcileSelectedScreen() {
        guard let id = primaryViewport.selectedScreenID else { return }
        if !screens.contains(where: { $0.id == id }) { primaryViewport.selectedScreenID = nil }
    }

    // MARK: Windows onto this session (W30)

    /// A window opened onto this session. Its display is asked for from now on.
    public func attach(_ viewport: DesktopViewport) {
        guard !closed, !viewports.contains(where: { $0 === viewport }) else { return }
        viewport.session = self
        viewports.append(viewport)
        if let display = viewport.key.display { dismissedDisplays.remove(display) }
        updateDisplayConnections()
    }

    /// A window closed. The session ends with its last window; a display window closed by hand
    /// is not reopened by `displayWindows` during this session. Its own connection closes with it.
    public func detach(_ viewport: DesktopViewport) {
        guard viewports.contains(where: { $0 === viewport }) else { return }
        viewports.removeAll { $0 === viewport }
        if let display = viewport.key.display, !closed, !shouldClosePresentation { dismissedDisplays.insert(display) }
        if viewports.isEmpty { close() } else { updateDisplayConnections() }
    }

    /// The window that answers for the session — credentials, trust, the display windows to
    /// open: the desktop's own while it is open, else the first display window.
    public var leadViewport: DesktopViewport? {
        viewports.contains(where: { $0 === primaryViewport }) ? primaryViewport : viewports.first
    }

    /// A display window for this session, with its own settings for that display.
    public func displayViewport(for display: UInt32) -> DesktopViewport {
        if let open = viewports.first(where: { $0.key.display == display }) { return open }
        return DesktopViewport(key: DesktopWindowKey(endpoint: connection.id, display: display), store: app.windowSettings)
    }

    /// The displays to open windows for, once: the desktop's window opens them.
    public func takeDisplayWindowRequests() -> [UInt32] {
        defer { displayWindowRequests = [] }
        return displayWindowRequests
    }

    /// A window's display or visibility changed.
    func viewportDidChange() {
        for viewport in viewports { displayConnections[viewport.id]?.setOnScreen(viewport.isOnScreen) }
        updateDisplayConnections()
        updateCursorImage()
    }

    /// Asks the transport only for what is on screen: the displays of the windows that are, except
    /// those a window's own connection shows (W38).
    private func updateRequestedRegions() {
        let framebuffer = frame.map { DesktopSize(width: $0.width, height: $0.height) }
        let regions = DesktopDisplayLayout.requestedRegions(
            onScreen: viewports.filter { $0.isOnScreen && ownConnection(for: $0) == nil }.map { region(for: $0) },
            windows: viewports.count, framebuffer: framebuffer)
        guard requestedRegions != .some(regions) else { return }
        requestedRegions = .some(regions)
        let target = transport
        Task { await target.setVisibleRegions(regions) }
    }

    /// What the transport was last asked for: nil for the whole framebuffer, empty for nothing.
    var currentRequestedRegions: [GlassRemoteRegion]? { requestedRegions ?? nil }

    // MARK: A display window's own connection (W38)

    /// The connection a window's picture and input go through when it is not the desktop's: its own,
    /// once that shows a picture.
    public func ownConnection(for viewport: DesktopViewport) -> DesktopDisplayConnection? {
        guard let connection = displayConnections[viewport.id], connection.isShowing else { return nil }
        return connection
    }

    /// The picture a window draws: its own connection's, or the desktop's.
    public func pictureFrame(for viewport: DesktopViewport) -> GlassRDPFrame? {
        ownConnection(for: viewport)?.frame ?? frame
    }

    /// The part of `pictureFrame(for:)` a window shows: all of its own connection's picture, else its
    /// display's part of the desktop's.
    public func pictureRegion(for viewport: DesktopViewport) -> DesktopRegion {
        if let picture = ownConnection(for: viewport)?.frame { return .whole(width: picture.width, height: picture.height) }
        return region(for: viewport)
    }

    /// Where a window's pointer and keys go.
    func inputTransport(for viewport: DesktopViewport) -> any GlassDesktopTransport {
        ownConnection(for: viewport)?.transport ?? transport
    }

    /// Whether the host's displays are of mixed density, as Apple's viewer counts it: at least one at
    /// 1x and at least one that is not (remotex's `mixed_density`).
    var hasMixedDensities: Bool {
        let densities = screens.compactMap(\.density)
        let oneX = densities.filter { abs($0 - 1) <= 0.005 }.count
        return oneX > 0 && oneX < densities.count
    }

    /// Whether a display window may open a connection of its own (W38). Off: a Mac serves every
    /// viewer at one scale at a time. With the desktop's connection at half size for its Retina
    /// display, the 1x display's own connection got no picture after its first few — the Mac's
    /// counters showed every update going through its scaling path, none unscaled — while its
    /// pointer still moved (2026-10-11, the owner on a Vision Pro: "the second display doesn't
    /// reflect any changes"). So, as Apple's viewer does over mixed densities, both displays come
    /// from the desktop's connection at their own pixels; Retina at 1x applies where only Retina
    /// displays are on screen. The mechanism stays, tested, for a Mac that can do otherwise.
    var opensDisplayConnections = false

    /// The display a window would take a connection of its own for, if any: a display window showing
    /// one display of a Mac whose displays are of mixed density, with Retina Displays at 1x.
    func ownConnectionDisplay(for viewport: DesktopViewport) -> UInt32? {
        guard opensDisplayConnections,
              !closed, isConnected, connection.protocol == .vnc, retinaDisplays == .oneX, !viewport.isPrimary,
              displayConnectionFailure == nil, attemptCredential != nil, hasMixedDensities,
              let display = viewport.selectedScreenID, screens.contains(where: { $0.id == display }) else { return nil }
        return display
    }

    /// Opens the display connections the windows want and closes the rest, then asks the desktop's
    /// connection for what is left.
    func updateDisplayConnections() {
        var wanted: [UUID: (viewport: DesktopViewport, display: UInt32)] = [:]
        for viewport in viewports {
            if let display = ownConnectionDisplay(for: viewport) { wanted[viewport.id] = (viewport, display) }
        }
        for (id, connection) in displayConnections where wanted[id]?.display != connection.display {
            connection.close()
            displayConnections.removeValue(forKey: id)
        }
        for (id, want) in wanted where displayConnections[id] == nil {
            openDisplayConnection(for: want.viewport, display: want.display, id: id)
        }
        updateRequestedRegions()
    }

    /// The same endpoint and the credential this attempt signed in with: the person signs in once,
    /// and nothing is stored anywhere new.
    private func openDisplayConnection(for viewport: DesktopViewport, display: UInt32, id: UUID) {
        guard let retained = attemptCredential, let password = retained.credential.password.toUTF8String() else { return }
        let account = retained.credential.username == DesktopConnection.passwordOnlyAccount ? "" : retained.credential.username
        let configuration = GlassVNCConfiguration(host: retained.connection.host, port: retained.connection.port,
                                                  username: account, password: password,
                                                  clipboardEnabled: false, display: display)
        let connection = DesktopDisplayConnection(display: display, viewportID: id,
                                                  transport: Self.makeTransport(for: retained.connection),
                                                  disconnect: operations.disconnect)
        connection.session = self
        displayConnections[id] = connection
        connection.start(configuration, quality: streamQuality, retina: retinaDisplays, onScreen: viewport.isOnScreen,
                         connect: operations.connect)
    }

    /// A display connection connected, showed its first picture, failed or ended.
    func displayConnectionChanged(_ connection: DesktopDisplayConnection) {
        guard displayConnections[connection.viewportID] === connection else { return }
        switch connection.state {
        case .failed(let message):
            // A Mac that will not take a second connection is not asked again for this one: its
            // display windows show their displays from the desktop's connection, as before W38.
            if connection.frame == nil, displayConnectionFailure == nil { displayConnectionFailure = message }
            connection.close()
            displayConnections.removeValue(forKey: connection.viewportID)
        case .disconnected:
            if connection.frame == nil, displayConnectionFailure == nil {
                displayConnectionFailure = "The Mac closed the display's own connection."
            }
            connection.close()
            displayConnections.removeValue(forKey: connection.viewportID)
        case .connecting, .connected:
            break
        }
        updateRequestedRegions()
        updateCursorImage()
    }

    /// The pointer, as a display connection says: its shape is the session's, and its position is
    /// mapped from that connection's picture into the desktop's.
    func receive(_ cursor: GlassRDPCursor, from connection: DesktopDisplayConnection) {
        guard isConnected, displayConnections[connection.viewportID] === connection else { return }
        if case .position(let x, let y) = cursor {
            guard let point = desktopPoint(DesktopPoint(x: x, y: y), from: connection) else { return }
            pointerPosition = point
        } else {
            applyCursor(cursor)
        }
    }

    /// A point in a display connection's picture, in the desktop's framebuffer.
    func desktopPoint(_ point: DesktopPoint, from connection: DesktopDisplayConnection) -> DesktopPoint? {
        guard let picture = connection.frame, picture.width > 0, picture.height > 0,
              let screen = screens.first(where: { $0.id == connection.display }) else { return nil }
        let x = screen.x + Int((Double(point.x) * Double(screen.width) / Double(picture.width)).rounded(.down))
        let y = screen.y + Int((Double(point.y) * Double(screen.height) / Double(picture.height)).rounded(.down))
        return DesktopPoint(x: min(screen.x + screen.width - 1, max(screen.x, x)),
                            y: min(screen.y + screen.height - 1, max(screen.y, y)))
    }

    /// A window's pointer moved to `point` in its picture (`pictureRegion(for:)`): the session's
    /// pointer, in the desktop's framebuffer.
    public func movePointer(to point: DesktopPoint, in viewport: DesktopViewport) {
        if let connection = ownConnection(for: viewport) {
            if let mapped = desktopPoint(point, from: connection) { pointerPosition = mapped }
        } else {
            pointerPosition = point
        }
    }

    /// Where the pointer is in a window's picture; nil when it is on a display the window does not
    /// show.
    public func pointerInPicture(for viewport: DesktopViewport) -> DesktopPoint? {
        guard let point = pointerPosition else { return nil }
        let region = region(for: viewport)
        guard point.x >= region.origin.x, point.y >= region.origin.y,
              point.x < region.origin.x + region.size.width, point.y < region.origin.y + region.size.height else { return nil }
        guard let picture = ownConnection(for: viewport)?.frame, region.size.width > 0, region.size.height > 0 else { return point }
        return DesktopPoint(x: Int(Double(point.x - region.origin.x) * Double(picture.width) / Double(region.size.width)),
                            y: Int(Double(point.y - region.origin.y) * Double(picture.height) / Double(region.size.height)))
    }

    /// The display a window shows, or, showing all of them, the one the pointer is on.
    func shownDisplay(for viewport: DesktopViewport) -> GlassRemoteScreen? {
        if let id = viewport.selectedScreenID, let screen = screens.first(where: { $0.id == id }) { return screen }
        guard let point = pointerPosition else { return DesktopDisplayLayout.mainScreen(screens) }
        return screens.first { point.x >= $0.x && point.y >= $0.y && point.x < $0.x + $0.width && point.y < $0.y + $0.height }
            ?? DesktopDisplayLayout.mainScreen(screens)
    }

    /// The scale a window's picture comes at from a Mac (1 is its own pixels); nil where the host
    /// cannot be asked.
    func pictureScale(for viewport: DesktopViewport) -> Double? {
        if let connection = ownConnection(for: viewport) { return connection.linkStatistics?.serverScale }
        return linkStatistics?.serverScale
    }

    /// The picture's pixels per point of the Mac's own on the display a window shows: 2 for a Retina
    /// display at its own pixels, 1 at 1x. Nil where the host does not say.
    func picturePixelsPerPoint(for viewport: DesktopViewport) -> Double? {
        guard let density = shownDisplay(for: viewport)?.density else { return nil }
        return density * (pictureScale(for: viewport) ?? 1)
    }

    /// The picture's pixels per pixel of the pointer's shape in a window: a Mac's pointer is in its
    /// points (W38), so on a Retina display at its own pixels it covers twice its pixel count.
    func cursorPictureScale(for viewport: DesktopViewport) -> Double {
        guard cursorBitmap?.isPointSized == true, let perPoint = picturePixelsPerPoint(for: viewport),
              perPoint.isFinite, perPoint > 0 else { return 1 }
        return min(4, max(0.25, perPoint))
    }

    /// What a window is being sent (W38), for Desktop Settings ▸ Connection and the status bar:
    /// "1728 × 1117 at 1x (50%)".
    public func sending(for viewport: DesktopViewport) -> String? {
        guard pictureFrame(for: viewport) != nil else { return nil }
        let size = pictureRegion(for: viewport).size
        var text = "\(size.width) × \(size.height)"
        if let perPoint = picturePixelsPerPoint(for: viewport) {
            text += " at \(DesktopLinkReadout.density(perPoint))"
            if let scale = pictureScale(for: viewport) { text += " (\(DesktopLinkReadout.scale(scale)))" }
        } else if let scale = pictureScale(for: viewport), scale < 0.995 {
            text += " (\(DesktopLinkReadout.scale(scale)))"
        }
        return text
    }

    /// The window's shape, width over height, while it keeps its display's proportions (W38): the
    /// picture it shows. Nil before there is a picture, with Keep Display Proportions off, and while
    /// Match Window Size makes the remote desktop take the window's shape instead.
    public func pictureAspect(for viewport: DesktopViewport) -> Double? {
        guard viewport.keepsProportions, pictureFrame(for: viewport) != nil, !followsWindowSize(viewport) else { return nil }
        let size = pictureRegion(for: viewport).size
        guard size.width > 0, size.height > 0 else { return nil }
        return Double(size.width) / Double(size.height)
    }

    /// Whether the remote desktop takes this window's size (Match Window Size, on a host that can):
    /// then the window is free, and the desktop follows it.
    func followsWindowSize(_ viewport: DesktopViewport) -> Bool {
        viewport.isPrimary && matchWindow && capabilities != nil && !holdsDisplayLayout
    }

    /// A host with several displays and a window for each: the desktop's window shows the main
    /// display, and the others open in their own — once per connection, and never one closed by
    /// hand. Only where a second window can open.
    private func applyDisplayWindows() {
        guard !appliedDisplayWindows, screens.count > 1, displayWindows == .windowPerDisplay,
              canOpenDisplayWindows ?? GlassWindowPresentation.canOpenWindows else { return }
        appliedDisplayWindows = true
        guard let main = DesktopDisplayLayout.mainScreen(screens) else { return }
        if primaryViewport.selectedScreenID == nil { primaryViewport.selectedScreenID = main.id }
        let shown = Set(viewports.compactMap(\.selectedScreenID)).union([primaryViewport.selectedScreenID].compactMap { $0 })
        displayWindowRequests = screens.map(\.id).filter { !shown.contains($0) && !dismissedDisplays.contains($0) }
    }

    /// Closes every display window's own connection: the session's attempt ended or changed.
    private func closeDisplayConnections() {
        for connection in displayConnections.values { connection.close() }
        displayConnections = [:]
        displayConnectionFailure = nil
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
                desktopScaleFactor: currentScaleFactor,
                graphicsMode: GlassRDPGraphicsMode(value.graphicsMode)))
            // The server is already being asked for this size, so no immediate second request.
            lastRequestedSize = initial
            lastRequestedScaleFactor = nil
        case .vnc:
            guard !password.isEmpty else { throw RDPCredentialValidationError.missingUsernameOrPassword }
            configuration = .vnc(GlassVNCConfiguration(host: value.host, port: value.port, username: account,
                                                       password: password, clipboardEnabled: value.clipboardEnabled,
                                                       highPerformance: highPerformanceRequest()))
        }
        attemptCredential = AttemptCredential(attemptID: attempt.id, connection: value,
            credential: RDPCredential(username: account.isEmpty ? DesktopConnection.passwordOnlyAccount : account,
                                      domain: domain, password: password))
        observe(attempt: attempt)
        // The connection opens at the level and over the displays its windows ask for (W30).
        await attempt.transport.setStreamQuality(streamQuality)
        await attempt.transport.setVisibleRegions(currentRequestedRegions)
        try requireCurrent(attempt.id)
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

    /// What a High Performance connection asks the Mac for: a virtual display the window's size in
    /// points, at this screen's density, its encoder capped at Data Saver and Lowest — the Mac's own
    /// rate controller otherwise moves between 20 and 60 Mbit/s.
    func highPerformanceRequest() -> GlassVNCHighPerformance? {
        guard macScreenSharing == .highPerformance else { return nil }
        let points = windowPoints ?? (1920, 1080)
        let cap: UInt64? = switch streamQuality {
        case .dataSaver: 8_000_000
        case .lowest: 3_000_000
        case .automatic, .best, .balanced: nil
        }
        return GlassVNCHighPerformance(width: max(640, Int(points.width.rounded())), height: max(480, Int(points.height.rounded())),
                                       density: displayScale >= 1.5 ? 2 : 1, bitrateCap: cap)
    }

    /// The remote size for this window at the chosen scale. Falls back to the window's own size when
    /// the scaled request would exceed the supported bounds.
    private func scaledWindowSize(width: Double, height: Double) -> DesktopSize {
        let factor = connection.protocol == .rdp ? sourceScale.factor(displayScale: displayScale) : 1
        let scaled = DesktopSize.fitting(width: width * factor, height: height * factor)
        if (try? scaled.validate()) != nil, capabilitiesAllow(scaled) { return scaled }
        return DesktopSize.fitting(width: width, height: height)
    }

    /// A VNC host with several displays keeps its own layout (W30). SetDesktopSize carries a whole
    /// layout, so asking for one desktop the size of a window would fold its displays into one —
    /// on a Mac, its real displays. Neither Match Window Size nor Desktop Resolution asks then.
    public var holdsDisplayLayout: Bool { connection.protocol == .vnc && screens.count > 1 }

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
        guard isConnected, let capabilities, !holdsDisplayLayout,
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
        guard !holdsDisplayLayout else {
            throw GlassRDPError.unsupported("This computer has several displays, so its resolution is left as it is. Change it on the computer itself.")
        }
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
    ///
    /// **Before the remote clipboard opens, the copy waits; it does not fail** (the owner,
    /// 2026-10-14: "Clipboard sharing is disabled or was not negotiated" over a desktop that had
    /// sharing on). A Mac sends its clipboard as the window comes forward — before Windows or GNOME
    /// has opened theirs — so the first copy of every session was lost behind that banner. If the
    /// clipboard has not opened `clipboardWaitNotice` after the copy, the desktop says why, once.
    public func pasteClipboard(_ content: GlassClipboardContent) {
        let clipboardEnabled = connection.clipboardEnabled
        if clipboardEnabled, isConnected, !remoteClipboardIsOpen {
            pendingClipboard = content
            noteClipboardWaiting()
            return
        }
        let send = operations.sendClipboard
        sendInput { target in
            if clipboardEnabled { try await send(target, content) }
            else if let text = content.text { try await target.sendText(text) }
        }
    }
    /// What the desktop says when a copy has waited and the remote clipboard has still not opened.
    static func clipboardWaitingMessage(_ name: String) -> String {
        "\(name) hasn't opened its clipboard yet, so your copy is waiting and goes across once it does. If it never does, the remote computer is set not to share its clipboard over Remote Desktop."
    }

    private func noteClipboardWaiting() {
        let attempt = attemptID
        guard clipboardWaitNoticeAttempt != attempt else { return }
        clipboardWaitNoticeAttempt = attempt
        let name = connection.name, delay = operations.delay
        Task { [weak self] in
            try? await delay(Self.clipboardWaitNotice)
            guard let self, attempt == attemptID, isConnected, !remoteClipboardIsOpen,
                  pendingClipboard != nil, errorMessage == nil else { return }
            errorMessage = Self.clipboardWaitingMessage(name)
        }
    }

    // MARK: Accessory keys

    /// Control, Option, Command or Shift for the next key: from the Keys menu, since a headset's or a
    /// phone's software keyboard has none of them (`DesktopAccessoryKeys`).
    public private(set) var armedModifiers: Set<DesktopStickyModifier> = []
    /// The accessory keys' own queue, in order, to the desktop's connection.
    private var accessoryInput: DesktopInput?
    private weak var accessoryTransport: (any GlassDesktopTransport)?
    /// Modifiers held down through an arrow pad drag.
    private var heldForDrag: [DesktopKey] = []

    public func toggleArmed(_ modifier: DesktopStickyModifier) {
        if armedModifiers.contains(modifier) { armedModifiers.remove(modifier) } else { armedModifiers.insert(modifier) }
    }

    /// The armed modifiers' keys, disarmed: for a key typed on the software keyboard, which presses
    /// them before it and releases them after.
    func takeArmedModifiers() -> [DesktopKey] {
        defer { armedModifiers = [] }
        return DesktopStickyModifier.allCases.filter(armedModifiers.contains).map(\.key)
    }

    /// One key from the Keys menu, with the modifiers armed for it.
    func sendAccessoryKey(_ key: DesktopKey) {
        guard let input = accessoryQueue() else { return }
        for event in DesktopAccessoryKeys.tap(key, holding: takeArmedModifiers()) { input.send(event) }
    }

    /// An arrow pad drag began: the armed modifiers go down for the whole of it.
    func beginArrowDrag() {
        guard let input = accessoryQueue() else { return }
        heldForDrag = takeArmedModifiers()
        for modifier in heldForDrag { input.send(.key(modifier.scancode, modifier.extended, true, false)) }
    }

    func sendArrowStep(_ key: DesktopKey) {
        guard let input = accessoryQueue() else { return }
        input.send(.key(key.scancode, key.extended, true, false))
        input.send(.key(key.scancode, key.extended, false, false))
    }

    func endArrowDrag() {
        guard let input = accessoryQueue() else { heldForDrag = []; return }
        for modifier in heldForDrag.reversed() { input.send(.key(modifier.scancode, modifier.extended, false, false)) }
        heldForDrag = []
    }

    /// The queue to the connection now, made again when the connection changes.
    private func accessoryQueue() -> DesktopInput? {
        guard isConnected else { return nil }
        if accessoryInput == nil || accessoryTransport !== transport {
            accessoryInput?.stop()
            accessoryInput = DesktopInput(session: transport) { [weak self] in self?.errorMessage = $0 }
            accessoryTransport = transport
        }
        return accessoryInput
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
        remoteClipboardIsOpen = false; pendingClipboard = nil
        closeDisplayConnections()
        screens = []; selectedScreenID = nil
        linkStatistics = nil; displayWindowRequests = []; appliedDisplayWindows = false
        highPerformanceStatus = nil
        armedModifiers = []; heldForDrag = []
        accessoryInput?.stop(); accessoryInput = nil; accessoryTransport = nil
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
            if value == .connected {
                // VNC's cut text needs no negotiation: open as soon as the desktop is.
                if snapshot.protocol == .vnc { remoteClipboardIsOpen = true }
                recordFirstDesktopIfReady(snapshot: snapshot); updateDisplayConnections()
            }
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
            applyCursor(value)
        case .screens(let value):
            guard state == .connecting || isConnected else { return }
            screens = value
            reconcileSelectedScreen()
            applyDisplayWindows()
            updateDisplayConnections()
        case .linkStatistics(let value):
            if isConnected { linkStatistics = value }
        case .clipboard(let value): if isConnected, snapshot.clipboardEnabled { remoteClipboard = value }
        case .clipboardReady:
            guard state == .connecting || isConnected else { return }
            remoteClipboardIsOpen = true
            // The copy that waited goes now, and the notice about it, if it was given, goes too.
            if errorMessage == Self.clipboardWaitingMessage(snapshot.name) { errorMessage = nil }
            if let waiting = pendingClipboard {
                pendingClipboard = nil
                pasteClipboard(waiting)
            }
        case .highPerformance(let value):
            if isConnected || state == .connecting { highPerformanceStatus = value }
        case .audio(let sample):
            // A Mac in High Performance mutes its own output and sends its sound here, as Apple's
            // Screen Sharing plays it: VNC sends sound only then.
            guard isConnected, snapshot.audioEnabled || connection.protocol == .vnc else { return }
            do { try audio.play(sample) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// The pointer's shape, visibility or position, from whichever connection says it.
    private func applyCursor(_ value: GlassRDPCursor) {
        cursor = value
        switch value {
        case .hidden: cursorVisible = false
        case .systemDefault: cursorBitmap = nil; cursorImage = nil; cursorVisible = true
        case .position(let x, let y): pointerPosition = .init(x: x, y: y)
        case .image(let raw):
            do { cursorBitmap = try DesktopCursorDecoder.decode(raw); cursorVisible = true; updateCursorImage() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func receive(_ value: GlassRDPFrame, attempt id: UUID) {
        guard id == attemptID, !attemptIsTerminal, state == .connecting || isConnected else { return }
        let previous = frame
        frame = value
        hadDesktop = true
        if previous?.width != value.width || previous?.height != value.height { updateRequestedRegions() }
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
