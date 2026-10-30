//
//  GlassEditorGitReadingTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  The parts of git in the editor added 2026-10-28 ("build git now, end to end, first class"),
//  read without git: branches, tags, stashes, remotes, commits and their graph, blame, the patches
//  that stage a hunk or chosen lines, word highlights, side-by-side rows and conflict markers.
//  Each answer is what git itself writes, copied from its documentation's formats.
//

import Foundation
import Testing
@testable import GlassEditor

@Suite("Git: reading branches, history and conflicts")
struct GlassEditorGitReadingTests {

    // MARK: References

    @Test func branchesReadTheirUpstreamDistanceAndWhichIsCheckedOut() {
        let lines = [
            "refs/heads/main\0aaa\0origin/main\0ahead 2, behind 1\01700000000\0First line\0*",
            "refs/heads/old\0bbb\0origin/old\0gone\01600000000\0Old work\0 ",
            "refs/heads/local\0ccc\0\0\01650000000\0No upstream\0 ",
            "refs/remotes/origin/HEAD\0aaa\0\0\01700000000\0First line\0 ",
            "refs/remotes/origin/feature/x\0ddd\0\0\01710000000\0Remote work\0 ",
        ].joined(separator: "\n") + "\n"
        let branches = GlassEditorGitBranch.parse(Data(lines.utf8))
        #expect(branches.map(\.name) == ["main", "old", "local", "origin/feature/x"], "a remote's HEAD pointer is left out")
        #expect(branches[0].isCurrent && branches[0].ahead == 2 && branches[0].behind == 1 && branches[0].upstream == "origin/main")
        #expect(branches[1].upstreamGone && !branches[1].isCurrent)
        #expect(branches[2].upstream == nil && branches[2].ahead == 0)
        let remote = branches[3]
        #expect(remote.isRemote && remote.remote == "origin" && remote.shortName == "feature/x")
        #expect(remote.date == Date(timeIntervalSince1970: 1_710_000_000))
    }

    @Test func anAnnotatedTagNamesItsCommitNotItsTagObject() {
        let lines = "v2\0tagobject\0commit2\01700000000\0Release two\nv1\0commit1\0\01600000000\0Light\n"
        let tags = GlassEditorGitTag.parse(Data(lines.utf8))
        #expect(tags.map(\.name) == ["v2", "v1"])
        #expect(tags[0].isAnnotated && tags[0].commit == "commit2")
        #expect(!tags[1].isAnnotated && tags[1].commit == "commit1")
    }

    @Test func stashesReadTheirPlaceAndMessage() {
        let lines = "stash@{0}\0abc\01700000000\0On main: wip\nstash@{12}\0def\01600000000\0WIP on main: 123 subject\n"
        let stashes = GlassEditorGitStash.parse(Data(lines.utf8))
        #expect(stashes.map(\.index) == [0, 12])
        #expect(stashes[0].message == "On main: wip" && stashes[1].commit == "def")
    }

