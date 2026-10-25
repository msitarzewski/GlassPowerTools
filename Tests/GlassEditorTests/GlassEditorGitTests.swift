//
//  GlassEditorGitTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  Git in the editor (2026-10-23): what `git status --porcelain=v2 -z` and `git diff` say, read;
//  a project's repository against a runner that answers as git does; and, on a Mac, the real
//  `git` in a repository made for the test.
//

import Foundation
import Testing
import GlassEditorCore
@testable import GlassEditor

@Suite("Git: reading what git says")
struct GlassEditorGitParsingTests {

    // MARK: Status

    @Test func statusReadsTheBranchAndEveryKindOfChange() {
        let fields = [
            "# branch.oid 0123456789abcdef0123456789abcdef01234567",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +2 -1",
            "1 .M N... 100644 100644 100644 aaaa bbbb Sources/App/a b.swift",
            "1 A. N... 000000 100644 100644 0000 bbbb new.txt",
            "1 .D N... 100644 100644 000000 aaaa aaaa gone.txt",
            "1 MM N... 100644 100644 100644 aaaa bbbb both.txt",
            "2 R. N... 100644 100644 100644 aaaa aaaa R100 renamed.txt",
            "old name.txt",
            "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc conflict.txt",
            "? notes/todo.md",
        ]
        let status = GlassEditorGitStatus.parse(Data((fields.joined(separator: "\0") + "\0").utf8))
        #expect(status.branch == "main")
        #expect(status.commit == "0123456789abcdef0123456789abcdef01234567")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 2 && status.behind == 1)
        #expect(status.changes.map(\.path) == ["Sources/App/a b.swift", "new.txt", "gone.txt", "both.txt",
                                               "renamed.txt", "conflict.txt", "notes/todo.md"])
        #expect(status.changes.map(\.kind) == [.modified, .added, .deleted, .modified, .renamed, .conflicted, .untracked])
        #expect(status.changes.map(\.letter) == ["M", "A", "D", "M", "R", "!", "U"])
        #expect(status.changes[4].originalPath == "old name.txt")
        #expect(status.changes[0].isStaged == false && status.changes[0].isUnstaged == true)
        #expect(status.changes[3].isStaged == true && status.changes[3].isUnstaged == true)
    }

    @Test func aRepositoryWithNoCommitAndADetachedHeadSayWhereTheyAre() {
        let initial = GlassEditorGitStatus.parse(Data("# branch.oid (initial)\0# branch.head trunk\0".utf8))
        #expect(initial.commit == nil)
        #expect(initial.headName == "trunk")
        let detached = GlassEditorGitStatus.parse(Data("# branch.oid abcdef0123456789\0# branch.head (detached)\0".utf8))
        #expect(detached.branch == nil)
        #expect(detached.headName == "at abcdef0")
    }

    // MARK: Diff

    private static let diff = """
    diff --git a/Sources/App.swift b/Sources/App.swift
    index 1111111..2222222 100644
    --- a/Sources/App.swift
    +++ b/Sources/App.swift
    @@ -1,4 +1,5 @@ import Foundation
     let a = 1
    -let b = 2
    +let b = 3
    +let c = 4
     let d = 5
     let e = 6
    @@ -20,2 +21,2 @@ func tail()
     one
    -two
    \\ No newline at end of file
    +two
    diff --git a/new file.txt b/new file.txt
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/new file.txt\t
    @@ -0,0 +1,2 @@
    +hello
    +world
    diff --git a/old.txt b/old.txt
    deleted file mode 100644
    index 4444444..0000000
    --- a/old.txt
    +++ /dev/null
    @@ -1 +0,0 @@
    -gone
    diff --git a/before.txt b/after.txt
    similarity index 90%
    rename from before.txt
    rename to after.txt
    index 5555555..6666666 100644
    --- a/before.txt
    +++ b/after.txt
    @@ -1,2 +1,2 @@
     same
    --- a/looks like a header
    ++++ b/looks like one too
    diff --git a/logo.png b/logo.png
    index 7777777..8888888 100644
    Binary files a/logo.png and b/logo.png differ
    diff --git a/run.sh b/run.sh
    old mode 100644
    new mode 100755

    """

    @Test func aDiffIsReadIntoFilesHunksAndNumberedLines() throws {
        let files = GlassEditorGitDiff.parse(Data(Self.diff.utf8))
        #expect(files.map(\.id) == ["Sources/App.swift", "new file.txt", "old.txt", "after.txt", "logo.png", "run.sh"])

        let app = files[0]
        #expect(app.hunks.count == 2)
        #expect(app.hunks[0].heading == "import Foundation")
        #expect(app.hunks[0].lines.map(\.kind) == [.context, .removed, .added, .added, .context, .context])
        #expect(app.hunks[0].lines.map(\.oldNumber) == [1, 2, nil, nil, 3, 4])
        #expect(app.hunks[0].lines.map(\.newNumber) == [1, nil, 2, 3, 4, 5])
        #expect(app.addedLines == 3 && app.removedLines == 2)
        // "\ No newline" belongs to the line before it, the old "two".
        let tail = app.hunks[1].lines
        #expect(tail.map(\.text) == ["one", "two", "two"])
        #expect(tail.map(\.noNewlineAtEnd) == [false, true, false])
        #expect(tail.map(\.newNumber) == [21, nil, 22])

        let new = files[1]
        #expect(new.oldPath == nil && new.newPath == "new file.txt")
        #expect(new.hunks.first?.lines.map(\.text) == ["hello", "world"])

        let deleted = files[2]
        #expect(deleted.newPath == nil && deleted.oldPath == "old.txt")
        #expect(deleted.hunks.first?.lines.map(\.kind) == [.removed])

        // Read by its counts: a removed line that reads like a header is still a line.
        let renamed = files[3]
        #expect(renamed.oldPath == "before.txt" && renamed.newPath == "after.txt")
        #expect(renamed.hunks.first?.lines.map(\.text) == ["same", "-- a/looks like a header", "+++ b/looks like one too"])
        #expect(renamed.hunks.first?.lines.map(\.kind) == [.context, .removed, .added])

        #expect(files[4].isBinary)
        #expect(files[5].oldMode == "100644" && files[5].newMode == "100755" && files[5].hunks.isEmpty)
    }

    @Test func quotedNamesAreUnquoted() {
        #expect(GlassEditorGitDiff.unquoted(#""caf\303\251 \"quoted\"\tname""#) == "café \"quoted\"\tname")
        let (old, new) = GlassEditorGitDiff.paths(inHeader: #""a/with\ttab" "b/with\ttab""#)
        #expect(old == "with\ttab" && new == "with\ttab")
        // A name holding " b/" is read from its two agreeing halves.
        let (left, right) = GlassEditorGitDiff.paths(inHeader: "a/x b/y b/x b/y")
        #expect(left == "x b/y" && right == "x b/y")
    }

    @Test func aNewFileReadsAsEveryLineAdded() {
        let file = GlassEditorFileDiff.addition(path: "notes.md", text: "one\ntwo")
        #expect(file.hunks.first?.lines.map(\.newNumber) == [1, 2])
        #expect(file.hunks.first?.lines.last?.noNewlineAtEnd == true)
        #expect(file.addedLines == 2)
    }

    // MARK: The command line for another machine

    @Test func aRemoteCommandQuotesOnlyWhatTheShellWouldRead() {
        #expect(GlassEditorRemoteGit.commandLine(["status", "--porcelain=v2", "--", "."], in: "/srv/app")
                == "git -C /srv/app status --porcelain=v2 -- .")
        #expect(GlassEditorRemoteGit.commandLine(["status"], in: "/home/ann/my project's")
                == "git -C '/home/ann/my project'\\''s' status")
        #expect(GlassEditorRemoteGit.shellWord("$(rm -rf ~)") == "'$(rm -rf ~)'")
        #expect(GlassEditorRemoteGit.shellWord("") == "''")
    }
}

