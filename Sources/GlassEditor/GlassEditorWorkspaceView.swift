//
//  GlassEditorWorkspaceView.swift
//  Glass Power Tools — GlassEditor
//
//  The editor window: open documents on the left, the text on the right, a find bar when asked for
//  and a status line that says where you are.
//
//  **Designed on visionOS terms and adapted down**, per the magic directive. The document list is a
//  gaze-height list that highlights when looked at; the status bar is a row of plain facts rather
//  than a dense strip of glyphs; the find bar is part of the surface rather than an ornament,
//  because rule 14 is about controls disappearing from the accessibility tree in a headset.
//
//  On the Mac it is an ordinary document window, which is the point — familiar to a Mac user, and
//  native in a headset. The family's own components do the framing: `GlassLayeredWindow` paints the
//  surface, `GlassLibraryColumnLayout` sizes the sidebar, `GlassSpatialMetrics` decides the row
//  metrics, so an editor window and a library window are recognisably the same product.
//

import SwiftUI
import UniformTypeIdentifiers
import GlassEditorCore
import GlassEditorUI
import GlassConnectionUI
import GlassShell
import GlassLayers

public struct GlassEditorWorkspaceView: View {
    @Bindable private var workspace: GlassEditorWorkspace
    // A new editor window has no project in it, so it opens with the tree out of the way; opening
    // a project brings it back (`GlassEditorWindowLifecycle`).
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var isImporting = false
    @State private var isImportingProject = false
    @State private var exportingDocument: GlassEditorDocument?
    @State private var closeCandidate: GlassEditorDocument?
    @State private var isGoingToLine = false
    @State private var goToLineText = ""
    @State private var filter = ""
    @State private var settingsProject: GlassEditorProject?
    @Environment(\.colorScheme) private var colorScheme
    // Optional: the scene injects it, and a preview or a test may not.
    @Environment(GlassEditorRuntime.self) private var runtime: GlassEditorRuntime?
    // Not macOS-only, so it can be handed to the dialogs modifier unconditionally; the Mac opens
    // the app's Settings scene through `SettingsLink` instead and never reads it.
    @State private var isShowingSettings = false

    /// This window's id, which is also its workspace's. The runtime is told when the window comes
    /// forward, so a file opened from the menu bar lands where the user is looking.
    private let windowID: UUID

    public init(workspace: GlassEditorWorkspace, windowID: UUID = UUID()) {
        self.workspace = workspace
        self.windowID = windowID
    }

