//
//  GlassEditorProjectsPanel.swift
//  Glass Power Tools — GlassEditor
//
//  Projects in the library, beside Collections, Workgroups and Keys.
//
//  It belongs there for the reason Keys does: a project spans the fleet rather than belonging to
//  one machine, and the list of them is a thing about the workspace, not about a window. It is
//  contributed through `GlassLibraryPanel` and registered with `registerLibraryPanel`, the seam
//  the editor's settings page already uses — the editor is not a capability, because a file is not
//  a service on a machine.
//
//  **On iOS and visionOS this is the editor's only entry point.** There is no File menu there and
//  no window to open one from, so until this existed the editor was a Mac surface with two
//  platforms compiled but unreachable.
//
//  Designed on visionOS terms and adapted down, per the magic directive: rows are gaze targets,
//  the detail is set at reading distance, and on a Mac it is an ordinary two-column library panel.
//

import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// Selection and presentation for both columns. Held outside them because they are two columns of
/// one split view, and a `@State` in one cannot be read by the other.
@MainActor @Observable
public final class GlassEditorProjectsPanelModel {
    var selection: GlassEditorProject.ID?
    var searchQuery: String = ""
    var showingOpenPanel = false
    var renaming: GlassEditorProject?
    var renamedTo: String = ""
    var pendingRemoval: GlassEditorProject?
    /// Something to say about the list — a folder chooser that failed.
    var message: String?
    /// Something to say about the selected project, raised by an action in its detail.
    ///
    /// **Two, because one would be shown in the wrong place.** The alert was attached to the
    /// results column alone, and on a phone that column is not in the hierarchy once the detail
    /// has been pushed — so Open on a folder that had gone set a message nobody ever saw and the
    /// tap did nothing at all. Each column says what happened in it.
    var detailMessage: String?

    public init() {}
}

public struct GlassEditorProjectsPanel: View {
    public enum Presentation { case results, detail }

    private let presentation: Presentation
    private let runtime: GlassEditorRuntime
    private let reach: (GlassEditorProject) -> GlassEditorProjectReach
    @Bindable private var panel: GlassEditorProjectsPanelModel
    @Environment(\.openWindow) private var openWindow

    public init(presentation: Presentation,
                runtime: GlassEditorRuntime,
                panel: GlassEditorProjectsPanelModel,
                reach: @escaping (GlassEditorProject) -> GlassEditorProjectReach) {
        self.presentation = presentation
        self.runtime = runtime
        self.panel = panel
        self.reach = reach
    }

