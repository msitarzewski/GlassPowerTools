//
//  GlassEditorChangesView.swift
//  Glass Power Tools — GlassEditor
//
//  Source Control's **Changes**: every file that differs from the last commit, with its lines, in
//  one scroll — what `git diff` says, as Zed's project diff shows it (the owner, 2026-10-23: "I'd
//  like to be able to see 'this' instead of having to open Zed").
//
//  Each file's header stays at the top while its lines scroll under it, and folds away. A line
//  opens its file there; the header's button opens the file. The tab keeps itself current while it
//  is open, as the terminal beside it changes things.
//
//  It commits, too (2026-10-23: "add gutter marks and stage/commit too"): each file's box stages
//  or unstages it, and the message above them commits what is staged — or, with nothing staged,
//  everything listed, as VS Code's smart commit does. Since 2026-10-28 what is staged is listed
//  apart from what isn't, as VS Code, Sublime Merge and Fork list it, because each hunk — or the
//  lines chosen in it — is staged from the one and unstaged from the other; a file a merge stopped
//  on is listed first, with its conflicts to settle.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import GlassConnectionUI

struct GlassEditorChangesView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    let ask: (GlassEditorGitRequest) -> Void

    /// Files folded away, by their place in the list ("staged:" or "unstaged:", then the path).
    @State private var folded: Set<String> = []
    /// The lines chosen in each file's hunks, by the same key.
    @State private var chosen: [String: [Int: Set<Int>]] = [:]
    /// Conflicted files being resolved here, by path.
    @State private var resolving: Set<String> = []
    /// Staged files outside the project's folder that a commit would take too, while it asks.
    @State private var stagedOutside: [String]?
    @FocusState private var messageFocused: Bool
    @Environment(\.openURL) private var openURL
    @AppStorage(GlassEditorDiffSettings.layoutKey) private var layout = GlassEditorDiffLayout.unified
    @AppStorage(GlassEditorDiffSettings.contextKey) private var context = 0
    @AppStorage(GlassEditorDiffSettings.whitespaceKey) private var ignoresWhitespace = false
    /// How wide the list is: side by side needs room, and falls back to unified without it.
    @State private var width: CGFloat = 1000

    private var fontSize: Double { workspace.windowTextConfiguration.fontSize }
    private var shownLayout: GlassEditorDiffLayout { GlassEditorDiffLayout.fitting(layout, width: width) }

    var body: some View {
        VStack(spacing: 0) {
            if !repository.status.changes.isEmpty || repository.amends {
                commitBar
                Divider()
            }
            if repository.status.changes.isEmpty {
                ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text(noChanges))
            } else {
                changes
            }
        }
        .alert("Commit Files Outside This Folder Too?", isPresented: Binding(
            get: { stagedOutside != nil }, set: { if !$0 { stagedOutside = nil } }
        )) {
            Button("Commit") {
                stagedOutside = nil
                Task { await repository.commit(includingOutside: true) }
            }
            Button("Cancel", role: .cancel) { stagedOutside = nil }
        } message: {
            Text(outsideMessage)
        }
        .onChange(of: context, initial: true) { _, value in repository.diffContext = GlassEditorDiffSettings.context(value) }
        .onChange(of: ignoresWhitespace, initial: true) { _, value in repository.ignoresWhitespace = value }
        // Chosen lines belong to the diff they were chosen in; a new one has other hunks.
        .onChange(of: repository.unstagedDiffs) { chosen = chosen.filter { !$0.key.hasPrefix("unstaged:") } }
        .onChange(of: repository.stagedDiffs) { chosen = chosen.filter { !$0.key.hasPrefix("staged:") } }
    }

    private var noChanges: String {
        let matches = "Everything matches the last commit on \(repository.status.headName)."
        guard let commit = repository.lastCommit else { return matches }
        let name = commit.name.map { " \($0)" } ?? ""
        let branch = commit.branch.map { " to \($0)" } ?? ""
        return "Committed\(name)\(branch): \(commit.summary)\n\(matches)"
    }

    /// "1 commit", "3 commits".
    static func commits(_ count: Int) -> String { count == 1 ? "1 commit" : "\(count) commits" }

    // MARK: Committing

    private var commitBar: some View {
        @Bindable var repository = repository
        let staged = repository.status.changes.filter(\.isStaged).count
        let total = repository.status.changes.count
        let message = repository.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = repository.amends ? "Amend" : (staged > 0 ? "Commit" : "Commit All")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField(repository.amends ? "Message (empty keeps the last one)" : "Message",
                          text: $repository.commitMessage, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($messageFocused)
                    .accessibilityIdentifier("editor-commit-message")
                Button(title) { commit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled((message.isEmpty && !repository.amends) || repository.isWorking
                              || repository.status.changes.contains { $0.kind == .conflicted })
                    .help(repository.amends ? "Make the last commit again with what is staged (⌘↩)"
                          : staged > 0 ? "Commit the staged files (⌘↩)" : "Stage every change listed and commit it (⌘↩)")
                    .accessibilityIdentifier("editor-commit")
            }
            HStack(spacing: 8) {
                Button {
                    Task {
                        if staged == total { await repository.unstageAll() } else { await repository.stageAll() }
                    }
                } label: {
                    Label(staged == total ? "Unstage All" : "Stage All",
                          systemImage: Self.boxSymbol(staged: staged, of: total))
                }
                .buttonStyle(.borderless)
                .disabled(repository.isWorking || total == 0)
                .accessibilityIdentifier("editor-stage-all")
                Text(staged == 0 ? "Nothing staged" : "\(staged) of \(total) staged")
                    .foregroundStyle(.secondary)
                Toggle("Amend", isOn: Binding(get: { repository.amends }, set: { amend($0) }))
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .disabled(repository.status.commit == nil || repository.isWorking)
                    .help("Replace the last commit instead of adding one: its changes, what is staged now, and this message")
                    .accessibilityIdentifier("editor-amend")
                Spacer(minLength: 0)
                if let commit = repository.lastCommit {
                    Text("Committed\(commit.name.map { " \($0)" } ?? ""): \(commit.summary)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("editor-last-commit")
                } else if repository.hasReadDiffs {
                    Text(totals).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, 8)
    }

    /// Amending begins from the last commit's message, as `git commit --amend` does.
    private func amend(_ on: Bool) {
        repository.amends = on
        guard on, repository.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if let message = await repository.lastCommitMessage(), repository.amends,
               repository.commitMessage.isEmpty {
                repository.commitMessage = message
            }
        }
    }

    private func commit() {
        guard !repository.isWorking else { return }
        Task {
            if case .alsoStagedOutside(let paths) = await repository.commit() {
                stagedOutside = paths
            } else if repository.actionProblem == nil {
                messageFocused = false
            }
        }
    }

    private var outsideMessage: String {
        let paths = stagedOutside ?? []
        let shown = paths.prefix(5).joined(separator: "\n")
        let more = paths.count > 5 ? "\nand \(paths.count - 5) more" : ""
        return "These are staged outside the project's folder, so they aren't listed here, and they'd be in the commit too:\n\(shown)\(more)"
    }

    /// A box for how much is staged: ticked for all of it, a dash for some, empty for none.
    static func boxSymbol(staged: Int, of total: Int) -> String {
        if staged == 0 { return "square" }
        return staged == total ? "checkmark.square.fill" : "minus.square.fill"
    }

    private var totals: String {
        let files = repository.status.changes.count
        let counted = "\(files) file\(files == 1 ? "" : "s")"
        let all = Array(repository.stagedDiffs.values) + Array(repository.unstagedDiffs.values)
        let added = all.reduce(0) { $0 + $1.addedLines }
        let removed = all.reduce(0) { $0 + $1.removedLines }
        return "\(counted)  +\(added) −\(removed)"
    }

    // MARK: The lists

    private enum Group: String {
        case conflicts, staged, unstaged
    }

    private var conflicted: [GlassEditorGitChange] { repository.status.changes.filter { $0.kind == .conflicted } }
    private var staged: [GlassEditorGitChange] { repository.status.changes.filter { $0.isStaged && $0.kind != .conflicted } }
    private var unstaged: [GlassEditorGitChange] { repository.status.changes.filter { $0.isUnstaged && $0.kind != .conflicted } }

    private var changes: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let problem = repository.diffProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                if !conflicted.isEmpty {
                    groupTitle("Conflicts", count: conflicted.count, group: .conflicts)
                    ForEach(conflicted) { change in
                        Section {
                            if resolving.contains(change.path) {
                                GlassEditorConflictView(workspace: workspace, projectID: projectID,
                                                        repository: repository, path: change.path) {
                                    resolving.remove(change.path)
                                }
                            }
                        } header: {
                            conflictHeader(change)
                        }
                    }
                }
                // Staged changes have a list of their own only once there are some: with nothing
                // staged, this is the one list it always was.
                if !staged.isEmpty {
                    groupTitle("Staged Changes", count: staged.count, group: .staged)
                    // Identified by list and path: a file staged and changed again is in both lists,
                    // and one identity for the two left the second without its header (rendered).
                    ForEach(staged, id: \.stagedKey) { change in
                        fileSection(change, group: .staged, diff: repository.stagedDiffs[change.path])
                    }
                }
                if !unstaged.isEmpty {
                    if !staged.isEmpty || !conflicted.isEmpty {
                        groupTitle("Changes", count: unstaged.count, group: .unstaged)
                    }
                    ForEach(unstaged, id: \.unstagedKey) { change in
                        fileSection(change, group: .unstaged, diff: repository.unstagedDiffs[change.path])
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityIdentifier("editor-changes")
    }

    private func groupTitle(_ title: String, count: Int, group: Group) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            switch group {
            case .staged:
                Button("Unstage All", systemImage: "minus.circle") { Task { await repository.unstageAll() } }
                    .disabled(repository.isWorking)
            case .unstaged:
                Button("Discard All…", systemImage: "arrow.uturn.backward.circle") { confirmDiscardAll() }
                    .disabled(repository.isWorking)
                Button("Stage All", systemImage: "plus.circle") { Task { await repository.stageAll() } }
                    .disabled(repository.isWorking)
            case .conflicts:
                EmptyView()
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func fileSection(_ change: GlassEditorGitChange, group: Group, diff: GlassEditorFileDiff?) -> some View {
        let key = group.rawValue + ":" + change.path
        Section {
            if !folded.contains(key) {
                lines(of: change, diff: diff, group: group, key: key)
            }
        } header: {
            fileHeader(change, group: group, diff: diff, key: key)
        }
    }

    // MARK: A file

    private func fileHeader(_ change: GlassEditorGitChange, group: Group, diff: GlassEditorFileDiff?,
                            key: String) -> some View {
        let path = repository.projectRelative(change.path)
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        let isFolded = folded.contains(key)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isFolded ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            if GlassEditorGitRepository.canStage(change) {
                stageBox(change, group: group, name: name)
            }
            GlassEditorGitMark(change: change)
            Text(name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if !folder.isEmpty {
                Text(folder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if let original = change.originalPath {
                Text("from \(repository.projectRelative(original))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if let diff, !diff.isBinary {
                if diff.addedLines > 0 { Text("+\(diff.addedLines)").foregroundStyle(.green) }
                if diff.removedLines > 0 { Text("−\(diff.removedLines)").foregroundStyle(.red) }
            }
            if group == .unstaged, GlassEditorGitRepository.canStage(change) {
                Button("Discard Changes to \(name)", systemImage: "arrow.uturn.backward") { confirmDiscard(change) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(repository.isWorking)
                    .help(change.kind == .untracked ? "Delete \(name)" : "Discard the changes to \(name) that aren't staged")
            }
            if change.kind != .deleted {
                Button("Open \(name)", systemImage: "arrow.up.forward.square") {
                    Task { await workspace.openChangedFile(change.path, in: projectID) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open \(name)")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture {
            if isFolded { folded.remove(key) } else { folded.insert(key) }
        }
        .contextMenu { fileMenu(change, group: group) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.description), \(group == .staged ? "staged" : "not staged"): \(path)")
        .accessibilityHint(isFolded ? "Shows its lines" : "Hides its lines")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            // The box and the buttons, which the combined row would otherwise hide.
            if GlassEditorGitRepository.canStage(change) {
                Button(group == .staged ? "Unstage" : "Stage") { toggleStage(change, group: group) }
            }
            if group == .unstaged, GlassEditorGitRepository.canStage(change) {
                Button("Discard Changes") { confirmDiscard(change) }
            }
            if change.kind != .deleted {
                Button("Open") { Task { await workspace.openChangedFile(change.path, in: projectID) } }
            }
        }
        .accessibilityIdentifier("editor-changes-file-\(group == .staged ? "staged-" : "")\(path)")
    }

    @ViewBuilder
    private func fileMenu(_ change: GlassEditorGitChange, group: Group) -> some View {
        if GlassEditorGitRepository.canStage(change) {
            Button(group == .staged ? "Unstage" : "Stage", systemImage: group == .staged ? "minus.circle" : "plus.circle") {
                toggleStage(change, group: group)
            }
        }
        if group == .unstaged, GlassEditorGitRepository.canStage(change) {
            Button(change.kind == .untracked ? "Delete File…" : "Discard Changes…", systemImage: "arrow.uturn.backward") {
                confirmDiscard(change)
            }
        }
        Divider()
        if change.kind != .deleted {
            Button("Open", systemImage: "arrow.up.forward.square") {
                Task { await workspace.openChangedFile(change.path, in: projectID) }
            }
        }
        if let absolute = repository.absolutePath(change.path), change.kind != .untracked, change.kind != .added {
            Button("Blame", systemImage: "person.text.rectangle") { workspace.showGit(.blame(absolute), of: absolute) }
            Button("File History", systemImage: "clock.arrow.circlepath") { workspace.showGit(.history(absolute), of: absolute) }
        }
        if let remote = repository.webRemote(for: repository.status.branch), change.kind != .untracked, change.kind != .added,
           let address = remote.webAddress(ofFile: change.originalPath ?? change.path,
                                           at: repository.status.upstream != nil ? (repository.status.branch ?? "HEAD") : (repository.status.commit ?? "HEAD")) {
            Button("Open on \(remote.isGitHub ? "GitHub" : "the Web")", systemImage: "safari") { openURL(address) }
        }
        Button("Copy Path", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(repository.projectRelative(change.path)) }
    }

    /// Whether the file goes into the next commit: ticked in the staged list, empty in the other.
    /// Pressing it moves the file across.
    private func stageBox(_ change: GlassEditorGitChange, group: Group, name: String) -> some View {
        let isStagedList = group == .staged
        let label = isStagedList ? "Unstage \(name)" : "Stage \(name)"
        return Button(label, systemImage: isStagedList ? "checkmark.square.fill" : "square") {
            toggleStage(change, group: group)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(isStagedList ? Color.accentColor : Color.secondary)
        .disabled(repository.isWorking)
        .help(isStagedList ? "Staged: in the next commit. Press to unstage."
              : change.isStaged ? "Changed again since it was staged. Press to stage the rest."
              : "Not staged. Press to stage it for the next commit.")
        .accessibilityIdentifier("editor-stage-\(isStagedList ? "staged-" : "")\(repository.projectRelative(change.path))")
    }

    private func toggleStage(_ change: GlassEditorGitChange, group: Group) {
        Task {
            if group == .staged { await repository.unstage([change]) } else { await repository.stage([change]) }
        }
    }

    // MARK: Discarding

    private func confirmDiscard(_ change: GlassEditorGitChange) {
        let name = (repository.projectRelative(change.path) as NSString).lastPathComponent
        let untracked = change.kind == .untracked
        ask(.confirm(GlassEditorGitConfirmation(
            title: untracked ? "Delete \(name)?" : "Discard Changes to \(name)?",
            message: untracked ? "It isn't in git, so it can't be brought back."
                : change.isStaged ? "Its changes since it was staged are thrown away; what is staged is kept. This can't be undone."
                : "It goes back to how the last commit has it. This can't be undone.",
            button: untracked ? "Delete" : "Discard") {
                await workspace.git(projectID) { repository in
                    await repository.discard([change])
                    return true
                }
            }))
    }

    private func confirmDiscardAll() {
        let files = unstaged.count
        let new = unstaged.filter { $0.kind == .untracked }.count
        ask(.confirm(GlassEditorGitConfirmation(
            title: "Discard All Changes?",
            message: "The changes to \(files) file\(files == 1 ? "" : "s") that aren't staged are thrown away"
                + (new > 0 ? ", and \(new) new file\(new == 1 ? " is" : "s are") deleted" : "")
                + ". What is staged is kept. This can't be undone.",
            button: "Discard All") {
                await workspace.git(projectID) { repository in
                    await repository.discardAll()
                    return true
                }
            }))
    }

    // MARK: Lines

    @ViewBuilder
    private func lines(of change: GlassEditorGitChange, diff: GlassEditorFileDiff?, group: Group, key: String) -> some View {
        if let diff {
            if diff.isBinary {
                note(change.kind == .untracked ? "Binary, or too large to show." : "Binary file: git shows no lines.")
            } else if diff.hunks.isEmpty {
                if let old = diff.oldMode, let new = diff.newMode, old != new {
                    note("Mode changed from \(old) to \(new).")
                } else {
                    note("No lines changed.")
                }
            } else {
                if repository.ignoresWhitespace, GlassEditorGitPatch.canPatch(diff) {
                    note("Whitespace is ignored, so lines can't be staged one at a time. Show whitespace again to stage them.")
                }
                GlassEditorDiffBody(
                    file: diff, rowID: key, layout: shownLayout, fontSize: fontSize,
                    wraps: workspace.windowTextConfiguration.wrapsLines,
                    actions: repository.ignoresWhitespace ? [] : (group == .staged ? [.unstage] : [.stage, .discard]),
                    perform: { action, hunk, lines in perform(action, file: diff, hunk: hunk, lines: lines, key: key) },
                    chosen: Binding(get: { chosen[key] ?? [:] }, set: { chosen[key] = $0.isEmpty ? nil : $0 }),
                    open: change.kind == .deleted ? nil : { line in
                        Task { await workspace.openChangedFile(change.path, in: projectID, line: line, asPreview: true) }
                    },
                    isDisabled: repository.isWorking)
            }
        } else if change.path.hasSuffix("/") {
            note("A folder that is a repository of its own.")
        } else if repository.hasReadDiffs {
            note(change.kind == .untracked ? "Not read: open the file to see it." : "No lines to show.")
        } else {
            note("Reading…")
        }
    }

    private func perform(_ action: GlassEditorHunkAction, file: GlassEditorFileDiff, hunk: Int, lines: Set<Int>?, key: String) {
        switch action {
        case .stage:
            chosen[key]?[hunk] = nil
            Task { await repository.stage(file, hunk: hunk, lines: lines) }
        case .unstage:
            chosen[key]?[hunk] = nil
            Task { await repository.unstage(file, hunk: hunk, lines: lines) }
        case .discard:
            let count = lines?.count
            ask(.confirm(GlassEditorGitConfirmation(
                title: count.map { $0 == 1 ? "Discard This Line?" : "Discard These \($0) Lines?" } ?? "Discard This Hunk?",
                message: "The file goes back to how it was there before you changed it. This can't be undone.",
                button: "Discard") {
                    chosen[key]?[hunk] = nil
                    await workspace.git(projectID) { repository in
                        await repository.discard(file, hunk: hunk, lines: lines)
                        return true
                    }
                }))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: Conflicts

    private func conflictHeader(_ change: GlassEditorGitChange) -> some View {
        let path = repository.projectRelative(change.path)
        let name = (path as NSString).lastPathComponent
        let isOpen = resolving.contains(change.path)
        return HStack(spacing: 8) {
            GlassEditorGitMark(change: change)
            Text(name).font(.body.weight(.semibold)).lineLimit(1)
            Text((path as NSString).deletingLastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            Menu("Take") {
                Button("Take Ours (\(repository.status.headName))") {
                    Task { await workspace.git(projectID) { await $0.resolve(change.path, taking: .ours) } }
                }
                Button("Take Theirs") {
                    Task { await workspace.git(projectID) { await $0.resolve(change.path, taking: .theirs) } }
                }
                Divider()
                Button("Mark as Resolved") { Task { await repository.stage([change]) } }
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Settle the whole file as one side has it, or say you've settled it yourself")
            Button(isOpen ? "Done" : "Resolve…") {
                if isOpen { resolving.remove(change.path) } else { resolving.insert(change.path) }
            }
            .accessibilityIdentifier("editor-resolve-\(path)")
            Button("Open \(name)", systemImage: "arrow.up.forward.square") {
                Task { await workspace.openChangedFile(change.path, in: projectID) }
            }
            .labelStyle(.iconOnly)
            .help("Open \(name) to resolve it by hand")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conflict: \(path)")
    }
}

/// A changed file's letter, in its colour: the tree's mark and the Changes tab's.
struct GlassEditorGitMark: View {
    let change: GlassEditorGitChange
    /// Whether it is staged, said by the mark: the tree's, where nothing else says it (2026-10-29).
    /// Changes says it by the list a file is in.
    var showsStaging = false

    /// Ready to commit: the letter on its colour, as a badge.
    private var staged: Bool { showsStaging && change.isStaged }
    /// Staged, then changed again: a commit takes the staged version, not what is on screen.
    private var changedSinceStaged: Bool { staged && change.isUnstaged }

    var body: some View {
        HStack(spacing: 2) {
            Text(change.letter)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(staged ? Color.white : change.tint)
                .padding(.horizontal, staged ? 3 : 0)
                .background {
                    if staged { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(change.tint) }
                }
            if changedSinceStaged {
                Circle()
                    .fill(change.tint)
                    .frame(width: 5, height: 5)
            }
        }
        .help(spoken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard showsStaging, change.kind != .untracked, change.kind != .conflicted else { return change.description }
        if changedSinceStaged { return change.description + ", staged, and changed again since: a commit takes the staged version" }
        return change.description + (change.isStaged ? ", staged" : ", not staged")
    }
}

extension GlassEditorGitChange {
    /// Its identity in each of Changes' lists.
    var stagedKey: String { "staged:" + path }
    var unstagedKey: String { "unstaged:" + path }

    /// VS Code's and Zed's colours: amber modified, green new, red deleted.
    var tint: Color {
        switch kind {
        case .modified, .typeChanged: .orange
        case .added, .untracked: .green
        case .deleted, .conflicted: .red
        case .renamed, .copied: .blue
        }
    }
}

/// The system's pasteboard, for Copy Line.
@MainActor
enum GlassEditorPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// The project footer's branch: its name and how many files differ from its last commit. Pressed,
/// it opens Changes.
struct GlassEditorBranchButton: View {
    let repository: GlassEditorGitRepository
    /// Pulls through the workspace, which reads again the open files the pull changes.
    let pull: () -> Void
    /// Opens Source Control at a part of it.
    let show: (GlassEditorSourceControlSection) -> Void

    private var count: Int { repository.status.changes.count }
    private var isReady: Bool { repository.state == .ready }

    /// A click shows Changes, as it always has; held or right-clicked, it pulls, pushes and fetches
    /// (2026-10-28), and opens the rest of Source Control. A button with a menu rather than a
    /// `Menu`: a Mac draws a menu's label as one title, which dropped the counts.
    var body: some View {
        Button { show(.changes) } label: {
            label
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button("Show Changes", systemImage: "list.bullet.rectangle") { show(.changes) }
            if isReady {
                Button("Show History", systemImage: "clock.arrow.circlepath") { show(.history) }
                Button("Show Branches", systemImage: "arrow.triangle.branch") { show(.branches) }
            }
            if isReady, repository.status.branch != nil {
                Divider()
                if let upstream = repository.status.upstream {
                    Button(repository.status.behind > 0 ? "Pull \(GlassEditorChangesView.commits(repository.status.behind))" : "Pull",
                           systemImage: "arrow.down", action: pull)
                        .help("Pull from \(upstream)")
                        .disabled(repository.isWorking)
                    Button(repository.status.ahead > 0 ? "Push \(GlassEditorChangesView.commits(repository.status.ahead))" : "Push",
                           systemImage: "arrow.up") { Task { await repository.push() } }
                        .disabled(repository.isWorking || !repository.canPush)
                    Button("Fetch", systemImage: "arrow.triangle.2.circlepath") { Task { await repository.fetch() } }
                        .disabled(repository.isWorking)
                } else {
                    Button("Publish Branch", systemImage: "icloud.and.arrow.up") { Task { await repository.push() } }
                        .disabled(repository.isWorking)
                }
            }
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier("editor-branch")
    }

    private var label: some View {
            HStack(spacing: 4) {
                Image(systemName: !isReady ? "exclamationmark.triangle"
                      : repository.operation != nil ? "arrow.triangle.merge" : "arrow.triangle.branch")
                Text(isReady ? repository.status.headName : "Git")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isReady, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
                if isReady, repository.status.upstream != nil, repository.status.ahead + repository.status.behind > 0 {
                    Text(Self.aheadBehind(repository.status))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if repository.networkAction != nil {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.caption)
    }

    /// ", 2 commits to push, 1 to pull", against an upstream.
    private var remoteHelp: String {
        let status = repository.status
        guard status.upstream != nil else { return "" }
        let parts = [status.ahead > 0 ? "\(GlassEditorChangesView.commits(status.ahead)) to push" : nil,
                     status.behind > 0 ? "\(status.behind) to pull" : nil].compactMap { $0 }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }

    /// "↑2 ↓1", either left out at zero.
    static func aheadBehind(_ status: GlassEditorGitStatus) -> String {
        [status.ahead > 0 ? "↑\(status.ahead)" : nil, status.behind > 0 ? "↓\(status.behind)" : nil]
            .compactMap { $0 }.joined(separator: " ")
    }

    private var help: String {
        let operation = repository.operation.map { " — \($0.title.lowercased()), not finished" } ?? ""
        switch repository.state {
        case .ready:
            return (count == 0 ? "Changes: none on \(repository.status.headName)"
                : "Changes: \(count) file\(count == 1 ? "" : "s") on \(repository.status.headName)") + remoteHelp + operation
        case .unavailable(let reason): return reason
        case .checking, .notARepository: return "Changes"
        }
    }
}
