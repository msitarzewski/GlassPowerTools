//
//  GlassEditorProjectOverview.swift
//  Glass Power Tools — GlassEditor
//
//  What an editor shows when a **project** is open and no file is.
//
//  It used to show "Open Project…, Open File…, New Document" — three ways to open something, to
//  someone who has just opened something (reported 2026-09-18). Those belong to an *empty* editor,
//  the one ⇧⌘E and File ▸ New Editor make, where they are the only thing to do.
//
//  With a folder open, the useful thing is what is **in** the folder. Every fact here comes from
//  the listing the tree already loaded and from the recents the app already keeps, so the overview
//  costs no reads of its own: the agent instructions a machine leaves for its next agent, the file
//  a human is meant to read first, what builds it, whether it is a git repository, and what you
//  were last editing here.
//
//  What git says changed is the project's repository's (`GlassEditorGitRepository`, 2026-10-23),
//  run where the folder is; here it is the branch and a way to Changes.
//

import SwiftUI
import GlassConnectionUI

/// The files in a project root worth naming, found by name alone.
public struct GlassEditorProjectLandmarks: Equatable, Sendable {
    /// Instructions written for an agent — the thing this app's own user writes most.
    public var agentFiles: [String] = []
    /// What a person is meant to read first.
    public var readFirst: [String] = []
    /// What builds or runs it.
    public var build: [String] = []
    /// A `.git` directory in the root.
    public var isGitRepository = false

    public var isEmpty: Bool {
        agentFiles.isEmpty && readFirst.isEmpty && build.isEmpty && !isGitRepository
    }

    // Lower-cased, matched exactly. A list rather than a guess: "anything ending in .md" would
    // make a folder of notes look like a project with six readmes.
    private static let agents = ["agents.md", "claude.md", "gemini.md", "copilot-instructions.md",
                                 ".cursorrules", ".windsurfrules", "conventions.md"]
    private static let read = ["readme.md", "readme", "readme.txt", "contributing.md",
                               "changelog.md", "license", "license.md"]
    private static let builds = ["package.swift", "package.json", "cargo.toml", "pyproject.toml",
                                 "requirements.txt", "go.mod", "gemfile", "makefile", "dockerfile",
                                 "docker-compose.yml", "cmakelists.txt", "build.gradle", "pom.xml"]

    /// Reads one directory listing. Order follows the lists above rather than the directory, so
    /// `AGENTS.md` is in the same place in every project.
    public static func detect(in nodes: [GlassEditorProjectNode]) -> Self {
        var found = Self()
        let files = Dictionary(nodes.filter { !$0.isDirectory }.map { ($0.name.lowercased(), $0.name) },
                               uniquingKeysWith: { first, _ in first })
        found.agentFiles = agents.compactMap { files[$0] }
        found.readFirst = read.compactMap { files[$0] }
        found.build = builds.compactMap { files[$0] }
        found.isGitRepository = nodes.contains { $0.isDirectory && $0.name == ".git" }
        return found
    }
}

struct GlassEditorProjectOverview: View {
    let workspace: GlassEditorWorkspace
    let project: GlassEditorProject
    let open: (String) -> Void

    private var root: GlassEditorProjectNode? { workspace.projectRoots[project.id] }
    private var landmarks: GlassEditorProjectLandmarks {
        GlassEditorProjectLandmarks.detect(in: root?.children ?? [])
    }

    /// Files edited here before, newest first. The app already keeps this list; filtering it by the
    /// project's path is the whole of the work. Folders are in the list too (Open Recent offers
    /// them) and are not files to edit.
    private var recents: [URL] {
        workspace.preferences.recents
            .filter { !$0.hasDirectoryPath && $0.path(percentEncoded: false).hasPrefix(project.path + "/") }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        #if os(visionOS)
        // **Under its title, on the headset** (W32, the owner, 2026-10-10: "the headers across all
        // of these should do a better job of matching"). The project's name is the column's own
        // title there, which visionOS sets level with the sidebar's, so the page starts where that
        // title does — as Your Library does under its own — and keeps the terminal's margin from
        // the window's edges. Centred, it floated away from the title it belongs to.
        ScrollView {
            overview
                .padding(GlassWindowShape.spatialColumnContentInsets)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("editor-project-overview")
        #else
        // **Centred in the pane, both ways**, like the empty state it replaced — a short list of
        // files pinned to the top of a tall empty window reads as content that failed to load.
        // The block itself stays left-aligned: a column of filenames is a list, not a poster.
        //
        // `minHeight` rather than `height`, so a project with a lot to say still scrolls.
        GeometryReader { proxy in
            ScrollView {
                overview
                    .padding(GlassSpatialMetrics.isSpatial ? 32 : 24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
        .accessibilityIdentifier("editor-project-overview")
        #endif
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading
            if root?.isLoading == true && landmarks.isEmpty {
                ProgressView("Reading \(project.displayName)")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            group("Agent Instructions", "sparkles", landmarks.agentFiles)
            group("Read First", "book", landmarks.readFirst)
            group("Build", "hammer", landmarks.build)
            if !recents.isEmpty {
                section("Recently Edited", "clock") {
                    ForEach(recents, id: \.self) { url in
                        fileButton(url.lastPathComponent,
                                   path: url.path(percentEncoded: false))
                    }
                }
            }
            if landmarks.isEmpty && recents.isEmpty && root?.isLoading != true {
                Text("Choose a file from the list to start editing.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Not on the headset: there the name is the column's title already, and the page
            // said it a second time, larger, just under it (W32).
            #if !os(visionOS)
            Text(project.displayName)
                .font(GlassSpatialMetrics.isSpatial ? .largeTitle : .title)
                .fontWeight(.semibold)
            #endif
            HStack(spacing: 10) {
                if let reach = workspace.projectReach[project.id] {
                    Label(reach.badge, systemImage: reach.symbolName)
                }
                if let repository = workspace.repositories[project.id], repository.state == .ready {
                    // The branch and what differs from its last commit, opening Changes (2026-10-23).
                    Button {
                        workspace.showChanges(of: project.id)
                    } label: {
                        let count = repository.status.changes.count
                        Label(count == 0 ? "\(repository.status.headName), no changes"
                                : "\(repository.status.headName), \(count) changed file\(count == 1 ? "" : "s")",
                              systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("editor-project-git")
                } else if landmarks.isGitRepository {
                    // Where this device has no git to run, or it has not answered yet.
                    Label("Git repository", systemImage: "arrow.triangle.branch")
                        .accessibilityIdentifier("editor-project-git")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ symbol: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            section(title, symbol) {
                ForEach(names, id: \.self) { name in
                    fileButton(name, path: (project.path as NSString).appendingPathComponent(name))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, _ symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            VStack(alignment: .leading, spacing: 2) { content() }
        }
    }

    private func fileButton(_ name: String, path: String) -> some View {
        Button { open(path) } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text(name)
                Spacer(minLength: 0)
            }
            // Room for the gaze highlight, and no more: the spatial row metrics made each file a
            // tall tile with wide gaps (2026-09-28). Not in a list, so the button keeps its own.
            .padding(.vertical, GlassSpatialMetrics.isSpatial ? 6 : 0)
            .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 8 : 0)
            #if os(visionOS)
            .contentShape(.hoverEffect, .rect(cornerRadius: 10))
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassGazeHighlight()
        #if os(visionOS)
        // The highlight reaches past the file's name and symbol, and they line up with the
        // section's own symbol and the column's title above (W32).
        .padding(.horizontal, -8)
        #endif
        .accessibilityIdentifier("editor-overview-\(name)")
    }
}
