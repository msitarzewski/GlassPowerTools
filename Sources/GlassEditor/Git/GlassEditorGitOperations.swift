//
//  GlassEditorGitOperations.swift
//  Glass Power Tools — GlassEditor
//
//  Everything a project's git does beyond staging a file and committing (2026-10-28: "build git
//  now, end to end, first class (diff viewer, all of it!)"): a hunk or chosen lines staged,
//  unstaged or thrown away; changes discarded; branches, tags and stashes; the history, a commit's
//  changes, cherry-picks, reverts and resets; merges and rebases and the conflicts they stop on;
//  who last changed each line. Each is one `git` command where the files are, and each that changes
//  something runs one at a time and refreshes after, as staging always has.
//

import Foundation
import GlassEditorCore

extension GlassEditorGitRepository {
    // MARK: Hunks and lines

    /// Stages one hunk of a file's unstaged changes, or the lines chosen in it.
    public func stage(_ file: GlassEditorFileDiff, hunk: Int, lines: Set<Int>? = nil) async {
        await apply(file, hunk: hunk, lines: lines, toIndex: true, reverse: false, doing: "stage those lines")
    }

    /// Takes one hunk of a file's staged changes, or the lines chosen in it, back out of the index.
    public func unstage(_ file: GlassEditorFileDiff, hunk: Int, lines: Set<Int>? = nil) async {
        await apply(file, hunk: hunk, lines: lines, toIndex: true, reverse: true, doing: "unstage those lines")
    }

    /// Throws away one hunk of a file's unstaged changes, or the lines chosen in it: the working
    /// tree goes back to what the index has there.
    public func discard(_ file: GlassEditorFileDiff, hunk: Int, lines: Set<Int>? = nil) async {
        await apply(file, hunk: hunk, lines: lines, toIndex: false, reverse: true, doing: "discard those lines")
    }

    private func apply(_ file: GlassEditorFileDiff, hunk: Int, lines: Set<Int>?, toIndex: Bool, reverse: Bool,
                       doing verb: String) async {
        guard !ignoresWhitespace else {
            actionProblem = "Lines can't be staged or discarded while whitespace is ignored: the hunks no longer match the file. Show whitespace again first."
            return
        }
        guard GlassEditorGitPatch.canPatch(file),
              let patch = GlassEditorGitPatch.patch(of: file, hunk: hunk, chosen: lines, reverse: reverse) else { return }
        let data = Data(patch.utf8)
        guard machine == nil || data.count <= GlassEditorRemoteGit.inputCeiling else {
            actionProblem = "That's too much to send at once. Stage the file whole, or a smaller part of it."
            return
        }
        await run(GlassEditorGitCommand.apply(toIndex: toIndex, reverse: reverse), input: data, doing: verb)
    }

    // MARK: Discarding

    /// Throws away the unstaged changes of files: tracked files go back to what the index has,
    /// files git doesn't know yet are deleted. What is staged is kept.
    public func discard(_ changes: [GlassEditorGitChange]) async {
        let untracked = changes.filter { $0.kind == .untracked && Self.canStage($0) }.map(\.path)
        let tracked = Self.paths(of: changes.filter { $0.kind != .untracked && $0.kind != .conflicted && $0.isUnstaged })
        if !tracked.isEmpty {
            guard await run(GlassEditorGitCommand.restoreFromIndex(tracked), doing: "discard the changes") else { return }
        }
        if !untracked.isEmpty {
            await run(GlassEditorGitCommand.removeUntracked(untracked), doing: "delete the new files")
        }
    }

    /// Throws away every unstaged change under the project's folder, new files included.
    public func discardAll() async {
        await discard(status.changes.filter { $0.isUnstaged })
    }

