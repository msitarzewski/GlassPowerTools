//
//  TerminalWorkgroupsView.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's Workgroups library mode: the Workgroups panel in the library's sidebar, which is
//  its only home (the separate Workgroups window went on 2026-10-08). List, detail, table and plan
//  rows are verbatim from ConnectionManagerView
//  (lines 840-998, 1136-1408); launching goes through the runtime so the connect flow stays the
//  one place that confirms legacy algorithms, prompts for trust and asks for passwords.
//

import SwiftUI
import GlassConnectionUI

enum ConnectionWorkgroupSelection: Hashable {
    case live(UUID)
    case preset(UUID)
}

/// The state the Workgroups results list and its detail pane share.
///
/// It lives outside both views because they now occupy two different columns of the library's
/// split view, and a `@State` in one cannot be read by the other. glas.sh had the same arrangement
/// for the same reason: `ConnectionManagerView` — the parent of both halves — owned
/// `selectedWorkgroupSelection`, not the results list.
@MainActor @Observable
final class TerminalWorkgroupsModel {
    var selection: ConnectionWorkgroupSelection?
    var searchQuery: String = ""
    var editorContext: WorkgroupEditorContext?
    var failureMessage: String?
    /// A Workgroup waiting for its deletion to be confirmed; deleting from the menu used to be
    /// immediate, with nothing to undo it.
    var pendingDeletion: LayoutPreset?

    init() {}
}

