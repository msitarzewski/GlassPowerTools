//
//  GlassTerminalCapability.swift
//  Glass Power Tools — GlassTerminal
//
//  The SSH capability's public surface: the runtime the app owns, the capability the shell routes
//  Connect through, and the bootstrap wrapper that hosts glas.sh's startup, deep-link, trust and
//  connect flows around the shell's library. Everything else in this module stays internal.
//

import SwiftUI
import OSLog
import GlassConnectionKit
import GlassShell
import GlassLayers

/// What the shell asked the terminal to open.
public enum GlassTerminalOpenPurpose: Sendable { case terminal, sftp }

/// The shell's outcome callback for one connect attempt (see `GlassCapabilityOutcome`).
public typealias GlassCapabilityReport = @MainActor (GlassCapabilityOutcome) -> Void

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
        /// `report` is the shell's outcome callback (nil for the terminal's own callers).
        case connect(serverID: UUID, purpose: TerminalSession.Purpose, report: GlassCapabilityReport?)
        case quickConnect(ServerConfiguration, password: String)
        case openWorkgroup(LayoutPreset)
        case addServer(draft: ServerConfiguration?)
        /// `hostContext` when the edit comes from the shell's host detail: the form then shows the
        /// host's address read-only instead of a second Host field.
        case editServer(ServerConfiguration, hostContext: ServerFormHostContext?)
        case serverInfo(ServerConfiguration)
        case deleteServer(ServerConfiguration)
        case localTerminal
        case showWorkgroups
        case showTailscale
        /// Show the connect flow's failure alert with this message (a link with nothing behind it).
        case showFailure(String)
    }
    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []

    /// The one layering state; the terminal's canvas appearance reads and writes it through
    /// `SettingsManager` so no second material system exists.
    public let layers: GlassLayerStore

    public init(layers: GlassLayerStore? = nil, windowRecovery: GlassWindowRecoveryManager? = nil) {
        let layers = layers ?? GlassLayerStore()
        self.layers = layers
        sessionManager = SessionManager(loadImmediately: false)
        settingsManager = SettingsManager(loadImmediately: false, layers: layers)
        windowRecoveryManager = windowRecovery ?? GlassWindowRecoveryManager()
    }

    /// Connect to the saved server whose id is the shell's endpoint id. Consumed by the bootstrap.
    /// `report`, when given, receives the attempt's terminal state (the shell stamps "last
    /// connected" only on `.connected`).
    public func requestConnect(serverID: UUID, purpose: GlassTerminalOpenPurpose = .terminal,
                               report: GlassCapabilityReport? = nil) {
        enqueue(.connect(serverID: serverID, purpose: purpose == .sftp ? .sftp : .terminal, report: report))
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
        enqueue(.editServer(server, hostContext: nil))
    }

    /// The host's address changed in the shell: every saved server that is a service of that
    /// host record follows it, so the machine's identity is edited once. Returns the ids updated.
    @discardableResult
    func applyHostAddress(_ address: String?, to host: HostProfile) -> [UUID] {
        GlassTerminalHostAddressSync.apply(address, to: host, in: sessionManager.serverManager)
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

/// The shell's SSH capability. A service is created complete through the shell's host sheet:
/// the terminal's draft commits the saved server under the shell's endpoint id, which is the
/// link. `open` connects to that server; a link with no server behind it is reported as such.
@MainActor
public final class GlassTerminalCapability: GlassCapability {
    public let kind: HostServiceKind = .ssh
    public let displayName = "Terminal"
    public let symbolName = "terminal"
    private let runtime: GlassTerminalRuntime

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public func open(service: HostServiceLink, host: HostProfile, report: @escaping GlassCapabilityReport) {
        open(service: service, host: host, hostAccess: GlassCapabilityHostAccess(address: host.address), report: report)
    }

    // MARK: Setup (the shell's host sheet)

    public func makeSetupDraft() -> any GlassServiceDraft {
        TerminalServiceDraft(serverManager: runtime.sessionManager.serverManager, settingsManager: runtime.settingsManager)
    }

    public func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else { return nil }
        return TerminalServiceDraft(editing: server, serverManager: runtime.sessionManager.serverManager,
                                    settingsManager: runtime.settingsManager)
    }

    public func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else { return }
        try runtime.sessionManager.serverManager.deleteServer(server)
    }

    /// The saved server's address, for hosts that predate addresses on the host record.
    public func knownAddress(service: HostServiceLink, host: HostProfile) -> String? {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else { return nil }
        let address = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    public func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
                     report: @escaping GlassCapabilityReport) {
        let serverID = service.endpointID.rawValue
        if runtime.hasServer(id: serverID) {
            runtime.requestConnect(serverID: serverID, report: report)
        } else {
            // A link another family app recorded without a saved server behind it. Nothing to
            // connect; the shell shows the message and the user can edit or remove the service.
            let message = "\(service.displayName) has no saved terminal configuration. Edit the service to set it up, or remove it."
            runtime.enqueue(.showFailure(message))
            report(.failed(message))
        }
    }

    public func hostAddressDidChange(host: HostProfile, address: String?) {
        runtime.applyHostAddress(address, to: host)
    }

    // MARK: Shell hooks

    public var settingsPages: [GlassCapabilitySettingsPage] {
        let runtime = self.runtime
        return GlassTerminalSettingsPages.all.map { page in
            GlassCapabilitySettingsPage(id: page.id, title: page.title, systemImage: page.systemImage) {
                page.view(runtime: runtime)
            }
        }
    }

    public func libraryToolbarItems() -> AnyView {
        AnyView(GlassTerminalLibraryToolbar(runtime: runtime))
    }

    public func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView {
        AnyView(GlassTerminalServiceActions(runtime: runtime, service: service, host: host))
    }

    /// Files is SFTP, offered as its own row because it is a separate tool, not a separate
    /// service: it rides this terminal's endpoint, credentials and host trust. Every SSH server
    /// this app can reach runs the SFTP subsystem, so the row appears whenever the service has a
    /// saved server; the session reports it honestly if the subsystem is refused.
    public func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] {
        let serverID = service.endpointID.rawValue
        guard runtime.hasServer(id: serverID) else { return [] }
        let runtime = self.runtime
        return [
            GlassServiceTool(id: "files-\(serverID.uuidString.lowercased())",
                             title: "Files",
                             symbolName: "folder",
                             subtitle: "Browse this machine's files over \(GlassServicePresentation.displayName(for: service.kind))") {
                runtime.requestConnect(serverID: serverID, purpose: .sftp)
            }
        ]
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
        platformRoot
            .modifier(TerminalConnectFlow())
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

/// Which saved servers follow a host's address, and to what. Pure so it is testable without a
/// keychain: a server follows when it is one of the host record's SSH services and its address
/// differs from the host's.
enum GlassTerminalHostAddressSync {
    /// Persists the change for every following server; a server whose update fails is logged and
    /// skipped so one bad record does not stop the rest. Returns the ids updated. A cleared
    /// address (nil) leaves the servers as they are: they still need something to connect to.
    @MainActor @discardableResult
    static func apply(_ address: String?, to host: HostProfile, in manager: ServerManager) -> [UUID] {
        guard let address else { return [] }
        var applied: [UUID] = []
        for server in servers(manager.servers, following: host, address: address) {
            do {
                try manager.updateServerOrThrow(server)
                applied.append(server.id)
            } catch {
                Logger.servers.error("Host address sync skipped \(server.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return applied
    }

    static func servers(_ servers: [ServerConfiguration], following host: HostProfile, address: String) -> [ServerConfiguration] {
        let owned = Set(host.services.filter { $0.kind == .ssh }.map(\.endpointID.rawValue))
        return servers.compactMap { server in
            guard owned.contains(server.id), server.host != address else { return nil }
            var updated = server
            updated.host = address
            return updated
        }
    }
}
