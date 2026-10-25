#if os(macOS)
import Foundation
import os
import Testing
@testable import GlassTerminal

/// The background process local terminals run in (D66): it hosts tmux, which ends with its last
/// session, and the host with it. Live tests use a private server: a socket of their own and no
/// configuration (rule 63).
@Suite("Local tmux host", .serialized)
nonisolated struct MacTmuxHostTests {
    @Test("only the app started as host runs as one: the flag, then tmux's full path, then a test's server arguments")
    func request() {
        #expect(MacTmuxHost.request(["app"]) == nil)
        #expect(MacTmuxHost.request(["app", "--tmux-host"]) == nil)
        #expect(MacTmuxHost.request(["app", "--other", "/t"]) == nil)
        #expect(MacTmuxHost.request(["app", "--tmux-host", "tmux"]) == nil, "a path, never a name looked up")
        let plain = MacTmuxHost.request(["app", "--tmux-host", "/opt/homebrew/bin/tmux"])
        #expect(plain?.tmux == "/opt/homebrew/bin/tmux" && plain?.serverArguments == [])
        #expect(MacTmuxHost.request(["app", "--tmux-host", "/t", "-S", "/tmp/s"])?.serverArguments == ["-S", "/tmp/s"])
    }

    /// 2026-10-24: a program the app starts from a thread other than the main one began with that
    /// thread's blocked signals — SIGINT, SIGHUP, SIGTERM and SIGCHLD among them — and a tmux server
    /// started so ignored `kill-server`. A shell that interrupts itself shows it: blocked, it lives
    /// to say so; as a new process should, it is ended.
    @Test("a program the app starts off the main thread gets its signals, as a new process does")
    func signalsReachWhatTheAppStarts() async {
        let interrupted = await Task.detached {
            MacLocalTmux.run("/bin/sh", ["-c", "kill -INT $$; echo survived"])
        }.value
        #expect(interrupted == nil, "the shell lived through its own SIGINT: \(interrupted ?? "")")
        #expect(await Task.detached { MacLocalTmux.run("/bin/sh", ["-c", "echo ran"]) }.value == "ran\n",
                "and a program that isn't interrupted runs as before")
    }

    @Test("its exit status is tmux's, or 128 and the signal that ended it")
    func exitStatus() {
        #expect(MacTmuxHost.exitStatus(0) == 0)
        #expect(MacTmuxHost.exitStatus(1 << 8) == 1)
        #expect(MacTmuxHost.exitStatus(9) == 137)
    }

    /// `serve` on a thread of its own, as the host's main thread runs it.
    private final class Serving: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private let result = OSAllocatedUnfairLock<Int32?>(initialState: nil)

        init(tmux: String, server: [String], firstSessionWait: Duration) {
            Thread.detachNewThread { [self] in
                let status = MacTmuxHost.serve(tmux: tmux, serverArguments: server, firstSessionWait: firstSessionWait,
                                               poll: .milliseconds(50))
                result.withLock { $0 = status }
                done.signal()
            }
        }

        func status(within seconds: Double) -> Int32? {
            done.wait(timeout: .now() + seconds) == .success ? result.withLock { $0 } : nil
        }
    }

    private func privateServer(_ tmux: String) throws -> (folder: String, server: [String]) {
        let folder = "/tmp/gpt-host-\(UUID().uuidString.prefix(8).lowercased())"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        return (folder, ["-S", folder + "/s", "-f", "/dev/null"])
    }

    private func until(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }

    @Test("the server ends with its last session, and the host with it: -D left exit-empty off, the host turns it on",
          .enabled(if: MacTmuxServiceTests.tmux != nil))
    func endsWithLastSession() throws {
        let tmux = try #require(MacTmuxServiceTests.tmux)
        let (folder, server) = try privateServer(tmux)
        defer {
            _ = MacLocalTmux.run(tmux, server + ["kill-server"])
            try? FileManager.default.removeItem(atPath: folder)
        }
        let serving = Serving(tmux: tmux, server: server, firstSessionWait: .seconds(30))
        #expect(until(seconds: 3) { MacTmuxService.serverRunning(tmux: tmux, serverArguments: server) })
        #expect(serving.status(within: 0.3) == nil, "an empty server waits for its first session")
        #expect(MacLocalTmux.run(tmux, server + ["new-session", "-d", "-s", "a", "/bin/sleep", "600"]) != nil)
        #expect(MacLocalTmux.run(tmux, server + ["new-session", "-d", "-s", "b", "/bin/sleep", "600"]) != nil)
        #expect(until(seconds: 3) {
            MacLocalTmux.run(tmux, server + ["show-options", "-gv", "exit-empty"])?.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        })
        #expect(MacLocalTmux.run(tmux, server + ["kill-session", "-t", "=a"]) != nil)
        #expect(serving.status(within: 0.5) == nil, "one session left: still running")
        #expect(MacLocalTmux.run(tmux, server + ["kill-session", "-t", "=b"]) != nil)
        #expect(serving.status(within: 3) == 0, "the last session ended: tmux, then the host, ended")
        #expect(!MacTmuxService.serverRunning(tmux: tmux, serverArguments: server))
    }

    @Test("a server given no session is ended, and the host with it", .enabled(if: MacTmuxServiceTests.tmux != nil))
    func endsWithoutSessions() throws {
        let tmux = try #require(MacTmuxServiceTests.tmux)
        let (folder, server) = try privateServer(tmux)
        defer {
            _ = MacLocalTmux.run(tmux, server + ["kill-server"])
            try? FileManager.default.removeItem(atPath: folder)
        }
        let serving = Serving(tmux: tmux, server: server, firstSessionWait: .milliseconds(300))
        #expect(serving.status(within: 5) != nil)
        #expect(!MacTmuxService.serverRunning(tmux: tmux, serverArguments: server))
    }
}
#endif
