import Foundation
import Testing
@testable import GlassTerminal

/// Type-ahead's folder source (D102, 2026-11-06): branches, file names, package scripts, make and just targets, read
/// from a folder the way a shell's current folder is read on this Mac.
@MainActor
@Suite("Type-ahead: the current folder")
struct TypeAheadFolderTests {
    @Test("package.json's scripts in the file's order; none from a file without them")
    func scripts() {
        let json = #"{"name":"shop","scripts":{"dev":"vite","build":"vite build","test:unit":"vitest"},"dependencies":{"vite":"5"}}"#
        #expect(TerminalTypeAheadFolder.packageScripts(Data(json.utf8)) == ["dev", "build", "test:unit"])
        #expect(TerminalTypeAheadFolder.packageScripts(Data(#"{"name":"x"}"#.utf8)).isEmpty)
        #expect(TerminalTypeAheadFolder.packageScripts(Data("not json".utf8)).isEmpty)
    }

    @Test("Makefile targets: not variables, patterns, special targets or recipe lines")
    func makeTargets() {
        let makefile = """
        CC := clang
        PREFIX = /usr/local
        .PHONY: all clean
        all: build test
        build: main.o
        \tcc -o app main.o
        %.o: %.c
        \t$(CC) -c $<
        test check: build
        # deploy: comment
        install:
        \tcp app $(PREFIX)/bin
        """
        #expect(TerminalTypeAheadFolder.makeTargets(makefile) == ["all", "build", "test", "check", "install"])
    }

    @Test("justfile recipes: not settings, assignments or private ones")
    func justRecipes() {
        let justfile = """
        set shell := ["bash", "-c"]
        version := "1.0"
        default:
            just --list
        build target="debug":
            cargo build
        @deploy env:
            ./deploy {{env}}
        _helper:
            echo hi
        alias b := build
        """
        #expect(TerminalTypeAheadFolder.justRecipes(justfile) == ["default", "build", "deploy"])
    }

    @Test("git: remotes from the config; branches loose and packed, remote ones as remote/branch")
    func git() {
        let config = """
        [core]
        \tbare = false
        [remote "origin"]
        \turl = https://example.com/shop.git
        [remote "upstream"]
        \turl = https://example.com/up.git
        [branch "main"]
        """
        #expect(TerminalTypeAheadFolder.gitRemotes(config) == ["origin", "upstream"])
        let packed = """
        # pack-refs with: peeled fully-peeled sorted
        1111111111111111111111111111111111111111 refs/heads/release/1.0
        2222222222222222222222222222222222222222 refs/remotes/origin/HEAD
        3333333333333333333333333333333333333333 refs/remotes/origin/main
        4444444444444444444444444444444444444444 refs/tags/v1.0
        ^5555555555555555555555555555555555555555
        """
        let found = TerminalTypeAheadFolder.packedBranches(packed)
        #expect(found.local == ["release/1.0"] && found.remote == ["origin/main"])
    }

    @Test("a name the shell would split is escaped")
    func shellWords() {
        #expect(TerminalTypeAheadFolder.shellWord("My Notes (old).txt") == "My\\ Notes\\ \\(old\\).txt")
        #expect(TerminalTypeAheadFolder.shellWord("plain-name.md") == "plain-name.md")
    }

    @Test("a real folder on this Mac: entries, scripts, targets, branches from the repository above it")
    func localFolder() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("shop/web")
        let git = root.appendingPathComponent("shop/.git")
        try FileManager.default.createDirectory(at: project.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: git.appendingPathComponent("refs/heads/feature"), withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: git.appendingPathComponent("HEAD"))
        try Data("1\n".utf8).write(to: git.appendingPathComponent("refs/heads/main"))
        try Data("2\n".utf8).write(to: git.appendingPathComponent("refs/heads/feature/login"))
        try Data("[remote \"origin\"]\n\turl = x\n".utf8).write(to: git.appendingPathComponent("config"))
        try Data(#"{"scripts":{"dev":"vite"}}"#.utf8).write(to: project.appendingPathComponent("package.json"))
        try Data("serve:\n\tpython3 -m http.server\n".utf8).write(to: project.appendingPathComponent("Makefile"))
        try Data("hi".utf8).write(to: project.appendingPathComponent("read me.txt"))

        let source = TerminalTypeAheadFolder(reader: TerminalLocalFolderReader())
        var loaded = false
        source.onLoaded = { loaded = true }
        #expect(source.words(line: "git checkout ", folder: project.path, kind: .branch).isEmpty, "read in the background first")
        for _ in 0..<200 where !loaded { try await Task.sleep(for: .milliseconds(10)) }
        #expect(loaded)
        func words(_ line: String, _ kind: TerminalFolderArgument) -> [String] {
            source.words(line: line, folder: project.path, kind: kind).map(\.word)
        }
        #expect(words("git checkout ", .branch) == ["feature/login", "main"])
        #expect(words("git push ", .remote) == ["origin"])
        #expect(words("npm run ", .script) == ["dev"])
        #expect(words("make ", .target) == ["serve"])
        #expect(words("cd ", .folder) == ["src/"])
        #expect(Set(words("cat ", .file)) == ["Makefile", "package.json", "read\\ me.txt", "src/"])
    }

