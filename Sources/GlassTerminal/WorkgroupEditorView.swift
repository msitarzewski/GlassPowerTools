//
//  WorkgroupEditorView.swift
//  Glass Power Tools — GlassTerminal
//
//  Moved verbatim from glas.sh's ConnectionManagerView.swift (lines 2591-3319) on 2026-09-10 when the shell
//  took over the connection library. The workgroup editor and its tab editor.
//

import SwiftUI
import GlassLayers

struct WorkgroupEditorContext: Identifiable {
    let id = UUID()
    let original: LayoutPreset?
    let name: String
    let colorTag: ServerColorTag
    let sessionIntents: [LayoutPreset.SessionIntent]
    var workspaceLayout: LayoutPreset.WorkspaceLayout? = nil
    var openingView: LayoutPreset.OpeningView = .tabs
    var autoFocusOnActivity = LayoutPreset.followsActivityByDefault
    var gridCardWidth: Double? = nil
    /// The settings the workgroup's window opens with (W20's look, W22): a captured window's, or
    /// the one being edited's. The editor changes their Look and Text (D84) and keeps the rest.
    var windowSettings = GlassWindowOverrides()

    static func new(
        name: String = "Workgroup",
        colorTag: ServerColorTag = .blue,
        sessionIntents: [LayoutPreset.SessionIntent] = []
    ) -> Self {
        Self(
            original: nil,
            name: name,
            colorTag: colorTag,
            sessionIntents: sessionIntents
        )
    }

    static func edit(_ preset: LayoutPreset) -> Self {
        Self(
            original: preset,
            name: preset.name,
            colorTag: preset.colorTag,
            sessionIntents: preset.sessionIntents,
            workspaceLayout: preset.workspaceLayout,
            openingView: preset.openingView,
            autoFocusOnActivity: preset.autoFocusOnActivity,
            gridCardWidth: preset.gridCardWidth,
            windowSettings: preset.windowSettings
        )
    }

    static func duplicate(_ preset: LayoutPreset) -> Self {
        let copyName = String("\(preset.name) Copy".prefix(LayoutPreset.maximumNameLength))
        return Self(
            original: nil,
            name: copyName,
            colorTag: preset.colorTag,
            // A copy opens terminals of its own, never the original's tmux sessions (W4b).
            sessionIntents: preset.sessionIntents.map { intent in
                var copy = intent
                copy.tmuxSession = nil
                return copy
            },
            workspaceLayout: preset.workspaceLayout,
            openingView: preset.openingView,
            autoFocusOnActivity: preset.autoFocusOnActivity,
            gridCardWidth: preset.gridCardWidth,
            windowSettings: preset.windowSettings
        )
    }

    /// The window settings the saved workgroup keeps (W20, W22), as the editor left them
    /// (`edited`, its Look). A window saved as a workgroup takes the window's, none included, and
    /// so does a copy or an edit of a workgroup keep its own; one made by hand keeps those of the
    /// workgroup it replaces, as it keeps how that one opens, but the look it was shown here: the
    /// editor shows the look a workgroup has, and None chosen there is none.
    func windowSettingsToSave(_ edited: GlassWindowOverrides, replacing replaced: LayoutPreset?) -> GlassWindowOverrides {
        if workspaceLayout != nil || original != nil || !windowSettings.isEmpty { return edited }
        return (replaced?.windowSettings ?? GlassWindowOverrides())
            .removing(TerminalWindowSettings.lookStyleKeys)
            .merging(edited)
    }

    /// As opened, with nothing changed in the editor.
    func windowSettingsToSave(replacing replaced: LayoutPreset?) -> GlassWindowOverrides {
        windowSettingsToSave(windowSettings, replacing: replaced)
    }
}

private extension ToolbarItemPlacement {
    static var workgroupActions: Self {
        #if os(visionOS)
        .bottomOrnament
        #elseif os(iOS)
        .bottomBar
        #else
        .primaryAction
        #endif
    }
}

struct WorkgroupTabDraft: Identifiable {
    let id: UUID
    /// Another kind of terminal is another machine: the tmux session stays with the old one.
    var kind: LayoutPreset.SessionIntent.Kind {
        didSet { if kind != oldValue { tmuxSession = nil } }
    }
    /// Another server, the same: a session lives on its host (W4b).
    var serverID: UUID? {
        didSet { if serverID != oldValue { tmuxSession = nil } }
    }
    var label: String
    var startupCommand: String
    var localShell: String = ""
    var localDirectory: String = ""
    /// W4b: the tmux session the tab opens on, kept through an edit — the editor rebuilds every
    /// terminal from its draft, and a name left out here was lost on save.
    var tmuxSession: String? = nil
    /// A plain shell by choice (2026-10-12), kept through an edit for the same reason.
    var withoutTmux = false

