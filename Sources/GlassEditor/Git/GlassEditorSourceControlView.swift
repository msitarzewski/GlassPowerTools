//
//  GlassEditorSourceControlView.swift
//  Glass Power Tools — GlassEditor
//
//  A project's **Source Control** tab (2026-10-28: "build git now, end to end, first class"): the
//  Changes tab it grew from, with the repository's History, Branches, Stashes and Tags beside it.
//  Along the top, the branch — a menu to switch it — and the remote; under that, a merge or a
//  rebase that stopped part way, with Continue and Abort; then the part chosen.
//
//  Everything that changes the files goes through `GlassEditorWorkspace.git(_:_:)`, which reads
//  again the open files a checkout, a merge or a stash changed.
//

import SwiftUI
import GlassConnectionUI

/// The parts of Source Control.
public enum GlassEditorSourceControlSection: String, CaseIterable, Sendable {
    case changes, history, branches, stashes, tags

    public var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .branches: "Branches"
        case .stashes: "Stashes"
        case .tags: "Tags"
        }
    }

    var symbol: String {
        switch self {
        case .changes: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .branches: "arrow.triangle.branch"
        case .stashes: "tray.full"
        case .tags: "tag"
        }
    }
}

/// What the Git menu asks Source Control to ask: it holds the questions.
public enum GlassEditorGitAsk: Equatable, Sendable {
    case newBranch, stash
}

/// Something a part of Source Control asks the person: a name, a message, or whether to go ahead.
enum GlassEditorGitRequest: Identifiable {
    /// A new branch at a commit (HEAD when nil), described for the prompt.
    case newBranch(start: String?, from: String)
    case renameBranch(GlassEditorGitBranch)
    case newTag(commit: String, from: String)
    case stash
    case confirm(GlassEditorGitConfirmation)

    var id: String {
        switch self {
        case .newBranch(let start, _): "branch-\(start ?? "HEAD")"
        case .renameBranch(let branch): "rename-\(branch.id)"
        case .newTag(let commit, _): "tag-\(commit)"
        case .stash: "stash"
        case .confirm(let confirmation): "confirm-\(confirmation.title)"
        }
    }

    var title: String {
        switch self {
        case .newBranch: "New Branch"
        case .renameBranch(let branch): "Rename \(branch.name)"
        case .newTag: "New Tag"
        case .stash: "Stash Changes"
        case .confirm(let confirmation): confirmation.title
        }
    }
}

/// A question before something that can't be undone, or that moves a lot.
struct GlassEditorGitConfirmation {
    let title: String
    let message: String
    let button: String
    var isDestructive = true
    let action: () async -> Void
}

struct GlassEditorSourceControlView: View {
    let workspace: GlassEditorWorkspace
    let projectID: GlassEditorProject.ID
    let document: GlassEditorDocument

    @State private var request: GlassEditorGitRequest?
    @State private var nameField = ""
    @State private var messageField = ""

    private var repository: GlassEditorGitRepository? { workspace.repositories[projectID] }

    private var section: Binding<GlassEditorSourceControlSection> {
        Binding(get: { workspace.gitSections[projectID] ?? .changes },
                set: { workspace.gitSections[projectID] = $0 })
    }

