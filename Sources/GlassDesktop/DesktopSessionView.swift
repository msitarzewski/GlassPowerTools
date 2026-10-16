import SwiftUI
import UniformTypeIdentifiers
import GlassRDPTransport
import GlassConnectionUI
import GlassLayers
import GlassShell
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A presented alert keeps its identity until dismissal. New events are read
/// from the session only when choosing the next alert, never from a stale queue.
struct DesktopSessionAlertPresentation: Equatable {
    enum Alert: Equatable {
        case trust(DesktopTrustRequest)
        case display(String)
        var title: String {
            switch self {
            case .trust: "Verify Remote Computer"
            case .display: "Display Error"
            }
        }
    }
    private(set) var active: Alert?
    private(set) var credentialSheetIsPresented = false

    mutating func credentialSheetRequested() { credentialSheetIsPresented = true }
    mutating func credentialSheetDidDismiss() { credentialSheetIsPresented = false }

    mutating func presentCurrent(trust: DesktopTrustRequest?, displayError: String?, credentialsRequested: Bool = false) {
        guard active == nil, !credentialSheetIsPresented, !credentialsRequested else { return }
        if let trust { active = .trust(trust) }
        else if let displayError { active = .display(displayError) }
    }

    @discardableResult mutating func dismiss() -> Alert? {
        defer { active = nil }
        return active
    }
}

