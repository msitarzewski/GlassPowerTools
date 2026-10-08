#if os(macOS)
#if os(macOS)
import Foundation
import Observation
import GlassTerminalEmulator
import os

@MainActor
@Observable
final class MacWorkspaceController {
    private static let maximumEncodedBytes = 128 * 1024

    private(set) var state: MacWorkspaceRestorationState
    private(set) var sessionsByPaneID: [UUID: TerminalSession] = [:]
    private(set) var loadingPaneIDs: Set<UUID> = []
    private(set) var errorsByPaneID: [UUID: String] = [:]
    private(set) var pendingCredentialErrorsByPaneID: [UUID: SessionOpenError] = [:]
    private(set) var explicitStartupCommandsByPaneID: [UUID: String] = [:]
    private var retainedStartupTicketsByPaneID: [UUID: TerminalStartupCommandTicket] = [:]
    private(set) var localRuntimesByPaneID: [UUID: SwiftTermLocalProcessRuntime] = [:]
    private(set) var localProcessStatusesByPaneID: [UUID: String] = [:]
    private(set) var recordersByPaneID: [UUID: SessionRecorder] = [:]
    private(set) var findTargetPaneID: UUID?
    private(set) var findRequestNonce: UInt64 = 0
    private(set) var isClosed = false
    var pendingSSHAxis: MacWorkspaceSplitAxis?

    private let defaults: UserDefaults
    private let startupCommandBroker: MacStartupCommandBroker
    private let liveSessionBroker: MacLiveSessionBroker
    private var startupTicketIDsByPaneID: [UUID: UUID] = [:]
    private var lifecycleGeneration: UInt64 = 0

    let workgroupID: UUID?
    let workgroupName: String?
    let workgroupColor: ServerColorTag?
    /// The name someone gave this tab, or nil for the automatic one (`MacWorkspaceTabNaming`).
    private(set) var tabLabel: String?
    /// What each pane's terminal says about itself, for the automatic name.
    private(set) var paneContextByPaneID: [UUID: MacWorkspacePaneContext] = [:]
    /// The shortest time between two changes of the automatic name; zero applies every change.
    @ObservationIgnored var paneContextInterval: Duration = .milliseconds(500)
    @ObservationIgnored private var pendingPaneContextByPaneID: [UUID: MacWorkspacePaneContext] = [:]
    @ObservationIgnored private var paneContextFlush: Task<Void, Never>?
    @ObservationIgnored private var pendingScrollByPaneID: [UUID: Double] = [:]
    @ObservationIgnored private var scrollFlush: Task<Void, Never>?
    /// A terminal in this tab printed something in the last moment: the sidebar's activity wave.
    private(set) var isProducingOutput = false
    @ObservationIgnored private var quietTask: Task<Void, Never>?
    /// How long after the last output a tab still counts as busy.
    static let activityLinger: Duration = .milliseconds(1_200)

    init(
        workspaceID: UUID,
        startsEmptyIfUnrestored: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.startupCommandBroker = .shared
        self.liveSessionBroker = .shared
        self.workgroupID = nil
        self.workgroupName = nil
        self.workgroupColor = nil
        self.tabLabel = nil
        self.state = Self.load(
            workspaceID: workspaceID,
            startsEmptyIfUnrestored: startsEmptyIfUnrestored,
            initialPaneIntent: nil,
            defaults: defaults
        ).state
    }

