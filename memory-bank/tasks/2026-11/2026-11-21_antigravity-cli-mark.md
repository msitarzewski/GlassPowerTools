# 2026-11-21 — Google's Antigravity CLI (`agy`) gets its agent mark (0.4.634)

**Owner and authorization:** his ask, "We need to add agy to the agnt detector... it's Google's Antigravity command
line. Look t up!" Local edits, tests, a VM check; the Mac install is standing. Committed and pushed 2026-11-22 at his
word, with 0.4.633–0.4.638.

## What `agy` is, from the sources
- Google's terminal agent, replacing Gemini CLI for individual accounts; a native Go program, not an npm package.
- **Google's script** (`https://antigravity.google/cli/install.sh`, read whole, not run): copies one program, which
  its archive names `antigravity`, to `~/.local/bin/agy` (`--dir` for another folder), then runs `agy install` for the
  shell's PATH. Windows: `%LOCALAPPDATA%\agy\bin`, so `agy.exe`.
- **Homebrew** (`antigravity-cli` cask, 1.5.14 on 2026-11-21, `formulae.brew.sh/api/cask/antigravity-cli.json`): the
  program stays `Caskroom/antigravity-cli/<version>/antigravity`; `agy` is a `command_wrapper`, which Homebrew writes
  (`Pathname#write_env_script`, read in Homebrew/brew) as `#!/bin/bash` and `AGY_CLI_DISABLE_AUTO_UPDATE="true" exec
  "…/antigravity" "$@"`. So tmux names it `antigravity`. `brew install --cask antigravity` is the desktop app.
- **Not it:** the Antigravity editor's own command-line launcher, a shell script called `antigravity` (as VS Code's
  `code` is); Python's standard-library joke `python3 -m antigravity`.
- Guides read: computingforgeeks, continuumcode.ai, agentpedia.codes (install paths, the cask, winget
  `Google.AntigravityCLI`).

## Changed
- `Sources/GlassTerminal/TerminalAgent.swift`: case `antigravity` ("Antigravity CLI"); `agy` in `byName`; a new
  `byProgramOnly` (`antigravity`), looked up only for a program's own name (`agent(named:)`), never for a script's
  name, a package or a Python module, so the editor's launcher and Python's module aren't taken for it.
- The mark: Lobe Icons `packages/static-svg/icons/antigravity.svg` at `9752d967494e48d8f83f2808feb2b0207bf70997`
  (licence unchanged there), without its `<title>`, its path written out command by command as the 2026-10-14 marks
  are (`tmp/agy/written_out.py`, which reproduces Amp's shipped mark byte for byte). Drawn 96 pt square, the
  published and written-out paths differ in 0 of 9,216 pixels. `logoSVG`, and the same file in
  `Resources/AgentMarks.xcassets/agent-antigravity.imageset`.
- Accent `#0EA5E9`: the owner's Agency Agents app's colour for Antigravity (`src-tauri/data/tools.json`, which also
  finds it by `agy --version`).
- Licence records: `THIRD-PARTY-NOTICES.md` (the row now also names the fourteen 1.95.1 marks, which it had left
  out), `Tools/Licenses/components.json`, `Acknowledgements.json` regenerated (one line).
- Help `site/help/library-connect.md` (the agents recognized), RELEASE-NOTES 0.4.634.
- Test `TerminalAgentTests.antigravity`: `agy`, `antigravity`, `agy.exe`; Google's and Homebrew's command lines; the
  wrapper before its exec; only the program kept from a command line; the editor's launcher, `python3 -m antigravity`
  and a package called `antigravity` are not it.

## Checked
- `TerminalAgentTests` and `TerminalTmuxTests`, 56 pass; the terminal module whole, 1,318 pass (live tests skip on his
  Mac, `TMUX` set).
- Each piece seen failing with it undone (`tmp/agy/agy-bite.py`): `agy` unknown; `antigravity` unknown; `antigravity`
  taken as any script's or module's name too (the launcher, module and package expectations fail); the asset catalog's
  mark differing from the Mac's.
- **macOS VM** (26.6, tmux 3.7c, Debug build of this change), a local tmux tab in the app. Running Google's script in
  the VM was refused by this session's safety check, so nothing of Google's ran: `/bin/sleep` copied under each
  install's own name and path, and Homebrew's wrapper as Homebrew writes it (`tmp/agy/standins.sh`,
  `tmp/agy/agy-check.zsh`). tmux said `agy` for `~/.local/bin/agy` and `antigravity` for Homebrew's `agy` after its
  exec; the process table, `…/local-bin/agy 600` and `…/Caskroom/antigravity-cli/1.5.14,…/antigravity 600`. The tab
  showed Antigravity's mark for both, the terminal icon for plain `sleep`, Claude Code's for the `claude` control
  (`tmp/agy/vm/agy-marks-vm.png`). A linked `sleep` is named by its target on macOS (tmux said `sleep`), so the
  stand-ins are copies. Stand-ins removed, VM stopped.
- Not tried: the real `agy` (refused, above); a basic terminal outside tmux in the VM (its reading is the same process
  table line the VM showed); an SSH host's tmux; Show All Windows, Active and the orb dock for this agent (each draws
  any agent the same way).