    init(
        id: UUID = UUID(),
        kind: LayoutPreset.SessionIntent.Kind,
        serverID: UUID? = nil,
        label: String = "",
        startupCommand: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.serverID = serverID
        self.label = label
        self.startupCommand = startupCommand
    }

    init(intent: LayoutPreset.SessionIntent) {
        self.init(
            kind: intent.kind,
            serverID: intent.serverID,
            label: intent.label ?? "",
            startupCommand: intent.startupCommand ?? ""
        )
        localShell = intent.localShell ?? ""
        localDirectory = intent.localDirectory ?? ""
        tmuxSession = intent.tmuxSession
        withoutTmux = intent.withoutTmux
    }

    var intent: LayoutPreset.SessionIntent {
        LayoutPreset.SessionIntent(
            kind: kind,
            serverID: kind == .ssh ? serverID : nil,
            label: label,
            startupCommand: startupCommand,
            localShell: kind == .local ? localShell : nil,
            localDirectory: kind == .local ? localDirectory : nil,
            tmuxSession: tmuxSession,
            withoutTmux: withoutTmux
        )
    }

    func validationMessage(servers: [ServerConfiguration]) -> String? {
        if kind == .ssh {
            guard let serverID, servers.contains(where: { $0.id == serverID }) else {
                return "Choose a saved connection."
            }
        }
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count <= LayoutPreset.SessionIntent.maximumLabelLength,
              !label.utf8.contains(0) else { return "Enter a label no longer than \(LayoutPreset.SessionIntent.maximumLabelLength) characters without null characters." }
        let command = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !command.isEmpty, TerminalStartupCommandTicket(command: command) == nil {
            return "Use a single-line startup command no larger than 4 KB."
        }
        if kind == .local {
            for path in [localShell, localDirectory] {
                let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && (!(value.hasPrefix("/") || value == "~" || value.hasPrefix("~/")) || value.utf8.contains(0)) {
                    return "Use an absolute path or ~ for the shell and working directory."
                }
            }
        }
        return nil
    }
}

