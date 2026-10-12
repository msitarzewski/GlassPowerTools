#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import GlassTerminal

/// Open Folder Here on a local pane (2026-10-08): the folder tmux or the shell is in, or a plain
/// message. With tmux on, the button opened Home: when tmux did not answer, the pane fell back to
/// the tmux client's folder, which is where the session started.
@Suite("Open Folder Here on a local pane")
struct MacLocalShellFolderTests {
    /// What the resolver asked tmux, and on which thread.
    nonisolated final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var _sessions: [String] = []
        private var _onMainThread: [Bool] = []
        var sessions: [String] { lock.withLock { _sessions } }
        var onMainThread: [Bool] { lock.withLock { _onMainThread } }
        func record(_ session: String) {
            let onMain = Thread.isMainThread
            lock.withLock {
                _sessions.append(session)
                _onMainThread.append(onMain)
            }
        }
    }

    /// A tmux that answers `answer`, and a disk on which only `folders` exist.
    private func lookups(tmux answer: String?, folders: Set<String>, asked: Asked = Asked()) -> MacLocalShellFolder.Lookups {
        MacLocalShellFolder.Lookups(
            tmuxDirectory: { session in
                asked.record(session)
                return answer
            },
            isFolder: { folders.contains($0) }
        )
    }

    /// Where a tmux client started: Home, as the session's `-c` folder usually is.
    private let clientFolder = FileManager.default.homeDirectoryForCurrentUser.path

    /// A folder of the test's own, removed afterwards.
    private func scratchFolder() throws -> String {
        let path = NSTemporaryDirectory() + "MacLocalShellFolderTests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test("in tmux, the folder is tmux's answer, and the client's folder is never read")
    func tmuxAnswers() async {
        let asked = Asked()
        var readProcess = false
        let folder = await MacLocalShellFolder.resolve(
            tmuxSession: "glass-3", shellIsRunning: true,
            processDirectory: { readProcess = true; return clientFolder },
            lookups: lookups(tmux: "/tmp/project", folders: ["/tmp/project", clientFolder], asked: asked)
        )
        #expect(folder == .folder("/tmp/project"))
        #expect(asked.sessions == ["glass-3"])
        #expect(!readProcess)
    }

    @Test("in tmux, no answer is unknown: never the client's folder, never Home")
    func tmuxFails() async {
        // Nothing, nothing usable, and a reply that is not a path.
        for answer in [nil, "", "glass-1_1_1"] as [String?] {
            for running in [true, false] {
                let folder = await MacLocalShellFolder.resolve(
                    tmuxSession: "glass-1", shellIsRunning: running,
                    processDirectory: { clientFolder },
                    lookups: lookups(tmux: answer, folders: [clientFolder])
                )
                #expect(folder == .unknown, "tmux answered \(String(describing: answer)), client running: \(running)")
            }
        }
    }

    @Test("a folder deleted since the shell went there is missing, and the pane says so")
    func deletedFolder() async throws {
        let base = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let path = base + "/build output"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        let onDisk = MacLocalShellFolder.Lookups(tmuxDirectory: { _ in path }, isFolder: MacLocalShellFolder.Lookups.folderExists)

        let before = await MacLocalShellFolder.resolve(tmuxSession: "glass-2", shellIsRunning: true,
                                                       processDirectory: { nil }, lookups: onDisk)
        #expect(before == .folder(path))

        try FileManager.default.removeItem(atPath: path)
        let inTmux = await MacLocalShellFolder.resolve(tmuxSession: "glass-2", shellIsRunning: true,
                                                       processDirectory: { nil }, lookups: onDisk)
        let plain = await MacLocalShellFolder.resolve(tmuxSession: nil, shellIsRunning: true,
                                                      processDirectory: { path }, lookups: onDisk)
        #expect(inTmux == .missing(path))
        #expect(plain == .missing(path))

        var opened: [URL] = []
        let problem = MacLocalShellFolder.open(inTmux) { opened.append($0); return true }
        #expect(opened.isEmpty)
        #expect(problem?.message.contains("build output") == true)
    }

    @Test("without tmux, the folder is the shell process's own, and tmux is not asked")
    func plainShell() async {
        let asked = Asked()
        let folder = await MacLocalShellFolder.resolve(
            tmuxSession: nil, shellIsRunning: true,
            processDirectory: { "/tmp/plain" },
            lookups: lookups(tmux: "/tmp/elsewhere", folders: ["/tmp/plain", "/tmp/elsewhere"], asked: asked)
        )
        #expect(folder == .folder("/tmp/plain"))
        #expect(asked.sessions.isEmpty)

        let unreported = await MacLocalShellFolder.resolve(
            tmuxSession: nil, shellIsRunning: true, processDirectory: { nil },
            lookups: lookups(tmux: nil, folders: [clientFolder])
        )
        #expect(unreported == .unknown)
    }

    @Test("a shell that has exited, outside tmux, is in no folder; a tmux session can outlive its client")
    func exitedShell() async {
        var readProcess = false
        let exited = await MacLocalShellFolder.resolve(
            tmuxSession: nil, shellIsRunning: false,
            processDirectory: { readProcess = true; return "/tmp/last" },
            lookups: lookups(tmux: nil, folders: ["/tmp/last", clientFolder])
        )
        #expect(exited == .unknown)
        #expect(!readProcess)
        // The button follows the same rule.
        #expect(!MacLocalShellFolder.isAvailable(tmuxSession: nil, shellIsRunning: false))
        #expect(MacLocalShellFolder.isAvailable(tmuxSession: nil, shellIsRunning: true))
        #expect(MacLocalShellFolder.isAvailable(tmuxSession: "glass-2", shellIsRunning: false))

        let detached = await MacLocalShellFolder.resolve(
            tmuxSession: "glass-2", shellIsRunning: false, processDirectory: { nil },
            lookups: lookups(tmux: "/tmp/still-running", folders: ["/tmp/still-running"])
        )
        #expect(detached == .folder("/tmp/still-running"))
    }

    @Test("tmux is asked off the main actor: it is a process spawn, and the window must not stall")
    func tmuxOffMain() async {
        let asked = Asked()
        _ = await MacLocalShellFolder.resolve(
            tmuxSession: "glass-1", shellIsRunning: true, processDirectory: { nil },
            lookups: lookups(tmux: "/tmp", folders: ["/tmp"], asked: asked)
        )
        #expect(asked.onMainThread == [false])
    }

    @Test("Finder is handed a folder URL for the exact folder: spaces, accents, other scripts, % # ?")
    func exactURL() async throws {
        let base = try scratchFolder()
        defer { try? FileManager.default.removeItem(atPath: base) }
        // A precomposed é, a decomposed one, and characters a URL would otherwise read as syntax.
        for name in ["Glass Folder", "caf\u{E9} r\u{E9}sum\u{E9}", "cafe\u{301}", "文件夹 📁", "100% #1 ?x"] {
            let path = base + "/" + name
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            let folder = await MacLocalShellFolder.resolve(
                tmuxSession: nil, shellIsRunning: true, processDirectory: { path },
                lookups: MacLocalShellFolder.Lookups(tmuxDirectory: { _ in nil },
                                                     isFolder: MacLocalShellFolder.Lookups.folderExists)
            )
            #expect(folder == .folder(path))

            var opened: [URL] = []
            let problem = MacLocalShellFolder.open(folder) { opened.append($0); return true }
            #expect(problem == nil)
            #expect(opened.count == 1)
            guard let url = opened.first else { continue }
            #expect(url.isFileURL)
            #expect(url.hasDirectoryPath)
            // Foundation stores a file URL's path decomposed, so the text compares canonically.
            #expect(url.path(percentEncoded: false) == path + "/", "\(name)")
            // And it reaches the very folder the shell's bytes name.
            var byPath = stat(), byURL = stat()
            #expect(path.withCString { stat($0, &byPath) } == 0)
            #expect(url.withUnsafeFileSystemRepresentation { $0.map { stat($0, &byURL) } ?? -1 } == 0)
            #expect(byPath.st_ino == byURL.st_ino, "\(name)")
        }
    }

    @Test("when Finder does not open the folder, the pane says so; nothing fails silently")
    func openerRefuses() throws {
        var opened: [URL] = []
        let refused = MacLocalShellFolder.open(.folder("/tmp/project")) { opened.append($0); return false }
        #expect(opened.count == 1)
        let shown = try #require(refused)
        #expect(!shown.title.isEmpty)
        #expect(shown.message.contains("project"))

        #expect(MacLocalShellFolder.open(.folder("/tmp/project")) { _ in true } == nil)

        var openedUnknown = false
        let unknown = MacLocalShellFolder.open(.unknown) { _ in openedUnknown = true; return true }
        #expect(unknown != nil)
        #expect(!openedUnknown)
    }
}
#endif
