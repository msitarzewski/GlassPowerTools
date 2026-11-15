# Every window in the orb dock, a setting (2026-11-13, 0.4.619, D107)

## Task
- **Asked (the owner):** "let's also allow a toggle to allow all windows to show in the dock all the time."
- **His choices (asked):** both docks; an open window's orb brings it to the front; the look "opposite of 2" (of
  "put-away orbs dimmed"), read as put-away orbs at full strength and open windows' fainter, and told to him.
- 0.4.619 (0.4.618 had gone to Apple already). Shipped at his word, "Let's ship 0.4.619" (2026-11-15).

## What changed
- `GlassOrbDockGeometry.swift`: `GlassOrbDockEveryWindow`, shared by both docks: the setting's key, which windows the
  dock lists (those put away, then every other open one, each once), and an orb's strength (fainter while none of its
  windows is put away; 0.5).
- Mac (`GlassMacOrbDock.swift`): the dock model learns each window that can dock as it opens
  (`opened(_:window:face:)`, from the window's orb modifier) and forgets it as it closes; `bringForward` brings a
  docked window back or an open one to the front; `keepsShown` keeps the panel up while the setting is on;
  `everyWindowChanged()` shows or hides it as Settings changes. The dock view lists the open terminal windows, a click
  or a dot brings them forward, and draws each orb at its strength.
- Vision Pro (`GlassOrbDock.swift`): the dock lists every open terminal window, a pinch on an open one activates it
  without the by-the-dock placement a docked one gets, each orb at its strength; the dock doesn't close while the
  setting is on, and opens at launch (`GlassConnectionsIdleWatcher.comeBackAsLeft`) and as the setting is turned on.
- Settings (`GlassShellSettingsView.swift`): **Show Every Window in the Dock** in Orbs, on the Mac, and on Vision Pro
  with Into the Dock.
- Help: `library-settings.md` (both Orbs sections), `library-connect.md` (both docks). `RELEASE-NOTES.md` 0.4.619.
  `decisions.md` D107.

## Validation
- `GlassOrbDockEveryWindowTests` (3) and `GlassMacOrbDockEveryWindowTests` (7) with the dock's own 15: 25 passed.
  **Seen failing with each piece undone:** the list (windows put away only), the strength (always full), the model not
  learning windows, not forgetting closed ones, not staying up, `everyWindowChanged`; and, separately, `bringForward`
  bringing back only docked windows (2 issues). Restored, passing.
- **Suites (0.4.619, with the agent change):** shell 426; terminal on the Mac 1,282, iPhone and Vision Pro simulators
  871 each (after the history test's allowance, below); builds for all three platforms.
- **macOS VM, the real app (Debug, `--demo-open terminal`), 2026-11-13:** before, two windows (the terminal, All
  Connections), no dock. Settings ▸ Appearance ▸ Show Every Window in the Dock on: the dock panel comes up (183 × 148)
  with Connections' orb and the open terminal's, the terminal's faint (pictured), nothing put away. A press and a real
  click on that orb each bring the terminal in front of Settings. Off: the dock goes; on: back. Shrink to Orb: the
  window goes, its orb full strength (pictured); a click brings the window back at its frame, the dock stays.
  `vmtool press` now also matches an accessibility identifier (a SwiftUI switch in a form has no title).
- **Vision Pro simulator, UI (`GlassSessionOrbUITests.testEveryOpenWindowIsInTheDock`, new):** the setting on at
  launch; the dock opens and lists the open terminal while its window stays open; a pinch on that orb closes nothing;
  Shrink to Orb, then its orb brings the window back and the dock stays. Passing, with the two dock tests beside it,
  three times. **Seen failing** with the dock listing only windows put away ("the open window has no orb in the
  dock") and with the dock closing when nothing is put away ("the dock went with the setting on"); restored.
  - **The 60 s wait in it:** the runner places no tap on visionOS (hit point {-1, -1}); the pinch on the open
    window's orb also lands in the terminal (`tap1 ended at=22,80`, `keyboard taken=true` in the app's log), and a
    terminal holding the keyboard never reports its animations idle (the runner's request at the next tap answered
    only as that window went or the app left the foreground). Not seen when the pinch stays on the orb (one run in
    four). Noted in the test.
  - **One failure, not ours:** the shared Vision Pro simulator ran another project's app (installed and launched
    18:39:23 by another session) into a full immersive space mid-test, hiding the terminal and its bar
    ("Failed to tap session-orb-shrink: no matches"); the recording's frame shows it. The three runs after were on a
    simulator made for them (since deleted).

## Also in 0.4.619: agents started with npx, and Homebrew's Codex in tmux
- **Found (2026-11-13), checking the agent read against npm's Codex (0.169.0, `npm pack`):** its `bin/codex.js` becomes the
  native `…/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex` with `process.execve` (Node 22.15+), a
  program named `codex`: told, in 0.4.616 too. Not told, in any build: an agent started through `npx` (in front is
  `node …/bin/npx @openai/codex`, npx being a node script) or `npm exec`; and Homebrew's Codex in tmux, which names
  the file `codex-aarch64-apple-darwin`.
- **Changed (`TerminalAgent.swift`):** an interpreter's script that is a runner (`runner(named:)`: `npx`, `npx-cli.js`,
  `npm-cli.js`, `pnpm.cjs`, `yarn.js`) launches the tool after it; `npm exec` and `npm x` are runners; a name with a
  platform after the agent's (`-aarch64-`, `-x86_64-`, `-arm64-`) is that agent. Only up to the tool is kept.
- **Tests:** `TerminalAgentTests.byRunnerScript`, `byPlatformName`; 7 checks fail with both changes out; 15 pass.

## Also: the history reader's timing test, measured per platform
- **Failed once:** the 0.4.619 iPhone simulator suite, `ShellHistoryFileTests.largeFiles`: zsh read in 0.641 s of
  thread time against 0.0227 s to split lines, 28.2 times, over the allowance of 27.
- **Found:** not load and not the reader (unchanged since `6c7a03aa`, which set the allowance). Measured with a
  temporary print of each ratio: the Mac gives zsh 18.3–18.4, bash 7.7, fish 13.5–13.8, as on 2026-11-06. The iPhone
  simulator gives zsh 25.1–27.3 alone and 26.2–27.2 inside the suite beside the visionOS suite; bash about 10, fish
  about 16.5. The Vision Pro simulator gives zsh 22.6–24.5. The splitting costs the same there; the unoptimised reader
  costs more. The allowance, 1.5 times the Mac's most, sat at the iPhone's edge.
- **Changed (test only):** the allowance is per platform, 1.5 times that platform's most: Mac 27 (as was), Vision Pro
  36, iPhone and iPad 42.
- **Still bites, each platform:** with an `NSRegularExpression` compiled per zsh entry, planted and removed, the Mac
  gives 39.9, iPhone 53.2 (51.2 again under the new figure, failing), Vision Pro 42.4 (41.6, failing). A Swift `Regex`
  per entry gives about 120 on all three. Logs in `tmp/history-ratio-619/`.