- 0.4.634 (634), Release, built for macOS, iOS and visionOS (Xcode-beta 27.3); installed 2026-11-21 18:03 on his Mac
  (read back from `/Applications`, running, no crash report), the iPhone and the headset (devicectl: "App installed").

## Follow-up, 2026-11-22: the mark pulsed while `agy` sat idle (0.4.637)
- **His report:** "For some reason the Antigravity icon continues to pulse though the terminal session seems idle." So
  the mark itself showed (the arch, on his Mac).
- **Cause, inferred:** the pulse was any output in the last 1.2 s (`SwiftTermOutputActivity`, fed by
  `SwiftTermHostModel.noteOutputActivity` from both output paths). His `~/.local/bin/agy` (Google's internal Go
  build, module list stripped) holds Bubble Tea's cursor-blink names (`CursorBlink`, `BlinkSpeed`, `initialBlink`,
  `tea.Tick`); that cursor blinks by redrawing its cell reversed and back every 530 ms, so an idle `agy` never went
  quiet. Read from the program file only, never run; its output was not seen.
- **Fix:** output counts once the live screen's text has changed: `SwiftTermBufferText.activityFingerprint` (the
  alternate screen or not, the live screen's first row as `getScrollInvariantLine` counts it, every character; no
  colours, no cursor) and `SwiftTermActivityGate`, looked at 200 ms after output arrives, one look at a time
  (`noteOutputActivity`). No screen yet counts, as before. Each engine gives `activityFingerprint()`. Usage minutes
  (`lastActivityAt`) follow the same rule.
- **Tests:** `TerminalActivityFingerprintTests` (headless: a reversed cell redrawn, the cursor hidden, shown and moved,
  a colour change are the same screen; a character, a spinner frame, the same lines scrolled, the alternate screen
  are work; the gate); `TerminalActivityTests` (a live hosted terminal: four blinks over 1.2 s leave it idle and the
  mark stops; a line printed starts it). Each seen failing with its rule undone (colours counted; scrolling ignored;
  every output counted, which also fails the live test). GlassTerminalTests 1,324, GlassShellTests 445 pass.
- Help `terminal-sessions.md` (what pulsing means); RELEASE-NOTES 0.4.637.
- 0.4.637 (637), built with Xcode-beta 27.3 for macOS, iOS and visionOS; installed 2026-11-22 08:51 on his Mac (read
  back, running, no crash report), the iPhone and the headset.
- **Not seen:** `agy` itself on his Mac after the fix; a program that changes its text without working (a clock in
  its status line) still pulses.

## Next
- His look at `agy` idle on 0.4.637: the mark should stop pulsing within about a second and a half of `agy` going
  quiet.