    public var body: some View {
        GlassLayeredWindow {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: GlassLibraryColumnLayout.navigationMinimum,
                                                    ideal: GlassLibraryColumnLayout.navigationIdeal,
                                                    max: GlassLibraryColumnLayout.navigationMaximum)
                    .glassLibraryColumnAutosave("com.glasspowertools.editor.columns")
            } detail: {
                GlassLayeredPanel(role: .embedded) { detail }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar { toolbar }
        }
        // **The text follows the system's appearance.** `GlassEditorModel` defaults to the dark
        // theme and nothing ever changed it, so in Light mode the window's chrome went light and the
        // text sat in a dark rectangle in the middle of it. The engine is right not to read the
        // environment itself — a model is not a view — so the view tells it, on appearance and on
        // every change after.
        .modifier(GlassEditorWindowLifecycle(workspace: workspace,
                                             runtime: runtime,
                                             windowID: windowID,
                                             colorScheme: colorScheme,
                                             columnVisibility: $columnVisibility))
        // Drop a file on the window to open it — the gesture a Mac user tries first, and the one
        // that works in the headset and on an iPad too.
        .dropDestination(for: URL.self) { urls, _ in
            var opened = false
            for url in urls where workspace.open(url) != nil { opened = true }
            return opened
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text, .sourceCode, .plainText, .json, .yaml, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): for url in urls { workspace.open(url) }
            case .failure(let error): workspace.message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImportingProject, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): workspace.openProject(url)
            case .failure(let error): workspace.message = error.localizedDescription
            }
        }
        .fileExporter(isPresented: Binding(get: { exportingDocument != nil },
                                           set: { if !$0 { exportingDocument = nil } }),
                      document: exportingDocument.map { GlassEditorTextFile(text: $0.model.text) },
                      contentType: .plainText,
                      defaultFilename: exportingDocument?.displayName) { result in
            if case .success(let url) = result, let document = exportingDocument {
                // `fileExporter` has already written the bytes; adopting the location is what makes
                // the next ⌘S go to the file the user just chose rather than asking again.
                workspace.save(document.id, to: url)
            }
            exportingDocument = nil
        }
        .modifier(GlassEditorDialogs(workspace: workspace,
                                     closeCandidate: $closeCandidate,
                                     exportingDocument: $exportingDocument,
                                     isGoingToLine: $isGoingToLine,
                                     goToLineText: $goToLineText,
                                     settingsProject: $settingsProject,
                                     isShowingSettings: $isShowingSettings,
                                     goToLine: goToLine))
        // ⌘N in an editor window means a new document; the shell owns the one File ▸ New item and
        // each window says what it makes (`GlassShellFileCommands`).
        .focusedSceneValue(\.glassNewItem, GlassNewItemAction(title: "New Document") {
            workspace.newDocument()
        })
        #if os(macOS)
        // Everything the Mac window needs, in one modifier: the type checker gives up on a `body`
        // with this many modifiers chained onto it, and says so as a timeout rather than an error
        // anyone can read.
        .modifier(MacEditorWindowBehaviour(
            actions: editorActions,
            canCloseDocument: workspace.selectedDocument != nil,
            closeDocument: { if let document = workspace.selectedDocument { requestClose(document) } }))
        #endif
    }

    #if os(macOS)
    /// Built here rather than inline in `body`: the whole expression is one literal with nine
    /// closures in it, and the type checker gives up on the chain it sits in.
    private var editorActions: GlassEditorActions {
        GlassEditorActions(
            canSave: workspace.selectedDocument?.isDirty == true,
            open: { isImporting = true },
            openProject: { isImportingProject = true },
            save: { saveSelected() },
            increaseFontSize: { workspace.preferences.increaseFontSize() },
            decreaseFontSize: { workspace.preferences.decreaseFontSize() },
            resetFontSize: { workspace.preferences.resetFontSize() },
            find: { workspace.findIsPresented = true },
            goToLine: { goToLineText = ""; isGoingToLine = true })
    }
    #endif

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $workspace.sidebarSelection) {
            ForEach(workspace.projects) { project in
                Section {
                    if let root = workspace.projectRoots[project.id] {
                        GlassEditorTreeRows(workspace: workspace, nodes: root.children ?? [],
                                            filter: filter, open: activate)
                    }
                }
                // No header. The project's name and where it is are in the **title bar** now, and
                // repeating them over the file list said the same two facts twice in one window
                // (2026-09-17). The machine badge lives in Project Settings, which is the place
                // that can also change it.
            }
        }
        .scrollContentBackground(.hidden)
        // **The project's own controls, at the foot of its own column.** Refresh was buried in a
        // "…" menu on the section header, and the gear in the toolbar is the *app's* settings —
        // this one is the project's, which is a different thing and belongs beside its tree.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let project = workspace.projects.first {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 8) {
                        Button("Project Settings", systemImage: "gearshape") {
                            settingsProject = project
                        }
                        .accessibilityIdentifier("editor-project-settings")
                        Spacer(minLength: 0)
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            workspace.refreshProject(project.id)
                        }
                        .accessibilityIdentifier("editor-project-refresh")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .frame(height: GlassSpatialMetrics.footerHeight)
                }
                // **No material.** The sidebar is glass and paints nothing of its own; a `.bar`
                // across its foot was an opaque strip sitting in a translucent column, and it
                // announced itself as a different surface. The divider is the separation.
                
            }
        }
        // A field, not a button. The connections list and the schema browser both filter their
        // list from a real search field (`GlassLibraryResults`, `SchemaBrowserView`); the editor
        // had a magnifying-glass button that toggled the find bar, which is a different act
        // entirely and is still on ⌥⌘F and in the Text menu.
        // `.sidebar` placement, so it is a field standing in the list — the "Filter" field the
        // connections window shows. Left to itself the modifier collapses into a magnifying glass
        // in the toolbar at this window width, which is the button this was meant to replace.
        .searchable(text: $filter, placement: .sidebar, prompt: "Filter")
        // **The keyboard reaches the tree.**
        //
        // ↑ and ↓ move the selection because the rows are tagged and selectable — which they were
        // not: a file row was a `Button`, and a button swallows the click before selection sees it,
        // so there was nothing to move. Return opens a file, or opens and closes a folder; ⌘↓ opens,
        // which is what the Finder and Xcode both mean by it.
        //
        // **← and → are not here, and that is measured rather than decided.** Handlers for them were,
        // and they never fired: the list is an `NSOutlineView` underneath and it takes the arrow keys
        // before a SwiftUI key handler sees them — verified by driving the running app, where →
        // changed nothing while setting the row's disclosure through the accessibility API expanded
        // it immediately. Return is the toggle until there is a way to get the key that does not
        // depend on guessing at the responder chain.
        .onKeyPress(.return, phases: .down) { _ in activateSelection() }
        .onKeyPress(.downArrow, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return activateSelection()
        }
    }

    /// What sits under the file's name in the title bar: the project and where it is, the way the
    /// terminal puts `michael@192.0.2.10:22` under "Terminal on oscar". A file opened on its own
    /// says where it is instead — the folder is the useful fact either way.
    private func subtitle(for document: GlassEditorDocument) -> String {
        if let project = workspace.projects.first {
            return "\(project.displayName) — \(abbreviated(project.path))"
        }
        guard let url = document.url else { return "" }
        return abbreviated(url.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// `~` for home, because a title bar is not the place to read someone's user name back to them.
    private func abbreviated(_ path: String) -> String {
        // `NSHomeDirectory()`, not `homeDirectoryForCurrentUser` — the latter is macOS-only, and a
        // macOS build says nothing about that (rule 32).
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count - 1)
    }

    /// Case-insensitive, per level — the way the schema browser filters databases and the tables
    /// inside them. An empty filter matches everything rather than nothing.
    func matches(_ name: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query)
    }

    /// Return, ⌘↓ and a double click all mean the same thing: open what is selected. A folder
    /// opens and closes instead, because a folder has nothing to show in an editor.
    @discardableResult
    private func activateSelection() -> KeyPress.Result {
        switch workspace.sidebarSelection {
        case .node(let id):
            guard let node = workspace.node(id) else { return .ignored }
            activate(node)
            return .handled
        case .document, .none:
            return .ignored
        }
    }

    private func activate(_ node: GlassEditorProjectNode) {
        if node.isDirectory {
            workspace.setExpanded(!workspace.isExpanded(node.id), for: node.id)
        } else {
            workspace.open(URL(filePath: node.path))
        }
    }


    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let document = workspace.selectedDocument {
            VStack(spacing: 0) {
                // Open documents are tabs, not a list in the sidebar — the database's strip,
                // shared rather than copied (`GlassWorkspaceTabBar`). One document is not a tab
                // bar, so the strip appears when there is something to switch between.
                if workspace.documents.count > 1 {
                    GlassWorkspaceTabBar(
                        tabs: workspace.documents.map { document in
                            GlassWorkspaceTabItem(id: document.id,
                                                  title: document.isDirty ? "\(document.displayName) •" : document.displayName,
                                                  symbolName: symbolName(for: document.model.language),
                                                  help: document.locationDescription ?? document.displayName)
                        },
                        selection: workspace.selection,
                        accessibilityLabel: "Open documents",
                        onSelect: { workspace.sidebarSelection = .document($0) },
                        onClose: { id in
                            if let target = workspace.documents.first(where: { $0.id == id }) {
                                requestClose(target)
                            }
                        })
                    .overlay(alignment: .bottom) { Divider() }
                }
                if workspace.findIsPresented { findBar(document) ; Divider() }
                // **Identity, or the text never changes.** The engine deliberately observes its
                // model rather than being pushed values through `updateNSView`, so handing this
                // view a *different* model does not reach the text view that is already on screen —
                // it keeps rendering the first document opened. Seen in the running app with three
                // files open and the first one still showing. One identity per document, so
                // switching documents builds the engine that belongs to it.
                GlassEditorView(model: document.model)
                    .id(document.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(document.displayName)
            // visionOS has no window subtitle — a title bar there is an ornament, not a bar — so
            // the fact goes in the status line instead of being dropped.
            #if os(macOS)
            .navigationSubtitle(subtitle(for: document))
            #endif
            // **A bar, not a strip of transparency over the text.** The status line was the last
            // row of a `VStack` with no surface of its own, so the gutter's line numbers showed
            // through it. This is the family's bottom bar — the shape the workgroup detail uses.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    statusBar(document)
                }
                .background(.bar)
            }
        } else {
            // **A freshly opened project puts its name in the title, full size.** The project is
            // what you have open at that moment; once a file is open the file's name is, and the
            // project moves to the subtitle beneath it. Same window, two states, and the big text
            // always names the thing you are looking at.
            ContentUnavailableView {
                Label(workspace.projects.first?.displayName ?? "No Document",
                      systemImage: workspace.projects.isEmpty ? "text.page" : "folder")
            } description: {
                Text(workspace.projects.isEmpty
                     ? "Open a file, drop one on this window, or start something new."
                     : "Choose a file from the project to start editing.")
            } actions: {
                Button("Open Project…") { isImportingProject = true }
                Button("Open File…") { isImporting = true }
                Button("New Document") { workspace.newDocument() }
            }
            #if os(visionOS)
            .font(.title3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            .navigationTitle(workspace.projects.first?.displayName ?? "Editor")
            #if os(macOS)
            .navigationSubtitle(workspace.projects.first.map { abbreviated($0.path) } ?? "")
            #endif
        }
    }

    private func findBar(_ document: GlassEditorDocument) -> some View {
        HStack(spacing: 8) {
            TextField("Find", text: $workspace.findQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { workspace.findNext() }
                .accessibilityIdentifier("editor-find-field")
            Button("Previous", systemImage: "chevron.up") { workspace.findNext(reverse: true) }
                .labelStyle(.iconOnly)
            Button("Next", systemImage: "chevron.down") { workspace.findNext() }
                .labelStyle(.iconOnly)
            Toggle("Aa", isOn: $workspace.findIsCaseSensitive)
                .toggleStyle(.button)
                .help("Match case")
            Toggle(".*", isOn: $workspace.findUsesRegularExpression)
                .toggleStyle(.button)
                .help("Regular expression")
            Divider().frame(height: 18)
            TextField("Replace", text: $workspace.replacement)
                .textFieldStyle(.roundedBorder)
            Button("All") {
                let count = workspace.replaceAll()
                workspace.message = count == 0 ? "No matches." : "Replaced \(count) match\(count == 1 ? "" : "es")."
            }
            Spacer(minLength: 0)
            Text(matchCountText(document))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("Done") { workspace.findIsPresented = false }
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, GlassSpatialMetrics.isSpatial ? 14 : 8)
    }

    private func statusBar(_ document: GlassEditorDocument) -> some View {
        HStack(spacing: 14) {
            Button {
                goToLineText = ""
                isGoingToLine = true
            } label: {
                Text(positionText(document)).font(.caption.monospacedDigit())
            }
            .buttonStyle(.plain)
            .help("Go to line")

            Menu {
                ForEach(LanguageID.allCases, id: \.self) { language in
                    Button(languageName(language)) { document.setLanguage(language) }
                }
            } label: {
                Text(languageName(document.model.language)).font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(document.model.snapshot.lineEndings.statusName).font(.caption)
            if document.model.isHighlightingDegradedToPlaintext {
                // Said out loud rather than left as a mystery: a very large file stops being
                // highlighted, and a user who sees colour disappear deserves the reason.
                Label("Highlighting off — large file", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if document.isDirty {
                Text("Edited").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 24 : 14)
        // The same height as the sidebar's footer beside it — two bars at two heights in one
        // window reads as a mistake before anyone works out why.
        .frame(height: GlassSpatialMetrics.footerHeight)
        .glassActionBarSurface()
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // **Leading the content region, past the divider — left of the title.** The library puts
        // its own actions at `.navigation` (`GlassConnectionLibrary`, itself following glassdb's Add
        // Connection), and the editor putting everything in `.primaryAction` is most of why it read
        // as a different application.
        ToolbarItem(placement: .navigation) {
            Button("New Document", systemImage: "plus") { workspace.newDocument() }
                .help("New Document")
                .accessibilityIdentifier("editor-new")
        }
        // The gear opens **Settings**, where every other preference in this app lives. It used to
        // drop a menu of toggles, which put the editor's preferences in one window's toolbar and
        // nowhere else — and grew a second language picker beside the footer's, which is how two
        // controls for one fact start disagreeing.
        ToolbarItem(placement: .primaryAction) {
            #if os(macOS)
            SettingsLink {
                Label("Editor Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("editor-settings")
            #else
            Button("Editor Settings", systemImage: "gearshape") { isShowingSettings = true }
                .accessibilityIdentifier("editor-settings")
            #endif
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Save", systemImage: "arrow.down.document") { saveSelected() }
                .disabled(workspace.selectedDocument?.isDirty != true)
                .accessibilityIdentifier("editor-save")
        }
    }

    // MARK: Actions

    private func saveSelected() {
        guard let document = workspace.selectedDocument else { return }
        if document.hasNeverBeenSaved { exportingDocument = document }
        else { workspace.save(document.id) }
    }

    private func requestClose(_ document: GlassEditorDocument) {
        if !workspace.close(document.id) { closeCandidate = document }
    }

    private func goToLine() {
        guard let document = workspace.selectedDocument,
              let line = Int(goToLineText.trimmingCharacters(in: .whitespaces)), line >= 1 else { return }
        let index = min(line - 1, max(0, document.model.lineCount - 1))
        let range = document.model.lineRange(ofLine: index)
        document.model.selectedRange = range.lowerBound..<range.lowerBound
    }

    // MARK: Small descriptions

    private func positionText(_ document: GlassEditorDocument) -> String {
        let offset = document.model.selectedRange.lowerBound
        let line = document.model.lineIndex(forUTF16Offset: offset)
        let lineStart = document.model.lineRange(ofLine: line).lowerBound
        return "Line \(line + 1), Column \(offset - lineStart + 1)"
    }

    private func matchCountText(_ document: GlassEditorDocument) -> String {
        guard !workspace.findQuery.isEmpty else { return "" }
        guard let matches = try? document.model.matches(of: workspace.findQueryValue) else {
            return "Invalid pattern"
        }
        return matches.isEmpty ? "No matches" : "\(matches.count) match\(matches.count == 1 ? "" : "es")"
    }

    private func languageName(_ language: LanguageID) -> String {
        switch language {
        case .sql: "SQL"
        case .json: "JSON"
        case .bash: "Shell"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .markdown: "Markdown"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .go: "Go"
        case .rust: "Rust"
        case .c: "C"
        case .php: "PHP"
        case .swift: "Swift"
        case .xml: "XML"
        case .plaintext: "Plain Text"
        }
    }

    private func symbolName(for language: LanguageID) -> String {
        switch language {
        case .sql: "cylinder.split.1x2"
        case .json, .toml, .yaml: "curlybraces"
        case .bash: "terminal"
        case .markdown: "text.alignleft"
        case .python, .javascript, .go, .rust, .c, .php, .swift: "chevron.left.forwardslash.chevron.right"
        case .xml: "chevron.left.slash.chevron.right"
        case .plaintext: "doc.text"
        }
    }
}

/// Every sheet, alert and dialog this window can show, in one modifier.
///
/// Not a tidying: `body` holds enough modifiers that the type checker gives up on it, and reports
/// that as a timeout rather than as an error anyone can read — on iOS and visionOS first, because
/// those platforms carry a settings sheet the Mac does not (rule 32 again: the Mac built fine).
private struct GlassEditorDialogs: ViewModifier {
    let workspace: GlassEditorWorkspace
    @Binding var closeCandidate: GlassEditorDocument?
    @Binding var exportingDocument: GlassEditorDocument?
    @Binding var isGoingToLine: Bool
    @Binding var goToLineText: String
    @Binding var settingsProject: GlassEditorProject?
    @Binding var isShowingSettings: Bool
    let goToLine: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Editor", isPresented: Binding(get: { workspace.message != nil },
            set: { if !$0 { workspace.message = nil } })) {
            Button("OK", role: .cancel) { workspace.message = nil }
            } message: {
            Text(workspace.message ?? "")
            }
            .confirmationDialog("Close without saving?", isPresented: Binding(
            get: { closeCandidate != nil }, set: { if !$0 { closeCandidate = nil } }),
            titleVisibility: .visible, presenting: closeCandidate) { document in
            Button("Save", role: .none) {
            if document.hasNeverBeenSaved { exportingDocument = document }
            else { workspace.save(document.id); workspace.close(document.id, force: true) }
            closeCandidate = nil
            }
            Button("Discard Changes", role: .destructive) {
            workspace.close(document.id, force: true)
            closeCandidate = nil
            }
            Button("Cancel", role: .cancel) { closeCandidate = nil }
            } message: { document in
            Text("\(document.displayName) has changes that have not been saved.")
            }
            #if !os(macOS)
            .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
            GlassEditorSettingsView(preferences: workspace.preferences)
            .navigationTitle("Editor")
            .toolbar {
            ToolbarItem(placement: .cancellationAction) {
            Button("Done") { isShowingSettings = false }
            }
            }
            }
            }
            #endif
            .sheet(item: $settingsProject) { project in
            GlassEditorProjectSettingsView(workspace: workspace, project: project)
            }
            .alert("Go to Line", isPresented: $isGoingToLine) {
            TextField("Line", text: $goToLineText)
            #if !os(macOS)
            .keyboardType(.numberPad)
            #endif
            Button("Go") { goToLine(); isGoingToLine = false }
            Button("Cancel", role: .cancel) { isGoingToLine = false }
            }
    }
}

/// What an editor window does as it comes and goes, in one modifier because `body` cannot hold
/// another chained one without the type checker giving up (it reports that as a timeout, not as an
/// error anyone can read).
private struct GlassEditorWindowLifecycle: ViewModifier {
    let workspace: GlassEditorWorkspace
    let runtime: GlassEditorRuntime?
    let windowID: UUID
    let colorScheme: ColorScheme
    @Binding var columnVisibility: NavigationSplitViewVisibility
    // Which window is in front. `controlActiveState` is macOS-only — a window in a headset or on a
    // phone is not "key" in that sense — so elsewhere the last window to appear is the front one,
    // which is true on those platforms anyway.
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #endif

    func body(content: Content) -> some View {
        content
            // Which window a file opened from the menu bar lands in: the one in front.
            .onAppear { runtime?.noteFrontmost(windowID) }
            #if os(macOS)
            .onChange(of: activeState) { _, state in
                if state == .key { runtime?.noteFrontmost(windowID) }
            }
            #endif
            .onDisappear { runtime?.forget(windowID) }
            // **The text follows the system's appearance.** `GlassEditorModel` defaults to the dark
            // theme; nothing ever changed it, so in Light mode the chrome went light and the text
            // sat in a dark rectangle in the middle of it. The engine is right not to read the
            // environment itself — a model is not a view — so the view tells it.
            .onAppear {
                workspace.preferences.prefersDarkTheme = colorScheme == .dark
                workspace.applyAppearance()
            }
            .onChange(of: colorScheme) { _, scheme in
                workspace.preferences.prefersDarkTheme = scheme == .dark
                workspace.applyAppearance()
            }
            // A preference changed in another window reaches this one's documents too.
            .onChange(of: workspace.preferences.showsLineNumbers) { _, _ in workspace.applyAppearance() }
            .onChange(of: workspace.preferences.wrapsLines) { _, _ in workspace.applyAppearance() }
            .onChange(of: workspace.preferences.fontSize) { _, _ in workspace.applyAppearance() }
            // Closing the window is how a project is closed — "I am done with this project" — so
            // there is no Close Project command to find. Documents are untouched: a file open in a
            // tab is work, and work is not thrown away by closing a window showing a folder.
            .onDisappear { workspace.closeAllProjects() }
            // A file opened on its own collapses the tree, because a project column with no project
            // in it is a stripe of empty space beside the text.
            .onChange(of: workspace.prefersCollapsedSidebar) { _, collapsed in
                columnVisibility = collapsed ? .detailOnly : .all
            }
            // A window that opens onto an existing project shows the tree; a new, empty one does
            // not, and neither does one showing a single file.
            .onAppear {
                if !workspace.projects.isEmpty { columnVisibility = .all }
            }
    }
}

#if os(macOS)
/// What an editor window is on a Mac, apart from its content: ⌘W closes the document rather than
/// the window, the menu bar can ask what this window can do, it has a floor for its size, and it
/// remembers where it was.
private struct MacEditorWindowBehaviour: ViewModifier {
    let actions: GlassEditorActions
    let canCloseDocument: Bool
    let closeDocument: () -> Void

    func body(content: Content) -> some View {
        content
            // ⌘W closes the document, and **the window when there is no document** — an editor
            // showing a project and no tabs is done with, and ⌘W is how you say so.
            //
            // Always enabled, deliberately: a registration that is present but disabled makes the
            // router *consume* Close and do nothing (it exists so a database's permanent Overview
            // tab cannot be closed by accident), which left ⌘W inert in an empty editor window.
            .glassCloseCommandTarget(priority: .workspace, isEnabled: true) {
                if canCloseDocument { closeDocument() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .focusedSceneValue(\.glassEditorActions, actions)
            .frame(minWidth: 820, minHeight: 520)
            .background { GlassEditorWindowFrameMemory() }
    }
}
#endif

#if os(macOS)
/// Remembers where the editor window was and how big it was.
///
/// A SwiftUI `WindowGroup` restores a window's frame through state restoration, which does not run
/// for a scene declared with `.defaultLaunchBehavior(.suppressed)` — the editor never opens at
/// launch, so it was always built fresh at the default size. AppKit's own autosave is what remains,
/// and it is one line.
///
/// One name, deliberately: the frame is a property of *the editor*, not of a particular window, so
/// a second editor window opens the size of the last one and AppKit cascades it clear of the first.
private struct GlassEditorWindowFrameMemory: NSViewRepresentable {
    static let autosaveName = "com.glasspowertools.editor.window"

    func makeNSView(context: Context) -> NSView {
        let view = FrameMemoryView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FrameMemoryView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Set once. Assigning the name a second time to the same window is harmless, but
            // assigning it while the window is being torn down is not worth finding out about.
            guard window.frameAutosaveName != GlassEditorWindowFrameMemory.autosaveName else { return }
            window.setFrameAutosaveName(GlassEditorWindowFrameMemory.autosaveName)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

/// One level of a project tree, and the level under it.
///
/// Built the way the database's schema browser builds databases and tables
/// (`SchemaBrowserView.schemaTree`): a `DisclosureGroup` per folder with its expansion **owned by
/// the model**, a tagged row so the list can select it, single click to select and double click to
/// open. `OutlineGroup` was doing the drawing before, and it owns its own expansion state, which is
/// why nothing outside the view could open a folder — the keyboard included.
private struct GlassEditorTreeRows: View {
    let workspace: GlassEditorWorkspace
    let nodes: [GlassEditorProjectNode]
    let filter: String
    let open: (GlassEditorProjectNode) -> Void

    private var visible: [GlassEditorProjectNode] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ForEach(visible) { node in
            if node.isDirectory {
                DisclosureGroup(isExpanded: Binding(
                    get: { workspace.isExpanded(node.id) },
                    set: { workspace.setExpanded($0, for: node.id) })) {
                    GlassEditorTreeRows(workspace: workspace, nodes: node.children ?? [],
                                        filter: filter, open: open)
                } label: {
                    row(node, symbol: "folder")
                }
                .tag(GlassEditorSidebarSelection.node(node.id))
            } else {
                row(node, symbol: "doc")
                    .tag(GlassEditorSidebarSelection.node(node.id))
            }
        }
    }

    private func row(_ node: GlassEditorProjectNode, symbol: String) -> some View {
        // **The row is as wide as the column, not as wide as the filename.**
        //
        // A bare `Label` is only as wide as its text, and `contentShape` shapes what is there — so a
        // click to the right of a short name landed on nothing and selected nothing. Verified in the
        // running app: clicking a row left the list with no selection at all. The database's rows
        // have always been an `HStack` ending in a `Spacer`, which is also where the trailing fact
        // about a row goes.
        HStack(spacing: 0) {
            // The list's own font, as the schema browser's table rows use — `rowSubtitleFont` is
            // `.caption` on a Mac, which made a file tree read like a footnote.
            Label(node.name, systemImage: symbol)
            Spacer(minLength: 0)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSpatialRowMetrics()
            .glassGazeHighlight()
            .contentShape(Rectangle())
            // **Single click selects, double click opens** — and the single click has to be said
            // out loud. Verified in the running app: with only the double-click gesture attached,
            // clicking a row moved AppKit's own selection but never reached the model, so Return
            // did nothing and the current folder stayed wherever the keyboard had last left it.
            // The database's schema browser has always done both (`SchemaBrowserView.tableRow`).
            .onTapGesture { workspace.sidebarSelection = .node(node.id) }
            #if os(macOS)
            .simultaneousGesture(TapGesture(count: 2).onEnded { open(node) })
            #endif
            .contextMenu {
                Button(node.isDirectory ? "Open Folder" : "Open") { open(node) }
                if node.isDirectory {
                    Button("Refresh") {
                        node.invalidate()
                        workspace.setExpanded(true, for: node.id)
                    }
                }
            }
            .accessibilityIdentifier("editor-file-\(node.name)")
    }
}

private extension LineEndingStyle {
    /// What the status bar calls it. A mixed file says so — silently normalising one is how an
    /// editor turns a one-line change into a whole-file diff, and the engine deliberately does not.
    var statusName: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        case .mixed(let dominant): "Mixed (\(dominant.rawValue.uppercased()))"
        }
    }
}

/// Only what `fileExporter` needs to write a document the user is choosing a home for. The real
/// save path is `AtomicSaver` in `GlassEditorDocument`; this one exists because the save panel
/// insists on writing the first copy itself.
struct GlassEditorTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .text, .sourceCode]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