    /// The owner's `cd ~/Software/gl` offered nothing (2026-11-07): a word with a slash was left alone.
    @Test("a path's folder part, as a reader reads it: ~ is home (a server's SFTP starts there), relative is in the folder")
    func pathFolders() {
        #expect(TerminalTypeAheadFolder.folder(of: "~/Software/", in: "/tmp", home: "/Users/ann") == "/Users/ann/Software/")
        #expect(TerminalTypeAheadFolder.folder(of: "~/", in: nil, home: "/Users/ann") == "/Users/ann/")
        #expect(TerminalTypeAheadFolder.folder(of: "~/Software/", in: nil, home: "") == "Software/")
        #expect(TerminalTypeAheadFolder.folder(of: "~/", in: nil, home: "") == ".")
        #expect(TerminalTypeAheadFolder.folder(of: "/usr/local/", in: nil, home: "") == "/usr/local/")
        #expect(TerminalTypeAheadFolder.folder(of: "src/lib/", in: "/srv/shop", home: "") == "/srv/shop/src/lib/")
        #expect(TerminalTypeAheadFolder.folder(of: "../", in: "/srv/shop", home: "") == "/srv/shop/../")
        #expect(TerminalTypeAheadFolder.folder(of: "My\\ Notes/", in: "/srv", home: "") == "/srv/My Notes/")
        #expect(TerminalTypeAheadFolder.folder(of: "src/", in: nil, home: "/Users/ann") == nil, "relative, no folder")
        #expect(TerminalTypeAheadFolder.folder(of: "~ann/", in: "/srv", home: "/Users/ann") == nil)
        #expect(TerminalTypeAheadFolder.folder(of: "\"My Notes/", in: "/srv", home: "") == nil)
    }

    @Test("a hidden name only once its dot is typed; cd takes folders, with their slash")
    func hiddenNames() {
        let entries = [TerminalFolderEntry(name: ".git", isFolder: true), TerminalFolderEntry(name: ".env", isFolder: false),
                       TerminalFolderEntry(name: "src", isFolder: true), TerminalFolderEntry(name: "a b.txt", isFolder: false)]
        #expect(TerminalTypeAheadFolder.names(entries, kind: .folder, typed: "").map(\.word) == ["src/"])
        #expect(TerminalTypeAheadFolder.names(entries, kind: .folder, typed: ".").map(\.word) == [".git/", "src/"],
                "what is typed narrows them later (the engine)")
        #expect(TerminalTypeAheadFolder.names(entries, kind: .file, typed: "").map(\.word) == ["src/", "a\\ b.txt"])
        #expect(TerminalTypeAheadFolder.names(entries, kind: .file, typed: ".g").map(\.word) == [".git/", ".env", "src/", "a\\ b.txt"])
    }

    @Test("a typed path on this Mac: ~/, absolute and relative, the folder it names read and its names offered")
    func localPaths() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("typeahead-paths-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Software/glass", "Software/gleam", "Software/notes", "Software/.hidden", "here/src/lib"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("Software/glossary.txt"))
        let source = TerminalTypeAheadFolder(reader: TerminalLocalFolderReader(), home: root.path)
        var loads = 0
        source.onLoaded = { loads += 1 }
        func words(_ line: String, _ kind: TerminalFolderArgument) async -> [String] {
            let first = source.words(line: line, folder: root.appendingPathComponent("here").path, kind: kind)
            if !first.isEmpty { return first.map(\.word) }
            let before = loads
            for _ in 0..<200 where loads == before { try? await Task.sleep(for: .milliseconds(10)) }
            return source.words(line: line, folder: root.appendingPathComponent("here").path, kind: kind).map(\.word)
        }
        // The owner's line: folders under ~/Software, as typed, each with its slash.
        let offered = await words("cd ~/Software/gl", .folder)
        #expect(Set(offered) == ["~/Software/glass/", "~/Software/gleam/", "~/Software/notes/"], "\(offered)")
        let chosen = TerminalTypeAheadEngine.choose(
            typed: "cd ~/Software/gl",
            candidates: TerminalTypeAheadEngine.wordCandidates(
                typed: "cd ~/Software/gl", words: source.words(line: "cd ~/Software/gl", folder: nil, kind: .folder), source: .folder))
        #expect(chosen.best?.command == "cd ~/Software/glass/")
        #expect(Set(await words("cat ~/Software/glo", .file)).contains("~/Software/glossary.txt"))
        #expect(await words("cd " + root.path + "/Software/no", .folder) == [root.path + "/Software/glass/", root.path + "/Software/gleam/",
                                                                         root.path + "/Software/notes/"])
        #expect(await words("cd src/", .folder) == ["src/lib/"], "relative to the folder the shell is in")
    }
}