    convenience init(
        request: MacWorkspaceLaunchRequest,
        startupCommandBroker: MacStartupCommandBroker = .shared,
        liveSessionBroker: MacLiveSessionBroker = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            request: request.tabs[0],
            startupCommandBroker: startupCommandBroker,
            liveSessionBroker: liveSessionBroker,
            defaults: defaults
        )
    }

    init(
        request: MacWorkspaceTabRequest,
        startupCommandBroker: MacStartupCommandBroker = .shared,
        liveSessionBroker: MacLiveSessionBroker = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.startupCommandBroker = startupCommandBroker
        self.liveSessionBroker = liveSessionBroker
        self.workgroupID = request.workgroupID
        self.workgroupName = request.workgroupName
        self.workgroupColor = request.workgroupColor
        self.tabLabel = request.tabLabel
        let loaded = Self.load(
            workspaceID: request.workspaceID,
            startsEmptyIfUnrestored: request.startsEmpty,
            initialPaneIntent: request.initialPaneIntent,
            defaults: defaults
        )
        self.state = loaded.state
        var acceptedInitialLayout = false
        if !loaded.hadRestorationData, let initial = request.initialState,
           let validated = try? initial.validated(for: request.workspaceID) {
            self.state = validated
            acceptedInitialLayout = true
            startupTicketIDsByPaneID = request.paneStartupTicketIDs ?? [:]
        } else {
            for id in request.paneStartupTicketIDs?.values ?? Dictionary<UUID, UUID>().values {
                startupCommandBroker.discard(id)
            }
        }
        if !loaded.hadRestorationData,
           let paneID = loaded.state.focusedPaneID,
           let ticketID = request.startupTicketID {
            startupTicketIDsByPaneID[paneID] = ticketID
        } else if let ticketID = request.startupTicketID {
            startupCommandBroker.discard(ticketID)
        }
        if !loaded.hadRestorationData,
           let paneID = loaded.state.focusedPaneID,
           let pane = loaded.state.root?.pane(id: paneID),
           let ticketID = request.liveSessionTicketID {
            if let ticket = liveSessionBroker.claim(ticketID) {
                if pane.intent.kind == .ssh,
                   pane.intent.serverID == ticket.session.server.id {
                    sessionsByPaneID[paneID] = ticket.session
                    observeOutput(of: ticket.session.terminalHostModel)
                } else {
                    ticket.discard()
                    errorsByPaneID[paneID] = "The prepared terminal session did not match its launch request."
                }
            } else {
                errorsByPaneID[paneID] = "The prepared terminal session expired before its window opened."
            }
        } else if let ticketID = request.liveSessionTicketID {
            liveSessionBroker.discard(ticketID)
        }
        for (paneID, ticketID) in startupTicketIDsByPaneID {
            guard state.root?.pane(id: paneID) != nil else {
                startupCommandBroker.discard(ticketID)
                continue
            }
            if let ticket = startupCommandBroker.claim(ticketID) {
                retainedStartupTicketsByPaneID[paneID] = ticket
                explicitStartupCommandsByPaneID[paneID] = ticket.command
            }
        }
        startupTicketIDsByPaneID.removeAll()
        let assignedTmuxSessions = assignLocalTmuxSessions()
        // Unselected tabs may never receive a focus or layout event. Save their
        // fresh trees now so window descriptors can restore every tab later.
        // Existing malformed restoration data is deliberately left untouched.
        if !loaded.hadRestorationData && (request.initialState == nil || acceptedInitialLayout) {
            persist()
        } else if loaded.hadRestorationData && assignedTmuxSessions {
            persist()
        }
    }

    var workspaceID: UUID { state.id }
    var restorationDescriptor: MacWorkspaceTabDescriptor {
        MacWorkspaceTabDescriptor(
            MacWorkspaceTabRequest(
                workspaceID: workspaceID,
                workgroupID: workgroupID,
                workgroupName: workgroupName,
                workgroupColor: workgroupColor,
                tabLabel: tabLabel
            )
        )
    }
    var focusedPaneID: UUID? { state.focusedPaneID }

    /// D44: closing this tab would stop something — a local shell, a pane still opening, or an
    /// SSH terminal not kept in tmux. Terminals in tmux, local ones included (D47), keep running,
    /// so they do not count; the same holds for quitting.
    var closeStopsWork: Bool {
        localRuntimesByPaneID.keys.contains { localTmuxSession(for: $0) == nil }
            || !loadingPaneIDs.isEmpty
            || sessionsByPaneID.values.contains(where: \.closeStopsWork)
    }
    var hasTerminalsInTmux: Bool { sessionsByPaneID.values.contains(where: \.survivesClose) || hasLocalTerminalsInTmux }
    var hasLocalTerminalsInTmux: Bool { localRuntimesByPaneID.keys.contains { localTmuxSession(for: $0) != nil } }

    func localTmuxSession(for paneID: UUID) -> String? {
        state.root?.pane(id: paneID)?.intent.localTmuxSession
    }

    /// Scrolling over a local pane in tmux scrolls tmux's history, rather than arriving as arrow
    /// keys (2026-10-08). Amounts are gathered for a frame and sent as whole lines.
    func scrollLocalTmux(_ paneID: UUID, deltaY: CGFloat, precise: Bool) -> Bool {
        guard localTmuxSession(for: paneID) != nil else { return false }
        // A trackpad reports points, a mouse wheel lines; a terminal line is about 16 points.
        pendingScrollByPaneID[paneID, default: 0] += precise ? Double(deltaY) / 16 : Double(deltaY)
        if scrollFlush == nil {
            scrollFlush = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(30))
                self?.flushLocalTmuxScroll()
            }
        }
        return true
    }

    private func flushLocalTmuxScroll() {
        scrollFlush = nil
        let server = MacLocalTmux.server
        guard let tmux = server.executablePath() else { return pendingScrollByPaneID.removeAll() }
        for (paneID, amount) in pendingScrollByPaneID {
            let lines = Int(amount.rounded(.towardZero))
            pendingScrollByPaneID[paneID] = amount - Double(lines)
            guard lines != 0, let session = localTmuxSession(for: paneID) else { continue }
            server.scroll(session, lines, tmux)
        }
    }

    /// Where a local pane's shell is. In tmux the process Glass started is the tmux client, whose
    /// directory never moves, so the answer is the one tmux gave.
    func localDirectory(for paneID: UUID) -> String? {
        localTmuxSession(for: paneID) == nil
            ? localRuntimesByPaneID[paneID]?.currentWorkingDirectory
            : paneContextByPaneID[paneID]?.directory
    }

    /// The same, for the focused pane alone.
    var focusedPaneCloseStopsWork: Bool {
        guard let id = focusedPaneID else { return false }
        return (localRuntimesByPaneID[id] != nil && localTmuxSession(for: id) == nil)
            || loadingPaneIDs.contains(id) || sessionsByPaneID[id]?.closeStopsWork == true
    }
    var focusedPane: MacWorkspacePane? {
        guard let focusedPaneID else { return nil }
        return state.root?.pane(id: focusedPaneID)
    }

    var isEmpty: Bool { state.root == nil }
    var windowTitle: String {
        switch (workgroupName, tabLabel) {
        case let (.some(workgroup), .some(tab)): "\(workgroup) · \(tab)"
        case let (.some(workgroup), .none): workgroup
        case let (.none, .some(tab)): tab
        case (.none, .none): "Terminal"
        }
    }
    var canAddPane: Bool {
        (state.root?.paneIDs.count ?? 0) < MacWorkspaceRestorationState.maximumPaneCount
    }

    func windowIdentity(
        servers: [ServerConfiguration],
        localUsername: String = NSUserName(),
        home: String? = NSHomeDirectory()
    ) -> MacWorkspaceWindowIdentity {
        guard let focusedPane else {
            return MacWorkspaceWindowIdentity(
                title: windowTitle == "Terminal" ? "New Terminal" : windowTitle,
                subtitle: nil
            )
        }

        switch focusedPane.intent.kind {
        case .local:
            // The subtitle is where it stands: on this Mac, "user@localhost" said nothing two
            // local tabs did not share.
            let context = paneContextByPaneID[focusedPane.id]
            // Named, else configured, else what the terminal says, else the workgroup, else the
            // tmux session as Active names it, else the shell.
            let shell = localRuntimesByPaneID[focusedPane.id]?.launchedShell.map { ($0 as NSString).lastPathComponent }
            let title = tabLabel ?? focusedPane.intent.label
                ?? MacWorkspaceTabNaming.automaticTitle(context, home: home) ?? workgroupName
                ?? focusedPane.intent.localTmuxSession.map(MacWorkspaceTabNaming.tmuxDisplayName)
                ?? (shell == "tmux" ? nil : shell) ?? "Local"
            // The folder, unless the title already says exactly that: "~" over "~" said it twice
            // and nothing else (2026-10-08). Then the machine, as before.
            let directory = context?.directory.map { MacWorkspaceTabNaming.abbreviated($0, home: home) }
            var subtitle = directory.flatMap { $0 == title ? nil : $0 } ?? "\(localUsername)@localhost"
            if focusedPane.intent.localTmuxSession != nil { subtitle += " · in tmux" }
            if let status = localProcessStatusesByPaneID[focusedPane.id] { subtitle += " — \(status)" }
            return MacWorkspaceWindowIdentity(title: title, subtitle: subtitle)
        case .ssh:
            let server = session(for: focusedPane.id)?.server
                ?? servers.first(where: { $0.id == focusedPane.intent.serverID })
            guard let server else {
                return MacWorkspaceWindowIdentity(
                    title: tabLabel ?? workgroupName ?? "SSH Terminal",
                    subtitle: nil
                )
            }
            // A remote home is unknown here, so a remote directory is named by its last part.
            return MacWorkspaceWindowIdentity(
                title: tabLabel ?? focusedPane.intent.label
                    ?? MacWorkspaceTabNaming.automaticTitle(paneContextByPaneID[focusedPane.id], home: nil)
                    ?? server.name,
                subtitle: Self.connectionSubtitle(
                    "\(server.username)@\(server.host):\(server.port)",
                    state: session(for: focusedPane.id)?.state
                )
            )
        }
    }

    func focusedSessionState() -> SessionState? {
        guard let focusedPaneID else { return nil }
        return session(for: focusedPaneID)?.state
    }

    /// Output arrived in one of this tab's terminals: busy now, quiet again once it stops.
    func noteOutput() {
        guard !isClosed else { return }
        if !isProducingOutput { isProducingOutput = true }
        quietTask?.cancel()
        quietTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.activityLinger)
            guard !Task.isCancelled, let self else { return }
            isProducingOutput = false
            refreshLocalTmuxContext()
        }
    }

    /// D47: tmux keeps a shell's title and directory from the terminal outside it, so a tab in
    /// tmux asks tmux what its panes show once output settles.
    private func refreshLocalTmuxContext() {
        let panes = localRuntimesByPaneID.keys.compactMap { id in localTmuxSession(for: id).map { (id, $0) } }
        guard !panes.isEmpty, let tmux = MacLocalTmux.executablePath() else { return }
        Task.detached(priority: .utility) { [weak self] in
            let contexts = panes.compactMap { paneID, session in
                MacLocalTmux.context(session: session, tmux: tmux).map { (paneID, $0) }
            }
            await MainActor.run { [weak self] in
                for (paneID, context) in contexts { self?.setPaneContext(context, for: paneID) }
            }
        }
    }

    private func observeOutput(of model: SwiftTermHostModel) {
        model.onOutputActivity = { [weak self] in self?.noteOutput() }
    }

    /// Names the tab; blank goes back to the automatic name. The window saves it with its tabs.
    func rename(to name: String?) {
        guard !isClosed else { return }
        tabLabel = MacWorkspaceChromeText.sanitize(name, maximumLength: MacWorkspaceTabRequest.maximumDisplayTextLength)
    }

    /// The title a pane's shell or program set, and its directory, as they change. A pane in
    /// tmux sees only tmux's own, so its context comes from `refreshLocalTmuxContext` instead.
    func updatePaneContext(title: String?, directory: String?, for paneID: UUID) {
        guard localTmuxSession(for: paneID) == nil else { return }
        let context = MacWorkspacePaneContext(title: title, directory: directory)
        guard paneContextInterval > .zero else { return setPaneContext(context, for: paneID) }
        // At most twice a second: a program animating its title (Claude Code's spinner) would
        // otherwise retitle the window and redraw the sidebar on every frame. The first change
        // shows at once; the latest one at the end of each interval.
        guard paneContextFlush != nil else {
            setPaneContext(context, for: paneID)
            schedulePaneContextFlush()
            return
        }
        pendingPaneContextByPaneID[paneID] = context
    }

    private func schedulePaneContextFlush() {
        paneContextFlush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.paneContextInterval ?? .zero)
            guard let self else { return }
            let pending = pendingPaneContextByPaneID
            pendingPaneContextByPaneID = [:]
            paneContextFlush = nil
            guard !pending.isEmpty else { return }
            for (paneID, context) in pending { setPaneContext(context, for: paneID) }
            schedulePaneContextFlush()
        }
    }

    private func setPaneContext(_ context: MacWorkspacePaneContext, for paneID: UUID) {
        guard !isClosed, state.root?.pane(id: paneID) != nil else { return }
        if paneContextByPaneID[paneID] != context { paneContextByPaneID[paneID] = context }
    }

    func updateLocalProcessStatus(_ status: String?, for paneID: UUID) {
        guard !isClosed, state.root?.pane(id: paneID)?.intent.kind == .local else { return }
        localProcessStatusesByPaneID[paneID] = status
    }

    static func connectionSubtitle(_ connection: String, state: SessionState?) -> String {
        let status: String
        switch state {
        case .connected, nil: return connection
        case .connecting: status = "Connecting…"
        case .reconnecting: status = "Reconnecting…"
        case .disconnected: status = "Disconnected"
        case .error: status = "Connection failed"
        }
        return "\(connection) — \(status)"
    }

    func session(for paneID: UUID) -> TerminalSession? {
        sessionsByPaneID[paneID]
    }

    func localRuntime(for paneID: UUID) -> SwiftTermLocalProcessRuntime? {
        guard !isClosed,
              state.root?.pane(id: paneID)?.intent.kind == .local else { return nil }
        if let runtime = localRuntimesByPaneID[paneID] {
            return runtime
        }
        // Never a second tmux client for a session a tab here already shows: it would mirror
        // that tab's window. The pane says so instead (`MacWorkspaceTabContent`).
        let tmuxSession = localTmuxSession(for: paneID)
        if let tmuxSession, !MacLocalTmux.claimShown(tmuxSession) { return nil }
        let runtime = SwiftTermLocalProcessRuntime()
        localRuntimesByPaneID[paneID] = runtime
        observeOutput(of: runtime.model)
        if tmuxSession != nil {
            runtime.model.onAlternateScreenScroll = { [weak self] deltaY, precise in
                self?.scrollLocalTmux(paneID, deltaY: deltaY, precise: precise) ?? false
            }
        }
        return runtime
    }

    func recorder(for paneID: UUID) -> SessionRecorder? {
        guard !isClosed,
              state.root?.pane(id: paneID) != nil else { return nil }
        if let recorder = recordersByPaneID[paneID] {
            return recorder
        }
        let recorder = SessionRecorder()
        recordersByPaneID[paneID] = recorder
        return recorder
    }

    /// Start every local pane independently of SwiftUI's lazy tab presentation.
    func startLocalPanes(sessionManager: SessionManager, settingsManager: SettingsManager, onEmpty: @escaping () -> Void) {
        for pane in state.root?.panes ?? [] where pane.intent.kind == .local {
            guard let runtime = localRuntime(for: pane.id), !runtime.hasEngine,
                  let recorder = recorder(for: pane.id) else { continue }
            runtime.start(
                configuration: MacLocalTerminalConfiguration.resolve(
                    shell: pane.intent.localShell ?? settingsManager.localShell,
                    directory: pane.intent.localDirectory ?? settingsManager.localWorkingDirectory,
                    tmuxSession: pane.intent.localTmuxSession
                ),
                theme: settingsManager.currentTheme.swiftTermTheme,
                runtimeSettings: SwiftTermRuntimeSettings(
                    cursorStyle: settingsManager.cursorStyle,
                    blinkingCursor: settingsManager.blinkingCursor,
                    scrollbackLines: settingsManager.saveScrollback ? settingsManager.maxScrollbackLines : 0
                ),
                onOutputData: { recorder.recordOutput($0) },
                onInputData: { recorder.recordInput($0) },
                onResize: { recorder.recordResize(width: $0, height: $1) },
                onProcessReady: { [weak self, weak runtime] in
                    guard let ticket = self?.claimStartupCommand(for: pane.id) else { return }
                    _ = runtime?.processState.sendCommand(ticket.command)
                },
                onProcessTerminated: { [weak self] exitCode in
                    if recorder.isRecording { _ = recorder.stop() }
                    guard let self, !isClosed,
                          MacLocalTerminalExitPolicy.shouldClose(exitCode: exitCode) else { return }
                    removePane(pane.id, sessionManager: sessionManager)
                    if state.root == nil { onEmpty() }
                }
            )
        }
    }

    func error(for paneID: UUID) -> String? {
        errorsByPaneID[paneID]
    }

    func isLoading(_ paneID: UUID) -> Bool {
        loadingPaneIDs.contains(paneID)
    }

    var closeWarning: String? {
        if recordersByPaneID.values.contains(where: \.isRecording)
            || sessionsByPaneID.values.contains(where: { $0.recorder?.isRecording == true }) {
            return "This tab is recording. Closing it will stop the recording and disconnect its terminals."
        }
        if !loadingPaneIDs.isEmpty {
            return "This tab is still starting a connection. Closing it will cancel that connection."
        }
        if sessionsByPaneID.values.contains(where: {
            $0.state == .connected || $0.state == .connecting || $0.pendingHostKeyChallenge != nil
        }) {
            return "This tab has an SSH session. Remote command activity cannot be verified; closing it will disconnect the session."
        }
        if localRuntimesByPaneID.contains(where: { paneID, runtime in
            localTmuxSession(for: paneID) == nil
                && runtime.processState.isRunning && runtime.hasActiveChildProcesses != false
        }) {
            return "This tab has running commands, or its activity could not be verified. Closing it will stop those commands."
        }
        return nil
    }

    func focus(_ paneID: UUID) {
        guard state.root?.pane(id: paneID) != nil else { return }
        state.focusedPaneID = paneID
        persist()
    }

    func focusNextPane() {
        let paneIDs = state.root?.paneIDs ?? []
        guard !paneIDs.isEmpty else { return }
        guard let focusedPaneID,
              let index = paneIDs.firstIndex(of: focusedPaneID) else {
            focus(paneIDs[0])
            return
        }
        focus(paneIDs[(index + 1) % paneIDs.count])
    }

    func addPane(
        intent: MacWorkspacePaneIntent,
        axis: MacWorkspaceSplitAxis
    ) {
        guard canAddPane else { return }
        let newPane = MacWorkspacePane(intent: intent)
        guard let root = state.root else {
            state.root = .pane(newPane)
            state.focusedPaneID = newPane.id
            assignLocalTmuxSessions()
            persist()
            return
        }
        let targetID = state.focusedPaneID ?? root.paneIDs.first
        guard let targetID else { return }
        state.root = root.splittingPane(id: targetID, axis: axis, newPane: newPane)
        state.focusedPaneID = newPane.id
        assignLocalTmuxSessions()
        persist()
    }

    /// D47: give each local pane its tmux session while "Keep local terminals running with tmux"
    /// is on, and let go of a saved one that is no longer running once it is off. Runs as panes
    /// enter the tab, so every launch path — `startLocalPanes`, the pane view, a restart — reads
    /// one saved name. Returns whether anything changed.
    @discardableResult
    private func assignLocalTmuxSessions() -> Bool {
        guard let root = state.root else { return false }
        let enabled = defaults.bool(forKey: UserDefaultsKeys.localTmux)
        let panes = root.panes.filter {
            $0.intent.kind == .local && (enabled || $0.intent.localTmuxSession != nil)
        }
        guard !panes.isEmpty else { return false }
        let server = MacLocalTmux.server
        let tmux = server.executablePath()
        var running: Set<String>?
        var unreadable = false
        var updated = root
        for pane in panes {
            let session = tmux.flatMap { tmux in
                MacLocalTmux.session(
                    saved: pane.intent.localTmuxSession,
                    enabled: enabled,
                    isRunning: { name in
                        if running == nil, !unreadable {
                            running = MacLocalTmux.listing(tmux: tmux).map { Set($0.map(\.name)) }
                            unreadable = running == nil
                        }
                        // Unread, a saved session is kept: it may well be running.
                        return unreadable || running?.contains(name) == true
                    },
                    allocate: { MacLocalTmux.allocateName(tmux: tmux, launch: localTmuxLaunch(for: pane)) }
                )
            }
            // Restored, or opened from Active: no other pane is given it, running yet or not.
            if let session { MacLocalTmux.reserve(session) }
            guard session != pane.intent.localTmuxSession else { continue }
            updated = updated.updatingPane(id: pane.id) { $0.intent.localTmuxSession = session }
        }
        guard updated != root else { return false }
        state.root = updated
        return true
    }

    /// What the pane will start its session with, as `startLocalPanes` and the pane view resolve
    /// it: the pane's own shell and folder, else the Settings ones (saved in `defaults`), else
    /// the login shell and Home. A new pane has no shell running yet, so not `localDirectory(for:)`.
    private func localTmuxLaunch(for pane: MacWorkspacePane) -> MacLocalTmux.Launch {
        MacLocalTerminalConfiguration.tmuxLaunch(
            shell: pane.intent.localShell ?? defaults.string(forKey: UserDefaultsKeys.localShell),
            directory: pane.intent.localDirectory ?? defaults.string(forKey: UserDefaultsKeys.localWorkingDirectory)
        )
    }

    func requestSSHPane(axis: MacWorkspaceSplitAxis) {
        pendingSSHAxis = axis
    }

    func addSSHPane(serverID: UUID) {
        let axis = pendingSSHAxis ?? .horizontal
        pendingSSHAxis = nil
        addPane(intent: .ssh(serverID: serverID), axis: axis)
    }

    func cancelSSHPaneRequest() {
        pendingSSHAxis = nil
    }

    func removeFocusedPane(sessionManager: SessionManager) {
        guard let paneID = state.focusedPaneID else { return }
        removePane(paneID, sessionManager: sessionManager)
    }

    /// A local pane in tmux detaches: its session keeps running, and Active lists it (D47).
    func removePane(_ paneID: UUID, sessionManager: SessionManager) {
        guard !isClosed, let root = state.root, let pane = root.pane(id: paneID) else { return }
        if let tmuxSession = pane.intent.localTmuxSession {
            letGoOfLocalTmuxSession(tmuxSession, wasShown: localRuntimesByPaneID[paneID] != nil)
        }
        if let session = sessionsByPaneID.removeValue(forKey: paneID) {
            sessionManager.closeSession(session)
        }
        loadingPaneIDs.remove(paneID)
        errorsByPaneID.removeValue(forKey: paneID)
        localRuntimesByPaneID.removeValue(forKey: paneID)?.terminate()
        localProcessStatusesByPaneID.removeValue(forKey: paneID)
        paneContextByPaneID.removeValue(forKey: paneID)
        recordersByPaneID.removeValue(forKey: paneID)?.finalize()
        discardStartupCommand(for: paneID)
        state.root = root.removingPane(id: paneID)
        state.focusedPaneID = state.root?.paneIDs.first
        persist()
    }

    func updateSplitFraction(_ splitID: UUID, fraction: Double) {
        guard let root = state.root, fraction.isFinite else { return }
        state.root = root.updatingSplitFraction(id: splitID, fraction: fraction)
        persist()
    }

    func retryPane(_ paneID: UUID) {
        guard !isClosed else { return }
        errorsByPaneID.removeValue(forKey: paneID)
        pendingCredentialErrorsByPaneID.removeValue(forKey: paneID)
    }

    func disconnectSSHPane(_ paneID: UUID, sessionManager: SessionManager) {
        guard !isClosed,
              state.root?.pane(id: paneID)?.intent.kind == .ssh else { return }
        if let session = sessionsByPaneID.removeValue(forKey: paneID) {
            sessionManager.closeSession(session)
        }
        loadingPaneIDs.remove(paneID)
        errorsByPaneID[paneID] = "The SSH session ended. Retry to reconnect."
    }

    @discardableResult
    func completeCleanSSHExit(_ paneID: UUID, sessionManager: SessionManager) -> Bool {
        guard !isClosed,
              state.root?.pane(id: paneID)?.intent.kind == .ssh else { return false }
        let closesWorkspace = state.root?.panes.count == 1
        removePane(paneID, sessionManager: sessionManager)
        return closesWorkspace
    }

    func requestFindInFocusedPane() {
        guard let focusedPaneID else { return }
        findTargetPaneID = focusedPaneID
        findRequestNonce &+= 1
    }

    private func prepareOffscreenRenderer(for session: TerminalSession, settingsManager: SettingsManager) {
        let model = session.terminalHostModel
        SwiftTermHostView(model: model,
            theme: settingsManager.currentTheme.swiftTermTheme,
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: settingsManager.cursorStyle,
                blinkingCursor: settingsManager.blinkingCursor,
                scrollbackLines: settingsManager.saveScrollback ? settingsManager.maxScrollbackLines : 0),
            allowsFocusOwnership: false,
            onSendData: { [weak session] data in session?.sendTerminalData(data) },
            onResize: { [weak session, weak model] columns, rows in
                // Offscreen geometry is the configured fallback, not a measured window.
                guard model?.rendererDiagnostics.isWindowAttached == true else { return }
                session?.updateTerminalGeometry(rows: rows, columns: columns)
            }
        ).prepareOffscreen(columns: session.currentTerminalGeometry.columns,
                           rows: session.currentTerminalGeometry.rows)
    }

    func prepareSSHPaneIfNeeded(
        _ pane: MacWorkspacePane,
        sessionManager: SessionManager,
        settingsManager: SettingsManager
    ) async {
        guard !isClosed,
              pane.intent.kind == .ssh,
              let serverID = pane.intent.serverID,
              sessionsByPaneID[pane.id] == nil,
              !loadingPaneIDs.contains(pane.id),
              errorsByPaneID[pane.id] == nil else { return }

        let generation = lifecycleGeneration
        loadingPaneIDs.insert(pane.id)
        defer { loadingPaneIDs.remove(pane.id) }

        let startupTicket = retainedStartupTicketsByPaneID.removeValue(forKey: pane.id) ?? claimStartupCommand(for: pane.id)
        let startupCommand = startupTicket?.command
        do {
            let launch = try await sessionManager.createAuthorizedSessionByServerID(
                serverID,
                settingsManager: settingsManager,
                startupCommand: startupCommand,
                initialTerminalPresentation: { [weak self] pendingSession in
                    guard let self,
                          !isClosed,
                          generation == lifecycleGeneration,
                          state.root?.pane(id: pane.id)?.intent == pane.intent else { return }
                    sessionsByPaneID[pane.id] = pendingSession
                    observeOutput(of: pendingSession.terminalHostModel)
                    prepareOffscreenRenderer(for: pendingSession, settingsManager: settingsManager)
                }
            )
            guard !isClosed,
                  generation == lifecycleGeneration,
                  state.root?.pane(id: pane.id)?.intent == pane.intent else {
                sessionManager.closeSession(launch.session)
                return
            }
            if launch.session.state == .connected || launch.session.pendingHostKeyChallenge != nil {
                sessionsByPaneID[pane.id] = launch.session
                observeOutput(of: launch.session.terminalHostModel)
            } else {
                if case .error(let message) = launch.session.state {
                    errorsByPaneID[pane.id] = message
                } else {
                    errorsByPaneID[pane.id] = "The SSH session ended before the pane opened."
                }
                if launch.session.hasPendingStartupCommand {
                    retainedStartupTicketsByPaneID[pane.id] = startupTicket
                }
                sessionsByPaneID.removeValue(forKey: pane.id)
                sessionManager.closeSession(launch.session)
            }
        } catch {
            guard !isClosed,
                  generation == lifecycleGeneration,
                  state.root?.pane(id: pane.id)?.intent == pane.intent else { return }
            errorsByPaneID[pane.id] = error.localizedDescription
            let pendingSession = sessionsByPaneID.removeValue(forKey: pane.id)
            if pendingSession == nil || pendingSession?.hasPendingStartupCommand == true {
                retainedStartupTicketsByPaneID[pane.id] = startupTicket
            }
            if let pendingSession { sessionManager.closeSession(pendingSession) }
            if let credentialError = error as? SessionOpenError {
                pendingCredentialErrorsByPaneID[pane.id] = credentialError
            }
        }
    }

    func closeAllSessions(sessionManager: SessionManager) {
        // Local terminals in tmux detach: they keep running, for Active or the next launch.
        for pane in state.root?.panes ?? [] {
            guard let tmuxSession = pane.intent.localTmuxSession else { continue }
            letGoOfLocalTmuxSession(tmuxSession, wasShown: localRuntimesByPaneID[pane.id] != nil)
        }
        isClosed = true
        lifecycleGeneration &+= 1
        let sessions = Array(sessionsByPaneID.values)
        sessionsByPaneID.removeAll()
        let localRuntimes = Array(localRuntimesByPaneID.values)
        localRuntimesByPaneID.removeAll()
        let recorders = Array(recordersByPaneID.values)
        recordersByPaneID.removeAll()
        loadingPaneIDs.removeAll()
        for ticketID in startupTicketIDsByPaneID.values {
            startupCommandBroker.discard(ticketID)
        }
        startupTicketIDsByPaneID.removeAll()
        retainedStartupTicketsByPaneID.removeAll()
        explicitStartupCommandsByPaneID.removeAll()
        pendingCredentialErrorsByPaneID.removeAll()
        for session in sessions {
            sessionManager.closeSession(session)
        }
        for runtime in localRuntimes {
            runtime.terminate()
        }
        for recorder in recorders {
            recorder.finalize()
        }
    }

    private func letGoOfLocalTmuxSession(_ name: String, wasShown: Bool) {
        MacLocalTmux.release(name)
        if wasShown { MacLocalTmux.noteHidden(name) }
    }

    func claimStartupCommand(for paneID: UUID) -> TerminalStartupCommandTicket? {
        guard !isClosed, state.root?.pane(id: paneID) != nil else { return nil }
        if let ticket = retainedStartupTicketsByPaneID.removeValue(forKey: paneID) { return ticket }
        guard !isClosed,
              state.root?.pane(id: paneID) != nil,
              let ticketID = startupTicketIDsByPaneID.removeValue(forKey: paneID) else {
            return nil
        }
        let ticket = startupCommandBroker.claim(ticketID)
        explicitStartupCommandsByPaneID[paneID] = ticket?.command
        return ticket
    }

    private func discardStartupCommand(for paneID: UUID) {
        retainedStartupTicketsByPaneID.removeValue(forKey: paneID)
        explicitStartupCommandsByPaneID.removeValue(forKey: paneID)
        pendingCredentialErrorsByPaneID.removeValue(forKey: paneID)
        guard let ticketID = startupTicketIDsByPaneID.removeValue(forKey: paneID) else { return }
        startupCommandBroker.discard(ticketID)
    }

    private func persist() {
        do {
            _ = try state.validated(for: state.id)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            guard data.count <= Self.maximumEncodedBytes else {
                throw MacWorkspaceStateError.encodedStateTooLarge
            }
            defaults.set(data, forKey: Self.defaultsKey(for: state.id))
        } catch {
            Logger.settings.error(
                "Refusing to persist invalid workspace state: \(error.localizedDescription, privacy: .public)"
            )
            assertionFailure("Refusing to persist invalid workspace state: \(error)")
        }
    }

    private struct LoadResult {
        let state: MacWorkspaceRestorationState
        let hadRestorationData: Bool
    }

    private static func load(
        workspaceID: UUID,
        startsEmptyIfUnrestored: Bool,
        initialPaneIntent: MacWorkspacePaneIntent?,
        defaults: UserDefaults
    ) -> LoadResult {
        let key = defaultsKey(for: workspaceID)
        guard let data = defaults.data(forKey: key) else {
            let state: MacWorkspaceRestorationState
            if startsEmptyIfUnrestored {
                state = .empty(id: workspaceID)
            } else {
                state = MacWorkspaceRestorationState(
                    id: workspaceID,
                    initialIntent: initialPaneIntent ?? .local
                )
            }
            return LoadResult(state: state, hadRestorationData: false)
        }
        guard data.count <= maximumEncodedBytes else {
            return LoadResult(
                state: .empty(id: workspaceID),
                hadRestorationData: true
            )
        }
        do {
            let state = try JSONDecoder()
                .decode(MacWorkspaceRestorationState.self, from: data)
                .validated(for: workspaceID)
            return LoadResult(state: state, hadRestorationData: true)
        } catch {
            // Keep malformed or future-version data untouched for diagnosis,
            // but never execute a launch request that failed validation.
            return LoadResult(
                state: .empty(id: workspaceID),
                hadRestorationData: true
            )
        }
    }

    private static func defaultsKey(for workspaceID: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).\(workspaceID.uuidString.lowercased())"
    }
}

