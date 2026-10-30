//
//  GlassEditorReferencesView.swift
//  Glass Power Tools — GlassEditor
//
//  Source Control's **Branches**, **Stashes** and **Tags** (2026-10-28). Branches: this
//  repository's and each remote's, the one checked out marked, each with how far it is ahead of and
//  behind what it follows; switch to one, merge it, rebase onto it, branch from it, rename, push or
//  delete it, open it — or begin a pull request — on GitHub. Stashes: the changes put away, each
//  one's lines, applied, popped or dropped. Tags: made, pushed, deleted, and shown in History.
//

import SwiftUI
import GlassConnectionUI

struct GlassEditorBranchesView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let ask: (GlassEditorGitRequest) -> Void
    @Environment(\.openURL) private var openURL
    @State private var filter = ""

    private var current: String? { repository.status.branch }

    private func matches(_ branch: GlassEditorGitBranch) -> Bool {
        filter.isEmpty || branch.name.localizedCaseInsensitiveContains(filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("editor-branches-filter")
                Spacer()
                Button("New Branch…", systemImage: "plus") {
                    ask(.newBranch(start: nil, from: repository.status.headName))
                }
                .disabled(repository.status.commit == nil)
                .accessibilityIdentifier("editor-new-branch")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            List {
                let locals = repository.branches.filter { !$0.isRemote && matches($0) }
                Section("Branches") {
                    if locals.isEmpty {
                        Text(repository.status.commit == nil ? "No commits yet: the first commit makes the branch." : "None match.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(locals) { branch in row(branch) }
                }
                ForEach(remoteNames, id: \.self) { remote in
                    let branches = repository.branches.filter { $0.isRemote && $0.remote == remote && matches($0) }
                    if !branches.isEmpty {
                        Section(remote) {
                            ForEach(branches) { branch in row(branch) }
                        }
                    }
                }
            }
            .accessibilityIdentifier("editor-branches")
        }
    }

    private var remoteNames: [String] {
        var names: [String] = []
        for branch in repository.branches where branch.isRemote {
            if let remote = branch.remote, !names.contains(remote) { names.append(remote) }
        }
        return names
    }

    private func row(_ branch: GlassEditorGitBranch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : (branch.isRemote ? "network" : "arrow.triangle.branch"))
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(branch.isRemote ? branch.shortName : branch.name)
                        .fontWeight(branch.isCurrent ? .semibold : .regular)
                        .lineLimit(1)
                    if let upstream = branch.upstream {
                        Text(upstream)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if branch.upstreamGone {
                        Text("upstream gone").font(.caption).foregroundStyle(.orange)
                    }
                    if branch.ahead + branch.behind > 0 {
                        Text([branch.ahead > 0 ? "↑\(branch.ahead)" : nil, branch.behind > 0 ? "↓\(branch.behind)" : nil]
                            .compactMap { $0 }.joined(separator: " "))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(String(branch.commit.prefix(7))) \(branch.subject)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(GlassEditorGitDates.relative(branch.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu { menu(branch) }
        .glassSpatialListRow()
        .onTapGesture(count: 2) {
            guard !branch.isCurrent else { return }
            Task { await workspace.git(projectID) { await $0.checkout(branch) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(branch.isCurrent ? "\(branch.name), checked out" : branch.name)
        .accessibilityActions { menu(branch) }
        .accessibilityIdentifier("editor-branch-\(branch.name)")
    }

    @ViewBuilder
    private func menu(_ branch: GlassEditorGitBranch) -> some View {
        if !branch.isCurrent {
            Button(branch.isRemote ? "Check Out as \(branch.shortName)" : "Switch To", systemImage: "arrow.uturn.down") {
                Task { await workspace.git(projectID) { await $0.checkout(branch) } }
            }
        }
        if let current, !branch.isCurrent {
            Button("Merge into \(current)", systemImage: "arrow.triangle.merge") {
                ask(.confirm(GlassEditorGitConfirmation(
                    title: "Merge \(branch.name) into \(current)?",
                    message: "\(branch.name)'s commits join \(current). If both changed the same lines, git stops so you can choose.",
                    button: "Merge", isDestructive: false) {
                        await workspace.git(projectID) { await $0.merge(branch.name) }
                    }))
            }
            Button("Rebase \(current) onto This", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                ask(.confirm(GlassEditorGitConfirmation(
                    title: "Rebase \(current) onto \(branch.name)?",
                    message: "\(current)'s own commits are made again on top of \(branch.name), as new commits. Don't rebase commits others already have.",
                    button: "Rebase", isDestructive: false) {
                        await workspace.git(projectID) { await $0.rebase(onto: branch.name) }
                    }))
            }
        }
        Button("New Branch from This…", systemImage: "plus") {
            ask(.newBranch(start: branch.name, from: branch.name))
        }
        if !branch.isRemote {
            Button("Rename…", systemImage: "pencil") { ask(.renameBranch(branch)) }
            Button(branch.upstream == nil ? "Publish" : "Push", systemImage: "arrow.up") {
                Task { await repository.push(branch) }
            }
        }
        Divider()
        if let remote = branch.isRemote ? repository.remotes.first(where: { $0.name == branch.remote }) : repository.webRemote(for: branch.name) {
            let name = branch.isRemote ? branch.shortName : (branch.upstream.map { upstream in
                remote.name.isEmpty ? upstream : String(upstream.dropFirst(remote.name.count + 1)) } ?? branch.name)
            if let page = remote.webAddress(ofBranch: name), branch.isRemote || branch.upstream != nil {
                Button("Open on \(remote.isGitHub ? "GitHub" : "the Web")", systemImage: "safari") { openURL(page) }
            }
            if (branch.isRemote || branch.upstream != nil), let pull = remote.pullRequestAddress(for: name),
               remote.isGitHub || remote.isGitLab {
                Button(remote.isGitLab ? "Create Merge Request" : "Create Pull Request", systemImage: "arrow.triangle.pull") {
                    openURL(pull)
                }
            }
        }
        Button("Copy Name", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(branch.name) }
        if !branch.isCurrent {
            Divider()
            Button(branch.isRemote ? "Delete on \(branch.remote ?? "the Remote")…" : "Delete…", systemImage: "trash", role: .destructive) {
                confirmDelete(branch)
            }
        }
    }

    private func confirmDelete(_ branch: GlassEditorGitBranch) {
        ask(.confirm(GlassEditorGitConfirmation(
            title: branch.isRemote ? "Delete \(branch.shortName) on \(branch.remote ?? "the remote")?" : "Delete \(branch.name)?",
            message: branch.isRemote ? "The branch is deleted on the remote, for everyone who uses it."
                : "Only the branch's name goes; its commits stay wherever another branch has them.",
            button: "Delete") {
                switch await repository.delete(branch) {
                case .notMerged:
                    ask(.confirm(GlassEditorGitConfirmation(
                        title: "\(branch.name) Isn't Merged",
                        message: "Its commits are on no other branch. Deleting it loses them, unless you know their hashes.",
                        button: "Delete Anyway") {
                            _ = await repository.delete(branch, force: true)
                        }))
                case .deleted, .notDeleted:
                    break
                }
            }))
    }
}

// MARK: - Stashes

struct GlassEditorStashesView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let ask: (GlassEditorGitRequest) -> Void

    @State private var selection: String?
    @State private var files: [GlassEditorFileDiff]?
    @State private var folded: Set<String> = []
    @State private var width: CGFloat = 1000
    @AppStorage(GlassEditorDiffSettings.layoutKey) private var layout = GlassEditorDiffLayout.unified

    private var selected: GlassEditorGitStash? { repository.stashes.first { $0.commit == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(repository.stashes.isEmpty ? "No stashes" : "\(repository.stashes.count) stash\(repository.stashes.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stash Changes…", systemImage: "tray.and.arrow.down") { ask(.stash) }
                    .disabled(repository.status.changes.isEmpty || repository.isWorking)
                    .help("Put your uncommitted changes away, and go back to the last commit")
                    .accessibilityIdentifier("editor-stash")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if repository.stashes.isEmpty {
                ContentUnavailableView("No Stashes", systemImage: "tray",
                                       description: Text("Stash your changes to put them away for later and work from the last commit."))
            } else {
                GeometryReader { geometry in
                    if geometry.size.width >= 720 {
                        HStack(spacing: 0) {
                            list.frame(width: max(280, geometry.size.width * 0.36))
                            Divider()
                            detail
                        }
                    } else {
                        VStack(spacing: 0) {
                            list.frame(height: min(220, geometry.size.height * 0.4))
                            Divider()
                            detail
                        }
                    }
                }
            }
        }
        .task(id: selection) {
            files = nil
            guard let selected else { return }
            files = await repository.diff(of: selected) ?? []
        }
        .onChange(of: repository.stashes) { _, stashes in
            if !stashes.contains(where: { $0.commit == selection }) { selection = stashes.first?.commit }
        }
        .onAppear { if selection == nil { selection = repository.stashes.first?.commit } }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(repository.stashes) { stash in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stash.message).lineLimit(2)
                    Text("\(stash.name) · \(GlassEditorGitDates.relative(stash.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(stash.commit)
                .contextMenu { menu(stash) }
                .accessibilityActions { menu(stash) }
                .glassSpatialListRow()
            }
        }
        .accessibilityIdentifier("editor-stashes")
    }

    @ViewBuilder
    private func menu(_ stash: GlassEditorGitStash) -> some View {
        Button("Apply", systemImage: "tray.and.arrow.up") {
            Task { await workspace.git(projectID) { await $0.apply(stash) } }
        }
        Button("Pop", systemImage: "arrow.up.bin") {
            Task { await workspace.git(projectID) { await $0.pop(stash) } }
        }
        Divider()
        Button("Drop…", systemImage: "trash", role: .destructive) {
            ask(.confirm(GlassEditorGitConfirmation(
                title: "Drop \(stash.name)?",
                message: "“\(stash.message)” is deleted. Its changes can't be brought back from here.",
                button: "Drop") { _ = await repository.drop(stash) }))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.message).font(.headline).textSelection(.enabled)
                            Text("\(selected.name) · \(selected.date.map(GlassEditorGitDates.full) ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") { Task { await workspace.git(projectID) { await $0.apply(selected) } } }
                            .help("Bring the changes back, and keep the stash")
                        Button("Pop") { Task { await workspace.git(projectID) { await $0.pop(selected) } } }
                            .buttonStyle(.borderedProminent)
                            .help("Bring the changes back, and drop the stash")
                    }
                    .disabled(repository.isWorking)
                    .padding(12)
                    Divider()
                    if let files {
                        ForEach(files) { file in
                            let key = "stash:\(selected.commit):\(file.id)"
                            Section {
                                if !folded.contains(key), !file.hunks.isEmpty {
                                    GlassEditorDiffBody(file: file, rowID: key, layout: GlassEditorDiffLayout.fitting(layout, width: width),
                                                        fontSize: workspace.windowTextConfiguration.fontSize,
                                                        wraps: workspace.windowTextConfiguration.wrapsLines)
                                }
                            } header: {
                                GlassEditorPlainFileHeader(file: file, path: repository.projectRelative(file.id),
                                                           isFolded: folded.contains(key)) {
                                    if folded.contains(key) { folded.remove(key) } else { folded.insert(key) }
                                }
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(24)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        } else {
            ContentUnavailableView("No Stash Chosen", systemImage: "tray", description: Text("Choose a stash to see its changes."))
        }
    }
}

/// A file's header in a diff nothing can be staged from: a stash's.
struct GlassEditorPlainFileHeader: View {
    let file: GlassEditorFileDiff
    let path: String
    let isFolded: Bool
    let toggle: () -> Void

    var body: some View {
        let letter = file.oldPath == nil ? "A" : file.newPath == nil ? "D" : file.oldPath != file.newPath ? "R" : "M"
        let tint: Color = switch letter { case "A": .green; case "D": .red; case "R": .blue; default: .orange }
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isFolded ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(letter).font(.caption.monospaced().weight(.bold)).foregroundStyle(tint)
            Text((path as NSString).lastPathComponent).font(.body.weight(.semibold)).lineLimit(1)
            Text((path as NSString).deletingLastPathComponent)
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 8)
            if file.isBinary {
                Text("binary").foregroundStyle(.secondary)
            } else {
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
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Tags

struct GlassEditorTagsView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let ask: (GlassEditorGitRequest) -> Void
    @Environment(\.openURL) private var openURL
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button("New Tag…", systemImage: "plus") {
                    if let commit = repository.status.commit {
                        ask(.newTag(commit: commit, from: repository.status.headName))
                    }
                }
                .disabled(repository.status.commit == nil)
                .accessibilityIdentifier("editor-new-tag")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            let tags = repository.tags.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
            if repository.tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag",
                                       description: Text("Tag a commit to mark a release. New Tag… tags the one checked out; History tags any."))
            } else {
                List(tags) { tag in
                    HStack(spacing: 8) {
                        Image(systemName: tag.isAnnotated ? "tag.fill" : "tag")
                            .foregroundStyle(.yellow)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name).lineLimit(1)
                            Text("\(String(tag.commit.prefix(7))) \(tag.subject)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(GlassEditorGitDates.relative(tag.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showInHistory(tag) }
                    .contextMenu { menu(tag) }
                    .accessibilityElement(children: .combine)
                    .accessibilityActions { menu(tag) }
                    .glassSpatialListRow()
                }
                .accessibilityIdentifier("editor-tags")
            }
        }
    }

    private func showInHistory(_ tag: GlassEditorGitTag) {
        workspace.showSourceControl(.history, of: projectID, commit: tag.commit)
    }

    @ViewBuilder
    private func menu(_ tag: GlassEditorGitTag) -> some View {
        Button("Show in History", systemImage: "clock.arrow.circlepath") { showInHistory(tag) }
        Button("Check Out…", systemImage: "arrow.uturn.down") {
            ask(.confirm(GlassEditorGitConfirmation(
                title: "Check Out \(tag.name)?",
                message: "The files become \(tag.name)'s, on no branch (a detached HEAD). Make a branch there to commit.",
                button: "Check Out", isDestructive: false) {
                    await workspace.git(projectID) { await $0.checkout(commit: tag.commit) }
                }))
        }
        Button("New Branch Here…", systemImage: "arrow.triangle.branch") {
            ask(.newBranch(start: tag.name, from: tag.name))
        }
        if repository.mainRemote != nil {
            Button("Push", systemImage: "arrow.up") { Task { _ = await repository.push(tag) } }
        }
        if let remote = repository.mainRemote, let address = remote.webAddress(ofCommit: tag.commit) {
            Button("Open on \(remote.isGitHub ? "GitHub" : "the Web")", systemImage: "safari") { openURL(address) }
        }
        Button("Copy Name", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(tag.name) }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            ask(.confirm(GlassEditorGitConfirmation(
                title: "Delete \(tag.name)?",
                message: "The tag goes from this repository. A copy pushed to the remote stays there.",
                button: "Delete") { _ = await repository.delete(tag) }))
        }
        if let remote = repository.mainRemote {
            Button("Delete on \(remote.name)…", systemImage: "trash", role: .destructive) {
                ask(.confirm(GlassEditorGitConfirmation(
                    title: "Delete \(tag.name) on \(remote.name)?",
                    message: "The tag is deleted on the remote, for everyone who uses it.",
                    button: "Delete") { _ = await repository.deleteOnRemote(tag) }))
            }
        }
    }
}
