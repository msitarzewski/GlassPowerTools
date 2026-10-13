#if os(macOS)
#if os(macOS)
import Foundation
import Observation
import GlassLayers
import GlassTerminalEmulator
import os

extension Logger {
    /// Saving and restoring terminal windows and tabs (W7b).
    nonisolated static let workspaceRestoration = Logger(subsystem: "sh.glas", category: "workspace")
}

extension Notification.Name {
    /// A terminal tab's or window's record was written, in the defaults the notification carries
    /// as its object. The reopen list follows it (`MacWindowsToReopen`, W12).
    static let macWorkspaceRecordSaved = Notification.Name("GlassTerminal.macWorkspaceRecordSaved")
}

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
    private(set) var findRequest = TerminalFindRequest.none
    private(set) var isClosed = false
    /// Why this tab's saved layout could not be read, or nil. The record is then left exactly as
    /// it was, never written over, until the tab is closed, which discards it on purpose (W7b).
    private(set) var restorationFailure: String?
    /// A layout made here rather than read from the record: saved when a window shows the tab or
    /// changes, never by init, so a controller made and thrown away writes nothing (W7b).
    @ObservationIgnored private var hasUnsavedState = false
    /// Panes its workgroup has just opened, which write a tmux name they claim back to it, once
    /// (W4b). Not panes restored later: their workgroup may have changed since.
    @ObservationIgnored private var panesOpenedFromWorkgroup: Set<UUID> = []
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
    /// The repository each pane's folder is in, with its branch (W11): the line under the tab's
    /// name, and its name when no program titled it.
    private(set) var repositoryByPaneID: [UUID: TerminalRepository] = [:]
    /// The least time between two lookups of a pane whose folder has not changed: a checkout
    /// changes the branch. A host is asked over the network, so less often. Tests set zero.
    @ObservationIgnored var localRepositoryInterval: Duration = .seconds(5)
    @ObservationIgnored var remoteRepositoryInterval: Duration = .seconds(15)
    @ObservationIgnored var repositoryCache = TerminalRepositoryCache.shared
    /// Where a local walk stops; tests give their own.
    @ObservationIgnored var repositoryHome: String? = NSHomeDirectory()
    @ObservationIgnored private var repositoryLookups: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var repositoryLookedUpAt: [UUID: ContinuousClock.Instant] = [:]
    /// Panes whose folder changed during their lookup: looked up again when it ends.
    @ObservationIgnored private var repositoryFolderChanged: Set<UUID> = []
    /// What each pane's tmux session was last told, so it is told only of a change.
    @ObservationIgnored private var sharedRepositoryByPaneID: [UUID: TerminalRepository?] = [:]
    @ObservationIgnored private var repositoryWrite: Task<Void, Never>?
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
        let loaded = Self.load(
            workspaceID: workspaceID,
            startsEmptyIfUnrestored: startsEmptyIfUnrestored,
            initialPaneIntent: nil,
            defaults: defaults
        )
        self.state = loaded.state
        self.restorationFailure = loaded.failure
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
        self.restorationFailure = loaded.failure
        var acceptedInitialLayout = false
        if !loaded.hadRestorationData, let initial = request.initialState,
           let validated = try? initial.validated(for: request.workspaceID) {
            self.state = validated
            acceptedInitialLayout = true
            startupTicketIDsByPaneID = request.paneStartupTicketIDs ?? [:]
            if request.workgroupID != nil {
                panesOpenedFromWorkgroup = Set(validated.root?.panes.filter { $0.intent.sourceSessionIndex != nil }.map(\.id) ?? [])
            }
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
                    watch(ticket.session, for: paneID)
                    // Connect, or Active's Open: the pane keeps the session's tmux name, now or
                    // once it claims one, so a relaunch reattaches (W4b). Saved with the window.
                    if let name = ticket.session.tmuxSessionName { setSSHTmuxSession(name, for: paneID) }
                    keepClaimedSSHTmuxSession(of: ticket.session, paneID: paneID, settingsManager: nil)
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
        // Unselected tabs may never receive a focus or layout event, so their fresh trees are
        // saved with their window (`saveIfUnsaved`), not here: a controller SwiftUI makes and
        // throws away wrote records — a new empty tab, a tmux name no window used (W7b).
        // Existing malformed restoration data is deliberately left untouched.
        hasUnsavedState = (!loaded.hadRestorationData && (request.initialState == nil || acceptedInitialLayout))
            || (loaded.hadRestorationData && assignedTmuxSessions)
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

    /// A local pane's tmux history and screen, for Select All (2026-10-11), read off the main thread
    /// after any scroll on its way.
    func localTmuxHistory(_ paneID: UUID) async -> String? {
        let server = MacLocalTmux.server
        guard let session = localTmuxSession(for: paneID), let tmux = server.executablePath() else { return nil }
        let captured: String? = await withCheckedContinuation { continuation in
            MacLocalTmux.scrollQueue.async { continuation.resume(returning: server.history(session, tmux)) }
        }
        return captured.map(TerminalTmux.historyText)
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
    /// Not in a tab whose saved layout couldn't be read: a new pane would be saved over it.
    var canAddPane: Bool {
        restorationFailure == nil
            && (state.root?.paneIDs.count ?? 0) < MacWorkspaceRestorationState.maximumPaneCount
    }

    func windowIdentity(
        servers: [ServerConfiguration],
        localUsername: String = NSUserName(),
        home: String? = NSHomeDirectory()
    ) -> MacWorkspaceWindowIdentity {
        guard let focusedPane else {
            if restorationFailure != nil {
                return MacWorkspaceWindowIdentity(title: tabLabel ?? "Tab Not Restored",
                                                  subtitle: "Its saved layout couldn't be read")
            }
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
            let repository = repositoryByPaneID[focusedPane.id]
            // Named, else configured, else what the terminal says, else the workgroup, else the
            // tmux session as Active names it, else the shell.
            let shell = localRuntimesByPaneID[focusedPane.id]?.launchedShell.map { ($0 as NSString).lastPathComponent }
            let title = tabLabel ?? focusedPane.intent.label
                ?? MacWorkspaceTabNaming.automaticTitle(context, repository: repository, home: home) ?? workgroupName
                ?? focusedPane.intent.localTmuxSession.map(MacWorkspaceTabNaming.tmuxDisplayName)
                ?? (shell == "tmux" ? nil : shell) ?? "Local"
            // Where it is — `repo · branch` in a repository (W11), else the folder — unless the
            // title already says exactly that: "~" over "~" said it twice and nothing else
            // (2026-10-08). Then the machine, as before.
            let location = TerminalSessionNaming.location(directory: context?.directory, home: home, repository: repository)
            var subtitle = location.flatMap { $0 == title ? nil : $0 } ?? "\(localUsername)@localhost"
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
            // A remote directory is named by its last part; in tmux the host says its home, which
            // names nothing, as Active and every other device have it (W19). In a repository the
            // line says it, then the machine (W11).
            let context = paneContextByPaneID[focusedPane.id]
            let repository = repositoryByPaneID[focusedPane.id]
            let connection = "\(server.username)@\(server.host):\(server.port)"
            return MacWorkspaceWindowIdentity(
                title: tabLabel ?? focusedPane.intent.label
                    ?? MacWorkspaceTabNaming.automaticTitle(context, repository: repository, home: context?.home)
                    ?? server.name,
                subtitle: Self.connectionSubtitle(
                    TerminalSessionNaming.location(directory: nil, home: nil, repository: repository)
                        .map { "\($0) · \(connection)" } ?? connection,
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
        // A program printing without pause (an agent's spinner) still has its branch checked
        // now and then: it may be the one checking out (W11).
        if repositorySweptAt.map({ ContinuousClock.now - $0 >= localRepositoryInterval }) ?? true {
            refreshRepositories()
        }
        quietTask?.cancel()
        quietTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.activityLinger)
            guard !Task.isCancelled, let self else { return }
            isProducingOutput = false
            // An SSH pane's terminal reads its own session as its output settles (W19).
            refreshLocalTmuxContext()
            refreshRepositories()
        }
    }

    /// D47: tmux keeps a shell's title and directory from the terminal outside it, so a tab in
    /// tmux asks tmux what its panes show once output settles, and what its sessions are called
    /// (W6, W19). One read answers every local tab (`MacLocalTmuxContextReads`), through
    /// `MacLocalTmux.server`, which tests replace.
    func refreshLocalTmuxContext() {
        guard !isClosed, localRuntimesByPaneID.keys.contains(where: { localTmuxSession(for: $0) != nil }) else { return }
        MacLocalTmux.contextReads.ask(self)
    }

    /// What this Mac's tmux said its sessions show, by session: each local pane in tmux takes its
    /// own. A name given here after the read was asked (`generation`) is not replaced by the name
    /// the read found.
    func applyLocalTmuxContexts(_ contexts: [String: MacWorkspacePaneContext], askedAt generation: UInt64) {
        guard !isClosed else { return }
        for paneID in state.root?.paneIDs ?? [] where localRuntimesByPaneID[paneID] != nil {
            guard let session = localTmuxSession(for: paneID), let context = contexts[session] else { continue }
            setPaneContext(context, for: paneID)
            if generation == givenNameGeneration { followSessionName(context.givenName, for: paneID) }
        }
    }

    private func observeOutput(of model: SwiftTermHostModel) {
        model.onOutputActivity = { [weak self] in self?.noteOutput() }
    }

    /// An SSH pane's terminal reads what its tmux session says about itself — the name a tab on
    /// any device gave it, the title its program set, its folder and repository — once attached
    /// and when its output settles, at most once an interval, as terminals on every other device
    /// do (W19). Its own title and folder reports stop at tmux, so they are the session's.
    private func watch(_ terminal: TerminalSession, for paneID: UUID) {
        terminal.readsTmuxPane = true
        terminal.tmuxPaneObserved = { [weak self, weak terminal] pane, firstSinceAttach in
            guard let self, let terminal else { return }
            terminalRead(pane, firstSinceAttach: firstSinceAttach, of: terminal, for: paneID)
        }
        // Already attached — Connect hands the tab a terminal that is — it is read now.
        terminal.readTmuxPaneIfDue()
    }

    private func terminalRead(_ pane: TerminalTmux.PaneState, firstSinceAttach: Bool,
                              of terminal: TerminalSession, for paneID: UUID) {
        guard !isClosed, state.root?.pane(id: paneID) != nil,
              sessionsByPaneID[paneID] == nil || sessionsByPaneID[paneID] === terminal else { return }
        setPaneContext(MacWorkspacePaneContext(title: pane.title, directory: pane.directory, givenName: pane.givenName,
                                               home: pane.home), for: paneID)
        // The read says the repository too: no lookup of its own (W11's took two commands).
        repositoryLookedUpAt[paneID] = .now
        setRepository(pane.repository.map { .repository($0) } ?? .none, for: paneID)
        // Attached again, the session may be one made again under the same name: met anew.
        if firstSinceAttach { sessionNameByPaneID[paneID] = nil }
        // The terminal's own name for it: what was read, unless named here since the read began.
        followSessionName(terminal.givenName, for: paneID)
    }

    /// An SSH pane whose terminal is in tmux and reads its session.
    private func readsItsTmuxSession(_ paneID: UUID) -> Bool {
        guard let terminal = sessionsByPaneID[paneID] else { return false }
        return terminal.readsTmuxPane && terminal.survivesClose
    }

    /// Names the tab; blank goes back to the automatic name. The window saves it with its tabs.
    /// The name also goes with each tmux session the tab shows, as the session's `@glass-name`
    /// (W6): Active on every device, and a tab attaching to the session later, call it the same.
    /// Going back to the automatic name takes it away there too.
    func rename(to name: String?) {
        guard !isClosed else { return }
        tabLabel = MacWorkspaceChromeText.sanitize(name, maximumLength: MacWorkspaceTabRequest.maximumDisplayTextLength)
        // Named here: a session's earlier name, read before this, is not taken over this one.
        givenNameGeneration &+= 1
        for paneID in state.root?.paneIDs ?? [] { tellSessionTheName(of: paneID) }
    }

    /// Counts namings here, so an answer asked for before one is not taken after it.
    @ObservationIgnored private(set) var givenNameGeneration: UInt64 = 0
    /// What each pane's tmux session is called, as last read there or told from here (W19); no
    /// entry until the tab and the session first meet. A read that differs from it is a name
    /// given, or taken away, on another device.
    @ObservationIgnored private var sessionNameByPaneID: [UUID: String?] = [:]
    /// Panes in tmux whose session could not be told the tab's name when it was given — an SSH
    /// terminal not connected — and is told at its next read, rather than giving its old name back.
    @ObservationIgnored private var sessionNameOwedPaneIDs: Set<UUID> = []
    /// Told when the tab took a name from its session, so the window saves it: a name taken
    /// away elsewhere, and not saved, came back from the tab's record at the next launch.
    @ObservationIgnored var nameTakenFromSession: (@MainActor () -> Void)?

    /// Gives the pane's tmux session the tab's name, or takes it away. An SSH terminal not
    /// connected owes it until it next reads.
    private func tellSessionTheName(of paneID: UUID) {
        guard let pane = state.root?.pane(id: paneID) else { return }
        if let session = pane.intent.localTmuxSession {
            MacLocalTmux.shareGivenName(tabLabel, session: session)
        } else if let terminal = sessionsByPaneID[paneID] {
            // Its own rename keeps it in order with its reads (W11): a read begun before it is not
            // taken over it, and the next waits for it to reach the host.
            terminal.rename(to: tabLabel)
            guard terminal.survivesClose, terminal.state == .connected else {
                if terminal.usesTmux || pane.intent.sshTmuxSession != nil { owe(paneID) }
                return
            }
        } else {
            if pane.intent.sshTmuxSession != nil { owe(paneID) }
            return
        }
        sessionNameOwedPaneIDs.remove(paneID)
        sessionNameByPaneID[paneID] = .some(tabLabel)
    }

    private func owe(_ paneID: UUID) {
        sessionNameOwedPaneIDs.insert(paneID)
        sessionNameByPaneID[paneID] = nil
    }

    /// A tab follows what its tmux sessions are called (W6, W19). Meeting a session — attaching,
    /// or attaching again — it takes the session's name when it has one, and otherwise gives the
    /// session its own, which a tab named before names were kept on sessions never did. From then
    /// on, a name given or taken away on another device shows here, and the window saves it. A
    /// name given here wins over a read begun before it (`givenNameGeneration`), and one the
    /// session could not be told is told at its next read.
    private func followSessionName(_ read: String?, for paneID: UUID) {
        guard !isClosed else { return }
        if sessionNameOwedPaneIDs.contains(paneID) { return tellSessionTheName(of: paneID) }
        let read = MacWorkspaceChromeText.sanitize(read, maximumLength: MacWorkspaceTabRequest.maximumDisplayTextLength)
        let known = sessionNameByPaneID[paneID]
        if known == nil, read == nil, tabLabel != nil { return tellSessionTheName(of: paneID) }
        sessionNameByPaneID[paneID] = .some(read)
        if let known, known == read { return }
        guard read != tabLabel else { return }
        tabLabel = read
        nameTakenFromSession?()
    }

    /// The title a pane's shell or program set, and its directory, as they change. A pane in
    /// tmux sees only tmux's own, so its context comes from tmux instead: this Mac's
    /// (`refreshLocalTmuxContext`), or for an SSH pane its host's (`watch`, W19).
    func updatePaneContext(title: String?, directory: String?, for paneID: UUID) {
        guard localTmuxSession(for: paneID) == nil, !readsItsTmuxSession(paneID) else { return }
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
            for (paneID, context) in pending where !readsItsTmuxSession(paneID) { setPaneContext(context, for: paneID) }
            schedulePaneContextFlush()
        }
    }

    private func setPaneContext(_ context: MacWorkspacePaneContext, for paneID: UUID) {
        guard !isClosed, state.root?.pane(id: paneID) != nil else { return }
        let folderChanged = paneContextByPaneID[paneID]?.directory != context.directory
        if paneContextByPaneID[paneID] != context { paneContextByPaneID[paneID] = context }
        if folderChanged { lookUpRepository(for: paneID, folderChanged: true) }
    }

    // MARK: Repository and branch (W11, 2026-10-09)

    /// Looks up again the repository of every pane whose last lookup is old enough.
    func refreshRepositories() {
        repositorySweptAt = .now
        for paneID in state.root?.paneIDs ?? [] { lookUpRepository(for: paneID, folderChanged: false) }
    }

    @ObservationIgnored private var repositorySweptAt: ContinuousClock.Instant?

    /// Which repository a pane's folder is in, and its branch: at once when the folder changed,
    /// otherwise at most once an interval. A local folder's files are read here; a host is asked,
    /// for the folder tmux says its shell is in, or the one the shell reported (OSC 7).
    private func lookUpRepository(for paneID: UUID, folderChanged: Bool) {
        guard !isClosed, let pane = state.root?.pane(id: paneID) else { return }
        guard repositoryLookups[paneID] == nil else {
            if folderChanged { repositoryFolderChanged.insert(paneID) }
            return
        }
        let interval = pane.intent.kind == .local ? localRepositoryInterval : remoteRepositoryInterval
        if !folderChanged, let last = repositoryLookedUpAt[paneID], ContinuousClock.now - last < interval { return }
        let cache = repositoryCache
        let reported = paneContextByPaneID[paneID]?.directory
        let lookup: @MainActor () async -> TerminalRepositoryAnswer
        switch pane.intent.kind {
        case .local:
            guard let folder = TerminalRepository.path(fromReported: reported) else { return }
            let home = repositoryHome
            lookup = {
                await cache.answer(for: .init(host: nil, folder: folder), maximumAge: interval) {
                    await TerminalRepository.readOffMain(folder: folder, home: home)
                }
            }
        case .ssh:
            guard let terminal = sessionsByPaneID[paneID], terminal.state == .connected else { return }
            if readsItsTmuxSession(paneID) {
                // Its session's read says the folder and the repository together (W19): a new
                // folder came with its repository, and otherwise the read is asked for again.
                guard !folderChanged else { return }
                repositoryLookedUpAt[paneID] = .now
                terminal.readTmuxPaneIfDue()
                return
            }
            lookup = {
                // tmux keeps the shell's reports to itself, so in tmux it is asked where the shell is.
                guard let folder = TerminalRepository.path(fromReported: await terminal.workingDirectory(reported: reported))
                else { return terminal.survivesClose ? .unknown : .none }
                return await cache.answer(for: .init(host: terminal.server.id, folder: folder), maximumAge: interval) {
                    guard let answer = try? await terminal.runTmuxCommand(TerminalRepository.remoteCommand(folder: folder))
                    else { return .unknown }
                    return TerminalRepository.parseRemote(answer)
                }
            }
        }
        repositoryLookedUpAt[paneID] = .now
        repositoryLookups[paneID] = Task { [weak self] in
            let answer = await lookup()
            guard let self else { return }
            repositoryLookups[paneID] = nil
            guard !isClosed, state.root?.pane(id: paneID) != nil else { return }
            setRepository(answer, for: paneID)
            if repositoryFolderChanged.remove(paneID) != nil { lookUpRepository(for: paneID, folderChanged: true) }
        }
    }

    private func setRepository(_ answer: TerminalRepositoryAnswer, for paneID: UUID) {
        guard answer != .unknown else { return }
        let repository = answer.repository
        if repositoryByPaneID[paneID] != repository { repositoryByPaneID[paneID] = repository }
        shareRepository(repository, for: paneID)
    }

    /// Keeps the repository and branch on the pane's tmux session, for Active on every device:
    /// only a change, and only the name and branch, which are all a listing carries.
    private func shareRepository(_ found: TerminalRepository?, for paneID: UUID) {
        let repository = found.map { TerminalRepository(name: $0.name, branch: $0.branch) }
        if let shared = sharedRepositoryByPaneID[paneID], shared == repository { return }
        guard let pane = state.root?.pane(id: paneID) else { return }
        if let session = pane.intent.localTmuxSession {
            sharedRepositoryByPaneID[paneID] = repository
            MacLocalTmux.shareRepository(repository, session: session)
        } else if let terminal = sessionsByPaneID[paneID], terminal.survivesClose, terminal.state == .connected,
                  let session = terminal.tmuxSessionName,
                  let command = TerminalTmux.repositoryCommand(session: session, repository: repository) {
            sharedRepositoryByPaneID[paneID] = repository
            // One after another, so the host keeps the latest.
            let previous = repositoryWrite
            repositoryWrite = Task {
                await previous?.value
                do { _ = try await terminal.runTmuxCommand(command) } catch {
                    Logger.ssh.notice("A tab's repository didn't reach its tmux session: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func forgetRepository(of paneID: UUID) {
        repositoryLookups.removeValue(forKey: paneID)?.cancel()
        repositoryByPaneID.removeValue(forKey: paneID)
        repositoryLookedUpAt.removeValue(forKey: paneID)
        repositoryFolderChanged.remove(paneID)
        sharedRepositoryByPaneID.removeValue(forKey: paneID)
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
            runtime.model.onFullHistory = { [weak self] in await self?.localTmuxHistory(paneID) }
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

    /// Start every local pane independently of SwiftUI's lazy tab presentation, with the settings
    /// of the window it is in (W22) — what its view draws with once it is shown.
    func startLocalPanes(sessionManager: SessionManager, settingsManager: SettingsManager,
                         window: GlassWindowOverrides = GlassWindowOverrides(), onEmpty: @escaping () -> Void) {
        let profile = TerminalWindowProfile.resolved(window, settings: settingsManager)
        for pane in state.root?.panes ?? [] where pane.intent.kind == .local {
            // The session a new pane of the workgroup was given goes back to the workgroup (W4b).
            if let name = pane.intent.localTmuxSession {
                writeBackTmuxSession(name, paneID: pane.id, settingsManager: settingsManager)
            }
            guard let runtime = localRuntime(for: pane.id), !runtime.hasEngine,
                  let recorder = recorder(for: pane.id) else { continue }
            runtime.start(
                configuration: MacLocalTerminalConfiguration.resolve(
                    shell: pane.intent.localShell ?? settingsManager.localShell,
                    directory: pane.intent.localDirectory ?? settingsManager.localWorkingDirectory,
                    tmuxSession: pane.intent.localTmuxSession
                ),
                theme: profile.theme.swiftTermTheme,
                runtimeSettings: profile.runtimeSettings,
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
                          MacLocalTerminalExitPolicy.shouldClose(exitCode: exitCode,
                                                                 tmuxSession: localTmuxSession(for: pane.id),
                                                                 sessionRuns: MacLocalTerminalExitPolicy.localSessionRuns)
                    else { return }
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
            $0.intent.kind == .local && !$0.intent.withoutTmux && (enabled || $0.intent.localTmuxSession != nil)
        }
        guard !panes.isEmpty else { return false }
        let server = MacLocalTmux.server
        let tmux = server.executablePath()
        var running: Set<String>?
        var unreadable = false
        var held: Set<String>?
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
                    allocate: {
                        // Never a name a saved workgroup holds for this Mac (W4b).
                        if held == nil {
                            held = LayoutPreset.tmuxSessionsHeld(in: SettingsManager.savedLayoutPresets(in: defaults), serverID: nil)
                        }
                        return MacLocalTmux.allocateName(tmux: tmux, launch: localTmuxLaunch(for: pane), avoiding: held ?? [])
                    }
                )
            }
            // Restored, or opened from Active: no other pane is given it, running yet or not.
            if let session { MacLocalTmux.reserve(session) }
            // A workgroup's saved session, with a startup command to run: claimed first. Made
            // again, the command runs in it; still running, nothing is typed into what runs
            // there (W4b). A new name was made for this pane, so its command always runs.
            if let session, let tmux, session == pane.intent.localTmuxSession,
               retainedStartupTicketsByPaneID[pane.id] != nil {
                let claim = server.claim([session], localTmuxLaunch(for: pane), tmux)
                    .map { TerminalTmux.parseClaim($0, candidates: [session]) }
                if claim != .created(session) { retainedStartupTicketsByPaneID.removeValue(forKey: pane.id) }
            }
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

    /// `withoutTmux`: a plain shell, though the host keeps its terminals in tmux (2026-10-12).
    func addSSHPane(serverID: UUID, withoutTmux: Bool = false) {
        let axis = pendingSSHAxis ?? .horizontal
        pendingSSHAxis = nil
        let intent = MacWorkspacePaneIntent.ssh(serverID: serverID)
        addPane(intent: withoutTmux ? intent.startingWithoutTmux() : intent, axis: axis)
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
        sessionNameByPaneID.removeValue(forKey: paneID)
        sessionNameOwedPaneIDs.remove(paneID)
        forgetRepository(of: paneID)
        recordersByPaneID.removeValue(forKey: paneID)?.finalize()
        discardStartupCommand(for: paneID)
        state.root = root.removingPane(id: paneID)
        state.focusedPaneID = state.root?.paneIDs.first
        // Closing the last pane is the one change that may save an empty layout over one with
        // panes; the tab closing next discards the record altogether (`discardSavedState`).
        persist(emptyingSavedLayout: true)
    }

    func updateSplitFraction(_ splitID: UUID, fraction: Double) {
        guard let root = state.root, fraction.isFinite else { return }
        state.root = root.updatingSplitFraction(id: splitID, fraction: fraction)
        persist()
    }

    /// The pane's last attempt found no saved server by its id.
    func failedForMissingServer(_ paneID: UUID) -> Bool {
        if case .savedServerNotFound = pendingCredentialErrorsByPaneID[paneID] { return true }
        return false
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

    /// Edit ▸ Find, Find Next and Find Previous, for the focused pane's find bar.
    func requestFind(_ command: TerminalFindCommand) {
        guard let focusedPaneID else { return }
        findTargetPaneID = focusedPaneID
        findRequest = TerminalFindRequest(nonce: findRequest.nonce &+ 1, command: command)
    }

    private func prepareOffscreenRenderer(for session: TerminalSession, settingsManager: SettingsManager,
                                          window: GlassWindowOverrides) {
        let model = session.terminalHostModel
        // The window's settings (W22), as its pane draws with them once shown.
        let profile = TerminalWindowProfile.resolved(window, settings: settingsManager)
        SwiftTermHostView(model: model,
            theme: profile.theme.swiftTermTheme,
            runtimeSettings: profile.runtimeSettings,
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
        settingsManager: SettingsManager,
        window: GlassWindowOverrides = GlassWindowOverrides()
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
        // The pane as it is now: a retry after a session ended carries the name it claimed.
        let tmuxSession = state.root?.pane(id: pane.id)?.intent.sshTmuxSession ?? pane.intent.sshTmuxSession
        let withoutTmux = pane.intent.withoutTmux
        do {
            let launch = try await sessionManager.createAuthorizedSessionByServerID(
                serverID,
                settingsManager: settingsManager,
                startupCommand: startupCommand,
                configure: { [weak self] session in
                    // A plain shell by choice: no session, whatever the server's setting.
                    session.withoutTmux = withoutTmux
                    // W4b: its saved session, claimed — joined when it runs, made again when it
                    // has ended — or, without one, the session it claims kept for next time.
                    if !withoutTmux, let tmuxSession {
                        session.tmuxSessionName = tmuxSession
                        session.tmuxClaimsGivenName = true
                    }
                    self?.keepClaimedSSHTmuxSession(of: session, paneID: pane.id, settingsManager: settingsManager)
                    // Before it connects, so its first read is the one its attach asks for.
                    self?.watch(session, for: pane.id)
                },
                initialTerminalPresentation: { [weak self] pendingSession in
                    guard let self,
                          !isClosed,
                          generation == lifecycleGeneration,
                          isSamePane(pane) else { return }
                    sessionsByPaneID[pane.id] = pendingSession
                    observeOutput(of: pendingSession.terminalHostModel)
                    prepareOffscreenRenderer(for: pendingSession, settingsManager: settingsManager, window: window)
                }
            )
            guard !isClosed,
                  generation == lifecycleGeneration,
                  isSamePane(pane) else {
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
                  isSamePane(pane) else { return }
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

    /// The pane is still here, to start as it was asked: a tmux name written back to it while it
    /// connects leaves it the same pane.
    private func isSamePane(_ pane: MacWorkspacePane) -> Bool {
        state.root?.pane(id: pane.id)?.intent.startsSamePane(as: pane.intent) == true
    }

    // MARK: SSH panes keep their tmux sessions (W4b, 2026-10-08)

    /// The pane keeps the tmux session its terminal is in. Returns whether that changed it.
    @discardableResult
    private func setSSHTmuxSession(_ name: String, for paneID: UUID) -> Bool {
        guard TerminalTmux.isValidSessionName(name), let root = state.root,
              let pane = root.pane(id: paneID), pane.intent.kind == .ssh,
              pane.intent.sshTmuxSession != name else { return false }
        state.root = root.updatingPane(id: paneID) { $0.intent.sshTmuxSession = name }
        return true
    }

    /// Keeps the name the pane's terminal claims for a new session: saved with the tab, so a
    /// relaunch reattaches to it, and — for a pane its workgroup just opened — written back to
    /// the workgroup, once. A tab its window has not saved yet saves it when the window opens.
    private func keepClaimedSSHTmuxSession(of session: TerminalSession, paneID: UUID, settingsManager: SettingsManager?) {
        session.tmuxSessionClaimed = { [weak self, weak settingsManager] name in
            guard let self, !isClosed, sessionsByPaneID[paneID] == nil || sessionsByPaneID[paneID] === session else { return }
            if setSSHTmuxSession(name, for: paneID), !hasUnsavedState { persist() }
            if let settingsManager { writeBackTmuxSession(name, paneID: paneID, settingsManager: settingsManager) }
        }
    }

    /// A pane its workgroup just opened, without a saved tmux session, was given `name`: the
    /// workgroup keeps it, so it opens on the same session next time, here or on another device.
    private func writeBackTmuxSession(_ name: String, paneID: UUID, settingsManager: SettingsManager) {
        guard panesOpenedFromWorkgroup.contains(paneID), let workgroupID,
              let pane = state.root?.pane(id: paneID), let index = pane.intent.sourceSessionIndex else { return }
        panesOpenedFromWorkgroup.remove(paneID)
        let opened = LayoutPreset.SessionIntent(kind: pane.intent.kind == .local ? .local : .ssh,
                                                serverID: pane.intent.serverID)
        settingsManager.recordWorkgroupTmuxSession(name, workgroupID: workgroupID, index: index, opened: opened)
    }

    func closeAllSessions(sessionManager: SessionManager) {
        // Local terminals in tmux detach: they keep running, for Active or the next launch.
        for pane in state.root?.panes ?? [] {
            guard let tmuxSession = pane.intent.localTmuxSession else { continue }
            letGoOfLocalTmuxSession(tmuxSession, wasShown: localRuntimesByPaneID[pane.id] != nil)
        }
        isClosed = true
        lifecycleGeneration &+= 1
        for lookup in repositoryLookups.values { lookup.cancel() }
        repositoryLookups.removeAll()
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
        // Let go of in this run, by a close or a quit: never offered back as left running (W7b).
        MacLocalTmuxLaunchOffer.shared.noteClosed(name)
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

    /// Saves a layout made rather than read (a new tab, or a tmux name given as it opened) once a
    /// window shows the tab. Nothing otherwise.
    func saveIfUnsaved() {
        if hasUnsavedState { persist() }
    }

    /// The tab is closing for good, so its saved layout goes too, read or not. One left behind
    /// was a layout a window could later come back to as an empty tab (W7b).
    func discardSavedState() {
        hasUnsavedState = false
        defaults.removeObject(forKey: Self.defaultsKey(for: state.id))
    }

    /// Stands in for a window whose saved tabs couldn't be read: says so, and saves nothing.
    func markNotRestored(_ reason: String) {
        restorationFailure = reason
        hasUnsavedState = false
    }

    /// Saves the layout, except over a saved one that couldn't be read, which stays as it was. An
    /// empty layout replaces one with panes only when the last pane was closed: a copy of the tab
    /// made before its layout was first saved would otherwise empty it (W7b).
    private func persist(emptyingSavedLayout: Bool = false) {
        guard restorationFailure == nil else { return }
        let key = Self.defaultsKey(for: state.id)
        do {
            _ = try state.validated(for: state.id)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            guard data.count <= Self.maximumEncodedBytes else {
                throw MacWorkspaceStateError.encodedStateTooLarge
            }
            hasUnsavedState = false
            if state.root == nil, !emptyingSavedLayout, let saved = defaults.data(forKey: key),
               Self.mayHavePanes(saved) {
                Logger.workspaceRestoration.error(
                    "Kept the saved layout of terminal tab \(self.state.id.uuidString, privacy: .public): an empty one would have replaced it although no one closed it"
                )
                return
            }
            defaults.set(data, forKey: key)
            // A pane may have just been given a tmux session: the reopen list follows (W12).
            NotificationCenter.default.post(name: .macWorkspaceRecordSaved, object: defaults)
        } catch {
            Logger.settings.error(
                "Refusing to persist invalid workspace state: \(error.localizedDescription, privacy: .public)"
            )
            assertionFailure("Refusing to persist invalid workspace state: \(error)")
        }
    }

    /// A saved layout that couldn't be read counts as having panes: it may well have had them.
    private static func mayHavePanes(_ data: Data) -> Bool {
        guard let saved = try? JSONDecoder().decode(MacWorkspaceRestorationState.self, from: data) else { return true }
        return saved.root != nil
    }

    private struct LoadResult {
        let state: MacWorkspaceRestorationState
        let hadRestorationData: Bool
        /// What the tab says when its record exists but couldn't be read.
        var failure: String? = nil
    }

    /// What went wrong reading a saved layout, in words for the log: the kind of failure and
    /// where, never the values themselves.
    static func plainDescription(of error: Error) -> String {
        func place(_ context: DecodingError.Context) -> String {
            context.codingPath.isEmpty ? "the top level" : context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case let error as MacWorkspaceStateError:
            return error.errorDescription ?? "it failed validation"
        case DecodingError.dataCorrupted(let context):
            return "it is damaged at \(place(context))"
        case DecodingError.keyNotFound(let key, let context):
            return "\(key.stringValue) is missing at \(place(context))"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            return "a value has the wrong type at \(place(context))"
        default:
            return "it couldn't be decoded"
        }
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
            Logger.workspaceRestoration.error(
                "Couldn't restore terminal tab \(workspaceID.uuidString, privacy: .public): its saved layout is \(data.count, privacy: .public) bytes, over the limit. It is kept unchanged."
            )
            return LoadResult(
                state: .empty(id: workspaceID),
                hadRestorationData: true,
                failure: "Its saved layout is larger than this version can read."
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
            Logger.workspaceRestoration.error(
                "Couldn't restore terminal tab \(workspaceID.uuidString, privacy: .public): \(plainDescription(of: error), privacy: .public). Its saved layout (\(data.count, privacy: .public) bytes) is kept unchanged."
            )
            return LoadResult(
                state: .empty(id: workspaceID),
                hadRestorationData: true,
                failure: "Its saved layout couldn't be read."
            )
        }
    }

    private static func defaultsKey(for workspaceID: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).\(workspaceID.uuidString.lowercased())"
    }

    /// The panes a tab's record holds, read without making the tab: nil when it has no record
    /// that can be read. The reopen list asks, so it never opens a window of tabs another window
    /// already shows (W12).
    static func savedPanes(workspaceID: UUID, defaults: UserDefaults) -> [MacWorkspacePane]? {
        guard let data = defaults.data(forKey: defaultsKey(for: workspaceID)), data.count <= maximumEncodedBytes,
              let state = try? JSONDecoder().decode(MacWorkspaceRestorationState.self, from: data)
                .validated(for: workspaceID) else { return nil }
        return state.root?.panes ?? []
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
        /// The tabs moving together, in the order the new window lists them (W8).
        let controllers: [MacWorkspaceController]
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
        controllers: [MacWorkspaceController],
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
            controllers: controllers,
            expirationTask: expirationTask,
            commit: commit,
            invalidate: invalidate
        )
        order.append(id)
        return id
    }

    /// The tabs a ticket moves, all of them or none: one closed meanwhile fails the whole move.
    func claim(_ id: UUID) -> [MacWorkspaceController]? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        entry.expirationTask.cancel()
        guard !entry.controllers.isEmpty, !entry.controllers.contains(where: \.isClosed), entry.commit(id) else {
            entry.invalidate(id)
            return nil
        }
        return entry.controllers
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
    /// The tab shown. Always one of `selectedTabIDs`.
    private(set) var selectedTabID: UUID
    /// The tabs selected in the sidebar: a click selects one, ⌘-click adds or removes one,
    /// ⇧-click a range (W8, owner, 2026-10-08). Not saved: a window reopens with its shown tab.
    private(set) var selectedTabIDs: Set<UUID> = []
    /// The selected tabs in the order they were picked. The tab shown is the last of them, as in
    /// Finder and Mail, so the detail never goes blank while the selection changes.
    @ObservationIgnored private var selectionOrder: [UUID] = []

    private let defaults: UserDefaults
    private let startupCommandBroker: MacStartupCommandBroker
    private let liveSessionBroker: MacLiveSessionBroker
    private let transferBroker: MacWorkspaceTransferBroker
    private var pendingTransferTicketsByWorkspaceID: [UUID: UUID] = [:]
    /// Why this window's saved tabs could not be read, or nil. The record is then kept as it was,
    /// never written over, until its one tab is closed (W7b).
    private(set) var restorationFailure: String?
    /// The tabs shown differ from the saved record: a new window, or one rebuilt from its
    /// request. Saved when the window opens (`windowDidOpen`), never by init (W7b).
    @ObservationIgnored private var hasUnsavedState = false
    /// Where the window is, saved with its tabs (W12): read from its record, then kept current
    /// by its window (`MacWorkspaceWindowPlacementTracker`).
    @ObservationIgnored private(set) var placement: MacWorkspaceWindowPlacement?
    /// The place read from the record, for the window's first appearance only.
    @ObservationIgnored private var placementToRestore: MacWorkspaceWindowPlacement?
    /// The window's own settings (W20's look, W22): every tab in it draws and behaves with them,
    /// local panes and SSH ones, and a tab moved in takes them. Empty follows the settings. Saved
    /// with the window's tabs; a new window opens with its request's (a saved Workgroup's, or the
    /// window its tabs left).
    private(set) var windowSettings = GlassWindowOverrides()

    /// Makes the window's tabs and writes nothing: SwiftUI makes controllers it throws away, and a
    /// window macOS restores after a crash must come back as it was saved, not be rewritten by
    /// whatever its request held (W7b). The window saves when it opens or changes.
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

        func makeTab(_ request: MacWorkspaceTabRequest) -> MacWorkspaceController {
            MacWorkspaceController(
                request: request,
                startupCommandBroker: startupCommandBroker,
                liveSessionBroker: liveSessionBroker,
                defaults: defaults
            )
        }

        let resolvedTabs: [MacWorkspaceController]
        let resolvedSelectedTabID: UUID
        var savesNow = false
        var unsaved = false
        var failure: String?
        var resolvedSettings = GlassWindowOverrides()
        let transferred = request.transferredTabTicketID.flatMap { transferBroker.claim($0) } ?? []
        if let first = transferred.first {
            // The move already happened: the source window has let the tabs go, so this one
            // saves them now rather than leaving them in neither record until it opens.
            resolvedTabs = transferred
            resolvedSelectedTabID = request.initialSelectedTabID.flatMap { requested in
                transferred.first(where: { $0.workspaceID == requested })?.workspaceID
            } ?? first.workspaceID
            resolvedSettings = request.windowSettings
            savesNow = true
        } else {
            // A moved tab's ticket dies with the process. After a crash macOS hands the window
            // the same request, and its saved record still holds the tab that moved in; a ticket
            // that failed in this process finds no record and fails closed with an empty tab.
            switch Self.load(windowID: request.windowID, defaults: defaults) {
            case .restored(let restored):
                resolvedTabs = restored.tabs.map { makeTab($0.request) }
                resolvedSelectedTabID = restored.selectedTabID
                placement = restored.placement
                placementToRestore = restored.placement
                resolvedSettings = restored.windowSettings
            case .unreadable(let reason):
                let fallback = makeTab(MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: true))
                fallback.markNotRestored(reason)
                failure = reason
                resolvedTabs = [fallback]
                resolvedSelectedTabID = fallback.workspaceID
            case .absent where request.transferredTabTicketID != nil:
                let fallback = makeTab(MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: true))
                resolvedTabs = [fallback]
                resolvedSelectedTabID = fallback.workspaceID
                unsaved = true
            case .absent:
                resolvedTabs = request.tabs.map(makeTab)
                resolvedSelectedTabID = request.initialSelectedTabID.flatMap { requested in
                    resolvedTabs.first(where: { $0.workspaceID == requested })?.workspaceID
                } ?? resolvedTabs[0].workspaceID
                resolvedSettings = request.windowSettings
                unsaved = true
            }
        }
        tabs = resolvedTabs
        selectedTabID = resolvedSelectedTabID
        windowSettings = resolvedSettings
        restorationFailure = failure
        hasUnsavedState = unsaved
        collapseSelection()
        saveNamesTakenFromSessions()
        if savesNow { persist() }
        // Made once per window: its view asks the registry first (`windowController(for:)`).
        MacWorkspacePreviewRegistry.shared.noteBuilt(self)
    }

    /// The window is on screen: saves what it opened with that is not saved yet — a new window,
    /// a new tab's layout, a tmux name given as a tab opened. A window restored unchanged writes
    /// nothing, and one whose record couldn't be read leaves it alone.
    func windowDidOpen() {
        guard restorationFailure == nil else { return }
        if hasUnsavedState {
            persist()
        } else {
            for tab in tabs { tab.saveIfUnsaved() }
        }
    }

    /// Where the window was when it was saved, the first time it is asked and only then: a window
    /// reopened from its record goes back there once, as it first appears (W12).
    func takePlacementToRestore() -> MacWorkspaceWindowPlacement? {
        defer { placementToRestore = nil }
        return placementToRestore
    }

    /// The window moved, resized, or went in or out of full screen: saved with its tabs, unless
    /// it is where it was saved. Never over a record that couldn't be read (`persist`).
    func savePlacement(_ placement: MacWorkspaceWindowPlacement) {
        guard let placement = placement.validated(), placement != self.placement else { return }
        self.placement = placement
        persist()
    }

    /// Gives the window its own settings, or none (W20, W22), from any tab's Settings ▸ This
    /// Window: every tab draws and behaves with them at once, and they are saved with the tabs.
    /// Never over a record that couldn't be read (`persist`); a saved Workgroup is changed only by
    /// saving the window as it.
    func setWindowSettings(_ settings: GlassWindowOverrides) {
        guard settings != windowSettings else { return }
        windowSettings = settings
        persist()
    }

    /// Whether this window's tabs are saved, so a launch request with its id restores them.
    static func hasSavedState(windowID: UUID, defaults: UserDefaults = .standard) -> Bool {
        if case .restored = load(windowID: windowID, defaults: defaults) { return true }
        return false
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
                    // The tmux session each terminal is in now, so the workgroup reopens on it
                    // (W4b): the live terminal's for SSH, which may have claimed one since.
                    let tmuxSession = intent.kind == .local
                        ? intent.localTmuxSession
                        : (tab.session(for: pane.id)?.tmuxSessionName ?? intent.sshTmuxSession)
                    intents.append(.init(kind: intent.kind == .local ? .local : .ssh,
                                         serverID: intent.serverID,
                                         label: intent.label,
                                         startupCommand: tab.explicitStartupCommandsByPaneID[pane.id] ?? sourceCommand,
                                         localShell: intent.kind == .local
                                            ? (tab.localRuntimesByPaneID[pane.id]?.launchedShell ?? intent.localShell ?? defaultLocalShell) : nil,
                                         localDirectory: intent.kind == .local
                                            ? (tab.localDirectory(for: pane.id) ?? intent.localDirectory ?? defaultLocalDirectory)
                                            : nil,
                                         tmuxSession: tmuxSession,
                                         withoutTmux: intent.withoutTmux))
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
        var preset = LayoutPreset(name: name, colorTag: selectedTab.workgroupColor ?? .blue,
                                  sessionIntents: intents,
                                  workspaceLayout: .init(tabs: savedTabs, selectedTabIndex: selectedIndex))
        // The window's settings go with it, so the workgroup opens as this window is (W20, W22).
        preset.windowSettings = windowSettings
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
    /// Not in a window whose saved tabs couldn't be read: the new tab would be saved over them.
    var canAddTab: Bool {
        restorationFailure == nil && tabs.count < MacWorkspaceWindowRestorationState.maximumTabCount
    }
    /// Move Tab to New Window, for the tabs selected in the sidebar.
    var canTransferSelectedTab: Bool {
        canTransferTabs(selectedTabIDs)
    }

    /// Whether these tabs can go to a new window together: each still here, none already on its
    /// way. A window's only tab stays, since a window holding just it changes nothing; two or more
    /// may be every tab, and this window then closes (W8).
    func canTransferTabs(_ ids: Set<UUID>) -> Bool {
        let moving = tabs.filter { ids.contains($0.workspaceID) }
        return !closesAfterLastTabLeft && !moving.isEmpty && moving.count == ids.count
            && (moving.count > 1 || tabs.count > 1)
            && moving.allSatisfy { pendingTransferTicketsByWorkspaceID[$0.workspaceID] == nil }
    }

    /// Shows a tab, and makes it the only one selected: ⌘1–⌘9, the overview, Active.
    func select(_ workspaceID: UUID) {
        guard tabs.contains(where: { $0.workspaceID == workspaceID }) else { return }
        selectedTabID = workspaceID
        collapseSelection()
        persist()
    }

    /// The sidebar's selection, as the list reports it: a click selects one tab, ⌘-click adds or
    /// removes one, ⇧-click a range. The tab shown is the one picked last that is still selected,
    /// and an empty selection keeps the tab shown: the detail never goes blank (W8).
    func updateSelection(_ ids: Set<UUID>) {
        let order = tabs.map(\.workspaceID)
        let selected = ids.intersection(order)
        guard !selected.isEmpty else { return collapseSelection() }
        // A range arrives as several tabs at once. The one clicked is the end farthest from the
        // tab shown, so it counts as picked last.
        let anchor = order.firstIndex(of: selectedTabID) ?? 0
        let added = order.indices
            .filter { selected.contains(order[$0]) && !selectedTabIDs.contains(order[$0]) }
            .sorted { (abs($0 - anchor), $0) < (abs($1 - anchor), $1) }
            .map { order[$0] }
        selectionOrder = selectionOrder.filter(selected.contains) + added
        if selectedTabIDs != selected { selectedTabIDs = selected }
        if let shown = selectionOrder.last, shown != selectedTabID {
            selectedTabID = shown
            persist()
        }
    }

    /// One tab selected: the one shown.
    private func collapseSelection() {
        if selectedTabIDs != [selectedTabID] { selectedTabIDs = [selectedTabID] }
        selectionOrder = [selectedTabID]
    }

    /// Takes a tab out of the list; never the last, which callers handle. When it was the tab
    /// shown, the tab picked before it in the selection is shown, or else the tab beside it.
    private func takeOut(at index: Int) -> MacWorkspaceController {
        let controller = tabs.remove(at: index)
        let id = controller.workspaceID
        selectionOrder.removeAll { $0 == id }
        selectedTabIDs.remove(id)
        guard !tabs.isEmpty else { return controller }
        if selectedTabID == id {
            selectedTabID = selectionOrder.last ?? tabs[min(index, tabs.count - 1)].workspaceID
        }
        if !selectedTabIDs.contains(selectedTabID) { collapseSelection() }
        return controller
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
        collapseSelection()
        saveNamesTakenFromSessions()
        persist()
        return controller
    }

    /// A tab that takes the name its tmux session was given on another device, or loses it there,
    /// has its window save it (W19), as Rename does.
    private func saveNamesTakenFromSessions() {
        for tab in tabs {
            tab.nameTakenFromSession = { [weak self, weak tab] in
                guard let self, let tab, tabs.contains(where: { $0 === tab }) else { return }
                persist()
            }
        }
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
        // Closing a tab discards its saved layout, read or not: a record left behind was a layout
        // a window could come back to empty (W7b). A tab kept running elsewhere is not closed.
        if tabs.count == 1 {
            cancelPendingTransfer(for: workspaceID)
            if closeSessions {
                tabs[0].closeAllSessions(sessionManager: sessionManager)
                tabs[0].discardSavedState()
            }
            forgetSavedWindow()
            return true
        }
        cancelPendingTransfer(for: workspaceID)
        let controller = takeOut(at: index)
        if closeSessions {
            controller.closeAllSessions(sessionManager: sessionManager)
            controller.discardSavedState()
        }
        guard !tabs.isEmpty else {
            forgetSavedWindow()
            return true
        }
        persist()
        return false
    }

    /// Closes several tabs, each as closing it alone would: a terminal in tmux detaches and keeps
    /// running (W8). True when that was every tab, and the window closes.
    @discardableResult
    func removeTabs(_ ids: Set<UUID>, sessionManager: SessionManager) -> Bool {
        for id in tabs.map(\.workspaceID) where ids.contains(id) {
            if removeTab(id, sessionManager: sessionManager) { return true }
        }
        return false
    }

    /// What closing these tabs should ask, or nil when none would stop anything. Each tab is
    /// judged by the rules for closing it alone (D44), so a terminal kept in tmux never counts.
    func closeWarning(forTabs ids: Set<UUID>) -> String? {
        Self.closeWarning(combining: tabs.filter { ids.contains($0.workspaceID) }.map(\.closeWarning))
    }

    /// One tab's own warning; for several, the one that would stop something, or how many would.
    static func closeWarning(combining warnings: [String?]) -> String? {
        let asking = warnings.compactMap { $0 }
        guard let first = asking.first else { return nil }
        if warnings.count == 1 { return first }
        if asking.count == 1 {
            let single = "This tab "
            return first.hasPrefix(single) ? "One of these tabs " + first.dropFirst(single.count) : first
        }
        return "\(asking.count) of these tabs have SSH sessions, running commands, a recording or a connection still starting. Closing them will stop those."
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
        acceptDroppedTabs([drag], at: index)
    }

    /// Tabs dragged together from one window's sidebar — the selected rows — dropped at `index`:
    /// reordered as a block within this window, or moved here running, in their sidebar order,
    /// from another (W8). All of them or none: false when this window can't take them all.
    @discardableResult
    func acceptDroppedTabs(_ drags: [MacWorkspaceTabDrag], at index: Int) -> Bool {
        guard !closesAfterLastTabLeft, let sourceID = drags.first?.windowID,
              drags.allSatisfy({ $0.windowID == sourceID }) else { return false }
        let ids = drags.map(\.workspaceID)
        if sourceID == windowID {
            return moveTabs(ids, to: index)
        }
        guard restorationFailure == nil,
              tabs.count + Set(ids).count <= MacWorkspaceWindowRestorationState.maximumTabCount,
              let source = MacWorkspacePreviewRegistry.shared.shownController(windowID: sourceID) else { return false }
        let moving = source.detachTabsForMove(ids)
        guard !moving.isEmpty else { return false }
        adoptTabs(moving, at: index)
        return true
    }

    /// Reorders: `index` is where the tab lands in the list as it was before the move.
    @discardableResult
    func moveTab(_ workspaceID: UUID, to index: Int) -> Bool {
        moveTabs([workspaceID], to: index)
    }

    /// Reorders several tabs as a block, in their sidebar order; `index` is counted in the list as
    /// it was before the move.
    @discardableResult
    func moveTabs(_ ids: [UUID], to index: Int) -> Bool {
        let moving = Set(ids)
        let block = tabs.filter { moving.contains($0.workspaceID) }
        guard !block.isEmpty else { return false }
        let target = min(max(index, 0), tabs.count)
        let movedFromAbove = tabs.prefix(target).filter { moving.contains($0.workspaceID) }.count
        tabs.removeAll { moving.contains($0.workspaceID) }
        tabs.insert(contentsOf: block, at: min(target - movedFromAbove, tabs.count))
        persist()
        return true
    }

    /// Lets a tab go to another window, its terminals untouched. The last tab leaves a
    /// placeholder and closes the window.
    func detachTabForMove(_ workspaceID: UUID) -> MacWorkspaceController? {
        detachTabsForMove([workspaceID]).first
    }

    /// Lets tabs go to another window, in sidebar order, their terminals untouched, and saves the
    /// tabs left. When none is left, a placeholder stands in and the window closes.
    func detachTabsForMove(_ ids: [UUID]) -> [MacWorkspaceController] {
        guard !closesAfterLastTabLeft else { return [] }
        let leaving = Set(ids)
        var moved: [MacWorkspaceController] = []
        for id in tabs.map(\.workspaceID) where leaving.contains(id) {
            cancelPendingTransfer(for: id)
            guard let index = tabs.firstIndex(where: { $0.workspaceID == id }) else { continue }
            if tabs.count == 1 {
                moved.append(tabs[0])
                standInForLastTab()
                return moved
            }
            moved.append(takeOut(at: index))
        }
        if !moved.isEmpty { persist() }
        return moved
    }

    /// The last tab has gone to another window: a placeholder stands in until the view closes the
    /// window, so nothing reads an empty list, and the window's record goes.
    private func standInForLastTab() {
        let placeholder = MacWorkspaceController(
            request: MacWorkspaceTabRequest(workspaceID: UUID(), startsEmpty: true),
            startupCommandBroker: startupCommandBroker,
            liveSessionBroker: liveSessionBroker,
            defaults: defaults
        )
        tabs = [placeholder]
        selectedTabID = placeholder.workspaceID
        collapseSelection()
        closesAfterLastTabLeft = true
        forgetSavedWindow()
    }

    /// Takes in a tab another window let go of, at `index`, and shows it.
    func adoptTab(_ controller: MacWorkspaceController, at index: Int) {
        adoptTabs([controller], at: index)
    }

    /// Takes in tabs another window let go of, at `index` in their order, selects them all and
    /// shows the first.
    func adoptTabs(_ controllers: [MacWorkspaceController], at index: Int) {
        guard let first = controllers.first else { return }
        tabs.insert(contentsOf: controllers, at: min(max(index, 0), tabs.count))
        selectedTabID = first.workspaceID
        selectedTabIDs = Set(controllers.map(\.workspaceID))
        selectionOrder = controllers.reversed().map(\.workspaceID)
        saveNamesTakenFromSessions()
        persist()
    }

    /// Move Tab to New Window, for the tabs selected in the sidebar.
    func transferSelectedTab() -> MacWorkspaceLaunchRequest? {
        transferTabs(selectedTabIDs)
    }

    /// Move Tabs to New Window: a request for a window holding these tabs, in sidebar order and
    /// still running, showing the one picked last. Nothing leaves this window until that window
    /// claims them; then this one saves the tabs left, or closes when none is (W8, W7b).
    func transferTabs(_ ids: Set<UUID>) -> MacWorkspaceLaunchRequest? {
        guard canTransferTabs(ids) else { return nil }
        let moving = tabs.filter { ids.contains($0.workspaceID) }
        let movingIDs = moving.map(\.workspaceID)
        // Emptying the window was asked for only if every tab was chosen. One that would empty
        // because the others closed meanwhile keeps its tab, and the new window fails closed.
        let takesEveryTab = moving.count == tabs.count
        let ticketID = transferBroker.issue(
            controllers: moving,
            commit: { [weak self] ticketID in
                self?.commitTransfer(movingIDs, ticketID: ticketID, mayEmptyWindow: takesEveryTab) ?? false
            },
            invalidate: { [weak self] ticketID in
                self?.invalidateTransfer(movingIDs, ticketID: ticketID)
            }
        )
        for id in movingIDs { pendingTransferTicketsByWorkspaceID[id] = ticketID }
        var request = MacWorkspaceLaunchRequest(
            windowID: UUID(),
            tabs: moving.map(\.restorationDescriptor.request),
            transferredTabTicketID: ticketID
        )
        request.initialSelectedTabID = selectionOrder.last(where: movingIDs.contains) ?? movingIDs[0]
        // The new window looks like the one they left, as a Safari profile's tab keeps its
        // profile in a new window (W20, W22). Dragged into another window, a tab takes that one's.
        request.windowSettings = windowSettings
        return request
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

    /// The new window claimed its tabs: they leave this one, which saves the tabs left.
    private func commitTransfer(_ ids: [UUID], ticketID: UUID, mayEmptyWindow: Bool) -> Bool {
        guard ids.allSatisfy({ pendingTransferTicketsByWorkspaceID[$0] == ticketID }) else {
            return false
        }
        for id in ids { pendingTransferTicketsByWorkspaceID.removeValue(forKey: id) }
        guard !closesAfterLastTabLeft,
              ids.allSatisfy({ id in tabs.contains { $0.workspaceID == id } }),
              mayEmptyWindow || tabs.count > ids.count else {
            return false
        }
        return detachTabsForMove(ids).count == ids.count
    }

    private func invalidateTransfer(_ ids: [UUID], ticketID: UUID) {
        for id in ids where pendingTransferTicketsByWorkspaceID[id] == ticketID {
            pendingTransferTicketsByWorkspaceID.removeValue(forKey: id)
        }
    }

    private func cancelPendingTransfer(for workspaceID: UUID) {
        guard let ticketID = pendingTransferTicketsByWorkspaceID[workspaceID] else {
            return
        }
        transferBroker.discard(ticketID)
    }

    /// Saves the window's tabs, and the layouts of new ones. Never over a record that couldn't be
    /// read, and never for a window whose last tab has left. When the list of tabs changes, the
    /// record it replaces is kept as the one previous generation (W7b).
    private func persist() {
        guard restorationFailure == nil, !closesAfterLastTabLeft else { return }
        for tab in tabs { tab.saveIfUnsaved() }
        let state = MacWorkspaceWindowRestorationState(
            tabs: tabs.map(\.restorationDescriptor),
            selectedTabID: selectedTabID,
            placement: placement,
            windowSettings: windowSettings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard state.validated() != nil,
              let data = try? encoder.encode(state),
              data.count <= Self.maximumEncodedBytes else {
            assertionFailure("Refusing to persist invalid macOS window tabs")
            return
        }
        hasUnsavedState = false
        let key = Self.defaultsKey(for: windowID)
        let saved = defaults.data(forKey: key)
        guard saved != data else { return }
        // One generation back, bounded to one record per window: enough to undo a bad write.
        // Only when the tabs themselves change, so selecting a tab never pushes it out.
        if let saved, let previous = Self.decode(saved), previous.tabs.map(\.id) != state.tabs.map(\.id) {
            defaults.set(saved, forKey: Self.previousGenerationKey(for: windowID))
        }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: .macWorkspaceRecordSaved, object: defaults)
    }

    /// The window is going for good: its record and the generation kept behind it.
    private func forgetSavedWindow() {
        defaults.removeObject(forKey: Self.defaultsKey(for: windowID))
        defaults.removeObject(forKey: Self.previousGenerationKey(for: windowID))
    }

    enum SavedWindow {
        case restored(MacWorkspaceWindowRestorationState)
        /// A record exists but neither it nor the generation before it can be read.
        case unreadable(String)
        case absent
    }

    /// The saved window, or the generation before it when the record itself can't be read.
    static func load(windowID: UUID, defaults: UserDefaults) -> SavedWindow {
        guard let data = defaults.data(forKey: defaultsKey(for: windowID)) else {
            return defaults.object(forKey: defaultsKey(for: windowID)) == nil
                ? .absent : .unreadable("This window's saved tabs couldn't be read.")
        }
        if let state = decode(data) { return .restored(state) }
        let previous = defaults.data(forKey: previousGenerationKey(for: windowID)).flatMap(decode)
        Logger.workspaceRestoration.error(
            "Couldn't read terminal window \(windowID.uuidString, privacy: .public)'s saved tabs (\(data.count, privacy: .public) bytes). \(previous == nil ? "No earlier generation can be read either; the record is kept unchanged." : "Restoring the generation before it.", privacy: .public)"
        )
        if let previous { return .restored(previous) }
        return .unreadable("This window's saved tabs couldn't be read.")
    }

    private static func decode(_ data: Data) -> MacWorkspaceWindowRestorationState? {
        guard data.count <= maximumEncodedBytes else { return nil }
        return (try? JSONDecoder().decode(MacWorkspaceWindowRestorationState.self, from: data))?.validated()
    }

    private static func defaultsKey(for windowID: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(windowID.uuidString.lowercased())"
    }

    static func previousGenerationKey(for windowID: UUID) -> String {
        defaultsKey(for: windowID) + ".previous"
    }
}
#endif

#endif
