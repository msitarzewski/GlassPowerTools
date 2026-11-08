import Foundation
import Testing
import SwiftTerm
@testable import GlassTerminalEmulator

/// Type-ahead's view of the prompt (D102, 2026-11-06): what the shell marks (OSC 133, VS Code's 633), and the keys
/// typed where it marks nothing, checked against the screen. A headless SwiftTerm terminal, fed as a shell would.
@MainActor
@Suite("Type-ahead: following the prompt")
struct TypeAheadTrackerTests {
    nonisolated final class Delegate: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private let delegate = Delegate()

    /// A terminal whose shell, where it marks nothing, is known to be reading the keys (a local terminal asks the
    /// system: `shellIsInForeground`).
    private func terminal(columns: Int = 40) -> (Terminal, TerminalPromptTracker) {
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: columns, rows: 10, scrollback: 100))
        let tracker = TerminalPromptTracker(terminal: terminal)
        tracker.shellIsInForeground = { true }
        return (terminal, tracker)
    }

    private func feed(_ terminal: Terminal, _ text: String) {
        terminal.feed(byteArray: Array(text.utf8))
    }

    private static let a = "\u{1B}]133;A\u{07}", b = "\u{1B}]133;B\u{07}", c = "\u{1B}]133;C\u{07}"
    private static func d(_ status: Int) -> String { "\u{1B}]133;D;\(status)\u{07}" }
    private static func e(_ command: String) -> String { "\u{1B}]633;E;\(command)\u{07}" }

    @Test("with shell integration: the line from where typing began, the command run, its exit status")
    func integration() {
        let (terminal, tracker) = terminal()
        var ran: [TerminalRanCommand] = []
        var finished: [Int?] = []
        tracker.onCommandRun = { ran.append($0) }
        tracker.onCommandFinished = { finished.append($0) }

        feed(terminal, Self.a + "~/src $ " + Self.b)
        #expect(tracker.hasShellIntegration && tracker.phase == .typing)
        #expect(tracker.currentLine()?.text == "", "nothing typed yet")
        feed(terminal, "git sta")
        let line = tracker.currentLine()
        #expect(line?.text == "git sta" && line?.cursorAtEnd == true && line?.source == .shellIntegration)
        #expect(line?.columnsLeft == 40 - 15)

        feed(terminal, "tus\r\n" + Self.e("git status") + Self.c + "On branch main\r\n" + Self.d(0))
        #expect(ran == [TerminalRanCommand(command: "git status", source: .shellIntegration)])
        #expect(finished == [0])
        #expect(tracker.currentLine() == nil, "a command ran; no prompt yet")
        // SwiftTerm still marked the typed cells as input: the marks were passed on (patch S3).
        #expect(terminal.semanticContent(at: Position(col: 9, row: 0)) == .input)
    }

    @Test("without E, the command is read from the cells typed; a failed one reports its status")
    func commandFromCells() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        var finished: [Int?] = []
        tracker.onCommandRun = { ran.append($0.command) }
        tracker.onCommandFinished = { finished.append($0) }
        feed(terminal, Self.a + "$ " + Self.b + "make test  \r\n" + Self.c + "error\r\n" + Self.d(2))
        #expect(ran == ["make test"], "the row's blanks dropped")
        #expect(finished == [2])
    }

    @Test("a typed line longer than the row: read across the wrap")
    func wrapped() {
        let (terminal, tracker) = terminal(columns: 20)
        feed(terminal, Self.a + "$ " + Self.b + "echo abcdefghijklmnopqrstuvwxyz")
        #expect(tracker.currentLine()?.text == "echo abcdefghijklmnopqrstuvwxyz")
    }

    @Test("VS Code's 633 marks count as 133's, and E's escapes are undone")
    func vsCode() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        tracker.onCommandRun = { ran.append($0.command) }
        feed(terminal, "\u{1B}]633;A\u{07}$ \u{1B}]633;B\u{07}echo a;b\r\n" + Self.e("echo a\\x3bb \\\\n") + "\u{1B}]633;C\u{07}")
        #expect(ran == ["echo a;b \\n"])
        #expect(TerminalPromptTracker.unescapeCommandLine("a\\x3bb\\\\c\\x0a") == "a;b\\c\n")
    }

    @Test("a cursor moved back into the line: nothing may follow it")
    func cursorInside() {
        let (terminal, tracker) = terminal()
        feed(terminal, Self.a + "$ " + Self.b + "git status\u{1B}[3D")
        let line = tracker.currentLine()
        #expect(line?.text == "git sta")
        #expect(line?.cursorAtEnd == false && line?.othersSuggestion == false)
    }

    @Test("the shell's own grey suggestion after the cursor is told apart from typed text")
    func othersSuggestion() {
        let (terminal, tracker) = terminal()
        // zsh-autosuggestions: the rest in bright black (90), the cursor back where typing is.
        feed(terminal, Self.a + "$ " + Self.b + "gi\u{1B}[90mt status\u{1B}[0m\u{1B}[8D")
        let line = tracker.currentLine()
        #expect(line?.text == "gi")
        #expect(line?.othersSuggestion == true && line?.cursorAtEnd == true)
    }

    @Test("on the alternate screen there is no line")
    func alternateScreen() {
        let (terminal, tracker) = terminal()
        feed(terminal, Self.a + "$ " + Self.b + "vi")
        feed(terminal, "\u{1B}[?1049h~")
        #expect(tracker.currentLine() == nil)
    }

    // MARK: - Without shell integration

    @Test("without integration: the keys typed count only when the screen shows them before the cursor")
    func typedKeys() {
        let (terminal, tracker) = terminal()
        var ran: [TerminalRanCommand] = []
        tracker.onCommandRun = { ran.append($0) }
        feed(terminal, "ann@alpha ~ % ")
        tracker.noteSent(Array("ls -l".utf8))
        #expect(tracker.currentLine() == nil, "not echoed yet")
        feed(terminal, "ls -l")
        #expect(tracker.currentLine() == TerminalTypedLine(text: "ls -l", cursorAtEnd: true, othersSuggestion: false,
                                                           source: .typedKeys, columnsLeft: 40 - 19))
        tracker.noteSent([0x7F])
        feed(terminal, "\u{08} \u{08}")
        #expect(tracker.currentLine()?.text == "ls -")
        tracker.noteSent(Array("a\r".utf8))
        #expect(ran.isEmpty, "the a wasn't echoed when Enter went: the screen didn't confirm the line")
    }

    @Test("Enter on a confirmed line is a command run; a line typed with echo off never is")
    func passwords() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        tracker.onCommandRun = { ran.append($0.command) }
        feed(terminal, "% ")
        tracker.noteSent(Array("sudo ls".utf8))
        feed(terminal, "sudo ls")
        tracker.noteSent([0x0D])
        #expect(ran == ["sudo ls"])
        feed(terminal, "\r\nPassword:")
        tracker.noteSent(Array("hunter2".utf8))
        #expect(tracker.currentLine() == nil, "echo is off: the screen never shows it")
        tracker.noteSent([0x0D])
        #expect(ran == ["sudo ls"], "the password was never taken for a command")
    }

    /// Seen in the macOS VM (2026-11-06): each terminal's first command was kept twice. Its prompt carried no marks
    /// (a reattached session's screen, or zsh loading the integration at its first prompt), so Enter on the
    /// confirmed line counted it, and then the integration's own C, arriving with it, counted it again.
    @Test("the first command, counted at Enter before any mark, isn't counted again by the C that follows it")
    func firstCommandOnce() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        tracker.onCommandRun = { ran.append($0.command) }
        feed(terminal, "% ")
        tracker.noteSent(Array("ls -la".utf8))
        feed(terminal, "ls -la")
        tracker.noteSent([0x0D])
        #expect(ran == ["ls -la"], "no marks yet: counted at Enter")
        feed(terminal, "\r\n" + Self.e("ls -la") + Self.c + "total 0\r\n" + Self.d(0) + Self.a + "% " + Self.b)
        #expect(ran == ["ls -la"], "the C that followed is the same run")
        feed(terminal, "pwd\r\n" + Self.e("pwd") + Self.c + "/\r\n" + Self.d(0))
        #expect(ran == ["ls -la", "pwd"], "from then on the marks count each run")
    }

    /// "No surprises for users" (the owner, 2026-11-06). In an SSH terminal whose shell marks nothing, a line typed
    /// into Claude Code, Python or mysql looks exactly like one typed at a prompt.
    @Test("without integration, nothing is offered or kept unless the shell is known to be reading the keys")
    func otherProgramsLines() {
        for foreground in [nil, false] as [Bool?] {
            let (terminal, tracker) = terminal()
            tracker.shellIsInForeground = foreground.map { value in { value } }
            var ran: [String] = []
            tracker.onCommandRun = { ran.append($0.command) }
            feed(terminal, "> ")
            tracker.noteSent(Array("explain this repo".utf8))
            feed(terminal, "explain this repo")
            #expect(tracker.currentLine() == nil, "offered over another program's input (\(String(describing: foreground)))")
            tracker.noteSent([0x0D])
            #expect(ran.isEmpty, "kept another program's input as a command (\(String(describing: foreground)))")
        }
    }

    // MARK: - fish 4's own marks

    private static let st = "\u{1B}\\"

    @Test("fish 4: its C names the command (cmdline_url); the app's E after it doesn't name the next one")
    func fishOrder() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        var finished: [Int?] = []
        tracker.onCommandRun = { ran.append($0.command) }
        tracker.onCommandFinished = { finished.append($0) }
        let a = "\u{1B}]133;A;click_events=1" + Self.st, b = "\u{1B}]133;B" + Self.st
        func c(_ url: String) -> String { "\u{1B}]133;C;cmdline_url=\(url)" + Self.st }
        feed(terminal, a + "~> " + b + "ls -la\r\n" + c("ls%20-la") + Self.e("ls -la") + "total 0\r\n" + "\u{1B}]133;D;0" + Self.st)
        #expect(ran == ["ls -la"] && finished == [0])
        // The second's C comes without its E yet: the first's E must not stand in for it.
        feed(terminal, a + "~> " + b + "pwd\r\n" + "\u{1B}]133;C" + Self.st)
        #expect(ran == ["ls -la", "pwd"], "read from the cells typed, not the last E: \(ran)")
        #expect(TerminalPromptTracker.commandLineParameter(["C", "cmdline_url=echo%20a%3Bb"]) == "echo a;b")
    }

    @Test("a C that can't say what ran, with no cells to read: the E after it names it")
    func commandLineAfterC() {
        let (terminal, tracker) = terminal()
        var ran: [String] = []
        tracker.onCommandRun = { ran.append($0.command) }
        // No B: nowhere to read the line from.
        feed(terminal, "\u{1B}]133;A" + Self.st + "~> make\r\n" + "\u{1B}]133;C" + Self.st)
        #expect(ran.isEmpty)
        feed(terminal, Self.e("make"))
        #expect(ran == ["make"])
        feed(terminal, Self.e("make"))
        #expect(ran == ["make"], "named once")
    }

    @Test("fish's read prompt inside a running command isn't the shell's: nothing offered there, and its D still ends it")
    func promptInsideCommand() {
        let (terminal, tracker) = terminal()
        var finished: [Int?] = []
        tracker.onCommandFinished = { finished.append($0) }
        feed(terminal, "\u{1B}]133;A;click_events=1" + Self.st + "~> " + "\u{1B}]133;B" + Self.st + "read -s secret\r\n"
             + "\u{1B}]133;C;cmdline_url=read%20-s%20secret" + Self.st + Self.e("read -s secret")
             + "\u{1B}]133;A;click_events=1" + Self.st + "read> " + "\u{1B}]133;B" + Self.st + "yes")
        #expect(tracker.phase == .running)
        #expect(tracker.currentLine() == nil, "a line offered at read's prompt: \(String(describing: tracker.currentLine()))")
        feed(terminal, "\r\n" + "\u{1B}]133;D;0" + Self.st)
        #expect(finished == [0], "the command's status")
    }

    @Test("an arrow, Tab or a ⌃ key loses the line until the next Enter or ⌃C; a one-line paste joins it")
    func lostLine() {
        let (terminal, tracker) = terminal()
        feed(terminal, "% git")
        tracker.noteSent(Array("git".utf8))
        #expect(tracker.currentLine()?.text == "git")
        tracker.noteSent([0x1B, 0x5B, 0x44])  // ←
        #expect(tracker.currentLine() == nil)
        tracker.noteSent([0x03])  // ⌃C starts again
        feed(terminal, "^C\r\n% ")
        tracker.noteSent(Array("\u{1B}[200~echo hi\u{1B}[201~".utf8))
        feed(terminal, "echo hi")
        #expect(tracker.currentLine()?.text == "echo hi")
        tracker.noteSent([0x09])
        #expect(tracker.currentLine() == nil, "Tab completes in the shell, out of sight")
    }

    // MARK: - Taking a suggestion

    @Test("→ and ⌃E take the rest; ⌥→ takes the next word; other keys take nothing")
    func keys() {
        let suffix = "tus --short"
        #expect(TerminalTypeAheadKeys.replacement(for: [0x1B, 0x5B, 0x43], suffix: suffix) == suffix)
        #expect(TerminalTypeAheadKeys.replacement(for: [0x1B, 0x4F, 0x43], suffix: suffix) == suffix)
        #expect(TerminalTypeAheadKeys.replacement(for: [0x05], suffix: suffix) == suffix)
        #expect(TerminalTypeAheadKeys.replacement(for: [0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x43], suffix: suffix) == "tus ")
        #expect(TerminalTypeAheadKeys.replacement(for: [0x1B, 0x66], suffix: suffix) == "tus ")
        #expect(TerminalTypeAheadKeys.replacement(for: Array("x".utf8), suffix: suffix) == nil)
        #expect(TerminalTypeAheadKeys.replacement(for: [0x1B, 0x5B, 0x43], suffix: "") == nil)
        #expect(TerminalTypeAheadKeys.nextWord(of: " src/app/main.swift") == " src/")
        #expect(TerminalTypeAheadKeys.nextWord(of: "app/main.swift") == "app/")
    }
}
