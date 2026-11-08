#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// The shell integration in real shells (D102, 2026-11-06): zsh (`-f`) and bash (`--norc
/// --noprofile`) on a PTY with a temporary HOME, the script sourced at the prompt, commands typed,
/// and the bytes that come back read for the marks. fish too, where this Mac has it.
///
/// Shells are found where they are usually installed; `GPT_TEST_SHELLS` (paths, `:`-separated)
/// adds more, so another bash or a fish can be tried without installing it. Never the real home
/// folder or its start-up files: every shell runs with a HOME of its own in the temporary folder.
@Suite("Shell integration in real shells (live)")
struct LiveShellIntegrationTests {

    // MARK: The marks

    @Test("A, B, the typed line, E with the exact command, C, the output, D;0; then D;1 for false",
          arguments: LiveShells.zshAndBash)
    func marksInOrder(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        let first = try await session.setUp()
        // Nothing before the first prompt after loading: no D for the command that loaded it.
        #expect(first.marks(starting: "133;D").isEmpty)
        #expect(first.marks(starting: "133;A").count == 1)

        let span = await session.run("echo hello")
        let typed = try #require(span.textIndex(containing: "echo hello"))
        let output = try #require(span.textIndex(equalTo: "hello"))
        let done = try #require(span.markIndex("133;D;0"))
        let next = try #require(span.markIndex(starting: "133;A", after: done))
        let end = try #require(span.markIndex("133;B", after: next))
        // Without E and C the typed line and its output are one stretch of text.
        #expect(typed <= output && output < done && done < next && next < end)
        if shell.marksCommands {
            let command = try #require(span.markIndex("633;E;echo hello"))
            let started = try #require(span.markIndex("133;C"))
            #expect(typed < command && command < started && started < output)
        } else {
            // Older bash: no PS0, so neither E nor C.
            #expect(span.marks(starting: "633;E").isEmpty && span.marks(starting: "133;C").isEmpty)
        }

        let failed = await session.run("false")
        #expect(failed.markIndex("133;D;1") != nil)
        #expect(failed.marks(starting: "133;D").count == 1)
    }

    @Test("$? is kept: after false the prompt shows 1, and echo $? prints 1", arguments: LiveShells.zshAndBash)
    func statusKept(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        // bash restores $? after PROMPT_COMMAND for the next command itself, but the prompt is
        // drawn with whatever PROMPT_COMMAND's last entry, the integration's, leaves.
        _ = try await session.setUp(before: shell.kind == .zsh ? "PS1='[%?] $ '" : "PS1='[$?] $ '")
        let failed = await session.run("false")
        let prompt = try #require(failed.markIndex(starting: "133;A", after: failed.markIndex(starting: "133;D") ?? -1))
        let end = try #require(failed.markIndex("133;B", after: prompt))
        #expect(failed.text(between: prompt, and: end).hasSuffix("[1] $ "), "\(failed.lines)")
        let span = await session.run("echo $?")
        #expect(span.textIndex(equalTo: "1") != nil, "\(span.lines)")
    }

    @Test("An empty Enter sends no D; the prompt is marked again", arguments: LiveShells.zshAndBash)
    func emptyEnter(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp()
        _ = await session.run("true")
        let span = await session.run("")
        #expect(span.marks(starting: "133;D").isEmpty)
        #expect(span.marks(starting: "133;A").count == 1 && span.marks(starting: "133;B").count == 1)
    }

    @Test("A password read with echo off is never marked as typing: no B until the next prompt",
          arguments: LiveShells.zshAndBash)
    func passwordNotMarked(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp()
        let asked = await session.type("read -s secret", until: { _ in false }, seconds: 0.6)
        #expect(asked.marks(starting: "133;B").isEmpty)
        let span = await session.run("hunter2")
        let done = try #require(span.markIndex(starting: "133;D"))
        #expect(span.marks(starting: "133;B").allSatisfy { $0 > done })
        #expect(span.textIndex(containing: "hunter2") == nil)
    }