/// Answers each git command from a table, and keeps what it was asked.
@MainActor
final class ScriptedGit: GlassEditorGitRunner {
    var answers: [String: GlassEditorCommandOutput] = [:]
    var thrown: GlassEditorGitError?
    private(set) var asked: [[String]] = []

    func git(_ arguments: [String], in directory: String) async throws -> GlassEditorCommandOutput {
        asked.append(arguments)
        if let thrown { throw thrown }
        let verb = arguments.first { !$0.hasPrefix("-") && $0 != "core.quotePath=false" } ?? ""
        return answers[verb] ?? GlassEditorCommandOutput(exitStatus: 0, standardOutput: Data())
    }
}

/// A project's files, held in memory.
@MainActor
struct MemoryFiles: GlassEditorFileAccess {
    var files: [String: String]
    func contents(ofDirectory path: String) async throws -> [GlassEditorProjectNode] { [] }
    func read(_ path: String) async throws -> Data {
        guard let text = files[path] else { throw CocoaError(.fileNoSuchFile) }
        return Data(text.utf8)
    }
    func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat? { nil }
    func stat(_ path: String) async throws -> RemoteStat? {
        files[path].map { RemoteStat(size: UInt64($0.utf8.count), modificationSeconds: 1) }
    }
}

@MainActor
@Suite("Git: a project's repository")
struct GlassEditorGitRepositoryTests {
    private func output(_ text: String, status: Int = 0, error: String = "") -> GlassEditorCommandOutput {
        GlassEditorCommandOutput(exitStatus: status, standardOutput: Data(text.utf8), standardError: Data(error.utf8))
    }

