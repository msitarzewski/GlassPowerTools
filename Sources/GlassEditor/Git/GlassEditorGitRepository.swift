//
//  GlassEditorGitRepository.swift
//  Glass Power Tools — GlassEditor
//
//  One open project's git: its branch, what changed, and — while the Changes tab is open — every
//  changed file's lines. Refreshed when the project opens, when its window comes forward, after a
//  save from the editor, from the footer's Refresh, and every few seconds while Changes is shown.
//

import Foundation
import Observation
import GlassEditorCore

/// A commit made from the Changes tab: what it is called, where, and its first line.
public struct GlassEditorCommitNote: Equatable, Sendable {
    /// Its short name; nil if git did not say.
    public var name: String?
    public var branch: String?
    public var summary: String
}

@MainActor @Observable
public final class GlassEditorGitRepository {
    public enum State: Equatable {
        /// Not asked yet, or asking for the first time.
        case checking
        /// The folder is in no repository. The window shows no git at all.
        case notARepository
        /// git could not answer, in words that say what to do.
        case unavailable(String)
        case ready
    }

    public private(set) var state: State = .checking
    public private(set) var status = GlassEditorGitStatus()
    /// Each changed file's diff, by its path from the repository's root — read while
    /// `showsDiffs`, and kept between refreshes.
    public private(set) var diffs: [String: GlassEditorFileDiff] = [:]
    /// Why the lines could not be read, when the list could.
    public private(set) var diffProblem: String?
    /// The lines have been read at least once since Changes opened.
    public private(set) var hasReadDiffs = false
    public private(set) var isRefreshing = false

    /// Whether the Changes tab wants the lines, which cost a second command and the reads of new
    /// files; the tree needs only the list.
    public var showsDiffs = false {
        didSet {
            guard showsDiffs != oldValue else { return }
            if showsDiffs { refresh() } else { hasReadDiffs = false; diffs = [:] }
        }
    }

    /// The project's folder, absolute, on its machine.
    public let projectPath: String
    /// The machine's name, for what an error says; nil for this Mac.
    public let machine: String?

    /// Changed files by their absolute path in the project, for the tree's marks.
    public private(set) var changesByPath: [String: GlassEditorGitChange] = [:]
    /// Every folder in the project with a changed file somewhere under it.
    public private(set) var changedFolders: Set<String> = []

    @ObservationIgnored private let runner: any GlassEditorGitRunner
    @ObservationIgnored private let access: any GlassEditorFileAccess
    /// The project's folder inside the repository: "" at its root, "Sources/App/" below it. Asked
    /// once; the folder does not move inside its repository while it is open.
    @ObservationIgnored private(set) var prefix: String?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var refreshesAgain = false

    public init(projectPath: String, machine: String?, runner: any GlassEditorGitRunner,
                access: any GlassEditorFileAccess) {
        self.projectPath = GlassEditorProject.normalized(projectPath)
        self.machine = machine
        self.runner = runner
        self.access = access
    }

    /// Whether there is a repository to show: the window hides git until there is.
    public var isRepository: Bool {
        switch state {
        case .ready, .unavailable: true
        case .checking, .notARepository: false
        }
    }

    // MARK: Refreshing

    /// Asks git again. A refresh asked for while one runs is made once more after it, so the last
    /// answer is never older than the last request.
    public func refresh() {
        guard refreshing == nil else {
            refreshesAgain = true
            return
        }
        refreshing = Task { [weak self] in
            await self?.performRefresh()
            guard let self else { return }
            self.refreshing = nil
            if self.refreshesAgain {
                self.refreshesAgain = false
                self.refresh()
            }
        }
    }

