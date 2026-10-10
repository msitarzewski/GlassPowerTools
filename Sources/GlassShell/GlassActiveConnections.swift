//
//  GlassActiveConnections.swift
//  Glass Power Tools — GlassShell
//
//  **Active**: the library's fourth category, and the ⚡ that takes you to it from anywhere.
//
//  The library already knew every machine; it only lacked which ones were live. So instead of a
//  switcher bolted onto every session's chrome (2026-09-21, morning), the live connections are a
//  row in the sidebar beside All, Favorites and Recent — grouped by machine, each machine a
//  disclosure over its live sessions, the way the Files list groups a folder over its files — and
//  every top toolbar in the app carries one control that means "take me there".
//
//  A row is a session, and choosing it **switches to** the open session rather than opening a
//  second one: on a Mac the window comes forward, on a phone the root swaps. That is what makes
//  the library the switcher instead of a list beside one.
//
//  W13 (owner, 2026-10-09, on the Vision Pro): "Multiselect from the 'Active' would be stellar …
//  I'd like to select multiple and open in a new window like the tab view." Sessions running on
//  the machines can be chosen together — ⌘-click and ⇧-click on a Mac, Select on the others — and
//  opened as one new window, a tab each, or ended together.
//

import SwiftUI
import GlassConnectionKit
import GlassConnectionUI
#if os(macOS)
import AppKit
#endif

/// "Take me to the live connections." Supplied to each capability's runtime by the composition
/// root, because the library is the shell's and a capability must not hold the shell.
public typealias GlassShowActiveConnections = @MainActor () -> Void

/// One machine's live sessions.
public struct GlassActiveMachine: Identifiable {
    /// The canonical host id, or a stand-in for sessions no machine in the library owns.
    public let id: String
    public let name: String
    public let sessions: [GlassOpenSession]
    /// Running on the machine (D44): detached, open on another device, or open here in a window
    /// the app lists nowhere else (W6).
    public var running: [GlassRunningSession] = []
    /// Why the machine's running sessions were not asked for, when they were not (W6).
    public var notChecked: String? = nil
}

public extension GlassShellModel {
    static let activePanelID = "active"

    /// Every open session, grouped by the machine it is on, machines in library order and
    /// sessions in the order their capabilities gave them.
    ///
    /// Read in a view body: it walks `openSessions()`, which is answered from each capability's
    /// live state, so the sidebar count and the list follow what is actually open.
    func activeMachines() -> [GlassActiveMachine] {
        var order: [String] = []
        var grouped: [String: (name: String, sessions: [GlassOpenSession])] = [:]
        for session in registry.openSessions() {
            let owner = session.endpointIDs.lazy.compactMap { self.host(owningEndpoint: $0) }.first
                ?? session.hostID.flatMap { self.host($0) }
            let key = owner?.id.rawValue.uuidString ?? "elsewhere"
            let name = owner?.displayName ?? "Elsewhere"
            if grouped[key] == nil { order.append(key); grouped[key] = (name, []) }
            grouped[key]?.sessions.append(session)
        }
        var machines = order.map { GlassActiveMachine(id: $0, name: grouped[$0]!.name, sessions: grouped[$0]!.sessions) }
        func machineIndex(owning endpoint: EndpointID) -> Int? {
            guard let owner = host(owningEndpoint: endpoint) else { return nil }
            let key = owner.id.rawValue.uuidString
            if let index = machines.firstIndex(where: { $0.id == key }) { return index }
            machines.append(GlassActiveMachine(id: key, name: owner.displayName, sessions: []))
            return machines.count - 1
        }
        for session in runningSessions {
            guard let index = machineIndex(owning: session.endpointID) else { continue }
            machines[index].running.append(session)
        }
        for unchecked in uncheckedMachines {
            guard let index = machineIndex(owning: unchecked.endpointID) else { continue }
            machines[index].notChecked = unchecked.reason
        }
        return machines
    }