struct MacWorkspaceWindowIdentity: Equatable {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String?) {
        self.title = MacWorkspaceChromeText.sanitize(
            title,
            maximumLength: 160
        ) ?? "Terminal"
        self.subtitle = subtitle.flatMap {
            MacWorkspaceChromeText.sanitize($0, maximumLength: 240)
        }
    }
}

@MainActor
final class MacWorkspaceTransferBroker {
    static let shared = MacWorkspaceTransferBroker()
    static let defaultCapacity = 16
    static let defaultExpiration: Duration = .seconds(30)

    private struct Entry {
        let controller: MacWorkspaceController
        let expirationTask: Task<Void, Never>
        let commit: @MainActor (UUID) -> Bool
        let invalidate: @MainActor (UUID) -> Void
    }

    private let capacity: Int
    private let expiration: Duration
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []

    init(
        capacity: Int = defaultCapacity,
        expiration: Duration = defaultExpiration
    ) {
        self.capacity = max(1, capacity)
        self.expiration = expiration
    }

    var pendingCount: Int { entries.count }

    func issue(
        controller: MacWorkspaceController,
        commit: @escaping @MainActor (UUID) -> Bool,
        invalidate: @escaping @MainActor (UUID) -> Void
    ) -> UUID {
        while entries.count >= capacity, let oldest = order.first {
            self.invalidate(oldest)
        }
        let id = UUID()
        let expirationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.expiration)
            guard !Task.isCancelled else { return }
            self.invalidate(id)
        }
        entries[id] = Entry(
            controller: controller,
            expirationTask: expirationTask,
            commit: commit,
            invalidate: invalidate
        )
        order.append(id)
        return id
    }

    func claim(_ id: UUID) -> MacWorkspaceController? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        entry.expirationTask.cancel()
        guard !entry.controller.isClosed, entry.commit(id) else {
            entry.invalidate(id)
            return nil
        }
        return entry.controller
    }

    func discard(_ id: UUID) {
        invalidate(id)
    }

    private func invalidate(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        entry.expirationTask.cancel()
        entry.invalidate(id)
    }
}