    @Test("A theme that builds PS1 afresh every prompt still ends with B", arguments: LiveShells.zshAndBash)
    func themeRebuildsPrompt(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        // Set before the integration, as a theme in a start-up file is. zsh's is added after it
        // too, which the integration answers by moving its hook last; the first such prompt's B
        // comes from zle-line-init.
        let theme = switch shell.kind {
        case .zsh: "theme() { PS1=\"theme$((++n))> \" }; precmd_functions+=(theme)"
        default: "theme() { PS1=\"theme$((n+=1))> \"; }; PROMPT_COMMAND=theme"
        }
        _ = try await session.setUp(before: theme)
        if shell.kind == .zsh {
            _ = await session.run("later() { PS1=\"later$((++m))> \" }; precmd_functions+=(later)")
        }
        for command in ["true", "echo x", "true"] {
            let span = await session.run(command)
            let prompt = try #require(span.markIndex(starting: "133;A", after: span.markIndex(starting: "133;D") ?? -1))
            let end = try #require(span.markIndex("133;B", after: prompt))
            let drawn = span.text(between: prompt, and: end)
            #expect(drawn.hasSuffix("> ") && drawn.contains(shell.kind == .zsh ? "later" : "theme"), "\(drawn)")
            #expect(span.marks(starting: "133;B").count == 1)
        }
    }

    @Test("bash: something appended to PROMPT_COMMAND later that builds PS1 still gets B from the next prompt",
          arguments: LiveShells.bash)
    func bashThemeAddedLater(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp()
        // The prompt right after can't carry B: the newcomer runs after the integration this once.
        _ = await session.type("later() { PS1=\"later$((n+=1))> \"; }; PROMPT_COMMAND+=$'\\n'later",
                               until: { $0.markIndex(starting: "133;A") != nil }, seconds: 3)
        for command in ["true", "true"] {
            let span = await session.run(command)
            let prompt = try #require(span.markIndex(starting: "133;A"))
            let end = try #require(span.markIndex("133;B", after: prompt))
            #expect(span.text(between: prompt, and: end).hasSuffix("> "))
        }
    }

    @Test("The shell's own hooks keep running, and see the command's status", arguments: LiveShells.zshAndBash)
    func ownHooksRun(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        let own = switch shell.kind {
        case .zsh: "mine() { print -n \"[mine:$?]\" }; precmd_functions+=(mine); "
            + "minepre() { print -n '[pre]' }; preexec_functions+=(minepre); precmd() { print -n '[fn]' }"
        default: "PROMPT_COMMAND='printf \"[mine:%s]\" $?'"
        }
        _ = try await session.setUp(before: own)
        let span = await session.run("false")
        let text = span.lines.joined()
        #expect(text.contains("[mine:1]"), "\(text)")
        if shell.kind == .zsh { #expect(text.contains("[pre]") && text.contains("[fn]")) }
    }

    @Test("bash 5.1 and later: an array PROMPT_COMMAND keeps its entries, each seeing the status",
          arguments: LiveShells.bash.filter { $0.atLeast(5, 1) })
    func bashArrayPromptCommand(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp(before: "PROMPT_COMMAND=('printf \"[a:%s]\" $?' 'printf \"[b:%s]\" $?')")
        let span = await session.run("false")
        let text = span.lines.joined()
        #expect(text.contains("[a:1]") && text.contains("[b:1]"), "\(text)")
        #expect(span.markIndex("133;D;1") != nil && span.marks(starting: "133;B").count == 1)
    }

    @Test("OSC 7 carries the folder after cd, percent-encoded", arguments: LiveShells.zshAndBash)
    func folderReported(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp()
        let folder = try session.makeFolder("a b é;%")
        let span = await session.run("cd '\(folder)'")
        let reported = try #require(span.marks(starting: "7;file://").last.map { span.mark(at: $0) })
        #expect(reported.hasSuffix(LiveShellSession.percentEncoded(folder)), "\(reported)")
        // file://<this machine><folder>: a host with no slash in it.
        #expect(!String(reported.dropFirst("7;file://".count).dropLast(LiveShellSession.percentEncoded(folder).count)).contains("/"))
    }

    @Test("Sourced twice, every mark still comes once", arguments: LiveShells.zshAndBash)
    func sourcedTwice(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp(sourcing: 2)
        let span = await session.run("echo once")
        for mark in ["133;A", "133;B", "133;D", "7;"] {
            #expect(span.marks(starting: mark).count == 1, "\(mark)")
        }
        let commandMarks = shell.marksCommands ? 1 : 0
        #expect(span.marks(starting: "633;E").count == commandMarks && span.marks(starting: "133;C").count == commandMarks)
    }

    @Test("E carries a command with ';', a backslash and unicode escaped as VS Code's",
          arguments: LiveShells.zshAndBash.filter(\.marksCommands))
    func commandEscaped(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell)
        _ = try await session.setUp()
        let command = #"echo 'a;b\c' "x;\\y" é"#
        let span = await session.run(command)
        let marks = span.marks(starting: "633;E;").map { span.mark(at: $0) }
        #expect(marks == ["633;E;" + TerminalShellIntegration.escapedCommandLine(command)])
    }