    /// Opens a running session here, or takes it over. It leaves the list at once — it is about
    /// to be open on this device, where Active lists it as open — and the hosts are asked again
    /// once the attach has had time to land. Until 2026-10-03 the row stayed, "Detached", under
    /// the same terminal's open row until something else refreshed the list. A session already
    /// open here only comes forward, and stays listed (W6).
    func open(_ session: GlassRunningSession, takingOver: Bool = false) {
        guard !session.isOpenHere else { return session.open() }
        runningSessions.removeAll { $0.id == session.id }
        if takingOver { session.takeOver() } else { session.open() }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await refreshRunningSessions()
        }
    }

    /// Asks every capability what is running on its hosts (D44). One pass at a time, and none
    /// before the library has loaded: a capability reads its saved machines from the catalog
    /// (`catalogDidLoad`), and asked earlier it knows none. The owner, on the Vision Pro
    /// (2026-10-09): the app relaunched with Active showing, Active asked first, and that empty
    /// answer stood until a manual refresh. The library asks once it has loaded.
    func refreshRunningSessions() async {
        guard isLoaded, !isCheckingRunningSessions else { return }
        isCheckingRunningSessions = true
        defer { isCheckingRunningSessions = false }
        let report = await registry.runningReport()
        runningSessions = report.sessions
        uncheckedMachines = report.unchecked
        runningSessionsCheckedAt = .now
    }

    /// How long the machines' answer stands before the library asks again by itself. Each ask
    /// can open a short SSH connection per host, and a Mac comes back to the front all day.
    static let runningSessionsMaxAge: Duration = .seconds(300)

    /// Asks the machines what runs on them as the library appears and as the app comes back,
    /// unless they answered within `runningSessionsMaxAge`. Until 2026-10-09 only Active asked,
    /// so the sidebar's count said 0 at every launch: *"the active count is always 0 to start.
    /// once you go in it updates to 15"* (owner, on the iPhone).
    func refreshRunningSessionsIfDue(now: ContinuousClock.Instant = .now) async {
        if let checked = runningSessionsCheckedAt, now - checked < Self.runningSessionsMaxAge { return }
        await refreshRunningSessions()
    }

    /// The services connected right now, for the library's green dots. Read in a view body, for
    /// the same reason as `activeMachines()`.
    func connectedEndpoints() -> Set<EndpointID> {
        Set(registry.openSessions().flatMap(\.connectedEndpointIDs))
    }

    /// How many sessions Active lists, for the sidebar row: those open here and those running on
    /// the machines, as last asked (W6) — the badge read 0 while fourteen sessions ran
    /// (2026-10-08). Counting asks nothing; the library asks as it appears
    /// (`refreshRunningSessionsIfDue`). Zero when there are none: *"Active needs a 0
    /// like the others when nothing is connected"* (2026-09-22) — Favorites and Workgroups say
    /// 0, and a row that says nothing looks like a row that has not counted.
    func activeSessionCount() -> Int {
        activeMachines().reduce(0) { $0 + $1.sessions.count + $1.running.count }
    }

    /// The ⚡'s destination.
    func showActiveConnections() { showPanel(Self.activePanelID) }

    /// The panel, seated in the Library section by its `sectionTitle`.
    func activeConnectionsPanel() -> GlassLibraryPanel {
        let model = self
        return GlassLibraryPanel(
            id: Self.activePanelID,
            sectionTitle: GlassLibraryPanel.librarySectionTitle,
            title: "Active",
            symbolName: "bolt.fill",
            count: model.activeSessionCount(),
            results: { GlassActiveConnectionsList(model: model) },
            detail: { GlassActiveConnectionsDetail(model: model) })
    }
}

// MARK: - Several at once (W13)

/// What Open does with the running sessions chosen: which open together, and which are left out
/// and why. Pure, so the choice is tested without a screen.
struct GlassOpenTogetherPlan {
    /// Opened together, in list order: one new window, a tab each.
    private(set) var opening: [GlassRunningSession] = []
    /// Shown in a window here already (W6): left out, where they are. A second client would
    /// mirror that window, and choosing one alone brings it forward.
    private(set) var alreadyOpen: [GlassRunningSession] = []
    /// From a capability that opens its sessions one at a time: left out, and said so.
    private(set) var oneAtATime: [GlassRunningSession] = []

    init(_ chosen: [GlassRunningSession]) {
        for session in chosen {
            if session.isOpenHere {
                alreadyOpen.append(session)
            } else if session.attachment != nil {
                opening.append(session)
            } else {
                oneAtATime.append(session)
            }
        }
    }

