//
//  GlassEditorGitWorkflowTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  The whole of git in the editor (2026-10-28), against this Mac's real `git` in repositories made
//  for each test: hunks and chosen lines staged, unstaged and thrown away, checked by what the
//  index and the disk then hold; branches, tags and stashes; the history and its graph; merges and
//  rebases stopped on conflicts, resolved, continued and aborted; amend, cherry-pick, revert,
//  reset; blame; and open files read again after a checkout.
//

#if os(macOS)
import Foundation
import Testing
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("Git: everything else, with this Mac's git", .serialized)
struct GlassEditorGitWorkflowTests {
    /// A repository with `f.txt` of twenty numbered lines committed on `trunk`, by a committer of its
    /// own, with no hooks or signing from this Mac's configuration.
    private func makeRepository() async throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorGitFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await git(["init", "-q", "-b", "trunk"], in: root)
        for (key, value) in [("user.name", "Test"), ("user.email", "test@example.com"), ("commit.gpgsign", "false"),
                             ("tag.gpgsign", "false"), ("core.hooksPath", ".git/hooks"), ("merge.conflictStyle", "merge")] {
            try await git(["config", key, value], in: root)
        }
        try write(Self.numbered, to: "f.txt", in: root)
        try write("keep\n", to: "b.txt", in: root)
        try await git(["add", "."], in: root)
        try await git(["commit", "-q", "-m", "first"], in: root)
        return root
    }

    static let numbered = (1...20).map { "line \($0)\n" }.joined()

    private func write(_ text: String, to name: String, in root: URL) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }

    private func read(_ name: String, in root: URL) throws -> String {
        String(decoding: try Data(contentsOf: root.appendingPathComponent(name)), as: UTF8.self)
    }

    /// git, waited for on a Dispatch thread, as `GlassEditorLocalGitTests` does.
    @discardableResult
    private func git(_ arguments: [String], in root: URL, expecting success: Bool = true) async throws -> GlassEditorCommandOutput {
        let executable = try #require(GlassEditorLocalGit.executable, "the tests need git on this Mac")
        let path = root.path(percentEncoded: false)
        let output = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try GlassEditorLocalGit.run(executable, arguments, in: path) })
            }
        }
        if success {
            #expect(output.exitStatus == 0, "\(arguments): \(String(decoding: output.standardError, as: UTF8.self))")
        }
        return output
    }

    private func text(_ output: GlassEditorCommandOutput) -> String {
        String(decoding: output.standardOutput, as: UTF8.self)
    }

    private func repository(at root: URL) async -> GlassEditorGitRepository {
        let repository = GlassEditorGitRepository(projectPath: root.path(percentEncoded: false), machine: nil,
                                                  runner: GlassEditorLocalGit.shared, access: GlassEditorLocalFileAccess())
        repository.showsDiffs = true
        await repository.settled()
        return repository
    }

    // MARK: Hunks and lines

    @Test func aHunkIsStagedUnstagedAndDiscardedOnItsOwn() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        // Two changes far enough apart to be two hunks.
        try write(Self.numbered.replacingOccurrences(of: "line 2\n", with: "line two\n")
            .replacingOccurrences(of: "line 15\n", with: "line fifteen\n"), to: "f.txt", in: root)
        let repository = await repository(at: root)
        let file = try #require(repository.unstagedDiffs["f.txt"])
        #expect(file.hunks.count == 2)

        await repository.stage(file, hunk: 0)
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        let index = text(try await git(["show", ":f.txt"], in: root))
        #expect(index.contains("line two\n") && index.contains("line 15\n"), "only the first hunk is staged")
        #expect(repository.stagedDiffs["f.txt"]?.hunks.count == 1)
        #expect(repository.unstagedDiffs["f.txt"]?.hunks.count == 1)

        let staged = try #require(repository.stagedDiffs["f.txt"])
        await repository.unstage(staged, hunk: 0)
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        #expect(text(try await git(["show", ":f.txt"], in: root)) == Self.numbered, "unstaged: the index is the commit again")
        #expect(repository.stagedDiffs.isEmpty)

        let both = try #require(repository.unstagedDiffs["f.txt"])
        await repository.discard(both, hunk: 1)
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        let disk = try read("f.txt", in: root)
        #expect(disk.contains("line two\n") && disk.contains("line 15\n") && !disk.contains("fifteen"),
                "the second hunk is gone from the file, the first kept")
    }

    @Test func onlyTheChosenLinesAreStagedOrUnstaged() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        // line 5 becomes two new lines: one removal, two additions in one hunk.
        try write(Self.numbered.replacingOccurrences(of: "line 5\n", with: "new A\nnew B\n"), to: "f.txt", in: root)
        let repository = await repository(at: root)
        let file = try #require(repository.unstagedDiffs["f.txt"])
        let lines = file.hunks[0].lines
        let newA = try #require(lines.firstIndex { $0.text == "new A" })

        // Only "new A": line 5 stays in the index, and "new A" goes in before it.
        await repository.stage(file, hunk: 0, lines: [newA])
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        let index = text(try await git(["show", ":f.txt"], in: root))
        #expect(index.contains("line 4\nline 5\nnew A\nline 6\n") || index.contains("line 4\nnew A\nline 5\nline 6\n"),
                "the chosen addition only: \(index)")
        #expect(!index.contains("new B"))

        // Everything staged, then "new B" alone taken back out.
        await repository.stageAll()
        let staged = try #require(repository.stagedDiffs["f.txt"])
        let newB = try #require(staged.hunks[0].lines.firstIndex { $0.text == "new B" })
        await repository.unstage(staged, hunk: 0, lines: [newB])
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        let after = text(try await git(["show", ":f.txt"], in: root))
        #expect(after.contains("line 4\nnew A\nline 6\n"), "the removal and new A stay staged: \(after)")
        #expect(!after.contains("new B"))
        #expect(try read("f.txt", in: root).contains("new A\nnew B\n"), "the file itself never changes")
    }

    @Test func discardingThrowsAwayUnstagedChangesAndDeletesNewFiles() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try write("changed\n", to: "b.txt", in: root)
        try write("new\n", to: "c.txt", in: root)
        let repository = await repository(at: root)
        #expect(repository.status.changes.count == 2)
        await repository.discard(repository.status.changes)
        #expect(repository.actionProblem == nil, "\(repository.actionProblem ?? "")")
        #expect(try read("b.txt", in: root) == "keep\n")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("c.txt").path(percentEncoded: false)))
        #expect(repository.status.changes.isEmpty)
    }

    @Test func whitespaceIgnoredLinesCantBeStagedAlone() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try write(Self.numbered.replacingOccurrences(of: "line 2\n", with: "line  2\nline two\n"), to: "f.txt", in: root)
        let repository = await repository(at: root)
        repository.ignoresWhitespace = true
        await repository.settled()
        let file = try #require(repository.unstagedDiffs["f.txt"])
        #expect(file.hunks[0].lines.allSatisfy { $0.text != "line  2" || $0.kind == .context }, "a spacing change is not a change")
        await repository.stage(file, hunk: 0)
        #expect(repository.actionProblem?.contains("whitespace") == true)
        #expect(text(try await git(["show", ":f.txt"], in: root)) == Self.numbered, "nothing was staged")
    }

    // MARK: Committing again

    @Test func amendingReplacesTheLastCommit() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        let before = text(try await git(["rev-parse", "HEAD"], in: root))
        try write("more\n", to: "b.txt", in: root)
        let repository = await repository(at: root)
        await repository.stageAll()
        repository.amends = true
        repository.commitMessage = ""
        #expect(await repository.commit() == .committed, "\(repository.actionProblem ?? "")")
        #expect(text(try await git(["log", "-1", "--format=%s"], in: root)) == "first\n", "an empty message keeps the last")
        #expect(text(try await git(["rev-list", "--count", "HEAD"], in: root)) == "1\n", "replaced, not added")
        #expect(text(try await git(["rev-parse", "HEAD"], in: root)) != before)
        #expect(text(try await git(["show", "HEAD:b.txt"], in: root)) == "more\n")
        #expect(!repository.amends && repository.lastCommit?.summary == "first")

        repository.amends = true
        repository.commitMessage = "Better words"
        #expect(await repository.commit() == .committed)
        #expect(text(try await git(["log", "-1", "--format=%s"], in: root)) == "Better words\n")
        #expect(await repository.lastCommitMessage() == "Better words")
    }

    // MARK: Branches, tags and stashes

    @Test func branchesAreMadeSwitchedRenamedAndDeleted() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = await repository(at: root)
        #expect(await repository.createBranch("topic", checkingOut: true))
        #expect(repository.status.branch == "topic")
        #expect(repository.branches.map(\.name).sorted() == ["topic", "trunk"])
        #expect(repository.branches.first { $0.name == "topic" }?.isCurrent == true)

        let topic = try #require(repository.branches.first { $0.name == "topic" })
        #expect(await repository.rename(topic, to: "topic-2"))
        #expect(repository.status.branch == "topic-2")

        // A commit only topic-2 has: deleting it asks first.
        try write("topic\n", to: "b.txt", in: root)
        repository.commitMessage = "Topic work"
        #expect(await repository.commit() == .committed)
        let trunk = try #require(repository.branches.first { $0.name == "trunk" })
        #expect(await repository.checkout(trunk))
        #expect(repository.status.branch == "trunk")
        #expect(try read("b.txt", in: root) == "keep\n")
        let unmerged = try #require(repository.branches.first { $0.name == "topic-2" })
        #expect(await repository.delete(unmerged) == .notMerged)
        #expect(repository.branches.contains { $0.name == "topic-2" }, "not deleted without asking")
        #expect(await repository.delete(unmerged, force: true) == .deleted)
        #expect(repository.branches.map(\.name) == ["trunk"])

        #expect(!(await repository.createBranch("bad name..", checkingOut: false)))
        #expect(repository.actionProblem != nil)
    }

    @Test func tagsAreMadeAtACommitAndDeleted() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = await repository(at: root)
        let head = try #require(repository.status.commit)
        #expect(await repository.createTag("v1", at: head, message: "Release one"))
        #expect(await repository.createTag("v0", at: head, message: ""))
        let tags = Dictionary(uniqueKeysWithValues: repository.tags.map { ($0.name, $0) })
        #expect(tags["v1"]?.isAnnotated == true && tags["v1"]?.commit == head)
        #expect(tags["v0"]?.isAnnotated == false && tags["v0"]?.commit == head, "an empty message makes a light tag")
        #expect(await repository.delete(try #require(tags["v0"])))
        #expect(repository.tags.map(\.name) == ["v1"])
    }

    @Test func stashesPutChangesAwayAndBringThemBack() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try write("stashed\n", to: "b.txt", in: root)
        try write("brand new\n", to: "n.txt", in: root)
        let repository = await repository(at: root)
        #expect(await repository.stash(message: "half done", includingUntracked: true))
        #expect(repository.status.changes.isEmpty)
        #expect(try read("b.txt", in: root) == "keep\n")
        let stash = try #require(repository.stashes.first)
        #expect(repository.stashes.count == 1 && stash.message.contains("half done"))
        let files = try #require(await repository.diff(of: stash))
        #expect(Set(files.map(\.id)) == ["b.txt", "n.txt"], "its new file is shown too")

        #expect(await repository.pop(stash))
        #expect(repository.stashes.isEmpty)
        #expect(try read("b.txt", in: root) == "stashed\n" && (try read("n.txt", in: root)) == "brand new\n")

        #expect(await repository.stash(message: nil, includingUntracked: false))
        #expect(repository.status.changes.map(\.path) == ["n.txt"], "a new file stays without being asked for")
        let second = try #require(repository.stashes.first)
        #expect(await repository.apply(second))
        #expect(repository.stashes.count == 1, "applied, and kept")
        #expect(await repository.drop(second))
        #expect(repository.stashes.isEmpty)
    }

    // MARK: History

    @Test func theHistoryShowsAMergeAndEachCommitsChanges() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try await git(["checkout", "-q", "-b", "feature"], in: root)
        try write("feature\n", to: "g.txt", in: root)
        try await git(["add", "g.txt"], in: root)
        try await git(["commit", "-q", "-m", "Feature"], in: root)
        try await git(["checkout", "-q", "trunk"], in: root)
        try write(Self.numbered + "line 21\n", to: "f.txt", in: root)
        try await git(["commit", "-q", "-am", "Trunk"], in: root)
        try await git(["merge", "-q", "--no-edit", "feature"], in: root)
        // A stash is commits of its own, which the history leaves out.
        try write("put away\n", to: "b.txt", in: root)
        try await git(["stash", "-q"], in: root)

        let repository = await repository(at: root)
        let commits = try #require(await repository.history(allBranches: true))
        #expect(commits.map(\.subject) == ["Merge branch 'feature' into trunk", "Trunk", "Feature", "first"]
                || commits.map(\.subject) == ["Merge branch 'feature' into trunk", "Feature", "Trunk", "first"])
        #expect(commits[0].isMerge && commits[0].refs.contains("HEAD -> trunk"))
        let rows = GlassEditorGitGraphRow.rows(for: commits)
        #expect(rows[0].outgoing.count == 2 && rows.map(\.width).max() == 2)
        #expect(rows[3].incoming.count == 2, "both lines end at the first commit")

        let merge = try #require(await repository.diff(of: commits[0]))
        #expect(merge.map(\.id) == ["g.txt"], "a merge's changes are against its first parent")
        let first = try #require(commits.last)
        let root0 = try #require(await repository.diff(of: first))
        #expect(Set(root0.map(\.id)) == ["b.txt", "f.txt"], "the first commit's changes are against nothing")

        let fileHistory = try #require(await repository.history(allBranches: false, path: root.appendingPathComponent("g.txt").path(percentEncoded: false)))
        #expect(fileHistory.map(\.subject) == ["Feature"])
        let paged = try #require(await repository.history(limit: 2, skip: 2, allBranches: true))
        #expect(paged.count == 2 && paged.last?.subject == "first")
    }

    @Test func aCommitIsCherryPickedRevertedAndResetTo() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try await git(["checkout", "-q", "-b", "side"], in: root)
        try write("from side\n", to: "s.txt", in: root)
        try await git(["add", "s.txt"], in: root)
        try await git(["commit", "-q", "-m", "Side"], in: root)
        let side = text(try await git(["rev-parse", "HEAD"], in: root)).trimmingCharacters(in: .whitespacesAndNewlines)
        try await git(["checkout", "-q", "trunk"], in: root)
        // Trunk moves on, or the pick would be the very same commit, made in the same second.
        try write("trunk moved\n", to: "b.txt", in: root)
        try await git(["commit", "-q", "-am", "Trunk moves"], in: root)

        let repository = await repository(at: root)
        let first = try #require(repository.status.commit)
        #expect(await repository.cherryPick(side), "\(repository.actionProblem ?? "")")
        #expect(try read("s.txt", in: root) == "from side\n")
        let picked = try #require(repository.status.commit)
        #expect(picked != side && picked != first)

        #expect(await repository.revert(picked), "\(repository.actionProblem ?? "")")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("s.txt").path(percentEncoded: false)))
        #expect(text(try await git(["log", "-1", "--format=%s"], in: root)).hasPrefix("Revert \"Side\""))

        #expect(await repository.reset(to: picked, mode: .soft))
        #expect(repository.status.commit == picked)
        #expect(repository.status.changes.contains { $0.path == "s.txt" && $0.isStaged }, "soft: the revert's change stays staged")
        #expect(await repository.reset(to: first, mode: .hard))
        #expect(repository.status.commit == first && repository.status.changes.isEmpty)
    }

    @Test func blameSaysWhoChangedEachLineAndWhatIsntCommitted() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try write("keep\nsecond\n", to: "b.txt", in: root)
        try await git(["-c", "user.name=Other", "commit", "-q", "-am", "Second line"], in: root)
        try write("keep\nsecond\nthird\n", to: "b.txt", in: root)
        let repository = await repository(at: root)
        let lines = try #require(await repository.blame(root.appendingPathComponent("b.txt").path(percentEncoded: false)))
        #expect(lines.map(\.text) == ["keep", "second", "third"])
        #expect(lines.map(\.author) == ["Test", "Other", "Not Committed Yet"])
        #expect(lines[1].summary == "Second line" && lines[2].isUncommitted)
    }

    // MARK: Merges and rebases that stop

    /// `trunk` and `feature` both change b.txt's one line.
    private func makeConflict() async throws -> URL {
        let root = try await makeRepository()
        try await git(["checkout", "-q", "-b", "feature"], in: root)
        try write("feature\n", to: "b.txt", in: root)
        try await git(["commit", "-q", "-am", "Feature"], in: root)
        try await git(["checkout", "-q", "trunk"], in: root)
        try write("trunk\n", to: "b.txt", in: root)
        try await git(["commit", "-q", "-am", "Trunk"], in: root)
        return root
    }

    @Test func aMergeStopsOnAConflictWhichIsResolvedAndContinued() async throws {
        let root = try await makeConflict(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = await repository(at: root)
        #expect(!(await repository.merge("feature")), "it stops")
        #expect(repository.actionProblem?.contains("resolve conflicts") == true, "\(repository.actionProblem ?? "")")
        #expect(repository.operation == .merge)
        #expect(repository.operationDetail == "Merge branch 'feature' into trunk")
        let change = try #require(repository.status.changes.first)
        #expect(change.kind == .conflicted && change.path == "b.txt")
        #expect(!(await repository.continueOperation()), "not while a file has conflicts")

        let (file, stat) = try #require(await repository.conflicts(in: "b.txt"))
        let conflict = try #require(file.conflicts.first)
        #expect(conflict.ours == ["trunk"] && conflict.theirs == ["feature"] && conflict.theirsLabel == "feature")
        #expect(await repository.resolve("b.txt", as: file.resolved([0: .oursThenTheirs]), expecting: stat))
        #expect(try read("b.txt", in: root) == "trunk\nfeature\n")
        #expect(repository.status.changes.first?.kind == .modified && repository.status.changes.first?.isStaged == true)

        #expect(await repository.continueOperation(), "\(repository.actionProblem ?? "")")
        #expect(repository.operation == nil && repository.operationDetail == nil)
        #expect(text(try await git(["log", "-1", "--format=%P"], in: root)).split(separator: " ").count == 2, "a merge commit")
        #expect(text(try await git(["log", "-1", "--format=%s"], in: root)) == "Merge branch 'feature' into trunk\n")
    }

    @Test func aRebaseThatStopsIsAbortedBackToWhereItWas() async throws {
        let root = try await makeConflict(); defer { try? FileManager.default.removeItem(at: root) }
        let before = text(try await git(["rev-parse", "HEAD"], in: root))
        let repository = await repository(at: root)
        #expect(!(await repository.rebase(onto: "feature")))
        #expect(repository.operation == .rebase)
        #expect(repository.operationDetail == "trunk: 1 of 1", "\(repository.operationDetail ?? "none")")
        #expect(repository.status.changes.contains { $0.kind == .conflicted })

        #expect(await repository.abortOperation(), "\(repository.actionProblem ?? "")")
        #expect(repository.operation == nil)
        #expect(repository.status.branch == "trunk")
        #expect(text(try await git(["rev-parse", "HEAD"], in: root)) == before)
        #expect(try read("b.txt", in: root) == "trunk\n")
    }

    @Test func aConflictedFileIsSettledWhollyAsOneSideHadIt() async throws {
        let root = try await makeConflict(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = await repository(at: root)
        _ = await repository.merge("feature")
        #expect(await repository.resolve("b.txt", taking: .theirs))
        #expect(try read("b.txt", in: root) == "feature\n")
        #expect(!repository.status.changes.contains { $0.kind == .conflicted })
        #expect(await repository.abortOperation())
    }

    // MARK: Cloning

    @Test func aRepositoryIsClonedIntoAProjectsFolderAndARefusalSaysWhy() async throws {
        let source = try await makeRepository(); defer { try? FileManager.default.removeItem(at: source) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EditorClone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.clone.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(folder))
        #expect(workspace.canRunGit(at: project.path))

        let address = source.path(percentEncoded: false)
        let clone = try #require(await workspace.cloneRepository(address, intoFolder: project.path), "\(workspace.message ?? "")")
        #expect(clone == project.path + "/" + source.lastPathComponent)
        #expect(String(decoding: try Data(contentsOf: URL(filePath: clone + "/f.txt")), as: UTF8.self) == Self.numbered)

        #expect(await workspace.cloneRepository(address, intoFolder: project.path) == nil)
        #expect(workspace.message?.contains("already something named") == true, "\(workspace.message ?? "")")
        #expect(await workspace.cloneRepository(project.path + "/nothing-here.git", intoFolder: project.path) == nil)
        #expect(workspace.message?.contains("no repository at that address") == true, "\(workspace.message ?? "")")
    }

    // MARK: The workspace

    @Test func openFilesAreReadAgainAfterACheckout() async throws {
        let root = try await makeConflict(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.gitflow.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        await repository.loadReferences()
        let document = try #require(await workspace.open(path: root.appendingPathComponent("b.txt").path(percentEncoded: false)))
        #expect(document.model.text == "trunk\n")
        #expect(document.model.showsChangeMarks, "a file git marks keeps room for its marks with line numbers off")
        let feature = try #require(repository.branches.first { $0.name == "feature" })
        #expect(await workspace.git(project.id) { await $0.checkout(feature) })
        #expect(document.model.text == "feature\n", "the open file took the checkout")
        #expect(!document.isDirty)

        // Blame and History tabs, opened once each.
        let path = root.appendingPathComponent("b.txt").path(percentEncoded: false)
        let blame = try #require(workspace.showGit(.blame(path), of: path))
        #expect(!blame.isText && blame.gitProject == project.id && blame.changesOfProject == nil)
        #expect(workspace.showGit(.blame(path), of: path)?.id == blame.id)
        let history = try #require(workspace.showGit(.history(path), of: path))
        #expect(history.id != blame.id && history.displayName == "History · b.txt")
        let sourceControl = try #require(workspace.showSourceControl(.branches, of: project.id))
        #expect(sourceControl.changesOfProject == project.id && sourceControl.displayName == "Branches")
        workspace.closeProject(project.id)
        #expect(!workspace.documents.contains { $0.gitProject == project.id }, "a project's git tabs close with it")
    }
}
#endif