    private var projects: [GlassEditorProject] {
        let all = runtime.projects.projects
        let query = panel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProject: GlassEditorProject? {
        guard let selection = panel.selection else { return nil }
        return runtime.projects.projects.first { $0.id == selection }
    }

    public var body: some View {
        content
            // Attached to whichever instance owns the results, never to both columns: a sheet on
            // both presents twice and an alert on both fights itself.
            .background { if presentation == .results { sharedPresentations } }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .results: results
        case .detail: detail
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        List(selection: $panel.selection) {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label(panel.searchQuery.isEmpty ? "No Projects" : "No Matching Projects",
                          systemImage: "folder")
                } description: {
                    Text(panel.searchQuery.isEmpty
                         ? "A project is a folder on a machine. Open one and it stays here, on every device you use."
                         : "Try a different search.")
                } actions: {
                    if panel.searchQuery.isEmpty {
                        Button("Open a Project…") { panel.showingOpenPanel = true }
                            #if os(visionOS)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            #endif
                    }
                }
            }
            ForEach(projects) { project in
                row(project)
                    .tag(project.id)
                    .glassSpatialListRow()
                    .contextMenu {
                        Button("Open", systemImage: "arrow.up.forward.app") { open(project) }
                        Button("Rename", systemImage: "pencil") { beginRenaming(project) }
                        Button("Remove from Library", systemImage: "trash", role: .destructive) {
                            panel.pendingRemoval = project
                        }
                    }
            }
        }
        .glassSpatialList()
        .scrollContentBackground(.hidden)
        .searchable(text: $panel.searchQuery, prompt: "Search Projects")
        .toolbar {
            ToolbarItem {
                // **New Document and the one Open…, as well as a project.** Off the Mac this panel
                // is the editor's only door, and it opened folders and nothing else: a blank
                // document, or one file without its folder, could be had only from inside an editor
                // window, which only a project could open (2026-10-09, Vision Pro). The Mac's File
                // menu has both (⇧⌘E, ⌘O); this is the same pair, and Open… is the same rule.
                Menu {
                    Button("New Document", systemImage: "doc.badge.plus") {
                        runtime.show([runtime.prepareNewEditorWindow()], with: openWindow)
                    }
                    .accessibilityIdentifier("projects-new-document")
                    Button("Open…", systemImage: "folder") { panel.showingOpenPanel = true }
                        .accessibilityIdentifier("projects-open")
                } label: {
                    Label("New or Open", systemImage: "plus")
                }
                .accessibilityIdentifier("projects-add")
            }
        }
    }

    private func row(_ project: GlassEditorProject) -> some View {
        let reach = reach(project)
        return GlassLibraryConnectionRow(
            name: project.displayName,
            nameAccessibilityIdentifier: "project-row-\(project.displayName)"
        ) {
            // Where it is, under what it is called: the machine, then the folder. A project on
            // two machines has the same name on both, so the machine is what tells them apart.
            HStack(spacing: 8) {
                Label(reach.badge, systemImage: reach.symbolName)
                    .labelStyle(.titleAndIcon)
                Text(project.path)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .font(GlassSpatialMetrics.rowSubtitleFont)
            .foregroundStyle(.secondary)
        } accessory: {
            EmptyView()
        }
        .accessibilityIdentifier("project-\(project.id.uuidString.lowercased())")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        detailContent
            .alert("Projects", isPresented: Binding(
                get: { panel.detailMessage != nil },
                set: { if !$0 { panel.detailMessage = nil } })
            ) {
                Button("OK", role: .cancel) { panel.detailMessage = nil }
            } message: {
                Text(panel.detailMessage ?? "")
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let project = selectedProject {
            let reach = reach(project)
            GlassLibraryDetail(title: project.displayName, content: {
                Section("Project") {
                    LabeledContent("Folder") {
                        Text(project.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.head)
                    }
                    .accessibilityIdentifier("project-detail-path")
                    LabeledContent("Machine") {
                        Label(reach.badge, systemImage: reach.symbolName)
                    }
                    .accessibilityIdentifier("project-detail-reach")
                    LabeledContent("Last Opened") { Text(project.openedAt, style: .date) }
                }
                Section("Availability") {
                    Text(availability(reach))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("project-detail-availability")
                }
            }, actions: {
                HStack(spacing: 12) {
                    Button("Remove", role: .destructive) { panel.pendingRemoval = project }
                        .accessibilityIdentifier("project-remove")
                    Spacer(minLength: 0)
                    Button("Rename") { beginRenaming(project) }
                        .accessibilityIdentifier("project-rename")
                    Button("Open") { open(project) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canOpen(reach))
                        .accessibilityIdentifier("project-open")
                }
            })
        } else {
            ContentUnavailableView {
                Label("Select a Project", systemImage: "folder")
            } description: {
                Text("A folder on a machine. The same project follows you between your devices, because what travels is where it is — never the files.")
            }
            #if os(visionOS)
            .font(.title3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }

    /// What this device can do with the project, said plainly rather than as a disabled button
    /// with no explanation (the `error-messages-say-the-fix` rule).
    private func availability(_ reach: GlassEditorProjectReach) -> String {
        switch reach {
        case .thisMachine:
            "The folder is on this device, so it opens straight from the file system."
        case .overSSH(let host):
            runtime.remoteAccess == nil
                ? "The folder is on \(host), and this build has no way to read another machine's folders."
                : "The folder is on \(host), and opens over that machine's Terminal service."
        case .unreachable(let host):
            "\(host) has no Terminal service on its record, so there is no way in from here. Add one to the machine and this project opens over it."
        }
    }

    private func canOpen(_ reach: GlassEditorProjectReach) -> Bool {
        switch reach {
        case .thisMachine: true
        case .overSSH: runtime.remoteAccess != nil
        case .unreachable: false
        }
    }

    // MARK: Actions

    private func open(_ project: GlassEditorProject) {
        let reach = reach(project)
        guard canOpen(reach) else {
            panel.detailMessage = availability(reach)
            return
        }
        // Only a folder on this device can be checked from here; a remote one is the reader's to
        // answer, and it reports on the row it failed to fill. Checked through the runtime, which
        // reaches a folder picked from Files the way this device kept it (a bookmark) — a plain
        // look at the path has no access to one and said it was gone.
        if case .thisMachine = reach, !runtime.localFolderExists(project) {
            panel.detailMessage = "There is no folder at \(project.path) any more. Remove the project, or put the folder back."
            return
        }
        if let windowID = runtime.openProject(project, reach: reach) {
            runtime.present(windowID)
        }
    }

    private func beginRenaming(_ project: GlassEditorProject) {
        panel.renamedTo = project.displayName
        panel.renaming = project
    }

    // MARK: Sheets and alerts

    @ViewBuilder
    private var sharedPresentations: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // One chooser for every platform, rather than an `NSOpenPanel` here and a document
            // picker there — and the editor's one Open…: files and folders together, decided by
            // what is chosen (`GlassEditorRuntime.open(urls:from:)`), so a folder is a project in a
            // window of its own and files are tabs.
            .fileImporter(isPresented: $panel.showingOpenPanel,
                          allowedContentTypes: [.folder, .data],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    // A folder chosen from Files on iOS arrives security-scoped, and reading it
                    // without asking for access silently returns nothing. The project asks, and
                    // **holds** it while it is open: this used to give it back the moment this
                    // returned, while the tree was still loading. It also leaves this device a
                    // bookmark, so the folder reopens from the list after a relaunch. A file holds
                    // its own access while its tab is open (`GlassEditorWorkspace.open(_:)`).
                    runtime.show(runtime.open(urls: urls), with: openWindow)
                case .failure(let error):
                    panel.message = error.localizedDescription
                }
            }
            .alert("Rename Project", isPresented: Binding(
                get: { panel.renaming != nil },
                set: { if !$0 { panel.renaming = nil } })
            ) {
                TextField("Name", text: $panel.renamedTo)
                Button("Rename") {
                    if let project = panel.renaming {
                        runtime.projects.rename(project.id, to: panel.renamedTo)
                    }
                    panel.renaming = nil
                }
                Button("Cancel", role: .cancel) { panel.renaming = nil }
            } message: {
                Text("What this project is called here. The folder is not moved or renamed.")
            }
            .alert("Projects", isPresented: Binding(
                get: { panel.message != nil },
                set: { if !$0 { panel.message = nil } })
            ) {
                Button("OK", role: .cancel) { panel.message = nil }
            } message: {
                Text(panel.message ?? "")
            }
            .confirmationDialog("Remove Project?",
                                isPresented: Binding(get: { panel.pendingRemoval != nil },
                                                     set: { if !$0 { panel.pendingRemoval = nil } }),
                                titleVisibility: .visible,
                                presenting: panel.pendingRemoval) { project in
                Button("Remove \(project.displayName)", role: .destructive) {
                    runtime.projects.forget(project.id)
                    if panel.selection == project.id { panel.selection = nil }
                    panel.pendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { panel.pendingRemoval = nil }
            } message: { project in
                Text("\(project.displayName) is removed from this list on every device. The folder at \(project.path) is not touched.")
            }
    }
}

public extension GlassEditorRuntime {
    /// The Projects panel, ready to register with `GlassCapabilityRegistry.registerLibraryPanel`.
    ///
    /// `reach` is supplied by the composition root because answering "is that machine this one?"
    /// needs the catalog, and the editor deliberately does not hold it.
    func libraryPanel(
        panel model: GlassEditorProjectsPanelModel,
        reach: @escaping (GlassEditorProject) -> GlassEditorProjectReach
    ) -> GlassLibraryPanel {
        let runtime = self
        return GlassLibraryPanel(
            id: "editor-projects",
            sectionTitle: "Projects",
            title: "Projects",
            symbolName: "folder",
            // `runtime`, not `self`: the count is asked for every time the sidebar row draws, so
            // the expression outlives this call. Stored, it said 5 with four projects in the list
            // (`GlassLibraryPanel.count`).
            count: runtime.projects.projects.isEmpty ? nil : runtime.projects.projects.count,
            selection: { model.selection },
            clearSelection: { model.selection = nil },
            results: {
                GlassEditorProjectsPanel(presentation: .results, runtime: runtime,
                                         panel: model, reach: reach)
            },
            detail: {
                GlassEditorProjectsPanel(presentation: .detail, runtime: runtime,
                                         panel: model, reach: reach)
            }
        )
    }
}