    // MARK: This Mac's zsh

    @Test("This Mac's zsh: the person's files run with their own ZDOTDIR, then the marks appear",
          arguments: [false, true], [false, true])
    func localZsh(customFolder: Bool, login: Bool) async throws {
        let session = try LiveShellSession(LiveShells.systemZsh, start: false)
        let home = session.home.path
        let theirs = customFolder ? home + "/zdot" : home
        try FileManager.default.createDirectory(atPath: theirs, withIntermediateDirectories: true)
        let files = [
            ".zshenv": "GLASS_TEST_ENV=ran\n",
            ".zprofile": "GLASS_TEST_PROFILE=ran\n",
            ".zshrc": "GLASS_TEST_RC=ran\nGLASS_TEST_SEEN=${ZDOTDIR-unset}\nPS1='$ '\n",
            ".zlogin": "GLASS_TEST_LOGIN=ran\n",
        ]
        for (name, contents) in files {
            try contents.write(toFile: theirs + "/" + name, atomically: true, encoding: .utf8)
        }
        let folder = home + "/startup"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for (name, contents) in TerminalShellIntegration.localZshStartupFiles() {
            try contents.write(toFile: folder + "/" + name, atomically: true, encoding: .utf8)
        }
        var inherited = session.environment
        if customFolder { inherited["ZDOTDIR"] = theirs }
        let environment = TerminalShellIntegration.localZshEnvironment(startupFolder: folder, inherited: inherited)
        try session.start(arguments: login ? ["-i", "-l"] : ["-i"], environment: environment)

        let first = await session.waitForPrompt()
        #expect(first.markIndex("133;B") != nil, "\(first.lines)")
        #expect(first.marks(starting: "133;D").isEmpty)
        let expected = customFolder ? theirs : "unset"
        let span = await session.run(#"print -r -- "env=$GLASS_TEST_ENV rc=$GLASS_TEST_RC profile=${GLASS_TEST_PROFILE-} "#
            + #"login=${GLASS_TEST_LOGIN-} seen=$GLASS_TEST_SEEN now=${ZDOTDIR-unset} history=$HISTFILE""#)
        let line = try #require(span.lines.first { $0.hasPrefix("env=") })
        let ran = login ? "profile=ran login=ran" : "profile= login="
        #expect(line.hasPrefix("env=ran rc=ran \(ran) seen=\(expected) now=\(expected) "), "\(line)")
        #expect(!line.contains(folder), "\(line)")
        #expect(span.markIndex(starting: "633;E;print -r") != nil && span.markIndex("133;D;0") != nil)
        #expect(span.marks(starting: "133;A").count == 1 && span.marks(starting: "133;B").count == 1)
    }

    // MARK: fish

    @Test("fish: the marks in order, with fish's own or (no-mark-prompt) the script's",
          .enabled(if: !LiveShells.fish.isEmpty, "fish isn't installed on this Mac"),
          arguments: LiveShells.fish, [false, true])
    func fishMarks(shell: LiveShell, fishMarksOff: Bool) async throws {
        let session = try LiveShellSession(shell, fishMarksOff: fishMarksOff)
        _ = try await session.setUp()
        let span = await session.run("echo hello")
        let typed = try #require(span.textIndex(containing: "echo hello"))
        let command = try #require(span.markIndex("633;E;echo hello"))
        let started = try #require(span.markIndex(starting: "133;C"))
        let output = try #require(span.textIndex(equalTo: "hello"))
        let done = try #require(span.markIndex("133;D;0"))
        let next = try #require(span.markIndex(starting: "133;A", after: done))
        let end = try #require(span.markIndex("133;B", after: next))
        // fish 4 sends its own C before any fish_preexec handler, so E follows it there.
        if session.fishMarksPrompts {
            #expect(typed < started && started < command && command < output)
        } else {
            #expect(typed < command && command < started && started < output)
        }
        #expect(output < done && done < next && next < end)
        for mark in ["133;A", "133;B", "133;C", "133;D", "633;E"] {
            #expect(span.marks(starting: mark).count == 1, "\(mark)")
        }

        let failed = await session.run("false")
        #expect(failed.markIndex("133;D;1") != nil)
        let status = await session.run("echo $status")
        #expect(status.textIndex(equalTo: "1") != nil)
        #expect(await session.run("").marks(starting: "133;D").isEmpty)

        // The script marks nothing inside a command. fish 4's own marks put A and B around `read`'s
        // prompt, inside C…D, so that is checked only with them off.
        if !session.fishMarksPrompts {
            let asked = await session.type("read -s secret", until: { _ in false }, seconds: 0.6)
            #expect(asked.marks(starting: "133;B").isEmpty)
            let read = await session.run("hunter2")
            let done = try #require(read.markIndex(starting: "133;D"))
            #expect(read.marks(starting: "133;B").allSatisfy { $0 > done })
        }
    }

    @Test("fish: a prompt defined anew still ends with B; the person's handlers still run; sourced twice, E once",
          .enabled(if: !LiveShells.fish.isEmpty, "fish isn't installed on this Mac"),
          arguments: LiveShells.fish, [false, true])
    func fishPromptAndHandlers(shell: LiveShell, fishMarksOff: Bool) async throws {
        let session = try LiveShellSession(shell, fishMarksOff: fishMarksOff)
        _ = try await session.setUp(
            before: "function mine --on-event fish_postexec; printf '[mine:%s]' $status; end", sourcing: 2)
        _ = await session.run("function fish_prompt; printf 'theme> '; end")
        let span = await session.run("false")
        #expect(span.lines.joined().contains("[mine:1]"))
        let prompt = try #require(span.markIndex(starting: "133;A", after: span.markIndex(starting: "133;D") ?? -1))
        let end = try #require(span.markIndex("133;B", after: prompt))
        #expect(span.text(between: prompt, and: end).hasSuffix("theme> "))
        #expect(span.marks(starting: "633;E").count == 1 && span.marks(starting: "133;B").count == 1)

        let command = #"echo 'a;b\c' é"#
        let escaped = await session.run(command)
        #expect(escaped.marks(starting: "633;E;").map { escaped.mark(at: $0) }
            == ["633;E;" + TerminalShellIntegration.escapedCommandLine(command)])
        let folder = try session.makeFolder("a b é")
        let moved = await session.run("cd '\(folder)'")
        #expect(moved.marks(starting: "7;file://").map { moved.mark(at: $0) }
            .contains { $0.hasSuffix(LiveShellSession.percentEncoded(folder)) })
    }

    // MARK: The scripts parse

    @Test("Each script parses in every shell found for it, bash 3.2 included", arguments: LiveShells.all)
    func scriptsParse(shell: LiveShell) async throws {
        let session = try LiveShellSession(shell, start: false)
        let script = try session.writeScript()
        let check = shell.kind == .fish ? ["--no-execute", script] : ["-n", script]
        let result = await LiveProcess.runDetached(shell.path, check, environment: session.environment, includingErrors: true)
        #expect(result.status == 0 && result.output.isEmpty, "\(result.output)")
    }
}

