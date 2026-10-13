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
import GlassEditorCore
import GlassLayers
import GlassSSHTransport
import GlassTerminalEmulator

/// What the shell asked the terminal to open.
public enum GlassTerminalOpenPurpose: Sendable { case terminal, sftp }

/// The shell's outcome callback for one connect attempt (see `GlassCapabilityOutcome`).
public typealias GlassCapabilityReport = @MainActor (GlassCapabilityOutcome) -> Void

/// A saved workgroup as the app's system integration sees it (D72): its id, name and how many
/// terminals it opens. Nothing else of the preset leaves the terminal.
public struct GlassTerminalWorkgroup: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let terminals: Int
}

/// Owns glas.sh's managers for the process. One per app, created in the composition root.
@MainActor @Observable
public final class GlassTerminalRuntime {
    let sessionManager: SessionManager
    let settingsManager: SettingsManager
    let windowRecoveryManager: WindowRecoveryManager

    /// Shared by the Workgroups panel's two columns, so the list and the detail agree about what
    /// is selected.
    let workgroupsModel = TerminalWorkgroupsModel()

    /// The library's id for the Workgroups panel, and what its menu items ask the library to open.
    static let workgroupsPanelID = "workgroups"

    /// Opens a panel in the library's sidebar. Supplied by the composition root, since the library
    /// is the shell's; nil means there is no library to show it in.
    public var showLibraryPanel: GlassShowLibraryPanel?

    /// Everything the library, the command palette, the workgroup and Tailscale surfaces and the
    /// shell can ask the terminal to do. One queue, consumed by `TerminalConnectFlow`, so the
    /// legacy-algorithm confirmation, trust prompt and password fallback exist exactly once.
    enum Request {
        /// `report` is the shell's outcome callback (nil for the terminal's own callers).
        /// `tmux` names a session already running on the host to attach to (D44, Active);
        /// `withoutTmux` opens a plain shell whatever the server's setting.
        case connect(serverID: UUID, purpose: TerminalSession.Purpose, report: GlassCapabilityReport?,
                     tmux: TerminalTmuxAttachment? = nil, withoutTmux: Bool = false)
        case quickConnect(ServerConfiguration, password: String)
        case openWorkgroup(LayoutPreset)
        case addServer(draft: ServerConfiguration?)
        /// `hostContext` when the edit comes from the shell's host detail: the form then shows the
        /// host's address read-only instead of a second Host field.
        case editServer(ServerConfiguration, hostContext: ServerFormHostContext?)
        case serverInfo(ServerConfiguration)
        case deleteServer(ServerConfiguration)
        /// `tmux` names a session on this Mac to attach to — Active's Open (D47).
        /// `withoutTmux`: a plain shell, whatever Settings ▸ Terminal says.
        case localTerminal(tmux: String? = nil, withoutTmux: Bool = false)
        /// Running tmux sessions, on this Mac and on saved servers, opened together in one new
        /// window in this order — Active's "Open N in New Window" (W13).
        case openTmuxSessions([TerminalTmuxTarget])
        case showWorkgroups
        // (`localTerminal` carries no report: the outcome is claimed by the pane that actually
        // starts a shell — see `expectLocalShell`.)
        case showTailscale
        /// Bring an already-open workgroup back to the screen (D1's `activate`). Not a connect:
        /// the sessions are live and only the thing pointing at them was cleared.
        case showWorkgroup(workgroupID: UUID)
        /// Show the connect flow's failure alert with this message (a link with nothing behind it).
        case showFailure(String)
        #if DEBUG
        /// Screenshots (App/GlassDemoMode.swift): a session that connects to nothing, showing a
        /// recorded transcript in the real terminal window. Typing goes nowhere.
        /// `windowSettings` for its window (W22), and This Window opened over it when asked.
        case demoReplay(name: String, output: Data, windowSettings: GlassWindowOverrides, opensSettings: Bool)
        /// Screenshots: one window holding a demo terminal on each of `names`, the first in front;
        /// on Vision Pro, shown in the grid when `grid` (W31: one bottom bar in tabs and in grid).
        case demoTabs(names: [String], output: Data, grid: Bool)
        /// Screenshots: the Files window over a session that connects to nothing, opened at
        /// `path`. It shows the window's frame and header, and the browser's own "not connected"
        /// state where a listing would be.
        case demoFiles(name: String, path: String)
        #endif
    }
    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []

    /// The one layering state; the terminal's canvas appearance reads and writes it through
    /// `SettingsManager` so no second material system exists.
    public let layers: GlassLayerStore

    /// D14: the second source the terminal's trust prompt can be driven from, for callers that
    /// have no `TerminalSession` — a borrowed port forward, or a setup-time trust resolution.
    let trustBroker: TerminalHostTrustBroker

    /// What "Open in Editor" does to a folder in the Files browser. Set by the composition root;
    /// nil means nothing can open a project here and the menu item is not offered.
    public var openFolderAsProject: GlassOpenFolderAsProject?

    /// What "Edit" does to a file in the Files browser: opens it in the editor, as a tab.
    public var openFileInEditor: GlassOpenFileInEditor?

    /// The editor as a view, for a device where the browser has to present it itself.
    public var editorFileScreen: GlassEditorFileScreen?

