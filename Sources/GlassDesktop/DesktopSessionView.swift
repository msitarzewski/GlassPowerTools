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
    @State private var session: DesktopSessionModel
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
        _session = State(initialValue: DesktopSessionModel(connection: connection, app: app))
    }

    /// A session built elsewhere: the simulator fixture, and the screenshot demo.
    #if DEBUG
    init(previewSession: DesktopSessionModel, showActiveConnections: (@MainActor () -> Void)? = nil) {
        onClose = nil
        onOutcome = nil
        self.showActiveConnections = showActiveConnections
        _session = State(initialValue: previewSession)
    }
    #endif

    public var body: some View {
        window
            // The window's own settings (W25), for everything drawn in it: GlassLayers' contract.
            // This view is the window's root and its settings' owner, so it resolves them from the
            // session it hands down (`profile`); what it presents reads them from here.
            .glassWindowOverrides(session.windowSettings)
    }

    /// What this window draws and drives with: its own settings over All Desktops' (W25).
    private var profile: DesktopWindowProfile {
        DesktopWindowProfile(window: session.windowSettings, defaults: allDesktops.defaults,
                             compactScreen: compactScreen, reduceTransparency: reduceTransparency)
    }

    private var compactScreen: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder private var window: some View {
        #if os(visionOS)
        GlassNativeWindowFrame {
            sessionContent
                .modifier(DesktopClipboardBridge(session: session))
                .padding(10)
                .background {
                    GlassCanvasBackdrop(blurAmount: profile.frost)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 24))
        } title: {
            Label(session.connection.name, systemImage: "desktopcomputer")
                .font(.headline).lineLimit(1).padding(.horizontal, 20).padding(.vertical, 10)
        } controls: {
            nativeControls
        }
        .frame(minWidth: 800, minHeight: 440)
        #else
        sessionContent
            .modifier(DesktopClipboardBridge(session: session))
            #if os(macOS)
            .frame(minWidth: DesktopWindowSizing.floor.width, minHeight: DesktopWindowSizing.floor.height)
            .background { DesktopWindowSizer(desktop: session.connection.desktop) }
            #endif
        #endif
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    ZStack {
                        DesktopMetalSurface(session: session, inputEnabled: remoteInputEnabled)
                        cursor(in: geometry.size)
                    }
                    #if os(visionOS)
                    .modifier(DesktopPinchProbe())
                    #endif
                    #if !os(visionOS)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : session.presentation.pitch), axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : session.presentation.yaw), axis: (x: 0, y: 1, z: 0))
                    #endif
                    // Only the remote image is zoomed and panned. The panels below must stay
                    // legible and inside the window whatever the image is doing.
                    .scaleEffect(session.presentation.zoom)
                    .offset(x: session.presentation.panX, y: session.presentation.panY)

                    if session.frame == nil {
                        connectionStatus
                            .padding(28).frame(maxWidth: 520)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .padding(12)
                    }
                }
                .onChange(of: geometry.size, initial: true) { _, size in
                    // Detail first: the size asked for is the window's at the window's scale.
                    session.apply(profile)
                    session.resize(width: size.width, height: size.height, displayScale: displayScale)
                }
                .onChange(of: session.capabilities) { _, _ in session.resize(width: geometry.size.width, height: geometry.size.height, displayScale: displayScale) }
                .onChange(of: session.isConnected) { _, value in if value { session.resize(width: geometry.size.width, height: geometry.size.height, displayScale: displayScale) } }
                .onChange(of: session.matchWindow) { _, value in if value { session.resize(width: geometry.size.width, height: geometry.size.height, displayScale: displayScale) } }
                .onChange(of: displayScale) { _, _ in session.resize(width: geometry.size.width, height: geometry.size.height, displayScale: displayScale) }
            }
            .background {
                // visionOS uses the shared frost behind the image, including
                // letterboxing. An opaque backing would defeat desktop opacity.
                #if os(macOS)
                // The Mac's window is clear (`DesktopMetalSurface`), so it gets the same glass as the
                // headset whenever the desktop is see-through: faded, or with a colour removed. An
                // opaque desktop keeps its black letterbox (owner, 2026-09-30: "I don't have a
                // transparency setting here?").
                if session.frame == nil || (session.presentation.mode == .original && session.presentation.opacity >= 1) {
                    Color.black
                } else {
                    GlassCanvasBackdrop(blurAmount: profile.frost)
                }
                #elseif !os(visionOS)
                if session.frame == nil || session.presentation.mode == .original { Color.black }
                #endif
            }
            if session.failurePresentation == nil, session.rendererError == nil, let error = session.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark") { session.errorMessage = nil }.labelStyle(.iconOnly)
                }
                .font(.callout).padding(12).background(.regularMaterial)
                .accessibilityElement(children: .contain).accessibilityLabel("Session error")
            }
            #if !os(visionOS)
            sessionStatusBar
            #endif
        }
        .frame(minWidth: 320, idealWidth: 1280, maxWidth: .infinity, minHeight: 240, idealHeight: 800, maxHeight: .infinity)
        .navigationTitle(session.connection.name)
        #if os(iOS)
        // The name belongs in the bar beside the controls, not in a large title that costs the
        // desktop a band of screen on a phone.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(visionOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) { sessionActions }
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
            session.apply(profile)
            #if DEBUG
            if session.demoOpensSettings {
                // Screenshots: This Window over the window it changes, once the window is up.
                session.demoOpensSettings = false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    settingsSection = .thisWindow
                    showDisplayOptions = true
                }
            }
            #endif
            await session.start()
        }
        // A setting changed here, in All Desktops, or by Reduce Transparency: drawn at once.
        .onChange(of: profile) { _, value in session.apply(value) }
        .sheet(isPresented: $showDisplayOptions, onDismiss: {
            if requestWallpaperAfterDisplay {
                requestWallpaperAfterDisplay = false
                chooseWallpaper = true
            }
        }) {
            NavigationStack {
                displayOptions
                    .navigationTitle("Desktop Settings")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showDisplayOptions = false }
                                .accessibilityIdentifier("session.display.done")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            // The complete image, in this window: its own Presentation and Opacity.
                            Button("Original") { session.windowSettings.showDesktopOriginal() }
                                .accessibilityIdentifier("display.glass.original")
                                .disabled(profile.backgroundRemoval == .original && profile.opacity == 1)
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.large])
            #else
            .frame(width: 760, height: 560)
            #endif
        }
        .onDisappear { alerts = DesktopSessionAlertPresentation(); session.close() }
        .onChange(of: session.shouldClosePresentation) { _, shouldClose in
            if shouldClose { if let onClose { onClose() } else { dismiss() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.releaseInput() } }
        // Report once, when the session genuinely reaches a terminal state. `.connecting` is not
        // an outcome and neither is having opened a window.
        .onChange(of: session.state) { _, state in
            switch state {
            case .connected, .failed: onOutcome?(state)
            default: break
            }
        }
        .sheet(isPresented: Binding(
            get: { session.needsCredentials },
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
    private var nativeControls: some View {
        HStack(spacing: 16) {
            sessionActions
            Divider().frame(height: 24)
            Button("Escape", systemImage: "escape") { session.sendKey(0x01) }
                .help("Send Escape").disabled(!session.isConnected)
            Button("Tab", systemImage: "arrow.right.to.line") { session.sendKey(0x0f) }
                .help("Send Tab").disabled(!session.isConnected)
            Button("Input", systemImage: "keyboard") { session.releaseInput(); showTextInput = true }
                .help("Send Text").disabled(!session.isConnected)
            // Last, as the ⚡ is on the trailing edge of every toolbar (2026-10-05).
            if let showActiveConnections {
                Divider().frame(height: 24)
                GlassActiveConnectionsButton { session.releaseInput(); showActiveConnections() }
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.controls")
    }
    #endif

    private var sessionStatusBar: some View {
        HStack(spacing: 12) {
                Circle().fill(session.isConnected ? .green : .secondary).frame(width: 6, height: 6)
                Text(session.status)
                if let frame = session.frame { Text("\(frame.width) × \(frame.height)").monospacedDigit() }
                Spacer()
                Button("Esc") { session.sendKey(0x01) }.disabled(!session.isConnected)
                Button("Tab") { session.sendKey(0x0f) }.disabled(!session.isConnected)
                #if os(iOS)
                Button(session.wantsKeyboard ? "Hide Keyboard" : "Keyboard", systemImage: "keyboard") {
                    session.wantsKeyboard.toggle()
                }
                .disabled(!session.isConnected)
                .accessibilityIdentifier("session.keyboard")
                #else
                Button("Input", systemImage: "keyboard") { session.releaseInput(); showTextInput = true }.disabled(!session.isConnected)
                #endif
            }
            .font(.caption).padding(10)
        #if !os(visionOS)
        .background(.regularMaterial)
        #endif
    }

    @ViewBuilder private var sessionActions: some View {
                Button("Settings", systemImage: "gearshape") {
                    session.releaseInput()
                    // Each opening starts on This Window, as a terminal's Settings does.
                    if !showDisplayOptions { settingsSection = .thisWindow }
                    showDisplayOptions.toggle()
                }
                    .labelStyle(.iconOnly)
                    .help("Settings")
                    .accessibilityIdentifier("session.display")
                    .accessibilityValue(showDisplayOptions ? "Open" : "Closed")

                Menu("Clipboard", systemImage: "document.on.clipboard") {
                    Button(session.connection.clipboardEnabled ? "Send Clipboard" : "Type Clipboard Text") { sendClipboard() }
                        .disabled(!session.isConnected)
                    Button("Copy Remote Clipboard") { copyRemoteClipboard() }.disabled(!session.isConnected || session.remoteClipboard == nil)
                    Button("Control–Alt–Delete") { session.sendSecureAttention() }.disabled(!session.isConnected)
                }.help("Clipboard")
    }

    @ViewBuilder private var connectionStatus: some View {
        if let failure = session.failurePresentation {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(failure.title).font(.title2)
                Text(failure.message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Reconnect") { Task { await session.reconnect() } }.buttonStyle(.borderedProminent)
                    Button("Close") { session.close() }.buttonStyle(.bordered)
                }
                Button("Enter Credentials") { Task { await session.requestCredentials() } }
                    .disabled(session.isApprovingCertificate)
                DisclosureGroup("Technical Details") {
                    ScrollView { Text(failure.details).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 120)
                }
            }
        } else {
            VStack(spacing: 16) {
                if session.state == .connecting || session.state == .connected { ProgressView() }
                Image(systemName: "desktopcomputer").font(.largeTitle)
                Text(session.status).font(.title2)
                if session.state != .connecting && !session.needsCredentials {
                    Button("Reconnect") { Task { await session.reconnect() } }.buttonStyle(.borderedProminent)
                    Button("Enter Credentials") { Task { await session.requestCredentials() } }
                        .disabled(session.isApprovingCertificate)
                }
            }
        }
    }

    private func presentCurrentAlert() {
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
                ForEach(DesktopSessionSettingsSection.allCases, id: \.self) { section in
                    NavigationLink(section.title) {
                        settingsForm(section).navigationTitle(section.title)
                    }
                }
            }
            #else
            GlassSettingsSections(selection: $settingsSection,
                options: DesktopSessionSettingsSection.allCases,
                title: { $0.title }, pickerIdentifier: "desktop.settings.section") { section in
                settingsForm(section)
            }
            #endif
        }
    }

    @ViewBuilder private func settingsForm(_ section: DesktopSessionSettingsSection) -> some View {
        switch section {
        case .thisWindow:
            DesktopWindowSettingsView(session: session, defaults: allDesktops.defaults, compactScreen: compactScreen) {
                requestWallpaperAfterDisplay = true
                showDisplayOptions = false
            }
        case .allDesktops:
            // Settings ▸ Desktops itself: what every window follows until it sets its own.
            DesktopSettingsView()
        }
    }

    @ViewBuilder private func cursor(in size: CGSize) -> some View {
        if session.cursorVisible, session.isConnected, session.cursorBitmap == nil || session.cursorImage == nil,
           session.pointerMode == .trackpad, let absolute = session.pointerPosition {
            // Relative pointing is unusable without seeing the pointer, and a host does not always
            // send one. Draw a stand-in so the cursor is never invisible while a finger steers it.
            let region = session.visibleRegion
            let scale = min(size.width / Double(region.size.width), size.height / Double(region.size.height))
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
        if session.cursorVisible, let bitmap = session.cursorBitmap, let image = session.cursorImage, session.isConnected {
            let region = session.visibleRegion
            let desktop = region.size
            let scale = min(size.width / Double(desktop.width), size.height / Double(desktop.height))
            let fallback = DesktopPoint(x: region.origin.x + desktop.width / 2, y: region.origin.y + desktop.height / 2)
            let absolute = session.pointerPosition ?? fallback
            let pointer = DesktopPoint(x: absolute.x - region.origin.x, y: absolute.y - region.origin.y)
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
                .frame(width: Double(bitmap.width) * scale, height: Double(bitmap.height) * scale)
                .position(x: (size.width - Double(desktop.width) * scale) / 2 + Double(pointer.x - bitmap.hotSpotX + bitmap.width / 2) * scale,
                          y: (size.height - Double(desktop.height) * scale) / 2 + Double(pointer.y - bitmap.hotSpotY + bitmap.height / 2) * scale)
                .allowsHitTesting(false).accessibilityHidden(true)
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
/// shape of a terminal's Settings (This Window, All Terminals).
private enum DesktopSessionSettingsSection: CaseIterable, Hashable {
    case thisWindow, allDesktops
    var title: String { self == .thisWindow ? "This Window" : "All Desktops" }
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
