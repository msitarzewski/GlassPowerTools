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
#if os(iOS)
import UIKit
#endif
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Where the phone is: the folders it has been pushed through, and the document when one is
    /// open. Empty means the root — the project's own folder, or the document in a window that
    /// has no project.
    @State private var compactPath: [GlassEditorCompactRoute] = []
    #endif
    /// Open… off the Mac: one picker for files and folders.
    @State private var isImporting = false
    @State private var exportingDocument: GlassEditorDocument?
    /// The document the save panel was opened for, kept apart from `exportingDocument` because the
    /// panel's own dismissal clears that — and when the dismissal came first, the completion found
    /// nothing, wrote the file and never adopted it: the tab stayed "Untitled" and dirty over a file
    /// that existed (2026-09-25, a new `.env`).
    @State private var exportTarget: GlassEditorDocument.ID?
    /// Counts closes called off, so the Mac window knows ⌘W's close of its last document is off.
    @State private var closeCancellations = 0
    /// A new document choosing its first location among the window's projects.
    @State private var firstSave: GlassEditorFirstSave?
    @State private var closeCandidate: GlassEditorDocument?
    @State private var isGoingToLine = false
    @State private var goToLineText = ""
    @State private var filter = ""
    @State private var settingsProject: GlassEditorProject?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    // Optional: the scene injects it, and a preview or a test may not.
    @Environment(GlassEditorRuntime.self) private var runtime: GlassEditorRuntime?
    /// **This window's** settings, then this file's and every editor's, from the gear in the
    /// toolbar — on every platform (`GlassEditorSettingsSheet`, W23). The Mac's gear used to be a
    /// `SettingsLink` to the app's Settings window, which is a keystroke away at ⌘, and did not
    /// need a toolbar button; what a window's toolbar is good for is the thing in that window
    /// (2026-09-18).
    @State private var isShowingSettings = false
    #if os(iOS)
    /// Whether the software keyboard is up, so the control in the status bar can say which way it
    /// goes. Read from the system's own notifications rather than from a flag this view sets: the
    /// keyboard also goes away by a swipe, by a hardware keyboard appearing, and by the app going
    /// to the background, and a button that disagrees with the screen is worse than no button.
    @State private var keyboardIsUp = false
    #endif

    /// This window's id, which is also its workspace's. The runtime is told when the window comes
    /// forward, so a file opened from the menu bar lands where the user is looking.
    private let windowID: UUID

    /// How to leave, on a platform where this is a presentation rather than a window.
    ///
    /// Nil on a Mac, where a window is closed by closing it. Not a `NavigationStack` wrapped
    /// around this view: a `NavigationSplitView` inside a `NavigationStack` draws its toolbar and
    /// none of its content on an iPhone — a black screen under a working navigation bar, which is
    /// exactly what it did.
    private let dismissal: GlassEditorDismissal?

    public init(workspace: GlassEditorWorkspace, windowID: UUID = UUID(),
                dismissal: GlassEditorDismissal? = nil) {
        self.workspace = workspace
        self.windowID = windowID
        self.dismissal = dismissal
    }

    public var body: some View {
        // On the headset the window draws Apple's glass itself, at Glass, and Opacity paints the
        // theme colour over it edge to edge in its shape (`GlassEditorWorkspace.navigationOpacity`);
        // its columns are our own (`spatialLayout`), because the split view's system glass could
        // not be cleared (W33). W28 had painted the text's column as a canvas set in from the
        // window's edges, which read as a dark panel.
        GlassLayeredWindow(paintsTheme: GlassWindowGlass.paintsTheme(GlassEditorWorkspace.navigationOpacity)) {
            #if os(iOS)
            // **A phone is not a narrow Mac.** `NavigationSplitView` collapses on a compact width
            // into a single stack showing its *sidebar* first — so an editor opened on a file
            // arrived as an empty list under a navigation bar carrying the file's name: the title
            // was there and the document was one push away, behind a column with nothing in it
            // (reported 2026-09-17). The library has always branched here
            // (`GlassConnectionLibrary.body`); the editor never did.
            if horizontalSizeClass == .compact { compactLayout } else { splitLayout }
            #elseif os(visionOS)
            spatialLayout
            #else
            splitLayout
            #endif
        }
        #if os(visionOS)
        // **In the window's shape.** A plain window gives its content none, so the status line's
        // bar, square, filled the window's bottom corners outside its rounded glass (the owner, on
        // the headset, 2026-10-14: "The Editor window's bottom corners show a square background").
        // The toolbar below the window is an ornament, outside this.
        .clipShape(RoundedRectangle(cornerRadius: GlassWindowShape.spatialWindowCornerRadius, style: .continuous))
        // Behind the paint, out to the window's edges: as much of Apple's glass as the window's
        // Glass asks for, none at 0 (`GlassSpatialWindowGlass`).
        .glassSpatialWindowGlass()
        // Shrinks into an orb (2026-10-15); a document has no picture yet, so its symbol.
        .glassSessionOrb(GlassSessionOrbFace(title: detailTitle, symbolName: "doc.text") { nil })
        #endif
        // **The text follows the system's appearance.** `GlassEditorModel` defaults to the dark
        // theme and nothing ever changed it, so in Light mode the window's chrome went light and the
        // text sat in a dark rectangle in the middle of it. The engine is right not to read the
        // environment itself — a model is not a view — so the view tells it, on appearance and on
        // every change after.
        // **Editing a file is committing to it.** The provisional tab stops being provisional the
        // moment there is something in it worth losing — which is the rule every editor with this
        // pattern uses, and the reason a preview can be replaced without a prompt.
        .onChange(of: workspace.selectedDocument?.isDirty ?? false) { _, isDirty in
            if isDirty, let id = workspace.selection { workspace.makePermanent(id) }
        }
        .modifier(GlassEditorWindowLifecycle(workspace: workspace,
                                             runtime: runtime,
                                             windowID: windowID,
                                             colorScheme: colorScheme,
                                             columnVisibility: $columnVisibility,
                                             isShowingSettings: $isShowingSettings))
        // Drop a file on the window to open it — the gesture a Mac user tries first, and the one
        // that works in the headset and on an iPad too. A folder dropped is a project, by the same
        // rule as Open…: its own window, unless this one is blank.
        .dropDestination(for: URL.self) { urls, _ in
            open(urls)
            return !urls.isEmpty
        }
        .modifier(GlassEditorOpenImporter(isPresented: $isImporting,
                                          open: { open($0) },
                                          failed: { workspace.message = $0.localizedDescription }))
        .fileExporter(isPresented: Binding(get: { exportingDocument != nil },
                                           set: { if !$0 { exportingDocument = nil } }),
                      document: exportingDocument.map { GlassEditorTextFile(text: $0.model.text) },
                      contentType: .plainText,
                      defaultFilename: exportingDocument?.displayName) { result in
            if case .success(let url) = result, let id = exportTarget {
                // `fileExporter` has already written the bytes; adopting the location is what makes
                // the tab take the file's name and the next ⌘S go there rather than asking again.
                Task { await workspace.save(id, to: url) }
            }
            exportTarget = nil
            exportingDocument = nil
        }
        .onChange(of: exportingDocument?.id) { _, id in
            if let id { exportTarget = id }
        }
        .modifier(GlassEditorDialogs(workspace: workspace,
                                     closeCandidate: $closeCandidate,
                                     exportingDocument: $exportingDocument,
                                     isGoingToLine: $isGoingToLine,
                                     goToLineText: $goToLineText,
                                     settingsProject: $settingsProject,
                                     isShowingSettings: $isShowingSettings,
                                     goToLine: goToLine,
                                     closeCancelled: { closeCancellations += 1 },
                                     firstSave: $firstSave,
                                     saveOutsideProjects: { saveOutsideProjects($0, closesAfterSaving: $1) }))
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
            saveItem: saveItem,
            canCloseDocument: workspace.selectedDocument != nil,
            documentCount: workspace.documents.count,
            hasProjects: !workspace.projects.isEmpty,
            closeCancellations: closeCancellations,
            closeDocument: { if let document = workspace.selectedDocument { requestClose(document) } },
            unsavedCount: workspace.documents.filter(\.isDirty).count,
            firstUnsaved: { workspace.documents.first(where: \.isDirty) },
            isAsking: { closeCandidate != nil || firstSave != nil },
            askToClose: { document in
                workspace.selection = document.id
                requestClose(document)
            }))
        #endif
        // **The window's own settings, for everything in it** (W23): outermost, so the window's
        // glass (`GlassLayeredWindow`), its panels and its sheets all draw with them.
        .glassWindowOverrides(workspace.windowSettings)
    }

    #if os(macOS)
    /// ⌘S for the document in front. "Save…" when it has never been saved, because then a panel
    /// asks where — and enabled for an untitled document even before it is edited, since choosing
    /// where a new file lives is a reason to save on its own. Nothing to save is a viewer, or no
    /// document at all.
    private var saveItem: GlassSaveItemAction? {
        guard let document = workspace.selectedDocument, document.viewer == nil else { return nil }
        return GlassSaveItemAction(title: document.hasNeverBeenSaved ? "Save…" : "Save",
                                   isEnabled: document.hasNeverBeenSaved || document.isDirty) {
            saveSelected()
        }
    }

    /// Built here rather than inline in `body`: the whole expression is one literal with several
    /// closures in it, and the type checker gives up on the chain it sits in.
    private var editorActions: GlassEditorActions {
        // The size this window follows: its own when it keeps one (W23), else every window's.
        GlassEditorActions(
            increaseFontSize: { workspace.adjustFontSize(by: 1) },
            decreaseFontSize: { workspace.adjustFontSize(by: -1) },
            resetFontSize: { workspace.resetFontSize() },
            find: { workspace.findIsPresented = true },
            goToLine: { goToLineText = ""; isGoingToLine = true })
    }
    #endif

    #if !os(visionOS)
    /// Two columns, for a Mac and an iPad. The headset draws its own (`spatialLayout`).
    @ViewBuilder
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: GlassLibraryColumnLayout.navigationMinimum,
                                                ideal: GlassLibraryColumnLayout.navigationIdeal,
                                                max: GlassLibraryColumnLayout.navigationMaximum)
        } detail: {
            GlassLayeredPanel(cornerRadius: 0, role: .embedded) { detail }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { toolbarContent(includingDismissal: true) }
        .glassActiveConnectionsToolbar(show: runtime?.showActiveConnections, dismissCurrent: dismissal?.action)
        // **No sidebar without a project.** The sidebar is the project's file tree and holds
        // nothing else — open documents are tabs. With no project open, the control offered to
        // reveal a column that could only ever be blank, so the control goes too: a toggle whose
        // only outcome is an empty stripe is a promise the window cannot keep.
        //
        // Nobody is stranded by it. Opening a project is Open… — File ▸ Open… (⌘O) on a Mac, the
        // toolbar elsewhere, and a button on the empty document view — none of which is in the
        // sidebar.
        .toolbar(removing: workspace.projects.isEmpty ? .sidebarToggle : nil)
    }
    #endif

    #if os(visionOS)
    /// **The file list beside the text, in our own columns** (W33; the owner, 2026-10-10: "Yes,
    /// all four"). The split view drew system glass that no setting could clear; here the window
    /// draws its own (`body`). The file list is titled "Files" with its filter field in its header
    /// (W32 gave it that title); the text's column names what is open and carries the sidebar
    /// toggle — only with a project, because the list is its tree — and the ⚡. The window's other
    /// actions stay in the bottom toolbar ornament (`editorLeading`, `editorTrailing`).
    private var spatialLayout: some View {
        GlassSpatialSplitView(visibility: $columnVisibility, showsToggle: !workspace.projects.isEmpty) {
            sidebar
        } content: {
            GlassLayeredPanel(cornerRadius: 0, role: .embedded) { detail }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSpatialColumn(detailTitle)
                // Nothing before the title but the toggle: on the headset an editor is always a
                // window, never a presentation with a way out (`dismissal` is a phone's).
                .glassSpatialColumnChrome {
                    if let show = runtime?.showActiveConnections {
                        GlassActiveConnectionsButton { show() }
                    }
                }
                // The window's actions: Apple's toolbar ornament below the window, as before.
                .toolbar { toolbarContent(includingDismissal: false) }
        }
    }

    /// What the text's column is titled: the document in front, else the project, else the
    /// window — the navigation titles the split view's detail had.
    private var detailTitle: String {
        if let document = workspace.selectedDocument { return document.displayName }
        if let project = workspace.projects.first { return project.displayName }
        return "Editor"
    }
    #endif

    #if os(iOS)
    /// One thing at a time, for a phone: the folder you are in, and what you choose from it.
    ///
    /// **Opening a folder lands on its files.** It used to land on the editor's empty state —
    /// *"Choose a file from the project to start editing"* — with the file list behind a toolbar
    /// toggle, so the one thing the user had just asked for was the one thing not on screen
    /// (reported 2026-09-18). Opening a *file* still goes straight to the editor, because there
    /// the file is what was chosen; a window with no project has no folder to show.
    ///
    /// **Nothing here is a modal.** The tree was a sheet over a document that was itself a
    /// full-screen cover: two dismissals to think about, and neither surface reading as a place
    /// you *are*. One stack, pushes, and the back button — the navigation `SFTPBrowserView`
    /// already has, which is the browser this one is compared to.
    ///
    /// The `Files` toolbar button goes with the sheet. A control to reveal something that is no
    /// longer hidden is a control for nothing.
    @ViewBuilder
    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            compactRoot
                .navigationDestination(for: GlassEditorCompactRoute.self) { route in
                    switch route {
                    case .folder(let id): compactFolder(id)
                    case .document: documentScreen
                    }
                }
        }
        // A document opened from anywhere — the tree, a drop, the menu bar, the remote screen's
        // own `task` — is a push, so one rule covers all of them rather than each caller
        // remembering to navigate.
        .onChange(of: workspace.selection) { _, selection in showDocument(ifOpen: selection) }
        .task { showDocument(ifOpen: workspace.selection) }
    }

    /// The project's own folder, or the document when this window has no project — which is what
    /// the Files browser's Edit opens.
    @ViewBuilder
    private var compactRoot: some View {
        if let project = workspace.projects.first, let root = workspace.projectRoots[project.id] {
            compactFolder(root)
        } else {
            documentScreen
        }
    }

    @ViewBuilder
    private func compactFolder(_ id: UUID) -> some View {
        if let node = workspace.node(id) {
            compactFolder(node)
        } else {
            // The project was closed while this screen was on the stack. Say so rather than
            // showing an empty list that looks like an empty folder.
            ContentUnavailableView("Folder Unavailable", systemImage: "folder.badge.questionmark",
                                   description: Text("Its project is no longer open."))
        }
    }

    private func compactFolder(_ node: GlassEditorProjectNode) -> some View {
        GlassEditorFolderList(workspace: workspace, folder: node, filter: filter,
                              open: { openFromFolderList($0, asPreview: false) },
                              preview: { openFromFolderList($0, asPreview: true) })
            // The shared header, the same one the Files browser shows: this folder's name, and
            // the path to it beneath. `~` for home, because a header is not the place to read
            // someone's user name back to them.
            .glassPathHeader(abbreviated(node.path))
            .glassSpatialList()
        .safeAreaInset(edge: .bottom, spacing: 0) { projectFooter }
            .searchable(text: $filter, prompt: "Filter")
            // The dismissal chevron belongs to the first screen only; every screen after it has
            // the stack's own back button, and two back controls in one bar is a puzzle.
            .toolbar { toolbarContent(includingDismissal: compactPath.isEmpty) }
            .glassActiveConnectionsToolbar(show: runtime?.showActiveConnections, dismissCurrent: dismissal?.action)
            .task {
                // Reads the folder the first time it is opened, through whichever reader its
                // project was opened with — the same call the disclosure triangle makes.
                workspace.setExpanded(true, for: node.id)
                // Where you are is what "here" means to New and to the project footer.
                workspace.sidebarSelection = .node(node.id)
            }
    }

    private var documentScreen: some View {
        GlassLayeredPanel(cornerRadius: 0, role: .embedded) { detail }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { toolbarContent(includingDismissal: compactPath.isEmpty) }
            .glassActiveConnectionsToolbar(show: runtime?.showActiveConnections, dismissCurrent: dismissal?.action)
    }

    /// Choosing a file from the list: select it, open it, and push the editor.
    ///
    /// The push is here as well as in `onChange` because opening a file that is **already open**
    /// leaves `selection` where it was, and a tap that changes nothing would be a tap that does
    /// nothing. Both routes are guarded, so neither can push twice.
    private func openFromFolderList(_ node: GlassEditorProjectNode, asPreview: Bool) {
        workspace.sidebarSelection = .node(node.id)
        Task {
            guard await workspace.open(path: node.path, asPreview: asPreview) != nil else { return }
            showDocument(ifOpen: workspace.selection)
        }
    }

    private func showDocument(ifOpen selection: GlassEditorDocument.ID?) {
        // With no project the document is the root; there is nothing to push it onto.
        guard selection != nil, !workspace.projects.isEmpty,
              compactPath.last != .document else { return }
        compactPath.append(.document)
    }
    #endif

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $workspace.sidebarSelection) {
            ForEach(workspace.projects) { project in
                Section {
                    if let root = workspace.projectRoots[project.id] {
                        GlassEditorTreeRows(workspace: workspace, nodes: root.children ?? [],
                                            filter: filter, open: activate, preview: preview)
                    }
                }
                // No header. The project's name and where it is are in the **title bar** now, and
                // repeating them over the file list said the same two facts twice in one window
                // (2026-09-17). The machine badge lives in Project Settings, which is the place
                // that can also change it.
            }
        }
        // Bare rows in the headset's own sidebar column, as the system's sidebar drew them (W33).
        .glassSpatialList()
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { projectFooter }
        // A field, not a button. The connections list and the schema browser both filter their
        // list from a real search field (`GlassLibraryResults`, `SchemaBrowserView`); the editor
        // had a magnifying-glass button that toggled the find bar, which is a different act
        // entirely and is still on ⌥⌘F and in the Text menu.
        // `.sidebar` placement, so it is a field standing in the list — the "Filter" field the
        // connections window shows. Left to itself the modifier collapses into a magnifying glass
        // in the toolbar at this window width, which is the button this was meant to replace.
        // On the headset the field is in the column's header (`glassSpatialColumn`, below).
        #if !os(visionOS)
        .searchable(text: $filter, placement: .sidebar, prompt: "Filter")
        #endif
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
        // **"Files", with its filter, on the headset** (W32 titled the column; W33 draws the
        // header itself, where there is no navigation bar): what the list is, while the text's
        // column names what is open.
        .glassSpatialColumn("Files", search: GlassSpatialSearch(text: $filter, prompt: "Filter",
                                                                 accessibilityIdentifier: "editor-files-filter"))
    }

    /// **The project's own controls, at the foot of its own list.** Refresh was buried in a "…"
    /// menu on the section header, and the gear in the toolbar is the *app's* settings — this one
    /// is the project's, which is a different thing and belongs beside its files.
    ///
    /// Shown under the tree on a Mac, an iPad and in the headset, and under every folder screen on
    /// a phone — one footer, wherever the project's files are.
    @ViewBuilder
    private var projectFooter: some View {
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
            // **A surface, after all.** This footer painted nothing, on the reasoning that the
            // sidebar is glass and a divider is separation enough. A divider separates; it does
            // not *cover* — the file list scrolled through the footer and a filename sat behind
            // the gear (photographed 2026-09-18). `.bar` is what the editor's own status line
            // uses, one window across.
            .background(.bar)
        }
    }

    /// What sits under the file's name in the title bar: the project and where it is, the way the
    /// terminal puts `user@192.0.2.10:22` under "Terminal on alpha". A file opened on its own
    /// says where it is instead — the folder is the useful fact either way.
    private func subtitle(for document: GlassEditorDocument) -> String {
        if let project = workspace.projects.first {
            return "\(project.displayName) — \(abbreviated(project.path))"
        }
        guard let url = document.url else { return "" }
        return abbreviated(url.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// `~` for home, because a title bar is not the place to read someone's user name back to
    /// them. The Files browser's header wants the same spelling, so the rule lives in
    /// `GlassPathLocation` and both ask it.
    private func abbreviated(_ path: String) -> String {
        GlassPathLocation.abbreviatingHome(path)
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

    /// Opening a file **deliberately** — a double click, Return, ⌘↓, Open in the context menu.
    /// The file is kept (`GlassEditorWorkspace.previewDocumentID`).
    private func activate(_ node: GlassEditorProjectNode) {
        if node.isDirectory {
            workspace.setExpanded(!workspace.isExpanded(node.id), for: node.id)
        } else {
            // By path, not by URL: the file may be on another machine, and the workspace resolves
            // which one from the project the path belongs to.
            Task { await workspace.open(path: node.path) }
        }
    }

    /// One click: show it, provisionally. The next single click takes the same tab, so reading
    /// down a folder leaves one tab behind rather than twenty.
    private func preview(_ node: GlassEditorProjectNode) {
        guard !node.isDirectory else { return }
        Task { await workspace.open(path: node.path, asPreview: true) }
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
                                                  symbolName: document.viewer?.kind.symbolName
                                                      ?? symbolName(for: document.model.language),
                                                  isProvisional: workspace.isPreview(document.id),
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
                if workspace.findIsPresented, document.viewer == nil { findBar(document) ; Divider() }
                // **Identity, or the text never changes.** The engine deliberately observes its
                // model rather than being pushed values through `updateNSView`, so handing this
                // view a *different* model does not reach the text view that is already on screen —
                // it keeps rendering the first document opened. Seen in the running app with three
                // files open and the first one still showing. One identity per document, so
                // switching documents builds the engine that belongs to it.
                if let viewer = document.viewer {
                    // Not text: the file as what it is (`GlassEditorViewerView`).
                    GlassEditorViewerView(viewer: viewer) {
                        Task { await workspace.openAsText(document) }
                    }
                    .id(document.id)
                } else {
                    // Text, its preview beside it, or the preview alone — VS Code's three states.
                    let kind = workspace.previewKind(for: document)
                    let mode = kind == nil ? .text : (workspace.previewModes[document.id] ?? .text)
                    HStack(spacing: 0) {
                        if mode != .previewOnly {
                            GlassEditorView(model: document.model)
                                .id(document.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if mode == .beside { Divider() }
                        if mode != .text, let kind {
                            GlassEditorPreviewPane(document: document, kind: kind,
                                                   access: workspace.access(for: document),
                                                   root: workspace.previewRoot(for: document))
                                .id(document.id)
                        }
                    }
                }
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
                // A viewer has no lines, encoding or language to report.
                if document.viewer == nil {
                    VStack(spacing: 0) {
                        Divider()
                        statusBar(document)
                    }
                    .background(.bar)
                }
            }
        } else if let project = workspace.projects.first {
            // **A folder is open, so say what is in it.** Three ways to open something, shown to
            // someone who has just opened something, is the wrong offer (2026-09-18) — the agent
            // files, the readme, what builds it, and what you were last editing here are the
            // right one (`GlassEditorProjectOverview`).
            GlassEditorProjectOverview(workspace: workspace, project: project) { path in
                // A click here is a single click like any other: the file arrives in the
                // provisional tab and the next one takes its place.
                Task { await workspace.open(path: path, asPreview: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(project.displayName)
            #if os(macOS)
            .navigationSubtitle(abbreviated(project.path))
            #endif
        } else {
            // An editor with nothing in it — what ⇧⌘E and File ▸ New Editor make. Here the ways
            // in are the only thing to offer, and they are the whole point of the window. One
            // Open… for files and folders: a folder chosen here becomes this window's project.
            ContentUnavailableView {
                Label("No Document", systemImage: "text.page")
            } description: {
                Text("Open a file or a folder, drop one on this window, or start something new.")
            } actions: {
                Button("Open…") { beginOpening() }
                Button("New Document") { workspace.newDocument() }
            }
            #if os(visionOS)
            .font(.title3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            .navigationTitle("Editor")
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
            #if os(visionOS)
            // Where the file is: the Mac's window subtitle. A window on the headset has no subtitle,
            // and this line said it was here rather than dropped while nothing showed it.
            let location = subtitle(for: document)
            if !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .accessibilityIdentifier("editor-status-location")
            }
            #endif
            if document.isDirty {
                Text("Edited").font(.caption).foregroundStyle(.secondary)
            }
            #if os(iOS)
            // **Hide and show the keyboard**, as the terminal has always been able to. On a phone
            // the keyboard is half the window, and reading a file with it up is reading a third
            // of a file. The other half of this control is the bar above the keyboard itself
            // (`GlassEditorUIKitEngine.installKeyboardAccessory`).
            Button {
                document.model.requestKeyboard(!keyboardIsUp)
            } label: {
                Image(systemName: keyboardIsUp ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(keyboardIsUp ? "Hide Keyboard" : "Show Keyboard")
            .accessibilityIdentifier("editor-keyboard-toggle")
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsUp = false
        }
        #endif
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 24 : 14)
        // The same height as the sidebar's footer beside it — two bars at two heights in one
        // window reads as a mistake before anyone works out why.
        .frame(height: GlassSpatialMetrics.footerHeight)
        .glassActionBarSurface()
    }

    // MARK: Toolbar


    /// `includingDismissal` is false on a screen that already has the navigation stack's back
    /// button — its own chevron would be a second way back, pointing somewhere else.
    @ToolbarContentBuilder
    private func toolbarContent(includingDismissal: Bool) -> some ToolbarContent {
        // **Leading the content region, past the divider — left of the title.** The library puts
        // its own actions at `.navigation` (`GlassConnectionLibrary`, itself following glassdb's Add
        // Connection), and the editor putting everything in `.primaryAction` is most of why it read
        // as a different application.
        if let dismissal, includingDismissal {
            ToolbarItem(placement: .cancellationAction) {
                // A chevron naming where it goes back to, so the file's name is the only other
                // wording in the bar — the desktop session's decision, taken from glassDT, and
                // the same one applies here.
                Button(dismissal.title, systemImage: "chevron.backward", action: dismissal.action)
                    .labelStyle(.iconOnly)
            }
        }
        ToolbarItem(placement: .editorLeading) {
            Button("New Document", systemImage: "plus") { workspace.newDocument() }
                .help("New Document")
                .accessibilityIdentifier("editor-new")
        }
        #if !os(macOS)
        // **Open…, off the Mac**, with ⌘O for a hardware keyboard. The Mac has it in the File menu,
        // which owns ⌘O there (rule 39); here there is no menu, and the only ways in were two
        // buttons on an empty window, gone the moment anything was open.
        ToolbarItem(placement: .editorLeading) {
            Button("Open…", systemImage: "folder") { beginOpening() }
                .keyboardShortcut("o", modifiers: .command)
                .help("Open files, or a folder as a project")
                .accessibilityIdentifier("editor-open")
        }
        #endif
        // **A folder you can work in and cannot find again.** Every Open puts a folder in the
        // Projects list now, but one removed from the list while its window is open is still
        // here — offered back rather than re-added silently, because that list is the user's and
        // it syncs (`GlassSuggestionButton`).
        if let project = workspace.projects.first, let runtime, !runtime.isRemembered(project) {
            ToolbarItem(placement: .editorTrailing) {
                GlassSuggestionButton("Save as Project",
                                      help: "Keep \(project.displayName) in Projects, on this device and your others.") {
                    runtime.remember(project)
                }
                .accessibilityIdentifier("editor-save-as-project")
            }
        }
        // The gear is **this window's** settings first (W23) — its glass and its text — then this
        // file's and every editor's, in one sheet. The project's own are at the foot of the file
        // list, and the app's defaults are also in Settings ▸ Editor at ⌘,; the gear in this
        // window's toolbar belongs to what this window is showing.
        // **Preview**, for text that has a picture: beside the text, then alone, then back.
        if let document = workspace.selectedDocument, workspace.previewKind(for: document) != nil {
            let mode = workspace.previewModes[document.id] ?? .text
            ToolbarItem(placement: .editorTrailing) {
                Button(mode == .text ? "Show Preview" : (mode == .beside ? "Preview Only" : "Hide Preview"),
                       systemImage: mode == .text ? "eye" : (mode == .beside ? "rectangle.righthalf.filled" : "eye.slash")) {
                    workspace.previewModes[document.id] = mode.next(roomBeside: previewHasRoomBeside)
                }
                .help("Preview: beside the text, then alone, then off")
                .accessibilityIdentifier("editor-preview-toggle")
            }
        }
        ToolbarItem(placement: .editorTrailing) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                .help("Settings for this window and this file")
                .accessibilityIdentifier("editor-settings")
        }
        ToolbarItem(placement: .editorTrailing) {
            // Enabled for a document never saved, edited or not, as the Mac's ⌘S is: choosing where
            // a new file lives is a reason to save on its own.
            Button("Save", systemImage: "arrow.down.document") { saveSelected() }
                .disabled(!(workspace.selectedDocument.map { $0.hasNeverBeenSaved || $0.isDirty } ?? false))
                #if !os(macOS)
                // ⌘S with a keyboard, here where there is no File menu: on a never-saved document
                // it asks where (the owner, on the headset, 2026-10-15: "I'd like to just hit
                // command s on an unsaved text file to get the location prompt"). The Mac's ⌘S is
                // File ▸ Save's, its one owner (`GlassShellFileCommands`).
                .keyboardShortcut("s", modifiers: .command)
                #endif
                .accessibilityIdentifier("editor-save")
        }
        #if !os(macOS)
        // **Find, and Close, off the Mac** (help audit): the Mac has both in its menu bar (⌘F, ⌘W);
        // here the find bar had no way in, and with one document open there is no tab strip, so no
        // close button either. The same actions the Mac's menu calls.
        if let document = workspace.selectedDocument {
            ToolbarItem(placement: .editorTrailing) {
                Button("Find", systemImage: "magnifyingglass") { workspace.findIsPresented.toggle() }
                    .disabled(document.viewer != nil)
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityIdentifier("editor-find")
            }
            ToolbarItem(placement: .editorTrailing) {
                Button("Close Document", systemImage: "xmark") { requestClose(document) }
                    .accessibilityIdentifier("editor-close-document")
            }
        }
        #endif
    }

    /// A phone has no room for the text and its preview side by side.
    private var previewHasRoomBeside: Bool {
        #if os(iOS)
        horizontalSizeClass != .compact
        #else
        true
        #endif
    }

    // MARK: Actions

    /// Open…: the Mac's own panel, the system picker everywhere else.
    private func beginOpening() {
        #if os(macOS)
        if let runtime { show(GlassEditorOpenPanel.run(runtime: runtime, from: windowID)) }
        #else
        isImporting = true
        #endif
    }

    /// What was chosen or dropped, through the runtime's one rule (`open(urls:from:)`): files
    /// here, and each folder a project in a window of its own — this one, if it is blank.
    private func open(_ urls: [URL]) {
        guard let runtime else {
            // A preview with no runtime: everything here, which is all it can do.
            for url in urls { Task { await workspace.open(url) } }
            return
        }
        show(runtime.open(urls: urls, from: windowID))
    }

    /// Shows the windows an open named, other than this one: each as a window where windows
    /// exist; on a phone, the last of them in this one's place, since only one is on screen.
    private func show(_ windows: [UUID]) {
        runtime?.show(windows.filter { $0 != windowID }, with: openWindow)
    }

    private func saveSelected() {
        guard let document = workspace.selectedDocument else { return }
        guard document.hasNeverBeenSaved else {
            Task { await workspace.save(document.id) }
            return
        }
        // With a project open — here or on a server — the first save offers its folders.
        if !workspace.projects.isEmpty {
            firstSave = GlassEditorFirstSave(document: document, closesAfterSaving: false)
        } else {
            saveOutsideProjects(document, closesAfterSaving: false)
        }
    }

    /// The platform's own panel: the Mac's Save panel, the document exporter elsewhere.
    private func saveOutsideProjects(_ document: GlassEditorDocument, closesAfterSaving: Bool) {
        #if os(macOS)
        GlassEditorSavePanel.run(for: document) { url in
            Task {
                await workspace.save(document.id, to: url)
                if closesAfterSaving, !document.isDirty { workspace.close(document.id) }
            }
        } cancelled: {
            if closesAfterSaving { closeCancellations += 1 }
        }
        #else
        exportingDocument = document
        #endif
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
        case .html: "HTML"
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
        case .html: "chevron.left.slash.chevron.right"
        case .plaintext: "doc.text"
        }
    }
}

/// Where the editor window's own actions go.
///
/// The bar's leading and trailing edges on a Mac, an iPad and a phone. **On Vision Pro, the
/// window's toolbar ornament** below it — the system's, as the database's actions and Active's are
/// there (D40: system toolbars and ornaments first). Placed in the navigation bar they would be
/// small circles crowded into the window's top corner (`GlassConnectionLibrary.withLibraryToolbar`).
/// The ⚡ stays in the bar, where it is in every other window on the headset.
private extension ToolbarItemPlacement {
    static var editorLeading: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .navigation
        #endif
    }

    static var editorTrailing: ToolbarItemPlacement {
        #if os(visionOS)
        .bottomOrnament
        #else
        .primaryAction
        #endif
    }
}

/// The one Open… picker: files and folders together, decided by what is chosen.
///
/// There were two — files in one, a folder in the other — and the folder one never asked for
/// access to what it was given, so a folder from Files opened empty. Access is now the runtime's
/// to ask for and the project's to hold. `.data` is every file and `.folder` every folder.
private struct GlassEditorOpenImporter: ViewModifier {
    @Binding var isPresented: Bool
    let open: ([URL]) -> Void
    let failed: (any Error) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder, .data],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): open(urls)
                case .failure(let error): failed(error)
                }
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
    /// The close was called off — Cancel in the question, or in the Save panel it led to.
    let closeCancelled: () -> Void
    @Binding var firstSave: GlassEditorFirstSave?
    let saveOutsideProjects: (GlassEditorDocument, Bool) -> Void

    func body(content: Content) -> some View {
        content
            // A remote media file big enough to ask before it is downloaded.
            .confirmationDialog("Download this file?", isPresented: Binding(
            get: { workspace.pendingLargeOpen != nil }, set: { if !$0 { workspace.cancelLargeOpen() } }),
            titleVisibility: .visible, presenting: workspace.pendingLargeOpen) { _ in
            Button("Download and View") { Task { await workspace.confirmLargeOpen() } }
            Button("Cancel", role: .cancel) { workspace.cancelLargeOpen() }
            } message: { pending in
            Text(pending.reason.localizedDescription)
            }
            .alert("Editor", isPresented: Binding(get: { workspace.message != nil },
            set: { if !$0 { workspace.message = nil } })) {
            Button("OK", role: .cancel) { workspace.message = nil }
            } message: {
            Text(workspace.message ?? "")
            }
            // A save that stopped to ask, or a window that came forward onto a changed file
            // (B-X2). The choices are `ConflictPrompt`'s, which is the same set the SFTP editor
            // offers — one vocabulary for "the file changed underneath you", wherever the file is.
            .confirmationDialog("The file has changed", isPresented: Binding(
            get: { workspace.pendingConflict != nil },
            set: { if !$0 { Task { await workspace.resolveConflict(.keepEditing) } } }),
            titleVisibility: .visible, presenting: workspace.pendingConflict) { conflict in
            ForEach(conflict.resolutions, id: \.self) { resolution in
            switch resolution {
            case .overwriteRemote:
            Button("Save Anyway", role: .destructive) {
            Task { await workspace.resolveConflict(.overwriteRemote) }
            }
            case .discardLocalAndReload:
            // Nothing is thrown away when the copy here has no edits: it is just older.
            Button(conflict.state == .remoteChangedLocalClean ? "Reload" : "Discard My Changes and Reload",
            role: conflict.state == .remoteChangedLocalClean ? nil : .destructive) {
            Task { await workspace.resolveConflict(.discardLocalAndReload) }
            }
            case .keepEditing:
            Button("Keep Editing", role: .cancel) { Task { await workspace.resolveConflict(.keepEditing) } }
            case .saveLocalCopy:
            EmptyView()
            }
            }
            } message: { conflict in
            Text(conflict.explanation)
            }
            .confirmationDialog("Close without saving?", isPresented: Binding(
            get: { closeCandidate != nil }, set: { if !$0 { closeCandidate = nil } }),
            titleVisibility: .visible, presenting: closeCandidate) { document in
            Button("Save", role: .none) {
            if document.hasNeverBeenSaved {
            // Saved, then closed — the close is what was asked for. Cancelling keeps it.
            if !workspace.projects.isEmpty {
            firstSave = GlassEditorFirstSave(document: document, closesAfterSaving: true)
            } else {
            saveOutsideProjects(document, true)
            }
            }
            else {
            // Closed only once it is safely saved; a conflict or a failed save keeps it open
            // (and a window close waiting on it is cancelled).
            Task { if await !workspace.saveThenClose(document.id) { closeCancelled() } }
            }
            closeCandidate = nil
            }
            Button("Discard Changes", role: .destructive) {
            workspace.close(document.id, force: true)
            closeCandidate = nil
            }
            Button("Cancel", role: .cancel) { closeCandidate = nil; closeCancelled() }
            } message: { document in
            Text("\(document.displayName) has changes that have not been saved.")
            }
            .sheet(isPresented: $isShowingSettings) {
            GlassEditorSettingsSheet(workspace: workspace, isPresented: $isShowingSettings)
            }
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
            .sheet(item: $firstSave) { request in
            GlassEditorSaveToProjectSheet(
            workspace: workspace, request: request,
            saveElsewhere: { firstSave = nil; saveOutsideProjects(request.document, request.closesAfterSaving) },
            dismiss: {
            // Dismissed without saving a document that was closing: the close is off.
            if request.closesAfterSaving, request.document.hasNeverBeenSaved { closeCancelled() }
            firstSave = nil
            })
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
    @Binding var isShowingSettings: Bool
    // Which window is in front. `controlActiveState` is macOS-only — a window in a headset or on a
    // phone is not "key" in that sense — so elsewhere the last window to appear is the front one,
    // which is true on those platforms anyway.
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif
    #if os(visionOS)
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The text on Apple's glass, with the theme under it at this window's Opacity (Appearance's,
    /// the window's own over it, whole under Reduce Transparency): the surface the SQL editor's
    /// text has in a database window (`SQLEditorSurface.applyEnvironment`), so the engine keeps
    /// the text readable over glass it can't see through, as it does there (W32). Never the opaque
    /// slab it was at every Opacity.
    private var textSurface: SurfaceCondition {
        let state = GlassLayerResolution.resolve(layers.state, window: workspace.windowSettings,
                                                 reduceTransparency: reduceTransparency)
        return SurfaceCondition(
            windowOpacity: GlassWindowGlass.surfaceOpacity(state.effectiveOpacity, GlassEditorWorkspace.navigationOpacity),
            backing: .blur(strength: state.frost),
            ambient: .unknown)
    }
    #endif

    private func checkForOutsideChange(_ id: GlassEditorDocument.ID?) {
        guard let id else { return }
        Task { await workspace.checkForOutsideChange(id) }
    }

    func body(content: Content) -> some View {
        content
            #if os(visionOS)
            .onChange(of: textSurface, initial: true) { _, surface in workspace.setTextSurface(surface) }
            #endif
            // Which window a file opened from the menu bar lands in: the one in front.
            .onAppear { runtime?.noteFrontmost(windowID) }
            #if os(macOS)
            .onChange(of: activeState) { _, state in
                guard state == .key else { return }
                runtime?.noteFrontmost(windowID)
                checkForOutsideChange(workspace.selection)
            }
            #else
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkForOutsideChange(workspace.selection) }
            }
            #endif
            // B-X2: the file in front is looked at again as its window comes forward and as it is
            // chosen, so a change made elsewhere is found before the edits, not at the save.
            .onChange(of: workspace.selection) { _, id in checkForOutsideChange(id) }
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
            //
            // **Only where a window is what went away.** On a phone this fires every time the
            // full-screen cover is dismissed, which is the back chevron meaning "show me the
            // library" — and it emptied the project out of a workspace the user was coming back
            // to, so the session switcher listed a window with nothing in it. The other half of
            // the same mistake as `forget` (D31, rule 54); the workspace is kept there and the
            // project with it, and `closeWorkspace` releases both on purpose. So is a workspace
            // with unsaved changes, kept for them (`forget`): a document from a project on a
            // server is saved through the project's connection.
            .onDisappear {
                if runtime?.closesWorkspaceWithItsWindow ?? true, !workspace.hasUnsavedChanges {
                    workspace.closeAllProjects()
                }
            }
            // A file opened on its own collapses the tree, because a project column with no project
            // in it is a stripe of empty space beside the text.
            .onChange(of: workspace.prefersCollapsedSidebar) { _, collapsed in
                columnVisibility = collapsed ? .detailOnly : .all
            }
            // A window that opens onto an existing project shows the tree; a new, empty one does
            // not, and neither does one showing a single file.
            .onAppear {
                columnVisibility = workspace.projects.isEmpty ? .detailOnly : .all
                #if DEBUG
                // Screenshots (App/GlassDemoMode.swift): This Window, over the window it changes —
                // once the window is on screen: a sheet asked for as it first appears is not shown.
                if workspace.demoOpensSettings {
                    workspace.demoOpensSettings = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        isShowingSettings = true
                    }
                }
                #endif
            }
            // The column follows the projects: it arrives with the first one and leaves with the
            // last. Closing the only project used to leave the tree open and empty, which is the
            // same blank stripe from the other direction.
            .onChange(of: workspace.projects.count) { previous, count in
                if count == 0 { columnVisibility = .detailOnly }
                else if previous == 0 { columnVisibility = .all }
            }
    }
}