    /// The last commit's whole message, to begin an amended one from.
    public func lastCommitMessage() async -> String? {
        guard status.commit != nil,
              let answer = try? await runner.git(GlassEditorGitCommand.global + ["log", "-1", "--format=%B"], in: projectPath),
              answer.succeeded else { return nil }
        return String(decoding: answer.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Reading

    /// What a query answered, or nil, with `actionProblem` saying why.
    func query(_ arguments: [String], doing verb: String) async -> Data? {
        do {
            let answer = try await runner.git(arguments, in: projectPath)
            guard answer.succeeded else {
                actionProblem = problem(answer, doing: verb)
                return nil
            }
            return answer.standardOutput
        } catch let error as GlassEditorGitError {
            actionProblem = error.explanation(on: machine)
        } catch {
            actionProblem = "Git couldn't be asked to \(verb) on \(machine ?? "this Mac"): \(error.localizedDescription)"
        }
        return nil
    }

    /// Reads the branches, tags, stashes and remotes again.
    public func loadReferences() async {
        guard state == .ready else { return }
        if let data = await query(GlassEditorGitCommand.branches, doing: "list the branches") {
            let read = GlassEditorGitBranch.parse(data)
            if read != branches { branches = read }
        }
        if let data = await query(GlassEditorGitCommand.tags, doing: "list the tags") {
            let read = GlassEditorGitTag.parse(data)
            if read != tags { tags = read }
        }
        if let data = await query(GlassEditorGitCommand.stashes, doing: "list the stashes") {
            let read = GlassEditorGitStash.parse(data)
            if read != stashes { stashes = read }
        }
        if let data = await query(GlassEditorGitCommand.remotesWithAddresses, doing: "list the remotes") {
            let read = GlassEditorGitRemote.parse(data)
            if read != remotes { remotes = read }
        }
    }

    /// `origin`, or the only remote: where Open on GitHub goes.
    public var mainRemote: GlassEditorGitRemote? {
        remotes.first { $0.name == "origin" } ?? (remotes.count == 1 ? remotes.first : nil)
    }

    /// A remote's web page for `branch`'s remote, or the main one.
    public func webRemote(for branch: String? = nil) -> GlassEditorGitRemote? {
        if let branch, let upstream = branches.first(where: { $0.name == branch && !$0.isRemote })?.upstream,
           let remote = remotes.first(where: { upstream.hasPrefix($0.name + "/") }) {
            return remote
        }
        return mainRemote
    }

    // MARK: Branches

    public func checkout(_ branch: GlassEditorGitBranch) async -> Bool {
        if branch.isRemote {
            // A local branch of the same name that follows it; the local one if it already exists.
            let local = branch.shortName
            if branches.contains(where: { !$0.isRemote && $0.name == local }) {
                return await run(GlassEditorGitCommand.checkout(local), doing: "switch to \(local)").andReload(self)
            }
            return await run(GlassEditorGitCommand.checkoutTracking(branch.name, as: local), doing: "check out \(branch.name)").andReload(self)
        }
        return await run(GlassEditorGitCommand.checkout(branch.name), doing: "switch to \(branch.name)").andReload(self)
    }

    /// A commit on its own, with no branch.
    public func checkout(commit: String) async -> Bool {
        await run(GlassEditorGitCommand.checkoutDetached(commit), doing: "check out that commit").andReload(self)
    }

    public func createBranch(_ name: String, at start: String? = nil, checkingOut: Bool) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await run(GlassEditorGitCommand.createBranch(name, at: start, checkingOut: checkingOut),
                         doing: "make the branch \(name)").andReload(self)
    }

    public func rename(_ branch: GlassEditorGitBranch, to name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != branch.name, !branch.isRemote else { return false }
        return await run(GlassEditorGitCommand.renameBranch(branch.name, to: name), doing: "rename \(branch.name)").andReload(self)
    }

    public enum DeleteOutcome: Equatable, Sendable {
        case deleted, notDeleted
        /// Its commits are on no other branch: deleting it loses them. Asked before forcing.
        case notMerged
    }

    public func delete(_ branch: GlassEditorGitBranch, force: Bool = false) async -> DeleteOutcome {
        if branch.isRemote {
            guard let remote = branch.remote else { return .notDeleted }
            return await network(.pushing, GlassEditorGitCommand.deleteRemoteBranch(branch.shortName, on: remote),
                                 doing: "delete \(branch.name)").andReload(self) ? .deleted : .notDeleted
        }
        guard !isWorking else { return .notDeleted }
        do {
            let answer = try await runner.git(GlassEditorGitCommand.deleteBranch(branch.name, force: force), in: projectPath)
            if answer.succeeded {
                actionProblem = nil
                await loadReferences()
                return .deleted
            }
            if String(decoding: answer.standardError, as: UTF8.self).contains("not fully merged") { return .notMerged }
            actionProblem = problem(answer, doing: "delete \(branch.name)")
        } catch let error as GlassEditorGitError {
            actionProblem = error.explanation(on: machine)
        } catch {
            actionProblem = "Git couldn't be asked to delete \(branch.name): \(error.localizedDescription)"
        }
        return .notDeleted
    }

    /// Pushes a local branch, publishing it when the remote doesn't have it.
    public func push(_ branch: GlassEditorGitBranch) async {
        guard !branch.isRemote else { return }
        if branch.isCurrent { await push(); await loadReferences(); return }
        if branch.upstream != nil {
            let remote = branch.upstream.flatMap { upstream in remotes.first { upstream.hasPrefix($0.name + "/") } }?.name ?? "origin"
            await network(.pushing, GlassEditorGitCommand.global + ["push", "--quiet", remote, branch.name], doing: "push")
        } else if let remote = mainRemote?.name {
            await network(.pushing, GlassEditorGitCommand.publish(branch.name, to: remote), doing: "push")
        } else {
            actionProblem = "This repository has no remote to push to. Add one in a terminal (git remote add origin <address>), then push."
        }
        await loadReferences()
    }

    // MARK: Combining

    /// Merges a branch or a commit into the one checked out. A merge that stops on conflicts is an
    /// operation under way; `actionProblem` says so.
    public func merge(_ ref: String) async -> Bool {
        await run(GlassEditorGitCommand.merge(ref), doing: "merge \(ref)").andReload(self)
    }

    /// The branch checked out, made again on top of `ref`.
    public func rebase(onto ref: String) async -> Bool {
        await run(GlassEditorGitCommand.rebase(onto: ref), doing: "rebase onto \(ref)").andReload(self)
    }

    /// A pull that merges or rebases, for a branch and upstream that have both moved on.
    public func pull(rebasing: Bool) async -> Bool {
        await network(.pulling, GlassEditorGitCommand.pull(rebasing: rebasing), doing: "pull").andReload(self)
    }

    public func cherryPick(_ commit: String) async -> Bool {
        await run(GlassEditorGitCommand.cherryPick(commit), doing: "cherry-pick that commit").andReload(self)
    }

    public func revert(_ commit: String) async -> Bool {
        await run(GlassEditorGitCommand.revert(commit), doing: "revert that commit").andReload(self)
    }

    /// Moves the branch to `commit`: keeping the changes staged (soft), keeping them unstaged
    /// (mixed), or throwing them away (hard).
    public func reset(to commit: String, mode: GlassEditorGitResetMode) async -> Bool {
        let command: GlassEditorGitCommand.ResetMode = switch mode {
        case .soft: .soft
        case .mixed: .mixed
        case .hard: .hard
        }
        return await run(GlassEditorGitCommand.reset(to: commit, mode: command), doing: "reset").andReload(self)
    }

    /// Goes on with the operation under way: its conflicts resolved and staged. A merge finishes
    /// with the commit git prepared.
    public func continueOperation() async -> Bool {
        guard let operation else { return false }
        if let conflicted = status.changes.first(where: { $0.kind == .conflicted }) {
            actionProblem = "\(projectRelative(conflicted.path)) still has conflicts. Resolve and stage every conflicted file first."
            return false
        }
        let arguments = operation == .merge ? GlassEditorGitCommand.concludeMerge
            : GlassEditorGitCommand.operation(operation.verb, "continue")
        return await run(arguments, doing: "continue the \(operation.verb)").andReload(self)
    }

    /// Gives up the operation under way: everything goes back to how it was before it began.
    public func abortOperation() async -> Bool {
        guard let operation else { return false }
        return await run(GlassEditorGitCommand.operation(operation.verb, "abort"), doing: "abort the \(operation.verb)").andReload(self)
    }

    /// Leaves out the commit a rebase or a cherry-pick stopped on, and goes on.
    public func skipOperation() async -> Bool {
        guard let operation, operation == .rebase || operation == .cherryPick else { return false }
        return await run(GlassEditorGitCommand.operation(operation.verb, "skip"), doing: "skip that commit").andReload(self)
    }

    // MARK: Conflicts

    /// A conflicted file's text and conflicts, with what it was when read, for writing it back.
    public func conflicts(in repositoryPath: String) async -> (file: GlassEditorConflictFile, stat: RemoteStat?)? {
        guard let path = absolutePath(repositoryPath) else { return nil }
        do {
            let stat = try await access.stat(path)
            let data = try await access.read(path)
            let text = (try? EncodingDetector.decode(data))?.content ?? String(decoding: data, as: UTF8.self)
            return (GlassEditorConflictFile.parse(text), stat)
        } catch {
            actionProblem = "\(projectRelative(repositoryPath)) couldn't be read: \(error.localizedDescription)"
            return nil
        }
    }

    /// Writes a conflicted file as resolved and stages it, which tells git it is settled.
    public func resolve(_ repositoryPath: String, as text: String, expecting stat: RemoteStat?) async -> Bool {
        guard let path = absolutePath(repositoryPath) else { return false }
        do {
            try await access.write(Data(text.utf8), to: path, expecting: stat)
        } catch {
            actionProblem = "\(projectRelative(repositoryPath)) couldn't be written: \(error.localizedDescription)"
            return false
        }
        return await run(GlassEditorGitCommand.stage([repositoryPath]), doing: "mark it resolved").andReload(self)
    }

    /// A conflicted file settled wholly as one side had it.
    public func resolve(_ repositoryPath: String, taking side: GlassEditorConflictFile.Choice) async -> Bool {
        let flag: String
        switch side {
        case .ours: flag = "--ours"
        case .theirs: flag = "--theirs"
        default: return false
        }
        guard await run(GlassEditorGitCommand.global + ["checkout", flag, "--", GlassEditorGitCommand.exactly(repositoryPath)],
                        doing: "take that side") else { return false }
        return await run(GlassEditorGitCommand.stage([repositoryPath]), doing: "mark it resolved").andReload(self)
    }

    // MARK: Tags

    public func createTag(_ name: String, at commit: String, message: String?) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await run(GlassEditorGitCommand.createTag(name, at: commit, message: message?.isEmpty == false ? message : nil),
                         doing: "make the tag \(name)").andReload(self)
    }

