//
//  TerminalShellIntegration.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the shell integration that tells the terminal where the prompt
//  ends and typing begins, so the app knows the line being typed. `tasks/2026-11/2026-11-06_type-ahead.md`,
//  "Knowing the line" and "Installing the integration".
//
//  **The marks are other terminals' marks.** OSC 133 A (a prompt starts), B (typing begins), C (a
//  command starts) and D;<status> (it ended) are what iTerm2, Ghostty, kitty and WezTerm send;
//  OSC 633 E;<command line> is VS Code's; OSC 7 is the folder. Every one ends with BEL. A shell that
//  already carries one of those terminals' integrations is understood as it is, so these scripts
//  stand aside there rather than mark every prompt twice.
//
//  **fish 4 marks its own prompts.** fish 4.0 and later send A, C (with `cmdline_url=`) and D
//  themselves, and B from 4.3, all ended with ST (ESC \) rather than BEL; fish 4.0 also reports the
//  folder. There the script adds only what fish leaves out: E always, and B before 4.3. fish sends
//  its C before any `fish_preexec` handler runs, so there E arrives just after C, not before it.
//
//  **This Mac's zsh** gets the integration without anyone installing it: the terminal starts zsh
//  with ZDOTDIR pointing at a small folder of the app's (`localZshStartupFiles`), as VS Code,
//  Ghostty and kitty do. That folder's .zshenv puts the person's own ZDOTDIR back at once, so
//  their files, and the system's (macOS's /etc/zshrc puts HISTFILE in `${ZDOTDIR:-$HOME}`), never
//  see the app's folder; zsh reads their .zprofile, .zshrc and .zlogin itself; the integration
//  loads at the first prompt, after all of them.
//
//  **Servers** get it only when someone asks: the coordinator writes `script(for:)` to
//  `remoteScriptPath(for:)` over SFTP and the start-up file `addingSourceLine(to:shell:)` returns;
//  removing undoes both. Everything here is text in, text out; nothing here touches a file.
//

import Foundation

