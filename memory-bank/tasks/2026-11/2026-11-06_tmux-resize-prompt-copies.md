# A resize leaves a copy of zsh's prompt in tmux (2026-11-06)

## Report

The owner passed on a screenshot from someone using the Mac release (0.4.603, macOS 26.6): a local
terminal in tmux, its screen filled with the same zsh prompt, one under another, after the window was
resized. The owner: "resising the window did that!", then "I watched it happen... every bit of movement
caused a newline." The window had Scale Text on (the button lit), and no tmux status bar showed, so the
tab was a control-mode client (D83). The default macOS zsh prompt, a new tab in the home folder.

## Cause (measured)

On a resize zsh redraws its prompt as `\r\r ESC[0m ESC[27m ESC[24m ESC[J` and the prompt: no newline
(bytes logged through `pipe-pane` and the control client's `%output`). With the prompt on the top row,
that clear runs from the top-left corner, which tmux treats as clearing the whole screen. tmux's
`scroll-on-clear` (added in 3.3, on by default) first scrolls the screen into history. So each resize
adds one copy of the prompt to the session's history.

- Measured on tmux 3.7c (Homebrew's build for macOS 26, in the macOS 26.6.2 VM) and 3.8 (this Mac):
  one copy per resize of any kind (width, height, both), through `resize-window` and through a
  control client's `refresh-client -C`. With `scroll-on-clear off` on the window: none.
- In the VM's real app (Debug build of the working tree), a 10-step drag of a local tab's corner took
  tmux's copy from 1 prompt to 4, while the tab itself showed one. SwiftTerm's erase-in-display only
  erases, so the app's own view keeps one prompt and tmux's copy drifts from it.
- **How they reached his screen (VM, before the fix):** a relaunch re-read the pane (`TmuxPaneRestore`),
  which put tmux's copies into the tab's own scrollback, one prompt still on screen. Growing the window
  then brought scrollback down onto the screen, the cursor moving down with it (SwiftTerm's
  `Buffer.resize` pulls history down while nothing is below the cursor, as Terminal.app does): "~ %
  clear", a blank line, then the copies, the cursor on the last. A few drags later the tab showed five
  stacked prompts, the layout of his screenshot. Any re-read does the same: a relaunch (an update
  relaunches), a reattach, the session opened on another device.
- With tmux attached the ordinary way (control mode off), tmux's screen kept one prompt and showed a
  status bar, which his screenshot doesn't have: his tab was a control-mode client.

## Fix (uncommitted)

`TmuxControlClient.askForPane` sends `set-option -wq scroll-on-clear off` for the window it follows,
at the start and on each session or window change (`Sources/GlassTerminalEmulator/TmuxControlClient.swift`).
The control client is how both local tabs (pipes) and SSH tabs (`-CC`) attach, so it covers both, and
sessions made by earlier versions. `-q`: tmux 3.2, which the client supports, has no such option.
Effect beyond the bug: a full-screen clear (`clear`, ⌃L) no longer copies the screen into tmux's
history, which matches what the tab itself keeps.

## Tests

- **VM, fixed build (Debug, working tree), macOS 26.6.2, tmux 3.7c:** the window option reads
  `scroll-on-clear off` once attached; three drags in and out left tmux at one prompt and no history; a
  relaunch and a growing drag then showed one prompt.
- `LiveTmuxControlResizeTests.dragLeavesOnePrompt`: the app's real terminal view in a window, zsh (`-f`)
  under a tmux server of the test's own, the prompt on the top row, 12 drag steps; one prompt in tmux's
  history and screen, and one in the tab. **Bites:** with the line removed, 9 prompts in tmux; file
  restored and compared with `cmp`. A reattach-and-grow step was tried in it and dropped: in this
  offscreen harness the reattached tab didn't bring history down on growing, so it passed with the bug.
- `TmuxControlClientTests` (`start`, `ownSwitch` and the scripted starts through `startReplies()`) and
  `TerminalTmuxControlSessionTests.controlClient` expect the new command in order.
- An earlier version of the drag test counted only the tab's prompts. It passed with the bug present,
  so it was rewritten. Tests that drove the bare client and the real view (with Scale on and off) all
  passed before the fix for the same reason: they looked at SwiftTerm, not tmux.

## Scale Text did nothing in a tab in tmux (fixed, uncommitted)

The same user: "changing the text size and enabling scale text broke the feature"; the owner: "Scale acted
like a regular resize, like the button wasn't clicked", then "Yep. I just tested it here" (his Mac, 0.4.606).

- **Cause.** `MacLocalTerminalPaneView.wantsScaling` turns Scale on only once the terminal has said its size
  (`hasMeasuredGrid`, set by the host view's `onResize`). That report comes from SwiftTerm's
  `LocalProcessTerminalView.sizeChanged`, which returns early unless its own process runs
  (`guard process.running`, upstream 1.20.0). A tab in tmux runs tmux on pipes (`TmuxControlPipe`), not
  that process, so the report never came: the button lit, This Window's When Resized said Scale, and the
  window resized the grid. The text size had nothing to do with it. A recording's size (`terminalColumns`,
  `terminalRows`) came from the same report.
- **Since** `ff46dcd3` (2026-10-20, Scale Text on the Mac's own terminals), the day after tabs in tmux moved
  to pipes (`485f608c`). `scaleKeepsTmuxsSize` calls `setScaling` directly and never met the gate.
- **Not the Metal change (D101), as he asked:** the user's 0.4.603 has none of D101. The vendored SwiftTerm's
  Mac files are identical to upstream v1.20.0 (only `iOSTerminalView.swift`'s visionOS scale and the
  generated build-info file differ). D101's app edits are the visionOS renderer default and UIKit-only code;
  the Mac drew with Metal before and after.
- **Fix, two lines** (`Sources/GlassTerminalEmulator/SwiftTermHostView.swift`):
  `MacLocalProcessDelegateProxy.sizeChanged` reports the size itself when the tab is tmux on pipes; and
  `startControlPipe` reports the grid once when tmux starts in a view already in its window. The second came
  from the VM: with the first alone, a window whose Scale Text was already on resized tmux on its first drag
  (106×36 → 101×34) and held only from then. Its view lays out first and starts the process after, so the one
  size change happened before the tab was a tmux tab.
- **Test.** `LiveTmuxControlResizeTests.tellsItsSize`: a tab in tmux started by its view in a window, as a
  window's tab is; the pane is told the tab's grid before any resize and after one. **Bites, each line on its
  own:** without the start-time report, "before any resize the pane was told []"; without the resize report,
  told `["110x31"]` while the tab was 72×21. File restored, `cmp` clean.
- **VM, the real button (macOS 26.6.2, tmux 3.7c), first fix only:** with Scale Text on, two drags (984×699,
  794×574) left tmux at 101×34 and the text scaled with the window.
- **VM, both fixes:** relaunched with Scale on, tmux 89×30 from launch through a grow (981×696) and a shrink
  (734×564), the text larger and smaller. The button off: tmux took the window's grid (108×36) and followed a
  drag (94×36); on again: held at 94×36 through 975×779 and 733×598. **His steps:** Scale off (114×43), ⌘+
  twice (97×39), Scale on, drags in and out (785×637, 1025×818): tmux 97×39 throughout.
- Mac `GlassTerminalTests`: 1,112 passing with both fixes. The VM's only new crash report (02:28) is the Debug
  build opened at login without `--ui-testing` (`CKContainer` in `GlassPowerToolsApp.init`), as at 23:47.

- **His "It used to work with tmux just fine" (2026-11-06, on 0.4.606):** an independent agent read the history
  from the code, before this note: no committed version took Scale in a local tab in tmux (control mode since
  `485f608c`, a day before Scale reached local tabs in `ff46dcd3`; its message says "tmux tabs included", and
  its test `scaleKeepsTmuxsSize` calls `setScaling` directly). It did work in SSH tabs, with or without tmux,
  since `394fb47e`, and in local tabs not in tmux. Not known: whether `terminalTmuxControlMode` was ever off on
  his Mac. 0.4.607 with the fix installed on his Mac and iPhone the same evening. **Observed by him on 0.4.607:
  "Scale works now in tmux."**

## Found along the way (not fixed)

1. **A fast drag races tmux's answers.** A randomized drag through the bare client showed sizes the
   client took for another device's (`showGrid` with `own: false`) dozens of times: a layout for size N
   arrives after N+1 was sent, so the client sees the window at "another client's" size and flips the
   terminal's grid to it and back. No duplicate prompts came of it.
2. **VM housekeeping.** Copying this Mac's tmux into the VM failed: its build for macOS 27 crashes in
   libevent on 26 (`tmux-*.ips` in the VM). It also overwrote the VM's own libevent, ncurses, utf8proc and
   jemalloc, which `brew reinstall` put back; the VM now has Homebrew's tmux 3.7c. The VM app was also
   run with `localTmux` on in its main defaults domain. The `glasspowertools-mac26-run` VM was already
   running from an earlier session.