    @Test func aRemotesWebPageIsFoundFromItsSSHOrHTTPSAddress() throws {
        let remotes = GlassEditorGitRemote.parse(Data("""
            origin\tgit@github.com:owner/repo.git (fetch)
            origin\tgit@github.com:owner/repo.git (push)
            lab\thttps://user:secret@gitlab.example.com:8443/group/repo.git (fetch)
            local\t/srv/git/repo.git (fetch)

            """.utf8))
        #expect(remotes.map(\.name) == ["origin", "lab", "local"])
        let github = remotes[0]
        #expect(github.webAddress?.absoluteString == "https://github.com/owner/repo")
        #expect(github.isGitHub)
        #expect(github.webAddress(ofCommit: "abc")?.absoluteString == "https://github.com/owner/repo/commit/abc")
        #expect(github.webAddress(ofFile: "Sources/a b.swift", at: "main", line: 12)?.absoluteString
                == "https://github.com/owner/repo/blob/main/Sources/a%20b.swift#L12")
        #expect(github.pullRequestAddress(for: "feature")?.absoluteString == "https://github.com/owner/repo/compare/feature?expand=1")
        let lab = remotes[1]
        #expect(lab.webAddress?.absoluteString == "https://gitlab.example.com/group/repo", "no password, no port")
        #expect(lab.webAddress(ofCommit: "abc")?.absoluteString == "https://gitlab.example.com/group/repo/-/commit/abc")
        #expect(remotes[2].webAddress == nil, "a folder has no web page")
    }

    @Test func aClonesFolderIsNamedAsGitNamesIt() {
        #expect(GlassEditorGitRepository.cloneName(of: "git@github.com:owner/repo.git") == "repo")
        #expect(GlassEditorGitRepository.cloneName(of: " https://github.com/owner/repo/ ") == "repo")
        #expect(GlassEditorGitRepository.cloneName(of: "/srv/git/project.git") == "project")
        #expect(GlassEditorGitRepository.cloneName(of: "repo") == nil, "a bare word is no address")
        #expect(GlassEditorGitRepository.cloneName(of: "https://example.com/..") == nil)
    }

    // MARK: History

    @Test func commitsReadTheirParentsRefsAndWholeMessage() {
        let record = "h1\0p1 p2\0Ann\0ann@example.com\01700000000\0HEAD -> main, origin/main, tag: v1\0Merge it\0Why it was merged.\n\nMore.\n\u{1E}"
            + "\nh2\0\0Bob\0bob@example.com\01600000000\0\0Root\0\u{1E}"
        let commits = GlassEditorGitCommit.parse(Data(record.utf8))
        #expect(commits.count == 2)
        #expect(commits[0].isMerge && commits[0].parents == ["p1", "p2"])
        #expect(commits[0].refs == ["HEAD -> main", "origin/main", "tag: v1"])
        #expect(commits[0].message == "Merge it\n\nWhy it was merged.\n\nMore.")
        #expect(commits[1].parents.isEmpty && commits[1].refs.isEmpty && commits[1].message == "Root")
    }

    /// m (merge of b into a) ─ a ─ root, and b ─ root: two lanes that meet at the merge and the root.
    @Test func theGraphPutsABranchInItsOwnLaneUntilItJoins() {
        func commit(_ hash: String, _ parents: [String]) -> GlassEditorGitCommit {
            GlassEditorGitCommit(hash: hash, parents: parents, author: "", email: "", date: .now, refs: [], subject: hash, body: "")
        }
        let rows = GlassEditorGitGraphRow.rows(for: [commit("m", ["a", "b"]), commit("a", ["root"]),
                                                     commit("b", ["root"]), commit("root", [])])
        #expect(rows[0].lane == 0 && rows[0].incoming.isEmpty && rows[0].outgoing == [0, 1], "the merge opens a lane for b")
        #expect(rows[1].lane == 0 && rows[1].passing == [1], "b's lane passes a")
        #expect(rows[2].lane == 1 && rows[2].incoming == [1] && rows[2].passing == [0])
        #expect(rows[3].lane == 0 && Set(rows[3].incoming) == [0, 1], "both lanes end at the root")
        #expect(rows.allSatisfy { $0.width >= 1 } && rows[1].width == 2)
    }

    /// x and the merge m both have b as a parent: the merge joins the lane already waiting for b
    /// rather than opening a third, as `git log --graph` draws it.
    @Test func aMergeJoinsTheLaneAlreadyWaitingForItsParent() {
        func commit(_ hash: String, _ parents: [String]) -> GlassEditorGitCommit {
            GlassEditorGitCommit(hash: hash, parents: parents, author: "", email: "", date: .now, refs: [], subject: hash, body: "")
        }
        let rows = GlassEditorGitGraphRow.rows(for: [commit("x", ["b"]), commit("m", ["a", "b"]), commit("a", ["root"]),
                                                     commit("b", ["root"]), commit("root", [])])
        #expect(rows[1].lane == 1 && rows[1].outgoing == [1, 0])
        #expect(rows[3].lane == 0 && rows[3].incoming == [0])
        #expect(rows.map(\.width).max() == 2)
    }

    @Test func blameReadsEachCommitsDetailsOnceAndEveryLine() {
        let hashA = String(repeating: "a", count: 40), zero = String(repeating: "0", count: 40)
        let text = """
            \(hashA) 1 1 2
            author Ann
            author-mail <ann@example.com>
            author-time 1700000000
            summary First
            filename a.txt
            \tline one
            \(hashA) 2 2
            \tline two
            \(zero) 3 3 1
            author Not Committed Yet
            author-time 1800000000
            summary Version of a.txt from a.txt
            filename a.txt
            \tline three

            """
        let lines = GlassEditorGitBlame.parse(Data(text.utf8))
        #expect(lines.map(\.number) == [1, 2, 3])
        #expect(lines.map(\.text) == ["line one", "line two", "line three"])
        #expect(lines[1].author == "Ann" && lines[1].summary == "First", "the second line reuses the commit's details")
        #expect(!lines[0].isUncommitted && lines[2].isUncommitted)
    }

    // MARK: Patches

    private var hunkFile: GlassEditorFileDiff {
        let diff = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,4 +1,4 @@
             one
            -two
            -three
            +2
            +3
             four

            """
        return GlassEditorGitDiff.parse(Data(diff.utf8))[0]
    }

    @Test func aWholeHunkIsItsOwnPatch() throws {
        let patch = try #require(GlassEditorGitPatch.patch(of: hunkFile, hunk: 0, reverse: false))
        #expect(patch == "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,4 +1,4 @@\n one\n-two\n-three\n+2\n+3\n four\n")
    }

    /// Lines 1 (−two) and 3 (+2) chosen: forwards, the unchosen removal stays as context and the
    /// unchosen addition goes; backwards, the other way about.
    @Test func chosenLinesKeepTheSideThePatchIsMatchedAgainst() throws {
        let forwards = try #require(GlassEditorGitPatch.patch(of: hunkFile, hunk: 0, chosen: [1, 3], reverse: false))
        #expect(forwards.hasSuffix("@@ -1,4 +1,4 @@\n one\n-two\n three\n+2\n four\n"))
        let backwards = try #require(GlassEditorGitPatch.patch(of: hunkFile, hunk: 0, chosen: [1, 3], reverse: true))
        #expect(backwards.hasSuffix("@@ -1,4 +1,4 @@\n one\n-two\n+2\n 3\n four\n"))
        #expect(GlassEditorGitPatch.patch(of: hunkFile, hunk: 0, chosen: [0, 5], reverse: false) == nil,
                "context alone changes nothing")
    }

    @Test func aPathWithASpaceOrAQuoteIsWrittenAsGitWritesIt() {
        #expect(GlassEditorGitPatch.name("a/", "my file.txt", ending: true) == "a/my file.txt\t")
        #expect(GlassEditorGitPatch.name("a/", "my file.txt") == "a/my file.txt")
        #expect(GlassEditorGitPatch.name("b/", "say \"hi\".txt") == "\"b/say \\\"hi\\\".txt\"")
        #expect(GlassEditorGitPatch.name("b/", "café.txt") == "b/café.txt")
    }

    @Test func onlyAFileWithTheSamePathOnBothSidesIsPatchedInParts() {
        #expect(GlassEditorGitPatch.canPatch(hunkFile))
        #expect(!GlassEditorGitPatch.canPatch(.addition(path: "new.txt", text: "x\n")))
    }

    // MARK: Showing a diff

    @Test func theWordsThatChangedAreHighlightedAndAWholeNewLineIsNot() throws {
        let ranges = try #require(GlassEditorWordDiff.ranges(old: "let width = 10", new: "let height = 10"))
        #expect(ranges.old == [4..<9] && ranges.new == [4..<10])
        #expect(GlassEditorWordDiff.ranges(old: "alpha beta", new: "gamma delta") == nil, "nothing in common")
        #expect(GlassEditorWordDiff.highlights(of: hunkFile.hunks[0]).isEmpty, "two → 2 have nothing in common")
        var hunk = GlassEditorDiffHunk(oldStart: 1, oldCount: 2, newStart: 1, newCount: 2, heading: "")
        hunk.lines = [GlassEditorDiffLine(kind: .removed, text: "let width = 10", oldNumber: 1, newNumber: nil),
                      GlassEditorDiffLine(kind: .removed, text: "same", oldNumber: 2, newNumber: nil),
                      GlassEditorDiffLine(kind: .added, text: "let height = 10", oldNumber: nil, newNumber: 1),
                      GlassEditorDiffLine(kind: .added, text: "same!", oldNumber: nil, newNumber: 2)]
        let highlights = GlassEditorWordDiff.highlights(of: hunk)
        #expect(highlights[0] == [4..<9] && highlights[2] == [4..<10], "removed and added lines paired in order")
        #expect(highlights[1] == nil && highlights[3] == [4..<5])
    }

    @Test func sideBySideRowsPairRemovedLinesWithTheirReplacements() {
        let rows = GlassEditorSplitRow.rows(of: hunkFile.hunks[0])
        #expect(rows == [GlassEditorSplitRow(left: 0, right: 0), GlassEditorSplitRow(left: 1, right: 3),
                         GlassEditorSplitRow(left: 2, right: 4), GlassEditorSplitRow(left: 5, right: 5)])
    }

    /// Wrap Long Lines off draws a diff a hunk at a time, each hunk's lines scrolling under its bar
    /// (2026-10-29): every row lands under its own hunk, none twice and none lost, in either layout.
    @MainActor @Test func unwrappedLinesAreGroupedUnderTheirOwnHunk() {
        let diff = """
            diff --git a/f.txt b/f.txt
            --- a/f.txt
            +++ b/f.txt
            @@ -1,2 +1,2 @@
             one
            -two
            +2
            @@ -10,2 +10,3 @@
             ten
            +10½
             eleven

            """
        let file = GlassEditorGitDiff.parse(Data(diff.utf8))[0]
        let unified = GlassEditorDiffRows.hunks(of: GlassEditorDiffRows.rows(of: file, id: "test-unified", layout: .unified))
        #expect(unified.map(\.index) == [0, 1])
        #expect(unified.map(\.rows.count) == [3, 3], "one row per line")
        let lines = unified[1].rows.compactMap { row -> Int? in
            if case .line(let hunk, let line, _) = row.content, hunk == 1 { return line } else { return nil }
        }
        #expect(lines == [0, 1, 2])
        let split = GlassEditorDiffRows.hunks(of: GlassEditorDiffRows.rows(of: file, id: "test-split", layout: .split))
        #expect(split.map(\.rows.count) == [2, 3], "−two and +2 share a row")
    }

    @Test func aCombinedDiffDoesNotRenameTheFileBeforeIt() {
        let diff = """
            diff --git a/a.txt b/a.txt
            --- a/a.txt
            +++ b/a.txt
            @@ -1 +1 @@
            -x
            +y
            diff --cc b.txt
            index 1,2..3
            --- a/b.txt
            +++ b/b.txt
            @@@ -1,1 -1,1 +1,5 @@@
            ++<<<<<<< HEAD

            """
        let files = GlassEditorGitDiff.parse(Data(diff.utf8))
        #expect(files.map(\.id) == ["a.txt"])
        #expect(files[0].oldPath == "a.txt")
    }

    // MARK: Conflicts

    @Test func conflictsAreReadWithTheirSidesAndWrittenBackAsChosen() {
        let text = "start\n<<<<<<< HEAD\nours 1\nours 2\n||||||| base\nbase\n=======\ntheirs\n>>>>>>> feature\nmiddle\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> feature\nend\n"
        let file = GlassEditorConflictFile.parse(text)
        #expect(file.conflicts.count == 2)
        #expect(file.conflicts[0].ours == ["ours 1", "ours 2"] && file.conflicts[0].base == ["base"]
                && file.conflicts[0].theirs == ["theirs"])
        #expect(file.conflicts[0].oursLabel == "HEAD" && file.conflicts[0].theirsLabel == "feature")
        #expect(file.conflicts[1].base == nil)
        #expect(file.resolved([0: .theirs, 1: .oursThenTheirs]) == "start\ntheirs\nmiddle\na\nb\nend\n")
        #expect(file.resolved([0: .ours]).contains("<<<<<<< HEAD\na\n=======\nb\n>>>>>>> feature\n"),
                "a conflict not chosen keeps its markers")
        #expect(GlassEditorConflictFile.parse("no markers\n").conflicts.isEmpty)
        let crlf = GlassEditorConflictFile.parse("x\r\n<<<<<<< HEAD\r\nm\r\n=======\r\nt\r\n>>>>>>> b\r\n")
        #expect(crlf.resolved([0: .theirs]) == "x\r\nt\r\n", "the file's line endings are kept")
    }

    // MARK: Another machine

    @Test func aCommandThatMustNotOpenAnEditorSaysSoToTheShellToo() {
        #expect(GlassEditorRemoteGit.commandLine(GlassEditorGitCommand.merge("feature"), in: "/srv/app")
            .hasPrefix("env GIT_EDITOR=true git -C /srv/app "))
        #expect(!GlassEditorRemoteGit.commandLine(GlassEditorGitCommand.status, in: "/srv/app").contains("GIT_EDITOR"))
    }

    #if os(macOS)
    /// The format the remote runner sends a patch in, given to the real `/usr/bin/printf`: every
    /// byte comes back as it went.
    @Test func aPatchSentToAnotherMachineArrivesByteForByte() throws {
        let input = Data("diff 'a' %d \\n \"q\" café\ttab\n\u{1}\n".utf8)
        let format = GlassEditorRemoteGit.printfFormat(input)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "/usr/bin/printf " + format]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(output == input)
    }
    #endif
}
