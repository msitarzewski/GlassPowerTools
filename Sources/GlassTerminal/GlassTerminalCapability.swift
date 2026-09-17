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
import GlassConnectionUI
import GlasSecretStore
import GlassShell
import GlassLayers
import GlassSSHTransport

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

    /// Shared by every Workgroups surface: the library panel's two columns, the standalone window
    /// and the iOS sheet. One instance, so a workgroup selected in one is selected in all of them
    /// and the two library columns agree about what is shown.
    let workgroupsModel = TerminalWorkgroupsModel()

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
        // (`localTerminal` carries no report: the outcome is claimed by the pane that actually
        // starts a shell — see `expectLocalShell`.)
        case showTailscale
        /// Show the connect flow's failure alert with this message (a link with nothing behind it).
        case showFailure(String)
    }
    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []

    /// The one layering state; the terminal's canvas appearance reads and writes it through
    /// `SettingsManager` so no second material system exists.
    public let layers: GlassLayerStore

    /// D14: the second source the terminal's trust prompt can be driven from, for callers that
    /// have no `TerminalSession` — a borrowed port forward, or a setup-time trust resolution.
    let trustBroker: TerminalHostTrustBroker

    public init(layers: GlassLayerStore? = nil, windowRecovery: GlassWindowRecoveryManager? = nil) {
        let layers = layers ?? GlassLayerStore()
        self.layers = layers
        let settingsManager = SettingsManager(loadImmediately: false, layers: layers)
        sessionManager = SessionManager(loadImmediately: false)
        self.settingsManager = settingsManager
        // The settings surface asks the catalog exactly one question — whether an interrupted SSH
        // key deletion left a key still referenced by a persisted server — and it has to reach the
        // catalog through its owner rather than reading storage behind its back (D26).
        settingsManager.serverManager = sessionManager.serverManager
        windowRecoveryManager = windowRecovery ?? GlassWindowRecoveryManager()
        trustBroker = TerminalHostTrustBroker {
            settingsManager.hostKeyVerificationMode == HostKeyVerificationMode.ask.rawValue
        }
    }

    /// Wires the terminal's saved-server storage to the shell's catalog (D26) and its host
    /// adoption (D27). Called once, by the composition root, which is the only place that can see
    /// both sides.
    ///
    /// One method rather than exposing `sessionManager`: the runtime is this module's public face,
    /// and the app has no business reaching through it into a manager. The App target compiles
    /// only under `xcodebuild` — it is not part of the SwiftPM package — so an accessibility
    /// mistake here is invisible to `swift build` and shows up at install time.
    @MainActor
    public func connectToLibrary(
        store: any GlassServiceStore,
        adopt: @escaping @MainActor (_ hostName: String, _ address: String, _ serviceName: String) async throws -> UUID,
        discard: @escaping @MainActor (UUID) async -> Void
    ) {
        // D26 stage 3: key records move into the Keychain, beside the material they name, so a key
        // imported on the Mac can be named on the phone rather than arriving as a nameless secret.
        settingsManager.attachKeychainKeyCatalog()
        let manager = sessionManager.serverManager
        manager.adoptHost = adopt
        manager.discardAdoption = discard
        manager.attach(store: .catalog(store))
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
    func applyHostAddress(_ address: String?, to host: HostProfile) async -> [UUID] {
        await GlassTerminalHostAddressSync.apply(address, to: host, in: sessionManager.serverManager)
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

    // MARK: The device's own shell (D8)

    /// Outcomes owed to the shell for local shells it asked for, oldest first. Opening a window
    /// is not a session, so the report waits for the pane that actually starts a process — or
    /// fails to start one — rather than claiming success the moment a window appears.
    private var pendingLocalShellReports: [GlassCapabilityReport] = []

    /// Records that the shell is waiting on the outcome of the local terminal being opened now.
    /// Nothing is queued for the toolbar's own Local Terminal button, which asks for no outcome.
    func expectLocalShell(report: GlassCapabilityReport?) {
        guard let report else { return }
        pendingLocalShellReports.append(report)
    }

    /// Called by a local pane once its process has started or failed to. Answers the oldest
    /// waiting request; with none waiting it does nothing, which is the normal case — most local
    /// panes are opened from the workspace itself and nobody is listening.
    func reportLocalShell(_ outcome: GlassCapabilityOutcome) {
        guard !pendingLocalShellReports.isEmpty else { return }
        pendingLocalShellReports.removeFirst()(outcome)
    }
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

    /// A terminal is device-bound when the key it authenticates with is a Secure Enclave key:
    /// that material cannot be copied off this Mac, so the connection cannot work anywhere else.
    ///
    /// Derived from the server's current `sshKeyID` every time it is asked, so switching the
    /// service to a password — or to an imported key — makes it start synchronizing again with no
    /// flag to clear.
    public func credential(for service: HostServiceLink, host: HostProfile) -> GlassServiceCredential {
        // No saved server behind the link is not the same as a password: this build cannot say what
        // authenticates the service, and saying "nothing" would let a key it uses look unused.
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else {
            return .unreadable
        }
        guard server.authMethod == .sshKey, let keyID = server.sshKeyID else { return .ownedByService }
        // A key whose record this device does not hold is a hardware key belonging to another Mac,
        // or one that has not arrived yet. Either way it is shared, and it is not usable here.
        let record = runtime.settingsManager.sshKeys.first { $0.id == keyID }
        return .sharedKey(id: keyID, deviceBound: record?.storageKind == .secureEnclave)
    }

    public func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else { return }
        try await runtime.sessionManager.serverManager.deleteServer(server)
    }

    /// The saved server's address, for hosts that predate addresses on the host record.
    public func knownAddress(service: HostServiceLink, host: HostProfile) -> String? {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else { return nil }
        let address = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    public func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
                     report: @escaping GlassCapabilityReport) {
        if service.endpointID == Self.localShellEndpointID {
            openLocalShell(report: report)
            return
        }
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
        // Same shape as the desktop's (`GlassDesktopCapability.swift:139-152`): the shell reports
        // the change synchronously, and each following server is a catalog write.
        let runtime = self.runtime
        Task { @MainActor in await runtime.applyHostAddress(address, to: host) }
    }

    // MARK: The device's own shell (D8)

    /// The endpoint id of the Mac's built-in local shell. A constant, because the shell stores no
    /// record for a built-in service: this is how the same service is recognised again in `open`.
    /// Readable as "GLAS…LOCALSHELL" in a JSON dump, and one no generated `UUID` will produce.
    public static let localShellEndpointID = EndpointID(rawValue: UUID(uuidString: "4c4f4341-4c00-0000-0000-5348454c4c00")!)

    /// The terminal's contribution to the device's own host: on a Mac, its shell. On iPhone, iPad
    /// and Vision Pro there is no local shell to open — no `posix_spawn` of a login shell, no PTY
    /// — so nothing is offered rather than a row that would do nothing when pressed.
    public func builtInLocalServices() -> [HostServiceLink] {
        #if os(macOS)
        [HostServiceLink(endpointID: Self.localShellEndpointID, kind: .ssh, displayName: "Local Shell")]
        #else
        []
        #endif
    }

    /// The terminal opts out of local setup: its service on this device is the built-in shell
    /// above, and a second, configurable way to make one would only be a worse one — glas.sh's
    /// workgroups already hold a saved shell, directory and layout.
    public var supportsLocalSetup: Bool { false }

    /// Connecting the built-in shell opens another local terminal — the same act as the toolbar's
    /// Local Terminal button, so pressing either repeatedly gives the user as many as they want.
    private func openLocalShell(report: @escaping GlassCapabilityReport) {
        #if os(macOS)
        runtime.expectLocalShell(report: report)
        runtime.requestLocalTerminal()
        #else
        // Not reachable through the library — `builtInLocalServices()` offers nothing off macOS —
        // but a stale link must still say why rather than appear to work.
        let message = "A local shell is only available on the Mac."
        runtime.enqueue(.showFailure(message))
        report(.failed(message))
        #endif
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

    /// D26: build the saved-server list now that the catalog can answer. `loadServersIfNeeded`
    /// is idempotent and refuses a store that is not readable yet, so calling it on every load is
    /// safe and calling it *only* at attach time was the bug — the list came back empty and the
    /// next write reconciled the catalog to match it.
    public func catalogDidLoad() {
        runtime.sessionManager.serverManager.loadServersIfNeeded()
    }

    public func libraryToolbarItems() -> AnyView {
        AnyView(GlassTerminalLibraryToolbar(runtime: runtime))
    }

    /// Workgroups belongs in the library's sidebar, beside Collections, because it is fleet-wide:
    /// a saved layout of sessions across several machines, not a property of one. glas.sh listed
    /// it exactly here; the merge moved it to a window of its own and that is what made it feel
    /// like a separate tool. Both columns read one `workgroupsModel` on the runtime, so the list
    /// and the detail agree about the selection.
    public func libraryPanels() -> [GlassLibraryPanel] {
        let runtime = self.runtime
        return [
            GlassLibraryPanel(
                id: "workgroups",
                sectionTitle: "Workgroups",
                title: "Workgroups",
                symbolName: "rectangle.stack",
                count: runtime.settingsManager.layoutPresets.count,
                results: {
                    TerminalWorkgroupsView(presentation: .results, model: runtime.workgroupsModel)
                        .environment(runtime)
                        .environment(runtime.sessionManager)
                        .environment(runtime.settingsManager)
                },
                detail: {
                    TerminalWorkgroupsView(presentation: .detail, model: runtime.workgroupsModel)
                        .environment(runtime)
                        .environment(runtime.sessionManager)
                        .environment(runtime.settingsManager)
                })
        ]
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
                TerminalWorkgroupsView(model: runtime.workgroupsModel)
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
                SFTPBrowserView(sessionID: context.sessionID, initialPath: context.initialPath)
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
    static func apply(_ address: String?, to host: HostProfile, in manager: ServerManager) async -> [UUID] {
        guard let address else { return [] }
        var applied: [UUID] = []
        for server in servers(manager.servers, following: host, address: address) {
            do {
                try await manager.updateServerOrThrow(server)
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

// MARK: - Lending the host's SSH transport to another capability (D7)

/// The shell's `GlassHostPortForward` over a real `SSHTunnel`. Closing it also releases this
/// borrower's claim on the transport, so a transport opened only for a tunnel goes away with it
/// while one shared with a live terminal session stays up.
private final class GlassTerminalPortForward: GlassHostPortForward {
    let localPort: Int
    private let tunnel: SSHTunnel
    private let transport: SSHTransport
    private let owner: UUID

    init(tunnel: SSHTunnel, transport: SSHTransport, owner: UUID) {
        self.localPort = tunnel.localPort
        self.tunnel = tunnel
        self.transport = transport
        self.owner = owner
    }

    func close() async {
        await tunnel.close()
        await transport.release(owner: owner)
    }
}

extension GlassTerminalCapability {
    /// Opens a `-L` forward from this device to `remoteHost:port` **as seen from `host`**, using
    /// the host's saved SSH service — its credentials, its jump chain and its already-established
    /// host-key trust. This is what lets the database capability reach a server bound to the
    /// machine's loopback without owning any SSH configuration of its own.
    ///
    /// **D14:** host-key trust is resolved here by asking, not by refusing. Opening a database is
    /// a foreground action — the user pressed play and is waiting — so an unknown or changed key
    /// surfaces the terminal's *own* fingerprint prompt through `TerminalHostTrustBroker`, and
    /// the transport pins and retries on acceptance. Auto-trusting remains forbidden: declining,
    /// or having host-key verification set to strict, still returns `hostNotTrusted`.
    public func openPortForward(host: HostProfile, toHost remoteHost: String,
                                port: Int) async throws -> any GlassHostPortForward {
        guard let link = host.services.first(where: { $0.kind == .ssh }),
              let server = runtime.sessionManager.serverManager.server(for: link.endpointID.rawValue)
        else { throw GlassPortForwardError.unavailable }

        let preparation = try runtime.sessionManager.prepareConnection(for: server)
        var materials: [UUID: SessionAuthenticationMaterial] = [
            preparation.authentication.target.serverID: preparation.authentication.target.material
        ]
        for hop in preparation.authentication.jumpHosts { materials[hop.serverID] = hop.material }

        let route = SSHConnection.makeRoute(for: server, jumpHostChain: preparation.jumpHostChain)
        let transport = SSHTransport(
            route: route,
            credentials: PreparedCredentialResolver(materials: materials),
            trustStore: SecretStoreHostTrustStore(configuration: KeychainManager.hostTrustConfig),
            trustDecider: BrokeredHostTrustDecider(broker: runtime.trustBroker)
        )
        let owner = UUID()
        _ = await transport.acquire(owner: owner)
        do {
            try await transport.connect()
            let tunnel = try await transport.forward(localPort: 0, toHost: remoteHost, port: port)
            return GlassTerminalPortForward(tunnel: tunnel, transport: transport, owner: owner)
        } catch let error as SSHTransportError {
            await transport.release(owner: owner)
            switch error {
            case .hostTrustRequired, .hostTrustRejected:
                throw GlassPortForwardError.hostNotTrusted(name: server.host)
            default:
                throw error
            }
        } catch {
            await transport.release(owner: owner)
            throw error
        }
    }

    /// Settles this machine's host-key trust without opening a tunnel (D14), so that a database
    /// service being *set up* to tunnel can have its fingerprint reviewed once, there and then,
    /// and simply connect later.
    ///
    /// Already-pinned machines are answered from the trust store without touching the network,
    /// so the setup sheet may call this unconditionally.
    public func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome {
        guard let link = host.services.first(where: { $0.kind == .ssh }),
              let server = runtime.sessionManager.serverManager.server(for: link.endpointID.rawValue)
        else { return .unavailable }

        let trustStore = SecretStoreHostTrustStore(configuration: KeychainManager.hostTrustConfig)
        if let pinned = try? trustStore.authorizedKeys(host: server.host, port: server.port), !pinned.isEmpty {
            return .trusted
        }

        // Not pinned yet, so the key has to be seen to be judged: connect far enough to be
        // offered it, let the prompt settle it, then drop the transport again. Nothing is left
        // open — this is a trust decision, not a session.
        let preparation: SessionManager.ConnectionPreparationResult
        do {
            preparation = try runtime.sessionManager.prepareConnection(for: server)
        } catch {
            // No usable credential yet: there is nothing to ask about, and saying "declined"
            // would blame the user for something they never saw.
            return .unavailable
        }
        var materials: [UUID: SessionAuthenticationMaterial] = [
            preparation.authentication.target.serverID: preparation.authentication.target.material
        ]
        for hop in preparation.authentication.jumpHosts { materials[hop.serverID] = hop.material }

        let transport = SSHTransport(
            route: SSHConnection.makeRoute(for: server, jumpHostChain: preparation.jumpHostChain),
            credentials: PreparedCredentialResolver(materials: materials),
            trustStore: trustStore,
            trustDecider: BrokeredHostTrustDecider(broker: runtime.trustBroker)
        )
        let owner = UUID()
        _ = await transport.acquire(owner: owner)
        defer { Task { await transport.release(owner: owner) } }
        do {
            try await transport.connect()
            return .trusted
        } catch let error as SSHTransportError {
            switch error {
            case .hostTrustRejected, .hostTrustRequired: return .declined
            // Anything else — unreachable, bad credential — is not the user declining, and
            // must not be reported as though it were.
            default: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}
