import Foundation
import Testing
@testable import GlassTerminal

/// Type-ahead's kept commands (D102, 2026-11-06): what is kept per machine and what never is, how a machine's own
/// history comes in, and that it all stays in this device's file.
@MainActor
@Suite("Type-ahead: the commands kept per machine")
struct TypeAheadHistoryTests {
    private func store() -> (TerminalCommandHistory, URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("history-\(UUID().uuidString)")
        return (TerminalCommandHistory(folder: folder), folder)
    }

    @Test("a command run is kept with its folder and what ran before it; again counts up")
    func record() {
        let (history, folder) = store()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(history.record("git status", machine: "alpha", folder: "/srv/shop"))
        #expect(history.record("git push", machine: "alpha", folder: "/srv/shop"))
        #expect(history.record("git status", machine: "alpha", folder: "/srv/blog"))
        let records = Dictionary(uniqueKeysWithValues: history.records(for: "alpha").map { ($0.command, $0) })
        #expect(records["git status"]?.count == 2)
        #expect(records["git status"]?.folders == ["/srv/shop": 1, "/srv/blog": 1])
        #expect(records["git push"]?.after == ["git status": 1])
        #expect(history.records(for: "bravo").isEmpty, "another machine's are its own")
        history.finish(machine: "alpha", status: 1)
        #expect(history.records(for: "alpha").first { $0.command == "git status" }?.lastStatus == 1)
    }

    @Test("never kept: a leading space, a secret, a blank line")
    func neverKept() {
        let (history, folder) = store()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!history.record(" ls -la", machine: "alpha", folder: nil), "a space first: the shells' own sign")
        #expect(!history.record(" mysql -u root -phunter2", machine: "alpha", folder: nil))
        #expect(!history.record("export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", machine: "alpha", folder: nil))
        #expect(!history.record("curl -H 'Authorization: Bearer abc' https://example.com", machine: "alpha", folder: nil))
        #expect(!history.record("   ", machine: "alpha", folder: nil))
        #expect(history.records(for: "alpha").isEmpty)
    }

    @Test("kept in this device's file and read back; Forget removes a machine's, Forget Everything all of them")
    func persistence() throws {
        let (history, folder) = store()
        defer { try? FileManager.default.removeItem(at: folder) }
        history.record("make test", machine: "alpha", folder: "/srv")
        history.record("ls", machine: "bravo", folder: nil)
        history.saveNow()
        let file = try #require(history.fileURL(for: "alpha"))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        let reopened = TerminalCommandHistory(folder: folder)
        #expect(reopened.records(for: "alpha").map(\.command) == ["make test"])
        reopened.forgetAll(machine: "alpha")
        reopened.saveNow()
        #expect(!FileManager.default.fileExists(atPath: file.path), "a machine with nothing kept has no file")
        #expect(TerminalCommandHistory(folder: folder).records(for: "bravo").map(\.command) == ["ls"])
        reopened.forgetEverything()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("at most the limit per machine: the least used and oldest go")
    func limit() {
        var table: [String: TerminalCommandRecord] = [:]
        let now = Date()
        for index in 0..<(TerminalCommandHistory.limit + 10) {
            table["cmd \(index)"] = TerminalCommandRecord(command: "cmd \(index)", count: index < 5 ? 3 : 1,
                                                          lastUsed: now.addingTimeInterval(Double(index)))
        }
        let trimmed = TerminalCommandHistory.trimmed(table)
        #expect(trimmed.count == TerminalCommandHistory.limit)
        #expect(trimmed["cmd 0"] != nil, "used three times: kept though oldest")
        #expect(trimmed["cmd 5"] == nil && trimmed["cmd 14"] == nil, "used once and oldest: gone")
    }

    // MARK: - Importing a machine's own history

    private struct Files: TerminalFolderReader {
        var files: [String: String]
        func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]? { nil }
        func read(_ path: String, maxBytes: Int) async -> Data? { files[path].map { Data($0.utf8) } }
        func exists(_ path: String) async -> Bool { files[path] != nil }
    }

    @Test("zsh's and fish's files read, in time order, through the same filter; seen commands keep their counts")
    func importing() async {
        let (history, folder) = store()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = Files(files: [
            "/home/ann/.zsh_history": ": 1700000100:0;git status\n: 1700000200:0;export API_TOKEN=abc123secret\n: 1700000300:0;make test\n",
            "/home/ann/.local/share/fish/fish_history": "- cmd: cargo build\n  when: 1700000250\n",
        ])
        history.record("make test", machine: "alpha", folder: nil)
        let added = await TerminalHistoryImport.importHistory(into: history, machine: "alpha", reader: reader,
                                                              home: "/home/ann")
        #expect(added == 2, "git status and cargo build; make test was kept already, the token never")
        let records = Dictionary(uniqueKeysWithValues: history.records(for: "alpha").map { ($0.command, $0) })
        #expect(records["git status"]?.imported == true && records["cargo build"]?.imported == true)
        #expect(records["make test"]?.imported == false && records["make test"]?.count == 1, "seen here, not counted again")
        #expect(records.keys.allSatisfy { !$0.contains("TOKEN") })
        #expect(records["cargo build"]!.lastUsed > records["git status"]!.lastUsed)
    }
}
