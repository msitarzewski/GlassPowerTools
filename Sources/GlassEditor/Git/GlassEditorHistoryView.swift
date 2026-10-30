//
//  GlassEditorHistoryView.swift
//  Glass Power Tools — GlassEditor
//
//  Source Control's **History**, and a file's History tab (2026-10-28): the commits, newest first,
//  with the lines of their graph as `git log --graph` draws them, the branches and tags at each,
//  and — chosen — a commit's message and its changes, with what can be done from it: check it out,
//  branch or tag it, cherry-pick it, revert it, reset to it, open it on GitHub.
//
//  Read a page at a time, as the list scrolls: a repository's history can be hundreds of
//  thousands of commits, and the first screenful is what is looked at.
//

import SwiftUI
import GlassConnectionUI

struct GlassEditorHistoryView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    /// A file's history, by its absolute path; nil for the repository's.
    let path: String?
    let ask: (GlassEditorGitRequest) -> Void

    @AppStorage("editor.git.historyAllBranches") private var allBranches = true
    @State private var commits: [GlassEditorGitCommit] = []
    @State private var rows: [GlassEditorGitGraphRow] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var selection: String?
    /// What was last read, to read again when the branch moves.
    @State private var readAt: String?

    static let page = 300

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            Group {
                if wide {
                    HStack(spacing: 0) {
                        list
                            .frame(width: max(320, geometry.size.width * 0.42))
                        Divider()
                        detail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if selectedCommit != nil {
                    VStack(spacing: 0) {
                        HStack {
                            Button("History", systemImage: "chevron.left") { selection = nil }
                                .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider()
                        detail
                    }
                } else {
                    list
                }
            }
        }
        .task(id: "\(repository.status.commit ?? "")|\(allBranches)|\(repository.branches.map(\.commit).joined())") {
            await reload()
        }
        .onChange(of: workspace.gitShownCommits[projectID]) { _, commit in
            guard path == nil, let commit else { return }
            Task { await show(commit) }
        }
    }

    private var selectedCommit: GlassEditorGitCommit? {
        selection.flatMap { hash in commits.first { $0.hash == hash } }
    }

    // MARK: Reading

    private func reload() async {
        let key = "\(repository.status.commit ?? "")|\(allBranches)|\(repository.branches.map(\.commit).joined())"
        guard key != readAt || commits.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        guard let read = await repository.history(limit: Self.page, allBranches: path == nil && allBranches, path: path) else { return }
        readAt = key
        commits = read
        rows = GlassEditorGitGraphRow.rows(for: read)
        reachedEnd = read.count < Self.page
        if let shown = workspace.gitShownCommits[projectID], path == nil {
            await show(shown)
        } else if selection == nil || !read.contains(where: { $0.hash == selection }) {
            selection = path != nil ? read.first?.hash : nil
        }
    }

    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        guard let read = await repository.history(limit: Self.page, skip: commits.count,
                                                  allBranches: path == nil && allBranches, path: path) else { return }
        let known = Set(commits.map(\.hash))
        commits += read.filter { !known.contains($0.hash) }
        rows = GlassEditorGitGraphRow.rows(for: commits)
        reachedEnd = read.count < Self.page
    }

    /// A commit asked for from elsewhere: chosen, once the pages it is in are read.
    private func show(_ hash: String) async {
        workspace.gitShownCommits[projectID] = nil
        var pages = 0
        while !commits.contains(where: { $0.hash.hasPrefix(hash) }), !reachedEnd, pages < 10 {
            await loadMore()
            pages += 1
        }
        selection = commits.first { $0.hash.hasPrefix(hash) }?.hash
    }

    // MARK: The list

    private var list: some View {
        VStack(spacing: 0) {
            if path == nil {
                HStack {
                    Picker("Branches", selection: $allBranches) {
                        Text("All Branches").tag(true)
                        Text(repository.status.headName).tag(false)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("editor-history-branches")
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                Divider()
            }
            if commits.isEmpty {
                if isLoading {
                    ProgressView("Reading the history").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No Commits", systemImage: "clock",
                                           description: Text(path == nil ? "Nothing has been committed yet." : "No commit has changed this file."))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(commits.enumerated()), id: \.element.hash) { index, commit in
                            row(commit, graph: index < rows.count ? rows[index] : nil, previous: index > 0 && index - 1 < rows.count ? rows[index - 1] : nil)
                                .onAppear {
                                    if index >= commits.count - 20 { Task { await loadMore() } }
                                }
                        }
                        if !reachedEnd {
                            ProgressView().controlSize(.small).padding(8)
                        }
                    }
                }
                .accessibilityIdentifier("editor-history")
            }
        }
    }

    static let rowHeight: CGFloat = 44

    /// One width for the graph in every row, so the subjects line up: the widest row's, up to a
    /// dozen lanes.
    private var graphWidth: CGFloat {
        CGFloat(min(max(rows.map(\.width).max() ?? 1, 1), 12)) * GlassEditorGraphCell.laneWidth + 6
    }

    private func row(_ commit: GlassEditorGitCommit, graph: GlassEditorGitGraphRow?, previous: GlassEditorGitGraphRow?) -> some View {
        let isSelected = selection == commit.hash
        return HStack(spacing: 6) {
            if let graph, path == nil {
                GlassEditorGraphCell(row: graph, isMerge: commit.isMerge)
                    .frame(width: graphWidth, height: Self.rowHeight, alignment: .leading)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(4), id: \.self) { ref in
                        GlassEditorRefBadge(ref: ref, remotes: repository.remotes.map(\.name))
                    }
                    Text(commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    Text(commit.shortHash).monospaced()
                    Text(commit.author).lineLimit(1)
                    Text(GlassEditorGitDates.relative(commit.date)).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = commit.hash }
        .contextMenu { commitMenu(commit) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(commit.subject), by \(commit.author), \(GlassEditorGitDates.relative(commit.date))"
                            + (commit.refs.isEmpty ? "" : ", at \(commit.refs.joined(separator: ", "))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("editor-commit-\(commit.shortHash)")
    }

    // MARK: A commit

    @ViewBuilder
    private var detail: some View {
        if let commit = selectedCommit {
            GlassEditorCommitDetail(workspace: workspace, projectID: projectID, repository: repository,
                                    commit: commit, focusPath: path, ask: ask) { parent in
                selection = commits.first { $0.hash == parent }?.hash ?? selection
            }
            .id(commit.hash)
        } else {
            ContentUnavailableView("No Commit Chosen", systemImage: "clock",
                                   description: Text("Choose a commit to see its changes."))
        }
    }

    @ViewBuilder
    private func commitMenu(_ commit: GlassEditorGitCommit) -> some View {
        GlassEditorCommitActions(workspace: workspace, projectID: projectID, repository: repository, commit: commit, ask: ask)
    }
}

/// What can be done from a commit: the History's menu and the details' buttons.
struct GlassEditorCommitActions: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let commit: GlassEditorGitCommit
    let ask: (GlassEditorGitRequest) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let isHead = commit.hash == repository.status.commit
        Button("Copy Hash", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(commit.hash) }
        Button("Copy Message", systemImage: "text.quote") { GlassEditorPasteboard.copy(commit.message) }
        if let remote = repository.mainRemote, let address = remote.webAddress(ofCommit: commit.hash) {
            Button("Open on \(remote.isGitHub ? "GitHub" : "the Web")", systemImage: "safari") { openURL(address) }
        }
        Divider()
        Button("New Branch Here…", systemImage: "arrow.triangle.branch") {
            ask(.newBranch(start: commit.hash, from: "\(commit.shortHash) “\(commit.subject)”"))
        }
        Button("New Tag Here…", systemImage: "tag") {
            ask(.newTag(commit: commit.hash, from: "\(commit.shortHash) “\(commit.subject)”"))
        }
        Button("Check Out This Commit…", systemImage: "arrow.uturn.down") {
            ask(.confirm(GlassEditorGitConfirmation(
                title: "Check Out \(commit.shortHash)?",
                message: "The files become this commit's, on no branch (a detached HEAD). New commits here belong to no branch until you make one.",
                button: "Check Out", isDestructive: false) {
                    await workspace.git(projectID) { await $0.checkout(commit: commit.hash) }
                }))
        }
        .disabled(isHead)
        Divider()
        if !isHead {
            Button("Cherry-Pick", systemImage: "arrow.down.right.circle") {
                Task { await workspace.git(projectID) { await $0.cherryPick(commit.hash) } }
            }
            .disabled(commit.isMerge)
        }
        Button("Revert…", systemImage: "arrow.uturn.backward.circle") {
            ask(.confirm(GlassEditorGitConfirmation(
                title: "Revert \(commit.shortHash)?",
                message: "A new commit undoes “\(commit.subject)”. The history keeps both.",
                button: "Revert", isDestructive: false) {
                    await workspace.git(projectID) { await $0.revert(commit.hash) }
                }))
        }
        .disabled(commit.isMerge)
        if isHead, repository.status.branch != nil {
            Button("Amend…", systemImage: "pencil") {
                repository.amends = true
                workspace.gitSections[projectID] = .changes
                Task {
                    if repository.commitMessage.isEmpty, let message = await repository.lastCommitMessage() {
                        repository.commitMessage = message
                    }
                }
            }
        }
        if !isHead, let branch = repository.status.branch {
            Menu("Reset \(branch) to Here", systemImage: "arrow.counterclockwise") {
                ForEach(GlassEditorGitResetMode.allCases, id: \.self) { mode in
                    Button(Self.title(of: mode), role: mode == .hard ? .destructive : nil) {
                        ask(.confirm(GlassEditorGitConfirmation(
                            title: "Reset \(branch) to \(commit.shortHash)?",
                            message: Self.explanation(of: mode, branch: branch),
                            button: "Reset", isDestructive: mode == .hard) {
                                await workspace.git(projectID) { await $0.reset(to: commit.hash, mode: mode) }
                            }))
                    }
                }
            }
        }
    }

    static func title(of mode: GlassEditorGitResetMode) -> String {
        switch mode {
        case .soft: "Keep Changes Staged (Soft)"
        case .mixed: "Keep Changes Unstaged (Mixed)"
        case .hard: "Discard Changes (Hard)…"
        }
    }

    static func explanation(of mode: GlassEditorGitResetMode, branch: String) -> String {
        switch mode {
        case .soft: "\(branch) moves back to this commit. The changes in the commits after it stay, staged, ready to commit again."
        case .mixed: "\(branch) moves back to this commit. The changes in the commits after it stay in the files, unstaged."
        case .hard: "\(branch) moves back to this commit and the files with it. The commits after it, and every uncommitted change, are thrown away. This can't be undone from here."
        }
    }
}