    /// What to say after opening, when some could not open together.
    var note: GlassActiveNotice? {
        guard !oneAtATime.isEmpty else { return nil }
        let names = oneAtATime.map(\.title).joined(separator: ", ")
        return GlassActiveNotice(title: "Only Terminal Sessions Open Together",
                                 message: "\(names) didn't open. Open \(oneAtATime.count == 1 ? "it" : "each") on its own.")
    }
}

/// Something Active says after acting on the chosen sessions.
struct GlassActiveNotice: Equatable {
    let title: String
    let message: String
}

extension GlassShellModel {
    /// Opens running sessions together: one new window holding them, a tab each, in the order
    /// given (W13). Each capability is asked once, with all of its own — never each row's `open`,
    /// which makes a window apiece. Those opened leave the list at once, as one opened alone does;
    /// those open here already, and those that open only alone, are left as they are.
    @discardableResult
    func openTogether(_ sessions: [GlassRunningSession]) -> GlassOpenTogetherPlan {
        let plan = GlassOpenTogetherPlan(sessions)
        guard !plan.opening.isEmpty else { return plan }
        let opened = Set(plan.opening.map(\.id))
        runningSessions.removeAll { opened.contains($0.id) }
        registry.openRunningSessions(plan.opening.compactMap(\.attachment))
        Task {
            try? await Task.sleep(for: .seconds(3))
            await refreshRunningSessions()
        }
        return plan
    }

    /// Ends each session on its machine, one after another — a probe connection apiece where no
    /// terminal is open there, and several at once could trip a server's limit on new ones — then
    /// asks the machines again. Returns what could not be ended, in plain words.
    func end(_ sessions: [GlassRunningSession]) async -> [String] {
        var failures: [String] = []
        for session in sessions {
            do {
                try await session.end()
            } catch {
                failures.append("\(session.title): \(error.localizedDescription)")
            }
        }
        await refreshRunningSessions()
        return failures
    }
}

/// The running sessions chosen in Active (W13): ⌘-click and ⇧-click on a Mac, as in W8's tab
/// sidebar; Select, then taps, on iPhone, iPad and Vision Pro, as in Mail and Files. Held by the
/// list; the model opens and ends.
@MainActor @Observable
final class GlassActiveSelection {
    /// The chosen rows, by `GlassRunningSession.id`.
    private(set) var ids: Set<String> = []
    /// Selection mode, where there is one: Select was chosen and a tap chooses. Leaving it
    /// chooses nothing. The Mac has none.
    var isSelecting = false {
        didSet { if !isSelecting { ids = [] } }
    }
    /// End asks once, for all of them.
    var isConfirmingEnd = false
    /// What could not be ended or opened together, said afterwards.
    var notice: GlassActiveNotice?

    /// The chosen sessions still listed, in the order Active lists them.
    func chosen(in machines: [GlassActiveMachine]) -> [GlassRunningSession] {
        machines.flatMap(\.running).filter { ids.contains($0.id) }
    }

    /// The list's selection changed. A plain click — one row, nothing held, not in selection mode
    /// — opens that row at once, as a tap always has, and leaves nothing chosen: the row to open
    /// is returned. Otherwise the rows are chosen.
    func listSelected(_ newIDs: Set<String>, plainClick: Bool,
                      in machines: [GlassActiveMachine]) -> GlassRunningSession? {
        let listed = machines.flatMap(\.running)
        let selected = newIDs.filter { id in listed.contains { $0.id == id } }
        guard plainClick, !isSelecting, selected.count == 1, let row = listed.first(where: { selected.contains($0.id) }) else {
            ids = selected
            return nil
        }
        ids = []
        return row
    }

    /// Open N in New Window: the chosen sessions open together and the choice ends.
    @discardableResult
    func openChosen(in model: GlassShellModel) -> GlassOpenTogetherPlan {
        let plan = model.openTogether(chosen(in: model.activeMachines()))
        finish()
        notice = plan.note
        return plan
    }

    /// End N: asks once, for all of them; `endChosen` ends each once it is answered.
    func askToEnd() {
        isConfirmingEnd = !ids.isEmpty
    }

