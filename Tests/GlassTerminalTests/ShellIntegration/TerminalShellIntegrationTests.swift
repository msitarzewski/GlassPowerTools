import Foundation
import Testing
@testable import GlassTerminal

/// The shell integration's text (D102, 2026-11-06): the line a server's start-up file gains and
/// loses, others' integrations read from that file, E's escaping, this Mac's zsh start-up folder.
/// What the scripts send is `LiveShellIntegrationTests`' to prove, in real shells.
@Suite("Shell integration: scripts, start-up files and E's escaping")
struct TerminalShellIntegrationTests {

    // MARK: Where things go

    @Test("Each shell's script and start-up file live where the plan puts them")
    func paths() {
        #expect(TerminalShellIntegration.remoteScriptPath(for: .zsh) == ".config/glasspowertools/shell-integration.zsh")
        #expect(TerminalShellIntegration.remoteScriptPath(for: .bash) == ".config/glasspowertools/shell-integration.bash")
        #expect(TerminalShellIntegration.remoteScriptPath(for: .fish) == ".config/glasspowertools/shell-integration.fish")
        #expect(TerminalShellIntegration.rcPath(for: .zsh) == ".zshrc")
        #expect(TerminalShellIntegration.rcPath(for: .bash) == ".bashrc")
        #expect(TerminalShellIntegration.rcPath(for: .fish) == ".config/fish/config.fish")
    }

    @Test("The source line is one line, marked, and sources its own shell's script only if it is there",
          arguments: TerminalShellKind.allCases)
    func sourceLine(shell: TerminalShellKind) {
        let line = TerminalShellIntegration.sourceLine(for: shell)
        #expect(!line.contains("\n") && !line.contains("\r"))
        #expect(line.hasSuffix(TerminalShellIntegration.marker))
        let script = "\"$HOME/\(TerminalShellIntegration.remoteScriptPath(for: shell))\""
        // Read first, sourced only after: twice in the line.
        #expect(line.components(separatedBy: script).count == 3)
    }

    // MARK: Adding and removing the line

