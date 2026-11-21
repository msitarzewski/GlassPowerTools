//
//  WorkgroupPanelEditor.swift
//  Glass Power Tools — GlassTerminal
//
//  A saved Workgroup is edited where it is shown (the owner, 2026-11-19, of the Edit Workgroup sheet: "one quick thing
//  that bugs me … Let's remove the edit modal and put that directly into the panel itself"). Asked, he chose: every
//  change saves as it is made, ⌘Z undoes it; on every device; and a new Workgroup — the + button, Duplicate, Save as
//  Workgroup — goes straight into the panel, ready to name. The sheet's sections are the panel's now: the name and
//  colour, how it opens, its terminals (each one's fields beneath the list, where the per-tab sheet was), its databases
//  and desktops, and its window's look.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import GlassShell

/// Undo for the panel's edits: the Workgroup as it was before each save.
@MainActor
final class WorkgroupEditorUndo {
    var restore: ((LayoutPreset) -> Void)?
}

struct WorkgroupEditorView: View {
    /// The Workgroup as saved now; one changed on another device is shown again as it is there.
    let saved: LayoutPreset
    let servers: [ServerConfiguration]
    /// A line under the name: how many tabs, terminals and commands.
    var summary: String = ""
    /// Saves an edit at once.
    let onSave: (LayoutPreset) -> Void
    /// A Workgroup just made: its name is selected for typing.
    var focusesName = false
    /// What the panel adds after the editor: the Mac's running terminals.
    var trailing: AnyView? = nil

    @Environment(GlassTerminalRuntime.self) private var runtime: GlassTerminalRuntime?
    @Environment(\.undoManager) private var undoManager

    @State private var name: String
    @State private var colorTag: ServerColorTag
    @State private var openingView: LayoutPreset.OpeningView
    @State private var autoFocusOnActivity: Bool
    /// The window settings it opens with: Look and Text change them (2026-10-21: "This way they can have personality
    /// from launch").
    @State private var windowSettings: GlassWindowOverrides
    @State private var tabs: [WorkgroupTabDraft]
    @State private var services: [UUID]
    /// The tab selected in the list, for the pencil and − beside it.
    @State private var selectedTabID: UUID?
    /// A tab in its sheet: a new one from +, or the one the pencil, a double-click or a tap opened.
    @State private var editingTab: WorkgroupTabDraft?
    /// What was saved last, from here or elsewhere: edits are compared with it, and undo goes back to it.
    @State private var lastSaved: LayoutPreset
    @State private var pendingSave: Task<Void, Never>?
    @State private var undo = WorkgroupEditorUndo()
    @FocusState private var nameIsFocused: Bool

    init(saved: LayoutPreset, servers: [ServerConfiguration], summary: String = "", focusesName: Bool = false,
         trailing: AnyView? = nil, onSave: @escaping (LayoutPreset) -> Void) {
        self.saved = saved
        self.servers = servers
        self.summary = summary
        self.focusesName = focusesName
        self.trailing = trailing
        self.onSave = onSave
        _name = State(initialValue: saved.name)
        _colorTag = State(initialValue: saved.colorTag)
        _openingView = State(initialValue: saved.openingView)
        _autoFocusOnActivity = State(initialValue: saved.autoFocusOnActivity)
        _windowSettings = State(initialValue: saved.windowSettings)
        _tabs = State(initialValue: saved.sessionIntents.map(WorkgroupTabDraft.init(intent:)))
        _services = State(initialValue: saved.services)
        _lastSaved = State(initialValue: saved)
    }

