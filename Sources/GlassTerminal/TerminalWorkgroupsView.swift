//
//  TerminalWorkgroupsView.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's Workgroups library mode, re-homed as its own surface now that the shell owns the
//  host library. List, detail, table and plan rows are verbatim from ConnectionManagerView
//  (lines 840-998, 1136-1408); launching goes through the runtime so the connect flow stays the
//  one place that confirms legacy algorithms, prompts for trust and asks for passwords.
//

import SwiftUI

enum ConnectionWorkgroupSelection: Hashable {
    case live(UUID)
    case preset(UUID)
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
    @State private var selectedWorkgroupSelection: ConnectionWorkgroupSelection?
    @State private var searchQuery: String = ""
    @FocusState private var searchIsFocused: Bool
    @State private var workgroupEditorContext: WorkgroupEditorContext?
    @State private var connectionFailureMessage: String?

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
        NavigationSplitView {
            workgroupResults(connectionLibrary: connectionLibrary)
        } detail: {
            workgroupDetail(connectionLibrary: connectionLibrary)
        }
        .sheet(item: $workgroupEditorContext) { context in
            WorkgroupEditorView(
                context: context,
                servers: serverManager.servers
            ) { preset in
                settingsManager.upsertLayoutPreset(preset)
            }
        }
        .alert("Workgroups", isPresented: Binding(
            get: { connectionFailureMessage != nil },
            set: { if !$0 { connectionFailureMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionFailureMessage ?? "")
        }
        .onChange(of: settingsManager.layoutPresets.map(\.id)) { _, workgroupIDs in
            if case .preset(let selectedWorkgroupID) = selectedWorkgroupSelection,
               !workgroupIDs.contains(selectedWorkgroupID) {
                selectedWorkgroupSelection = nil
            }
        }
        #if os(iOS)
        .onChange(of: sessionManager.workgroups.map(\.id)) { _, workgroupIDs in
            if case .live(let selectedWorkgroupID) = selectedWorkgroupSelection,
               !workgroupIDs.contains(selectedWorkgroupID) {
                selectedWorkgroupSelection = nil
            }
        }
        #endif
        .task { serverManager.loadServersIfNeeded() }
    }

    @ViewBuilder
    private func workgroupResults(
        connectionLibrary: ConnectionLibraryProjection
    ) -> some View {
        let presets = connectionLibrary.workgroups(matching: searchQuery)
        let liveWorkgroups = matchingLiveWorkgroups(searchQuery)
        let visibleSelections = liveWorkgroups.map { ConnectionWorkgroupSelection.live($0.id) }
            + presets.map { ConnectionWorkgroupSelection.preset($0.id) }
        return List(selection: $selectedWorkgroupSelection) {
            if liveWorkgroups.isEmpty, presets.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? "No Workgroups" : "No Matching Workgroups",
                    systemImage: "rectangle.stack",
                    description: Text(
                        searchQuery.isEmpty
                            ? "Create a reusable command-per-tab terminal workspace."
                            : "Try a different search."
                        )
                )
            }

            #if os(iOS)
            if !liveWorkgroups.isEmpty {
                Section("Live Terminals") {
                    ForEach(Array(liveWorkgroups.reversed())) { workgroup in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(workgroup.colorTag.color)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workgroup.name)
                                    .font(.headline)
                                Text("\(liveSessions(in: workgroup).count) live tabs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }
                        .tag(ConnectionWorkgroupSelection.live(workgroup.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedWorkgroupSelection = .live(workgroup.id)
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
                    HStack(spacing: 10) {
                        Circle()
                            .fill(preset.colorTag.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.headline)
                            Text("\(preset.sessionIntents.count) tabs")
                                .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .tag(ConnectionWorkgroupSelection.preset(preset.id))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(preset.name), \(preset.sessionIntents.count) tabs"
                    )
                    .accessibilityHint("Select to show workgroup details")
                    .accessibilityIdentifier(
                        "connection-library-workgroup-\(preset.id.uuidString.lowercased())"
                    )
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWorkgroupSelection = .preset(preset.id)
                    }
                    #endif
                    .contextMenu {
                        Button("Open", systemImage: "rectangle.stack") {
                            runtime.requestOpenWorkgroup(preset.id)
                        }
                        Button("Edit", systemImage: "pencil") {
                            workgroupEditorContext = .edit(preset)
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            workgroupEditorContext = .duplicate(preset)
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            settingsManager.deleteLayoutPreset(preset)
                        }
                    }
                }
                }
            }
        }
        .accessibilityIdentifier("connection-library-results-workgroups")
        .navigationTitle("Workgroups")
        .searchable(text: $searchQuery, prompt: "Search workgroups...")
        .searchFocused($searchIsFocused)
        .onChange(of: visibleSelections) { _, visibleSelections in
            if let selectedWorkgroupSelection,
               !visibleSelections.contains(selectedWorkgroupSelection) {
                self.selectedWorkgroupSelection = nil
            }
        }
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

                #if !os(macOS)
                Button {
                    editCurrentSessionsAsWorkgroup()
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .disabled(currentSavedSessionIntents.isEmpty)
                .accessibilityLabel("Save current SSH sessions as workgroup")
                .accessibilityIdentifier("connection-library-save-current-workgroup")
                #endif

                Button {
                    workgroupEditorContext = .new()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New workgroup")
                .accessibilityIdentifier("connection-library-add-workgroup")
            }
            #endif
        }
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
                            Text("\(preset.workspaceLayout?.tabs.count ?? preset.sessionIntents.count) tabs · \(preset.sessionIntents.count) terminals · \(preset.sessionIntents.filter { $0.startupCommand != nil }.count) startup commands")
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
                        workgroupEditorContext = .edit(preset)
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
        } else {
            ContentUnavailableView {
                Label("Select a Workgroup", systemImage: "rectangle.stack")
            } description: {
                Text("Workgroups open one configured command per terminal tab.")
            } actions: {
                Button("New Workgroup", systemImage: "plus") {
                    workgroupEditorContext = .new()
                }
                .accessibilityIdentifier("connection-library-add-workgroup-empty-detail")
            }
            .accessibilityIdentifier("connection-library-detail-empty-workgroup")
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
        guard case .preset(let selectedWorkgroupID) = selectedWorkgroupSelection else {
            return nil
        }
        return connectionLibrary.workgroups.first(where: { $0.id == selectedWorkgroupID })
    }

    private var selectedLiveWorkgroup: TerminalWorkgroup? {
        #if os(iOS)
        guard case .live(let selectedWorkgroupID) = selectedWorkgroupSelection else {
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
        sessionManager.sessions.compactMap { session in
            guard session.purpose == .terminal,
                  serverManager.server(for: session.server.id) != nil else { return nil }
            return LayoutPreset.SessionIntent(serverID: session.server.id)
        }
    }

    private func editCurrentSessionsAsWorkgroup() {
        let intents = currentSavedSessionIntents
        guard !intents.isEmpty else {
            connectionFailureMessage = "No open sessions use a saved SSH connection."
            return
        }
        workgroupEditorContext = .new(
            name: "Workgroup (\(intents.count) tabs)",
            sessionIntents: intents
        )
    }

    #if os(iOS)
    private func resumeLiveWorkgroup(_ workgroupID: UUID) {
        guard iOSRouter.resumeTerminal(workgroupID: workgroupID, in: sessionManager) else {
            connectionFailureMessage = "The terminal workgroup is no longer available."
            return
        }
    }
    #endif
}