public struct DesktopSessionView: View {
    private let onClose: (@MainActor () -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var session: DesktopSessionModel
    /// This window onto the session (W30): the desktop's own, or one display's.
    @State private var viewport: DesktopViewport
    @State private var showDisplayOptions = false
    @State private var settingsSection = DesktopSessionSettingsSection.thisWindow
    @State private var requestWallpaperAfterDisplay = false
    /// Settings ▸ Desktops on this device, which this window follows until it sets its own (W25).
    /// Until W25 the window wrote its presentation back into these as it changed, so one window's
    /// Desktop Settings changed every desktop's; now it changes only its own (`windowSettings`).
    private var allDesktops = DesktopAllDesktopsStorage()
    @State private var chooseWallpaper = false
    @State private var showTextInput = false
    @State private var alerts = DesktopSessionAlertPresentation()
    /// The picture's area, for holding a Mac window to the picture's shape (W38).
    @State private var canvasSize = CGSize.zero
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Reports the *real* outcome of this session to whoever asked for it — the shell, when the
    /// window was opened by Connect. Opening a window is not connecting, so the report is made
    /// when the session actually reaches a state, never at presentation time.
    private let onOutcome: (@MainActor (GlassRDPState) -> Void)?

    /// The ⚡: back to the library's Active list, from a window that is otherwise only the
    /// desktop. Every session window carries it (`GlassActiveConnections.swift`); the desktop's
    /// window did not until 2026-09-27 — *"the Desktop window itself doesn't link back"*.
    private let showActiveConnections: (@MainActor () -> Void)?

    public init(connection: DesktopConnection, app: DesktopAppModel,
                onOutcome: (@MainActor (GlassRDPState) -> Void)? = nil,
                onClose: (@MainActor () -> Void)? = nil,
                showActiveConnections: (@MainActor () -> Void)? = nil) {
        self.onClose = onClose
        self.onOutcome = onOutcome
        self.showActiveConnections = showActiveConnections
        let model = DesktopSessionModel(connection: connection, app: app)
        _session = State(initialValue: model)
        _viewport = State(initialValue: model.primaryViewport)
    }

    /// A window onto a session that is already open (W30): a display window, or the desktop's own
    /// window reopened while its display windows kept the connection.
    init(session: DesktopSessionModel, viewport: DesktopViewport,
         onOutcome: (@MainActor (GlassRDPState) -> Void)? = nil,
         onClose: (@MainActor () -> Void)? = nil,
         showActiveConnections: (@MainActor () -> Void)? = nil) {
        self.onClose = onClose
        self.onOutcome = onOutcome
        self.showActiveConnections = showActiveConnections
        _session = State(initialValue: session)
        _viewport = State(initialValue: viewport)
    }

    /// A session built elsewhere: the simulator fixture, and the screenshot demo.
    #if DEBUG
    init(previewSession: DesktopSessionModel, showActiveConnections: (@MainActor () -> Void)? = nil) {
        onClose = nil
        onOutcome = nil
        self.showActiveConnections = showActiveConnections
        _session = State(initialValue: previewSession)
        _viewport = State(initialValue: previewSession.primaryViewport)
    }
    #endif

    public var body: some View {
        window
            // The window's own settings (W25), for everything drawn in it: GlassLayers' contract.
            // This view is the window's root and its settings' owner, so it resolves them from the
            // session it hands down (`profile`); what it presents reads them from here.
            .glassWindowOverrides(viewport.windowSettings)
    }

    /// What this window draws and drives with: its own settings over All Desktops' (W25).
    private var profile: DesktopWindowProfile {
        DesktopWindowProfile(window: viewport.windowSettings, defaults: allDesktops.defaults,
                             compactScreen: compactScreen, reduceTransparency: reduceTransparency)
    }

    /// The window that answers for the session: credentials, trust, display windows to open.
    private var isLead: Bool { session.viewports.isEmpty || session.leadViewport === viewport }

    /// The desktop's name, and the display when this window shows one.
    private var windowTitle: String {
        guard let display = viewport.selectedScreenID, session.screens.count > 1 else { return session.connection.name }
        return "\(session.connection.name) · \(DesktopDisplayLayout.name(of: display, in: session.screens))"
    }

    /// Match Window Size follows the desktop's own window only: a display window shows part of the
    /// desktop, and its size says nothing about the size the desktop should be.
    private func matchWindow(_ size: CGSize) {
        guard viewport.isPrimary else { return }
        session.resize(width: size.width, height: size.height, displayScale: displayScale)
    }

    #if os(iOS)
    /// Black behind the picture, out to every edge: before the first picture, and around one shown as
    /// it is. A presentation that fades or keys out a colour shows the page instead.
    private var drawsBlackBackdrop: Bool {
        session.frame == nil || viewport.presentation.mode == .original
    }
    #endif

    private var compactScreen: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder private var window: some View {
        #if os(visionOS)
        // **The terminal's window, with the remote screen as its canvas** (W28; owner, 2026-10-10:
        // "rebuild all window appearances to match the new terminal. So screen sharing, database,
        // etc."). The window is plain and draws Apple's glass itself, once, as strong as its
        // Background Frost — none at all at 0 — so with Opacity at 0 too it is completely clear
        // but for its title and controls. The screen sits an even 34 points inside the window's
        // edge in the corner concentric with Apple's, as a terminal's canvas does. It was a frosted
        // card 22 points in with the screen 10 points inside that: a material plate laid over the
        // room, and a corner of its own.
        GlassNativeWindowFrame {
            sessionContent
                .modifier(DesktopClipboardBridge(session: session))
                .clipShape(.rect(cornerRadius: GlassWindowShape.spatialNestedCanvasCornerRadius, style: .continuous))
                .padding(GlassWindowShape.spatialNestedCanvasPadding(showsTitle: true, showsControls: true))
        } title: {
            Label(windowTitle, systemImage: "desktopcomputer")
                .font(.headline).lineLimit(1).padding(.horizontal, 20).padding(.vertical, 10)
        } controls: {
            nativeControls
        }
        .frame(minWidth: DesktopWindowAspect.spatialMinimum.width, minHeight: DesktopWindowAspect.spatialMinimum.height)
        .glassSpatialWindowGlass(strength: GlassWindowGlass.strength(frost: profile.frost,
                                                                     reduceTransparency: reduceTransparency))
        // W38: the window resizes only in its display's shape.
        .background {
            GlassWindowAspectLock(aspect: session.pictureAspect(for: viewport), chrome: DesktopWindowAspect.spatialChrome,
                                  minimum: DesktopWindowAspect.spatialMinimum)
        }
        // Shrinks into an orb with the remote screen live on its face (2026-10-15).
        .glassSessionOrb(GlassSessionOrbFace(title: windowTitle, symbolName: "display") { [session] in
            session.frame.flatMap(GlassDesktopCapability.picture(of:))
        })
        #else
        sessionContent
            .modifier(DesktopClipboardBridge(session: session))
            #if os(macOS)
            .frame(minWidth: DesktopWindowSizing.floor.width, minHeight: DesktopWindowSizing.floor.height)
            .background { DesktopWindowSizer(desktop: viewport.isPrimary ? session.connection.desktop : session.region(for: viewport).size) }
            .background {
                GlassWindowAspectLock(aspect: session.pictureAspect(for: viewport), canvas: canvasSize,
                                      minimum: DesktopWindowSizing.floor)
            }
            #endif
        #endif
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    ZStack {
                        DesktopMetalSurface(session: session, viewport: viewport, inputEnabled: remoteInputEnabled,
                                            keyboardTools: keyboardTools)
                        cursor(in: geometry.size)
                    }
                    #if os(visionOS)
                    .modifier(DesktopPinchProbe())
                    #endif
                    #if !os(visionOS)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : viewport.presentation.pitch), axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : viewport.presentation.yaw), axis: (x: 0, y: 1, z: 0))
                    #endif
                    // Only the remote image is zoomed and panned. The panels below must stay
                    // legible and inside the window whatever the image is doing.
                    .scaleEffect(viewport.presentation.zoom)
                    .offset(x: viewport.presentation.panX, y: viewport.presentation.panY)

                    if session.frame == nil {
                        // The system's own unavailable-content view, as Apple's apps say a thing is
                        // not there — not a panel of our own (the owner on the unfolded Duo,
                        // 2026-10-13: "This feels web, so of out of place").
                        connectionStatus
                            #if !os(visionOS)
                            // On the desktop's black, so its words are light.
                            .environment(\.colorScheme, .dark)
                            #endif
                    }
                }
                .onChange(of: geometry.size, initial: true) { _, size in
                    // Detail first: the size asked for is the window's at the window's scale.
                    session.apply(profile, to: viewport)
                    matchWindow(size)
                    canvasSize = size
                }
                .onChange(of: session.capabilities) { _, _ in matchWindow(geometry.size) }
                .onChange(of: session.isConnected) { _, value in if value { matchWindow(geometry.size) } }
                .onChange(of: session.matchWindow) { _, value in if value { matchWindow(geometry.size) } }
                .onChange(of: displayScale) { _, _ in matchWindow(geometry.size) }
            }
            .background {
                // visionOS: nothing. The window's own glass is behind the image, including
                // letterboxing (W28). An opaque backing would defeat desktop opacity.
                #if os(macOS)
                // The Mac's window is clear (`DesktopMetalSurface`), so it gets the same glass as the
                // headset whenever the desktop is see-through: faded, or with a colour removed. An
                // opaque desktop keeps its black letterbox (owner, 2026-09-30: "I don't have a
                // transparency setting here?").
                if session.frame == nil || (viewport.presentation.mode == .original && viewport.presentation.opacity >= 1) {
                    Color.black
                } else {
                    GlassCanvasBackdrop(blurAmount: profile.frost)
                }
                #elseif !os(visionOS)
                // Into every edge: on a phone on its side the system's controls keep a margin, and
                // it showed white beside the black (the unfolded Duo, 2026-10-13).
                if drawsBlackBackdrop { Color.black.ignoresSafeArea() }
                #endif
            }
            // Over a live picture only: without one, the status view says it (`connectionStatus`).
            if session.frame != nil, session.failurePresentation == nil, session.rendererError == nil,
               let error = session.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark") { session.errorMessage = nil }.labelStyle(.iconOnly)
                }
                .font(.callout).padding(12).background(.regularMaterial)
                .accessibilityElement(children: .contain).accessibilityLabel("Session error")
            }
            #if os(iOS)
            // One bar of controls at a time: while the keyboard is up its own bar has the keys, the
            // arrow pad and the tools (`DesktopKeyboardBar`), as a terminal's does.
            if !session.keyboardAccessoryShown { sessionStatusBar }
            #elseif os(macOS)
            sessionStatusBar
            #endif
        }
        .frame(minWidth: 320, idealWidth: 1280, maxWidth: .infinity, minHeight: 240, idealHeight: 800, maxHeight: .infinity)
        .navigationTitle(session.connection.name)
        #if os(iOS)
        // The name belongs in the bar beside the controls, not in a large title that costs the
        // desktop a band of screen on a phone.
        .navigationBarTitleDisplayMode(.inline)
        // The title sits over the desktop's black, not over a bar: in light mode it was black on
        // black (2026-10-15, as the terminal's tab switcher was). Light over the black; the system's
        // own where the page shows instead.
        .toolbarColorScheme(drawsBlackBackdrop ? .dark : nil, for: .navigationBar)
        #endif
        #if os(macOS)
        // A pinch in opens Show All Windows, as on a terminal (the desktop does not pinch to zoom).
        .glassShowAllWindowsOnPinch()
        #endif
        #if !os(visionOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) { sessionActions }
            #if os(macOS)
            // Show All Windows, beside the ⚡, as in every window (GlassShowAllWindows).
            ToolbarItem(placement: GlassActiveConnectionsToolbarModifier.placement) {
                GlassShowAllWindowsButton()
            }
            #endif
            if let showActiveConnections {
                // The trailing edge on every platform, after the session's own controls.
                ToolbarItem(placement: GlassActiveConnectionsToolbarModifier.placement) {
                    GlassActiveConnectionsButton { session.releaseInput(); showActiveConnections() }
                }
            }
        }
        #endif
        .onChange(of: session.failurePresentation, initial: false) { _, failure in
            // A panel the user must read should not be hidden behind the keyboard.
            if failure != nil { session.wantsKeyboard = false }
        }
        .task {
            session.apply(profile, to: viewport)
            #if DEBUG
            if session.demoOpensSettings {
                // Screenshots: This Window over the window it changes, once the window is up.
                session.demoOpensSettings = false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    settingsSection = session.demoOpensConnection ? .connection : .thisWindow
                    showDisplayOptions = true
                }
            }
            #endif
            // A display window joins the connection its desktop's window opened (W30).
            if viewport.isPrimary { await session.start() }
        }
        // A setting changed here, in All Desktops, or by Reduce Transparency: drawn at once.
        .onChange(of: profile) { _, value in session.apply(value, to: viewport) }
        // W30: this window onto the session, for as long as it is open; the session ends with the
        // last. A window in the background asks the server for nothing.
        .onAppear { session.attach(viewport) }
        .onChange(of: scenePhase, initial: true) { _, phase in viewport.isOnScreen = phase != .background }
        // A window for each display: the lead window opens them when the layout arrives.
        .onChange(of: session.displayWindowRequests, initial: true) { _, requests in
            guard isLead, !requests.isEmpty, GlassWindowPresentation.canOpenWindows else { return }
            for display in session.takeDisplayWindowRequests() {
                openWindow(id: DesktopDisplayWindowValue.windowID,
                           value: DesktopDisplayWindowValue(endpoint: session.connection.id.rawValue, display: display))
            }
        }
        .sheet(isPresented: $showDisplayOptions, onDismiss: {
            if requestWallpaperAfterDisplay {
                requestWallpaperAfterDisplay = false
                chooseWallpaper = true
            }
        }) {
            // Laid out as every window's Settings sheet is (W27): title, Done, one size. Original,
            // which was a toolbar button here, is on This Window, under Presentation.
            GlassSettingsSheet("Desktop Settings", doneIdentifier: "session.display.done",
                               done: { showDisplayOptions = false }) {
                displayOptions
            }
        }
        .onDisappear { alerts = DesktopSessionAlertPresentation(); session.detach(viewport) }
        .onChange(of: session.shouldClosePresentation) { _, shouldClose in
            if shouldClose { if let onClose { onClose() } else { dismiss() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.releaseInput() } }
        #if os(macOS)
        // A Mac going to sleep is not a scene-phase change, and a key held at that moment would
        // stay down on the remote computer until the session ended (B-X25).
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            session.releaseInput()
        }
        #endif
        // Report once, when the session genuinely reaches a terminal state. `.connecting` is not
        // an outcome and neither is having opened a window.
        .onChange(of: session.state) { _, state in
            switch state {
            case .connected, .failed: onOutcome?(state)
            default: break
            }
        }
        .sheet(isPresented: Binding(
            get: { session.needsCredentials && isLead },
            set: { if !$0 && session.needsCredentials { session.cancelCredentialEntry() } }
        ), onDismiss: {
            alerts.credentialSheetDidDismiss()
            presentCurrentAlert()
        }) {
            credentials.onAppear { alerts.credentialSheetRequested() }
        }
        .onChange(of: session.needsCredentials, initial: true) { _, requested in
            // A false request starts dismissal; only onDismiss ends this gate.
            if requested { alerts.credentialSheetRequested() }
        }
        .sheet(isPresented: $showTextInput) {
            RemoteTextEntry { session.sendText($0) }
                #if os(visionOS)
                .presentationBreakthroughEffect(.prominent)
                #endif
        }
        .fileImporter(isPresented: $chooseWallpaper, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): Task { await session.importWallpaper(from: url) }
            case .failure(let error): session.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: session.trustRequest, initial: true) { _, _ in presentCurrentAlert() }
        .onChange(of: session.rendererError, initial: true) { _, _ in presentCurrentAlert() }
        .alert(alerts.active?.title ?? "Session", isPresented: Binding(
            get: { alerts.active != nil },
            set: { if !$0 { dismissPresentedAlert() } }
        ), presenting: alerts.active) { presented in
            switch presented {
            case .trust(let request):
                if request.certificate.sha256 != nil {
                    Button("Trust and Reconnect") {
                        // SwiftUI may clear presentation state before invoking
                        // an action. Approve this immutable challenge snapshot.
                        Task { await session.approveCertificate(request) }
                    }.accessibilityIdentifier("session.trust.approve")
                }
                Button("Cancel", role: .cancel) { session.cancelTrustRequest(request) }
                    .accessibilityIdentifier("session.trust.cancel")
            case .display:
                Button("OK") {}
            }
        } message: { presented in
            switch presented {
            case .trust(let request):
                Text("The certificate for \(request.certificate.host):\(String(request.certificate.port)) was not accepted. Verify its SHA-256 fingerprint with the computer's administrator before trusting it.\n\n\(request.certificate.sha256 ?? "Fingerprint unavailable")")
            case .display(let message): Text(message)
            }
        }
    }

    private var remoteInputEnabled: Bool {
        !showDisplayOptions && !showTextInput && !chooseWallpaper && !session.needsCredentials && alerts.active == nil
    }

    #if os(visionOS)
    /// The window's controls as separate items of Apple's toolbar ornament (`GlassNativeWindowFrame`),
    /// which sizes and spaces them and draws the capsule, so the bar is the size of every other
    /// window's (W31). No stack, spacing or padding of their own: a stack would be one item.
    @ViewBuilder private var nativeControls: some View {
        Group {
            sessionActions
            Divider().frame(height: 24)
            // The terminal's keys and cursor pad, for a desktop (2026-10-11); Escape and Tab are the
            // Keys menu's first two, so they have no buttons of their own.
            DesktopKeysMenu(session: session, typeText: { session.releaseInput(); showTextInput = true })
            DesktopArrowPad(session: session)
            // Last, as the ⚡ is on the trailing edge of every toolbar (2026-10-05).
            if let showActiveConnections {
                Divider().frame(height: 24)
                GlassActiveConnectionsButton { session.releaseInput(); showActiveConnections() }
            }
        }
    }
    #endif

    private var sessionStatusBar: some View {
        HStack(spacing: 12) {
                Circle().fill(session.isConnected ? .green : .secondary).frame(width: 6, height: 6)
                Text(session.status).lineLimit(1)
                // What this window is sent (W38): its own connection's picture, or its part of the
                // desktop's. Not on a phone, where it wrapped onto three lines beside the rest.
                if !compactScreen, let sending = session.sending(for: viewport) {
                    Text(sending).monospacedDigit().lineLimit(1).accessibilityIdentifier("session.sending")
                }
                if session.isConnected,
                   let statistics = session.ownConnection(for: viewport)?.linkStatistics ?? session.linkStatistics {
                    Text(DesktopLinkReadout.line(statistics)).monospacedDigit().lineLimit(1)
                        .accessibilityIdentifier("session.readout")
                }
                Spacer(minLength: 4)
                // Escape and Tab are the Keys menu's first two, and on the Mac so is Type Text.
                #if os(iOS)
                // Symbols only on a phone, as the keyboard's own bar has them.
                if compactScreen {
                    DesktopKeysMenu(session: session).labelStyle(.iconOnly)
                } else {
                    DesktopKeysMenu(session: session)
                }
                #else
                DesktopKeysMenu(session: session, typeText: { session.releaseInput(); showTextInput = true })
                #endif
                #if os(iOS)
                DesktopArrowPad(session: session)
                // Asked for again, even when it was asked for before and put away since: the keyboard's
                // own bar hides it, and this bar steps aside while that one is up.
                Button("Keyboard", systemImage: "keyboard") {
                    session.wantsKeyboard = false
                    session.wantsKeyboard = true
                }
                    .labelStyle(.iconOnly)
                    .disabled(!session.isConnected)
                    .accessibilityIdentifier("session.keyboard")
                #endif
            }
            .font(.caption).padding(10)
        #if !os(visionOS)
        .background(.regularMaterial)
        #endif
    }

    /// The window's tools in the bar above the software keyboard, which covers the status bar on an
    /// iPhone and an iPad, as a terminal's Tools menu does there. A Vision Pro keeps its toolbar.
    private var keyboardTools: AnyView? {
        #if os(iOS)
        AnyView(sessionActions)
        #else
        nil
        #endif
    }

    @ViewBuilder private var sessionActions: some View {
                Button("Settings", systemImage: "gearshape") {
                    session.releaseInput()
                    // Each opening starts on This Window, as a terminal's Settings does.
                    if !showDisplayOptions { settingsSection = .thisWindow }
                    showDisplayOptions.toggle()
                }
                    // On Vision Pro the toolbar draws it as an icon itself; set there, the style
                    // made it a narrower item than its neighbours (W31).
                    #if !os(visionOS)
                    .labelStyle(.iconOnly)
                    #endif
                    .help("Settings")
                    .accessibilityIdentifier("session.display")
                    .accessibilityValue(showDisplayOptions ? "Open" : "Closed")

                Menu("Clipboard", systemImage: "document.on.clipboard") {
                    if !session.connection.clipboardEnabled {
                        // Off unless the service shares it — said here, rather than leaving the remote
                        // clipboard grey for no reason anyone can see (the owner, 2026-10-13: "the
                        // clipboard sync is failing with <a desktop> … Not sure if I was supposed to do something").
                        Text("Clipboard sharing is off for this desktop. Turn on Share clipboard in its service settings, then reconnect.")
                    }
                    if session.connection.clipboardEnabled {
                        // Copies crossing by themselves, or only when asked (the owner, 2026-10-14).
                        Toggle("Sync Automatically", isOn: Binding(
                            get: { session.connection.clipboardSyncsAutomatically },
                            set: { syncs in Task { await session.setClipboardSyncsAutomatically(syncs) } }))
                        Divider()
                    }
                    Button(session.connection.clipboardEnabled ? "Send Clipboard" : "Type Clipboard Text") { sendClipboard() }
                        .disabled(!session.isConnected)
                    Button("Copy Remote Clipboard") { copyRemoteClipboard() }.disabled(!session.isConnected || session.remoteClipboard == nil)
                    Button("Control–Alt–Delete") { session.sendSecureAttention() }.disabled(!session.isConnected)
                }.help("Clipboard")
                // Displays and Quality were menus of their own here; both are in Settings ▸ This
                // Window, and the toolbar was getting busy (the owner, 2026-10-11).
    }

    /// What stands where the desktop will be: the system's spinner while it signs in or waits for
    /// the first picture, and otherwise the system's unavailable-content view — the state, the
    /// reason, and what to do. The error that would have been a banner below is its description.
    @ViewBuilder private var connectionStatus: some View {
        if let failure = session.failurePresentation {
            ContentUnavailableView {
                Label(failure.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.message)
            } actions: {
                Button("Reconnect") { Task { await session.reconnect() } }.buttonStyle(.borderedProminent)
                Button("Enter Credentials") { Task { await session.requestCredentials() } }
                    .disabled(session.isApprovingCertificate)
                Button("Close") { session.close() }
                DisclosureGroup("Technical Details") {
                    ScrollView { Text(failure.details).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 120)
                }
                .frame(maxWidth: 480)
            }
        } else if session.state == .connecting || session.state == .connected {
            VStack(spacing: 20) {
                ProgressView { Text(session.status) }.controlSize(.large)
                // Signed in and still no picture: a way out other than leaving.
                if session.state == .connected, !session.needsCredentials {
                    Button("Reconnect") { Task { await session.reconnect() } }.buttonStyle(.bordered)
                }
            }
        } else {
            ContentUnavailableView {
                Label(session.status, systemImage: "desktopcomputer")
            } description: {
                if let error = session.errorMessage { Text(error) }
            } actions: {
                if !session.needsCredentials {
                    Button("Reconnect") { Task { await session.reconnect() } }.buttonStyle(.borderedProminent)
                    Button("Enter Credentials") { Task { await session.requestCredentials() } }
                        .disabled(session.isApprovingCertificate)
                }
            }
        }
    }

    private func presentCurrentAlert() {
        // One window asks: the session's questions are not each display window's (W30).
        guard isLead else { return }
        alerts.presentCurrent(trust: session.trustRequest, displayError: session.rendererError,
                              credentialsRequested: session.needsCredentials)
    }

    private func dismissPresentedAlert() {
        // Clear exactly what was displayed. A newer trust request or renderer
        // error must remain available for the next presentation.
        switch alerts.dismiss() {
        case .trust(let request): session.dismissTrustRequest(request)
        case .display(let error):
            if session.rendererError == error { session.rendererError = nil }
        case nil: return
        }
        // Give the native presenter a dismissal turn, then read current model
        // state. Requests superseded meanwhile are never reintroduced.
        Task { @MainActor in
            await Task.yield()
            presentCurrentAlert()
        }
    }

    private var displayOptions: some View {
        Group {
            #if os(iOS)
            List {
                ForEach(DesktopSessionSettingsSection.offered(for: session), id: \.self) { section in
                    NavigationLink(section.title) {
                        settingsForm(section).navigationTitle(section.title)
                    }
                }
            }
            #else
            GlassSettingsSections(selection: $settingsSection,
                options: DesktopSessionSettingsSection.offered(for: session),
                title: { $0.title }, pickerIdentifier: "desktop.settings.section") { section in
                settingsForm(section)
            }
            #endif
        }
    }

    @ViewBuilder private func settingsForm(_ section: DesktopSessionSettingsSection) -> some View {
        switch section {
        case .thisWindow:
            DesktopWindowSettingsView(session: session, viewport: viewport, defaults: allDesktops.defaults, compactScreen: compactScreen) {
                requestWallpaperAfterDisplay = true
                showDisplayOptions = false
            }
        case .connection:
            // W30: Display Windows, Quality and what the link carries now; every window's the same.
            DesktopConnectionSettingsView(session: session, defaults: allDesktops.defaults)
        case .allDesktops:
            // Settings ▸ Desktops itself: what every window follows until it sets its own.
            DesktopSettingsView()
        }
    }

    /// Whether the remote pointer is on the display this window shows (W30): a host's pointer is
    /// drawn in the window of the display it is on, and only there — where the host reports it
    /// (W38), else where this app last put it.
    private var pointerIsShown: Bool {
        session.pointerPosition == nil ? viewport.isPrimary : session.pointerInPicture(for: viewport) != nil
    }

    @ViewBuilder private func cursor(in size: CGSize) -> some View {
        // The window's picture: its own connection's (W38), or its part of the desktop's.
        let region = session.pictureRegion(for: viewport)
        let scale = min(size.width / Double(max(1, region.size.width)), size.height / Double(max(1, region.size.height)))
        if session.cursorVisible, session.isConnected, session.cursorBitmap == nil || session.cursorImage == nil,
           viewport.pointerMode == .trackpad, let absolute = session.pointerInPicture(for: viewport) {
            // Relative pointing is unusable without seeing the pointer, and a host does not always
            // send one. Draw a stand-in so the cursor is never invisible while a finger steers it.
            let local = DesktopPoint(x: absolute.x - region.origin.x, y: absolute.y - region.origin.y)
            Image(systemName: "cursorarrow")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.85), radius: 1)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .position(x: (size.width - Double(region.size.width) * scale) / 2 + Double(local.x) * scale + 6,
                          y: (size.height - Double(region.size.height) * scale) / 2 + Double(local.y) * scale + 8)
                .allowsHitTesting(false).accessibilityHidden(true)
                .accessibilityIdentifier("session.pointer")
        }
        if session.cursorVisible, let bitmap = session.cursorBitmap, let image = session.cursorImage, session.isConnected,
           pointerIsShown {
            let desktop = region.size
            let fallback = DesktopPoint(x: region.origin.x + desktop.width / 2, y: region.origin.y + desktop.height / 2)
            let absolute = session.pointerInPicture(for: viewport) ?? fallback
            let pointer = DesktopPoint(x: absolute.x - region.origin.x, y: absolute.y - region.origin.y)
            // A Mac's pointer is in its points: on a Retina display sent at its own pixels it covers
            // twice its pixel count, so it is drawn at the size the Mac shows it (W38).
            let drawn = scale * session.cursorPictureScale(for: viewport)
            Image(decorative: image, scale: 1).interpolation(drawn == scale ? .none : .medium).resizable()
                .frame(width: Double(bitmap.width) * drawn, height: Double(bitmap.height) * drawn)
                .position(x: (size.width - Double(desktop.width) * scale) / 2 + Double(pointer.x) * scale
                              + (Double(bitmap.width) / 2 - Double(bitmap.hotSpotX)) * drawn,
                          y: (size.height - Double(desktop.height) * scale) / 2 + Double(pointer.y) * scale
                              + (Double(bitmap.height) / 2 - Double(bitmap.hotSpotY)) * drawn)
                .allowsHitTesting(false).accessibilityHidden(true)
                .accessibilityIdentifier("session.cursor")
        }
    }

    private var credentials: some View {
        CredentialPrompt(name: session.connection.name, initialUsername: session.connection.username,
                         protocol: session.connection.protocol,
                         errorMessage: session.errorMessage, submitting: session.isSubmittingCredentials,
                         onCancel: { session.cancelCredentialEntry() }) { username, password, remember in
            Task { await session.submitCredentials(username: username, password: password, remember: remember) }
        }
    }

    private func sendClipboard() {
        if let content = DesktopPasteboard.read() { session.pasteClipboard(content) }
    }
    private func copyRemoteClipboard() {
        guard session.isConnected, let content = session.remoteClipboard else { return }
        DesktopPasteboard.write(content)
    }

}

