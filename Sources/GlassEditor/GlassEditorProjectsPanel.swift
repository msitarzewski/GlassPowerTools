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
    var message: String?

    public init() {}
}

public struct GlassEditorProjectsPanel: View {
    public enum Presentation { case results, detail }

    private let presentation: Presentation
    private let runtime: GlassEditorRuntime
    private let reach: (GlassEditorProject) -> GlassEditorProjectReach
    @Bindable private var panel: GlassEditorProjectsPanelModel

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
                    .contextMenu {
                        Button("Open", systemImage: "arrow.up.forward.app") { open(project) }
                        Button("Rename", systemImage: "pencil") { beginRenaming(project) }
                        Button("Remove from Library", systemImage: "trash", role: .destructive) {
                            panel.pendingRemoval = project
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $panel.searchQuery, prompt: "Search Projects")
        .toolbar {
            ToolbarItem {
                Button("Open a Project…", systemImage: "plus") { panel.showingOpenPanel = true }
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
        .glassSpatialRowMetrics()
        .glassGazeHighlight()
        .accessibilityIdentifier("project-\(project.id.uuidString.lowercased())")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
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
            panel.message = availability(reach)
            return
        }
        // Only a folder on this device can be checked from here; a remote one is the reader's to
        // answer, and it reports on the row it failed to fill.
        if case .thisMachine = reach {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                panel.message = "There is no folder at \(project.path) any more. Remove the project, or put the folder back."
                return
            }
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
            // One folder chooser for every platform, rather than an `NSOpenPanel` here and a
            // document picker there.
            .fileImporter(isPresented: $panel.showingOpenPanel,
                          allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    // A folder chosen from Files on iOS arrives security-scoped, and reading it
                    // without asking for access silently returns nothing. Every other importer in
                    // this app does this; the editor's was the one that did not.
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let windowID = runtime.openProject(url) {
                        runtime.present(windowID)
                    }
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
            count: projects.projects.isEmpty ? nil : projects.projects.count,
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
