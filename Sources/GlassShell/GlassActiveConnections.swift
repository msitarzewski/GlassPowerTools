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

import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// "Take me to the live connections." Supplied to each capability's runtime by the composition
/// root, because the library is the shell's and a capability must not hold the shell.
public typealias GlassShowActiveConnections = @MainActor () -> Void

/// One machine's live sessions.
public struct GlassActiveMachine: Identifiable {
    /// The canonical host id, or a stand-in for sessions no machine in the library owns.
    public let id: String
    public let name: String
    public let sessions: [GlassOpenSession]
    /// Running on the machine and not shown here (D44): detached, or open on another device.
    public var running: [GlassRunningSession] = []
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
        for session in runningSessions {
            guard let owner = host(owningEndpoint: session.endpointID) else { continue }
            let key = owner.id.rawValue.uuidString
            if let index = machines.firstIndex(where: { $0.id == key }) {
                machines[index].running.append(session)
            } else {
                machines.append(GlassActiveMachine(id: key, name: owner.displayName, sessions: [], running: [session]))
            }
        }
        return machines
    }

    /// Asks every capability what is running on its hosts (D44). One pass at a time.
    func refreshRunningSessions() async {
        guard !isCheckingRunningSessions else { return }
        isCheckingRunningSessions = true
        defer { isCheckingRunningSessions = false }
        runningSessions = await registry.runningSessions()
    }

    /// How many sessions are live, for the sidebar row. Zero when there are none: *"Active needs
    /// a 0 like the others when nothing is connected"* (2026-09-22) — Favorites and Workgroups
    /// say 0, and a row that says nothing looks like a row that has not counted.
    func activeSessionCount() -> Int {
        registry.openSessions().count
    }

    /// The ⚡'s destination.
    func showActiveConnections() { panelToShow = Self.activePanelID }

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

/// The results column: each machine a disclosure over its live sessions.
struct GlassActiveConnectionsList: View {
    let model: GlassShellModel
    @State private var collapsed: Set<String> = []

    var body: some View {
        let machines = model.activeMachines()
        List {
            if machines.isEmpty {
                ContentUnavailableView("Nothing Is Open",
                                       systemImage: "bolt.slash",
                                       description: Text("Connect to a machine and it appears here while the session is live."))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(machines) { machine in
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
                    }
                    ForEach(machine.running) { session in
                        GlassRunningSessionRow(session: session) { await model.refreshRunningSessions() }
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
        }
        .glassSpatialList()
        .navigationTitle("Active")
        .accessibilityIdentifier("active-connections")
        .task { await model.refreshRunningSessions() }
        .refreshable { await model.refreshRunningSessions() }
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
    }
}

/// A session running on the machine that this device is not showing (D44). Choosing it opens
/// it here; Take Over also detaches whoever else has it; End stops it on the machine.
struct GlassRunningSessionRow: View {
    let session: GlassRunningSession
    let didEnd: @MainActor () async -> Void
    @State private var confirmingEnd = false
    @State private var endFailure: String?

    var body: some View {
        Button {
            session.open()
        } label: {
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
                Image(systemName: "arrow.down.right.circle")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassSpatialListRow()
        .swipeActions(edge: .trailing) {
            Button("End", systemImage: "stop.circle", role: .destructive) { confirmingEnd = true }
        }
        .contextMenu {
            Button("Open Here", systemImage: "arrow.down.right.circle") { session.open() }
            if session.isAttachedElsewhere {
                Button("Take Over", systemImage: "arrow.down.right.and.arrow.up.left") { session.takeOver() }
            }
            Button("End Session…", systemImage: "stop.circle", role: .destructive) { confirmingEnd = true }
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
        .accessibilityHint("Opens this session here")
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
    /// How a row is closed where this is read: a Mac mouse cannot swipe.
    static var closeHint: String {
        #if os(macOS)
        "Choose a session to switch to it. Right-click one to close it."
        #else
        "Choose a session to switch to it. Swipe one to close it."
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

/// The ⚡ in a top toolbar: one control, one meaning, everywhere.
///
/// On a device with windows it brings the library window forward and opens Active there. On a
/// phone the session is dismissed first — `dismissCurrent`, the same closure the chrome uses for
/// its own back control — and the library, now on screen, opens Active. Nil `show` means the
/// composition root offered no destination, and the bolt is not drawn rather than drawn dead.
public struct GlassActiveConnectionsToolbarModifier: ViewModifier {
    private let show: GlassShowActiveConnections?
    private let dismissCurrent: (@MainActor () -> Void)?
    @Environment(\.openWindow) private var openWindow

    public init(show: GlassShowActiveConnections?, dismissCurrent: (@MainActor () -> Void)? = nil) {
        self.show = show
        self.dismissCurrent = dismissCurrent
    }

    public func body(content: Content) -> some View {
        content.toolbar {
            if let show {
                ToolbarItem(placement: .primaryAction) {
                    GlassActiveConnectionsButton {
                        if GlassWindowPresentation.canOpenWindows {
                            openWindow(id: "main")
                        } else {
                            dismissCurrent?()
                        }
                        show()
                    }
                }
            }
        }
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
            openWindow(id: "main")
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