    var body: some View {
        if let repository {
            VStack(spacing: 0) {
                bar(repository)
                Divider()
                if repository.state == .ready, let operation = repository.operation {
                    operationBanner(operation, repository: repository)
                    Divider()
                }
                // What a stage, a commit, a push or a pull couldn't do: shown in every part, as a
                // push comes after the last commit.
                if let problem = repository.actionProblem {
                    problemLine(problem, repository: repository)
                    Divider()
                }
                content(repository)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .alert(request?.title ?? "", isPresented: Binding(
                get: { request != nil }, set: { if !$0 { request = nil } }
            ), presenting: request) { request in
                requestActions(request, repository: repository)
            } message: { request in
                Text(requestMessage(request))
            }
            .onChange(of: section.wrappedValue, initial: true) { _, section in
                if document.untitledName != section.title { document.untitledName = section.title }
            }
            .onChange(of: workspace.gitAsks[projectID], initial: true) { _, asked in
                guard let asked else { return }
                workspace.gitAsks[projectID] = nil
                switch asked {
                case .newBranch: ask(.newBranch(start: nil, from: repository.status.headName))
                case .stash: ask(.stash)
                }
            }
            // Current while it is open: a terminal beside it is where most changes are made. A
            // folder here is asked often; one on a server, a command away, less.
            .task(id: projectID) {
                await repository.loadReferences()
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

    private func ask(_ request: GlassEditorGitRequest) {
        nameField = ""
        messageField = ""
        if case .renameBranch(let branch) = request { nameField = branch.name }
        self.request = request
    }

    /// Runs something that may change the files, then reads open ones again.
    private func git(_ operation: @escaping (GlassEditorGitRepository) async -> Bool) {
        Task { await workspace.git(projectID, operation) }
    }

    // MARK: The bar

    private func bar(_ repository: GlassEditorGitRepository) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                branchMenu(repository)
                if repository.state == .ready {
                    GlassEditorRemoteButtons(repository: repository) {
                        Task { await workspace.pull(projectID) }
                    }
                }
                Spacer(minLength: 0)
                if repository.isRefreshing || repository.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    repository.refresh()
                    Task { await repository.loadReferences() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Ask git again")
                .accessibilityIdentifier("editor-changes-refresh")
            }
            if repository.state == .ready {
                HStack(spacing: 8) {
                    Picker("Show", selection: section) {
                        ForEach(GlassEditorSourceControlSection.allCases, id: \.self) { section in
                            Text(title(of: section, in: repository)).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 560)
                    .accessibilityIdentifier("editor-git-section")
                    Spacer(minLength: 0)
                    GlassEditorDiffOptionsMenu()
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, 6)
        .frame(minHeight: GlassSpatialMetrics.footerHeight)
        .background(.bar)
    }

    /// "Changes 4", "Stashes 2": what each part holds, where it is worth counting.
    private func title(of section: GlassEditorSourceControlSection, in repository: GlassEditorGitRepository) -> String {
        let count = switch section {
        case .changes: repository.status.changes.count
        case .stashes: repository.stashes.count
        default: 0
        }
        return count > 0 ? "\(section.title) \(count)" : section.title
    }

    /// The branch, as a menu that switches it, makes one, or shows them all.
    private func branchMenu(_ repository: GlassEditorGitRepository) -> some View {
        let locals = repository.branches.filter { !$0.isRemote }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return Menu {
            if !locals.isEmpty {
                Section("Switch To") {
                    ForEach(locals.prefix(12)) { branch in
                        Button {
                            guard !branch.isCurrent else { return }
                            git { await $0.checkout(branch) }
                        } label: {
                            if branch.isCurrent {
                                Label(branch.name, systemImage: "checkmark")
                            } else {
                                Text(branch.name)
                            }
                        }
                    }
                }
            }
            Button("New Branch…", systemImage: "plus") {
                ask(.newBranch(start: nil, from: repository.status.headName))
            }
            .disabled(repository.status.commit == nil)
            Button("Show Branches", systemImage: "list.bullet") { section.wrappedValue = .branches }
        } label: {
            Label(repository.state == .ready ? repository.status.headName : "Git", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(repository.state != .ready || repository.isWorking)
        .help("Switch branches, or make one")
        .accessibilityIdentifier("editor-changes-branch")
    }

    // MARK: An operation under way

    private func operationBanner(_ operation: GlassEditorGitOperation, repository: GlassEditorGitRepository) -> some View {
        let conflicts = repository.status.changes.filter { $0.kind == .conflicted }.count
        return HStack(spacing: 10) {
            Image(systemName: conflicts > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.merge")
                .foregroundStyle(conflicts > 0 ? .orange : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.title + (repository.operationDetail.map { " — \($0)" } ?? ""))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(conflicts > 0
                     ? "\(conflicts) file\(conflicts == 1 ? "" : "s") with conflicts. Choose a side for each in Changes, then Continue."
                     : "No conflicts left. Continue to finish, or Abort to put everything back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Abort", role: .destructive) {
                request = .confirm(GlassEditorGitConfirmation(
                    title: "Abort the \(operation.verb)?",
                    message: "Everything goes back to how it was before the \(operation.verb) began, including any conflicts you've resolved.",
                    button: "Abort") { await workspace.git(projectID) { await $0.abortOperation() } })
            }
            .accessibilityIdentifier("editor-operation-abort")
            if operation == .rebase || operation == .cherryPick {
                Button("Skip") { git { await $0.skipOperation() } }
                    .help("Leave out the commit it stopped on, and go on")
            }
            Button("Continue") { git { await $0.continueOperation() } }
                .buttonStyle(.borderedProminent)
                .disabled(conflicts > 0 || repository.isWorking)
                .accessibilityIdentifier("editor-operation-continue")
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-operation")
    }

    private func problemLine(_ problem: String, repository: GlassEditorGitRepository) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark") { repository.actionProblem = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 20 : 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("editor-commit-problem")
    }

    // MARK: The parts

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
        case .ready:
            switch section.wrappedValue {
            case .changes:
                GlassEditorChangesView(workspace: workspace, projectID: projectID, repository: repository, ask: ask)
            case .history:
                GlassEditorHistoryView(workspace: workspace, projectID: projectID, repository: repository, path: nil, ask: ask)
            case .branches:
                GlassEditorBranchesView(workspace: workspace, projectID: projectID, repository: repository, ask: ask)
            case .stashes:
                GlassEditorStashesView(workspace: workspace, projectID: projectID, repository: repository, ask: ask)
            case .tags:
                GlassEditorTagsView(workspace: workspace, projectID: projectID, repository: repository, ask: ask)
            }
        }
    }

    // MARK: Questions

    @ViewBuilder
    private func requestActions(_ request: GlassEditorGitRequest, repository: GlassEditorGitRepository) -> some View {
        switch request {
        case .newBranch(let start, _):
            TextField("Name", text: $nameField)
            Button("Create and Switch") {
                let name = nameField
                git { await $0.createBranch(name, at: start, checkingOut: true) }
            }
            Button("Create") {
                let name = nameField
                git { await $0.createBranch(name, at: start, checkingOut: false) }
            }
            Button("Cancel", role: .cancel) {}
        case .renameBranch(let branch):
            TextField("Name", text: $nameField)
            Button("Rename") {
                let name = nameField
                git { await $0.rename(branch, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        case .newTag(let commit, _):
            TextField("Name", text: $nameField)
            TextField("Message (optional)", text: $messageField)
            Button("Create") {
                let name = nameField, message = messageField
                git { await $0.createTag(name, at: commit, message: message) }
            }
            Button("Cancel", role: .cancel) {}
        case .stash:
            TextField("Message (optional)", text: $messageField)
            Button("Stash") {
                let message = messageField
                git { await $0.stash(message: message, includingUntracked: false) }
            }
            Button("Stash Including New Files") {
                let message = messageField
                git { await $0.stash(message: message, includingUntracked: true) }
            }
            Button("Cancel", role: .cancel) {}
        case .confirm(let confirmation):
            Button(confirmation.button, role: confirmation.isDestructive ? .destructive : nil) {
                Task { await confirmation.action() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func requestMessage(_ request: GlassEditorGitRequest) -> String {
        switch request {
        case .newBranch(_, let from): "A new branch starting at \(from)."
        case .renameBranch: "Its commits and upstream stay as they are."
        case .newTag(_, let from): "A tag at \(from). With a message it's an annotated tag."
        case .stash: "Your uncommitted changes are put away, and the files go back to the last commit. New files stay unless you stash them too."
        case .confirm(let confirmation): confirmation.message
        }
    }
}

/// Pull, Push and Fetch, with how far the branch is behind and ahead of its upstream; Publish for
/// a branch the remote doesn't have yet. What is under way says so instead.
struct GlassEditorRemoteButtons: View {
    let repository: GlassEditorGitRepository
    /// Pulls through the workspace, which reads again the open files the pull changes.
    let pull: () -> Void

    var body: some View {
        let status = repository.status
        if let action = repository.networkAction {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(action.words).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("editor-remote-working")
        } else if status.branch != nil {
            HStack(spacing: 12) {
                if let upstream = status.upstream {
                    Button(action: pull) {
                        Label(status.behind > 0 ? "Pull \(status.behind)" : "Pull", systemImage: "arrow.down")
                    }
                    .disabled(repository.isWorking)
                    .help(status.behind > 0 ? "Pull \(GlassEditorChangesView.commits(status.behind)) from \(upstream)" : "Pull from \(upstream)")
                    .accessibilityLabel(status.behind > 0 ? "Pull \(GlassEditorChangesView.commits(status.behind))" : "Pull")
                    .accessibilityIdentifier("editor-pull")
                    Button {
                        Task { await repository.push() }
                    } label: {
                        Label(status.ahead > 0 ? "Push \(status.ahead)" : "Push", systemImage: "arrow.up")
                    }
                    .disabled(repository.isWorking || !repository.canPush)
                    .help(status.ahead > 0 ? "Push \(GlassEditorChangesView.commits(status.ahead)) to \(upstream)" : "Nothing to push to \(upstream)")
                    .accessibilityLabel(status.ahead > 0 ? "Push \(GlassEditorChangesView.commits(status.ahead))" : "Push")
                    .accessibilityIdentifier("editor-push")
                    Button("Fetch", systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await repository.fetch()
                            await repository.loadReferences()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(repository.isWorking)
                    .help("Ask \(upstream) what's new, without changing anything here")
                    .accessibilityIdentifier("editor-fetch")
                } else {
                    Button("Publish Branch", systemImage: "icloud.and.arrow.up") {
                        Task { await repository.push() }
                    }
                    .disabled(repository.isWorking)
                    .help("Push \(status.headName) to the remote, and follow it from now on")
                    .accessibilityIdentifier("editor-publish")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.monospacedDigit())
        }
    }
}

/// "3 minutes ago", for a commit's or a branch's date.
@MainActor
enum GlassEditorGitDates {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    static func full(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