@MainActor
@Observable
final class MacWorkspaceWindowController {
    private static let maximumEncodedBytes = 64 * 1024

    let windowID: UUID
    private(set) var tabs: [MacWorkspaceController]
    private(set) var selectedTabID: UUID

    private let defaults: UserDefaults
    private let startupCommandBroker: MacStartupCommandBroker
    private let liveSessionBroker: MacLiveSessionBroker
    private let transferBroker: MacWorkspaceTransferBroker
    private var pendingTransferTicketsByWorkspaceID: [UUID: UUID] = [:]

    init(
        request: MacWorkspaceLaunchRequest,
        startupCommandBroker: MacStartupCommandBroker = .shared,
        liveSessionBroker: MacLiveSessionBroker = .shared,
        transferBroker: MacWorkspaceTransferBroker = .shared,
        defaults: UserDefaults = .standard
    ) {
        windowID = request.windowID
        self.defaults = defaults
        self.startupCommandBroker = startupCommandBroker
        self.liveSessionBroker = liveSessionBroker
        self.transferBroker = transferBroker

        let resolvedTabs: [MacWorkspaceController]
        let resolvedSelectedTabID: UUID
        if let ticketID = request.transferredTabTicketID {
            if let transferred = transferBroker.claim(ticketID) {
                resolvedTabs = [transferred]
                resolvedSelectedTabID = transferred.workspaceID
            } else {
                let fallback = MacWorkspaceController(
                    request: MacWorkspaceTabRequest(
                        workspaceID: UUID(),
                        startsEmpty: true
                    ),
                    startupCommandBroker: startupCommandBroker,
                    liveSessionBroker: liveSessionBroker,
                    defaults: defaults
                )
                resolvedTabs = [fallback]
                resolvedSelectedTabID = fallback.workspaceID
            }
        } else if let restored = Self.load(windowID: request.windowID, defaults: defaults) {
            resolvedTabs = restored.tabs.map {
                MacWorkspaceController(
                    request: $0.request,
                    startupCommandBroker: startupCommandBroker,
                    liveSessionBroker: liveSessionBroker,
                    defaults: defaults
                )
            }
            resolvedSelectedTabID = restored.selectedTabID
        } else if defaults.object(
            forKey: Self.defaultsKey(for: request.windowID)
        ) != nil {
            let fallback = MacWorkspaceController(
                request: MacWorkspaceTabRequest(
                    workspaceID: UUID(),
                    startsEmpty: true
                ),
                startupCommandBroker: startupCommandBroker,
                liveSessionBroker: liveSessionBroker,
                defaults: defaults
            )
            resolvedTabs = [fallback]
            resolvedSelectedTabID = fallback.workspaceID
        } else {
            resolvedTabs = request.tabs.map {
                MacWorkspaceController(
                    request: $0,
                    startupCommandBroker: startupCommandBroker,
                    liveSessionBroker: liveSessionBroker,
                    defaults: defaults
                )
            }
            resolvedSelectedTabID = request.initialSelectedTabID.flatMap { requested in
                resolvedTabs.first(where: { $0.workspaceID == requested })?.workspaceID
            } ?? resolvedTabs[0].workspaceID
        }
        tabs = resolvedTabs
        selectedTabID = resolvedSelectedTabID
        persist()
        // Made once per window: its view asks the registry first (`windowController(for:)`).
        MacWorkspacePreviewRegistry.shared.noteBuilt(self)
    }

