import Foundation
import Testing
@testable import GlassTerminal
import GlassTerminalEmulator

/// Type-ahead's programs on the machine (D102, 2026-11-06, the owner: "Yes, add PATH"): command names from the
/// usual PATH folders, `/etc/paths` and `/etc/paths.d`, and the shell's own, for the word in a command's place.
@MainActor
@Suite("Type-ahead: the programs on the machine")
struct TypeAheadCommandsTests {
    /// A machine's folders: each folder's entries (a trailing "/" makes one a folder) and its small files.
    private struct Machine: TerminalFolderReader {
        var folders: [String: [String]] = [:]
        var files: [String: String] = [:]
        func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]? {
            folders[folder].map { names in
                names.prefix(limit).map { TerminalFolderEntry(name: $0.hasSuffix("/") ? String($0.dropLast()) : $0,
                                                              isFolder: $0.hasSuffix("/")) }
            }
        }
        func read(_ path: String, maxBytes: Int) async -> Data? { files[path].map { Data($0.utf8) } }
        func exists(_ path: String) async -> Bool { folders[path] != nil || files[path] != nil }
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("a command's place: the line's first word, after a separator, a variable set for it, or sudo and the like")
    func commandPlace() {
        for base in ["", "  ", "ls | ", "make && ", "a || ", "cd x; ", "(", "sudo ", "sudo -E ", "FOO=1 ", "FOO=1 sudo ",
                     "time nohup ", "env "] where base != "sudo -E " {
            #expect(TerminalTypeAheadCommands.isCommandPlace(base), "\"\(base)\"")
        }
        for base in ["git ", "cd ", "ls -la ", "make && git ", "sudo -E ", "=x ", "1A=2 ", "echo FOO=1 "] {
            #expect(!TerminalTypeAheadCommands.isCommandPlace(base), "\"\(base)\"")
        }
    }

    @Test("read: the usual folders' programs, the folders /etc/paths and /etc/paths.d add, the home's own, the shell's; not folders, hidden names or spaces")
    func read() async {
        let machine = Machine(
            folders: ["/usr/bin": ["ls", "git", "zip", "share/", ".hidden", "odd name"],
                      "/opt/homebrew/bin": ["tmux", "git"],
                      "/etc/paths.d": ["10-extra", "skip/"],
                      "/opt/extra/bin": ["extra-tool"],
                      "/opt/listed/bin": ["listed-tool"],
                      "/Users/ann/.local/bin": ["mine"],
                      ".local/bin": ["server-own"]],
            files: ["/etc/paths": "/usr/bin\n/opt/listed/bin\n\nnot-absolute\n",
                    "/etc/paths.d/10-extra": "  /opt/extra/bin  \n"])
        let mac = await TerminalTypeAheadCommands.read(with: machine, home: "/Users/ann")
        for name in ["ls", "git", "zip", "tmux", "extra-tool", "listed-tool", "mine", "cd", "export"] {
            #expect(mac.contains(name), "\(name)")
        }
        for name in ["share", ".hidden", "odd name", "server-own", "skip"] { #expect(!mac.contains(name), "\(name)") }
        #expect(mac == mac.sorted() && Set(mac).count == mac.count, "sorted, each once")

        // A server's SFTP paths start in its home folder.
        let server = await TerminalTypeAheadCommands.read(with: machine, home: "")
        #expect(server.contains("server-own"))
        #expect(!server.contains("mine"))
    }

    @Test("offered only in a command's place and once something is typed; read once per machine; a known tool first")
    func words() async {
        var reads = 0
        struct Counting: TerminalFolderReader {
            let machine: Machine
            let counted: @Sendable () -> Void
            func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]? {
                if folder == "/usr/bin" { counted() }
                return await machine.list(folder, limit: limit)
            }
            func read(_ path: String, maxBytes: Int) async -> Data? { await machine.read(path, maxBytes: maxBytes) }
            func exists(_ path: String) async -> Bool { await machine.exists(path) }
        }
        let counter = Counter()
        let reader = Counting(machine: Machine(folders: ["/usr/bin": ["docker", "docker-compose", "dockerd", "git"]]),
                              counted: { counter.add() })
        let id = "commands-\(UUID().uuidString)"
        let source = TerminalTypeAheadCommands(machine: id, reader: reader, home: "")
        var loaded = 0
        source.onLoaded = { loaded += 1 }
        #expect(source.words(line: "doc").isEmpty, "nothing until read")
        #expect(await waitFor(seconds: 5) { loaded == 1 })

        let offered = source.words(line: "doc")
        #expect(Set(offered.map(\.word)) == ["docker", "docker-compose", "dockerd"])
        let docker = offered.first { $0.word == "docker" }?.score ?? 0
        #expect(docker > (offered.first { $0.word == "dockerd" }?.score ?? 1), "docker is a tool the app knows")
        #expect(source.words(line: "sudo doc").count == 3)
        #expect(source.words(line: "git doc").isEmpty, "an argument, not a command")
        #expect(source.words(line: "sudo ").isEmpty, "nothing typed yet")
        #expect(source.words(line: "").isEmpty)

        // Another terminal on the same machine: what was read already.
        let again = TerminalTypeAheadCommands(machine: id, reader: reader, home: "")
        #expect(again.words(line: "gi").map(\.word) == ["git"])
        reads = counter.value
        #expect(reads == 1, "read once: \(reads)")
    }