    @Test("Adding the line puts it at the end once; a second add changes nothing", arguments: TerminalShellKind.allCases)
    func addingIsIdempotent(shell: TerminalShellKind) throws {
        let line = TerminalShellIntegration.sourceLine(for: shell)
        #expect(TerminalShellIntegration.addingSourceLine(to: nil, shell: shell) == line + "\n")
        #expect(TerminalShellIntegration.addingSourceLine(to: "", shell: shell) == line + "\n")

        let rc = "export EDITOR=vi\nalias ll='ls -l'\n"
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: shell))
        #expect(added == rc + line + "\n")
        #expect(TerminalShellIntegration.addingSourceLine(to: added, shell: shell) == nil)
    }

    @Test("Removing the line gives the file back; a second removal changes nothing", arguments: TerminalShellKind.allCases)
    func removingIsIdempotent(shell: TerminalShellKind) throws {
        let rc = "export EDITOR=vi\n\n# keep this comment\nalias ll='ls -l'\n"
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: shell))
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: added, shell: shell))
        #expect(Array(removed.utf8) == Array(rc.utf8))
        #expect(TerminalShellIntegration.removingSourceLine(from: removed, shell: shell) == nil)
        #expect(TerminalShellIntegration.removingSourceLine(from: rc, shell: shell) == nil)
    }

    @Test("Removal leaves every other line byte for byte, wherever the line is")
    func removalKeepsOtherLines() throws {
        let line = TerminalShellIntegration.sourceLine(for: .zsh)
        let before = "# my zshrc\n  indented\tline  \n\nunicode é ✓ 🙂\n"
        let after = "trailing spaces   \nlast line without an ending"
        let rc = before + line + "\n" + after
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: rc, shell: .zsh))
        #expect(Array(removed.utf8) == Array((before + after).utf8))
    }

    @Test("A CRLF file gains a CRLF line and loses it again exactly")
    func crlfFile() throws {
        let line = TerminalShellIntegration.sourceLine(for: .bash)
        let rc = "export A=1\r\nexport B=2\r\n"
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: .bash))
        #expect(Array(added.utf8) == Array((rc + line + "\r\n").utf8))
        #expect(TerminalShellIntegration.addingSourceLine(to: added, shell: .bash) == nil)
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: added, shell: .bash))
        #expect(Array(removed.utf8) == Array(rc.utf8))

        // Someone's CRLF file with the line in the middle: the lines around it keep their CRLFs.
        let middle = "a\r\n" + line + "\r\nb\r\n"
        let kept = try #require(TerminalShellIntegration.removingSourceLine(from: middle, shell: .bash))
        #expect(Array(kept.utf8) == Array("a\r\nb\r\n".utf8))
    }

    @Test("A file without a final line ending gains one, then a line that says so and ends with one; removal takes both")
    func noTrailingNewline() throws {
        let line = TerminalShellIntegration.sourceLine(for: .fish)
        let rc = "set -gx EDITOR vi"
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: .fish))
        let marked = String(line.dropLast(TerminalShellIntegration.marker.count))
            + TerminalShellIntegration.markerAfterAddedLineBreak
        #expect(added == rc + "\n" + marked + "\n")
        #expect(marked.contains(TerminalShellIntegration.marker))
        #expect(TerminalShellIntegration.addingSourceLine(to: added, shell: .fish) == nil)
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: added, shell: .fish))
        #expect(removed == rc)

        // The plain line last: the line before it keeps its ending, which was the file's own.
        let lineLast = "set -gx EDITOR vi\n" + line + "\n"
        #expect(TerminalShellIntegration.removingSourceLine(from: lineLast, shell: .fish) == "set -gx EDITOR vi\n")
    }

    @Test("Something appended later with >> is a line of its own, outside the app's comment, and stays when the line goes",
          arguments: TerminalShellKind.allCases, [
              "export EDITOR=vi\nesac",
              "export A=1\r\nexport B=2",
              "export EDITOR=vi\n",
              nil,
          ] as [String?])
    func appendedLater(shell: TerminalShellKind, rc: String?) throws {
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: shell))
        let appended = added + "echo appended\n"
        let lines = appended.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .newlines) }
        #expect(lines.contains("echo appended"))
        #expect(!lines.contains { $0.contains(TerminalShellIntegration.marker) && $0.contains("echo appended") })

        // Removed, the person's own last line and the appended one stay apart.
        let original = rc ?? ""
        let ending = original.contains("\r\n") ? "\r\n" : "\n"
        let kept = original.isEmpty || original.unicodeScalars.last == "\n" ? original : original + ending
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: appended, shell: shell))
        #expect(Array(removed.utf8) == Array((kept + "echo appended\n").utf8))
    }

    @Test("Adding then removing gives the file back byte for byte",
          arguments: TerminalShellKind.allCases, [
              "export EDITOR=vi\nalias ll='ls -l'\n",
              "export EDITOR=vi\nesac",
              "export A=1\r\nexport B=2",
              "export A=1\r\nexport B=2\r\n",
              "",
              nil,
          ] as [String?])
    func addThenRemove(shell: TerminalShellKind, rc: String?) throws {
        let added = try #require(TerminalShellIntegration.addingSourceLine(to: rc, shell: shell))
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: added, shell: shell))
        // No file at first comes back empty: removing can only say what the file holds.
        #expect(Array(removed.utf8) == Array((rc ?? "").utf8))
    }

    @Test("Only the app's line goes: an edited copy of it does, a comment naming the app and another shell's line don't")
    func onlyTheLine() throws {
        let line = TerminalShellIntegration.sourceLine(for: .zsh)
        let comment = "\(TerminalShellIntegration.marker) is something I tried once\n"
        let bashLine = TerminalShellIntegration.sourceLine(for: .bash) + "\n"
        let edited = "  " + line.replacingOccurrences(of: "; then", with: ";  then") + "  \n"
        let rc = comment + bashLine + edited
        let removed = try #require(TerminalShellIntegration.removingSourceLine(from: rc, shell: .zsh))
        #expect(removed == comment + bashLine)
        #expect(TerminalShellIntegration.addingSourceLine(to: rc, shell: .zsh) == nil)
        #expect(TerminalShellIntegration.addingSourceLine(to: comment + bashLine, shell: .zsh) != nil)
    }

    // MARK: Others' integrations

    @Test("Each terminal's own loading line is recognized", arguments: [
        ("iTerm2", #"test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh""#),
        ("iTerm2", "source ~/.iterm2_shell_integration.fish"),
        ("VS Code", #"[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)""#),
        ("VS Code", #"string match -q "$TERM_PROGRAM" "vscode"; and . (code --locate-shell-integration-path fish)"#),
        ("Ghostty", #"source "$GHOSTTY_RESOURCES_DIR"/shell-integration/zsh/ghostty-integration"#),
        ("Ghostty", #"builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash""#),
        ("WezTerm", "source ~/.config/wezterm/wezterm.sh"),
        ("kitty", #"export KITTY_SHELL_INTEGRATION="enabled""#),
        ("kitty", #"source "$KITTY_INSTALLATION_DIR/shell-integration/bash/kitty.bash""#),
    ])
    func otherIntegrationFound(name: String, line: String) {
        let rc = "export PATH=\"$HOME/bin:$PATH\"\n" + line + "\nalias ll='ls -l'\n"
        #expect(TerminalShellIntegration.otherIntegrations(in: rc) == [name])
    }

    @Test("A commented-out line, the app's own line and an ordinary file name no other integration")
    func noOtherIntegration() {
        let rc = """
            # source ~/.iterm2_shell_integration.zsh
              #  source ~/.config/wezterm/wezterm.sh
            \(TerminalShellIntegration.sourceLine(for: .zsh))
            export PATH="$HOME/bin:$PATH"
            alias ghostty-notes='vi ~/notes'
            """
        #expect(TerminalShellIntegration.otherIntegrations(in: rc).isEmpty)
        #expect(TerminalShellIntegration.otherIntegrations(in: "").isEmpty)
    }

    @Test("Several at once are named in a fixed order")
    func severalOtherIntegrations() {
        let rc = "source ~/.config/wezterm/wezterm.sh\nsource ~/.iterm2_shell_integration.bash\n"
        #expect(TerminalShellIntegration.otherIntegrations(in: rc) == ["iTerm2", "WezTerm"])
    }

    // MARK: E's escaping

    @Test("E escapes a backslash, ';' and control characters as VS Code does, and nothing else", arguments: [
        ("echo a;b", #"echo a\x3bb"#),
        (#"printf '%s\n' x"#, #"printf '%s\\n' x"#),
        (#"a\\b"#, #"a\\\\b"#),
        ("for i in 1 2\ndo echo $i\ndone", #"for i in 1 2\x0ado echo $i\x0adone"#),
        ("a\tb\rc", #"a\x09b\x0dc"#),
        ("\u{1b}[31mred\u{7f}\u{01}", #"\x1b[31mred\x7f\x01"#),
        ("echo 'héllo wörld' ✓ 🙂 日本", "echo 'héllo wörld' ✓ 🙂 日本"),
        ("", ""),
    ])
    func escaping(line: String, escaped: String) {
        #expect(TerminalShellIntegration.escapedCommandLine(line) == escaped)
        #expect(TerminalShellIntegration.commandLine(escaped: escaped) == line)
    }

    @Test("Reading E back refuses a stray backslash and reads either case of hex")
    func readingEscapes() {
        #expect(TerminalShellIntegration.commandLine(escaped: #"a\qb"#) == nil)
        #expect(TerminalShellIntegration.commandLine(escaped: #"a\x3"#) == nil)
        #expect(TerminalShellIntegration.commandLine(escaped: #"trailing\"#) == nil)
        #expect(TerminalShellIntegration.commandLine(escaped: #"\x3B\x0A"#) == ";\n")
    }

    // MARK: This Mac's zsh

    @Test("The local start-up folder holds .zshenv and the zsh script, and .zshenv hands ZDOTDIR back first")
    func localStartupFiles() throws {
        let files = TerminalShellIntegration.localZshStartupFiles()
        #expect(Set(files.keys) == [".zshenv", TerminalShellIntegration.localZshScriptName])
        #expect(files[TerminalShellIntegration.localZshScriptName] == TerminalShellIntegration.script(for: .zsh))
        let zshenv = try #require(files[".zshenv"])
        let handBack = try #require(zshenv.range(of: "GLASS_USER_ZDOTDIR\""))
        let source = try #require(zshenv.range(of: "'builtin' 'source'"))
        #expect(handBack.lowerBound < source.lowerBound)
        #expect(zshenv.contains(TerminalShellIntegration.localZshScriptName))
    }

    @Test("The local environment points ZDOTDIR at the folder and hands the person's own over")
    func localEnvironment() {
        let folder = "/tmp/startup"
        let plain = TerminalShellIntegration.localZshEnvironment(
            startupFolder: folder, inherited: ["HOME": "/Users/ann", "PATH": "/usr/bin:/bin"])
        #expect(plain == ["HOME": "/Users/ann", "PATH": "/usr/bin:/bin", "ZDOTDIR": folder])

        let own = TerminalShellIntegration.localZshEnvironment(
            startupFolder: folder, inherited: ["HOME": "/Users/ann", "ZDOTDIR": "/Users/ann/.config/zsh"])
        #expect(own == ["HOME": "/Users/ann", "ZDOTDIR": folder, "GLASS_USER_ZDOTDIR": "/Users/ann/.config/zsh"])

        // One of the app's own terminals' environments, handed down: the folder isn't the person's.
        let handedDown = TerminalShellIntegration.localZshEnvironment(
            startupFolder: folder, inherited: ["ZDOTDIR": folder + "/", "GLASS_USER_ZDOTDIR": "/Users/ann/zsh"])
        #expect(handedDown == ["ZDOTDIR": folder, "GLASS_USER_ZDOTDIR": "/Users/ann/zsh"])
        let stale = TerminalShellIntegration.localZshEnvironment(
            startupFolder: folder, inherited: ["GLASS_USER_ZDOTDIR": "/Users/ann/old"])
        #expect(stale == ["ZDOTDIR": folder])
    }

    @Test("In tmux the integration is the session's own, and the server keeps the person's ZDOTDIR")
    func tmuxSplit() {
        let folder = "/tmp/startup"
        // No ZDOTDIR of their own: the session gets the folder; the rest has none.
        let plain = TerminalShellIntegration.tmuxSessionVariables(["HOME": "/Users/ann", "ZDOTDIR": folder], startupFolder: folder)
        #expect(plain.session == ["ZDOTDIR": folder])
        #expect(plain.rest == ["HOME": "/Users/ann"])
        // Their own: the session gets both; the server and clients get theirs back.
        let own = TerminalShellIntegration.tmuxSessionVariables(
            ["HOME": "/Users/ann", "ZDOTDIR": folder + "/", "GLASS_USER_ZDOTDIR": "/Users/ann/.config/zsh"], startupFolder: folder)
        #expect(own.session == ["ZDOTDIR": folder + "/", "GLASS_USER_ZDOTDIR": "/Users/ann/.config/zsh"])
        #expect(own.rest == ["HOME": "/Users/ann", "ZDOTDIR": "/Users/ann/.config/zsh"])
        // Not integrated (another shell, the setting off): nothing moves.
        let mine = TerminalShellIntegration.tmuxSessionVariables(["ZDOTDIR": "/Users/ann/zsh"], startupFolder: folder)
        #expect(mine.session.isEmpty)
        #expect(mine.rest == ["ZDOTDIR": "/Users/ann/zsh"])
    }

    // MARK: Nothing private

    @Test("The scripts and the start-up folder name no machine, person or private folder")
    func nothingPrivate() throws {
        var texts = TerminalShellKind.allCases.map { TerminalShellIntegration.script(for: $0) }
        texts += TerminalShellIntegration.localZshStartupFiles().values
        texts += TerminalShellKind.allCases.map { TerminalShellIntegration.sourceLine(for: $0) }
        // This Mac's own, found as the test runs rather than written here. A simulator's test process has no user
        // name and a home of its own; the Mac's home is `SIMULATOR_HOST_HOME` (2026-11-06: an empty name looked
        // for "//", which every `file://` holds).
        let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
        let homes = [NSHomeDirectory()] + (hostHome.map { [$0] } ?? [])
        let user = NSUserName().isEmpty ? hostHome.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "" : NSUserName()
        try #require(!user.isEmpty, "whose name to look for")
        let host = ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? ""
        let address = try! NSRegularExpression(pattern: #"\b\d{1,3}(\.\d{1,3}){3}\b"#)
        for text in texts {
            for folder in ["/Users/", "/home/", "/private/", "/var/folders/", "/Volumes/", "/root/"] {
                #expect(!text.contains(folder), "names \(folder)")
            }
            for home in homes { #expect(!text.contains(home)) }
            #expect(!text.contains("/\(user)/"))
            if host.count > 3 { #expect(!text.localizedCaseInsensitiveContains(host)) }
            #expect(address.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil)
        }
    }
}