#if os(macOS)
/// What an editor window is on a Mac, apart from its content: ⌘W closes the document rather than
/// the window, the menu bar can ask what this window can do, it has a floor for its size, and it
/// remembers where it was.
private struct MacEditorWindowBehaviour: ViewModifier {
    let actions: GlassEditorActions
    let saveItem: GlassSaveItemAction?
    let canCloseDocument: Bool
    let documentCount: Int
    let hasProjects: Bool
    let closeCancellations: Int
    let closeDocument: () -> Void
    /// Documents with unsaved changes, and the first of them, read as they are asked about.
    let unsavedCount: Int
    let firstUnsaved: () -> GlassEditorDocument?
    /// Whether a question about closing a document, or the save it led to, is on screen.
    let isAsking: () -> Bool
    /// Asks about one document as closing it does: Save, Discard Changes or Cancel.
    let askToClose: (GlassEditorDocument) -> Void

    @State private var windowHolder = GlassEditorWindowHolder()
    /// Set when ⌘W is closing the window's last document, so the window goes with it once the
    /// document has actually gone — after the unsaved-changes question, if there was one.
    @State private var closesWindowWhenEmptied = false
    /// Set while the window is closing with unsaved changes: each document with changes is asked
    /// about in turn, and the window closes once none is left (2026-10-17: closing the window
    /// discarded them without a word, though closing one document asked).
    @State private var closingWithUnsavedChanges = false