private struct CredentialPrompt: View {
    let name: String
    let `protocol`: DesktopProtocol
    let onConnect: (String, String, Bool) -> Void
    let onCancel: () -> Void
    let errorMessage: String?
    let submitting: Bool
    @State private var username: String
    @State private var password = ""
    @State private var remember = false
    init(name: String, initialUsername: String, protocol: DesktopProtocol = .rdp, errorMessage: String?, submitting: Bool,
         onCancel: @escaping () -> Void, onConnect: @escaping (String, String, Bool) -> Void) {
        self.name = name; self.protocol = `protocol`; self.onConnect = onConnect; self.onCancel = onCancel
        self.errorMessage = errorMessage; self.submitting = submitting
        _username = State(initialValue: initialUsername)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField(`protocol` == .vnc ? "Mac user name (optional)" : "Username", text: $username).autocorrectionDisabled()
                    .accessibilityIdentifier("session.credentials.username")
                SecureField(`protocol` == .vnc && username.isEmpty ? "VNC password" : "Password", text: $password)
                    .accessibilityIdentifier("session.credentials.password")
                Toggle("Save in Keychain", isOn: $remember)
                if `protocol` == .vnc {
                    Text("Enter a Mac user name and password for Apple Screen Sharing, or only the VNC password when the host allows VNC viewers with a password.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary).textSelection(.enabled) }
            }.disabled(submitting).formStyle(.grouped).navigationTitle("Connect to \(name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { onConnect(username, password, remember) }
                        .accessibilityIdentifier("session.credentials.connect")
                        .disabled(submitting || (`protocol` == .rdp && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                  || (`protocol` == .vnc && password.isEmpty))
                }
            }.frame(minWidth: 300, idealWidth: 400, minHeight: 240)
        }.onDisappear { password = "" }
    }
}