    @Test func aProjectBelowTheRepositoryRootMarksItsOwnPaths() async {
        let git = ScriptedGit()
        git.answers["rev-parse"] = output("Sources/\n")
        git.answers["status"] = output([
            "# branch.oid abc", "# branch.head main",
            "1 .M N... 100644 100644 100644 a b Sources/App/Model.swift",
            "? Sources/notes.md",
        ].joined(separator: "\0") + "\0")
        let repository = GlassEditorGitRepository(projectPath: "/srv/repo/Sources", machine: "alpha", runner: git,
                                                  access: MemoryFiles(files: [:]))
        repository.refresh()
        await repository.settled()
        #expect(repository.state == .ready)
        #expect(repository.change(atPath: "/srv/repo/Sources/App/Model.swift")?.kind == .modified)
        #expect(repository.change(atPath: "/srv/repo/Sources/notes.md")?.kind == .untracked)
        #expect(repository.folderHasChanges("/srv/repo/Sources/App"))
        #expect(repository.folderHasChanges("/srv/repo/Sources"))
        #expect(!repository.folderHasChanges("/srv/repo"))
        #expect(repository.projectRelative("Sources/App/Model.swift") == "App/Model.swift")
        // The list is enough for the tree: no diff until Changes asks.
        #expect(!git.asked.contains { $0.contains("diff") })
    }

    @Test func changesReadsTheDiffAndNewFilesWhole() async throws {
        let git = ScriptedGit()
        git.answers["rev-parse"] = output("")
        git.answers["status"] = output("# branch.oid abc\0# branch.head main\01 .M N... 100644 100644 100644 a b a.txt\0? b.txt\0")
        git.answers["diff"] = output("diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-old\n+new\n")
        let repository = GlassEditorGitRepository(projectPath: "/p", machine: nil, runner: git,
                                                  access: MemoryFiles(files: ["/p/b.txt": "fresh\n"]))
        repository.showsDiffs = true
        await repository.settled()
        #expect(repository.hasReadDiffs)
        #expect(repository.diffs["a.txt"]?.hunks.first?.lines.map(\.text) == ["old", "new"])
        #expect(repository.diffs["b.txt"]?.hunks.first?.lines.map(\.text) == ["fresh"])
        let diff = try #require(git.asked.first { $0.contains("diff") })
        #expect(diff.contains("HEAD"))
        #expect(diff.contains("--no-ext-diff") && diff.contains("--src-prefix=a/") && diff.contains("--no-relative"))
    }

    @Test func aFolderOutsideAnyRepositoryShowsNoGit() async {
        let git = ScriptedGit()
        git.answers["rev-parse"] = output("", status: 128, error: "fatal: not a git repository (or any of the parent directories): .git\n")
        let repository = GlassEditorGitRepository(projectPath: "/p", machine: nil, runner: git, access: MemoryFiles(files: [:]))
        repository.refresh()
        await repository.settled()
        #expect(repository.state == .notARepository)
        #expect(!repository.isRepository)
    }