    /// The window's close button, File ▸ Close Window and ⌘W in an empty window, asked before the
    /// window goes: with unsaved changes it stays, and the documents are asked about.
    private func windowShouldClose() -> Bool {
        guard firstUnsaved() != nil else { return true }
        closingWithUnsavedChanges = true
        askAboutTheNextDocument()
        return false
    }

    /// The next document with changes, once the last question has left the window; the window
    /// itself when there is none.
    private func askAboutTheNextDocument() {
        afterSheetsHaveGone {
            guard closingWithUnsavedChanges, !isAsking() else { return }
            if let document = firstUnsaved() {
                askToClose(document)
            } else {
                closingWithUnsavedChanges = false
                windowHolder.window?.performClose(nil)
            }
        }
    }

    /// `body` once no sheet is attached to the window: a question that was just answered is still
    /// leaving, and a window with a sheet attached neither closes nor shows another.
    private func afterSheetsHaveGone(_ body: @escaping @MainActor () -> Void) {
        guard let window = windowHolder.window, window.attachedSheet != nil else { body(); return }
        Task { @MainActor in
            var turns = 0
            while window.attachedSheet != nil, turns < 50 {
                try? await Task.sleep(for: .milliseconds(20))
                turns += 1
            }
            body()
        }
    }

    func body(content: Content) -> some View {
        content
            // ⌘W closes the document, and **the window when there is no document** — an editor
            // showing a project and no tabs is done with, and ⌘W is how you say so.
            //
            // Always enabled, deliberately: a registration that is present but disabled makes the
            // router *consume* Close and do nothing (it exists so a database's permanent Overview
            // tab cannot be closed by accident), which left ⌘W inert in an empty editor window.
            //
            // **⌘W on the last document closes the window too** (2026-09-25: *"Command w means I'm
            // done here. Not looking for a prompt to do something else."*). It used to leave the
            // window up on "No Document" and its three buttons. A window with a project open stays,
            // on its tree: closing a file there is not closing the project, and ⌘W again closes it.
            .glassCloseCommandTarget(priority: .workspace, isEnabled: true) {
                if canCloseDocument {
                    closesWindowWhenEmptied = documentCount == 1 && !hasProjects
                    closeDocument()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .onChange(of: documentCount) { _, count in
                guard count == 0, closesWindowWhenEmptied else { return }
                closesWindowWhenEmptied = false
                guard let window = windowHolder.window else { return }
                // After the unsaved-changes question the document goes while its sheet is still
                // leaving, and a window with a sheet attached will not close: it beeps and stays,
                // on "No Document" (2026-09-29, Discard after ⌘W). Waiting for the sheet fixed that
                // but showed the empty window for a moment, where Mail's goes the instant you
                // choose. So it leaves the screen now, and is closed once the sheet has let go.
                guard window.attachedSheet != nil else {
                    window.performClose(nil)
                    return
                }
                window.orderOut(nil)
                Task { @MainActor in
                    var turns = 0
                    while window.attachedSheet != nil, turns < 50 {
                        try? await Task.sleep(for: .milliseconds(20))
                        turns += 1
                    }
                    window.close()
                }
            }
            // Cancel — in the question, or in the Save panel it led to — leaves the window. Save
            // and Discard do not: the document goes, and the window with it.
            .onChange(of: closeCancellations) { _, _ in
                closesWindowWhenEmptied = false
                closingWithUnsavedChanges = false
            }
            // A document asked about was saved or discarded: on to the next, or the window.
            .onChange(of: unsavedCount) { _, _ in
                if closingWithUnsavedChanges { askAboutTheNextDocument() }
            }
            .background { GlassWindowCloseGate(shouldClose: windowShouldClose) }
            .focusedSceneValue(\.glassEditorActions, actions)
            .focusedSceneValue(\.glassSaveItem, saveItem)
            .frame(minWidth: 820, minHeight: 520)
            .background { GlassEditorWindowFrameMemory(holder: windowHolder) }
    }
}
#endif

#if os(macOS)
/// The Mac's own Save panel, for a document that has never been saved.
///
/// Not SwiftUI's `fileExporter`: on a Mac that is an *export* panel — "Export As:", an Export
/// button — and typed as plain text it appended `.txt`, so a new `.env` would have been
/// `.env.txt` (2026-09-25: *"The save button said Export?"*). This is Save, it adds no extension
/// to the name typed, and the document writes the file itself, once — the exporter wrote it and
/// then the document wrote it again to adopt it.
@MainActor
enum GlassEditorSavePanel {
    static func run(for document: GlassEditorDocument,
                    saved: @escaping (URL) -> Void,
                    cancelled: @escaping () -> Void = {}) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        panel.canCreateDirectories = true
        // No content types: the name typed is the name written, `.env` included.
        panel.allowsOtherFileTypes = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { saved(url) } else { cancelled() }
        }
        // A sheet on the editor. `mainWindow`, not `keyWindow`: while the unsaved-changes question
        // is going away, *it* can still be key; its parent stays main, and AppKit queues a sheet
        // behind one that is ending.
        if let window = NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}

/// An editor view's own window, held weakly and never observed.
@MainActor
final class GlassEditorWindowHolder {
    weak var window: NSWindow?
}

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
    /// Where this editor's own window is recorded, for closing it by name rather than whichever
    /// window happens to be key — a dialog's sheet can still be, as it goes.
    var holder: GlassEditorWindowHolder? = nil