    /// Whether this window's tabs are saved, so a launch request with its id restores them.
    static func hasSavedState(windowID: UUID, defaults: UserDefaults = .standard) -> Bool {
        load(windowID: windowID, defaults: defaults) != nil
    }

    var selectedTab: MacWorkspaceController {
        tabs.first(where: { $0.workspaceID == selectedTabID }) ?? tabs[0]
    }

    func capturePreset(
        name: String,
        servers: [ServerConfiguration],
        defaultLocalShell: String? = nil,
        defaultLocalDirectory: String? = nil,
        sourcePresets: [LayoutPreset] = []
    ) throws -> LayoutPreset {
        var intents: [LayoutPreset.SessionIntent] = []
        var savedTabs: [LayoutPreset.WorkspaceLayout.Tab] = []
        var selectedIndex = 0
        for tab in tabs {
            guard let root = tab.state.root else { continue }
            var indices: [UUID: Int] = [:]
            func convert(_ node: MacWorkspaceNode) throws -> LayoutPreset.WorkspaceLayout.Node {
                switch node {
                case .pane(let pane):
                    guard intents.count < LayoutPreset.maximumSessionCount else { throw MacWorkspaceStateError.tooManyPanes }
                    let index = intents.count
                    indices[pane.id] = index
                    let intent = pane.intent
                    let sourcePreset = sourcePresets.first { $0.id == tab.workgroupID }
                    let sourceIntent = intent.sourceSessionIndex.flatMap { sourceIndex in
                        sourcePreset?.sessionIntents.indices.contains(sourceIndex) == true
                            ? sourcePreset?.sessionIntents[sourceIndex] : nil
                    }
                    let sourceCommand = sourceIntent.flatMap { source in
                        source.kind.rawValue == intent.kind.rawValue && source.serverID == intent.serverID
                            ? source.startupCommand : nil
                    }
                    if intent.kind == .ssh,
                       !servers.contains(where: { $0.id == intent.serverID }) {
                        throw MacWorkspaceStateError.invalidPaneIntent
                    }
                    intents.append(.init(kind: intent.kind == .local ? .local : .ssh,
                                         serverID: intent.serverID,
                                         label: intent.label,
                                         startupCommand: tab.explicitStartupCommandsByPaneID[pane.id] ?? sourceCommand,
                                         localShell: intent.kind == .local
                                            ? (tab.localRuntimesByPaneID[pane.id]?.launchedShell ?? intent.localShell ?? defaultLocalShell) : nil,
                                         localDirectory: intent.kind == .local
                                            ? (tab.localDirectory(for: pane.id) ?? intent.localDirectory ?? defaultLocalDirectory)
                                            : nil))
                    return .session(index)
                case .split(let split):
                    return .split(axis: split.axis == .horizontal ? .horizontal : .vertical,
                                  fraction: split.fraction, first: try convert(split.first), second: try convert(split.second))
                }
            }
            let savedRoot = try convert(root)
            if tab.workspaceID == selectedTabID { selectedIndex = savedTabs.count }
            savedTabs.append(.init(label: tab.tabLabel, root: savedRoot,
                                   focusedSessionIndex: tab.focusedPaneID.flatMap { indices[$0] } ?? indices[root.paneIDs[0]]!))
        }
        let preset = LayoutPreset(name: name, colorTag: selectedTab.workgroupColor ?? .blue,
                                  sessionIntents: intents,
                                  workspaceLayout: .init(tabs: savedTabs, selectedTabIndex: selectedIndex))
        guard preset.isValidForPersistence else { throw MacWorkspaceStateError.invalidPaneIntent }
        return preset
    }