    /// Everything open in the whole app, for the Mac's Terminal Overview to show beside its own
    /// tabs. Supplied by the composition root, because the answer is the shell's registry and a
    /// capability must not hold the shell — the same seam as `openFolderAsProject` above. Nil
    /// means the overview shows only what it always showed.
    public var openSessions: (@MainActor () -> [GlassOpenSession])?

    /// The name of the machine a saved server is a terminal on, from the shell's catalog, for
    /// menus that already say "Terminal on" (2026-10-12: "New Terminal on ▸ Terminal on alpha").
    /// Supplied by the composition root, by the same seam; nil leaves them the server's own name.
    public var hostName: (@MainActor (UUID) -> String?)?

    /// What a menu that says "Terminal on" calls a saved server: its machine's name; for a
    /// terminal named something else, both. A "Terminal on …" name is the default a host sheet
    /// gives (`serviceDisplayName`), kept when the machine is renamed since ("bravo — Terminal on
    /// old-bravo", 2026-10-12): the machine's name now is the one. Without the machine,
    /// the name less that default prefix.
    static func machineTitle(serverName: String, hostName: String?) -> String {
        let defaultPrefix = "Terminal on "
        if let hostName = hostName?.trimmingCharacters(in: .whitespacesAndNewlines), !hostName.isEmpty {
            return serverName.hasPrefix(defaultPrefix) || serverName == hostName ? hostName : "\(hostName) — \(serverName)"
        }
        return serverName.hasPrefix(defaultPrefix) ? String(serverName.dropFirst(defaultPrefix.count)) : serverName
    }

    /// Titles two terminals on one machine would share get their user names, so a menu tells
    /// them apart ("alpha (ann)", "alpha (root)").
    static func distinguished(_ titled: [(ServerConfiguration, String)]) -> [(server: ServerConfiguration, title: String)] {
        let counts = Dictionary(titled.map { ($0.1, 1) }, uniquingKeysWith: +)
        return titled.map { server, title in
            (server, counts[title, default: 0] > 1 ? "\(title) (\(server.username))" : title)
        }
    }

    func machineTitle(of server: ServerConfiguration) -> String {
        Self.machineTitle(serverName: server.name, hostName: hostName?(server.id))
    }