    @Test("through the engine: a program completes the line, and a command run outranks it")
    func ranking() async {
        let reader = Machine(folders: ["/usr/bin": ["docker", "dockerd"]])
        let source = TerminalTypeAheadCommands(machine: "commands-\(UUID().uuidString)", reader: reader, home: "")
        _ = source.words(line: "d")
        #expect(await waitFor(seconds: 5) { !source.words(line: "d").isEmpty })
        let programs = TerminalTypeAheadEngine.wordCandidates(typed: "dock", words: source.words(line: "dock"), source: .commands)
        #expect(TerminalTypeAheadEngine.choose(typed: "dock", candidates: programs).best?.command == "docker")
        let run = TerminalTypeAheadCandidate(command: "docker compose up -d", score: 1.2, source: .history)
        #expect(TerminalTypeAheadEngine.choose(typed: "dock", candidates: programs + [run]).best?.command == "docker compose up -d")
    }

    /// "Every part exists and nothing joins them" (the project's recurring defect; type-ahead was attached to one of a
    /// terminal's two engines only, 2026-11-06). Each kind of terminal gets every word source, from one function each.
    @Test("every word source is attached to a terminal on this Mac and to a server's")
    func everySourceAttached() throws {
        let wordKinds = Set(TerminalTypeAheadSource.allCases).subtracting([.history, .imported, .snippet, .assistant])
        let defaults = try #require(UserDefaults(suiteName: "commands-\(UUID().uuidString)"))
        let local = TerminalTypeAheadController.attach(to: SwiftTermHostModel(), machine: "mac", folder: { nil },
                                                       snippets: { [] }, history: TerminalCommandHistory(folder: nil),
                                                       defaults: defaults)
        local.addThisMacSources(servers: { [] }, home: NSTemporaryDirectory())
        #expect(Set(local.wordSources.map(\.source)) == wordKinds)
        let server = TerminalTypeAheadController.attach(to: SwiftTermHostModel(), machine: "server", folder: { nil },
                                                        snippets: { [] }, history: TerminalCommandHistory(folder: nil),
                                                        defaults: defaults)
        server.addServerSources(servers: { [] }, reader: Machine())
        #expect(Set(server.wordSources.map(\.source)) == wordKinds)
    }

    /// `~` in a typed path is the home a terminal on this Mac is given (the owner's `cd ~/Software/gl`, 2026-11-07).
    @Test("a terminal on this Mac completes ~/ from the home it is given")
    func macHome() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("commands-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Software/glass"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let defaults = try #require(UserDefaults(suiteName: "commands-\(UUID().uuidString)"))
        let controller = TerminalTypeAheadController.attach(to: SwiftTermHostModel(), machine: "mac-home", folder: { nil },
                                                            snippets: { [] }, history: TerminalCommandHistory(folder: nil),
                                                            defaults: defaults)
        controller.addThisMacSources(servers: nil, home: home.path)
        let folderWords = try #require(controller.wordSources.first { $0.source == .folder }?.words)
        _ = folderWords("cd ~/Software/gl")
        #expect(await waitFor(seconds: 5) { folderWords("cd ~/Software/gl").map(\.word) == ["~/Software/glass/"] },
                "\(folderWords("cd ~/Software/gl"))")
    }

    #if os(macOS)
    /// This Mac's own folders, read as a terminal here reads them; the home folder is one of the test's, so nothing of
    /// the person's is listed.
    @Test("this Mac: the system's programs and the shell's own are there")
    func thisMac() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("commands-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data().write(to: home.appendingPathComponent(".local/bin/my-own-tool"))
        let names = await TerminalTypeAheadCommands.read(with: TerminalLocalFolderReader(), home: home.path)
        for name in ["ls", "git", "ssh", "zsh", "cd", "my-own-tool"] { #expect(names.contains(name), "\(name)") }
    }
    #endif
}

/// A count a `Sendable` closure can add to.
private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