/// A commit's message, its author, its parents and its changes.
struct GlassEditorCommitDetail: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let commit: GlassEditorGitCommit
    /// A file whose history this is: its changes first, the rest folded.
    let focusPath: String?
    let ask: (GlassEditorGitRequest) -> Void
    let showParent: (String) -> Void

    @State private var files: [GlassEditorFileDiff]?
    @State private var folded: Set<String> = []
    @State private var width: CGFloat = 1000
    @AppStorage(GlassEditorDiffSettings.layoutKey) private var layout = GlassEditorDiffLayout.unified
    @AppStorage(GlassEditorDiffSettings.contextKey) private var context = 0
    @AppStorage(GlassEditorDiffSettings.whitespaceKey) private var ignoresWhitespace = false

    private var fontSize: Double { workspace.windowTextConfiguration.fontSize }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                Divider()
                if let files {
                    if files.isEmpty {
                        Text("No files changed.").foregroundStyle(.secondary).padding(12)
                    }
                    ForEach(files) { file in
                        let key = "commit:\(commit.hash):\(file.id)"
                        Section {
                            if !folded.contains(key) {
                                if file.isBinary {
                                    Text("Binary file: git shows no lines.").font(.callout).foregroundStyle(.secondary).padding(12)
                                } else if file.hunks.isEmpty {
                                    Text(file.oldMode != file.newMode ? "Mode changed." : "No lines changed.")
                                        .font(.callout).foregroundStyle(.secondary).padding(12)
                                } else {
                                    GlassEditorDiffBody(file: file, rowID: key, layout: GlassEditorDiffLayout.fitting(layout, width: width),
                                                        fontSize: fontSize,
                                                        wraps: workspace.windowTextConfiguration.wrapsLines)
                                }
                            }
                        } header: {
                            fileHeader(file, key: key)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(24)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: "\(context)|\(ignoresWhitespace)") {
            var read = await repository.diff(of: commit, context: GlassEditorDiffSettings.context(context),
                                             ignoringWhitespace: ignoresWhitespace) ?? []
            if let focus = focusPath.flatMap({ repository.repositoryPath(of: $0) }) {
                // The file first, as it was named in this commit; the others folded.
                read.sort { ($0.newPath == focus || $0.oldPath == focus) && !($1.newPath == focus || $1.oldPath == focus) }
                folded = Set(read.filter { $0.newPath != focus && $0.oldPath != focus }.map { "commit:\(commit.hash):\($0.id)" })
            }
            files = read
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commit.subject)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs, id: \.self) { GlassEditorRefBadge(ref: $0, remotes: repository.remotes.map(\.name)) }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(commit.author) <\(commit.email)>").textSelection(.enabled)
                Text(GlassEditorGitDates.full(commit.date))
                HStack(spacing: 6) {
                    Text(commit.hash).monospaced().textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button("Copy", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(commit.hash) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Copy the commit's hash")
                }
                if !commit.parents.isEmpty {
                    HStack(spacing: 6) {
                        Text(commit.parents.count == 1 ? "Parent" : "Parents")
                        ForEach(commit.parents, id: \.self) { parent in
                            Button(String(parent.prefix(7))) { showParent(parent) }
                                .buttonStyle(.borderless)
                                .monospaced()
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Menu("Actions") {
                    GlassEditorCommitActions(workspace: workspace, projectID: projectID, repository: repository,
                                             commit: commit, ask: ask)
                }
                .fixedSize()
                .accessibilityIdentifier("editor-commit-actions")
                if let files {
                    let added = files.reduce(0) { $0 + $1.addedLines }, removed = files.reduce(0) { $0 + $1.removedLines }
                    Text("\(files.count) file\(files.count == 1 ? "" : "s")  +\(added) −\(removed)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(GlassSpatialMetrics.isSpatial ? 20 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileHeader(_ file: GlassEditorFileDiff, key: String) -> some View {
        let path = repository.projectRelative(file.id)
        let isFolded = folded.contains(key)
        let letter = file.oldPath == nil ? "A" : file.newPath == nil ? "D" : file.oldPath != file.newPath ? "R" : "M"
        let tint: Color = switch letter { case "A": .green; case "D": .red; case "R": .blue; default: .orange }
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isFolded ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(letter).font(.caption.monospaced().weight(.bold)).foregroundStyle(tint)
            Text((path as NSString).lastPathComponent).font(.body.weight(.semibold)).lineLimit(1)
            Text((path as NSString).deletingLastPathComponent)
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            if let old = file.oldPath, let new = file.newPath, old != new {
                Text("from \(repository.projectRelative(old))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if !file.isBinary {
                if file.addedLines > 0 { Text("+\(file.addedLines)").foregroundStyle(.green) }
                if file.removedLines > 0 { Text("−\(file.removedLines)").foregroundStyle(.red) }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture { if isFolded { folded.remove(key) } else { folded.insert(key) } }
        .contextMenu {
            if file.newPath != nil, let absolute = repository.absolutePath(file.id) {
                Button("Open", systemImage: "arrow.up.forward.square") {
                    Task { await workspace.openChangedFile(file.id, in: projectID) }
                }
                Button("Blame", systemImage: "person.text.rectangle") { workspace.showGit(.blame(absolute), of: absolute) }
                Button("File History", systemImage: "clock.arrow.circlepath") { workspace.showGit(.history(absolute), of: absolute) }
            }
            Button("Copy Path", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(path) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isFolded ? "Shows its lines" : "Hides its lines")
    }
}

/// A branch or a tag at a commit, as a small label: `HEAD -> main`, `origin/main`, `tag: v1`.
struct GlassEditorRefBadge: View {
    let ref: String
    /// The remotes' names: `origin/main` is a remote's branch, `feature/units` a local one.
    var remotes: [String] = []

    var body: some View {
        let isTag = ref.hasPrefix("tag: ")
        let isHead = ref.hasPrefix("HEAD")
        let name = isTag ? String(ref.dropFirst(5)) : isHead ? ref.replacingOccurrences(of: "HEAD -> ", with: "") : ref
        let isRemote = !isTag && !isHead && remotes.contains { name.hasPrefix($0 + "/") }
        let tint: Color = isTag ? .yellow : isHead ? .accentColor : isRemote ? .purple : .green
        HStack(spacing: 2) {
            Image(systemName: isTag ? "tag.fill" : isHead ? "checkmark.circle.fill" : isRemote ? "network" : "arrow.triangle.branch")
                .imageScale(.small)
            Text(name).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(tint.opacity(0.22)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.5))
        .fixedSize()
        .help(ref)
    }
}

/// One row's part of the graph: lanes passing, the lines into the commit from its children, the
/// commit's dot, and the lines out to its parents.
struct GlassEditorGraphCell: View {
    let row: GlassEditorGitGraphRow
    let isMerge: Bool

    nonisolated static let laneWidth: CGFloat = 12
    nonisolated static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo, .mint, .brown]

    var body: some View {
        Canvas { context, size in
            let top: CGFloat = 0, bottom = size.height, middle = size.height / 2
            func x(_ lane: Int) -> CGFloat { CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2 + 3 }
            func color(_ lane: Int) -> Color { Self.colors[lane % Self.colors.count] }
            func stroke(_ path: Path, _ lane: Int) {
                context.stroke(path, with: .color(color(lane)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            for lane in row.passing {
                stroke(Path { $0.move(to: CGPoint(x: x(lane), y: top)); $0.addLine(to: CGPoint(x: x(lane), y: bottom)) }, lane)
            }
            for lane in row.incoming {
                stroke(Path { path in
                    path.move(to: CGPoint(x: x(lane), y: top))
                    if lane == row.lane {
                        path.addLine(to: CGPoint(x: x(lane), y: middle))
                    } else {
                        path.addCurve(to: CGPoint(x: x(row.lane), y: middle),
                                      control1: CGPoint(x: x(lane), y: middle * 0.8),
                                      control2: CGPoint(x: x(row.lane), y: middle * 0.4))
                    }
                }, lane)
            }
            for lane in row.outgoing {
                stroke(Path { path in
                    path.move(to: CGPoint(x: x(row.lane), y: middle))
                    if lane == row.lane {
                        path.addLine(to: CGPoint(x: x(lane), y: bottom))
                    } else {
                        path.addCurve(to: CGPoint(x: x(lane), y: bottom),
                                      control1: CGPoint(x: x(row.lane), y: middle + (bottom - middle) * 0.6),
                                      control2: CGPoint(x: x(lane), y: middle + (bottom - middle) * 0.2))
                    }
                }, lane)
            }
            let radius: CGFloat = isMerge ? 3.5 : 4.5
            let dot = CGRect(x: x(row.lane) - radius, y: middle - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(color(row.lane)))
            if isMerge {
                context.stroke(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(color(row.lane)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
