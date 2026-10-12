#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// This Mac's tmux server under launchd (2026-10-12): a Force Quit of an app started inside a
/// session ended every local terminal, since a server an app starts is that app's to end.
@Suite("Local tmux under launchd", .serialized)
struct MacTmuxServiceTests {
    static let host = "/Applications/Glass Power Tools.app/Contents/MacOS/Glass Power Tools"

    @Test("the job runs the app as the host of tmux, at a terminal's priority, with the pane's environment less launchd's own")
    func job() throws {
        let job = MacTmuxService.job(host: Self.host, tmux: "/opt/homebrew/bin/tmux",
                                     environment: ["PATH": "/opt/homebrew/bin:/usr/bin", "LANG": "en_US.UTF-8",
                                                   "SSH_AUTH_SOCK": "/private/tmp/stale", "TMPDIR": "/var/folders/stale"])
        #expect(job["Label"] as? String == "com.glasspowertools.tmux")
        #expect(job["ProgramArguments"] as? [String] == [Self.host, "--tmux-host", "/opt/homebrew/bin/tmux"],
                "the app's own executable, so a terminal's programs answer to Glass Power Tools")
        #expect(job["EnvironmentVariables"] as? [String: String] == ["PATH": "/opt/homebrew/bin:/usr/bin", "LANG": "en_US.UTF-8"],
                "the agent socket and temporary folder are launchd's, current for this login")
        #expect(job["ProcessType"] as? String == "Interactive" && job["KeepAlive"] as? Bool == false)
        #expect(job["RunAtLoad"] as? Bool == true && job["AbandonProcessGroup"] as? Bool == true)
        #expect(MacTmuxService.jobURL()?.path.contains("/Library/LaunchAgents/") == false, "no login item")
        let test = MacTmuxService.job(label: "t", host: "/h", tmux: "/t", environment: [:], serverArguments: ["-S", "/tmp/s"])
        #expect(test["ProgramArguments"] as? [String] == ["/h", "--tmux-host", "/t", "-S", "/tmp/s"])
        #expect(MacTmuxService.appExecutable() == nil, "a test runner is no app: it never hosts this Mac's tmux")
    }

    private final class Calls: @unchecked Sendable {
        let lock = NSLock()
        var list: [[String]] = []
        var serverAnswersAfter = Int.max
        var bootstrapFails = false
        func run(_ executable: String, _ arguments: [String]) -> String? {
            lock.withLock {
                list.append([executable] + arguments)
                if arguments.contains("-N") {
                    serverAnswersAfter -= 1
                    return serverAnswersAfter < 0 ? "" : nil
                }
                if arguments.first == "bootstrap" { return bootstrapFails ? nil : "" }
                return nil
            }
        }
    }

    @Test("a running server is left alone; none is started under launchd, which is asked to drop a stale job first")
    func ensure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-tmuxjob-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let jobURL = folder.appendingPathComponent("job.plist")

        let running = Calls()
        running.serverAnswersAfter = 0
        #expect(MacTmuxService.ensureServer(host: Self.host, tmux: "tmux", environment: [:], jobURL: jobURL, run: running.run, wait: { _ in }) == .alreadyRunning)
        #expect(running.list == [["tmux", "-N", "list-sessions"]])
        #expect(!FileManager.default.fileExists(atPath: jobURL.path), "nothing written")

        let starting = Calls()
        starting.serverAnswersAfter = 3
        #expect(MacTmuxService.ensureServer(host: Self.host, tmux: "tmux", environment: ["LANG": "C"], jobURL: jobURL, run: starting.run, wait: { _ in }) == .started)
        let launchctl = starting.list.filter { $0.first == "/bin/launchctl" }.map { Array($0.dropFirst()) }
        #expect(launchctl.map(\.first) == ["bootout", "bootstrap"], "out first, so the new environment runs")
        #expect(launchctl.last?.last == jobURL.path)
        let written = try #require(NSDictionary(contentsOf: jobURL) as? [String: Any])
        #expect(written["EnvironmentVariables"] as? [String: String] == ["LANG": "C"])

        let refused = Calls()
        refused.bootstrapFails = true
        #expect(MacTmuxService.ensureServer(host: Self.host, tmux: "tmux", environment: [:], jobURL: jobURL, run: refused.run, wait: { _ in }) == .couldNotStart,
                "the claim then starts tmux itself, as before")

        let silent = Calls()
        var waited: Duration = .zero
        #expect(MacTmuxService.ensureServer(host: Self.host, tmux: "tmux", environment: [:], jobURL: jobURL, run: silent.run, wait: { waited += $0 }) == .couldNotStart)
        #expect(waited >= MacTmuxService.startTimeout)
    }

    @Test("ending the server from Settings ends tmux, then takes the job out")
    func stop() {
        let calls = Calls()
        MacTmuxService.stopServer(tmux: "/t", label: "l", serverArguments: ["-S", "/tmp/s"], run: calls.run)
        #expect(calls.list == [["/t", "-S", "/tmp/s", "kill-server"], ["/bin/launchctl", "bootout", "gui/\(getuid())/l"]])
    }

    nonisolated static var tmux: String? { MacLocalTmux.executablePath() }

    /// A process's resource coalition: macOS counts everything an app starts, and everything those
    /// start, as the app's, and a server tmux daemonizes stays in it (its parent and process group
    /// are its own either way). `PROC_PIDCOALITIONINFO` is flavor 20 of `proc_pidinfo`; the resource
    /// coalition's id comes first.
    static func coalition(_ pid: pid_t) -> UInt64? {
        var info = [UInt64](repeating: 0, count: 5)
        let size = Int32(info.count * MemoryLayout<UInt64>.size)
        let read = info.withUnsafeMutableBytes { proc_pidinfo(pid, 20, 0, $0.baseAddress, size) }
        return read == size && info[0] != 0 ? info[0] : nil
    }

    static func serverPID(socket: String) -> pid_t? {
        (MacLocalTmux.run("/usr/bin/pgrep", ["-f", "\(socket) -f /dev/null"]) ?? "").split(separator: "\n").compactMap { pid_t($0) }.first
    }

    /// The real thing on a private server: a socket of its own, no configuration, a label of its own,
    /// and the job file in a temporary folder — neither the owner's server nor his job is touched.
    @Test("launchd runs a private tmux server in a coalition of its own, where one this process starts shares its coalition",
          .enabled(if: MacTmuxServiceTests.tmux != nil))
    func live() throws {
        let tmux = try #require(Self.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-tmuxjob-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let socket = folder.appendingPathComponent("s").path
        let server = ["-S", socket, "-f", "/dev/null"]
        let ownSocket = folder.appendingPathComponent("o").path
        let ownServer = ["-S", ownSocket, "-f", "/dev/null"]
        let label = "com.glasspowertools.tmux.test.\(UUID().uuidString.prefix(8))"
        let jobURL = folder.appendingPathComponent("job.plist")
        // The app as host, as far as launchd sees it: a program given the host's arguments that
        // runs tmux in the foreground (MacTmuxHostTests runs the host's own code).
        let host = folder.appendingPathComponent("host").path
        try Data("#!/bin/sh\nshift\ntmux=\"$1\"\nshift\nexec \"$tmux\" \"$@\" -u -D\n".utf8).write(to: URL(fileURLWithPath: host))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host)
        defer {
            MacTmuxService.remove(label: label, jobURL: jobURL)
            _ = MacLocalTmux.run(tmux, server + ["kill-server"])
            _ = MacLocalTmux.run(tmux, ownServer + ["kill-server"])
            try? FileManager.default.removeItem(at: folder)
        }
        let mine = try #require(Self.coalition(getpid()))
        // The contrast: a server this process starts is this process's, as the app's was.
        #expect(MacLocalTmux.run(tmux, ownServer + ["new-session", "-d", "-s", "own", "/bin/sleep", "600"]) != nil)
        #expect(Self.serverPID(socket: ownSocket).flatMap(Self.coalition) == mine, "a server started the old way shares the coalition")

        #expect(!MacTmuxService.serverRunning(tmux: tmux, serverArguments: server))
        let outcome = MacTmuxService.ensureServer(host: host, tmux: tmux, environment: ["PATH": "/usr/bin:/bin", "TMUX_TMPDIR": folder.path],
                                                  label: label, serverArguments: server, jobURL: jobURL)
        #expect(outcome == .started)
        let serverPID = try #require(Self.serverPID(socket: socket))
        let theirs = try #require(Self.coalition(serverPID))
        #expect(theirs != mine, "launchd's server is in a coalition of its own")
        #expect(MacLocalTmux.run(tmux, server + ["new-session", "-d", "-s", "probe", "/bin/sleep", "600"]) != nil)
        let pane = try #require((MacLocalTmux.run("/usr/bin/pgrep", ["-P", String(serverPID)]) ?? "")
            .split(separator: "\n").compactMap { pid_t($0) }.first)
        #expect(Self.coalition(pane) == theirs, "and so are its panes")
        #expect(MacTmuxService.ensureServer(host: host, tmux: tmux, environment: [:], label: label, serverArguments: server,
                                            jobURL: jobURL) == .alreadyRunning)
        // Taken away, the job's server ends with it.
        MacTmuxService.remove(label: label, jobURL: jobURL)
        var gone = false
        for _ in 0..<40 where !gone {
            gone = !MacTmuxService.serverRunning(tmux: tmux, serverArguments: server)
            if !gone { Thread.sleep(forTimeInterval: 0.05) }
        }
        #expect(gone)
    }
}
#endif