    /// Ends each chosen session. The choice ends first: they are on their way out.
    func endChosen(in model: GlassShellModel) async {
        let sessions = chosen(in: model.activeMachines())
        finish()
        let failures = await model.end(sessions)
        guard !failures.isEmpty else { return }
        notice = GlassActiveNotice(title: failures.count == 1 ? "Couldn't End a Session" : "Couldn't End \(failures.count) Sessions",
                                   message: failures.joined(separator: "\n"))
    }

    /// Nothing chosen, and out of selection mode.
    func finish() {
        ids = []
        isSelecting = false
        isConfirmingEnd = false
    }

    // MARK: Words

    /// Where several open: a new window on a Mac and Vision Pro. On iPhone and iPad a terminal
    /// takes the library's place rather than opening a window, so they open together there.
    static func openTitle(count: Int) -> String {
        #if os(iOS)
        count > 1 ? "Open \(count) Together" : "Open"
        #else
        count > 1 ? "Open \(count) in New Window" : "Open in New Window"
        #endif
    }

    static let openHelp = "Opens the chosen sessions in one new window, a tab each. Sessions open here already stay where they are."

    static func endTitle(count: Int) -> String {
        count > 1 ? "End \(count) Sessions…" : "End Session…"
    }

    /// End's question, plainly: one session by name, as its own row asks; several by number.
    static func endQuestion(for chosen: [GlassRunningSession]) -> (title: String, message: String, button: String) {
        guard chosen.count > 1 else {
            return ("End \(chosen.first?.title ?? "the Session")?", "Everything running in it stops, on every device.", "End Session")
        }
        return ("End \(chosen.count) sessions?", "What runs in them stops, on every device.", "End \(chosen.count) Sessions")
    }
}

/// The results column: each machine a disclosure over its live sessions.
struct GlassActiveConnectionsList: View {
    let model: GlassShellModel
    @State private var collapsed: Set<String> = []
    /// The running sessions chosen to open together or end (W13).
    @State private var selection = GlassActiveSelection()