    public func delete(_ tag: GlassEditorGitTag) async -> Bool {
        await run(GlassEditorGitCommand.deleteTag(tag.name), doing: "delete \(tag.name)").andReload(self)
    }

    public func push(_ tag: GlassEditorGitTag) async -> Bool {
        guard let remote = mainRemote?.name else {
            actionProblem = "This repository has no remote to push to."
            return false
        }
        return await network(.pushing, GlassEditorGitCommand.pushTag(tag.name, to: remote), doing: "push \(tag.name)").andReload(self)
    }

    public func deleteOnRemote(_ tag: GlassEditorGitTag) async -> Bool {
        guard let remote = mainRemote?.name else { return false }
        return await network(.pushing, GlassEditorGitCommand.deleteRemoteTag(tag.name, on: remote),
                             doing: "delete \(tag.name) on \(remote)").andReload(self)
    }

    // MARK: Stashes

    /// Puts the uncommitted changes away, leaving the working tree as the last commit has it.
    public func stash(message: String?, includingUntracked: Bool) async -> Bool {
        let message = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run(GlassEditorGitCommand.stash(message: message?.isEmpty == false ? message : nil,
                                                     includingUntracked: includingUntracked),
                         doing: "stash the changes").andReload(self)
    }

    public func apply(_ stash: GlassEditorGitStash) async -> Bool {
        await run(GlassEditorGitCommand.stashAction("apply", stash.name), doing: "apply the stash").andReload(self)
    }

