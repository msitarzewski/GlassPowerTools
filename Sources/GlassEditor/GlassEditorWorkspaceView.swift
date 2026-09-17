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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isImporting = false
    @State private var isImportingProject = false
    @State private var exportingDocument: GlassEditorDocument?
    @State private var closeCandidate: GlassEditorDocument?
    @State private var isGoingToLine = false
    @State private var goToLineText = ""

    public init(workspace: GlassEditorWorkspace) {
        self.workspace = workspace
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
        .alert("Go to Line", isPresented: $isGoingToLine) {
            TextField("Line", text: $goToLineText)
                #if !os(macOS)
                .keyboardType(.numberPad)
                #endif
            Button("Go") { goToLine(); isGoingToLine = false }
            Button("Cancel", role: .cancel) { isGoingToLine = false }
        }
        // ⌘N in an editor window means a new document; the shell owns the one File ▸ New item and
        // each window says what it makes (`GlassShellFileCommands`).
        .focusedSceneValue(\.glassNewItem, GlassNewItemAction(title: "New Document") {
            workspace.newDocument()
        })
        #if os(macOS)
        .focusedSceneValue(\.glassEditorActions, GlassEditorActions(
            canSave: workspace.selectedDocument?.isDirty == true,
            open: { isImporting = true },
            save: { saveSelected() },
            find: { workspace.findIsPresented = true },
            goToLine: { goToLineText = ""; isGoingToLine = true }))
        .frame(minWidth: 820, minHeight: 520)
        #endif
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $workspace.selection) {
            ForEach(workspace.projects) { project in
                Section {
                    if let root = workspace.projectRoots[project.id] {
                        OutlineGroup(root.children ?? [], id: \.id, children: \.loadedChildren) { node in
                            projectRow(node)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(project.displayName)
                        if let reach = workspace.projectReach[project.id] {
                            // The badge the user asked for: which machine these files are on, and
                            // how this device is reaching them.
                            Label(reach.badge, systemImage: reach.symbolName)
                                .font(.caption2)
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Menu {
                            Button("Refresh") { workspace.refreshProject(project.id) }
                            Button("Close Project", role: .destructive) { workspace.closeProject(project.id) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .font(GlassSpatialMetrics.sectionHeaderFont)
                }
            }
            Section("Open") {
                if workspace.documents.isEmpty {
                    Text("No documents open.")
                        .font(GlassSpatialMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                }
                ForEach(workspace.documents) { document in
                    documentRow(document)
                        .tag(document.id)
                        .contextMenu {
                            Button("Save") { workspace.save(document.id) }
                                .disabled(!document.isDirty)
                            Button("Save As…") { exportingDocument = document }
                            Button("Close", role: .destructive) { requestClose(document) }
                        }
                }
            }
            if !workspace.recents.isEmpty {
                Section("Recent") {
                    ForEach(workspace.recents.prefix(8), id: \.self) { url in
                        Button { workspace.open(url) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                    .font(GlassSpatialMetrics.rowSubtitleFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        .buttonStyle(.plain)
                        .glassSpatialRowMetrics()
                        .glassGazeHighlight()
                    }
                    Button("Clear Recents") { workspace.clearRecents() }
                        .font(GlassSpatialMetrics.rowSubtitleFont)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Editor")
    }

    /// One entry in a project tree. A folder loads its children the first time it is expanded; a
    /// file opens into the editor.
    @ViewBuilder
    private func projectRow(_ node: GlassEditorProjectNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .font(GlassSpatialMetrics.rowSubtitleFont)
                .glassSpatialRowMetrics()
                .onAppear { node.loadChildrenIfNeeded(using: GlassEditorLocalDirectoryReader()) }
        } else {
            Button {
                workspace.open(URL(filePath: node.path))
            } label: {
                Label(node.name, systemImage: "doc")
                    .font(GlassSpatialMetrics.rowSubtitleFont)
            }
            .buttonStyle(.plain)
            .glassSpatialRowMetrics()
            .glassGazeHighlight()
            .accessibilityIdentifier("editor-file-\(node.name)")
        }
    }

    private func documentRow(_ document: GlassEditorDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName(for: document.model.language))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName)
                    .font(GlassSpatialMetrics.rowTitleFont)
                    .lineLimit(1)
                if let location = document.locationDescription {
                    Text(location)
                        .font(GlassSpatialMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            // The one mark that matters in a list of documents: this one has unsaved work.
            if document.isDirty {
                Circle().fill(.tint).frame(width: 7, height: 7)
                    .accessibilityLabel("Unsaved changes")
            }
        }
        .glassSpatialRowMetrics()
        .glassGazeHighlight()
        .accessibilityIdentifier("editor-document-\(document.displayName)")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let document = workspace.selectedDocument {
            VStack(spacing: 0) {
                if workspace.findIsPresented { findBar(document) ; Divider() }
                GlassEditorView(model: document.model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar(document)
            }
        } else {
            ContentUnavailableView {
                Label("No Document", systemImage: "text.page")
            } description: {
                Text("Open a file, drop one on this window, or start something new.")
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
        .padding(.vertical, GlassSpatialMetrics.isSpatial ? 12 : 6)
        .glassActionBarSurface()
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Document", systemImage: "doc.badge.plus") { workspace.newDocument() }
                Button("Open…", systemImage: "doc") { isImporting = true }
                Button("Open Project…", systemImage: "folder") { isImportingProject = true }
            } label: {
                Label("New", systemImage: "plus")
            }
            .accessibilityIdentifier("editor-new")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Find", systemImage: "magnifyingglass") {
                workspace.findIsPresented.toggle()
            }
            .disabled(workspace.selectedDocument == nil)
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
        case .plaintext: "Plain Text"
        }
    }

    private func symbolName(for language: LanguageID) -> String {
        switch language {
        case .sql: "cylinder.split.1x2"
        case .json, .toml, .yaml: "curlybraces"
        case .bash: "terminal"
        case .markdown: "text.alignleft"
        case .python, .javascript, .go, .rust, .c, .php: "chevron.left.forwardslash.chevron.right"
        case .plaintext: "doc.text"
        }
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
