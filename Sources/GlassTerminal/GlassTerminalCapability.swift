//
//  GlassTerminalCapability.swift
//  Glass Power Tools — GlassTerminal
//
//  The SSH capability's public surface: the runtime the app owns, the capability the shell routes
//  Connect through, and the bootstrap wrapper that hosts glas.sh's startup, deep-link, trust and
//  connect flows around the shell's library. Everything else in this module stays internal.
//

import SwiftUI
import GlassConnectionKit
import GlassShell
import GlassLayers

/// What the shell asked the terminal to open.
public enum GlassTerminalOpenPurpose: Sendable { case terminal, sftp }

/// Owns glas.sh's managers for the process. One per app, created in the composition root.
@MainActor @Observable
public final class GlassTerminalRuntime {
    let sessionManager: SessionManager
    let settingsManager: SettingsManager
    let windowRecoveryManager: WindowRecoveryManager

    /// Everything the library, the command palette, the workgroup and Tailscale surfaces and the
    /// shell can ask the terminal to do. One queue, consumed by `TerminalConnectFlow`, so the
    /// legacy-algorithm confirmation, trust prompt and password fallback exist exactly once.
    enum Request {
        case connect(serverID: UUID, purpose: TerminalSession.Purpose)
        case quickConnect(ServerConfiguration, password: String)
        case openWorkgroup(LayoutPreset)
        case addServer(draft: ServerConfiguration?)
        case editServer(ServerConfiguration)
        case serverInfo(ServerConfiguration)
        case deleteServer(ServerConfiguration)
        case localTerminal
        case showWorkgroups
        case showTailscale
    }
    struct SetupRequest: Identifiable {
        let host: HostProfile
        let service: HostServiceLink
        var id: EndpointID { service.endpointID }
    }

    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []
    var setupRequest: SetupRequest?

    /// The one layering state; the terminal's canvas appearance reads and writes it through
    /// `SettingsManager` so no second material system exists.
    public let layers: GlassLayerStore

    public init(layers: GlassLayerStore? = nil) {
        let layers = layers ?? GlassLayerStore()
        self.layers = layers
        sessionManager = SessionManager(loadImmediately: false)
        settingsManager = SettingsManager(loadImmediately: false, layers: layers)
        windowRecoveryManager = WindowRecoveryManager()
    }

    /// Connect to the saved server whose id is the shell's endpoint id. Consumed by the bootstrap.
    public func requestConnect(serverID: UUID, purpose: GlassTerminalOpenPurpose = .terminal) {
        enqueue(.connect(serverID: serverID, purpose: purpose == .sftp ? .sftp : .terminal))
    }
    /// Open a saved workgroup preset (all of its terminals) through the launch plan.
    public func requestOpenWorkgroup(_ presetID: UUID) {
        guard let preset = settingsManager.layoutPresets.first(where: { $0.id == presetID }) else { return }
        enqueue(.openWorkgroup(preset))
    }
    /// glas.sh's server form, empty or pre-filled (Tailscale import, shell service link).
    public func requestAddServer() { enqueue(.addServer(draft: nil)) }
    public func requestEditServer(id: UUID) {
        guard let server = sessionManager.serverManager.server(for: id) else { return }
        enqueue(.editServer(server))
    }
    public func requestServerInfo(id: UUID) {
        guard let server = sessionManager.serverManager.server(for: id) else { return }
        enqueue(.serverInfo(server))
    }
    public func requestDeleteServer(id: UUID) {
        guard let server = sessionManager.serverManager.server(for: id) else { return }
        enqueue(.deleteServer(server))
    }
    /// macOS: a new workspace window with a local shell. Elsewhere this is a no-op.
    public func requestLocalTerminal() { enqueue(.localTerminal) }
    public func requestShowWorkgroups() { enqueue(.showWorkgroups) }
    public func requestShowTailscale() { enqueue(.showTailscale) }

    func enqueue(_ request: Request) {
        pendingRequests.append(request)
        requestSerial &+= 1
    }