    public func pop(_ stash: GlassEditorGitStash) async -> Bool {
        await run(GlassEditorGitCommand.stashAction("pop", stash.name), doing: "pop the stash").andReload(self)
    }

    public func drop(_ stash: GlassEditorGitStash) async -> Bool {
        await run(GlassEditorGitCommand.stashAction("drop", stash.name), doing: "drop the stash").andReload(self)
    }

    /// A stash's changes, and the new files it kept, when it kept any.
    public func diff(of stash: GlassEditorGitStash) async -> [GlassEditorFileDiff]? {
        guard let data = await query(GlassEditorGitCommand.stashDiff(stash.name), doing: "show the stash") else { return nil }
        var files = GlassEditorGitDiff.parse(data)
        // Only a stash made with its new files has a third parent; others answer an error, which is no problem.
        if let answer = try? await runner.git(GlassEditorGitCommand.stashUntrackedDiff(stash.commit), in: projectPath),
           answer.succeeded {
            files += GlassEditorGitDiff.parse(answer.standardOutput)
        }
        return files
    }

    // MARK: Cloning

    /// Clones `address` into a new folder `name` in this one, with the machine's own git and keys.
    /// Whether it worked; when it didn't, `actionProblem` says why.
    public func clone(_ address: String, named name: String) async -> Bool {
        await network(.fetching, GlassEditorGitCommand.clone(address, into: name), doing: "clone")
    }