private struct RemoteTextEntry: View {
    let onSend: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).padding().navigationTitle("Send Text")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Send") { onSend(text); text = ""; dismiss() }.disabled(text.isEmpty) }
                }.frame(minWidth: 300, idealWidth: 450, minHeight: 240)
        }
    }
}


/// Desktop Settings' pages (W25): the window's own settings first, then every window's — the
/// shape of a terminal's Settings (This Window, All Terminals). Between them (W30), the desktop's
/// connection, which all its windows share: offered for VNC and for a host with several displays.
private enum DesktopSessionSettingsSection: CaseIterable, Hashable {
    case thisWindow, connection, allDesktops
    var title: String {
        switch self {
        case .thisWindow: "This Window"
        case .connection: "Connection"
        case .allDesktops: "All Desktops"
        }
    }

    @MainActor static func offered(for session: DesktopSessionModel) -> [Self] {
        allCases.filter { $0 != .connection || DesktopConnectionSettingsView.isOffered(for: session) }
    }
}

#if os(macOS)
/// Finds the session's window and, if it opened at the floor, gives it the configured desktop
/// (`DesktopWindowSizing`). Zero-size and non-hit-testing, the shape of `GlassWindowLayerReader`.
/// Once per window: a user who then shrinks it is not fought.
private struct DesktopWindowSizer: NSViewRepresentable {
    let desktop: DesktopSize