    func takeRequests() -> [Request] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }

    /// Saved servers the shell can surface (command palette, service actions).
    public var savedServerIDs: [UUID] { sessionManager.serverManager.servers.map(\.id) }
    public func savedServerName(id: UUID) -> String? { sessionManager.serverManager.server(for: id)?.name }
    /// Whether the user has configured Tailscale credentials (decides whether the entry shows).
    public var tailscaleIsConfigured: Bool { tailscaleConfigured }
    var tailscaleConfigured = false
    public func refreshTailscaleConfiguration() async {
        tailscaleConfigured = await TailscaleClient.storedCredentialPresence() == .configured
    }

    /// True when a saved SSH server exists for this endpoint id.
    public func hasServer(id: UUID) -> Bool {
        sessionManager.serverManager.server(for: id) != nil
    }

    #if os(macOS)
    /// Lets the app's `NSApplicationDelegateAdaptor` confirm quit with live sessions, as glas.sh does.
    public func attach(to delegate: MacTerminalAppDelegate) {
        delegate.sessionManager = sessionManager
        delegate.settingsManager = settingsManager
    }
    #endif
}

/// The shell's SSH capability. `open` connects when a saved server exists for the service's
/// endpoint id; otherwise it asks the bootstrap to present glas.sh's server form so the user
/// creates one — the new server takes the shell's endpoint id, which is the link.
@MainActor
public final class GlassTerminalCapability: GlassCapability {
    public let kind: HostServiceKind = .ssh
    public let displayName = "Terminal"
    public let symbolName = "terminal"
    private let runtime: GlassTerminalRuntime

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public func open(service: HostServiceLink, host: HostProfile) {
        let serverID = service.endpointID.rawValue
        if runtime.hasServer(id: serverID) {
            runtime.requestConnect(serverID: serverID)
        } else {
            runtime.setupRequest = .init(host: host, service: service)
        }
    }
}

/// Wraps the shell's library window content with glas.sh's bootstrap (persistent state load,
/// deep links, trust prompts), the connect flow, the server-setup sheet, and — on iPhone — the
/// router that swaps the library for a live terminal workgroup or an SFTP browser.
public struct GlassTerminalBootstrap<Content: View>: View {
    private let runtime: GlassTerminalRuntime
    private let content: Content
    #if os(iOS)
    @State private var router = IOSAppRouter()
    #endif

    public init(runtime: GlassTerminalRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    public var body: some View {
        @Bindable var runtime = runtime
        platformRoot
            .modifier(TerminalConnectFlow())
            .sheet(item: $runtime.setupRequest) { request in
                // The SSH connection panel: the Stage 2 layering proof on a real capability surface.
                GlassLayeredPanel(cornerRadius: 0) {
                    AddServerView(
                        serverManager: runtime.sessionManager.serverManager,
                        draft: ServerConfiguration(
                            id: request.service.endpointID.rawValue,
                            name: request.host.displayName,
                            host: request.host.aliases.first ?? "",
                            username: ""
                        )
                    )
                }
            }
            #if os(iOS)
            .sheet(isPresented: Binding(get: { router.showsWorkgroups }, set: { router.showsWorkgroups = $0 })) {
                TerminalWorkgroupsView()
            }
            .sheet(isPresented: Binding(get: { router.showsTailscale }, set: { router.showsTailscale = $0 })) {
                TerminalTailscaleView()
            }
            #endif
            #if os(macOS)
            .focusedSceneValue(\.macCommandCenterEntries, GlassTerminalCommandCenter.entries(runtime: runtime))
            #endif
            .task { await runtime.refreshTailscaleConfiguration() }
            .onReceive(NotificationCenter.default.publisher(for: .tailscaleCredentialsDidChange)) { _ in
                Task { await runtime.refreshTailscaleConfiguration() }
            }
            .environment(runtime)
            .environment(runtime.sessionManager)
            .environment(runtime.settingsManager)
            #if os(iOS)
            .environment(router)
            #endif
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(iOS)
        @Bindable var router = router
        Group {
            if let workgroupID = router.terminalWorkgroupID {
                VisionTerminalWorkgroupView(workgroupID: workgroupID)
                    .id(workgroupID)
            } else {
                MainBootstrapView { content }
            }
        }
        .sheet(isPresented: Binding(
            get: { router.sftpContext != nil },
            set: { if !$0 { router.sftpContext = nil } }
        )) {
            if let context = router.sftpContext,
               runtime.sessionManager.session(for: context.sessionID) != nil {
                SFTPBrowserView(sessionID: context.sessionID)
            } else {
                SFTPBrowserNotFoundView(context: router.sftpContext)
            }
        }
        #else
        MainBootstrapView { content }
        #endif
    }
}