    /// Waits until no refresh is running (tests, and callers that act on the answer).
    public func settled() async {
        while let refreshing { await refreshing.value }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if prefix == nil {
                let answer = try await runner.git(GlassEditorGitCommand.prefix, in: projectPath)
                guard answer.succeeded else {
                    settle(failure: answer)
                    return
                }
                prefix = String(decoding: answer.standardOutput, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let answer = try await runner.git(GlassEditorGitCommand.status, in: projectPath)
            guard answer.succeeded else {
                settle(failure: answer)
                return
            }
            take(GlassEditorGitStatus.parse(answer.standardOutput))
            if state != .ready { state = .ready }
            if showsDiffs { await readDiffs() }
        } catch GlassEditorGitError.notInstalled {
            // Said only where there is a repository to read: a Mac without git would otherwise
            // put a warning under every folder it opens.
            let marked = (try? await access.stat(projectPath == "/" ? "/.git" : projectPath + "/.git")) != nil
            state = marked ? .unavailable(GlassEditorGitError.notInstalled.explanation(on: machine)) : .notARepository
        } catch let error as GlassEditorGitError {
            state = .unavailable(error.explanation(on: machine))
        } catch {
            state = .unavailable("Git couldn't be asked about \(machine ?? "this Mac")'s files: \(error.localizedDescription)")
        }
    }

    /// A command that ran and refused. Status 128 from `rev-parse` is git's "not a git repository"
    /// — except when it is git refusing a repository another account owns, which says how to
    /// allow it, and is worth saying.
    private func settle(failure answer: GlassEditorCommandOutput) {
        let said = String(decoding: answer.standardError, as: UTF8.self)
        if said.contains("safe.directory") {
            state = .unavailable("Git won't read this folder because another account owns it. Run git config --global --add safe.directory \(GlassEditorRemoteGit.shellWord(projectPath)) on \(machine ?? "this Mac"), then refresh.")
        } else if answer.exitStatus == 128 {
            prefix = nil
            take(GlassEditorGitStatus())
            diffs = [:]
            state = .notARepository
        } else if said.localizedCaseInsensitiveContains("unknown option") {
            state = .unavailable("Git on \(machine ?? "this Mac") is too old for the editor, which needs Git 2.15 or later. Update it there, then refresh.")
        } else {
            state = .unavailable("Git couldn't read the changes: \(answer.complaint ?? "it stopped with status \(answer.exitStatus.map(String.init) ?? "unknown").")")
        }
    }

    /// The new status, and the tree's marks from it. Assigned only when it changed: every
    /// assignment redraws whatever reads it, and most refreshes find nothing new.
    private func take(_ new: GlassEditorGitStatus) {
        if new != status { status = new }
        var byPath: [String: GlassEditorGitChange] = [:]
        var folders: Set<String> = []
        for change in new.changes {
            guard let path = absolutePath(change.path) else { continue }
            byPath[path] = change
            var folder = (path as NSString).deletingLastPathComponent
            while folder.count >= projectPath.count, folder.hasPrefix(projectPath) {
                guard folders.insert(folder).inserted else { break }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        if byPath != changesByPath { changesByPath = byPath }
        if folders != changedFolders { changedFolders = folders }
    }

    // MARK: The lines

    /// The most a new, untracked file is read for the Changes tab, and the most of them altogether.
    static let untrackedFileCeiling = 512 * 1024
    static let untrackedFilesRead = 100

    private func readDiffs() async {
        do {
            let base: String
            if status.commit == nil {
                // No commit yet: everything is new against the empty tree.
                let tree = try await runner.git(GlassEditorGitCommand.emptyTree, in: projectPath)
                guard tree.succeeded else {
                    diffProblem = "Git couldn't read the changes: \(tree.complaint ?? "no empty tree")"
                    return
                }
                base = String(decoding: tree.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                base = "HEAD"
            }
            let answer = try await runner.git(GlassEditorGitCommand.diff(against: base), in: projectPath)
            guard answer.succeeded else {
                diffProblem = "Git couldn't read the changes: \(answer.complaint ?? "it stopped with status \(answer.exitStatus.map(String.init) ?? "unknown").")"
                return
            }
            var read: [String: GlassEditorFileDiff] = [:]
            for file in GlassEditorGitDiff.parse(answer.standardOutput) { read[file.id] = file }
            // `git diff` leaves out files git does not know yet; they are read as they are, as
            // wholly new. A folder is a repository of its own, and has no lines to show.
            var budget = Self.untrackedFilesRead
            for change in status.changes where change.kind == .untracked && !change.path.hasSuffix("/") {
                guard budget > 0 else { break }
                guard let path = absolutePath(change.path) else { continue }
                budget -= 1
                if let kept = diffs[change.path], kept.newPath == change.path, !kept.hunks.isEmpty || kept.isBinary,
                   let stamp = try? await access.stat(path), stamp == untrackedStamps[change.path] {
                    read[change.path] = kept
                    continue
                }
                read[change.path] = await untracked(change.path, at: path)
            }
            if read != diffs { diffs = read }
            diffProblem = nil
            hasReadDiffs = true
        } catch let error as GlassEditorGitError {
            diffProblem = error.explanation(on: machine)
        } catch {
            diffProblem = "Git couldn't read the changes: \(error.localizedDescription)"
        }
    }

    /// What each new file looked like when it was last read, so a refresh does not read it again.
    @ObservationIgnored private var untrackedStamps: [String: RemoteStat] = [:]

    private func untracked(_ relative: String, at path: String) async -> GlassEditorFileDiff {
        var file = GlassEditorFileDiff(oldPath: nil, newPath: relative)
        let stamp = try? await access.stat(path)
        if let size = stamp?.size, size > UInt64(Self.untrackedFileCeiling) {
            file.isBinary = true
            return file
        }
        guard let data = try? await access.read(path) else { return file }
        untrackedStamps[relative] = stamp
        // git's own test for binary: a NUL in the first 8,000 bytes.
        if data.prefix(8000).contains(0) {
            file.isBinary = true
            return file
        }
        return .addition(path: relative, text: String(decoding: data, as: UTF8.self))
    }

    // MARK: A file's last commit

    /// What a file in the project said at the last commit, for the marks beside its lines; nil when
    /// git has nothing to compare it with — an ignored file, or one it could not read. A file git
    /// doesn't know yet, or one added since, was empty then.
    public func committedText(ofPath path: String) async -> String? {
        guard state == .ready, let repositoryPath = repositoryPath(of: path) else { return nil }
        let change = change(atPath: path)
        if change?.kind == .untracked || change?.kind == .added { return "" }
        guard let commit = status.commit else { return nil }
        // A renamed file's last commit is under its old name.
        let source = change?.originalPath ?? repositoryPath
        if committedTextsCommit != commit {
            committedTexts = [:]
            committedTextsCommit = commit
        }
        if let kept = committedTexts[source] { return kept }
        guard let answer = try? await runner.git(GlassEditorGitCommand.committed(source), in: projectPath) else {
            // Not kept: a connection that dropped may answer next time.
            return nil
        }
        var text: String?
        if answer.succeeded, answer.standardOutput.count <= Self.committedTextCeiling,
           !answer.standardOutput.prefix(8000).contains(0) {
            text = (try? EncodingDetector.decode(answer.standardOutput))?.content
        }
        if committedTextsCommit == commit {
            if committedTexts.count >= Self.committedTextsKept { committedTexts = [:] }
            committedTexts[source] = text
        }
        return text
    }

    /// The largest last-commit version of a file the marks compare with, and how many are kept.
    static let committedTextCeiling = 8 * 1024 * 1024
    static let committedTextsKept = 64
    @ObservationIgnored private var committedTexts: [String: String?] = [:]
    @ObservationIgnored private var committedTextsCommit: String?

    // MARK: Staging and committing

    /// The message being written for the next commit, kept while the project is open.
    public var commitMessage = ""
    /// A stage, an unstage or a commit is running.
    public private(set) var isWorking = false
    /// What the last of those could not do, in words that say what to do.
    public var actionProblem: String?
    /// The commit made from here most recently, for the line that says it was.
    public private(set) var lastCommit: GlassEditorCommitNote?

    /// Whether anything is staged under the project's folder.
    public var hasStagedChanges: Bool { status.changes.contains(where: \.isStaged) }

    /// Whether a change can be staged from here: a folder that is a repository of its own cannot.
    public static func canStage(_ change: GlassEditorGitChange) -> Bool { !change.path.hasSuffix("/") }

    public func stage(_ changes: [GlassEditorGitChange]) async {
        let paths = Self.paths(of: changes.filter(Self.canStage))
        guard !paths.isEmpty else { return }
        await perform(GlassEditorGitCommand.stage(paths), failing: "stage")
    }

    public func unstage(_ changes: [GlassEditorGitChange]) async {
        let paths = Self.paths(of: changes.filter(Self.canStage))
        guard !paths.isEmpty else { return }
        await perform(GlassEditorGitCommand.unstage(paths), failing: "unstage")
    }

    /// Stages every change under the project's folder.
    public func stageAll() async {
        await perform(GlassEditorGitCommand.stageAll(except: nestedRepositories), failing: "stage")
    }

    public func unstageAll() async {
        await perform(GlassEditorGitCommand.unstageAll, failing: "unstage")
    }

    /// How asking for a commit ended.
    public enum CommitOutcome: Equatable, Sendable {
        case committed
        /// Nothing was committed; `actionProblem` says why, when there is a why.
        case notCommitted
        /// Files outside the project's folder are staged too, and would go into the commit. Asked
        /// first, because the Changes tab does not show them.
        case alsoStagedOutside([String])
    }

    /// Commits `commitMessage`. With nothing staged, everything under the project's folder is
    /// staged first ("Commit All", VS Code's smart commit). `includingOutside` is the answer to
    /// `.alsoStagedOutside`.
    @discardableResult
    public func commit(includingOutside: Bool = false) async -> CommitOutcome {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            actionProblem = "Write a message for the commit first."
            return .notCommitted
        }
        guard !isWorking else { return .notCommitted }
        isWorking = true
        defer { isWorking = false }
        await settled()
        do {
            if !includingOutside, let prefix, !prefix.isEmpty {
                let staged = try await runner.git(GlassEditorGitCommand.staged, in: projectPath)
                if staged.succeeded {
                    let outside = staged.standardOutput.split(separator: 0)
                        .map { String(decoding: $0, as: UTF8.self) }
                        .filter { !$0.hasPrefix(prefix) }
                    if !outside.isEmpty { return .alsoStagedOutside(outside) }
                }
            }
            if !hasStagedChanges {
                let answer = try await runner.git(GlassEditorGitCommand.stageAll(except: nestedRepositories),
                                                  in: projectPath)
                guard answer.succeeded else {
                    actionProblem = problem(answer, doing: "stage")
                    await refreshed()
                    return .notCommitted
                }
            }
            let answer = try await runner.git(GlassEditorGitCommand.commit(message: commitMessage), in: projectPath)
            guard answer.succeeded else {
                actionProblem = problem(answer, doing: "commit")
                await refreshed()
                return .notCommitted
            }
            actionProblem = nil
            commitMessage = ""
            await refreshed()
            let summary = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
            lastCommit = GlassEditorCommitNote(name: status.commit.map { String($0.prefix(7)) },
                                               branch: status.branch, summary: summary)
            return .committed
        } catch let error as GlassEditorGitError {
            actionProblem = error.explanation(on: machine)
        } catch {
            actionProblem = "Git couldn't be asked to commit on \(machine ?? "this Mac"): \(error.localizedDescription)"
        }
        await refreshed()
        return .notCommitted
    }

    /// Runs one stage or unstage, one at a time, then asks git what changed.
    private func perform(_ arguments: [String], failing verb: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await settled()
        do {
            let answer = try await runner.git(arguments, in: projectPath)
            actionProblem = answer.succeeded ? nil : problem(answer, doing: verb)
        } catch let error as GlassEditorGitError {
            actionProblem = error.explanation(on: machine)
        } catch {
            actionProblem = "Git couldn't be asked to \(verb) on \(machine ?? "this Mac"): \(error.localizedDescription)"
        }
        await refreshed()
    }

    private func refreshed() async {
        refresh()
        await settled()
    }

    /// Folders under the project that are repositories of their own, which "stage everything"
    /// leaves alone.
    private var nestedRepositories: [String] {
        status.changes.filter { $0.kind == .untracked && $0.path.hasSuffix("/") }.map(\.path)
    }

    /// A change's paths: both of a rename's, so the old name's removal goes with the new name.
    static func paths(of changes: [GlassEditorGitChange]) -> [String] {
        var paths: [String] = []
        for change in changes {
            paths.append(change.path)
            if let original = change.originalPath, change.kind == .renamed { paths.append(original) }
        }
        return paths
    }

    /// Why git refused, in words that say what to do.
    func problem(_ answer: GlassEditorCommandOutput, doing verb: String) -> String {
        let said = String(decoding: answer.standardError, as: UTF8.self)
        let place = machine ?? "this Mac"
        if said.contains("Please tell me who you are") || said.contains("empty ident")
            || said.contains("unable to auto-detect email address") {
            return "Git doesn't know who you are on \(place). Run git config --global user.name \"Your Name\" and git config --global user.email you@example.com there, then commit again."
        }
        if said.contains("index.lock") {
            return "Another git command is using this repository. Wait for it to finish and try again; if nothing is running, delete .git/index.lock first."
        }
        let output = String(decoding: answer.standardOutput, as: UTF8.self)
        if verb == "commit", answer.exitStatus == 1,
           [said, output].contains(where: { $0.contains("nothing to commit") || $0.contains("no changes added to commit") }) {
            return "There's nothing to commit: no changes are staged."
        }
        // A hook that stopped the commit says why on either stream.
        let reason = answer.complaint
            ?? output.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
        return "Git couldn't \(verb): \(reason ?? "it stopped with status \(answer.exitStatus.map(String.init) ?? "unknown").")"
    }

    // MARK: Paths

    /// A path in the project as git names it, from the repository's root; nil outside the project.
    public func repositoryPath(of path: String) -> String? {
        let path = GlassEditorProject.normalized(path)
        guard let prefix else { return nil }
        if projectPath == "/" { return prefix + path.dropFirst() }
        guard path.hasPrefix(projectPath + "/") else { return nil }
        return prefix + path.dropFirst(projectPath.count + 1)
    }

    /// A path from the repository's root, as one in the project; nil when it is outside the
    /// project's folder.
    public func absolutePath(_ repositoryPath: String) -> String? {
        guard let prefix, repositoryPath.hasPrefix(prefix) else { return nil }
        let inside = repositoryPath.dropFirst(prefix.count)
        guard !inside.isEmpty else { return projectPath }
        return projectPath == "/" ? "/" + inside : projectPath + "/" + inside
    }

    /// A path from the repository's root, as the project shows it: from the project's folder.
    public func projectRelative(_ repositoryPath: String) -> String {
        guard let prefix, repositoryPath.hasPrefix(prefix) else { return repositoryPath }
        return String(repositoryPath.dropFirst(prefix.count))
    }

    public func change(atPath path: String) -> GlassEditorGitChange? {
        changesByPath[GlassEditorProject.normalized(path)]
    }

    public func folderHasChanges(_ path: String) -> Bool {
        changedFolders.contains(GlassEditorProject.normalized(path))
    }
}