    var body: some View {
        Form {
            header
            workgroupSection
            tabsSection
            if let runtime, let describe = runtime.describeService {
                servicesSection(describe: describe, choices: runtime.workgroupServiceChoices?() ?? [])
            }
            if let trailing { trailing }
            // This Window's Look and Text, which the window opens with; This Window changes them for that window after,
            // and never the saved Workgroup.
            TerminalLooksSettingsView(settings: $windowSettings, subject: "every tab this Workgroup opens")
            Section {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workgroup-validation")
                }
            } footer: {
                Text("Changes are saved as you make them\(undoHint). Startup commands run once when you open the Workgroup; don't include passwords or tokens, which would be saved with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
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
        .onAppear {
            undo.restore = { previous in load(previous) }
            if focusesName { nameIsFocused = true }
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: saved) { _, latest in
            // Saved here, and read back: nothing to show again. Changed on another device: shown as it is now.
            guard !Self.sameContent(latest, draft) else {
                lastSaved = latest
                return
            }
            guard !Self.sameContent(latest, lastSaved) else { return }
            load(latest)
            lastSaved = latest
        }
        .onDisappear { commit() }
    }

    private var undoHint: String {
        #if os(macOS)
        "; ⌘Z undoes"
        #else
        ""
        #endif
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.largeTitle)
                    .foregroundStyle(colorTag.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Workgroup Name", text: $name, prompt: Text("Name"))
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                        // The name as the panel's title, where it was shown before, not a form row's value.
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .terminalTextInputDefaults()
                        .focused($nameIsFocused)
                        .onSubmit { nameIsFocused = false }
                        .accessibilityIdentifier("workgroup-name")
                    if !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var workgroupSection: some View {
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
                .help("Follow new terminal output while viewing Grid. Does not switch active terminal tabs.")
                .accessibilityIdentifier("workgroup-auto-focus-activity")
            LabeledContent("Color") {
                HStack(spacing: 10) {
                    ForEach(ServerColorTag.allCases, id: \.self) { tag in
                        Button { colorTag = tag } label: {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if colorTag == tag { Circle().strokeBorder(.primary, lineWidth: 2).padding(2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tag.rawValue) color")
                        .accessibilityAddTraits(colorTag == tag ? .isSelected : [])
                    }
                }
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
    }

    @ViewBuilder
    private var tabsSection: some View {
        Section {
            #if os(macOS)
            tabTable
                .frame(height: min(360, max(150, CGFloat(tabs.count) * 32 + 32)))
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
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
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
                deleteTabs(indices.map { tabs[$0].id })
            }
            if canChangeStructure {
                Button("Add Tab", systemImage: "plus") { addTab() }
                    .disabled(tabs.count >= LayoutPreset.maximumSessionCount)
                    .accessibilityIdentifier("workgroup-add-tab")
            }
            #endif
        } header: {
            HStack {
                Text("\(canChangeStructure ? "Tabs" : "Terminals in saved layout") · \(tabs.count)")
                #if os(macOS)
                Spacer()
                ControlGroup {
                    Button("Add Tab", systemImage: "plus") { addTab() }
                        .help("Add Tab")
                        .disabled(!canChangeStructure || tabs.count >= LayoutPreset.maximumSessionCount)
                        .accessibilityIdentifier("workgroup-add-tab")
                    Button("Delete Tab", systemImage: "minus") {
                        if let id = selectedTabID { deleteTabs([id]) }
                    }
                    .help("Delete selected tab")
                    .disabled(!canChangeStructure || selectedTabID == nil)
                    .accessibilityIdentifier("workgroup-delete-tab")
                    Button("Edit Tab", systemImage: "pencil") {
                        if let id = selectedTabID { editTab(id) }
                    }
                    .help("Edit selected tab")
                    .disabled(selectedTabID == nil)
                    .accessibilityIdentifier("workgroup-edit-tab")
                }
                .controlSize(.small)
                .accessibilityIdentifier("workgroup-tab-controls")
                #endif
            }
        } footer: {
            if !canChangeStructure {
                Text("Split layout preserved. Edit terminal settings here; rearrange or remove panes in the Mac workspace, then save it again.")
            } else {
                #if os(macOS)
                Text("Double-click a tab, or select it and choose the pencil, to edit it. Drag to reorder.")
                #else
                Text("Tap a tab to edit it. Swipe to delete it.")
                #endif
            }
        }
    }

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
                Button("Delete Tab", systemImage: "trash", role: .destructive) { deleteTabs([id]) }
                    .disabled(!canChangeStructure)
            }
        } primaryAction: { ids in
            if let id = ids.first { editTab(id) }
        }
        .onDeleteCommand { if let id = selectedTabID { deleteTabs([id]) } }
        .accessibilityIdentifier("workgroup-tabs-table")
        .accessibilityHint("Drag to reorder. Double-click a tab to edit it.")
    }
    #endif

    /// Its databases and desktops (B-F40), opened with its terminals, each as Connect opens it.
    private func servicesSection(describe: @escaping @MainActor (UUID) -> GlassFavoriteDescription?,
                                 choices: [UUID]) -> some View {
        let addable = choices.filter { !services.contains($0) }
        return Section {
            ForEach(services, id: \.self) { id in
                WorkgroupServiceRow(description: describe(id)) {
                    services.removeAll { $0 == id }
                }
            }
            Menu {
                ForEach(addable, id: \.self) { id in
                    if let service = describe(id) {
                        Button { services.append(id) } label: {
                            Text(service.title)
                            Text(service.subtitle)
                        }
                    }
                }
            } label: {
                Label("Add Database or Desktop", systemImage: "plus")
            }
            .disabled(addable.isEmpty || services.count >= LayoutPreset.maximumServiceCount)
            .accessibilityIdentifier("workgroup-add-service")
        } header: {
            Text("Databases and Desktops · \(services.count)")
        } footer: {
            Text("Each opens with the terminals, as Connect opens it.")
        }
    }

    // MARK: Tabs

    private var canChangeStructure: Bool { lastSaved.workspaceLayout == nil }

    private func tabTitle(_ tab: WorkgroupTabDraft) -> String {
        let label = tab.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        if tab.kind == .local { return "Local Terminal" }
        return servers.first(where: { $0.id == tab.serverID })?.name ?? "Missing Connection"
    }

    private func layoutGroup(for tab: WorkgroupTabDraft) -> String? {
        guard let layout = lastSaved.workspaceLayout,
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

    /// A new tab, in its sheet: a Mac's own shell on a Mac, else the first saved connection. Added when its Add is chosen.
    private func addTab() {
        guard canChangeStructure, tabs.count < LayoutPreset.maximumSessionCount else { return }
        #if os(macOS)
        editingTab = WorkgroupTabDraft(kind: .local)
        #else
        editingTab = WorkgroupTabDraft(kind: .ssh, serverID: servers.first?.id)
        #endif
    }

    /// A tab, in its sheet.
    private func editTab(_ id: UUID) {
        selectedTabID = id
        editingTab = tabs.first { $0.id == id }
    }

    /// Gone at once; ⌘Z brings them back.
    private func deleteTabs(_ ids: [UUID]) {
        guard canChangeStructure else { return }
        let index = tabs.firstIndex { ids.contains($0.id) }
        tabs.removeAll { ids.contains($0.id) }
        if let selectedTabID, ids.contains(selectedTabID) {
            self.selectedTabID = index.flatMap { tabs.indices.contains($0) ? tabs[$0].id : tabs.last?.id }
        }
    }

    private func moveTab(_ id: UUID, by offset: Int) {
        guard canChangeStructure, let source = tabs.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard tabs.indices.contains(destination) else { return }
        tabs.swapAt(source, destination)
    }

    // MARK: Saving as you go

    private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The Workgroup as the panel shows it now, from the saved one, so nothing the panel doesn't show is lost.
    private var draft: LayoutPreset {
        var preset = lastSaved
        preset.name = normalizedName
        preset.colorTag = colorTag
        preset.sessionIntents = tabs.map(\.intent)
        preset.openingView = openingView
        preset.autoFocusOnActivity = autoFocusOnActivity
        preset.windowSettings = windowSettings
        preset.services = services
        return preset
    }

    /// What keeps an edit from being saved yet: shown under the panel, and the last whole Workgroup stays saved.
    private var validationMessage: String? {
        Self.validationMessage(name: normalizedName, tabs: tabs, services: services, servers: servers)
    }

    static func validationMessage(name: String, tabs: [WorkgroupTabDraft], services: [UUID],
                                  servers: [ServerConfiguration]) -> String? {
        guard !name.isEmpty else { return "Enter a name. The Workgroup keeps its last name until then." }
        guard name.count <= LayoutPreset.maximumNameLength, !name.utf8.contains(0) else {
            return "The name can be at most \(LayoutPreset.maximumNameLength) characters."
        }
        guard !tabs.isEmpty || !services.isEmpty else {
            return "Add a terminal tab, a database or a desktop. Until then, the Workgroup keeps what it had."
        }
        guard tabs.count <= LayoutPreset.maximumSessionCount else {
            return "A Workgroup can contain at most \(LayoutPreset.maximumSessionCount) tabs."
        }
        for (index, tab) in tabs.enumerated() {
            if let message = tab.validationMessage(servers: servers) { return "Tab \(index + 1): \(message)" }
        }
        return nil
    }

    /// A moment after the last change, so typing a name is one save, not one per letter.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    /// Saves what the panel shows, when it is a whole Workgroup and differs from what is saved; ⌘Z goes back.
    private func commit() {
        pendingSave?.cancel()
        pendingSave = nil
        guard validationMessage == nil else { return }
        let preset = draft
        guard !Self.sameContent(preset, lastSaved) else { return }
        let previous = lastSaved
        lastSaved = preset
        onSave(preset)
        undoManager?.registerUndo(withTarget: undo) { undo in undo.restore?(previous) }
        undoManager?.setActionName("Edit Workgroup")
    }

    /// Shows `preset` in the panel — undone to it, or changed to it on another device.
    private func load(_ preset: LayoutPreset) {
        name = preset.name
        colorTag = preset.colorTag
        openingView = preset.openingView
        autoFocusOnActivity = preset.autoFocusOnActivity
        windowSettings = preset.windowSettings
        if tabs.map(\.intent) != preset.sessionIntents {
            tabs = preset.sessionIntents.map(WorkgroupTabDraft.init(intent:))
            if let selectedTabID, !tabs.contains(where: { $0.id == selectedTabID }) { self.selectedTabID = nil }
        }
        services = preset.services
    }

    /// The same Workgroup, whenever each was saved.
    static func sameContent(_ a: LayoutPreset, _ b: LayoutPreset) -> Bool {
        var a = a, b = b
        a.modifiedAt = nil
        b.modifiedAt = nil
        return a == b
    }

    /// The saved Workgroup a new one named `name` would stand beside: the same name, ignoring case.
    static func workgroup(named name: String, in presets: [LayoutPreset]) -> LayoutPreset? {
        presets.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// A name for a new Workgroup that none saved has: "New Workgroup", else "New Workgroup 2" and on.
    static func unusedName(_ base: String = "New Workgroup", in presets: [LayoutPreset]) -> String {
        guard workgroup(named: base, in: presets) != nil else { return base }
        var number = 2
        while workgroup(named: "\(base) \(number)", in: presets) != nil { number += 1 }
        return "\(base) \(number)"
    }
}

/// One tab, added or edited in its own sheet (the owner, 2026-11-19, after trying its fields under the list: "I want the
/// edit tool to open the modal like before, but without the intermediary Edit > list of tabs"): the + and pencil beside
/// the panel's tab list, a double-click on a tab, or a tap elsewhere open it; its Save changes the tab, and the panel
/// saves the Workgroup.
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
            Text("The tab is removed from the Workgroup at once. On a Mac, Edit ▸ Undo brings it back.")
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