    /// "Take me to the live connections" — the ⚡ in every toolbar. Supplied by the composition
    /// root, since the library is the shell's; nil means the bolt is not offered.
    public var showActiveConnections: GlassShowActiveConnections?

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
        wakeWatcher = SSHWakeWatcher()
        #if os(macOS)
        // Show All Windows is drawn here, with every terminal window's tabs as live tiles; the
        // shell's button and every window's toolbar reach it through this (GlassShowAllWindows).
        GlassShowAllWindows.toggle = { [weak self] openWindow in
            guard let self else { return }
            MacTerminalExpose.shared.toggle(.init(runtime: self, openWindow: openWindow))
        }
        // ⇧⌘\ is Show All Windows' from the start, before any window could press it.
        MacTerminalExposeShortcut.install()
        // The one Command Palette's terminal entries: a terminal on each saved machine.
        let sessionManager = self.sessionManager
        GlassCommandPaletteSources.register(id: "terminal") { openWindow in
            sessionManager.serverManager.servers.map { server in
                MacCommandCenterEntry(id: "connection.connect.\(server.id)", title: "connect: \(server.name)",
                                      detail: "Open an SSH terminal window") {
                    sessionManager.paletteConnectionRequest = server.id
                    openWindow(id: "main")
                }
            }
        }
        #endif
    }

    /// Asks every SSH connection to answer after a wake or a return to the foreground (B-X25).
    private let wakeWatcher: SSHWakeWatcher

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
    /// `withoutTmux`: a plain shell, though the server keeps its terminals in tmux.
    public func requestConnect(serverID: UUID, purpose: GlassTerminalOpenPurpose = .terminal,
                               report: GlassCapabilityReport? = nil, withoutTmux: Bool = false) {
        enqueue(.connect(serverID: serverID, purpose: purpose == .sftp ? .sftp : .terminal, report: report,
                         withoutTmux: withoutTmux))
    }
    /// Open a saved workgroup preset (all of its terminals) through the launch plan.
    public func requestOpenWorkgroup(_ presetID: UUID) {
        guard let preset = settingsManager.layoutPresets.first(where: { $0.id == presetID }) else { return }
        enqueue(.openWorkgroup(preset))
    }
    /// glas.sh's server form, empty or pre-filled (Tailscale import, shell service link).
    public func requestAddServer() { enqueue(.addServer(draft: nil)) }

    /// An `ssh://` link opened with the app (D72): a machine in the library connects as saved; one
    /// that is not opens the new-server form filled in from the link (`TerminalSSHLink`).
    public func requestOpen(sshLink url: URL) {
        guard let link = TerminalSSHLink(url) else {
            enqueue(.showFailure("That SSH link names no machine Glass Power Tools can connect to. A link looks like ssh://user@host:22."))
            return
        }
        if let server = link.match(in: sessionManager.serverManager.servers) {
            requestConnect(serverID: server.id)
        } else {
            enqueue(.addServer(draft: link.draft))
        }
    }
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
    public func requestLocalTerminal(withoutTmux: Bool = false) { enqueue(.localTerminal(withoutTmux: withoutTmux)) }

    #if os(macOS)
    /// A terminal window on this Mac, in `folder` when there is one — a file stands for the folder
    /// it is in — opened straight from outside any window: Siri, Shortcuts, a Finder service, the
    /// Dock (D72). In tmux as this Mac's setting says. Not through the request queue, which only the
    /// Connections window drains: a Mac with only terminal windows open would never see it.
    public func openLocalTerminal(in folder: URL?, with openWindow: OpenWindowAction) {
        openWindow(id: "workspace", value: MacLocalTerminalStart.windowRequest(in: folder.map(Self.folderPath(for:))))
    }

    /// A tab in the terminal window in front, in `folder` — "New Glass Power Tools Tab Here" (D72).
    /// With no terminal window on screen, or none with room, a window.
    public func openLocalTerminalTab(in folder: URL, with openWindow: OpenWindowAction) {
        let request = MacWorkspaceTabRequest(initialPaneIntent: MacLocalTerminalStart.intent(in: Self.folderPath(for: folder)))
        if !addToFrontWindow(request) { openLocalTerminal(in: folder, with: openWindow) }
    }

    /// A script opened with the app — a `.command` file from the Finder (D72) — run in a new tab
    /// of the window in front, in its own folder, as Terminal runs one: its path is typed into the
    /// tab's shell, escaped as a dropped path is.
    public func runInTerminal(_ script: URL, with openWindow: OpenWindowAction) {
        let folder = Self.folderPath(for: script)
        let ticket = MacStartupCommandBroker.shared.issue(command: TerminalDroppedPaths.escaped(script.standardizedFileURL.path))
        let intent = MacLocalTerminalStart.intent(in: folder)
        if !addToFrontWindow(MacWorkspaceTabRequest(initialPaneIntent: intent, startupTicketID: ticket)) {
            openWindow(id: "workspace", value: MacWorkspaceLaunchRequest(initialPaneIntent: intent, startupTicketID: ticket))
        }
    }

    /// Adds the tab to the terminal window in front and brings it forward; false with none.
    private func addToFrontWindow(_ request: MacWorkspaceTabRequest) -> Bool {
        guard let front = MacWorkspacePreviewRegistry.shared.frontTabAdder(), front.add(request) else { return false }
        NSApp.activate()
        if front.window.isMiniaturized { front.window.deminiaturize(nil) }
        front.window.makeKeyAndOrderFront(nil)
        return true
    }
    #endif

    /// The folder a file or folder URL names: the folder itself, or the one holding the file.
    nonisolated static func folderPath(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        let isFolder = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        return (isFolder ? standardized : standardized.deletingLastPathComponent()).path(percentEncoded: false)
    }

    /// The saved workgroups, for Shortcuts and Siri (D72): metadata only.
    public var workgroups: [GlassTerminalWorkgroup] {
        settingsManager.layoutPresets.map {
            GlassTerminalWorkgroup(id: $0.id, name: $0.name, terminals: $0.sessionIntents.count)
        }
    }

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

    /// Window ▸ Workgroups, Library ▸ Workgroups… and the palette's Workgroups: the Connections
    /// window, on its Workgroups panel. An open one comes forward; with none open, one is opened
    /// and picks the request up as it appears.
    func showWorkgroups(openWindow: OpenWindowAction) {
        #if os(macOS)
        if !GlassLibraryWindows.bringForward() { openWindow(id: "main") }
        #elseif os(visionOS)
        // One Connections window on the headset: opening it brings that one forward.
        openWindow.openConnections()
        #endif
        showWorkgroupsPanel()
    }

    /// The library half of `showWorkgroups`, which every platform shares.
    func showWorkgroupsPanel() {
        showLibraryPanel?(Self.workgroupsPanelID)
    }
    #if DEBUG
    /// Screenshots only: a terminal window on `name` showing `output`, with no connection behind it,
    /// keeping `windowSettings` as its own (W22); with `opensSettings`, Settings ▸ This Window opens
    /// over it.
    public func requestDemoReplay(name: String, output: Data,
                                  windowSettings: GlassWindowOverrides = GlassWindowOverrides(),
                                  opensSettings: Bool = false) {
        enqueue(.demoReplay(name: name, output: output, windowSettings: windowSettings, opensSettings: opensSettings))
    }
    /// Screenshots only: one window with a demo terminal on each of `names` as its tabs, each
    /// showing `output`; on Vision Pro in the grid when `grid`.
    public func requestDemoTabs(names: [String], output: Data, grid: Bool = false) {
        enqueue(.demoTabs(names: names, output: output, grid: grid))
    }
    /// Screenshots only: a terminal window's own settings (W22) — lighter glass with a tint, a
    /// larger font and a bar cursor — over the demo's Appearance.
    public static var demoWindowSettings: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.35
        window[TerminalWindowSettings.tint] = "#FF2D55"
        window[TerminalWindowSettings.fontSize] = 18
        window[TerminalWindowSettings.cursorStyle] = "Bar"
        return window
    }
    /// Screenshots only: the Files window on `name` at `path`, with no connection behind it.
    public func requestDemoFiles(name: String, path: String) { enqueue(.demoFiles(name: name, path: path)) }
    #endif
    public func requestShowTailscale() { enqueue(.showTailscale) }

    func enqueue(_ request: Request) {
        pendingRequests.append(request)
        requestSerial &+= 1
    }

    /// Changes each time the library's catalog has loaded (`catalogDidLoad`): until the first, the
    /// terminal knows no saved servers. W15 reopens the last run's workgroups once it has, as
    /// Active waits for it (54a66d5).
    private(set) var catalogLoads = 0

    func noteCatalogLoaded() {
        catalogLoads &+= 1
    }

    /// iPad: workgroups waiting for the new window opened to show them — **Move Tab to New Window**
    /// (W15) — taken by that window as it appears, oldest first.
    @ObservationIgnored private var workgroupsAwaitingWindow: [UUID] = []

    func requestWindow(showing workgroupID: UUID) {
        workgroupsAwaitingWindow.append(workgroupID)
    }

    /// Vision Pro: windows made by dropping a terminal dragged out of the library (D72), each
    /// waiting for its server's session, by server id. The session goes into the window's own
    /// workgroup rather than a new window, so it stands where it was dropped.
    @ObservationIgnored private var windowsAwaitingSession: [UUID: UUID] = [:]

    /// A workgroup id for a dropped window to show once `serverID`'s session is ready.
    func reserveWindow(forServer serverID: UUID) -> UUID {
        let workgroupID = UUID()
        windowsAwaitingSession[serverID] = workgroupID
        return workgroupID
    }

    /// The dropped window waiting for `serverID`'s session, taken once.
    func takeReservedWindow(forServer serverID: UUID) -> UUID? {
        windowsAwaitingSession.removeValue(forKey: serverID)
    }

    /// A dropped window that stopped waiting — its connection failed or was turned down.
    func releaseReservation(_ workgroupID: UUID) {
        windowsAwaitingSession = windowsAwaitingSession.filter { $0.value != workgroupID }
    }

    func takeWorkgroupAwaitingWindow() -> UUID? {
        workgroupsAwaitingWindow.isEmpty ? nil : workgroupsAwaitingWindow.removeFirst()
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
    let runtime: GlassTerminalRuntime

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    // MARK: Open sessions (D1)

    /// One row per workgroup that still has a live session in it, newest first.
    ///
    /// The workgroup rather than the session, because that is what the phone actually shows and
    /// what `showTerminal(workgroupID:)` takes — a connect on iPhone makes a workgroup named
    /// after the machine and puts the one session in it. A workgroup whose sessions have all
    /// ended is not listed: it would be a row that goes to an empty screen.
    public func openSessions() -> [GlassOpenSession] {
        let manager = runtime.sessionManager
        return workgroupSessions(manager) + loneSessions(manager)
    }

    /// **A terminal opened by Connect on a Mac is in no workgroup.** iOS and visionOS put every
    /// terminal in a workgroup (`presentTerminalWindow`), so the workgroup listing covered them;
    /// the Mac opens a workspace window with a live-session ticket and the session belongs to
    /// nothing but its window — so Active showed the MySQL session on a server and not the terminal
    /// beside it (2026-09-22). One row per such session; brought forward and closed through the
    /// window that holds it, which the overview's registry already knows.
    private func loneSessions(_ manager: SessionManager) -> [GlassOpenSession] {
        let grouped = Set(manager.workgroups.flatMap(\.sessionIDs))
        // A probe (D44) is a few seconds of Active asking a host about tmux: never a row.
        let servers = manager.serverManager.servers
        return manager.sessions.filter { !grouped.contains($0.id) && $0.purpose != .probe }.map { session in
            GlassOpenSession(
                id: Self.sessionID(sessionID: session.id),
                title: session.purpose == .sftp ? "SFTP on \(session.server.name)" : Self.name(of: session, servers: servers),
                subtitle: Self.subtitle(for: [session]),
                symbolName: session.purpose == .sftp ? "folder" : symbolName,
                endpointIDs: [EndpointID(rawValue: session.server.id)],
                activate: { Self.reveal(session, in: manager) },
                close: { Self.close(session, in: manager) },
                closeTitle: Self.closeTitle(for: [session]),
                closeSymbolName: Self.closeSymbolName(for: [session]),
                isConnected: session.state == .connected,
                snapshot: { Self.preview(of: session) }
            )
        }
    }

    /// A terminal in no workgroup is called what the tab showing it is called (W19): on the Mac,
    /// Active said the server's name while the tab said what ran there. Else what it calls
    /// itself (`TerminalWorkgroupOpening.label`), else its server.
    private static func name(of session: TerminalSession, servers: [ServerConfiguration]) -> String {
        #if os(macOS)
        if let title = MacWorkspacePreviewRegistry.shared.tabTitle(sessionID: session.id, servers: servers) { return title }
        #endif
        return TerminalWorkgroupOpening.label(session, on: .active)
    }

    private static func reveal(_ session: TerminalSession, in manager: SessionManager) {
        #if os(macOS)
        MacWorkspacePreviewRegistry.shared.reveal(sessionID: session.id)
        #endif
    }

    /// Through the window's own pane removal where there is one, so the pane goes with the
    /// session rather than staying on screen dead; the manager alone otherwise.
    private static func close(_ session: TerminalSession, in manager: SessionManager) {
        #if os(macOS)
        if MacWorkspacePreviewRegistry.shared.close(sessionID: session.id, sessionManager: manager) { return }
        #endif
        manager.closeSession(session)
    }

    /// The id this capability gives a session that is in no workgroup.
    public static func sessionID(sessionID: UUID) -> String {
        "terminal-session:\(sessionID.uuidString)"
    }

    private func workgroupSessions(_ manager: SessionManager) -> [GlassOpenSession] {
        manager.workgroups.reversed().compactMap { workgroup in
            let live = workgroup.sessionIDs.compactMap { manager.session(for: $0) }
            guard !live.isEmpty else { return nil }
            return GlassOpenSession(
                id: Self.sessionID(workgroupID: workgroup.id),
                title: Self.title(of: workgroup, live: live),
                subtitle: Self.subtitle(for: live),
                symbolName: symbolName,
                // The machines this workgroup is on: its servers are the shell's endpoints (D26).
                endpointIDs: live.map { EndpointID(rawValue: $0.server.id) },
                activate: { [runtime] in runtime.enqueue(.showWorkgroup(workgroupID: workgroup.id)) },
                close: { manager.closeWorkgroup(workgroup.id) },
                closeTitle: Self.closeTitle(for: live),
                closeSymbolName: Self.closeSymbolName(for: live),
                connectedEndpointIDs: live.filter { $0.state == .connected }.map { EndpointID(rawValue: $0.server.id) },
                // The card shows the terminal the workgroup has selected — the one you would be
                // looking at if you went back to it. Drawn by the emulator, which has been able
                // to do this since glas.sh's overview; nothing new was needed.
                snapshot: {
                    let shown = workgroup.selectedSessionID.flatMap { manager.session(for: $0) } ?? live[0]
                    return Self.preview(of: shown)
                }
            )
        }
    }

    /// A workgroup Connect made for one terminal is named after its server ("Terminal on alpha"),
    /// so its row is named as its window names the terminal (W11): the name it was given, its
    /// program's title, its repository. The owner, on the Vision Pro (2026-10-09): Active said
    /// "Terminal on …" while the window had the name. A workgroup with a name of its own, or with
    /// several terminals, keeps its name.
    static func title(of workgroup: TerminalWorkgroup, live: [TerminalSession]) -> String {
        guard live.count == 1, let only = live.first, workgroup.name == only.server.name else { return workgroup.name }
        return TerminalWorkgroupOpening.label(only, on: .active)
    }

    /// D44: a row says when its terminals are in tmux, and ending it is a detach when they all
    /// are — the sessions go on running on the machine, and Active lists them there.
    static func subtitle(for live: [TerminalSession]) -> String {
        let inTmux = live.filter(\.survivesClose)
        if live.count == 1 {
            guard let name = inTmux.first?.tmuxSessionName else { return live[0].state.displayName }
            let label = TerminalTmux.glassNumber(name).map { "Terminal \($0)" } ?? name
            return "\(live[0].state.displayName) · in tmux (\(label))"
        }
        if inTmux.isEmpty { return "\(live.count) terminals" }
        return inTmux.count == live.count ? "\(live.count) terminals in tmux" : "\(live.count) terminals, \(inTmux.count) in tmux"
    }

    static func closeTitle(for live: [TerminalSession]) -> String {
        !live.isEmpty && live.allSatisfy(\.survivesClose) ? "Detach" : "Close"
    }

    static func closeSymbolName(for live: [TerminalSession]) -> String {
        closeTitle(for: live) == "Detach" ? "eject" : "xmark"
    }

    /// A still of a terminal, in whatever image type this platform uses. 800px wide is the
    /// overview's own figure (`VisionTerminalWorkgroupView`), kept so both look the same.
    private static func preview(of session: TerminalSession) -> Image? {
        #if os(macOS)
        session.terminalHostModel.previewImage(maxPixelWidth: 800).map(Image.init(nsImage:))
        #else
        session.terminalHostModel.previewImage(maxPixelWidth: 800).map(Image.init(uiImage:))
        #endif
    }

    /// The id this capability gives a workgroup in the switcher. A terminal's own chrome uses it
    /// to exclude itself, so the two must agree — hence one function rather than two literals.
    public static func sessionID(workgroupID: UUID) -> String {
        "terminal:\(workgroupID.uuidString)"
    }

    public func open(service: HostServiceLink, host: HostProfile, report: @escaping GlassCapabilityReport) {
        open(service: service, host: host, hostAccess: GlassCapabilityHostAccess(address: host.address), report: report)
    }

    // MARK: Setup (the shell's host sheet)

    public func makeSetupDraft() -> any GlassServiceDraft {
        TerminalServiceDraft(serverManager: runtime.sessionManager.serverManager, settingsManager: runtime.settingsManager)
    }

    public func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? {
        guard let server = runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue) else {
            // **A link this device has no configuration for is still editable.**
            //
            // The service exists in the library because it synced; its settings are not here. The
            // failure the user gets says "Edit the service to set it up, or remove it", and until
            // now Edit was a dead end for exactly the case the sentence describes — the sheet had
            // no draft to show, so the only offered action that worked was the destructive one.
            //
            // A *new* draft, not an empty editor: `commit(endpointID:host:address:)` persists
            // under the endpoint id it is given, so setting it up here fills this link rather than
            // leaving it and making a second service beside it.
            return TerminalServiceDraft(serverManager: runtime.sessionManager.serverManager,
                                        settingsManager: runtime.settingsManager)
        }
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

    /// The saved server's SSH port, for the availability dot; none for this Mac's own shell.
    public func knownPort(service: HostServiceLink, host: HostProfile) -> Int? {
        guard service.endpointID != Self.localShellEndpointID else { return nil }
        return runtime.sessionManager.serverManager.server(for: service.endpointID.rawValue)?.port
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
        runtime.sessionManager.serverManager.reloadFromStore()
        // W15: the last run's terminal windows and tabs can come back now.
        runtime.noteCatalogLoaded()
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
                id: GlassTerminalRuntime.workgroupsPanelID,
                sectionTitle: "Workgroups",
                title: "Workgroups",
                symbolName: "rectangle.stack",
                count: runtime.settingsManager.layoutPresets.count,
                // On a phone the library pushes a panel's detail when the panel says something is
                // selected; without these a tapped workgroup went nowhere (the owner's iPhone,
                // 2026-10-12: "tapping a workgroup in iphone is a dead end").
                selection: { runtime.workgroupsModel.selection },
                clearSelection: { runtime.workgroupsModel.selection = nil },
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
        var tools = [
            GlassServiceTool(id: "files-\(serverID.uuidString.lowercased())",
                             title: "Files",
                             symbolName: "folder",
                             subtitle: "Browse this machine's files over SFTP") {
                runtime.requestConnect(serverID: serverID, purpose: .sftp)
            }
        ]
        // A host that keeps its terminals in tmux can still give a plain shell (the owner,
        // 2026-10-12: "allow remote sessions without tmux too even if it's been selected as
        // default"). Where it does not, Connect gives one already.
        if runtime.sessionManager.serverManager.server(for: serverID)?.keepsSessionsInTmux == true {
            tools.append(GlassServiceTool(id: "plain-terminal-\(serverID.uuidString.lowercased())",
                                          title: "Basic Terminal",
                                          symbolName: "terminal",
                                          subtitle: "A shell outside tmux: it ends when you close it") {
                runtime.requestConnect(serverID: serverID, withoutTmux: true)
            })
        }
        return tools
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
                    .environment(\.glassOpenFolderAsProject, runtime.openFolderAsProject)
                    .environment(\.glassOpenFileInEditor, runtime.openFileInEditor)
                    .environment(\.glassEditorFileScreen, runtime.editorFileScreen)
            } else {
                SFTPBrowserNotFoundView(context: router.sftpContext)
            }
        }
        // iPad: a window opened by Move Tab to New Window shows the tab's new workgroup (W15).
        // Once, as the window appears — after the Group, whose modifiers each of its views gets.
        .onAppear {
            if let workgroupID = runtime.takeWorkgroupAwaitingWindow(),
               runtime.sessionManager.workgroup(for: workgroupID) != nil {
                router.showTerminal(workgroupID: workgroupID)
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

/// The shell's `GlassHostPortForward` over a real `SSHTunnel`, on a connection of its own: closing
/// it closes that connection.
///
/// **Not on the terminals' shared connections (W21's pool), on purpose** (B-X5, 2026-10-13). The
/// pool exists for the server's limits, and a tunnel is not what they count: `MaxSessions` counts
/// shell, login and subsystem sessions and permits forwarding even at 0 (sshd_config(5)), and a
/// tunnel adds one sign-in when it opens. Sharing would put a desktop's frames or a large result
/// on the same TCP stream as every keystroke, which OpenSSH users see as interactive lag on a
/// multiplexed connection (openssh-unix-dev, 2009-10 and 2011-03), and would end the tunnel with
/// the terminals' connection.
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

/// An SFTP session held open for as long as a project is.
///
/// The transport is owned here rather than borrowed from a live terminal session, so opening a
/// project does not require the user to have a terminal window up — and closing the project drops
/// exactly what opening it made.
/// Internal rather than private so the live test can build one over a real SFTP session and
/// exercise the same object the app uses.
final class GlassTerminalDirectoryLister: GlassHostDirectoryLister {
    private let sftp: any SFTPSession
    /// The same client the Files browser uses, so the verified commit below is *the* verified
    /// commit rather than a second one written to look like it.
    private let client: SFTPClient
    private let transport: SSHTransport?
    private let owner: UUID
    private let serverID: UUID

    init(sftp: any SFTPSession, client: SFTPClient, transport: SSHTransport?, owner: UUID,
         serverID: UUID) {
        self.sftp = sftp
        self.client = client
        self.transport = transport
        self.owner = owner
        self.serverID = serverID
    }

    func list(_ path: String) async throws -> [GlassHostDirectoryEntry] {
        Self.entries(from: try await sftp.list(path))
    }

    /// The folder's entries as the editor gets them, **without names it must not join onto the
    /// folder** (S5; B-X22, 2026-10-13): the server sends the names, and the editor builds each
    /// child's path from one, so a name with `/` or NUL in it, or `.`/`..`, would reach outside the
    /// folder it was listed from. Left out, and counted in the log.
    static func entries(from listed: [SFTPEntry]) -> [GlassHostDirectoryEntry] {
        let safe = listed.filter(\.hasSafeName)
        if safe.count < listed.count {
            Logger.ssh.error("SFTP listing: left out \(listed.count - safe.count, privacy: .public) entries whose names are not a single path component")
        }
        return safe.map { GlassHostDirectoryEntry(name: $0.name, isDirectory: $0.attributes.isDirectory) }
    }

    /// Reads the whole file, in the chunks SFTP actually delivers: a read is answered with *at
    /// most* what was asked for, so a short answer means "less this time", not "end of file" —
    /// only a zero-length answer means that. Reading until the size is reached and then stopping
    /// would truncate any file whose size changed between the stat and the read.
    func read(_ path: String) async throws -> Data {
        let handle = try await sftp.open(path, mode: .read, permissions: nil)
        defer { Task { try? await handle.close() } }
        var data = Data()
        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try await handle.read(from: offset, length: 32_768)
            if chunk.isEmpty { break }
            data.append(chunk)
            offset += UInt64(chunk.count)
            guard data.count <= Self.fileByteCeiling else {
                throw GlassPortForwardError.unavailable
            }
        }
        return data
    }

    /// Writes the file back through the Files browser's verified commit.
    ///
    /// **Not a second implementation of saving.** That path stages the bytes locally, uploads them
    /// while checking continuously that the destination has not moved underneath, publishes only
    /// after verifying what landed, carries the original file's permissions and timestamps onto
    /// the replacement, and reports an ambiguous commit as ambiguous rather than as success or
    /// failure. A hand-rolled temporary-file-and-rename here would have looked equivalent and been
    /// none of those things — the first version of this method was exactly that, and it dropped a
    /// file's executable bit on every save.
    ///
    /// `expecting` is what the editor last saw. The commit refuses to land on anything else,
    /// which closes the window between the editor asking "has this changed?" and the bytes
    /// arriving.
    @discardableResult
    func write(_ data: Data, to path: String, expecting: GlassHostFileStamp?) async throws -> GlassHostFileStamp? {
        // What the destination is *now*, read the way the commit wants it: attributes and a digest
        // of the bytes, which is what lets it verify rather than hope.
        let current = try await SFTPBrowserView.readVerifiedRemoteObservation(
            client: client, path: path, maximumBytes: UInt64(Self.fileByteCeiling)
        )
        if let expecting, !Self.matches(expecting, current.stat) {
            throw GlassPortForwardError.targetChanged((path as NSString).lastPathComponent)
        }
        let result = try await SFTPBrowserView.uploadRemoteEditorBytes(
            data,
            client: client,
            serverID: serverID,
            remoteDirectory: (path as NSString).deletingLastPathComponent,
            filename: (path as NSString).lastPathComponent,
            targetPath: path,
            expectedRemote: current,
            maximumBytes: UInt64(Self.fileByteCeiling)
        )
        guard let committed = result.committedStat else {
            // The bytes went and the machine did not describe what it ended up with. Saying
            // "saved" would be a guess in the direction that loses work.
            throw GlassPortForwardError.commitOutcomeUnknown((path as NSString).lastPathComponent)
        }
        return GlassHostFileStamp(
            size: committed.size,
            modifiedAt: committed.modificationSeconds.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }

    /// Whether the destination is still the file the editor last saw. A field counts only when
    /// both sides carry it — a server that omits one proves nothing by omitting it.
    private static func matches(_ expecting: GlassHostFileStamp, _ now: RemoteStat) -> Bool {
        if let a = expecting.size, let b = now.size, a != b { return false }
        if let a = expecting.modifiedAt, let b = now.modificationSeconds,
           Int64(a.timeIntervalSince1970.rounded(.down)) != b { return false }
        return true
    }

    func stat(_ path: String) async throws -> GlassHostFileStamp? {
        guard let attributes = try? await sftp.attributes(at: path, followSymlinks: true) else {
            return nil
        }
        guard attributes.size != nil || attributes.modificationTime != nil else { return nil }
        return GlassHostFileStamp(size: attributes.size, modifiedAt: attributes.modificationTime)
    }

    /// A file the editor will hold entirely in memory and syntax-highlight. Past this it is not a
    /// document, and saying so beats reading 400 MB into a text view.
    private static let fileByteCeiling = 64 * 1024 * 1024

    func realPath(_ path: String) async throws -> String {
        try await sftp.realPath(path)
    }

    func close() async {
        try? await sftp.close()
        await transport?.release(owner: owner)
    }
}

extension GlassTerminalCapability {
    /// Opens an SFTP listing of `host`'s folders, using the host's saved SSH service — its
    /// credentials, its jump chain and its already-established host-key trust.
    ///
    /// The same borrow as `openPortForward`, and the same D14 rule: an unknown or changed host key
    /// surfaces the terminal's own fingerprint prompt rather than being refused or, worse, trusted
    /// silently. Opening a project is a foreground action; the user pressed Open and is waiting.
    ///
    /// The connection is opened again when it has gone (`GlassTerminalReconnectingLister`): a
    /// project stays open across a phone locking or a network changing.
    public func openDirectoryLister(host: HostProfile) async throws -> any GlassHostDirectoryLister {
        let first = try await openConnectedLister(host: host)
        return GlassTerminalReconnectingLister(machine: host.displayName, first: first) { [weak self] in
            guard let self else { throw SFTPSessionError.closed }
            return try await self.openConnectedLister(host: host)
        }
    }

    /// One connection's lister, as `openDirectoryLister` describes.
    private func openConnectedLister(host: HostProfile) async throws -> GlassTerminalDirectoryLister {
        let connection = try await openSFTPConnection(host: host)
        return GlassTerminalDirectoryLister(
            sftp: connection.sftp,
            client: connection.client,
            transport: connection.transport,
            owner: connection.owner,
            serverID: connection.server.id
        )
    }

    /// An SFTP session on the host's saved SSH service, on a connection of its own: its
    /// credentials, its jump chain, its host trust asked for as every connection asks (D14). The
    /// caller closes the client and releases `owner` on `transport`.
    private func openSFTPConnection(host: HostProfile) async throws
        -> (sftp: any SFTPSession, client: SFTPClient, transport: SSHTransport, owner: UUID, server: ServerConfiguration) {
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
            let sftp = try await transport.openSFTP()
            let extensions = await sftp.serverExtensions
            return (sftp, SFTPClient(session: sftp, extensions: extensions), transport, owner, server)
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

    /// Files sent to a machine from Shortcuts, Siri or the share sheet (D72): into `folder` on it —
    /// relative to the home folder, or absolute; the home folder itself when there is none — each
    /// under a name nothing there has, through the Files browser's verified upload, as a file dropped
    /// on a terminal goes (W14). Nothing there is ever replaced.
    public func sendFiles(_ files: [URL], toHost host: HostProfile, folder: String?) async throws -> GlassSentFiles {
        let connection = try await openSFTPConnection(host: host)
        let result: GlassSentFiles
        do {
            let home = try await connection.client.getRealPath(atPath: ".")
            let target = GlassSentFiles.remoteFolder(folder, home: home)
            guard let attributes = try? await connection.client.getAttributes(at: target.path),
                  attributes.fileType == .directory else {
                throw GlassSentFiles.Failure.noFolder(target.shown, machine: host.displayName)
            }
            let drop = TerminalRemoteDropHost(client: connection.client, serverID: connection.server.id,
                                              upload: SFTPBrowserView.uploadDroppedFile)
            let outcomes = await drop.send(files, into: target.path)
            result = GlassSentFiles(
                machine: host.displayName, folder: target.shown,
                arrived: outcomes.filter { $0.remotePath != nil }.map(\.name),
                failed: outcomes.compactMap { outcome in outcome.failure.map { (outcome.name, Self.sendReason($0)) } }
                    .map { GlassSentFiles.Problem(name: $0.0, reason: $0.1) })
        } catch {
            try? await connection.client.close()
            await connection.transport.release(owner: connection.owner)
            throw error
        }
        try? await connection.client.close()
        await connection.transport.release(owner: connection.owner)
        return result
    }

    /// A drop's failure, as sending a file says it.
    private static func sendReason(_ failure: TerminalRemoteDropFailure) -> String {
        switch failure {
        case .folderRefused: "the folder could not be read. Check that your account can write to it."
        case .connectionLost: "the connection ended. Send it again."
        case .didNotFinish: "the upload didn't finish. Send it again."
        default: failure.reason
        }
    }

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

/// What `GlassTerminalCapability.sendFiles` did (D72): the files that arrived, and the ones that did
/// not with why, in words for the person who sent them.
public struct GlassSentFiles: Sendable, Equatable {
    public struct Problem: Sendable, Equatable {
        public let name: String
        public let reason: String
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case noFolder(String, machine: String)

        public var errorDescription: String? {
            switch self {
            case let .noFolder(folder, machine): "\(machine) has no folder \(folder). Choose a folder that exists, or leave it empty for your home folder."
            }
        }
    }

    public let machine: String
    /// The folder, as the person would write it: `~`, `~/Uploads`, `/srv/share`.
    public let folder: String
    public let arrived: [String]
    public let failed: [Problem]

    /// One sentence for Siri or Shortcuts to say.
    public var summary: String {
        var parts: [String] = []
        if !arrived.isEmpty {
            let what = arrived.count == 1 ? arrived[0] : "\(arrived.count) files"
            parts.append("Sent \(what) to \(folder) on \(machine).")
        }
        for problem in failed { parts.append("\(problem.name) wasn't sent: \(problem.reason)") }
        return parts.isEmpty ? "Nothing was sent." : parts.joined(separator: " ")
    }

    /// The folder to send into: `folder` under the home folder, or absolute as given; the home
    /// folder for none. `shown` is how to name it back.
    static func remoteFolder(_ folder: String?, home: String) -> (path: String, shown: String) {
        let base = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        var trimmed = (folder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" || trimmed.isEmpty { return (base, "~") }
        if trimmed.hasPrefix("~/") { trimmed.removeFirst(2) }
        if trimmed.hasPrefix("/") { return (trimmed, trimmed) }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return (base + "/" + trimmed, "~/" + trimmed)
    }
}
