#if os(macOS)
import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

/// tmux's control mode against this Mac's own tmux (D83, 2026-10-19): `tmux -CC` on a real PTY, the
/// app's `TmuxControlClient` between it and a real SwiftTerm terminal, as a terminal tab would have
/// them. Each test runs a tmux server of its own (`-L`, no configuration) and ends it. Not run where
/// tmux isn't installed.
///
/// Off the main actor: its reads wait on the PTY, and on the main actor they starved the suite's
/// timing tests running beside them.
@Suite("tmux control mode against this Mac's tmux (live)", .serialized)
nonisolated struct LiveTmuxControlTests {
    static let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    static let environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "TERM": "xterm-256color",
                              "HOME": NSTemporaryDirectory(), "LANG": "en_US.UTF-8", "SHELL": "/bin/sh"]

    /// What a tab writes tmux's commands to and reads its protocol from.
    nonisolated protocol Transport: AnyObject {
        func write(_ data: Data)
        func read(milliseconds: Int32) -> Data?
        func end()
    }

    /// tmux as `-C` on pipes, no terminal: what a local pane runs (`MacTmuxControlPipe`).
    nonisolated final class PipeProcess: Transport {
        private let input: Int32, output: Int32
        private(set) var pid: pid_t = 0
        private var ended = false

        init?(_ arguments: [String]) {
            var toChild: [Int32] = [-1, -1], fromChild: [Int32] = [-1, -1]
            guard pipe(&toChild) == 0, pipe(&fromChild) == 0 else { return nil }
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_adddup2(&actions, toChild[0], 0)
            posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1)
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
            let argv = arguments.map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            let envp = LiveTmuxControlTests.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { envp.forEach { free($0) } }
            let spawned = posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp)
            close(toChild[0])
            close(fromChild[1])
            input = toChild[1]
            output = fromChild[0]
            guard spawned == 0 else { return nil }
        }

        func write(_ data: Data) {
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(input, buffer.baseAddress! + offset, buffer.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
        }

        func read(milliseconds: Int32) -> Data? {
            var descriptor = pollfd(fd: output, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, milliseconds) > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(output, &buffer, buffer.count)
            return count > 0 ? Data(buffer[..<count]) : nil
        }

        func end() {
            guard !ended else { return }
            ended = true
            close(input)
            close(output)
            var status: Int32 = 0
            for _ in 0..<50 {
                if waitpid(pid, &status, WNOHANG) == pid { return }
                usleep(20_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }

        deinit { end() }
    }

    /// A program on a PTY of its own.
    nonisolated final class PTYProcess: Transport {
        let master: Int32
        private(set) var pid: pid_t = 0

        init?(_ arguments: [String], columns: Int, rows: Int) {
            master = posix_openpt(O_RDWR | O_NOCTTY)
            guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else { return nil }
            let slave = String(cString: name)
            var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
            _ = withUnsafeMutablePointer(to: &size) { ioctl(master, TIOCSWINSZ, $0) }
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_addopen(&actions, 0, slave, O_RDWR, 0)
            posix_spawn_file_actions_adddup2(&actions, 0, 1)
            posix_spawn_file_actions_adddup2(&actions, 0, 2)
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // A session of its own, and none of the test process's descriptors (`LiveProcess`).
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT) | Int16(0x0400))
            let argv = arguments.map { strdup($0) } + [nil]
            defer { argv.forEach { free($0) } }
            let envp = LiveTmuxControlTests.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer { envp.forEach { free($0) } }
            guard posix_spawn(&pid, arguments[0], &actions, &attributes, argv, envp) == 0 else { return nil }
        }

        func write(_ data: Data) {
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(master, buffer.baseAddress! + offset, buffer.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
        }

        func read(milliseconds: Int32) -> Data? {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, milliseconds) > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(master, &buffer, buffer.count)
            return count > 0 ? Data(buffer[..<count]) : nil
        }

        private var ended = false

        /// Closes the PTY and reaps the program, killing it if it lingers: a tmux client left
        /// behind holds a PTY, and this Mac has 511.
        func end() {
            guard !ended else { return }
            ended = true
            close(master)
            kill(pid, SIGHUP)
            var status: Int32 = 0
            for _ in 0..<50 {
                if waitpid(pid, &status, WNOHANG) == pid { return }
                usleep(20_000)
            }
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
        }

        deinit { end() }
    }

    nonisolated final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    /// One tab's worth: tmux on a PTY, the client, and the terminal drawing what it says.
    nonisolated final class Tab {
        var client: TmuxControlClient
        let terminal: Terminal
        let process: any Transport
        private let delegate = Delegate()
        var live = false, exited = false

        init?(_ arguments: [String], columns: Int = 80, rows: Int = 24, overPipe: Bool = false) {
            guard let process: any Transport = overPipe ? PipeProcess(arguments)
                    : PTYProcess(arguments, columns: columns, rows: rows) else { return nil }
            self.process = process
            client = TmuxControlClient(columns: columns, rows: rows, overPipe: overPipe)
            terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: columns, rows: rows, scrollback: 10_000))
        }

        func apply(_ actions: [TmuxControlAction]) {
            for action in actions {
                switch action {
                case .terminal(let data): terminal.feed(byteArray: Array(data))
                case .transport(let data): process.write(data)
                case .live: live = true
                case .exited: exited = true
                }
            }
        }

        /// Reads and draws until `done` holds and output has been quiet a moment, or time runs out.
        @discardableResult
        func pump(seconds: Double = 10, until done: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            var quietSince = Date()
            while Date() < deadline {
                if let data = process.read(milliseconds: 50) {
                    apply(client.receive(data))
                    quietSince = Date()
                } else if done(), Date().timeIntervalSince(quietSince) > 0.3 {
                    return true
                }
            }
            return done()
        }

        func type(_ text: String) { apply(client.input(Data(text.utf8))) }

        /// Every line the terminal holds, history and screen.
        var lines: [String] {
            var lines: [String] = []
            var row = 0
            while let line = terminal.getScrollInvariantLine(row: row) {
                lines.append(line.translateToString(trimRight: true))
                row += 1
            }
            return lines
        }

        var screen: [String] { (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) } }

        func detach() {
            // A blank line detaches a control client.
            process.write(Data("\n".utf8))
            pump(seconds: 5) { exited }
            process.end()
        }
    }

    private func server() -> (socket: String, kill: () -> Void)? {
        guard let tmux = Self.tmux else { return nil }
        let socket = "glass-cc-\(UUID().uuidString.prefix(8))"
        // `kill-session`: tmux 3.8's `kill-server` answered success and left this server running.
        return (socket, { _ = LiveProcess.run(tmux, ["-L", socket, "kill-session", "-t", "cc"], environment: Self.environment) })
    }

    private func attach(_ socket: String, columns: Int = 80, rows: Int = 24) -> Tab? {
        guard let tmux = Self.tmux else { return nil }
        return Tab([tmux, "-L", socket, "-f", "/dev/null", "-u", "-CC", "new-session", "-A", "-s", "cc", "/bin/sh"],
                   columns: columns, rows: rows)
    }

    @Test("over pipes, as a local pane runs it: 2,000 lines at once, every one, in order, once")
    func overPipes() throws {
        guard let (socket, kill) = server(), let tmux = Self.tmux else { print("NOT RUN: no tmux on this Mac"); return }
        defer { kill() }
        let tab = try #require(Tab([tmux, "-L", socket, "-f", "/dev/null", "-u", "-C", "new-session", "-A", "-s", "cc", "/bin/sh"],
                                   overPipe: true))
        #expect(tab.pump { tab.live }, "attached and drawn, with no terminal under tmux")
        tab.type("PS1='$ '; seq 1 2000\r")
        tab.pump { tab.screen.contains("2000") }
        #expect(tab.lines.compactMap { Int($0) } == Array(1...2000))
        tab.detach()
    }

    @Test("2,000 lines printed at once: every one in the terminal's history, in order, once")
    func everyLine() throws {
        guard let (socket, kill) = server() else { print("NOT RUN: no tmux on this Mac"); return }
        defer { kill() }
        let tab = try #require(attach(socket))
        #expect(tab.pump { tab.live }, "attached and drawn")
        tab.type("PS1='$ '; seq 1 2000\r")
        tab.pump { tab.screen.contains("2000") }
        let numbers = tab.lines.compactMap { Int($0) }
        #expect(numbers == Array(1...2000), "\(numbers.count) numbers; missing \(Set(1...2000).subtracting(numbers).sorted().prefix(20))")
        #expect(!tab.terminal.isCurrentBufferAlternate, "a shell draws on the normal screen")
        tab.detach()
    }

    @Test("text with a quote, a backslash, a semicolon and a tilde reaches the program as typed")
    func typedExactly() throws {
        guard let (socket, kill) = server() else { print("NOT RUN: no tmux on this Mac"); return }
        defer { kill() }
        let tab = try #require(attach(socket))
        #expect(tab.pump { tab.live })
        tab.type("PS1='$ '; printf '%s\\n' \"it's ~ \\\\ ; -x done\"\r")
        #expect(tab.pump { tab.screen.contains(#"it's ~ \ ; -x done"#) }, "\(tab.screen)")
        tab.detach()
    }

    @Test("leaving and coming back: the history and the screen are read back in")
    func reattach() throws {
        guard let (socket, kill) = server() else { print("NOT RUN: no tmux on this Mac"); return }
        defer { kill() }
        let first = try #require(attach(socket))
        #expect(first.pump { first.live })
        first.type("PS1='$ '; seq 1 500\r")
        first.pump { first.screen.contains("500") }
        first.detach()

        let second = try #require(attach(socket))
        #expect(second.pump { second.live }, "attached again")
        let numbers = second.lines.compactMap { Int($0) }
        #expect(numbers == Array(1...500), "\(numbers.count) numbers back")
        #expect(second.screen.contains("500"), "the screen as it was: \(second.screen.suffix(3))")
        second.type("echo after-$((6*7))\r")
        #expect(second.pump { second.screen.contains("after-42") }, "and live after")
        second.detach()
    }

    @Test("a program on the alternate screen is still on it after coming back, the shell behind it")
    func alternateScreen() throws {
        guard let (socket, kill) = server() else { print("NOT RUN: no tmux on this Mac"); return }
        defer { kill() }
        let first = try #require(attach(socket))
        #expect(first.pump { first.live })
        first.type("PS1='$ '; echo before-the-program; printf '\\033[?1049h\\033[2J\\033[HFULL SCREEN'; sleep 60\r")
        first.pump { first.screen.contains("FULL SCREEN") }
        #expect(first.terminal.isCurrentBufferAlternate)
        first.detach()

        let second = try #require(attach(socket))
        #expect(second.pump { second.live })
        #expect(second.terminal.isCurrentBufferAlternate, "the program's screen")
        #expect(second.screen.first?.hasPrefix("FULL SCREEN") == true, "\(second.screen.prefix(2))")
        // Leaving the alternate screen shows the shell as it was behind it.
        second.terminal.feed(byteArray: Array("\u{1B}[?1049l".utf8))
        #expect(second.lines.contains("before-the-program"), "\(second.lines.suffix(5))")
        second.detach()
    }
}
#endif