    /// The folder a clone of `address` makes, as `git clone` names it: the address's last part
    /// without `.git`. Nil for an address with no name in it.
    nonisolated public static func cloneName(of address: String) -> String? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        guard let last = text.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init),
              !last.isEmpty, last != ".", last != "..", text.contains(where: { $0 == "/" || $0 == ":" }) else { return nil }
        return last
    }

    // MARK: History

    /// A page of commits, newest first: every branch's, the one checked out, or one file's.
    public func history(limit: Int = 200, skip: Int = 0, allBranches: Bool, path: String? = nil) async -> [GlassEditorGitCommit]? {
        // From the project's folder, where git runs: `--follow` takes one plain path.
        let pathspec = path.flatMap { repositoryPath(of: $0) }.map(projectRelative)
        guard status.commit != nil else { return [] }
        return await query(GlassEditorGitCommand.log(limit: limit, skip: skip, allBranches: allBranches, path: pathspec),
                           doing: "read the history").map(GlassEditorGitCommit.parse)
    }

    /// One commit's changes: against its first parent, or from nothing for a first commit.
    public func diff(of commit: GlassEditorGitCommit, context: Int? = nil, ignoringWhitespace: Bool = false) async -> [GlassEditorFileDiff]? {
        await query(GlassEditorGitCommand.commitDiff(commit.hash, parent: commit.parents.first, context: context,
                                                     ignoringWhitespace: ignoringWhitespace),
                    doing: "show the commit").map(GlassEditorGitDiff.parse)
    }

    /// Who last changed each line of a file, in the project or by its absolute path.
    public func blame(_ path: String) async -> [GlassEditorBlameLine]? {
        guard let relative = repositoryPath(of: path) else { return nil }
        // A file, not a pathspec: from the project's folder, where git runs.
        return await query(GlassEditorGitCommand.blame(projectRelative(relative)),
                           doing: "read who changed each line").map(GlassEditorGitBlame.parse)
    }
}

/// How far a reset goes.
public enum GlassEditorGitResetMode: String, CaseIterable, Sendable {
    /// The branch moves; the changes since stay staged.
    case soft
    /// The branch moves; the changes since stay in the files, unstaged.
    case mixed
    /// The branch moves and the files with it: the changes since are gone.
    case hard
}

private extension Bool {
    /// The branches, tags and stashes read again after something that may have changed them.
    @MainActor func andReload(_ repository: GlassEditorGitRepository) async -> Bool {
        await repository.loadReferences()
        return self
    }
}