    var isEmpty: Bool {
        tabs.allSatisfy(\.isEmpty)
    }

    /// Names a tab, or with a blank name returns it to its automatic one, and saves the window so
    /// the name survives a relaunch.
    func renameTab(_ workspaceID: UUID, to name: String?) {
        guard let tab = tabs.first(where: { $0.workspaceID == workspaceID }) else { return }
        tab.rename(to: name)
        persist()
    }

    /// What closing this window should ask, or nil when nothing would stop (D44).
    var closeConfirmationMessage: String? {
        guard tabs.contains(where: \.closeStopsWork) else { return nil }
        return tabs.contains(where: \.hasTerminalsInTmux)
            ? "Terminals in this window that aren't kept in tmux will be disconnected. Those in tmux keep running, and Active lists them."
            : "Running terminal sessions in this window will be disconnected."
    }

    /// What quitting the app should ask about this window, or nil when nothing would stop. Local
    /// terminals in tmux keep running through a quit and reattach on the next launch (D47).
    var quitConfirmationMessage: String? {
        guard tabs.contains(where: \.closeStopsWork) else { return nil }
        switch (tabs.contains(where: \.hasTerminalsInTmux), tabs.contains(where: \.hasLocalTerminalsInTmux)) {
        case (true, true):
            return "Terminals that aren't kept in tmux will be disconnected. Those in tmux keep running: local ones reopen with the app, and Active lists the rest."
        case (true, false):
            return "Terminals that aren't kept in tmux will be disconnected. Those in tmux keep running, and Active lists them."
        case (false, true):
            return "Terminals that aren't kept in tmux will be stopped. Local terminals in tmux keep running and reopen with the app."
        case (false, false):
            return "Running terminal sessions will be disconnected."
        }
    }
    var canAddTab: Bool {
        tabs.count < MacWorkspaceWindowRestorationState.maximumTabCount
    }
    var canTransferSelectedTab: Bool {
        tabs.count > 1
            && pendingTransferTicketsByWorkspaceID[selectedTabID] == nil
    }

