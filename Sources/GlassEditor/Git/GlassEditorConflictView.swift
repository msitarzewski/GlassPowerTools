//
//  GlassEditorConflictView.swift
//  Glass Power Tools — GlassEditor
//
//  A file a merge, a rebase, a cherry-pick or a stash stopped on, resolved in Changes (2026-10-28):
//  each conflict's two sides beside each other — ours, the branch checked out; theirs, what came
//  in — and a choice for each: ours, theirs, or both in either order. Saved, the file is written
//  and staged, which is how git is told it is settled. Anything finer is done in the editor: Open.
//

import SwiftUI
import GlassEditorCore
import GlassConnectionUI

struct GlassEditorConflictView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let repository: GlassEditorGitRepository
    /// From the repository's root.
    let path: String
    let done: () -> Void

    @State private var file: GlassEditorConflictFile?
    @State private var stat: RemoteStat?
    @State private var choices: [Int: GlassEditorConflictFile.Choice] = [:]
    @State private var isSaving = false

    private var fontSize: Double { workspace.windowTextConfiguration.fontSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let file {
                if file.conflicts.isEmpty {
                    HStack {
                        Text("No conflict markers are left in this file.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Mark as Resolved") { markResolved() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(Array(file.conflicts.enumerated()), id: \.offset) { index, conflict in
                        conflictCard(conflict, index: index, of: file.conflicts.count)
                    }
                    HStack {
                        Text("\(choices.count) of \(file.conflicts.count) chosen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open in Editor") {
                            Task { await workspace.openChangedFile(path, in: projectID) }
                        }
                        Button("Save and Mark Resolved") { save(file) }
                            .buttonStyle(.borderedProminent)
                            .disabled(choices.count < file.conflicts.count || isSaving)
                            .accessibilityIdentifier("editor-conflict-save")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .task(id: path) {
            guard let read = await repository.conflicts(in: path) else { return }
            file = read.file
            stat = read.stat
            choices = [:]
        }
    }

    private func conflictCard(_ conflict: GlassEditorConflictFile.Conflict, index: Int, of total: Int) -> some View {
        let choice = choices[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conflict \(index + 1) of \(total)").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Use", selection: Binding(get: { choices[index] }, set: { choices[index] = $0 })) {
                    Text("Choose…").tag(GlassEditorConflictFile.Choice?.none)
                    Text("Ours").tag(GlassEditorConflictFile.Choice?.some(.ours))
                    Text("Theirs").tag(GlassEditorConflictFile.Choice?.some(.theirs))
                    Text("Both, Ours First").tag(GlassEditorConflictFile.Choice?.some(.oursThenTheirs))
                    Text("Both, Theirs First").tag(GlassEditorConflictFile.Choice?.some(.theirsThenOurs))
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("editor-conflict-\(index)")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    side("Ours", label: ours(conflict), lines: conflict.ours, tint: .blue,
                         chosen: choice == .ours || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[index] = .ours }
                        .frame(minWidth: 280)
                    side("Theirs", label: conflict.theirsLabel, lines: conflict.theirs, tint: .purple,
                         chosen: choice == .theirs || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[index] = .theirs }
                        .frame(minWidth: 280)
                }
                VStack(alignment: .leading, spacing: 8) {
                    side("Ours", label: ours(conflict), lines: conflict.ours, tint: .blue,
                         chosen: choice == .ours || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[index] = .ours }
                    side("Theirs", label: conflict.theirsLabel, lines: conflict.theirs, tint: .purple,
                         chosen: choice == .theirs || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[index] = .theirs }
                }
            }
            if let base = conflict.base {
                DisclosureGroup("What they had in common (\(base.count) line\(base.count == 1 ? "" : "s"))") {
                    lines(base)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(choice == nil ? Color.orange.opacity(0.6) : Color.clear))
    }

    /// Ours, by the branch's name where git wrote HEAD.
    private func ours(_ conflict: GlassEditorConflictFile.Conflict) -> String {
        conflict.oursLabel == "HEAD" ? repository.status.headName : conflict.oursLabel
    }

    private func side(_ title: String, label: String, lines text: [String], tint: Color, chosen: Bool,
                      use: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Use \(title)", action: use)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            lines(text)
                .background(tint.opacity(chosen ? 0.18 : 0.06))
                .overlay(alignment: .leading) {
                    if chosen { Rectangle().fill(tint).frame(width: 3) }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lines(_ text: [String]) -> some View {
        Text(text.isEmpty ? "(nothing)" : text.joined(separator: "\n").replacingOccurrences(of: "\t", with: "    "))
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save(_ file: GlassEditorConflictFile) {
        isSaving = true
        let text = file.resolved(choices)
        Task {
            let worked = await workspace.git(projectID) { await $0.resolve(path, as: text, expecting: stat) }
            isSaving = false
            if worked { done() }
        }
    }

    private func markResolved() {
        Task {
            await workspace.git(projectID) { repository in
                guard let change = repository.status.changes.first(where: { $0.path == path }) else { return false }
                await repository.stage([change])
                return true
            }
            done()
        }
    }
}

// MARK: - Blame

/// A file's **Blame** tab (2026-10-28): who last changed each line, and in which commit — each run
/// of lines from one commit marked once, its age shaded, older lighter. A commit opens in History.
struct GlassEditorBlameView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    /// The file's absolute path.
    let path: String

    @State private var lines: [GlassEditorBlameLine]?
    @State private var problem: String?
    @State private var hovered: String?

    private var repository: GlassEditorGitRepository? { workspace.repositories[projectID] }
    private var fontSize: Double { workspace.windowTextConfiguration.fontSize }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label((path as NSString).lastPathComponent, systemImage: "person.text.rectangle")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("File History", systemImage: "clock.arrow.circlepath") { workspace.showGit(.history(path), of: path) }
                Button("Open", systemImage: "arrow.up.forward.square") { Task { await workspace.open(path: path, line: nil) } }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await read() } }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
            .frame(minHeight: GlassSpatialMetrics.footerHeight)
            .background(.bar)
            Divider()
            if let lines {
                table(lines)
            } else if let problem {
                ContentUnavailableView("Can't Show Who Changed Each Line", systemImage: "exclamationmark.triangle",
                                       description: Text(problem))
            } else {
                ProgressView("Reading who changed each line").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: path) { await read() }
    }

    private func read() async {
        guard let repository else { return }
        repository.actionProblem = nil
        if let read = await repository.blame(path) {
            lines = read
            problem = nil
        } else {
            problem = repository.actionProblem ?? "Git couldn't say who changed this file's lines."
            repository.actionProblem = nil
        }
    }

    private func table(_ lines: [GlassEditorBlameLine]) -> some View {
        let dates = lines.compactMap(\.date)
        let oldest = dates.min() ?? .now, newest = dates.max() ?? .now
        let numberWidth = CGFloat(String(lines.count).count) * fontSize * 0.62 + 10
        return ScrollView([.vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let first = index == 0 || lines[index - 1].commit != line.commit
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        annotation(line, shown: first, age: age(line.date, oldest: oldest, newest: newest))
                            .frame(width: 260, alignment: .leading)
                        Text("\(line.number)")
                            .frame(width: numberWidth, alignment: .trailing)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                        Text(line.text.isEmpty ? " " : line.text.replacingOccurrences(of: "\t", with: "    "))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: fontSize, design: .monospaced))
                    .padding(.vertical, 1)
                    .background(hovered == line.commit ? Color.accentColor.opacity(0.10) : Color.clear)
                    .overlay(alignment: .top) {
                        if first, index > 0 { Divider().opacity(0.6) }
                    }
                    .onHover { inside in hovered = inside ? line.commit : (hovered == line.commit ? nil : hovered) }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { Task { await workspace.open(path: path, line: line.number) } }
                    .contextMenu { menu(line) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.isUncommitted
                                        ? "Line \(line.number), not committed yet: \(line.text)"
                                        : "Line \(line.number), \(line.author), \(GlassEditorGitDates.relative(line.date)), \(line.summary): \(line.text)")
                }
            }
        }
        .accessibilityIdentifier("editor-blame")
    }

    /// 1 for the newest commit in the file, 0 for the oldest.
    private func age(_ date: Date?, oldest: Date, newest: Date) -> Double {
        guard let date, newest > oldest else { return 1 }
        return date.timeIntervalSince(oldest) / newest.timeIntervalSince(oldest)
    }

    /// The first line of each commit's run says whose it is; every line has the run's bar, as tall as
    /// the line, so a row is the same height with or without the words (rendered, 2026-10-28).
    @ViewBuilder
    private func annotation(_ line: GlassEditorBlameLine, shown: Bool, age: Double) -> some View {
        HStack(spacing: 6) {
            if shown {
                if line.isUncommitted {
                    Text("Not committed yet").foregroundStyle(.orange)
                } else {
                    Button(line.shortCommit) { showCommit(line) }
                        .buttonStyle(.borderless)
                        .monospaced()
                        .help(line.summary)
                    Text(line.author).lineLimit(1)
                    Text(GlassEditorGitDates.relative(line.date)).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(" ")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.leading, 10)
        .background(alignment: .leading) {
            Rectangle()
                .fill(line.isUncommitted ? Color.orange : Color.accentColor.opacity(0.15 + 0.75 * age))
                .frame(width: 3)
        }
        .padding(.leading, 4)
    }

    private func showCommit(_ line: GlassEditorBlameLine) {
        workspace.showSourceControl(.history, of: projectID, commit: line.commit)
    }

    @ViewBuilder
    private func menu(_ line: GlassEditorBlameLine) -> some View {
        if !line.isUncommitted {
            Button("Show Commit in History", systemImage: "clock.arrow.circlepath") { showCommit(line) }
            Button("Copy Hash", systemImage: "doc.on.doc") { GlassEditorPasteboard.copy(line.commit) }
        }
        Button("Open at Line \(line.number)", systemImage: "arrow.up.forward.square") {
            Task { await workspace.open(path: path, line: line.number) }
        }
    }
}

/// A file's **History** tab: the commits that changed it, following it across renames.
struct GlassEditorFileHistoryView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let path: String

    @State private var request: GlassEditorGitRequest?

    var body: some View {
        if let repository = workspace.repositories[projectID], repository.state == .ready {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label((path as NSString).lastPathComponent, systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Button("Blame", systemImage: "person.text.rectangle") { workspace.showGit(.blame(path), of: path) }
                    Button("Open", systemImage: "arrow.up.forward.square") { Task { await workspace.open(path: path, line: nil) } }
                    GlassEditorDiffOptionsMenu().labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
                .frame(minHeight: GlassSpatialMetrics.footerHeight)
                .background(.bar)
                Divider()
                GlassEditorHistoryView(workspace: workspace, projectID: projectID, repository: repository, path: path) {
                    // What a commit's actions ask lands in Source Control, which has the questions.
                    if case .confirm(let confirmation) = $0 {
                        request = .confirm(confirmation)
                    } else {
                        workspace.showSourceControl(.history, of: projectID)
                    }
                }
            }
            .alert(request?.title ?? "", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                   presenting: request) { request in
                if case .confirm(let confirmation) = request {
                    Button(confirmation.button, role: confirmation.isDestructive ? .destructive : nil) {
                        Task { await confirmation.action() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: { request in
                if case .confirm(let confirmation) = request { Text(confirmation.message) }
            }
        } else {
            ContentUnavailableView("No Repository", systemImage: "arrow.triangle.branch",
                                   description: Text("Git isn't available for this file."))
        }
    }
}
