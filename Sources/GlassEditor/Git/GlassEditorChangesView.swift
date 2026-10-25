//
//  GlassEditorChangesView.swift
//  Glass Power Tools — GlassEditor
//
//  A project's **Changes** tab: every file that differs from the last commit, with its lines, in
//  one scroll — what `git diff HEAD` says, as Zed's project diff shows it (the owner, 2026-10-23:
//  "I'd like to be able to see 'this' instead of having to open Zed").
//
//  Each file's header stays at the top while its lines scroll under it, and folds away. A line
//  opens its file there; the header's button opens the file. The tab keeps itself current while it
//  is open, as the terminal beside it changes things.
//
//  It commits, too (2026-10-23: "add gutter marks and stage/commit too"): each file's box stages
//  or unstages it, as Zed's do, and the message above them commits what is staged — or, with
//  nothing staged, everything listed, as VS Code's smart commit does.
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
    /// Files folded away, by path.
    @State private var folded: Set<String> = []
    /// Staged files outside the project's folder that a commit would take too, while it asks.
    @State private var stagedOutside: [String]?
    @FocusState private var messageFocused: Bool

    private var repository: GlassEditorGitRepository? { workspace.repositories[projectID] }
    private var fontSize: Double { workspace.windowTextConfiguration.fontSize }

    var body: some View {
        if let repository {
            VStack(spacing: 0) {
                summary(repository)
                Divider()
                if repository.state == .ready, !repository.status.changes.isEmpty {
                    commitBar(repository)
                    Divider()
                }
                content(repository)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Current while it is open: a terminal beside it is where most changes are made. A
            // folder here is asked often; one on a server, a command away, less.
            .task(id: projectID) {
                let interval: Duration = repository.machine == nil ? .seconds(4) : .seconds(20)
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { break }
                    repository.refresh()
                }
            }
        } else {
            ContentUnavailableView("No Repository", systemImage: "arrow.triangle.branch",
                                   description: Text("Git isn't available for this project."))
        }
    }

    // MARK: The line along the top

    private func summary(_ repository: GlassEditorGitRepository) -> some View {
        let status = repository.status
        return HStack(spacing: 12) {
            Label(repository.state == .ready ? status.headName : "Git", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("editor-changes-branch")
            if status.upstream != nil, status.ahead > 0 || status.behind > 0 {
                Text("↑\(status.ahead) ↓\(status.behind)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("\(status.ahead) commits to push, \(status.behind) to pull, against \(status.upstream ?? "")")
            }
            Spacer(minLength: 0)
            if repository.state == .ready, !status.changes.isEmpty {
                Text(totals(repository))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if repository.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button("Refresh", systemImage: "arrow.clockwise") { repository.refresh() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Ask git again")
                .accessibilityIdentifier("editor-changes-refresh")
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .frame(minHeight: GlassSpatialMetrics.footerHeight)
        .background(.bar)
    }

    // MARK: Committing

    private func commitBar(_ repository: GlassEditorGitRepository) -> some View {
        @Bindable var repository = repository
        let staged = repository.status.changes.filter(\.isStaged).count
        let total = repository.status.changes.count
        let message = repository.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField("Message", text: $repository.commitMessage, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($messageFocused)
                    .accessibilityIdentifier("editor-commit-message")
                Button(staged > 0 ? "Commit" : "Commit All") { commit(repository) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(message.isEmpty || repository.isWorking)
                    .help(staged > 0 ? "Commit the staged files (⌘↩)" : "Stage every change listed and commit it (⌘↩)")
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
                .disabled(repository.isWorking)
                .accessibilityIdentifier("editor-stage-all")
                Text(staged == 0 ? "Nothing staged" : "\(staged) of \(total) staged")
                    .foregroundStyle(.secondary)
                if repository.isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if let commit = repository.lastCommit {
                    Text("Committed\(commit.name.map { " \($0)" } ?? ""): \(commit.summary)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("editor-last-commit")
                }
            }
            .font(.caption)
            if let problem = repository.actionProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("editor-commit-problem")
            }
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, 8)
    }

    private func commit(_ repository: GlassEditorGitRepository) {
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

    private func totals(_ repository: GlassEditorGitRepository) -> String {
        let files = repository.status.changes.count
        let counted = "\(files) file\(files == 1 ? "" : "s")"
        guard repository.hasReadDiffs else { return counted }
        let added = repository.diffs.values.reduce(0) { $0 + $1.addedLines }
        let removed = repository.diffs.values.reduce(0) { $0 + $1.removedLines }
        return "\(counted)  +\(added) −\(removed)"
    }

    // MARK: What is under it

    @ViewBuilder
    private func content(_ repository: GlassEditorGitRepository) -> some View {
        switch repository.state {
        case .checking:
            ProgressView("Asking git")
        case .notARepository:
            ContentUnavailableView("Not a Git Repository", systemImage: "arrow.triangle.branch",
                                   description: Text("This folder isn't in a git repository."))
        case .unavailable(let reason):
            ContentUnavailableView {
                Label("Git Can't Answer", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason)
            } actions: {
                Button("Refresh") { repository.refresh() }
            }
        case .ready where repository.status.changes.isEmpty:
            ContentUnavailableView("No Changes", systemImage: "checkmark.circle",
                                   description: Text(noChanges(repository)))
        case .ready:
            changes(repository)
        }
    }

    private func noChanges(_ repository: GlassEditorGitRepository) -> String {
        let matches = "Everything matches the last commit on \(repository.status.headName)."
        guard let commit = repository.lastCommit else { return matches }
        let name = commit.name.map { " \($0)" } ?? ""
        let branch = commit.branch.map { " to \($0)" } ?? ""
        return "Committed\(name)\(branch): \(commit.summary)\n\(matches)"
    }

    private func changes(_ repository: GlassEditorGitRepository) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let problem = repository.diffProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(repository.status.changes) { change in
                    let diff = repository.diffs[change.path]
                    Section {
                        if !folded.contains(change.path) {
                            lines(of: change, diff: diff, in: repository)
                        }
                    } header: {
                        fileHeader(change, diff: diff, in: repository)
                    }
                }
            }
        }
        .accessibilityIdentifier("editor-changes")
    }

    // MARK: A file

    private func fileHeader(_ change: GlassEditorGitChange, diff: GlassEditorFileDiff?,
                            in repository: GlassEditorGitRepository) -> some View {
        let path = repository.projectRelative(change.path)
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        let isFolded = folded.contains(change.path)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isFolded ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            if GlassEditorGitRepository.canStage(change) {
                stageBox(change, name: name, in: repository)
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
            if isFolded { folded.remove(change.path) } else { folded.insert(change.path) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.description): \(path)")
        .accessibilityHint(isFolded ? "Shows its lines" : "Hides its lines")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            // The box and the button, which the combined row would otherwise hide.
            if GlassEditorGitRepository.canStage(change) {
                let whole = change.isStaged && !change.isUnstaged
                Button(whole ? "Unstage" : "Stage") {
                    Task {
                        if whole { await repository.unstage([change]) } else { await repository.stage([change]) }
                    }
                }
            }
            if change.kind != .deleted {
                Button("Open") { Task { await workspace.openChangedFile(change.path, in: projectID) } }
            }
        }
        .accessibilityIdentifier("editor-changes-file-\(path)")
    }

    /// Whether the file goes into the next commit: ticked when all of it is staged, a dash when
    /// part is (staged, then edited again), empty when none is. Pressing it stages the rest, or
    /// takes a fully staged file back out.
    private func stageBox(_ change: GlassEditorGitChange, name: String,
                          in repository: GlassEditorGitRepository) -> some View {
        let whole = change.isStaged && !change.isUnstaged
        let symbol = whole ? "checkmark.square.fill" : change.isStaged ? "minus.square.fill" : "square"
        let label = whole ? "Unstage \(name)" : "Stage \(name)"
        return Button(label, systemImage: symbol) {
            Task {
                if whole { await repository.unstage([change]) } else { await repository.stage([change]) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(change.isStaged ? Color.accentColor : Color.secondary)
        .disabled(repository.isWorking)
        .help(whole ? "Staged: in the next commit. Press to unstage."
              : change.isStaged ? "Partly staged: changed again since. Press to stage the rest."
              : "Not staged. Press to stage it for the next commit.")
        .accessibilityIdentifier("editor-stage-\(repository.projectRelative(change.path))")
    }

    @ViewBuilder
    private func lines(of change: GlassEditorGitChange, diff: GlassEditorFileDiff?,
                       in repository: GlassEditorGitRepository) -> some View {
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
                let width = numberWidth(diff)
                // One list of rows per file, each with an id of its own across the whole tab: nested
                // lists identified by position drew blank wherever a later file's positions repeated
                // an earlier one's (rendered, 2026-10-23).
                ForEach(DiffRow.rows(of: diff, path: change.path)) { row in
                    switch row.content {
                    case .hunk(let hunk): hunkHeader(hunk)
                    case .line(let line): lineRow(line, change: change, width: width)
                    }
                }
            }
        } else if change.path.hasSuffix("/") {
            note("A folder that is a repository of its own.")
        } else if repository.hasReadDiffs {
            note(change.kind == .untracked ? "Not read: open the file to see it." : "No lines to show.")
        } else {
            note("Reading…")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func hunkHeader(_ hunk: GlassEditorDiffHunk) -> some View {
        Text(hunk.heading.isEmpty ? hunk.range : "\(hunk.range)  \(hunk.heading)")
            .font(.system(size: fontSize * 0.9, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
    }

    private func lineRow(_ line: GlassEditorDiffLine, change: GlassEditorGitChange, width: CGFloat) -> some View {
        let sign = switch line.kind { case .added: "+"; case .removed: "−"; case .context: " " }
        let tint: Color = switch line.kind { case .added: .green; case .removed: .red; case .context: .clear }
        // Where the line is in the file now: a removed line's place is the line after it.
        let target = line.newNumber ?? line.oldNumber
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: width, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: width, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(sign)
                .frame(width: fontSize * 1.6)
                .foregroundStyle(tint == .clear ? Color.secondary : tint)
            Text(Self.shown(line.text))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if line.noNewlineAtEnd {
                Image(systemName: "arrow.uturn.left")
                    .foregroundStyle(.secondary)
                    .help("No newline at the end of the file")
                    .padding(.trailing, 8)
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .padding(.vertical, 1)
        .background(tint.opacity(0.16))
        .contentShape(Rectangle())
        .onTapGesture {
            guard change.kind != .deleted else { return }
            Task { await workspace.openChangedFile(change.path, in: projectID, line: target, asPreview: true) }
        }
        .contextMenu {
            if change.kind != .deleted, let target {
                Button("Open at Line \(target)", systemImage: "arrow.up.forward.square") {
                    Task { await workspace.openChangedFile(change.path, in: projectID, line: target) }
                }
            }
            Button("Copy Line", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(line.text) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(line))
    }

    /// Wide enough for the file's largest line number.
    private func numberWidth(_ diff: GlassEditorFileDiff) -> CGFloat {
        let largest = diff.hunks.map { max($0.oldStart + $0.oldCount, $0.newStart + $0.newCount) }.max() ?? 1
        return CGFloat(String(largest).count) * fontSize * 0.62 + 10
    }

    /// A tab as four spaces: Text's own tab is narrow and uneven.
    private static func shown(_ text: String) -> String {
        let expanded = text.replacingOccurrences(of: "\t", with: "    ")
        return expanded.isEmpty ? " " : expanded
    }

    private static func spoken(_ line: GlassEditorDiffLine) -> String {
        switch line.kind {
        case .added: "Added, line \(line.newNumber ?? 0): \(line.text)"
        case .removed: "Removed, was line \(line.oldNumber ?? 0): \(line.text)"
        case .context: "Line \(line.newNumber ?? 0): \(line.text)"
        }
    }
}

/// One row of a file's lines in Changes: a hunk's heading, or a line.
struct DiffRow: Identifiable {
    enum Content {
        case hunk(GlassEditorDiffHunk)
        case line(GlassEditorDiffLine)
    }

    let id: String
    let content: Content

    static func rows(of diff: GlassEditorFileDiff, path: String) -> [DiffRow] {
        var rows: [DiffRow] = []
        for (h, hunk) in diff.hunks.enumerated() {
            rows.append(DiffRow(id: "\(path)#\(h)", content: .hunk(hunk)))
            for (l, line) in hunk.lines.enumerated() {
                rows.append(DiffRow(id: "\(path)#\(h).\(l)", content: .line(line)))
            }
        }
        return rows
    }
}

/// A changed file's letter, in its colour: the tree's mark and the Changes tab's.
struct GlassEditorGitMark: View {
    let change: GlassEditorGitChange

    var body: some View {
        Text(change.letter)
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(change.tint)
            .help(change.description)
            .accessibilityLabel(change.description)
    }
}

extension GlassEditorGitChange {
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
    let action: () -> Void

    private var count: Int { repository.status.changes.count }
    private var isReady: Bool { repository.state == .ready }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isReady ? "arrow.triangle.branch" : "exclamationmark.triangle")
                Text(isReady ? repository.status.headName : "Git")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isReady, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                }
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier("editor-branch")
    }

    private var help: String {
        switch repository.state {
        case .ready:
            count == 0 ? "Changes: none on \(repository.status.headName)"
                : "Changes: \(count) file\(count == 1 ? "" : "s") on \(repository.status.headName)"
        case .unavailable(let reason): reason
        case .checking, .notARepository: "Changes"
        }
    }
}