    func select(_ workspaceID: UUID) {
        guard tabs.contains(where: { $0.workspaceID == workspaceID }) else { return }
        selectedTabID = workspaceID
        persist()
    }

    /// A new tab, by default with a shell on this Mac, in tmux when that is on, rather than the
    /// empty chooser "+" and ⌘T used to show (2026-10-08). The caller starts its panes
    /// (`startLocalPanes`), so they do not wait for the tab's view.
    @discardableResult
    func addTab(_ request: MacWorkspaceTabRequest = MacWorkspaceTabRequest(initialPaneIntent: .local))
        -> MacWorkspaceController?
    {
        guard canAddTab else { return nil }
        let controller = MacWorkspaceController(
            request: request,
            startupCommandBroker: startupCommandBroker,
            liveSessionBroker: liveSessionBroker,
            defaults: defaults
        )
        tabs.append(controller)
        selectedTabID = controller.workspaceID
        persist()
        return controller
    }

    @discardableResult
    func removeTab(
        _ workspaceID: UUID,
        sessionManager: SessionManager,
        closeSessions: Bool = true
    ) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.workspaceID == workspaceID }) else {
            return false
        }
        if tabs.count == 1 {
            cancelPendingTransfer(for: workspaceID)
            if closeSessions {
                tabs[0].closeAllSessions(sessionManager: sessionManager)
            }
            defaults.removeObject(forKey: Self.defaultsKey(for: windowID))
            return true
        }
        cancelPendingTransfer(for: workspaceID)
        let controller = tabs.remove(at: index)
        if closeSessions {
            controller.closeAllSessions(sessionManager: sessionManager)
        }
        guard !tabs.isEmpty else {
            defaults.removeObject(forKey: Self.defaultsKey(for: windowID))
            return true
        }
        if selectedTabID == workspaceID {
            selectedTabID = tabs[min(index, tabs.count - 1)].workspaceID
        }
        persist()
        return false
    }

    // MARK: Dragging tabs between windows (2026-10-08)

    /// Set when this window's last tab was dragged into another: its view closes the window. A
    /// placeholder tab stands in until then, so nothing ever reads an empty list of tabs, and
    /// closing this window cannot touch the terminals that moved.
    private(set) var closesAfterLastTabLeft = false

    /// A tab dropped on this window's tab list at `index`: reordered when it is from this window,
    /// moved here, running, when it is from another. False when it cannot be taken.
    ///
    /// The source is the controller the dragging window shows (`MacWorkspacePreviewRegistry`),
    /// never another made for the same id: taking a copy's tab left the real one in place, still
    /// attached, and with tmux the two windows mirrored one session (2026-10-08).
    @discardableResult
    func acceptDroppedTab(_ drag: MacWorkspaceTabDrag, at index: Int) -> Bool {
        guard !closesAfterLastTabLeft else { return false }
        if drag.windowID == windowID {
            return moveTab(drag.workspaceID, to: index)
        }
        guard canAddTab, let source = MacWorkspacePreviewRegistry.shared.shownController(windowID: drag.windowID),
              let controller = source.detachTabForMove(drag.workspaceID) else { return false }
        adoptTab(controller, at: index)
        return true
    }

    /// Reorders: `index` is where the tab lands in the list as it was before the move.
    @discardableResult
    func moveTab(_ workspaceID: UUID, to index: Int) -> Bool {
        guard let from = tabs.firstIndex(where: { $0.workspaceID == workspaceID }) else { return false }
        let tab = tabs.remove(at: from)
        let target = min(max(index, 0), tabs.count + 1)
        tabs.insert(tab, at: min(target > from ? target - 1 : target, tabs.count))
        persist()
        return true
    }

    /// Lets a tab go to another window, its terminals untouched. The last tab leaves a
    /// placeholder and closes the window.
    func detachTabForMove(_ workspaceID: UUID) -> MacWorkspaceController? {
        guard !closesAfterLastTabLeft,
              let index = tabs.firstIndex(where: { $0.workspaceID == workspaceID }) else { return nil }
        cancelPendingTransfer(for: workspaceID)
        let controller = tabs.remove(at: index)
        if tabs.isEmpty {
            let placeholder = MacWorkspaceController(
                request: MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: true),
                startupCommandBroker: startupCommandBroker,
                liveSessionBroker: liveSessionBroker,
                defaults: defaults
            )
            tabs = [placeholder]
            selectedTabID = placeholder.workspaceID
            closesAfterLastTabLeft = true
            defaults.removeObject(forKey: Self.defaultsKey(for: windowID))
            return controller
        }
        if selectedTabID == workspaceID {
            selectedTabID = tabs[min(index, tabs.count - 1)].workspaceID
        }
        persist()
        return controller
    }

    /// Takes in a tab another window let go of, at `index`, and shows it.
    func adoptTab(_ controller: MacWorkspaceController, at index: Int) {
        tabs.insert(controller, at: min(max(index, 0), tabs.count))
        selectedTabID = controller.workspaceID
        persist()
    }

    func transferSelectedTab() -> MacWorkspaceLaunchRequest? {
        guard canTransferSelectedTab else { return nil }
        let controller = selectedTab
        let ticketID = transferBroker.issue(
            controller: controller,
            commit: { [weak self] ticketID in
                self?.commitTransfer(
                    controller.workspaceID,
                    ticketID: ticketID
                ) ?? false
            },
            invalidate: { [weak self] ticketID in
                self?.invalidateTransfer(
                    controller.workspaceID,
                    ticketID: ticketID
                )
            }
        )
        pendingTransferTicketsByWorkspaceID[controller.workspaceID] = ticketID
        return MacWorkspaceLaunchRequest(
            windowID: UUID(),
            tabs: [controller.restorationDescriptor.request],
            transferredTabTicketID: ticketID
        )
    }

    func closeAllSessions(sessionManager: SessionManager) {
        let pendingTickets = Array(pendingTransferTicketsByWorkspaceID.values)
        for ticketID in pendingTickets {
            transferBroker.discard(ticketID)
        }
        pendingTransferTicketsByWorkspaceID.removeAll()
        for tab in tabs {
            tab.closeAllSessions(sessionManager: sessionManager)
        }
    }

    private func commitTransfer(_ workspaceID: UUID, ticketID: UUID) -> Bool {
        guard pendingTransferTicketsByWorkspaceID[workspaceID] == ticketID else {
            return false
        }
        guard let index = tabs.firstIndex(where: { $0.workspaceID == workspaceID }),
              tabs.count > 1 else {
            pendingTransferTicketsByWorkspaceID.removeValue(forKey: workspaceID)
            return false
        }
        pendingTransferTicketsByWorkspaceID.removeValue(forKey: workspaceID)
        tabs.remove(at: index)
        if selectedTabID == workspaceID {
            selectedTabID = tabs[min(index, tabs.count - 1)].workspaceID
        }
        persist()
        return true
    }

    private func invalidateTransfer(_ workspaceID: UUID, ticketID: UUID) {
        guard pendingTransferTicketsByWorkspaceID[workspaceID] == ticketID else {
            return
        }
        pendingTransferTicketsByWorkspaceID.removeValue(forKey: workspaceID)
    }

    private func cancelPendingTransfer(for workspaceID: UUID) {
        guard let ticketID = pendingTransferTicketsByWorkspaceID[workspaceID] else {
            return
        }
        transferBroker.discard(ticketID)
    }

    private func persist() {
        let state = MacWorkspaceWindowRestorationState(
            tabs: tabs.map(\.restorationDescriptor),
            selectedTabID: selectedTabID
        )
        guard state.validated() != nil,
              let data = try? JSONEncoder().encode(state),
              data.count <= Self.maximumEncodedBytes else {
            assertionFailure("Refusing to persist invalid macOS window tabs")
            return
        }
        defaults.set(data, forKey: Self.defaultsKey(for: windowID))
    }

    private static func load(
        windowID: UUID,
        defaults: UserDefaults
    ) -> MacWorkspaceWindowRestorationState? {
        guard let data = defaults.data(forKey: defaultsKey(for: windowID)),
              data.count <= maximumEncodedBytes,
              let state = try? JSONDecoder().decode(
                MacWorkspaceWindowRestorationState.self,
                from: data
              ) else {
            return nil
        }
        return state.validated()
    }

    private static func defaultsKey(for windowID: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(windowID.uuidString.lowercased())"
    }
}
#endif

#endif