nonisolated enum TerminalShellIntegration {

    // MARK: Scripts

    /// The script for a shell.
    static func script(for shell: TerminalShellKind) -> String {
        switch shell {
        case .zsh: zshScript
        case .bash: bashScript
        case .fish: fishScript
        }
    }

    /// Where a server keeps the script, relative to home: `.config/glasspowertools/shell-integration.<zsh|bash|fish>`.
    static func remoteScriptPath(for shell: TerminalShellKind) -> String {
        ".config/glasspowertools/shell-integration.\(shell.rawValue)"
    }

    /// The start-up file the source line goes in, relative to home: `.zshrc`, `.bashrc`, `.config/fish/config.fish`.
    ///
    /// bash reads .bashrc in an interactive shell that isn't a login shell; a login shell reads
    /// .bash_profile, which on most Linux systems reads .bashrc in turn. A server whose
    /// .bash_profile doesn't (macOS has none at all by default) won't load it over SSH.
    static func rcPath(for shell: TerminalShellKind) -> String {
        switch shell {
        case .zsh: ".zshrc"
        case .bash: ".bashrc"
        case .fish: ".config/fish/config.fish"
        }
    }

    // MARK: The source line

    /// What marks the line as the app's, at its end: a comment, so it costs the shell nothing, and
    /// so a CRLF file's stray carriage return falls inside it rather than in a command.
    static let marker = "# Glass Power Tools shell integration"

    /// The marker on a line added to a file whose last line had no ending: the line break before
    /// the source line is the app's too, so removing the line takes it away again. It begins with
    /// `marker`, so anything looking for the marker finds this one as well.
    static let markerAfterAddedLineBreak = marker + " (it also added the line break before this line)"

    /// The one marked line added to that file (a comment marker on the same line; it sources the script only if it exists).
    ///
    /// `if`, not `&&`: as the last line of a start-up file, a `[ -r ] &&` that found no script
    /// would leave the first prompt's `$?` at 1.
    static func sourceLine(for shell: TerminalShellKind) -> String {
        sourceLine(for: shell, marker: marker)
    }

    private static func sourceLine(for shell: TerminalShellKind, marker: String) -> String {
        let path = "\"$HOME/\(remoteScriptPath(for: shell))\""
        return switch shell {
        case .zsh: "if [[ -r \(path) ]]; then source \(path); fi \(marker)"
        case .bash: "if [ -r \(path) ]; then . \(path); fi \(marker)"
        case .fish: "if test -r \(path); source \(path); end \(marker)"
        }
    }

    /// The start-up file with the line added at the end, once. Nil if it is already there. A nil `rc` means no file yet.
    ///
    /// The line ends the way the file's lines do (CRLF if it has any), so the file ends with a line
    /// break and whatever is appended later (`echo … >> ~/.bashrc`) is a line of its own. A file
    /// whose last line had no ending gets one before the source line, and the source line says so
    /// (`markerAfterAddedLineBreak`), so removing it gives that file back byte for byte (a server's
    /// .bashrc ending "…esac" gained a newline it never had, 2026-11-06).
    static func addingSourceLine(to rc: String?, shell: TerminalShellKind) -> String? {
        guard let rc, !rc.isEmpty else { return sourceLine(for: shell) + "\n" }
        if lines(of: rc).contains(where: { sourceLineForm($0, shell: shell) != nil }) { return nil }
        let ending = rc.contains("\r\n") ? "\r\n" : "\n"
        if rc.unicodeScalars.last != "\n" {
            return rc + ending + sourceLine(for: shell, marker: markerAfterAddedLineBreak) + ending
        }
        return rc + sourceLine(for: shell) + ending
    }

    /// The start-up file with that line, and only it, removed. Nil if it isn't there.
    ///
    /// Every other line stays byte for byte, endings included, but one: a line that says the app
    /// added the line break before it takes that break with it, when it is still the file's last
    /// line. Once something follows it, that break keeps the line before from running into what
    /// follows, so it stays. A line counts as the app's when it ends with either marker and names
    /// this shell's script, so one someone edited a little is still found and a comment that merely
    /// mentions the app is not.
    static func removingSourceLine(from rc: String, shell: TerminalShellKind) -> String? {
        let all = lines(of: rc)
        let forms = all.map { sourceLineForm($0, shell: shell) }
        guard forms.contains(where: { $0 != nil }) else { return nil }
        var kept = zip(all, forms).filter { $0.1 == nil }.map(\.0)
        let lastLines = forms.reversed().prefix { $0 != nil }
        if lastLines.contains(.afterAddedLineBreak), let previous = kept.popLast() {
            kept.append(withoutEnding(previous))
        }
        return kept.joined()
    }

    /// The app's source line, as added to a file that ended with a line break or to one that didn't.
    private enum SourceLineForm { case plain, afterAddedLineBreak }

    /// A line without its ending, "\r\n" or "\n".
    private static func withoutEnding(_ line: String) -> String {
        var scalars = line.unicodeScalars
        guard scalars.last == "\n" else { return line }
        scalars.removeLast()
        if scalars.last == "\r" { scalars.removeLast() }
        return String(scalars)
    }

    /// A file's lines, each with its own ending, so joining them gives the file back exactly.
    /// Split on scalars: Swift counts "\r\n" as one character, which a split on "\n" would miss.
    private static func lines(of text: String) -> [String] {
        var lines: [String] = []
        var line = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            line.append(scalar)
            if scalar == "\n" {
                lines.append(String(line))
                line = String.UnicodeScalarView()
            }
        }
        if !line.isEmpty { lines.append(String(line)) }
        return lines
    }

    private static func sourceLineForm(_ line: String, shell: TerminalShellKind) -> SourceLineForm? {
        let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.contains("glasspowertools/shell-integration.\(shell.rawValue)") else { return nil }
        if content.hasSuffix(markerAfterAddedLineBreak) { return .afterAddedLineBreak }
        return content.hasSuffix(marker) ? .plain : nil
    }

    // MARK: Others' integrations

    /// Other terminals' integrations a start-up file already loads, by name ("iTerm2", "VS Code", "Ghostty", "WezTerm", "kitty").
    ///
    /// Read from the lines that load them as each terminal's own instructions write them; a
    /// commented-out line doesn't count. The scripts check again in the running shell, where an
    /// integration loaded some other way shows itself.
    static func otherIntegrations(in rc: String) -> [String] {
        let active = lines(of: rc)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return otherIntegrationSigns.compactMap { name, loads in active.contains(where: loads) ? name : nil }
    }

    private static let otherIntegrationSigns: [(name: String, loads: @Sendable (String) -> Bool)] = [
        // ~/.iterm2_shell_integration.zsh, .bash or .fish.
        ("iTerm2", { $0.contains("iterm2_shell_integration") || $0.contains("iterm_shell_integration_installed") }),
        // `code --locate-shell-integration-path zsh`, or the scripts by name.
        ("VS Code", { $0.contains("locate-shell-integration-path") || $0.contains("shellintegration-")
            || $0.contains("shellintegration.fish") || $0.contains("vscode_shell_integration") }),
        // "$GHOSTTY_RESOURCES_DIR"/shell-integration/zsh/ghostty-integration, …/bash/ghostty.bash, …/ghostty-shell-integration.fish.
        ("Ghostty", { $0.contains("ghostty") && ($0.contains("shell-integration") || $0.contains("ghostty-integration")) }),
        // wezterm.sh, wherever it was copied.
        ("WezTerm", { $0.contains("wezterm.sh") }),
        // "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration, …/bash/kitty.bash, …/kitty-shell-integration.fish.
        ("kitty", { $0.contains("kitty_shell_integration") || $0.contains("kitty-integration")
            || ($0.contains("kitty") && $0.contains("shell-integration")) }),
    ]

    // MARK: The command line (OSC 633 E)

    /// The command line as E carries it, as VS Code writes it: a backslash doubled, and ";" and
    /// every control character (below 0x20, and 0x7f) as `\xNN` in lowercase hex. Everything else,
    /// unicode included, as it is. The scripts produce exactly this; the live tests compare them.
    static func escapedCommandLine(_ line: String) -> String {
        var escaped = ""
        for scalar in line.unicodeScalars {
            switch scalar.value {
            case 0x5c: escaped += "\\\\"
            case 0x3b, 0..<0x20, 0x7f: escaped += String(format: "\\x%02x", scalar.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    /// E's text back as the command line: `\\` a backslash, `\xNN` that character. Nil for a stray
    /// backslash, which no integration that follows VS Code's rules writes.
    static func commandLine(escaped: String) -> String? {
        var line = String.UnicodeScalarView()
        var scalars = escaped.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\\" else { line.append(scalar); continue }
            switch scalars.next() {
            case "\\": line.append("\\")
            case "x":
                guard let high = scalars.next(), let low = scalars.next(),
                      let value = UInt32(String([Character(high), Character(low)]), radix: 16),
                      let decoded = Unicode.Scalar(value) else { return nil }
                line.append(decoded)
            default: return nil
            }
        }
        return String(line)
    }

    // MARK: This Mac's zsh

    /// The name of the integration script inside the local start-up folder.
    static let localZshScriptName = "shell-integration.zsh"

    /// This Mac's zsh: the files (name → contents) of a ZDOTDIR folder. It puts back the person's own ZDOTDIR
    /// (handed over in `GLASS_USER_ZDOTDIR`; unset means their home), reads their .zshenv, .zprofile (login shells),
    /// .zshrc (interactive) and .zlogin from there as zsh would, then loads the integration. Their own files must see
    /// their own ZDOTDIR, not ours.
    ///
    /// Only .zshenv: it hands ZDOTDIR back before zsh reads anything else, so zsh itself reads the
    /// person's .zprofile, .zshrc and .zlogin from their folder — exactly as it would without the
    /// app — and the integration's script, beside it, loads at the first prompt.
    static func localZshStartupFiles() -> [String: String] {
        [".zshenv": localZshEnv, localZshScriptName: zshScript]
    }

    /// The environment for starting this Mac's zsh with that folder (written to `startupFolder`).
    ///
    /// The person's own ZDOTDIR, if they have one, travels in GLASS_USER_ZDOTDIR. One that already
    /// names the app's folder (an environment handed down from one of its terminals) is not theirs.
    static func localZshEnvironment(startupFolder: String, inherited: [String: String]) -> [String: String] {
        var environment = inherited
        let folder = standardized(startupFolder)
        environment["GLASS_USER_ZDOTDIR"] = nil
        if let own = inherited["ZDOTDIR"] {
            if standardized(own) != folder {
                environment["GLASS_USER_ZDOTDIR"] = own
            } else if let handed = inherited["GLASS_USER_ZDOTDIR"], standardized(handed) != folder {
                environment["GLASS_USER_ZDOTDIR"] = handed
            }
        }
        environment["ZDOTDIR"] = startupFolder
        return environment
    }

    /// `localZshEnvironment`'s result split for a terminal in tmux: what the session itself is given
    /// (`new-session -e`), and the rest, for the tmux server and its clients, with the person's own
    /// ZDOTDIR back where they had one.
    ///
    /// tmux gives a new session's shell the server's environment, never its client's beyond
    /// `update-environment`, so a ZDOTDIR handed only to the client reached no shell in tmux: no tab
    /// in tmux marked its prompt, and type-ahead offered nothing there (2026-11-06, the owner: "I'm not
    /// seeing any auto complete at all"). And a server started with it would hand the app's folder to
    /// every session on it, those started from another terminal too.
    static func tmuxSessionVariables(_ environment: [String: String], startupFolder: String)
        -> (session: [String: String], rest: [String: String]) {
        guard let zdotdir = environment["ZDOTDIR"], standardized(zdotdir) == standardized(startupFolder) else {
            return ([:], environment)
        }
        var session = ["ZDOTDIR": zdotdir]
        var rest = environment
        rest["ZDOTDIR"] = nil
        rest["GLASS_USER_ZDOTDIR"] = nil
        if let own = environment["GLASS_USER_ZDOTDIR"] {
            session["GLASS_USER_ZDOTDIR"] = own
            rest["ZDOTDIR"] = own
        }
        return (session, rest)
    }

    private static func standardized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    // MARK: zsh

    private static let localZshEnv = ##"""
    # Glass Power Tools: zsh in this Mac's terminals.
    #
    # The terminal starts zsh with ZDOTDIR set to this folder. This file puts the person's own
    # ZDOTDIR back at once (GLASS_USER_ZDOTDIR; unset means their home), reads their .zshenv from
    # there, and leaves zsh to read their .zprofile, .zshrc and .zlogin as it always does. The shell
    # integration beside this file loads at the first prompt, after all of them.
    #
    # Words an alias could stand for are quoted: aliases may be defined already.

    if [[ -n "${GLASS_USER_ZDOTDIR+X}" ]]; then
        'builtin' 'export' ZDOTDIR="$GLASS_USER_ZDOTDIR"
        'builtin' 'unset' 'GLASS_USER_ZDOTDIR'
    else
        'builtin' 'unset' 'ZDOTDIR'
    fi

    {
        'builtin' 'typeset' __glass_si_file="${ZDOTDIR-$HOME}/.zshenv"
        # zsh skips a start-up file it can't read, and so does this; and never this file itself.
        if [[ -r "$__glass_si_file" && ! "$__glass_si_file" -ef "${(%):-%x}" ]]; then
            'builtin' 'source' '--' "$__glass_si_file"
        fi
    } always {
        if [[ -o 'interactive' ]]; then
            'builtin' 'typeset' -g __glass_si_script="${${(%):-%x}:A:h}/shell-integration.zsh"
            # At the first prompt, once .zprofile, .zshrc and .zlogin have run.
            __glass_si_load() {
                'builtin' 'local' -i __glass_status=$? __glass_hooked=${precmd_functions[(Ie)__glass_si_precmd]:-0}
                precmd_functions=(${precmd_functions:#__glass_si_load})
                'builtin' 'unfunction' '__glass_si_load'
                [[ -r "$__glass_si_script" ]] && 'builtin' 'source' '--' "$__glass_si_script"
                'builtin' 'unset' '__glass_si_script'
                # This prompt's own marks: the integration's hook joined after this round of hooks began.
                if (( ! __glass_hooked && ${precmd_functions[(Ie)__glass_si_precmd]:-0} )); then
                    () { 'builtin' 'return' $1 } $__glass_status
                    __glass_si_precmd
                fi
                'builtin' 'return' $__glass_status
            }
            'builtin' 'typeset' -ga precmd_functions
            precmd_functions+=('__glass_si_load')
        fi
        'builtin' 'unset' '__glass_si_file'
    }
    """##

    private static let zshScript = ##"""
    # Glass Power Tools shell integration for zsh.
    #
    # It tells the terminal where the prompt and each command begin and end, so Glass Power Tools
    # knows the line being typed and can offer the rest of it. It sends the marks iTerm2, VS Code,
    # Ghostty, WezTerm and kitty use: OSC 133 A where the prompt starts, B where typing begins, C as a
    # command starts and D with its exit status when it ends; VS Code's OSC 633 E with the command
    # line; and OSC 7 with the folder. It prints nothing else and changes nothing else: the prompt
    # looks the same, $? is kept, and other hooks keep running.
    #
    # It loads once per shell, only in an interactive shell on a terminal, and stands aside where
    # another terminal's integration already marks the prompt. To remove it, delete the line that
    # sources this file from ~/.zshrc, then this file; Glass Power Tools' settings can do both.

    () {
        builtin emulate -L zsh -o no_aliases
        # Whether stdout is a terminal is asked at the first prompt instead: powerlevel10k's instant
        # prompt sends it to a file while .zshrc runs.
        [[ -o interactive && $TERM != dumb && $TERM != linux ]] || builtin return 0
        if (( ${+GLASS_SHELL_INTEGRATION} )); then
            # Loaded already. One handed down from a parent shell isn't this shell's: it loads its own.
            [[ ${(t)GLASS_SHELL_INTEGRATION} == *export* ]] || builtin return 0
            builtin unset GLASS_SHELL_INTEGRATION
        fi
        builtin typeset -g GLASS_SHELL_INTEGRATION=1

        # Another terminal's integration marks prompts already: iTerm2's, VS Code's, Ghostty's,
        # kitty's or WezTerm's, or powerlevel10k's own when it is turned on.
        __glass_si_other_integration() {
            [[ -n ${ITERM_SHELL_INTEGRATION_INSTALLED-} || -n ${VSCODE_SHELL_INTEGRATION-} ||
               ${POWERLEVEL9K_TERM_SHELL_INTEGRATION-} == true ]] && builtin return 0
            (( ${+functions[iterm2_precmd]} || ${+functions[__vsc_precmd]} ||
               ${+functions[_ghostty_deferred_init]} || ${+functions[_ghostty_precmd]} ||
               ${+functions[_ksi_deferred_init]} || ${+functions[_ksi_precmd]} ||
               ${precmd_functions[(Ie)__wezterm_semantic_precmd]:-0} ))
        }

        # The command line as OSC 633 E carries it, in REPLY: a backslash doubled, and ";" and every
        # control character as \xNN, as VS Code writes them.
        __glass_si_escape() {
            builtin emulate -L zsh -o no_aliases
            builtin local value=${1//\\/\\\\} char hex
            builtin local -i code
            value=${value//;/\\x3b}
            for code in {1..31} 127; do
                char=${(#)code}
                [[ $value == *$char* ]] || continue
                builtin printf -v hex '\\x%02x' $code
                value=${value//$char/$hex}
            done
            REPLY=$value
        }

        # OSC 7: this machine and the folder, percent-encoded.
        __glass_si_report_folder() {
            builtin emulate -L zsh -o no_aliases -o extended_glob -o no_multibyte
            builtin local MATCH MBEGIN MEND
            builtin local folder=${PWD//(#m)[^A-Za-z0-9\/._~-]/%${(l:2::0:)$(( [##16] #MATCH ))}}
            builtin local host=${HOST//(#m)[^A-Za-z0-9._-]/%${(l:2::0:)$(( [##16] #MATCH ))}}
            builtin print -rn -- $'\e]7;file://'$host$folder$'\a'
        }

        # B at the very end of the prompt, inside %{ %} so it takes no room. A theme may build PS1
        # afresh before every prompt; then it is added again.
        __glass_si_mark_prompt_end() {
            [[ -o prompt_percent ]] || builtin return 0
            [[ -n ${__glass_si_marked_ps1+x} && $PS1 == "$__glass_si_marked_ps1" ]] && builtin return 0
            builtin local ps1=${PS1%"$__glass_si_b"}
            builtin local trail=${ps1##*[^%]}
            builtin typeset -g __glass_si_clean_ps1=$ps1
            # A lone % at the end would swallow the mark's %{.
            (( ${#trail} % 2 )) && ps1+=%
            builtin typeset -g __glass_si_marked_ps1=$ps1$__glass_si_b
            PS1=$__glass_si_marked_ps1
        }

        __glass_si_precmd() {
            builtin local -i ret=$?
            builtin emulate -L zsh -o no_aliases
            if [[ ! -t 1 ]] || __glass_si_other_integration; then
                __glass_si_stand_aside
                builtin return $ret
            fi
            # Some plugins run the precmd hooks from a widget to redraw the prompt: no prompt starts.
            if ! builtin zle; then
                if (( __glass_si_ran )); then
                    builtin print -rn -- $'\e]133;D;'$ret$'\a'
                    __glass_si_ran=0
                fi
                __glass_si_report_folder
                builtin print -rn -- $'\e]133;A\a'
            fi
            __glass_si_mark_prompt_end
            # Last among the hooks, so whatever builds the prompt has built it before B goes on.
            [[ ${precmd_functions[-1]} == __glass_si_precmd ]] ||
                precmd_functions=(${precmd_functions:#__glass_si_precmd} __glass_si_precmd)
            [[ ${preexec_functions[-1]} == __glass_si_preexec ]] ||
                preexec_functions=(${preexec_functions:#__glass_si_preexec} __glass_si_preexec)
            builtin return $ret
        }

        __glass_si_preexec() {
            builtin emulate -L zsh -o no_aliases
            # Other hooks see the prompt as it was; the next prompt marks it again.
            [[ -n ${__glass_si_marked_ps1+x} && $PS1 == "$__glass_si_marked_ps1" ]] && PS1=$__glass_si_clean_ps1
            # $1 is the line as typed. It is empty only when history is off.
            if [[ -n $1 ]]; then
                builtin local REPLY
                __glass_si_escape "$1"
                builtin print -rn -- $'\e]633;E;'$REPLY$'\a'
            fi
            builtin print -rn -- $'\e]133;C\a'
            __glass_si_ran=1
        }

        # Where typing begins, when the prompt just drawn didn't carry B: a theme rebuilt PS1 after
        # this hook ran, as on the first prompt of this Mac's terminals. The prompt is drawn by now
        # and the cursor waits where typing begins. Not on a continuation line or in vared.
        __glass_si_line_init() {
            [[ $CONTEXT == start && $PS1 != *"$__glass_si_b" ]] || builtin return 0
            builtin print -rn -- $'\e]133;B\a'
        }

        # Out of the way, for another terminal's integration or a shell that isn't on a terminal.
        __glass_si_stand_aside() {
            add-zsh-hook -d precmd __glass_si_precmd
            add-zsh-hook -d preexec __glass_si_preexec
            (( __glass_si_line_hooked )) && add-zle-hook-widget -d line-init __glass_si_line_init
            __glass_si_line_hooked=0
            [[ -n ${__glass_si_marked_ps1+x} && $PS1 == "$__glass_si_marked_ps1" ]] && PS1=$__glass_si_clean_ps1
            builtin unset __glass_si_marked_ps1 __glass_si_clean_ps1
        }

        __glass_si_other_integration && builtin return 0
        builtin typeset -gi __glass_si_ran=0 __glass_si_line_hooked=0
        builtin typeset -g __glass_si_b=$'%{\e]133;B\a%}'
        builtin autoload -Uz add-zsh-hook
        add-zsh-hook precmd __glass_si_precmd
        add-zsh-hook preexec __glass_si_preexec
        # zsh 5.3 and later.
        if builtin autoload +X -Uz add-zle-hook-widget 2>/dev/null; then
            add-zle-hook-widget line-init __glass_si_line_init && __glass_si_line_hooked=1
        fi
    }
    """##

    // MARK: bash

    private static let bashScript = ##"""
    # Glass Power Tools shell integration for bash.
    #
    # It tells the terminal where the prompt and each command begin and end, so Glass Power Tools
    # knows the line being typed and can offer the rest of it. It sends the marks iTerm2, VS Code,
    # Ghostty, WezTerm and kitty use: OSC 133 A where the prompt starts, B where typing begins, C as a
    # command starts and D with its exit status when it ends; VS Code's OSC 633 E with the command
    # line; and OSC 7 with the folder. It prints nothing else and changes nothing else: the prompt
    # looks the same, $? is kept, and PROMPT_COMMAND keeps running.
    #
    # bash 4.4 and later send every mark. Older bash, macOS's 3.2 among them, has no PS0 to show
    # where a command starts, so it sends A, B and D only, and D only for a command history kept.
    #
    # It loads once per shell, only in an interactive shell on a terminal, and stands aside where
    # another terminal's integration already marks the prompt. To remove it, delete the line that
    # sources this file from ~/.bashrc, then this file; Glass Power Tools' settings can do both.

    if [[ $- == *i* ]] && [ -t 1 ] && [[ ${TERM-} != dumb && ${TERM-} != linux ]]; then

    # Another terminal's integration marks prompts already: iTerm2's, VS Code's, Ghostty's, kitty's
    # or WezTerm's.
    __glass_si_other_integration() {
        [[ -n ${ITERM_SHELL_INTEGRATION_INSTALLED-} || -n ${VSCODE_SHELL_INTEGRATION-} ]] && builtin return 0
        builtin declare -F __iterm2_prompt_command >/dev/null && builtin return 0
        builtin declare -F __vsc_prompt_cmd >/dev/null && builtin return 0
        builtin declare -F __ghostty_precmd >/dev/null && builtin return 0
        builtin declare -F _ksi_prompt_command >/dev/null && builtin return 0
        [[ " ${precmd_functions[*]-} " == *" __wezterm_semantic_precmd "* ]] && builtin return 0
        builtin return 1
    }

    # The command line as OSC 633 E carries it, in __glass_si_reply: a backslash doubled, and ";"
    # and every control character as \xNN, as VS Code writes them.
    __glass_si_escape() {
        builtin local b='\' value code octal char hex
        value=${1//"$b"/"$b$b"}
        value=${value//;/"${b}x3b"}
        if [[ $value == *["$__glass_si_controls"]* ]]; then
            code=1
            while (( code < 128 )); do
                (( code == 32 )) && code=127
                octal=$(( code / 64 ))$(( code / 8 % 8 ))$(( code % 8 ))
                builtin printf -v char "\\$octal"
                if [[ $value == *"$char"* ]]; then
                    builtin printf -v hex '\\x%02x' "$code"
                    value=${value//"$char"/"$hex"}
                fi
                code=$(( code + 1 ))
            done
        fi
        __glass_si_reply=$value
    }

    # A path percent-encoded byte by byte, for OSC 7. Run with LC_ALL=C, so a character is a byte.
    __glass_si_percent() {
        builtin local path="$1" encoded= char code i=0
        while (( i < ${#path} )); do
            char=${path:i:1}
            case $char in
                [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._~-]) encoded=$encoded$char ;;
                *)
                    builtin printf -v code '%d' "'$char"
                    # bash 3.2 reads a byte above 0x7f as negative.
                    (( code < 0 )) && code=$(( code + 256 ))
                    builtin printf -v char '%%%02X' "$code"
                    encoded=$encoded$char
                    ;;
            esac
            i=$(( i + 1 ))
        done
        builtin printf '%s' "$encoded"
    }

    # The letters every bracket below lists one by one: a range like A-Z follows the locale's
    # collation in older bash, where it can take in letters with accents.
    __glass_si_url() {
        case $1 in
            *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._~-]*)
                __glass_si_reply=$(LC_ALL=C; __glass_si_percent "$1") ;;
            *) __glass_si_reply=$1 ;;
        esac
    }

    # OSC 7: this machine and the folder. Encoded again only when the folder changes.
    __glass_si_report_folder() {
        if [[ $PWD != "${__glass_si_folder-}" ]]; then
            __glass_si_folder=$PWD
            __glass_si_url "$PWD"
            __glass_si_folder_url=$__glass_si_reply
        fi
        builtin printf '\033]7;file://%s%s\007' "$__glass_si_host" "$__glass_si_folder_url"
    }

    # B at the very end of the prompt, inside \[ \] so it takes no room. Something before this in
    # PROMPT_COMMAND may build PS1 afresh every prompt; then it is added again.
    __glass_si_mark_prompt_end() {
        [[ -n ${__glass_si_marked_ps1+x} && $PS1 == "$__glass_si_marked_ps1" ]] && builtin return 0
        builtin local b='\' ps1="${PS1%"$__glass_si_b"}" trail
        trail=${ps1##*[!"$b"]}
        __glass_si_clean_ps1=$ps1
        # A lone backslash at the end would swallow the mark's \[.
        (( ${#trail} % 2 )) && ps1=$ps1$b
        __glass_si_marked_ps1=$ps1$__glass_si_b
        PS1=$__glass_si_marked_ps1
    }

    # The number of history's last line, in __glass_si_reply; empty when history is empty.
    __glass_si_history_number() {
        builtin local last
        last=$(HISTTIMEFORMAT= builtin history 1)
        last=${last#"${last%%[0123456789]*}"}
        __glass_si_reply=${last%%[!0123456789]*}
    }

    # PS0 is shown after a command is read and before it runs, never for an empty line. Through an
    # array subscript's arithmetic, which expands to nothing, it notes in the shell itself that a
    # command ran and history's count (HISTCMD, which grows only when history keeps the line); then
    # E and C come from a copy of the shell. HISTCMD is read there and not in PROMPT_COMMAND, which
    # bash runs with history set aside: bash 3.2 reads 1 there.
    __glass_si_arm() {
        if (( __glass_si_ps0 )) && builtin shopt -q promptvars; then
            [[ ${PS0-} == *"$__glass_si_ps0_part"* ]] || PS0=${PS0-}$__glass_si_ps0_part
            if [[ -z ${__glass_si_now-} ]]; then
                # The count before the first command: one past history's last line.
                __glass_si_history_number
                __glass_si_now=$(( ${__glass_si_reply:-0} + 1 ))
            fi
            __glass_si_armed=1
        else
            [[ ${PS0-} == *"$__glass_si_ps0_part"* ]] && PS0=${PS0//"$__glass_si_ps0_part"/}
            __glass_si_armed=0
        fi
    }

    # E with the line history kept for this command, then C. A line history didn't keep (a leading
    # space with ignorespace, a repeat with ignoredups) gets no E: history's last line is an older one.
    __glass_si_preexec() {
        if (( ${__glass_si_now:-0} > ${__glass_si_before:-0} )); then
            builtin local line
            line=$(HISTTIMEFORMAT= builtin history 1)
            line=${line#*[0123456789][* ] }
            __glass_si_escape "$line"
            builtin printf '\033]633;E;%s\007' "$__glass_si_reply"
        fi
        builtin printf '\033]133;C\007'
    }

    # First in PROMPT_COMMAND, for the status before anything else changes it: D, if a command ran.
    # Without PS0 a command ran if history's last line changed, so one history didn't keep gets no D.
    __glass_si_precmd() {
        builtin local ret=$?
        if (( __glass_si_armed )); then
            (( __glass_si_ran )) && builtin printf '\033]133;D;%s\007' "$ret"
        else
            __glass_si_history_number
            [[ -n ${__glass_si_seen+x} && $__glass_si_reply != "$__glass_si_seen" ]] &&
                builtin printf '\033]133;D;%s\007' "$ret"
            __glass_si_seen=$__glass_si_reply
        fi
        __glass_si_ran=0
        builtin return "$ret"
    }

    # Last in PROMPT_COMMAND, after whatever builds the prompt: the folder, A, and B on the prompt.
    __glass_si_prompt() {
        builtin local ret=$?
        if __glass_si_other_integration; then
            __glass_si_stand_aside
            builtin return "$ret"
        fi
        __glass_si_keep_in_place
        __glass_si_report_folder
        builtin printf '\033]133;A\007'
        __glass_si_mark_prompt_end
        __glass_si_arm
        builtin return "$ret"
    }

    # First and last in PROMPT_COMMAND, when something added to it since has moved them. One that
    # took PROMPT_COMMAND over and runs the old one itself is left alone.
    __glass_si_keep_in_place() {
        builtin local first="$__glass_si_first" last="$__glass_si_last" nl=$'\n' entry pc
        if (( ${#PROMPT_COMMAND[@]} > 1 )); then
            [[ ${PROMPT_COMMAND[0]} == "$first" && ${PROMPT_COMMAND[${#PROMPT_COMMAND[@]}-1]} == "$last" ]] && builtin return 0
            builtin local -a others
            others=()
            for entry in "${PROMPT_COMMAND[@]}"; do
                [[ $entry == "$first" || $entry == "$last" ]] || others+=("$entry")
            done
            PROMPT_COMMAND=("$first" "${others[@]}" "$last")
        else
            pc=${PROMPT_COMMAND-}
            [[ $pc == "$first$nl"* && $pc == *"$nl$last" ]] && builtin return 0
            [[ $pc == *"$first"* || $pc == *"$last"* ]] || builtin return 0
            pc=${pc//"$first$nl"/}
            pc=${pc//"$nl$last"/}
            pc=${pc//"$first"/}
            pc=${pc//"$last"/}
            PROMPT_COMMAND=$first$nl$pc$nl$last
        fi
    }

    # Out of the way, for another terminal's integration.
    __glass_si_stand_aside() {
        builtin local first="$__glass_si_first" last="$__glass_si_last" nl=$'\n' entry pc
        if (( ${#PROMPT_COMMAND[@]} > 1 )); then
            builtin local -a others
            others=()
            for entry in "${PROMPT_COMMAND[@]}"; do
                [[ $entry == "$first" || $entry == "$last" ]] || others+=("$entry")
            done
            PROMPT_COMMAND=("${others[@]}")
        else
            pc=${PROMPT_COMMAND-}
            pc=${pc//"$first$nl"/}
            pc=${pc//"$nl$last"/}
            pc=${pc//"$first"/}
            pc=${pc//"$last"/}
            PROMPT_COMMAND=$pc
        fi
        [[ ${PS0-} == *"$__glass_si_ps0_part"* ]] && PS0=${PS0//"$__glass_si_ps0_part"/}
        [[ -n ${__glass_si_marked_ps1+x} && $PS1 == "$__glass_si_marked_ps1" ]] && PS1=$__glass_si_clean_ps1
        builtin unset __glass_si_marked_ps1 __glass_si_clean_ps1
        __glass_si_armed=0
    }

    __glass_si_load() {
        if [[ -n ${GLASS_SHELL_INTEGRATION+x} ]]; then
            # Loaded already. One handed down from a parent shell isn't this shell's: it loads its own.
            builtin local attributes
            attributes=$(builtin declare -p GLASS_SHELL_INTEGRATION 2>/dev/null)
            attributes=${attributes#declare -}
            [[ ${attributes%% *} == *x* ]] || builtin return 0
            builtin export -n GLASS_SHELL_INTEGRATION
        fi
        GLASS_SHELL_INTEGRATION=1
        __glass_si_other_integration && builtin return 0

        __glass_si_ran=0
        __glass_si_armed=0
        __glass_si_b='\[\e]133;B\a\]'
        __glass_si_ps0=0
        (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) && __glass_si_ps0=1
        __glass_si_ps0_part='${__glass_si_none[__glass_si_ran=1,__glass_si_before=__glass_si_now,__glass_si_now=HISTCMD]-}$(__glass_si_preexec 2>/dev/null)'
        __glass_si_first='__glass_si_precmd 2>/dev/null'
        __glass_si_last='__glass_si_prompt 2>/dev/null'

        # Every control character, for the escape's quick test.
        builtin local code=1 octal char nl=$'\n' kind
        __glass_si_controls=
        while (( code < 128 )); do
            (( code == 32 )) && code=127
            octal=$(( code / 64 ))$(( code / 8 % 8 ))$(( code % 8 ))
            builtin printf -v char "\\$octal"
            __glass_si_controls=$__glass_si_controls$char
            code=$(( code + 1 ))
        done

        __glass_si_url "${HOSTNAME-}"
        __glass_si_host=$__glass_si_reply

        # Around what is there already, string or (bash 5.1 and later) array, a line each, so a
        # trailing ";" or comment in someone's own can't run into ours. A function missing from a
        # shell that was handed PROMPT_COMMAND says nothing.
        kind=$(builtin declare -p PROMPT_COMMAND 2>/dev/null)
        if [[ $kind == 'declare -a'* ]]; then
            PROMPT_COMMAND=("$__glass_si_first" "${PROMPT_COMMAND[@]}" "$__glass_si_last")
        elif [[ -n ${PROMPT_COMMAND-} ]]; then
            PROMPT_COMMAND=$__glass_si_first$nl$PROMPT_COMMAND$nl$__glass_si_last
        else
            PROMPT_COMMAND=$__glass_si_first$nl$__glass_si_last
        fi
    }

    __glass_si_load
    builtin unset -f __glass_si_load

    fi
    """##

    // MARK: fish

    private static let fishScript = ##"""
    # Glass Power Tools shell integration for fish.
    #
    # It tells the terminal where the prompt and each command begin and end, so Glass Power Tools
    # knows the line being typed and can offer the rest of it. It sends the marks iTerm2, VS Code,
    # Ghostty, WezTerm and kitty use: OSC 133 A where the prompt starts, B where typing begins, C as a
    # command starts and D with its exit status when it ends; VS Code's OSC 633 E with the command
    # line; and OSC 7 with the folder. It prints nothing else and changes nothing else: the prompt
    # looks the same, $status is kept, and other handlers keep running.
    #
    # fish 4.0 and later send A, C and D themselves, and B from 4.3, and report the folder; with
    # them this sends only what fish leaves out: E, and B before 4.3.
    #
    # It loads once per shell, only in an interactive shell on a terminal, and stands aside where
    # another terminal's integration already marks the prompt. To remove it, delete the line that
    # sources this file from ~/.config/fish/config.fish, then this file; Glass Power Tools'
    # settings can do both.

    function __glass_si_other_integration --description "Another terminal's integration marks prompts already"
        # iTerm2's, VS Code's, Ghostty's or kitty's; WezTerm has none for fish.
        functions -q iterm2_status; and return 0
        set -q VSCODE_SHELL_INTEGRATION; and return 0
        functions -q __ghostty_setup; and return 0
        functions -q __ghostty_mark_prompt_start; and return 0
        functions -q __ksi_schedule; and return 0
        functions -q __ksi_mark_prompt_start; and return 0
        return 1
    end

    function __glass_si_escape --description 'The command line as OSC 633 E carries it'
        # A backslash doubled, and ";" and every control character as \xNN, as VS Code writes them.
        # A line at a time: a command substitution splits at newlines, so they go back in as \x0a.
        set -l lines
        for line in (string split -- \n $argv[1])
            set line (string replace -a -- \\ \\\\ $line)
            set line (string replace -a -- ';' '\x3b' $line)
            if string match -qr -- '[\x01-\x1f\x7f]' $line
                for code in 01 02 03 04 05 06 07 08 09 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 7f
                    set line (string replace -a -- (printf "\x$code") "\\x$code" $line)
                end
            end
            set -a lines $line
        end
        string join -- '\x0a' $lines
    end

    function __glass_si_wrapped --description 'Whether fish_prompt is the wrapper that adds B'
        functions -q fish_prompt; and string match -q -- '*__glass_si_user_prompt*' (functions fish_prompt)
    end

    function __glass_si_wrap_prompt --description 'fish_prompt as the person has it, then where typing begins'
        # A theme or fish_config can define fish_prompt anew at any time; it is wrapped again then.
        __glass_si_wrapped; and return
        functions -q fish_prompt; or return
        functions -e __glass_si_user_prompt
        functions -c fish_prompt __glass_si_user_prompt
        function fish_prompt --description 'The prompt, then OSC 133 B where typing begins'
            __glass_si_user_prompt $argv
            printf '\e]133;B\a'
        end
    end

    function __glass_si_stand_aside --description "Out of the way of another terminal's integration"
        set -g __glass_si_off 1
        if __glass_si_wrapped
            functions -e fish_prompt
            functions -c __glass_si_user_prompt fish_prompt
            functions -e __glass_si_user_prompt
        end
    end

    function __glass_si_load
        status is-interactive; or return
        test -t 1; or return
        contains -- "$TERM" dumb linux; and return
        if set -q GLASS_SHELL_INTEGRATION
            # Loaded already. One handed down from a parent shell isn't this shell's: it loads its own.
            set -qx GLASS_SHELL_INTEGRATION; or return
            set -e GLASS_SHELL_INTEGRATION
        end
        set -g GLASS_SHELL_INTEGRATION 1
        __glass_si_other_integration; and return

        # fish 4.0 and later report the folder themselves, and mark prompts unless the
        # no-mark-prompt feature is set (from 4.0.6; before it the feature doesn't exist and fish
        # always marks). B came in 4.3.
        set -g __glass_si_fish_folder 0
        set -g __glass_si_fish_marks 0
        set -g __glass_si_fish_marks_end 0
        set -l release (string match -r '^(\d+)\.(\d+)' -- $version)
        if set -q release[3]; and test $release[2] -ge 4
            set __glass_si_fish_folder 1
            status test-feature mark-prompt 2>/dev/null
            if test $status -ne 1
                set __glass_si_fish_marks 1
                if test $release[2] -gt 4; or test $release[3] -ge 3
                    set __glass_si_fish_marks_end 1
                end
            end
        end
        set -g __glass_si_ran 0

        function __glass_si_prompt --on-event fish_prompt
            set -q __glass_si_off; and return
            if __glass_si_other_integration
                __glass_si_stand_aside
                return
            end
            if test $__glass_si_fish_folder = 0
                printf '\e]7;file://%s%s\a' (string escape --style=url -- $hostname) (string escape --style=url -- $PWD)
            end
            test $__glass_si_fish_marks = 1; or printf '\e]133;A\a'
            test $__glass_si_fish_marks_end = 1; or __glass_si_wrap_prompt
        end

        function __glass_si_preexec --on-event fish_preexec
            set -q __glass_si_off; and return
            printf '\e]633;E;%s\a' (__glass_si_escape $argv[1])
            test $__glass_si_fish_marks = 1; or printf '\e]133;C\a'
            set -g __glass_si_ran 1
        end

        function __glass_si_postexec --on-event fish_postexec
            set -l ret $status
            set -q __glass_si_off; and return $ret
            if test $__glass_si_fish_marks = 0; and test $__glass_si_ran = 1
                printf '\e]133;D;%s\a' $ret
            end
            set -g __glass_si_ran 0
            return $ret
        end
    end

    __glass_si_load
    functions -e __glass_si_load
    """##
}