struct WorkgroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let context: WorkgroupEditorContext
    let servers: [ServerConfiguration]
    /// The workgroups saved now: a new one given one of their names may replace it (W4b).
    let existing: [LayoutPreset]
    let onSave: (LayoutPreset) -> Void

    @State private var name: String
    @State private var colorTag: ServerColorTag
    @State private var openingView: LayoutPreset.OpeningView
    @State private var autoFocusOnActivity: Bool
    /// The window settings it opens with; Look and Text change them here (the owner, 2026-10-21:
    /// "This way they can have personality from launch").
    @State private var windowSettings: GlassWindowOverrides
    @State private var tabs: [WorkgroupTabDraft]
    @State private var selectedTabID: UUID?
    @State private var editingTab: WorkgroupTabDraft?
    @State private var pendingDeletionIDs: [UUID] = []
    @State private var showingTabDeletion = false
    /// A saved workgroup with the name being saved, waiting for Replace or Keep Both.
    @State private var replaceCandidate: LayoutPreset?

    init(
        context: WorkgroupEditorContext,
        servers: [ServerConfiguration],
        existing: [LayoutPreset] = [],
        onSave: @escaping (LayoutPreset) -> Void
    ) {
        self.context = context
        self.servers = servers
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: context.name)
        _colorTag = State(initialValue: context.colorTag)
        _openingView = State(initialValue: context.openingView)
        _autoFocusOnActivity = State(initialValue: context.autoFocusOnActivity)
        _windowSettings = State(initialValue: context.windowSettings)
        _tabs = State(initialValue: context.sessionIntents.map(WorkgroupTabDraft.init(intent:)))
    }

    @FocusState private var nameIsFocused: Bool

    var body: some View {
        NavigationStack {
            platformForm
                .navigationTitle(context.original == nil ? "New Workgroup" : "Edit Workgroup")
                .toolbar {
                    #if !os(macOS)
                    ToolbarItemGroup(placement: .workgroupActions) { tabListControls }
                    #endif
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(validationMessage != nil)
                            #if os(macOS)
                            .keyboardShortcut(.defaultAction)
                            #endif
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 760, maxWidth: 900,
               minHeight: 620, idealHeight: 720, maxHeight: 820)
        #endif
        .onAppear { nameIsFocused = true }
        .sheet(item: $editingTab) { draft in
            WorkgroupTabEditorView(
                draft: draft,
                isNew: !tabs.contains(where: { $0.id == draft.id }),
                canDelete: canChangeStructure,
                servers: servers,
                onSave: { updated in
                    if let index = tabs.firstIndex(where: { $0.id == updated.id }) {
                        tabs[index] = updated
                    } else if canChangeStructure, tabs.count < LayoutPreset.maximumSessionCount {
                        tabs.append(updated)
                    }
                    selectedTabID = updated.id
                },
                onDelete: { deleteTabs([draft.id]) }
            )
        }
        .confirmationDialog("Delete \(pendingDeletionIDs.count == 1 ? "Tab" : "Tabs")?", isPresented: $showingTabDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteTabs(pendingDeletionIDs)
                pendingDeletionIDs = []
            }
            Button("Cancel", role: .cancel) { pendingDeletionIDs = [] }
        } message: {
            Text("This removes the selected tabs from this draft. The saved Workgroup is unchanged until you save.")
        }
        .confirmationDialog(
            "Replace “\(replaceCandidate?.name ?? normalizedName)”?",
            isPresented: Binding(get: { replaceCandidate != nil }, set: { if !$0 { replaceCandidate = nil } }),
            titleVisibility: .visible,
            presenting: replaceCandidate
        ) { candidate in
            Button("Replace", role: .destructive) { save(replacing: candidate) }
            Button("Keep Both") { save(replacing: nil) }
            Button("Cancel", role: .cancel) { replaceCandidate = nil }
        } message: { _ in
            Text("A workgroup with this name already exists. Replace it with these tabs, on every device, or keep both.")
        }
    }

    @ViewBuilder
    private var platformForm: some View {
        #if os(macOS)
        Form { formSections }
            .formStyle(.grouped)
        #else
        Form { formSections }
        #endif
    }

    @ViewBuilder
    private var formSections: some View {
        Section("Workgroup") {
            #if os(macOS)
            Picker("Open in", selection: $openingView) {
                ForEach(LayoutPreset.OpeningView.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("workgroup-opening-view")
            Toggle("Auto-focus on activity", isOn: $autoFocusOnActivity)
                .help("Follow new terminal output while viewing Grid or Carousel. Does not switch active terminal tabs.")
                .accessibilityIdentifier("workgroup-auto-focus-activity")
            #endif
            LabeledContent {
                TextField("Name", text: $name)
                    .terminalTextInputDefaults()
                    .focused($nameIsFocused)
                    .serverFormTextFieldPresentation()
                    .onSubmit { nameIsFocused = false }
            } label: {
                fieldLabel("Name", required: true)
            }

            #if os(macOS)
            LabeledContent("Color") {
                HStack(spacing: 10) {
                    ForEach(ServerColorTag.allCases, id: \.self) { tag in
                        Button {
                            colorTag = tag
                        } label: {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if colorTag == tag {
                                        Circle().strokeBorder(.primary, lineWidth: 2).padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tag.rawValue) color")
                        .accessibilityAddTraits(colorTag == tag ? .isSelected : [])
                    }
                }
                .serverFormControlPresentation()
            }
            #else
            Picker("Color", selection: $colorTag) {
                ForEach(ServerColorTag.allCases, id: \.self) { tag in
                    Label(tag.rawValue.capitalized, systemImage: "circle.fill")
                        .foregroundStyle(tag.color)
                        .tag(tag)
                }
            }
            #endif
        }

        Section {
            #if os(macOS)
            tabTable
                .frame(height: min(360, max(220, CGFloat(tabs.count) * 36 + 32)))
            #else
            ForEach(tabs) { tab in
                Button { editTab(tab.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.kind == .local ? "apple.terminal" : "network")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tabTitle(tab)).font(.headline)
                            if let group = layoutGroup(for: tab) {
                                Text(group).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(tab.startupCommand.isEmpty ? "Interactive shell" : tab.startupCommand)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .moveDisabled(!canChangeStructure)
                .deleteDisabled(!canChangeStructure)
            }
            .onMove { source, destination in
                guard canChangeStructure else { return }
                tabs.move(fromOffsets: source, toOffset: destination)
            }
            .onDelete { indices in
                guard canChangeStructure else { return }
                requestDeletion(indices.map { tabs[$0].id })
            }
            #endif
        } header: {
            HStack {
                Text("\(canChangeStructure ? "Tabs" : "Terminals in saved layout") · \(tabs.count)")
                #if os(macOS)
                Spacer()
                ControlGroup { tabListControls }
                    .controlSize(.small)
                    .accessibilityIdentifier("workgroup-tab-controls")
                #endif
            }
        } footer: {
            if !canChangeStructure {
                Text("Split layout preserved. Edit terminal settings here; rearrange or remove panes in the Mac workspace, then save it again.")
            }
        }

        // This Window's Look and Text, which the window opens with; This Window changes them for
        // that window after, and never the saved Workgroup.
        TerminalLooksSettingsView(settings: $windowSettings, subject: "every tab this Workgroup opens")

        Section {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Startup commands run once when you open the Workgroup. Do not include passwords or tokens; commands are saved with the Workgroup.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(required ? "Required" : "Optional")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var canChangeStructure: Bool { context.workspaceLayout == nil }

    #if os(macOS)
    private var tabTable: some View {
        Table(of: WorkgroupTabDraft.self, selection: $selectedTabID) {
            TableColumn("Order") { tab in
                HStack(spacing: 6) {
                    Image(systemName: canChangeStructure ? "line.3.horizontal" : "lock")
                        .foregroundStyle(.tertiary)
                    Text("\((tabs.firstIndex(where: { $0.id == tab.id }) ?? 0) + 1)")
                        .monospacedDigit()
                }
            }.width(55)
            TableColumn("Label") { tab in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tabTitle(tab)).lineLimit(1)
                    if let group = layoutGroup(for: tab) {
                        Text(group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }.width(min: 120, ideal: 160)
            TableColumn("Type") { tab in
                Label(tab.kind == .local ? "Local" : "SSH", systemImage: tab.kind == .local ? "apple.terminal" : "network")
            }.width(75)
            TableColumn("Startup command") { tab in
                Text(tab.startupCommand.isEmpty ? "Interactive shell" : tab.startupCommand)
                    .font(.body.monospaced())
                    .foregroundStyle(tab.startupCommand.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .help(tab.startupCommand)
            }.width(min: 150, ideal: 240)
        } rows: {
            ForEach(tabs) { tab in
                if canChangeStructure {
                    TableRow(tab).draggable(tab.id.uuidString)
                } else {
                    TableRow(tab)
                }
            }
            .dropDestination(for: String.self) { destination, payloads in
                guard canChangeStructure, let payload = payloads.first,
                      let id = UUID(uuidString: payload),
                      let source = tabs.firstIndex(where: { $0.id == id }) else { return }
                tabs.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
                selectedTabID = id
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first {
                Button("Edit Tab", systemImage: "pencil") { editTab(id) }
                Button("Move Up", systemImage: "arrow.up") { moveTab(id, by: -1) }
                    .disabled(!canChangeStructure || tabs.first?.id == id)
                Button("Move Down", systemImage: "arrow.down") { moveTab(id, by: 1) }
                    .disabled(!canChangeStructure || tabs.last?.id == id)
                Button("Delete Tab", systemImage: "trash", role: .destructive) { requestDeletion([id]) }
                    .disabled(!canChangeStructure)
            }
        } primaryAction: { ids in
            if let id = ids.first { editTab(id) }
        }
        .accessibilityIdentifier("workgroup-tabs-table")
        .accessibilityHint("Drag to reorder. Double-click a tab to edit it.")
    }
    #endif

    @ViewBuilder private var tabListControls: some View {
            Button("Add Tab", systemImage: "plus") { beginAddingTab() }
                .help("Add Tab")
                .disabled(!canChangeStructure || tabs.count >= LayoutPreset.maximumSessionCount)
                .accessibilityIdentifier("workgroup-add-tab")
            #if os(macOS)
            Button("Delete Tab", systemImage: "minus") {
                if let id = selectedTabID { requestDeletion([id]) }
            }
            .help("Delete selected tab")
            .accessibilityIdentifier("workgroup-delete-tab")
            .disabled(!canChangeStructure || selectedTabID == nil)
            Button("Edit Tab", systemImage: "pencil") {
                if let id = selectedTabID { editTab(id) }
            }
            .disabled(selectedTabID == nil)
            .help("Edit selected tab")
            .accessibilityIdentifier("workgroup-edit-tab")
            #else
            if canChangeStructure { EditButton() }
            #endif
    }

    private func tabTitle(_ tab: WorkgroupTabDraft) -> String {
        let label = tab.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        if tab.kind == .local { return "Local Terminal" }
        return servers.first(where: { $0.id == tab.serverID })?.name ?? "Missing Connection"
    }

    private func editTab(_ id: UUID) {
        selectedTabID = id
        editingTab = tabs.first(where: { $0.id == id })
    }

    private func layoutGroup(for tab: WorkgroupTabDraft) -> String? {
        guard let layout = context.workspaceLayout,
              let terminalIndex = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        func contains(_ node: LayoutPreset.WorkspaceLayout.Node) -> Bool {
            switch node {
            case .session(let index): return index == terminalIndex
            case let .split(_, _, first, second): return contains(first) || contains(second)
            }
        }
        guard let index = layout.tabs.firstIndex(where: { contains($0.root) }) else { return nil }
        return "Tab \(index + 1)\(layout.tabs[index].label.map { " · " + $0 } ?? "")"
    }

    private func requestDeletion(_ ids: [UUID]) {
        guard canChangeStructure, !ids.isEmpty else { return }
        pendingDeletionIDs = ids
        showingTabDeletion = true
    }

    private func beginAddingTab() {
        guard canChangeStructure, tabs.count < LayoutPreset.maximumSessionCount else { return }
        #if os(macOS)
        editingTab = WorkgroupTabDraft(kind: .local)
        #else
        editingTab = WorkgroupTabDraft(kind: .ssh, serverID: servers.first?.id)
        #endif
    }

    private func deleteTabs(_ ids: [UUID]) {
        guard canChangeStructure else { return }
        tabs.removeAll { ids.contains($0.id) }
        if let selectedTabID, ids.contains(selectedTabID) { self.selectedTabID = tabs.first?.id }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard !normalizedName.isEmpty else { return "Enter a workgroup name." }
        guard normalizedName.count <= LayoutPreset.maximumNameLength,
              !normalizedName.utf8.contains(0) else {
            return "The workgroup name must be at most \(LayoutPreset.maximumNameLength) characters."
        }
        guard !tabs.isEmpty else { return "Add at least one terminal tab." }
        guard tabs.count <= LayoutPreset.maximumSessionCount else {
            return "A workgroup can contain at most \(LayoutPreset.maximumSessionCount) tabs."
        }
        for (index, tab) in tabs.enumerated() {
            if let message = tab.validationMessage(servers: servers) {
                return "Tab \(index + 1): \(message)"
            }
        }
        return nil
    }

    private func moveTab(_ id: UUID, by offset: Int) {
        guard canChangeStructure, let source = tabs.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard tabs.indices.contains(destination) else { return }
        tabs.swapAt(source, destination)
    }

    private func save() {
        guard validationMessage == nil else { return }
        // A new workgroup under a name already saved — a window saved again to rebuild its
        // workgroup (owner, 2026-10-08) — asks whether it replaces that one.
        if context.original == nil, let candidate = Self.workgroup(named: normalizedName, in: existing) {
            replaceCandidate = candidate
            return
        }
        save(replacing: nil)
    }

    /// The saved workgroup a new one named `name` would replace: the same name, ignoring case.
    static func workgroup(named name: String, in presets: [LayoutPreset]) -> LayoutPreset? {
        presets.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Saves the draft. Replacing keeps the replaced workgroup's identity, so every device
    /// updates that workgroup rather than gaining a second one.
    private func save(replacing replaced: LayoutPreset?) {
        guard validationMessage == nil else { return }
        replaceCandidate = nil
        let kept = replaced ?? context.original
        let intents = tabs.map(\.intent)
        var preset = LayoutPreset(
            id: kept?.id ?? UUID(),
            name: normalizedName,
            colorTag: colorTag,
            sessionIntents: intents,
            createdAt: kept?.createdAt ?? Date(),
            lastUsed: kept?.lastUsed
        )
        preset.workspaceLayout = context.workspaceLayout
        #if os(macOS)
        preset.openingView = openingView
        preset.autoFocusOnActivity = autoFocusOnActivity
        #else
        // Not offered here: a workgroup replaced from this device keeps how the Mac opens it.
        preset.openingView = replaced?.openingView ?? openingView
        preset.autoFocusOnActivity = replaced?.autoFocusOnActivity ?? autoFocusOnActivity
        #endif
        preset.gridCardWidth = context.gridCardWidth ?? replaced?.gridCardWidth
        preset.windowSettings = context.windowSettingsToSave(windowSettings, replacing: replaced)
        onSave(preset)
        dismiss()
    }
}

struct WorkgroupTabEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkgroupTabDraft
    @State private var showingDeleteConfirmation = false
    let isNew: Bool
    let canDelete: Bool
    let servers: [ServerConfiguration]
    let onSave: (WorkgroupTabDraft) -> Void
    let onDelete: () -> Void
    private let includesLocalChoice: Bool

    init(
        draft: WorkgroupTabDraft,
        isNew: Bool,
        canDelete: Bool,
        servers: [ServerConfiguration],
        onSave: @escaping (WorkgroupTabDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
        self.canDelete = canDelete
        self.servers = servers
        self.onSave = onSave
        self.onDelete = onDelete
        #if os(macOS)
        includesLocalChoice = true
        #else
        includesLocalChoice = draft.kind == .local
        #endif
    }

    var body: some View {
        NavigationStack {
            platformForm
                .navigationTitle(isNew ? "Add Tab" : "Edit Tab")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isNew ? "Add" : "Save") {
                            guard draft.validationMessage(servers: servers) == nil else { return }
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(draft.validationMessage(servers: servers) != nil)
                        #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 600, maxWidth: 680,
               minHeight: 420, idealHeight: 540, maxHeight: 720)
        #endif
        .confirmationDialog("Delete this tab?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Tab", role: .destructive) {
                guard canDelete else { return }
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tab will be removed when you save the Workgroup.")
        }
    }

    @ViewBuilder private var platformForm: some View {
        #if os(macOS)
        Form { sections }.formStyle(.grouped)
        #else
        Form { sections }
        #endif
    }

    @ViewBuilder private var sections: some View {
        Section("Connection") {
            LabeledContent("Type") {
                Picker("Type", selection: $draft.kind) {
                    if includesLocalChoice {
                        Text("Local").tag(LayoutPreset.SessionIntent.Kind.local)
                    }
                    Text("SSH").tag(LayoutPreset.SessionIntent.Kind.ssh)
                }
                .pickerStyle(.segmented)
                .serverFormControlPresentation()
                .onChange(of: draft.kind) { _, kind in
                    draft.serverID = kind == .ssh ? (draft.serverID ?? servers.first?.id) : nil
                }
            }
            if draft.kind == .ssh {
                LabeledContent {
                    Picker("Connection", selection: $draft.serverID) {
                        Text("Choose a saved connection").tag(UUID?.none)
                        ForEach(servers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                        if let serverID = draft.serverID,
                           !servers.contains(where: { $0.id == serverID }) {
                            Text("Missing Connection").tag(Optional(serverID))
                        }
                    }
                    .serverFormControlPresentation()
                } label: {
                    fieldLabel("Connection", required: true)
                }
            }
            textField("Label", text: $draft.label)
            // W4b: the session this tab reopens on. Forgetting it leaves the session running, in
            // Active; the tab starts a new one the next time the workgroup opens.
            if let tmuxSession = draft.tmuxSession {
                LabeledContent("tmux session") {
                    HStack {
                        Text(tmuxSession)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button("Start a New One") { draft.tmuxSession = nil }
                            .help("Open a new tmux session next time. This one keeps running, and Active lists it.")
                    }
                    .serverFormControlPresentation()
                }
            }
        }
        Section {
            textField("Startup command", text: $draft.startupCommand, monospaced: true)
            if draft.kind == .local {
                textField("Shell", text: $draft.localShell, prompt: "App default")
                textField("Working directory", text: $draft.localDirectory, prompt: "App default")
            }
        } header: {
            Text("Startup")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The command runs once when you open the Workgroup. Do not include passwords or tokens; commands are saved with the Workgroup.")
                #if !os(macOS)
                if draft.kind == .local {
                    Text("Local terminals open on Mac. These settings are preserved when you save on Vision Pro or iPad.")
                }
                #endif
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        if let message = draft.validationMessage(servers: servers) {
            Section {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !isNew {
            Section {
                Button("Delete Tab", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(!canDelete)
            } footer: {
                if !canDelete {
                    Text("This terminal belongs to a saved split layout. Open the Workgroup on Mac to remove it, then save the updated workspace.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(required ? "Required" : "Optional")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func textField(
        _ title: String,
        text: Binding<String>,
        prompt: String = "",
        monospaced: Bool = false
    ) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt))
                .terminalTextInputDefaults()
                .font(monospaced ? .body.monospaced() : .body)
                .serverFormTextFieldPresentation()
        } label: {
            fieldLabel(title)
        }
    }
}