    var body: some View {
        let machines = model.activeMachines()
        let chosen = selection.chosen(in: machines)
        List(selection: listSelection(machines)) {
            if machines.isEmpty {
                ContentUnavailableView("Nothing Is Open",
                                       systemImage: "bolt.slash",
                                       description: Text("Connect to a machine and it appears here while the session is live."))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
            ForEach(machines) { machine in
                machineGroup(machine, chosen: chosen)
            }
        }
        .glassSpatialList()
        #if !os(macOS)
        .environment(\.editMode, editMode)
        #endif
        .navigationTitle("Active")
        .accessibilityIdentifier("active-connections")
        .task { await model.refreshRunningSessions() }
        .refreshable { await model.refreshRunningSessions() }
        .toolbar { selectionToolbar(machines: machines, chosen: chosen) }
        .toolbar {
            ToolbarItem {
                if model.isCheckingRunningSessions {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Checking machines for running sessions")
                } else {
                    Button("Check Machines", systemImage: "arrow.clockwise") {
                        Task { await model.refreshRunningSessions() }
                    }
                    .help("Look for sessions running on your machines")
                }
            }
        }
        .modifier(GlassActiveSelectionPrompts(model: model, selection: selection, chosen: chosen))
    }

    /// One machine: a disclosure over its live sessions.
    @ViewBuilder
    private func machineGroup(_ machine: GlassActiveMachine, chosen: [GlassRunningSession]) -> some View {
        // A disclosure per machine, open by default: the point of coming here is to see
        // what is live, not to open folders first. Collapsing is remembered for the sheet.
        DisclosureGroup(isExpanded: Binding(
            get: { !collapsed.contains(machine.id) },
            set: { expanded in if expanded { collapsed.remove(machine.id) } else { collapsed.insert(machine.id) } }
        )) {
            ForEach(machine.sessions) { session in
                GlassActiveSessionRow(session: session) {
                    // A detached session is still running on its machine: list it there.
                    // The client takes a moment to leave, so ask once it has.
                    guard session.closeTitle != "Close" else { return }
                    try? await Task.sleep(for: .seconds(1))
                    await model.refreshRunningSessions()
                }
                // Open here already: nothing to open together (W13). Choosing one switches to it.
                .selectionDisabled()
                .disabled(selection.isSelecting)
            }
            ForEach(machine.running) { session in
                GlassRunningSessionRow(session: session,
                                       opensOnTap: opensOnTap,
                                       batch: batchActions(for: session, chosen: chosen),
                                       open: { model.open(session, takingOver: $0) },
                                       didEnd: { await model.refreshRunningSessions() })
                    .tag(GlassActiveRowTag(sessionID: session.id))
            }
            if let reason = machine.notChecked {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .glassSpatialListRow()
                    .selectionDisabled()
                    .accessibilityIdentifier("active-not-checked-\(machine.id)")
            }
        } label: {
            HStack {
                Label(machine.name, systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Text(machine.sessions.count + machine.running.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("active-machine-\(machine.id)")
        }
    }

    // MARK: Choosing several (W13)

    /// A running row opens when tapped, as it always has — except on a Mac, where the list's own
    /// selection reports the click (so ⌘-click and ⇧-click choose), and in selection mode, where
    /// a tap chooses.
    private var opensOnTap: Bool {
        #if os(macOS)
        false
        #else
        !selection.isSelecting
        #endif
    }

    /// The list's own selection, as W8's tab sidebar uses it. On a Mac a plain click with nothing
    /// held opens the row at once and leaves nothing chosen; ⌘-click and ⇧-click choose. On the
    /// others it chooses only in selection mode: a tap otherwise reaches the row's button.
    private func listSelection(_ machines: [GlassActiveMachine]) -> Binding<Set<GlassActiveRowTag>> {
        Binding(
            get: { Set(selection.ids.map(GlassActiveRowTag.init)) },
            set: { tags in
                let ids = Set(tags.map(\.sessionID))
                #if os(macOS)
                if let row = selection.listSelected(ids, plainClick: Self.clickOpensRow(), in: machines) {
                    // After the click: it may bring a window forward.
                    Task { model.open(row) }
                }
                #else
                guard selection.isSelecting else { return }
                _ = selection.listSelected(ids, plainClick: false, in: machines)
                #endif
            })
    }

    #if os(macOS)
    /// The selection changed under a click with neither ⌘ nor ⇧ held: open the row. A key moving
    /// the selection, or a change with no event behind it, only chooses.
    private static func clickOpensRow() -> Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown?, .leftMouseUp?:
            return NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
        default:
            return false
        }
    }
    #else
    /// Selection mode is the system's edit mode, so the list draws its own checkmarks.
    private var editMode: Binding<EditMode> {
        Binding(get: { selection.isSelecting ? .active : .inactive },
                set: { selection.isSelecting = $0.isEditing })
    }
    #endif

    /// The chosen rows' actions on the menu of a row that is one of several chosen; nil otherwise,
    /// and the row offers its own.
    private func batchActions(for session: GlassRunningSession,
                              chosen: [GlassRunningSession]) -> GlassActiveBatchActions? {
        guard chosen.count > 1, chosen.contains(where: { $0.id == session.id }) else { return nil }
        let plan = GlassOpenTogetherPlan(chosen)
        return GlassActiveBatchActions(
            openTitle: GlassActiveSelection.openTitle(count: plan.opening.count),
            canOpen: !plan.opening.isEmpty,
            endTitle: GlassActiveSelection.endTitle(count: chosen.count),
            open: { selection.openChosen(in: model) },
            end: { selection.askToEnd() })
    }

    @ToolbarContentBuilder
    private func selectionToolbar(machines: [GlassActiveMachine], chosen: [GlassRunningSession]) -> some ToolbarContent {
        let plan = GlassOpenTogetherPlan(chosen)
        #if os(macOS)
        if !chosen.isEmpty {
            ToolbarItem {
                Button(GlassActiveSelection.openTitle(count: plan.opening.count), systemImage: "macwindow.badge.plus") {
                    selection.openChosen(in: model)
                }
                .disabled(plan.opening.isEmpty)
                .help(GlassActiveSelection.openHelp)
            }
        }
        #else
        ToolbarItem {
            Button(selection.isSelecting ? "Done" : "Select") {
                withAnimation { selection.isSelecting.toggle() }
            }
            .disabled(!selection.isSelecting && machines.allSatisfy(\.running.isEmpty))
            .accessibilityIdentifier("active-select")
        }
        if selection.isSelecting {
            ToolbarItemGroup(placement: .glassActiveSelectionActions) {
                Button(GlassActiveSelection.openTitle(count: plan.opening.count), systemImage: "macwindow.badge.plus") {
                    selection.openChosen(in: model)
                }
                .labelStyle(.titleOnly)
                .disabled(plan.opening.isEmpty)
                .accessibilityIdentifier("active-open-together")
                #if os(iOS)
                // Mail's bar: one action at each end. An ornament sizes to what it holds.
                Spacer()
                #endif
                Button(GlassActiveSelection.endTitle(count: chosen.count), systemImage: "stop.circle", role: .destructive) {
                    selection.askToEnd()
                }
                .labelStyle(.titleOnly)
                .disabled(chosen.isEmpty)
                .accessibilityIdentifier("active-end-together")
            }
        }
        #endif
    }
}

#if !os(macOS)
private extension ToolbarItemPlacement {
    /// Selection mode's actions: the system's bottom bar, an ornament on Vision Pro (D40).
    static var glassActiveSelectionActions: Self {
        #if os(visionOS)
        .bottomOrnament
        #else
        .bottomBar
        #endif
    }
}
#endif

/// A running row in the list's selection. Its own type, so nothing else in the list — a
/// machine's disclosure is tagged with its `String` id — can be chosen.
struct GlassActiveRowTag: Hashable {
    let sessionID: String
}

/// The question End asks for the chosen sessions, once for all of them, and what could not be
/// ended or opened together, afterwards.
private struct GlassActiveSelectionPrompts: ViewModifier {
    let model: GlassShellModel
    let selection: GlassActiveSelection
    let chosen: [GlassRunningSession]

    func body(content: Content) -> some View {
        let question = GlassActiveSelection.endQuestion(for: chosen)
        content
            .confirmationDialog(question.title, isPresented: Bindable(selection).isConfirmingEnd,
                                titleVisibility: .visible) {
                Button(question.button, role: .destructive) {
                    Task { await selection.endChosen(in: model) }
                }
            } message: {
                Text(question.message)
            }
            .alert(selection.notice?.title ?? "", isPresented: Binding(
                get: { selection.notice != nil },
                set: { if !$0 { selection.notice = nil } }
            )) {
            } message: {
                Text(selection.notice?.message ?? "")
            }
    }
}

/// The chosen rows' actions, offered on the menu of a row that is one of them (W13): right-click
/// one of several chosen, as in Finder, and the menu acts on all of them.
struct GlassActiveBatchActions {
    let openTitle: String
    let canOpen: Bool
    let endTitle: String
    let open: @MainActor () -> Void
    let end: @MainActor () -> Void
}

/// A session running on the machine (D44). Choosing it opens it here, or goes to it when a
/// window here already shows it (W6); Take Over also detaches whoever else has it; End stops it
/// on the machine.
struct GlassRunningSessionRow: View {
    let session: GlassRunningSession
    /// False where the list's selection takes the tap (W13): on a Mac, and in selection mode.
    var opensOnTap = true
    /// The chosen rows' actions, when this row is one of several chosen (W13).
    var batch: GlassActiveBatchActions? = nil
    /// Opens it here; `true` takes it over.
    let open: @MainActor (Bool) -> Void
    let didEnd: @MainActor () async -> Void
    @State private var confirmingEnd = false
    @State private var endFailure: String?

    /// Open here already: the row goes to it, as an open session's row does.
    private var openSymbol: String { session.isOpenHere ? "arrow.right.circle" : "arrow.down.right.circle" }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: session.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                Text(session.subtitle ?? (session.isAttachedElsewhere ? "Open elsewhere" : "Running on the machine"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: openSymbol)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    var body: some View {
        Group {
            if opensOnTap {
                Button {
                    open(false)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                // The list's selection takes the tap; VoiceOver's activate still opens it.
                content
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { open(false) }
            }
        }
        .glassSpatialListRow()
        .swipeActions(edge: .trailing) {
            Button("End", systemImage: "stop.circle", role: .destructive) { confirmingEnd = true }
        }
        .contextMenu {
            if let batch {
                Button(batch.openTitle, systemImage: "macwindow.badge.plus") { batch.open() }
                    .disabled(!batch.canOpen)
                Button(batch.endTitle, systemImage: "stop.circle", role: .destructive) { batch.end() }
            } else {
                if session.isOpenHere {
                    Button("Switch To", systemImage: openSymbol) { open(false) }
                } else {
                    Button("Open Here", systemImage: openSymbol) { open(false) }
                }
                // Taking over a session open here would detach this app's own window from it.
                if session.isAttachedElsewhere && !session.isOpenHere {
                    Button("Take Over", systemImage: "arrow.down.right.and.arrow.up.left") { open(true) }
                }
                Button("End Session…", systemImage: "stop.circle", role: .destructive) { confirmingEnd = true }
            }
        }
        .confirmationDialog("End \(session.title)?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive) {
                Task {
                    do { try await session.end() } catch { endFailure = error.localizedDescription }
                    await didEnd()
                }
            }
        } message: {
            Text("Everything running in it stops, on every device.")
        }
        .alert("Couldn't End the Session", isPresented: Binding(get: { endFailure != nil }, set: { if !$0 { endFailure = nil } })) {
        } message: {
            Text(endFailure ?? "")
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(session.isOpenHere ? "Switches to this session" : "Opens this session here")
        .accessibilityIdentifier("active-running-\(session.id)")
    }
}

/// One live session. Choosing it switches to it; the swipe ends it.
struct GlassActiveSessionRow: View {
    let session: GlassOpenSession
    var didClose: @MainActor () async -> Void = {}

    private func close() {
        session.close()
        Task { await didClose() }
    }

    var body: some View {
        Button {
            session.activate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.symbolName)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                    if let subtitle = session.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A button row in a list is highlighted by the list; ours nested inside it (2026-09-28).
        .glassSpatialListRow()
        .swipeActions(edge: .trailing) {
            Button(session.closeTitle, systemImage: session.closeSymbolName, role: .destructive) { close() }
        }
        .contextMenu {
            Button("Switch To", systemImage: "arrow.right.circle") { session.activate() }
            Button(session.closeTitle, systemImage: session.closeSymbolName, role: .destructive) { close() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.subtitle ?? "")")
        .accessibilityHint("Switches to this session")
        .accessibilityIdentifier("active-session-\(session.id)")
    }
}

/// The detail column on a wide layout. Rows switch rather than select, so there is nothing to
/// detail; this says what the column is for instead of sitting blank.
struct GlassActiveConnectionsDetail: View {
    /// How a row is closed where this is read: a Mac mouse cannot swipe. And how several running
    /// sessions are chosen there (W13).
    static var closeHint: String {
        #if os(macOS)
        "Choose a session to switch to it. Right-click one to close it. ⌘-click running sessions to open several in one window."
        #else
        "Choose a session to switch to it. Swipe one to close it. Choose Select to open several running sessions together."
        #endif
    }

    let model: GlassShellModel

    var body: some View {
        let count = model.activeSessionCount()
        ContentUnavailableView(
            count == 0 ? "Nothing Is Open" : "\(count) live",
            systemImage: "bolt.fill",
            description: Text(count == 0
                              ? "Connect to a machine and it appears under Active while the session is live."
                              : Self.closeHint))
    }
}

// MARK: - The bolt

public extension View {
    /// On the Mac, ends this view's toolbar with the ⚡ from the environment's route. **Apply it
    /// directly before the view's own `.toolbar`**: SwiftUI orders the inner modifier's items
    /// last, after the view's flexible spacer and its buttons. A window whose panes split their
    /// toolbar with a spacer — the database's — drew a ⚡ added at window level on the left,
    /// beside Back (2026-10-05, measured with an off-screen toolbar probe). Elsewhere: nothing.
    ///
    /// `isActive`: a window that keeps several panes alive and shows one must add the ⚡ from the
    /// shown pane only, as it adds that pane's own buttons, or there is a ⚡ per open tab.
    @ViewBuilder func glassActiveConnectionsLastInToolbar(isActive: Bool = true) -> some View {
        #if os(macOS)
        toolbar { if isActive { GlassActiveConnectionsToolbarContent() } }
        #else
        self
        #endif
    }
}

/// The ⚡ in a top toolbar: one control, one meaning, everywhere.
///
/// On a device with windows it brings the library window forward and opens Active there. On a
/// phone the session is dismissed first — `dismissCurrent`, the same closure the chrome uses for
/// its own back control — and the library, now on screen, opens Active. Nil `show` means the
/// composition root offered no destination, and the bolt is not drawn rather than drawn dead.
/// Where the ⚡ goes and what it dismisses first, handed down to the views whose toolbars end
/// with it (`glassActiveConnectionsLastInToolbar`).
public struct GlassActiveConnectionsRoute {
    public let show: GlassShowActiveConnections
    public let dismissCurrent: (@MainActor () -> Void)?
    public init(show: @escaping GlassShowActiveConnections, dismissCurrent: (@MainActor () -> Void)? = nil) {
        self.show = show
        self.dismissCurrent = dismissCurrent
    }
}

public extension EnvironmentValues {
    @Entry var glassActiveConnectionsRoute: GlassActiveConnectionsRoute? = nil
}

/// The ⚡ as toolbar content. Given no action, it takes the route from the environment.
public struct GlassActiveConnectionsToolbarContent: ToolbarContent {
    private let explicitShow: GlassShowActiveConnections?
    private let explicitDismiss: (@MainActor () -> Void)?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.glassActiveConnectionsRoute) private var route

    public init(show: GlassShowActiveConnections?, dismissCurrent: (@MainActor () -> Void)? = nil) {
        explicitShow = show
        explicitDismiss = dismissCurrent
    }

    /// From the environment's route.
    public init() {
        explicitShow = nil
        explicitDismiss = nil
    }

    private var show: GlassShowActiveConnections? { explicitShow ?? route?.show }
    private var dismissCurrent: (@MainActor () -> Void)? { explicitDismiss ?? route?.dismissCurrent }

    public var body: some ToolbarContent {
        if let show {
            ToolbarItem(placement: GlassActiveConnectionsToolbarModifier.placement) {
                GlassActiveConnectionsButton {
                    if GlassWindowPresentation.canOpenWindows {
                        openWindow.openConnections()
                    } else {
                        dismissCurrent?()
                    }
                    show()
                }
            }
        }
    }
}

public struct GlassActiveConnectionsToolbarModifier: ViewModifier {
    /// **Always the trailing edge** (2026-10-05). On the Mac `.primaryAction` is the *leading*
    /// edge — the database window drew the ⚡ beside its back button, on the other side from every
    /// other window's. `.automatic` is the trailing group there, after the window's own items;
    /// elsewhere `.primaryAction` is already trailing.
    public static var placement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .primaryAction
        #endif
    }

    private let show: GlassShowActiveConnections?
    private let dismissCurrent: (@MainActor () -> Void)?
    @Environment(\.openWindow) private var openWindow

    public init(show: GlassShowActiveConnections?, dismissCurrent: (@MainActor () -> Void)? = nil) {
        self.show = show
        self.dismissCurrent = dismissCurrent
    }

    public func body(content: Content) -> some View {
        content.toolbar { GlassActiveConnectionsToolbarContent(show: show, dismissCurrent: dismissCurrent) }
    }
}

/// The bolt itself, so the library's own toolbar can draw the same control without the
/// window-or-dismiss decision — it is already where the bolt goes.
public struct GlassActiveConnectionsButton: View {
    private let action: () -> Void
    @Environment(\.openWindow) private var openWindow

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button {
            #if os(visionOS)
            // Every bolt on the headset brings the one Connections window forward (a `Window`
            // scene there, so this reuses it) and opens Active in it. The desktop's control-bar
            // bolt only asked for Active, which did nothing while Connections was closed
            // (2026-09-29).
            openWindow.openConnections()
            #endif
            action()
        } label: {
            Label("Active Connections", systemImage: "bolt.fill")
        }
        .labelStyle(.iconOnly)
        .help("Active connections")
        .accessibilityIdentifier("active-connections-bolt")
    }
}

public extension View {
    /// See `GlassActiveConnectionsToolbarModifier`.
    func glassActiveConnectionsToolbar(show: GlassShowActiveConnections?,
                                       dismissCurrent: (@MainActor () -> Void)? = nil) -> some View {
        modifier(GlassActiveConnectionsToolbarModifier(show: show, dismissCurrent: dismissCurrent))
    }
}