    @Test func whatGoesWrongIsSaidWithWhatToDo() async {
        let owned = ScriptedGit()
        owned.answers["rev-parse"] = output("", status: 128, error: """
            fatal: detected dubious ownership in repository at '/srv/app'
            To add an exception for this directory, call:

            \tgit config --global --add safe.directory /srv/app
            """)
        let repository = GlassEditorGitRepository(projectPath: "/srv/app", machine: "alpha", runner: owned, access: MemoryFiles(files: [:]))
        repository.refresh()
        await repository.settled()
        #expect(repository.state == .unavailable("Git won't read this folder because another account owns it. Run git config --global --add safe.directory /srv/app on alpha, then refresh."))

        let missing = ScriptedGit()
        missing.thrown = .notInstalled
        let elsewhere = GlassEditorGitRepository(projectPath: "/srv/app", machine: "alpha", runner: missing,
                                                 access: MemoryFiles(files: ["/srv/app/.git": ""]))
        elsewhere.refresh()
        await elsewhere.settled()
        #expect(elsewhere.state == .unavailable("Git isn't installed on alpha. Install it there (for example, sudo apt install git), then refresh."))
        #expect(elsewhere.isRepository, "the footer says so, rather than hiding git")

        // No git and no repository: nothing to say.
        let plain = GlassEditorGitRepository(projectPath: "/srv/notes", machine: "alpha", runner: missing,
                                             access: MemoryFiles(files: [:]))
        plain.refresh()
        await plain.settled()
        #expect(plain.state == .notARepository)
    }
}

@MainActor
@Suite("Git: staging and committing")
struct GlassEditorGitCommitTests {
    private func output(_ text: String, status: Int = 0, error: String = "") -> GlassEditorCommandOutput {
        GlassEditorCommandOutput(exitStatus: status, standardOutput: Data(text.utf8), standardError: Data(error.utf8))
    }

    private func ready(_ git: ScriptedGit, prefix: String = "", projectPath: String = "/p",
                       entries: [String]) async -> GlassEditorGitRepository {
        git.answers["rev-parse"] = output(prefix + "\n")
        git.answers["status"] = output((["# branch.oid abc1234def", "# branch.head main"] + entries)
            .joined(separator: "\0") + "\0")
        let repository = GlassEditorGitRepository(projectPath: projectPath, machine: "alpha", runner: git,
                                                  access: MemoryFiles(files: [:]))
        repository.refresh()
        await repository.settled()
        return repository
    }