    func makeNSView(context: Context) -> NSView {
        let view = FrameMemoryView(frame: .zero)
        view.holder = holder
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FrameMemoryView: NSView {
        weak var holder: GlassEditorWindowHolder?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            holder?.window = window
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

#if os(iOS)
/// Where a phone can be inside a project: in a folder, or in the document it opened from one.
enum GlassEditorCompactRoute: Hashable {
    case folder(UUID)
    case document
}

/// One folder's contents, as a screen — the phone's answer to the tree.
///
/// A tree with disclosure triangles is a Mac and headset idiom: it needs a pointer and width, and
/// on a 390-point screen the tree *was* the screen. Here a folder is a push and the back button is
/// the way out, which is what the Files browser does on the same device and what the user asked
/// for: *"rely on the back button and tapping the folder in the list view or tree view"*.
struct GlassEditorFolderList: View {
    let workspace: GlassEditorWorkspace
    let folder: GlassEditorProjectNode
    let filter: String
    /// A double tap: the file is kept.
    let open: (GlassEditorProjectNode) -> Void
    /// A single tap: the file is shown in the provisional tab.
    let preview: (GlassEditorProjectNode) -> Void

    private var query: String { filter.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Case-insensitive, this level only — the same rule the tree filters each level by.
    private var visible: [GlassEditorProjectNode] {
        let children = folder.children ?? []
        guard !query.isEmpty else { return children }
        return children.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ForEach(visible) { node in
                if node.isDirectory {
                    // A link, not a tap handler: it carries the chevron that says a row leads
                    // somewhere, and the stack does the pushing.
                    NavigationLink(value: GlassEditorCompactRoute.folder(node.id)) {
                        GlassEditorFileRow(workspace: workspace, node: node,
                                           symbol: "folder", open: open)
                    }
                } else {
                    GlassEditorFileRow(workspace: workspace, node: node, symbol: "doc", open: open)
                        .onTapGesture { preview(node) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { open(node) })
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay { if visible.isEmpty { emptyState } }
    }

    /// An empty list is four different facts, and a blank screen says none of them.
    @ViewBuilder
    private var emptyState: some View {
        if folder.isLoading {
            ProgressView("Reading \(folder.name)")
        } else if let loadError = folder.loadError {
            ContentUnavailableView("Cannot Read \(folder.name)",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else if query.isEmpty {
            ContentUnavailableView("Empty Folder", systemImage: "folder",
                                   description: Text("There is nothing in \(folder.name)."))
        } else {
            ContentUnavailableView.search(text: filter)
        }
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
    /// Opening it for good — a double click.
    let open: (GlassEditorProjectNode) -> Void
    /// Showing it provisionally — one click.
    let preview: (GlassEditorProjectNode) -> Void

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
                                        filter: filter, open: open, preview: preview)
                } label: {
                    row(node, symbol: "folder")
                }
                .tag(GlassEditorSidebarSelection.node(node.id))
                // The sidebar's row spacing in the headset's own column (W33); nothing elsewhere.
                .glassSpatialListRow()
            } else {
                row(node, symbol: "doc")
                    .tag(GlassEditorSidebarSelection.node(node.id))
                    .glassSpatialListRow()
            }
        }
    }

    private func row(_ node: GlassEditorProjectNode, symbol: String) -> some View {
        GlassEditorFileRow(workspace: workspace, node: node, symbol: symbol, open: open)
            // **Single click selects, double click opens** — and the single click has to be said
            // out loud. Verified in the running app: with only the double-click gesture attached,
            // clicking a row moved AppKit's own selection but never reached the model, so Return
            // did nothing and the current folder stayed wherever the keyboard had last left it.
            // The database's schema browser has always done both (`SchemaBrowserView.tableRow`).
            // **One tap opens on a touch screen; on a Mac it takes two.**
            //
            // A double click is a mouse idiom and there is nothing to double-tap on a phone, so
            // the only gesture the tree had was selection — a file could be chosen and never
            // opened, on the one platform where the tree is the *only* way to open anything. The
            // file list did exactly what it was told and looked like an editor that does nothing.
            //
            // A folder is left to its disclosure triangle on both: opening it is what the triangle
            // is for, and a tap that both selects and toggles fights itself.
            //
            // **And one click now previews, on both.** The file opens in the provisional tab and
            // the next single click takes that same tab; a double click keeps it. That is what
            // Xcode and VS Code do, and it is why reading through a folder does not end with
            // twenty tabs (`GlassEditorWorkspace.previewDocumentID`).
            .onTapGesture {
                workspace.sidebarSelection = .node(node.id)
                preview(node)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { open(node) })
    }
}

/// What a file or folder looks like in a list — in the tree, and on a phone's folder screen.
///
/// The two lists navigate differently (a tree selects and expands in place; a phone pushes), so
/// the gestures stay with the list. What a row *is* lives here, once.
private struct GlassEditorFileRow: View {
    let workspace: GlassEditorWorkspace
    let node: GlassEditorProjectNode
    let symbol: String
    let open: (GlassEditorProjectNode) -> Void
    @State private var isNamingNewFile = false
    @State private var newFileName = ""

    /// The folder a new file goes in: this one, or the one this file is in.
    private var newFileFolder: String {
        node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
    }

    var body: some View {
        // **The row is as wide as the column, not as wide as the filename.**
        //
        // A bare `Label` is only as wide as its text, and `contentShape` shapes what is there — so a
        // click to the right of a short name landed on nothing and selected nothing. Verified in the
        // running app: clicking a row left the list with no selection at all. The database's rows
        // have always been an `HStack` ending in a `Spacer`, which is also where the trailing fact
        // about a row goes.
        HStack(spacing: 6) {
            // The list's own font, as the schema browser's table rows use — `rowSubtitleFont` is
            // `.caption` on a Mac, which made a file tree read like a footnote.
            Label(node.name, systemImage: symbol)
            Spacer(minLength: 0)
            // Trailing, where a fact about a row goes. A folder on this device is read before the
            // frame draws and neither of these is ever seen; a folder on another machine is a
            // listing crossing a network, and an empty triangle would read as an empty folder.
            if node.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading \(node.name)")
            } else if let loadError = node.loadError {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(loadError)
                    .accessibilityLabel("\(node.name) could not be read: \(loadError)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glassSpatialListRow()
        .contextMenu {
            Button(node.isDirectory ? "Open Folder" : "Open") { open(node) }
            // Local or on a server, through the project's own access (2026-09-26: the editor had
            // no way to start a new file on a server).
            Button("New File…", systemImage: "doc.badge.plus") {
                newFileName = ""
                isNamingNewFile = true
            }
            if node.isDirectory {
                Button("Refresh") { refresh() }
            }
        }
        .alert("New File", isPresented: $isNamingNewFile) {
            TextField("File name", text: $newFileName)
            Button("Create") {
                let name = newFileName, folder = newFileFolder
                Task {
                    do {
                        try await workspace.createFile(named: name, inFolder: folder)
                        // A file's folder is already open; a folder shows its new file.
                        if node.isDirectory { workspace.setExpanded(true, for: node.id) }
                    } catch {
                        workspace.message = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In \((newFileFolder as NSString).lastPathComponent.isEmpty ? "/" : (newFileFolder as NSString).lastPathComponent). It opens in the editor.")
        }
        .accessibilityIdentifier("editor-file-\(node.name)")
    }

    private func refresh() {
        node.invalidate()
        workspace.setExpanded(true, for: node.id)
        // A folder that was already open stays in the expansion set, so `setExpanded` has nothing
        // to do and would not re-read it — the node is asked directly as well.
        node.beginLoadingChildrenIfNeeded(using: workspace.access(for: node))
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
