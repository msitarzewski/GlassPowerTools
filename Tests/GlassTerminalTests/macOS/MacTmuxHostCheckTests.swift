#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// The host local terminals run in, after an update has replaced it (2026-11-23). An update swaps the app's
/// executable under the running host; macOS's check of the host then fails, and programs in its terminals are
/// refused folders. These compile a small program into a folder of their own, run it, and replace its file as an
/// update replaces the app: nothing of this Mac's tmux is asked or touched. (Copies of the system's own programs
/// can't stand in: macOS ends them when they run from anywhere else, status 137.)
@Suite("Local tmux host after an update", .serialized)
nonisolated struct MacTmuxHostCheckTests {
    @Test("the server's process is tmux's #{pid}, the first line that is one; no answer, no process")
    func serverPID() {
        #expect(MacTmuxHostCheck.serverPID(listing: "4812\n4812\n") == 4812)
        #expect(MacTmuxHostCheck.serverPID(listing: " 4812 \n") == 4812)
        #expect(MacTmuxHostCheck.serverPID(listing: nil) == nil)
        #expect(MacTmuxHostCheck.serverPID(listing: "") == nil)
        #expect(MacTmuxHostCheck.serverPID(listing: "no server running\n") == nil)
        #expect(MacTmuxHostCheck.serverPID(listing: "1\n") == nil, "launchd is never a tmux server")
        #expect(MacTmuxHostCheck.sessionCount(listing: "4812\n4812\n4812\n") == 3)
        #expect(MacTmuxHostCheck.sessionCount(listing: nil) == 0)
    }

    @Test("a program is intact while its file is its own, and replaced once an update-like swap puts another there")
    func codeState() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let program = try Self.compile(Self.hold, in: folder)
        let process = try Self.start(program, [])
        defer { process.terminate() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(process.isRunning)

        #expect(MacTmuxHostCheck.codeState(pid: process.processIdentifier, identifier: Self.identifier) == .intact)
        #expect(MacTmuxHostCheck.codeState(pid: process.processIdentifier, identifier: "com.glasspowertools") == nil,
                "another program's process is not ours to judge")

        try Self.replace(program, in: folder)
        #expect(MacTmuxHostCheck.codeState(pid: process.processIdentifier, identifier: Self.identifier) == .replaced)
    }

    @Test("the host is the server's parent: named once its file is replaced, and with the server's sessions")
    func replacedHost() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        // A host that starts a server and waits for it, as `MacTmuxHost.serve` does: given an argument, the
        // program starts a copy of itself and prints that one's process.
        let host = try Self.compile(Self.hold, in: folder)
        let output = Pipe()
        let process = try Self.start(host, ["host"], output: output)
        defer { process.terminate() }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        let server = try #require(pid_t(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { kill(server, SIGTERM) }
        let listing = "\(server)\n\(server)\n"

        #expect(MacTmuxHostCheck.process(server)?.parent == process.processIdentifier)
        #expect(MacTmuxHostCheck.replacedHost(listing: listing, identifier: Self.identifier) == nil, "intact")

        try Self.replace(host, in: folder)
        let found = try #require(MacTmuxHostCheck.replacedHost(listing: listing, identifier: Self.identifier))
        #expect(found.pid == process.processIdentifier)
        #expect(found.terminals == 2)
        #expect(found.started > 0 && found.key == "\(found.pid)@\(found.started)")
        #expect(MacTmuxHostCheck.replacedHost(listing: listing, identifier: "com.glasspowertools") == nil,
                "a host that isn't this app's")
        #expect(MacTmuxHostCheck.replacedHost(listing: nil, identifier: Self.identifier) == nil, "no server")
    }

    @Test("the notice says what's wrong, for which folders, and the way out, with the count")
    func notice() {
        let one = MacTmuxHostCheck.notice(terminals: 1)
        #expect(one.message.hasPrefix("Glass Power Tools was updated while 1 local terminal was running. Until it ends,"))
        #expect(one.message.contains("Ending it fixes this. Whatever is running in it stops"))
        #expect(!one.message.contains("them"), "one terminal is never \"them\"")
        #expect(one.end == "End Terminal")
        let four = MacTmuxHostCheck.notice(terminals: 4)
        #expect(four.message.contains("4 local terminals were running. Until they end,"))
        #expect(four.message.contains("your Documents, Desktop and Downloads folders"))
        #expect(four.message.contains("Ending them fixes this. Whatever is running in them stops"))
        #expect(four.end == "End 4 Terminals")
    }

    @Test("with local tmux off, or no tmux, nothing is asked")
    @MainActor func currentAsksNothingWhenOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "MacTmuxHostCheckTests-\(UUID().uuidString)"))
        var server = MacLocalTmux.Server(executablePath: { "/opt/homebrew/bin/tmux" }, listSessions: { _ in nil },
                                         kill: { _, _ in }, detachClients: { _, _ in }, scroll: { _, _, _ in })
        server.serverProcess = { _ in Issue.record("asked with local tmux off"); return nil }
        defaults.set(false, forKey: UserDefaultsKeys.localTmux)
        #expect(MacTmuxHostCheck.current(server: server, defaults: defaults, identifier: "com.glasspowertools") == nil)
        defaults.set(true, forKey: UserDefaultsKeys.localTmux)
        server.executablePath = { nil }
        #expect(MacTmuxHostCheck.current(server: server, defaults: defaults, identifier: "com.glasspowertools") == nil)
    }

    // MARK: Helpers

    static func folder() throws -> String {
        let folder = NSTemporaryDirectory() + "gpt-hostcheck-" + UUID().uuidString.prefix(8).lowercased()
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        return folder
    }

    static func start(_ executable: String, _ arguments: [String], output: Pipe? = nil) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// The program's name, which the linker's own signature takes as its identifier.
    static let identifier = "glass-hostcheck"

    /// Waits; given an argument, starts a copy of itself that waits, prints its process and waits for it.
    static let hold = """
        #include <stdio.h>
        #include <unistd.h>
        #include <sys/wait.h>
        int main(int argc, char **argv) {
            if (argc > 1) {
                pid_t child = fork();
                if (child == 0) { sleep(30); return 0; }
                printf("%d\\n", child);
                fflush(stdout);
                waitpid(child, 0, 0);
                return 0;
            }
            sleep(30);
            return 0;
        }
        """

    /// Builds `source` as `identifier` in a folder of its own inside `folder`; the linker signs it.
    static func compile(_ source: String, in folder: String, as name: String = "build") throws -> String {
        let directory = folder + "/" + name
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let file = directory + "/main.c"
        try source.write(toFile: file, atomically: true, encoding: .utf8)
        let program = directory + "/" + identifier
        let compiler = try start("/usr/bin/cc", ["-o", program, file])
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0, "cc built the stand-in")
        return program
    }

    /// As an update does: another program is written beside the old, takes its name, and the old is gone.
    static func replace(_ path: String, in folder: String) throws {
        let incoming = try compile("int main(void) { return 7; }\n", in: folder, as: "update")
        #expect(rename(incoming, path) == 0)
    }
}
#endif