    @Test func stagingNamesEachPathExactlyAndARenameByBothNames() async throws {
        let git = ScriptedGit()
        let repository = await ready(git, entries: [
            "1 .M N... 100644 100644 100644 a b src/a b.txt",
            "2 R. N... 100644 100644 100644 a b R100 new.txt", "old.txt",
        ])
        await repository.stage(repository.status.changes)
        let add = try #require(git.asked.first { $0.contains("add") })
        #expect(Array(add.drop { $0 != "add" }) == ["add", "-A", "--", ":(top,literal)src/a b.txt",
                                                   ":(top,literal)new.txt", ":(top,literal)old.txt"])
        await repository.unstage([try #require(repository.status.changes.first)])
        let reset = try #require(git.asked.first { $0.contains("reset") })
        #expect(Array(reset.drop { $0 != "reset" }) == ["reset", "-q", "--", ":(top,literal)src/a b.txt"])
        // Each is followed by asking git what it did.
        #expect(git.asked.last?.contains("status") == true)
        #expect(repository.actionProblem == nil && !repository.isWorking)
    }

    @Test func aCommitWithNothingStagedStagesEverythingButNestedRepositoriesFirst() async throws {
        let git = ScriptedGit()
        let repository = await ready(git, entries: ["1 .M N... 100644 100644 100644 a b a.txt", "? vendor/lib/"])
        repository.commitMessage = "  Fix the thing\n\nWhy it was broken.\n"
        #expect(await repository.commit() == .committed)
        let verbs = git.asked.compactMap { $0.first { ["add", "commit", "diff"].contains($0) } }
        #expect(verbs == ["add", "commit"], "at the repository's root nothing is outside the folder to ask about")
        let add = try #require(git.asked.first { $0.contains("add") })
        #expect(Array(add.drop { $0 != "add" }) == ["add", "-A", "--", ".", ":(exclude,top,literal)vendor/lib/"])
        let commit = try #require(git.asked.first { $0.contains("commit") })
        #expect(Array(commit.drop { $0 != "commit" }) == ["commit", "--quiet", "-m", "  Fix the thing\n\nWhy it was broken.\n"])
        #expect(repository.commitMessage.isEmpty)
        #expect(repository.lastCommit == GlassEditorCommitNote(name: "abc1234", branch: "main", summary: "Fix the thing"))
    }

    @Test func filesStagedOutsideTheFolderAreAskedAboutFirst() async throws {
        let git = ScriptedGit()
        let repository = await ready(git, prefix: "Sources/", projectPath: "/repo/Sources",
                                     entries: ["1 M. N... 100644 100644 100644 a b Sources/a.txt"])
        git.answers["diff"] = output("Sources/a.txt\0README.md\0")
        repository.commitMessage = "Both"
        #expect(await repository.commit() == .alsoStagedOutside(["README.md"]))
        #expect(!git.asked.contains { $0.contains("commit") }, "nothing committed before the answer")
        #expect(repository.commitMessage == "Both")
        #expect(await repository.commit(includingOutside: true) == .committed)
        #expect(git.asked.contains { $0.contains("commit") })
    }

    @Test func aRefusedCommitSaysWhatToDo() async {
        let git = ScriptedGit()
        let repository = await ready(git, entries: ["1 M. N... 100644 100644 100644 a b a.txt"])
        repository.commitMessage = "Message"
        git.answers["commit"] = output("", status: 128, error: """
            Author identity unknown

            *** Please tell me who you are.

            fatal: empty ident name (for <>) not allowed
            """)
        #expect(await repository.commit() == .notCommitted)
        #expect(repository.actionProblem == "Git doesn't know who you are on alpha. Run git config --global user.name \"Your Name\" and git config --global user.email you@example.com there, then commit again.")
        #expect(repository.commitMessage == "Message", "the message is kept for the next try")

        // A hook that refused, on standard output.
        git.answers["commit"] = output("lint: 3 problems\nmore\n", status: 1)
        #expect(await repository.commit() == .notCommitted)
        #expect(repository.actionProblem == "Git couldn't commit: lint: 3 problems")

        git.answers["commit"] = output("", status: 128, error: "fatal: Unable to create '/p/.git/index.lock': File exists.\n")
        #expect(await repository.commit() == .notCommitted)
        #expect(repository.actionProblem?.hasPrefix("Another git command is using this repository.") == true)

        repository.commitMessage = "   "
        #expect(await repository.commit() == .notCommitted)
        #expect(repository.actionProblem == "Write a message for the commit first.")
    }

    @Test func aFilesLastCommitIsReadOnceAndANewFileWasEmpty() async throws {
        let git = ScriptedGit()
        let repository = await ready(git, prefix: "app/", projectPath: "/srv/repo/app", entries: [
            "1 .M N... 100644 100644 100644 a b app/a.txt",
            "2 R. N... 100644 100644 100644 a b R100 app/moved.txt", "app/was.txt",
            "? app/new.txt",
        ])
        git.answers["cat-file"] = output("one\ntwo\n")
        #expect(await repository.committedText(ofPath: "/srv/repo/app/a.txt") == "one\ntwo\n")
        #expect(git.asked.last?.suffix(2) == ["--filters", "HEAD:app/a.txt"])
        #expect(await repository.committedText(ofPath: "/srv/repo/app/a.txt") == "one\ntwo\n")
        #expect(git.asked.filter { $0.contains("cat-file") }.count == 1, "kept until the commit changes")
        _ = await repository.committedText(ofPath: "/srv/repo/app/moved.txt")
        #expect(git.asked.last?.last == "HEAD:app/was.txt", "a renamed file's last commit is under its old name")
        #expect(await repository.committedText(ofPath: "/srv/repo/app/new.txt") == "")
        #expect(await repository.committedText(ofPath: "/srv/elsewhere/a.txt") == nil)
        git.answers["cat-file"] = output("", status: 128, error: "fatal: path 'app/ignored.log' does not exist in 'HEAD'\n")
        #expect(await repository.committedText(ofPath: "/srv/repo/app/ignored.log") == nil, "an ignored file has no marks")
    }
}