    func makeNSView(context: Context) -> SizerView { SizerView() }
    func updateNSView(_ view: SizerView, context: Context) { view.desktop = desktop }

    final class SizerView: NSView {
        var desktop = DesktopSize.standard
        /// Two looks at most — after attaching and on first becoming key — so a window the user
        /// later shrinks to the floor on purpose is not grown back every time it is focused.
        private var looks = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            guard let window else { return }
            // The remembered frame lands after the content is attached: look after this turn, and
            // once more when the window becomes key, in case it landed later still.
            DispatchQueue.main.async { [weak self] in self?.sizeIfAtFloor() }
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
        }

        @objc private func windowBecameKey(_ notification: Notification) { sizeIfAtFloor() }

        private func sizeIfAtFloor() {
            guard looks < 2, let window, let content = window.contentView else { return }
            looks += 1
            guard DesktopWindowSizing.isAtFloor(content.frame.size) else { return }
            looks = 2
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let chrome = CGSize(width: window.frame.width - content.frame.width,
                                height: window.frame.height - content.frame.height)
            let target = DesktopWindowSizing.contentSize(
                desktop: desktop,
                available: CGSize(width: visible.width - chrome.width, height: visible.height - chrome.height))
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
            // Keep the top-left where it was, and the whole window on the screen.
            frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: true, animate: false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
