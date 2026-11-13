# Claude Code from npm gets its agent mark (2026-11-12, 0.4.617)

## Task
- **Asked (the owner, 2026-11-11):** whether agent detection works for local (not tmux) terminals: a local tab
  running Claude Code showed no mark while another did.
- **His word (2026-11-12):** "build the fix as 0.4.617". Not committed.
- **Scope:** `TerminalAgent.identify`, which every surface asks (a Mac's local terminals from the process table,
  tmux here and on other machines from tmux's program name and the foreground group's command line, Show All
  Windows' tiles).

## What was found
- The local path works: `LiveLocalAgentTests` runs zsh in a PTY with this Mac's integration and `claude` in
  front, and the app's own read (`tcgetpgrp` → `TerminalProcessTable.commandLine` → `identify`) says Claude Code.
  It fails with the read pointed at the shell instead of the group in front (seen, then restored).
- The process table of the unmarked tab: the program in front was Claude Code installed through npm, run by its
  whole path, `…/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. The package names its program
  `bin/claude.exe` on every platform (`npm view @anthropic-ai/claude-code bin`, 2.1.322).
- `identify` knew `claude` by name, but not `claude.exe`, and read a package folder only from an interpreter's
  script, never from the program itself. tmux would say `claude.exe` as the program's name: no mark there either.
- Claude Code 2.1.3xx also runs background sessions as `claude bg-spare` inside a terminal of its own under a
  detached `claude bg-pty-host` (read from its binary's strings). Those are never a tab's program; already told
  as Claude Code by name.

## What changed (`Sources/GlassTerminal/TerminalAgent.swift`)
- `agent(named:)`: a program's name, or its name without `.exe`; used for tmux's program name and the command
  line's first word.
- A program run by its path from inside an agent's package is that agent, as an interpreter's script already
  was (`agent(forScript:)`): by its stem, or the package folder after `node_modules` (`@anthropic-ai/claude-code`
  → `claude-code`). Never for an interpreter, shell or runner (`needsCommandLine`), whose own path says nothing
  of what it runs; never a project folder that merely has an agent's name.
- `RELEASE-NOTES.md` 0.4.617. Help unchanged: it already says local terminals and tmux are read by their program.

## Validation
- Unit (`TerminalAgentTests.byProgramPath`, a neutral home folder): with the old code, the npm path, tmux's
  `claude.exe` and the package-folder case fail (3 issues); the negatives (`notclaude.exe`, `setup.exe`, a
  project folder `claude-code`) pass. With the interpreter guard removed, the `node` inside the package case
  fails (seen, restored).
- Live (`LiveLocalAgentTests.npmClaudeInFront`): zsh in a PTY runs `sleep` linked as
  `…/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` by its whole path; fails before the change
  (`told`), passes after. `claudeInFront` passes before and after.
- Agent and live suites with the fix: 15 tests passed. Whole suites: Mac terminal 1,279 (3 new), iOS and
  visionOS simulators 869 each (1 new), all passed; the corrupt-file decode lines logged as often as in 0.4.616's.
- Built 0.4.617 (617) for the Mac, iOS and visionOS (Release, development signed). On the Mac at 13:36, read back
  0.4.617 (617), running, no crash reports. On the iPhone at 13:36, read back 0.4.617 (617). On the headset at 19:22,
  read back 0.4.617 (617).

## Remaining
- Commit, and a release or TestFlight, only at his word.