#if os(macOS)
/// This Mac's `git`, in a repository made for the test.
@MainActor
@Suite("Git: this Mac's git", .serialized)
struct GlassEditorLocalGitTests {
    private func makeRepository() async throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorGit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try await git(["init", "-q", "-b", "trunk"], in: root)
        try Data("one\ntwo\nthree\n".utf8).write(to: root.appendingPathComponent("Sources/a.txt"))
        try Data("keep\n".utf8).write(to: root.appendingPathComponent("b.txt"))
        try await git(["add", "."], in: root)
        // No hooks: the owner's global git configuration may name some, and they'd run here.
        try await git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
                       "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "first"], in: root)
        return root
    }

    /// git, waited for on a Dispatch thread: this suite is on the main actor, and seven to ten runs a
    /// test held it from every other main-actor test in the run (2026-10-24).
    @discardableResult
    private func git(_ arguments: [String], in root: URL) async throws -> GlassEditorCommandOutput {
        let executable = try #require(GlassEditorLocalGit.executable, "the tests need git on this Mac")
        let path = root.path(percentEncoded: false)
        let output = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try GlassEditorLocalGit.run(executable, arguments, in: path) })
            }
        }
        #expect(output.exitStatus == 0, "\(arguments): \(String(decoding: output.standardError, as: UTF8.self))")
        return output
    }

    @Test func aProjectInARepositoryShowsItsChangesAndTheirLines() async throws {
        let root = try await makeRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("one\n2\nthree\n".utf8).write(to: root.appendingPathComponent("Sources/a.txt"))
        try Data("new\n".utf8).write(to: root.appendingPathComponent("Sources/c.txt"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.txt"))

        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.git.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        #expect(repository.state == .ready)
        #expect(repository.status.branch == "trunk")
        let sources = project.path + "/Sources"
        #expect(workspace.gitChange(at: sources + "/a.txt")?.kind == .modified)
        #expect(workspace.gitChange(at: sources + "/c.txt")?.kind == .untracked)
        #expect(workspace.folderHasGitChanges(sources))
        #expect(repository.status.changes.contains { $0.path == "b.txt" && $0.kind == .deleted })

        let changes = try #require(workspace.showChanges())
        #expect(changes.changesOfProject == project.id && !changes.isText && !changes.hasNeverBeenSaved)
        await repository.settled()
        let lines = try #require(repository.diffs["Sources/a.txt"]?.hunks.first?.lines)
        #expect(lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(lines.map(\.text) == ["one", "two", "2", "three"])
        #expect(repository.diffs["b.txt"]?.newPath == nil)
        #expect(repository.diffs["Sources/c.txt"]?.hunks.first?.lines.map(\.text) == ["new"])

        // Chosen again, not opened twice; closing it stops the reading.
        #expect(workspace.showChanges()?.id == changes.id)
        workspace.close(changes.id)
        #expect(!repository.showsDiffs)
    }

    @Test func aRepositoryWithNoCommitShowsEverythingAsNew() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorGit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await git(["init", "-q", "-b", "trunk"], in: root)
        try Data("first\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        try await git(["add", "a.txt"], in: root)
        let repository = GlassEditorGitRepository(projectPath: root.path(percentEncoded: false), machine: nil,
                                                  runner: GlassEditorLocalGit.shared, access: GlassEditorLocalFileAccess())
        repository.showsDiffs = true
        await repository.settled()
        #expect(repository.status.commit == nil)
        #expect(repository.status.headName == "trunk")
        #expect(repository.diffs["a.txt"]?.hunks.first?.lines.map(\.kind) == [.added])
        #expect(repository.diffProblem == nil)
    }

    /// A repository the editor itself can commit in: its own name and address, no signing, and
    /// no hooks from this Mac's global configuration.
    private func makeCommittableRepository() async throws -> URL {
        let root = try await makeRepository()
        try await git(["config", "user.name", "Test"], in: root)
        try await git(["config", "user.email", "test@example.com"], in: root)
        try await git(["config", "commit.gpgsign", "false"], in: root)
        try await git(["config", "core.hooksPath", ".git/hooks"], in: root)
        return root
    }

    @Test func filesAreStagedUnstagedAndCommittedFromChanges() async throws {
        let root = try await makeCommittableRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("one\n2\nthree\n".utf8).write(to: root.appendingPathComponent("Sources/a.txt"))
        try Data("new\n".utf8).write(to: root.appendingPathComponent("Sources/c.txt"))
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.git.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        let a = try #require(repository.status.changes.first { $0.path == "Sources/a.txt" })

        await repository.stage([a])
        let staged = try #require(repository.status.changes.first { $0.path == "Sources/a.txt" })
        #expect(staged.isStaged && !staged.isUnstaged)
        #expect(repository.hasStagedChanges)
        await repository.unstage([staged])
        #expect(repository.status.changes.first { $0.path == "Sources/a.txt" }?.isStaged == false)
        await repository.stage([a])

        repository.commitMessage = "Change a\n\nTwo is a number now."
        #expect(await repository.commit() == .committed)
        #expect(repository.actionProblem == nil)
        #expect(repository.status.changes.map(\.path) == ["Sources/c.txt"], "only what was staged went in")
        #expect(repository.lastCommit?.summary == "Change a")
        #expect(repository.lastCommit?.branch == "trunk")
        let message = try await git(["log", "-1", "--format=%B"], in: root)
        #expect(String(decoding: message.standardOutput, as: UTF8.self) == "Change a\n\nTwo is a number now.\n\n")

        // Nothing staged: Commit All takes the new file too.
        repository.commitMessage = "Add c"
        #expect(await repository.commit() == .committed)
        #expect(repository.status.changes.isEmpty)
        let count = try await git(["rev-list", "--count", "HEAD"], in: root)
        #expect(String(decoding: count.standardOutput, as: UTF8.self) == "3\n")
    }

    @Test func aProjectBelowTheRootAsksBeforeCommittingFilesStagedOutsideIt() async throws {
        let root = try await makeCommittableRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("changed\n".utf8).write(to: root.appendingPathComponent("b.txt"))
        try await git(["add", "b.txt"], in: root)
        try Data("one\n2\nthree\n".utf8).write(to: root.appendingPathComponent("Sources/a.txt"))
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let repository = GlassEditorGitRepository(projectPath: sources.path(percentEncoded: false), machine: nil,
                                                  runner: GlassEditorLocalGit.shared, access: GlassEditorLocalFileAccess())
        repository.refresh()
        await repository.settled()
        repository.commitMessage = "Only a"
        #expect(await repository.commit() == .alsoStagedOutside(["b.txt"]))
        #expect(repository.status.changes.first?.isStaged == false, "nothing staged before the answer")
    }

    @Test func marksFollowTheTextAsItIsTypedSavedAndCommitted() async throws {
        let root = try await makeCommittableRepository(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("brand new\n".utf8).write(to: root.appendingPathComponent("Sources/c.txt"))
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.git.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        let document = try #require(await workspace.open(path: project.path + "/Sources/a.txt"))
        let model = document.model

        func marks(becoming expected: [LineChange]) async -> [LineChange] {
            for _ in 0..<200 where model.lineChanges != expected {
                await workspace.lineMarksSettled(document.id)
                try? await Task.sleep(for: .milliseconds(20))
            }
            return model.lineChanges
        }
        // Once the last commit's text is read and compared: before that, no marks proves nothing.
        await workspace.lineMarksSettled(document.id)
        #expect(model.lineChanges == [], "an unchanged file has no marks")

        // Typed, not saved: the marks follow the buffer.
        let two = model.lineRange(ofLine: 1).lowerBound
        try model.apply(TextEdit(replacementRange: two..<(two + 3), text: "2"))
        let changed = [LineChange(kind: .modified, lines: 1..<2, baseLines: 1..<2)]
        #expect(await marks(becoming: changed) == changed)
        try model.apply(TextEdit(replacementRange: 0..<0, text: "zero\n"))
        let more = [LineChange(kind: .added, lines: 0..<1, baseLines: 0..<0),
                    LineChange(kind: .modified, lines: 2..<3, baseLines: 1..<2)]
        #expect(await marks(becoming: more) == more)

        // Saved and committed: the last commit moved, and nothing differs from it.
        await workspace.save(document.id)
        await repository.settled()
        await repository.stage(repository.status.changes.filter { $0.path == "Sources/a.txt" })
        repository.commitMessage = "Typed"
        #expect(await repository.commit() == .committed)
        #expect(await marks(becoming: []) == [])

        // A file git doesn't know yet is new throughout.
        let fresh = try #require(await workspace.open(path: project.path + "/Sources/c.txt"))
        let added = [LineChange(kind: .added, lines: 0..<1, baseLines: 0..<0)]
        for _ in 0..<200 where fresh.model.lineChanges != added {
            await workspace.lineMarksSettled(fresh.id)
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fresh.model.lineChanges == added)

        // Closed, its marks stop.
        workspace.close(fresh.id, force: true)
        #expect(fresh.model.lineChanges.isEmpty)
    }

    @Test func aFolderOutsideARepositoryHasNoBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorPlain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.git.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        #expect(repository.state == .notARepository)
        #expect(workspace.showChanges() == nil, "no Changes for a folder git does not know")
    }
}
#endif