// MARK: - Shells

/// A shell this Mac can run.
nonisolated struct LiveShell: Sendable, CustomTestStringConvertible {
    let kind: TerminalShellKind
    let path: String
    let version: [Int]

    var testDescription: String { "\(kind.rawValue) \(version.map(String.init).joined(separator: ".")) at \(path)" }

    func atLeast(_ major: Int, _ minor: Int) -> Bool {
        (version.first ?? 0, version.dropFirst().first ?? 0) >= (major, minor)
    }

    /// Whether the integration sends E and C here: everywhere but bash before 4.4, which has no PS0.
    var marksCommands: Bool { kind != .bash || atLeast(4, 4) }

    init?(path: String) {
        let name = (path as NSString).lastPathComponent
        guard FileManager.default.isExecutableFile(atPath: path),
              let kind = TerminalShellKind.allCases.first(where: { name.hasPrefix($0.rawValue) }) else { return nil }
        let asked = switch kind {
        case .zsh: "echo $ZSH_VERSION"
        case .bash: "echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
        case .fish: "echo $version"
        }
        let answer = LiveProcess.run(path, ["-c", asked], environment: ["HOME": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin"])
        let numbers = answer.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { !$0.isNumber }).prefix(2).compactMap { Int($0) }
        guard answer.status == 0, numbers.count == 2 else { return nil }
        self.kind = kind
        self.path = path
        self.version = numbers
    }
}

nonisolated enum LiveShells {
    static let all: [LiveShell] = {
        let usual = ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/zsh", "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
                     "/opt/homebrew/bin/fish", "/usr/local/bin/fish"]
        let more = ProcessInfo.processInfo.environment["GPT_TEST_SHELLS"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (usual + more).compactMap { path in
            let real = (path as NSString).resolvingSymlinksInPath
            guard seen.insert(real).inserted else { return nil }
            return LiveShell(path: path)
        }
    }()
    static let zshAndBash = all.filter { $0.kind != .fish }
    static let bash = all.filter { $0.kind == .bash }
    static let fish = all.filter { $0.kind == .fish }
    /// macOS's own zsh, what this Mac's terminals start.
    static let systemZsh = LiveShell(path: "/bin/zsh")!
}

// MARK: - A shell on a PTY

/// One shell on a PTY with a HOME of its own, the integration's script beside it, and the bytes it
/// has sent so far. Blocking reads happen off the main actor (`offMainActor`), so these tests run
/// side by side without holding it.
nonisolated final class LiveShellSession: @unchecked Sendable {
    let shell: LiveShell
    let home: URL
    let environment: [String: String]
    private let fishMarksOff: Bool
    private var process: LiveTmuxControlTests.PTYProcess?
    private var bytes: [UInt8] = []
    private var answered = 0

    init(_ shell: LiveShell, fishMarksOff: Bool = false, start: Bool = true) throws {
        self.shell = shell
        self.fishMarksOff = fishMarksOff
        home = FileManager.default.temporaryDirectory.appendingPathComponent("glass-si-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        environment = [
            "HOME": home.path, "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "XDG_CONFIG_HOME": home.path + "/.config", "XDG_DATA_HOME": home.path + "/.local/share",
            "XDG_CACHE_HOME": home.path + "/.cache", "BASH_SILENCE_DEPRECATION_WARNING": "1",
        ]
        if start {
            let arguments = switch shell.kind {
            case .zsh: ["-f", "-i"]
            case .bash: ["--norc", "--noprofile", "-i"]
            case .fish: fishMarksOff ? ["--features", "no-mark-prompt", "-i"] : ["-i"]
            }
            try self.start(arguments: arguments, environment: environment)
        }
    }

    deinit {
        process?.end()
        try? FileManager.default.removeItem(at: home)
    }

    /// Whether fish marks its own prompts here: fish 4 and later, unless told not to.
    var fishMarksPrompts: Bool { shell.kind == .fish && shell.atLeast(4, 0) && !fishMarksOff }

    /// Through `script`, which gives the shell a PTY of its own as its controlling terminal, as the
    /// app's terminals have one. A PTY opened after `setsid` isn't one on macOS (that takes
    /// TIOCSCTTY): zsh and bash put up with that, fish refuses to start ("No TTY for interactive shell").
    func start(arguments: [String], environment: [String: String]) throws {
        let assignments = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let command = ["/usr/bin/env", "-i"] + assignments + ["/usr/bin/script", "-q", "/dev/null", shell.path] + arguments
        guard let process = LiveTmuxControlTests.PTYProcess(command, columns: 160, rows: 40) else {
            throw LiveShellError.couldNotStart(shell.path)
        }
        self.process = process
    }

    func writeScript() throws -> String {
        let path = home.path + "/shell-integration." + shell.kind.rawValue
        try TerminalShellIntegration.script(for: shell.kind).write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func makeFolder(_ name: String) throws -> String {
        let path = home.path + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Waits for the first prompt, then types a simple prompt, whatever `before` sets up, and the
    /// script sourced `sourcing` times; returns what came back up to the next prompt's B.
    func setUp(before: String? = nil, sourcing: Int = 1) async throws -> ShellSpan {
        let script = try writeScript()
        _ = await waitForPrompt(marked: false)
        let prompt = shell.kind == .fish ? "function fish_prompt; printf '$ '; end" : "PS1='$ '"
        let line = ([prompt] + (before.map { [$0] } ?? []) + Array(repeating: "source '\(script)'", count: sourcing))
            .joined(separator: "; ")
        let span = await run(line)
        guard span.markIndex("133;B") != nil else { throw LiveShellError.noPrompt(span.lines) }
        return span
    }

    /// The first prompt: its B when it is marked, or quiet output when it isn't.
    func waitForPrompt(marked: Bool = true) async -> ShellSpan {
        await offMainActor { [self] in
            if marked { return read(from: 0, seconds: 8) { $0.markIndex("133;B") != nil } }
            return read(from: 0, seconds: 4, quietFor: 0.4) { !$0.pieces.isEmpty }
        }
    }

    /// Types a line and Enter; returns what came back up to the next prompt's B.
    func run(_ line: String) async -> ShellSpan {
        await type(line, until: { $0.markIndex("133;B") != nil }, seconds: 6)
    }

    /// Types a line and Enter; returns what came back once `done` holds, or `seconds` pass.
    func type(_ line: String, until done: @escaping @Sendable (ShellSpan) -> Bool, seconds: Double) async -> ShellSpan {
        await offMainActor { [self] in
            let start = bytes.count
            process?.write(Data((line + "\r").utf8))
            return read(from: start, seconds: seconds, until: done)
        }
    }

    private func read(from start: Int, seconds: Double, quietFor quiet: Double = 0.15,
                      until done: (ShellSpan) -> Bool) -> ShellSpan {
        let deadline = Date().addingTimeInterval(seconds)
        var lastData = Date()
        while Date() < deadline {
            if let data = process?.read(milliseconds: 30) {
                bytes += data
                lastData = Date()
                answerQueries()
            } else if Date().timeIntervalSince(lastData) >= quiet, done(ShellSpan(bytes[start...])) {
                break
            }
        }
        return ShellSpan(bytes[start...])
    }

    /// fish 4 asks the terminal what it is (primary device attributes) and waits for the answer.
    private func answerQueries() {
        let text = String(decoding: bytes, as: UTF8.self)
        let asked = text.components(separatedBy: "\u{1b}[c").count - 1 + text.components(separatedBy: "\u{1b}[0c").count - 1
        while answered < asked {
            process?.write(Data("\u{1b}[?62;22c".utf8))
            answered += 1
        }
    }

    /// A path as OSC 7 carries it: every byte but letters, digits and `/._~-` as %XX.
    static func percentEncoded(_ path: String) -> String {
        let plain = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._~-".utf8)
        return path.utf8.map { plain.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
    }
}

nonisolated enum LiveShellError: Error {
    case couldNotStart(String)
    case noPrompt([String])
}

// MARK: - What came back

/// A stretch of a shell's output as marks (each OSC's text, ended by BEL or ST) and the text
/// between them, other escape sequences and carriage returns removed.
nonisolated struct ShellSpan: Sendable {
    enum Piece: Sendable, Equatable {
        case mark(String)
        case text(String)
    }

    let pieces: [Piece]

    init(_ bytes: ArraySlice<UInt8>) {
        var pieces: [Piece] = []
        var text = String.UnicodeScalarView()
        let scalars = Array(String(decoding: bytes, as: UTF8.self).unicodeScalars)
        var index = 0
        func flush() {
            if !text.isEmpty { pieces.append(.text(String(text))) }
            text = String.UnicodeScalarView()
        }
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\u{1b}", index + 1 < scalars.count else {
                if scalar == "\n" || scalar.value >= 0x20 && scalar.value != 0x7f { text.append(scalar) }
                index += 1
                continue
            }
            let kind = scalars[index + 1]
            index += 2
            switch kind {
            case "]", "P":
                // OSC (or DCS): up to BEL or ST.
                var body = String.UnicodeScalarView()
                while index < scalars.count {
                    if scalars[index] == "\u{07}" { index += 1; break }
                    if scalars[index] == "\u{1b}", index + 1 < scalars.count, scalars[index + 1] == "\\" { index += 2; break }
                    body.append(scalars[index])
                    index += 1
                }
                if kind == "]" {
                    flush()
                    pieces.append(.mark(String(body)))
                }
            case "[":
                // CSI: parameters, then a final byte from @ to ~.
                while index < scalars.count, !(0x40...0x7e).contains(scalars[index].value) { index += 1 }
                index += 1
            default:
                break
            }
        }
        flush()
        self.pieces = pieces
    }

    /// The text, line by line.
    var lines: [String] {
        pieces.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
            .components(separatedBy: "\n")
    }

    func mark(at index: Int) -> String {
        if case .mark(let text) = pieces[index] { text } else { "" }
    }

    /// The indexes of the marks that begin with `prefix`.
    func marks(starting prefix: String) -> [Int] {
        pieces.indices.filter { if case .mark(let text) = pieces[$0] { text.hasPrefix(prefix) } else { false } }
    }

    func markIndex(_ exactly: String, after: Int = -1) -> Int? {
        pieces.indices.first { $0 > after && pieces[$0] == .mark(exactly) }
    }

    func markIndex(starting prefix: String, after: Int = -1) -> Int? {
        marks(starting: prefix).first { $0 > after }
    }

    func textIndex(containing needle: String) -> Int? {
        pieces.indices.first { if case .text(let text) = pieces[$0] { text.contains(needle) } else { false } }
    }

    /// A text piece holding `line` as a line of its own.
    func textIndex(equalTo line: String) -> Int? {
        pieces.indices.first {
            if case .text(let text) = pieces[$0] { text.components(separatedBy: "\n").contains(line) } else { false }
        }
    }

    func text(between start: Int, and end: Int) -> String {
        pieces[(start + 1)..<end].compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }
}
#endif