struct TerminalWorkgroupsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(GlassTerminalRuntime.self) private var runtime
    #if os(iOS)
    @Environment(IOSAppRouter.self) private var iOSRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var serverManager: ServerManager { sessionManager.serverManager }
    /// Which column this instance is drawing. The library renders `.results` and `.detail` into
    /// two of its columns over one model.
    enum Presentation { case results, detail }
    let presentation: Presentation
    @Bindable var model: TerminalWorkgroupsModel
    @FocusState private var searchIsFocused: Bool

    init(presentation: Presentation, model: TerminalWorkgroupsModel) {
        self.presentation = presentation
        self.model = model
    }

    private var showsExplicitSearchAction: Bool {
        #if os(visionOS)
        true
        #elseif os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    private var connectionLibrary: ConnectionLibraryProjection {
        ConnectionLibraryProjection(
            servers: serverManager.servers,
            workgroups: settingsManager.layoutPresets,
            networkIsConfigured: runtime.tailscaleIsConfigured
        )
    }

    var body: some View {
        content
            // The editor sheet, the failure alert and the pruning of a selection whose workgroup
            // has gone are attached once, to the instance that owns the results — never to both
            // columns, or the sheet presents twice and the alert fights itself. Carried on a
            // zero-size background the way the library carries its own presentation anchor.
            .background { if presentation == .results { sharedPresentations } }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .results:
            workgroupResults(connectionLibrary: connectionLibrary)
        case .detail:
            workgroupDetail(connectionLibrary: connectionLibrary)
        }
    }

    @ViewBuilder
    fileprivate var sharedPresentations: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sheet(item: $model.editorContext) { context in
            WorkgroupEditorView(
                context: context,
                servers: serverManager.servers,
                existing: settingsManager.layoutPresets
            ) { preset in
                settingsManager.upsertLayoutPreset(preset)
            }
        }
        .confirmationDialog("Delete Workgroup?", isPresented: Binding(
            get: { model.pendingDeletion != nil },
            set: { if !$0 { model.pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: model.pendingDeletion) { preset in
            Button("Delete", role: .destructive) {
                settingsManager.deleteLayoutPreset(preset)
                model.pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: { preset in
            Text("\(preset.name) and its layout are removed from this device. The connections in it are not affected.")
        }
        .alert("Workgroups", isPresented: Binding(
            get: { model.failureMessage != nil },
            set: { if !$0 { model.failureMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.failureMessage ?? "")
        }
        .onChange(of: settingsManager.layoutPresets.map(\.id)) { _, workgroupIDs in
            if case .preset(let selectedWorkgroupID) = model.selection,
               !workgroupIDs.contains(selectedWorkgroupID) {
                model.selection = nil
            }
        }
        #if os(iOS)
        .onChange(of: sessionManager.workgroups.map(\.id)) { _, workgroupIDs in
            if case .live(let selectedWorkgroupID) = model.selection,
               !workgroupIDs.contains(selectedWorkgroupID) {
                model.selection = nil
            }
        }
        #endif
        .task { serverManager.loadServersIfNeeded() }
    }

    /// What a workgroup's row says it holds: "1 tab", "5 tabs", "2 live tabs".
    static func tabCount(_ count: Int, live: Bool = false) -> String {
        "\(count) \(live ? "live " : "")\(count == 1 ? "tab" : "tabs")"
    }

    /// The tabs a saved workgroup opens: its Mac layout's tabs when it has one, else its sessions —
    /// the figure the detail already shows.
    static func tabTotal(_ preset: LayoutPreset) -> Int {
        preset.workspaceLayout?.tabs.count ?? preset.sessionIntents.count
    }

    @ViewBuilder
    private func workgroupResults(
        connectionLibrary: ConnectionLibraryProjection
    ) -> some View {
        let presets = connectionLibrary.workgroups(matching: model.searchQuery)
        let liveWorkgroups = matchingLiveWorkgroups(model.searchQuery)
        let visibleSelections = liveWorkgroups.map { ConnectionWorkgroupSelection.live($0.id) }
            + presets.map { ConnectionWorkgroupSelection.preset($0.id) }
        return List(selection: $model.selection) {
            if liveWorkgroups.isEmpty, presets.isEmpty {
                ContentUnavailableView(
                    model.searchQuery.isEmpty ? "No Workgroups" : "No Matching Workgroups",
                    systemImage: "rectangle.stack",
                    description: Text(
                        model.searchQuery.isEmpty
                            ? "Create a reusable command-per-tab terminal workspace."
                            : "Try a different search."
                        )
                )
            }

            #if os(iOS)
            if !liveWorkgroups.isEmpty {
                Section("Live Terminals") {
                    ForEach(Array(liveWorkgroups.reversed())) { workgroup in
                        // The library's row, as Connections draws it (2026-10-07).
                        GlassLibraryConnectionRow(name: workgroup.name,
                                                  subtitle: Self.tabCount(liveSessions(in: workgroup).count, live: true),
                                                  color: workgroup.colorTag.color) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                        .tag(ConnectionWorkgroupSelection.live(workgroup.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selection = .live(workgroup.id)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(workgroup.name), \(liveSessions(in: workgroup).count) live tabs"
                        )
                        .accessibilityHint("Select to inspect this live terminal workgroup")
                        .accessibilityIdentifier(
                            "connection-library-live-workgroup-\(workgroup.id.uuidString.lowercased())"
                        )
                        .contextMenu {
                            Button("Resume", systemImage: "arrow.uturn.backward.circle") {
                                resumeLiveWorkgroup(workgroup.id)
                            }
                        }
                    }
                }
            }
            #endif

            if !presets.isEmpty {
                Section("Saved Workgroups") {
                    ForEach(presets) { preset in
                    // The library's row, as Connections draws it: the same height, the name in the
                    // same place, the colour after the name (2026-10-07). The count is the one the
                    // detail shows — a Mac workgroup's tabs, else its sessions.
                    GlassLibraryConnectionRow(name: preset.name,
                                              subtitle: Self.tabCount(Self.tabTotal(preset)),
                                              color: preset.colorTag.color)
                    .tag(ConnectionWorkgroupSelection.preset(preset.id))
                    .accessibilityLabel(
                        "\(preset.name), \(Self.tabCount(Self.tabTotal(preset)))"
                    )
                    .accessibilityHint("Select to show workgroup details")
                    .accessibilityIdentifier(
                        "connection-library-workgroup-\(preset.id.uuidString.lowercased())"
                    )
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selection = .preset(preset.id)
                    }
                    #endif
                    .contextMenu {
                        Button("Open", systemImage: "rectangle.stack") {
                            runtime.requestOpenWorkgroup(preset.id)
                        }
                        Button("Edit", systemImage: "pencil") {
                            model.editorContext = .edit(preset)
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            model.editorContext = .duplicate(preset)
                        }
                        Divider()
                        Button("Delete…", systemImage: "trash", role: .destructive) {
                            model.pendingDeletion = preset
                        }
                    }
                    // Icons in the menu on the Mac too, as every machine menu has (2026-10-04).
                    .labelStyle(.titleAndIcon)
                }
                }
            }
        }
        .accessibilityIdentifier("connection-library-results-workgroups")
        .onChange(of: visibleSelections) { _, visibleSelections in
            if let current = model.selection, !visibleSelections.contains(current) {
                model.selection = nil
            }
        }
        #if os(visionOS)
        // The column's header on the headset, with the search field the bar's search button
        // used to reveal, and the bar's two actions (W33): there is no bar there.
        .glassSpatialColumn("Workgroups",
                            search: GlassSpatialSearch(text: $model.searchQuery, prompt: "Search workgroups...",
                                                       accessibilityIdentifier: "connection-library-search")) {
            workgroupActions
        }
        #else
        .navigationTitle("Workgroups")
        .searchable(text: $model.searchQuery, prompt: "Search workgroups...")
        .searchFocused($searchIsFocused)
        .toolbar {
            #if !os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                if showsExplicitSearchAction {
                    Button {
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                    .accessibilityIdentifier("connection-library-search")
                }
                workgroupActions
            }
            #endif
        }
        #endif
    }

    /// Save the open sessions as a workgroup, and a new one: the bar's actions off the Mac.
    @ViewBuilder private var workgroupActions: some View {
        #if !os(macOS)
        Button {
            editCurrentSessionsAsWorkgroup()
        } label: {
            Image(systemName: "rectangle.stack.badge.plus")
        }
        .disabled(currentSavedSessionIntents.isEmpty)
        .accessibilityLabel("Save current SSH sessions as workgroup")
        .accessibilityIdentifier("connection-library-save-current-workgroup")

        Button {
            model.editorContext = .new()
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("New workgroup")
        .accessibilityIdentifier("connection-library-add-workgroup")
        #endif
    }

    @ViewBuilder

    private func workgroupDetail(
        connectionLibrary: ConnectionLibraryProjection
    ) -> some View {
        if let workgroup = selectedLiveWorkgroup {
            let sessions = liveSessions(in: workgroup)
            VStack(spacing: 0) {
                List {
                    Section("Live Workgroup") {
                        LabeledContent("Name", value: workgroup.name)
                        LabeledContent("Live Tabs", value: "\(sessions.count)")
                    }
                    Section("Tabs") {
                        ForEach(sessions) { session in
                            let isSelected = session.id == workgroup.selectedSessionID
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.server.name)
                                        .font(.headline)
                                    Text("\(session.server.username)@\(session.server.host):\(session.server.port)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(session.state.displayName)
                                    .font(.caption)
                                    .foregroundStyle(session.state.color)
                            }
                        }
                    }
                }
                #if os(iOS)
                HStack {
                    Spacer()
                    Button("Resume Terminal", systemImage: "arrow.uturn.backward.circle") {
                        resumeLiveWorkgroup(workgroup.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "connection-library-resume-workgroup-\(workgroup.id.uuidString.lowercased())"
                    )
                }
                .labelStyle(.titleAndIcon)
                .padding()
                .background(.bar)
                #endif
            }
            .navigationTitle(workgroup.name)
            .accessibilityIdentifier(
                "connection-library-detail-live-workgroup-\(workgroup.id.uuidString.lowercased())"
            )
            // The column's header on the headset, where the bar's title was (W33).
            .glassSpatialColumn(workgroup.name)
        } else if let preset = selectedWorkgroup(in: connectionLibrary) {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.largeTitle)
                            .foregroundStyle(preset.colorTag.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preset.name)
                                .font(.title2.bold())
                                .textSelection(.enabled)
                            Text("\(Self.tabCount(Self.tabTotal(preset))) · \(preset.sessionIntents.count) terminals · \(preset.sessionIntents.filter { $0.startupCommand != nil }.count) startup commands")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                #if os(macOS)
                Section("Terminals") {
                    workgroupDetailTable(preset)
                }
                Section("Running terminals") {
                    let tabs = MacWorkspacePreviewRegistry.shared.tabs(for: preset.id)
                    if tabs.isEmpty {
                        Label("Not running — open this workgroup to start its terminals.", systemImage: "apple.terminal")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 520), spacing: 18)], spacing: 18) {
                            ForEach(tabs, id: \.workspaceID) { tab in
                                let statuses = (tab.state.root?.panes ?? []).map { tab.previewStatus(for: $0.id) }
                                VStack(alignment: .leading, spacing: 6) {
                                    MacWorkspacePreview(controller: tab)
                                    Text(tab.windowIdentity(servers: sessionManager.serverManager.servers).title)
                                        .font(.headline).lineLimit(1)
                                        .foregroundStyle(MacTerminalPreviewStatus.color(for: statuses))
                                        .help(statuses.joined(separator: " · "))
                                        .accessibilityHint(statuses.joined(separator: " · "))
                                }
                                .padding(10)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                #else
                ForEach(Array(preset.sessionIntents.enumerated()), id: \.offset) { index, intent in
                    Section {
                        workgroupIntentRow(intent, index: index, preset: preset)
                    } header: {
                        if index == 0 {
                            Text("Startup Plan")
                        }
                    } footer: {
                        if index == preset.sessionIntents.count - 1 {
                            Text("All terminals start when you open this Workgroup. Commands run independently, without waiting for another tab.")
                        }
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button("Edit", systemImage: "pencil") {
                        model.editorContext = .edit(preset)
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Edit Workgroup")
                    .accessibilityIdentifier("connection-library-edit-workgroup-\(preset.id.uuidString.lowercased())")
                    Spacer()
                    Button("Open Workgroup", systemImage: "rectangle.stack") {
                        runtime.requestOpenWorkgroup(preset.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .labelStyle(.titleAndIcon)
                    .keyboardShortcut(.defaultAction)
                    .help("Open Workgroup")
                    .accessibilityIdentifier(
                        "connection-library-open-workgroup-\(preset.id.uuidString.lowercased())"
                    )
                }
                .buttonStyle(.bordered)
                .padding()
                .background(.bar)
            }
            .navigationTitle(preset.name)
            .accessibilityIdentifier(
                "connection-library-detail-workgroup-\(preset.id.uuidString.lowercased())"
            )
            .glassSpatialColumn(preset.name)
        } else {
            ContentUnavailableView {
                Label("Select a Workgroup", systemImage: "rectangle.stack")
            } description: {
                Text("Workgroups open one configured command per terminal tab.")
            } actions: {
                Button("New Workgroup", systemImage: "plus") {
                    model.editorContext = .new()
                }
                .accessibilityIdentifier("connection-library-add-workgroup-empty-detail")
            }
            .accessibilityIdentifier("connection-library-detail-empty-workgroup")
            // A header with nothing to name, for the window's sidebar toggle (W33).
            .glassSpatialColumn("")
        }
    }

    #if os(macOS)

    private func workgroupDetailTable(_ preset: LayoutPreset) -> some View {
        let rows = preset.sessionIntents.map(WorkgroupTabDraft.init(intent:))
        return Table(rows) {
            TableColumn("Order") { row in
                Text("\((rows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1)").monospacedDigit()
            }.width(45)
            TableColumn("Label") { row in
                let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                Text(preset.sessionIntents[index].label ?? defaultIntentLabel(preset.sessionIntents[index]))
                    .lineLimit(1)
            }.width(min: 100, ideal: 140)
            TableColumn("Destination") { row in
                let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                Label(workgroupIntentDestination(preset.sessionIntents[index]),
                      systemImage: row.kind == .local ? "apple.terminal" : "network")
                    .lineLimit(1)
            }.width(min: 110, ideal: 180)
            TableColumn("Startup command") { row in
                Text(row.startupCommand.isEmpty ? "Interactive shell" : row.startupCommand)
                    .font(.body.monospaced()).lineLimit(1)
                    .help(row.startupCommand)
            }.width(min: 140, ideal: 220)
            TableColumn("Status") { row in
                let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                let statuses = MacWorkspacePreviewRegistry.shared.tabs(for: preset.id).flatMap { tab in
                    (tab.state.root?.panes ?? []).filter { $0.intent.sourceSessionIndex == index }
                        .map { tab.previewStatus(for: $0.id) }
                }
                Text(statuses.isEmpty ? "Not running" : statuses.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.width(min: 80, ideal: 100)
        }
        .frame(height: min(340, max(120, CGFloat(rows.count) * 32 + 32)))
        .accessibilityIdentifier("workgroup-detail-table")
    }
    #endif

    private func workgroupIntentRow(
        _ intent: LayoutPreset.SessionIntent, index: Int, preset: LayoutPreset
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(intent.label ?? defaultIntentLabel(intent))
                        .font(.headline)
                        #if !os(macOS)
                        .opacity(intent.kind == .local ? 0.55 : 1)
                        #endif
                    Label(workgroupIntentDestination(intent), systemImage: intent.kind == .local ? "apple.terminal" : "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let layout = preset.workspaceLayout,
                       let tabIndex = layout.tabs.firstIndex(where: { workgroupNode($0.root, contains: index) }) {
                        Text("Tab \(tabIndex + 1)\(layout.tabs[tabIndex].label.map { " · " + $0 } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if intent.kind == .local {
                VStack(alignment: .leading, spacing: 6) {
                    Label(intent.localDirectory ?? "App default working directory", systemImage: "folder")
                    Label(intent.localShell ?? "App default shell", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                #if !os(macOS)
                Label("Local terminals require macOS", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Use SSH connection…") { runtime.requestOpenWorkgroup(preset.id) }
                #endif
            }
            if let command = intent.startupCommand {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Startup command: \(command)")
            } else {
                Text("Interactive shell · No startup command")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workgroup-terminal-plan-\(index)")
    }

    private func workgroupIntentDestination(_ intent: LayoutPreset.SessionIntent) -> String {
        guard intent.kind == .ssh else { return "Local terminal" }
        guard let id = intent.serverID, let server = serverManager.server(for: id) else {
            return "Missing SSH connection — edit this Workgroup to choose a host"
        }
        return "\(server.username)@\(server.host):\(server.port)"
    }

    private func workgroupNode(_ node: LayoutPreset.WorkspaceLayout.Node, contains index: Int) -> Bool {
        switch node {
        case .session(let candidate): return candidate == index
        case let .split(_, _, first, second):
            return workgroupNode(first, contains: index) || workgroupNode(second, contains: index)
        }
    }

    @ViewBuilder

    private func selectedWorkgroup(
        in connectionLibrary: ConnectionLibraryProjection
    ) -> LayoutPreset? {
        guard case .preset(let selectedWorkgroupID) = model.selection else {
            return nil
        }
        return connectionLibrary.workgroups.first(where: { $0.id == selectedWorkgroupID })
    }

    private var selectedLiveWorkgroup: TerminalWorkgroup? {
        #if os(iOS)
        guard case .live(let selectedWorkgroupID) = model.selection else {
            return nil
        }
        return iOSRouter.liveWorkgroups(in: sessionManager).first {
            $0.id == selectedWorkgroupID
        }
        #else
        return nil
        #endif
    }

    private func liveSessions(in workgroup: TerminalWorkgroup) -> [TerminalSession] {
        workgroup.sessionIDs.compactMap { sessionManager.session(for: $0) }
    }

    private func matchingLiveWorkgroups(_ query: String) -> [TerminalWorkgroup] {
        #if os(iOS)
        let workgroups = iOSRouter.liveWorkgroups(in: sessionManager)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return workgroups }
        return workgroups.filter { workgroup in
            if workgroup.name.localizedCaseInsensitiveContains(normalizedQuery) {
                return true
            }
            return liveSessions(in: workgroup).contains { session in
                session.server.name.localizedCaseInsensitiveContains(normalizedQuery)
                    || session.server.host.localizedCaseInsensitiveContains(normalizedQuery)
                    || session.server.username.localizedCaseInsensitiveContains(normalizedQuery)
            }
        }
        #else
        return []
        #endif
    }

    private func defaultIntentLabel(_ intent: LayoutPreset.SessionIntent) -> String {
        if intent.kind == .local { return "Local Terminal" }
        guard let serverID = intent.serverID,
              let server = serverManager.server(for: serverID) else {
            return "Missing Connection"
        }
        return server.name
    }

    private var currentSavedSessionIntents: [LayoutPreset.SessionIntent] {
        Self.savedSessionIntents(of: sessionManager.sessions, servers: serverManager.servers)
    }

    /// The open terminals on saved servers as a workgroup's tabs, each with the tmux session it
    /// is in, so the workgroup reopens on them (W4b).
    static func savedSessionIntents(of sessions: [TerminalSession],
                                    servers: [ServerConfiguration]) -> [LayoutPreset.SessionIntent] {
        sessions.compactMap { session in
            guard session.purpose == .terminal,
                  servers.contains(where: { $0.id == session.server.id }) else { return nil }
            return LayoutPreset.SessionIntent(serverID: session.server.id, label: session.workgroupLabel,
                                              tmuxSession: session.usesTmux ? session.tmuxSessionName : nil)
        }
    }

    private func editCurrentSessionsAsWorkgroup() {
        let intents = currentSavedSessionIntents
        guard !intents.isEmpty else {
            model.failureMessage = "No open sessions use a saved SSH connection."
            return
        }
        model.editorContext = .new(
            name: "Workgroup (\(intents.count) tabs)",
            sessionIntents: intents
        )
    }

    #if os(iOS)
    private func resumeLiveWorkgroup(_ workgroupID: UUID) {
        guard iOSRouter.resumeTerminal(workgroupID: workgroupID, in: sessionManager) else {
            model.failureMessage = "The terminal workgroup is no longer available."
            return
        }
    }
    #endif
}
