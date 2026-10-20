# 2026-10-19 — Selecting through a scroll in tmux tabs

**Objective.** The owner: "I need to be able to drag select through a scroll. I think the tmux buffers are
messing with it. I used to be able to (before tmux) start a selection, scroll several pages up, hold shift
(continue selection) and click. and it just worked. Now it starts a new selection in the current buffer."
**Owner.** The coordinating agent. **Decision:** D83 (control mode), after route A was built and measured.

## Why it broke (measured)

- tmux 3.8 turns its mouse on with no config (`show-options -g mouse` → `on`, a throwaway `-L` server), and a
  drag's end runs `copy-pipe-and-cancel`. On a Mac the first drag is tmux's selection, gone on release. Shift
  bypasses mouse reporting (SwiftTerm `shiftBypassesMouseReporting`), so shift-click is the terminal's selection,
  which knows only the screen.
- tmux draws on the alternate screen, so the terminal has no history. A scroll in a tmux tab is the app's
  `copy-mode` + `scroll-up` over a side channel (`TerminalSession.scrollTmux`, `MacLocalTmux`), which redraws the
  screen in place.

## Route A, built and tested, then backed out of the wiring (2026-10-19)

Before installing 0.4.481 on his devices, nothing turns it on any more: `TerminalSession.attachTmux` and
`MacWorkspaceController.startLocalPanes` are as they were, and the four command-counting and Find tests with
them. Kept, off, for control mode: `TerminalTmuxScreen` (filter, `prefill`) and its tests,
`SwiftTermHostModel.keepsScrollbackUnderTmux` and the engines' plumbing, `TerminalTmux.scrollbackArguments`,
`SwiftTermLocalProcessRuntime.start(tmuxHistory:)`, the Find gate, and
`LiveTmuxTests.historyIsTheTerminalsOwn`, disabled until the control-mode client passes it.

What was built:

- `Sources/GlassTerminalEmulator/TerminalTmuxScreen.swift` (new): in tmux tabs the terminal declines `CSI ? 47/1047/1049 h/l` and the mouse modes, follows `CSI t;b r`, and turns `CSI n S` (tmux's `indn`,
  seen five times in sixty lines) into line feeds at the region's last row when the region starts at the top, since
  SwiftTerm keeps only line-feed scrolls in history (`Terminal.scroll`, `scrollTop == 0`). `prefill(history:rows:)`
  clears, writes `capture-pane -p -e -J -S -10000 -E -1`, and pushes it above the screen.
- `SwiftTermHostModel.keepsScrollbackUnderTmux` → each engine (`keepScrollbackUnderTmux`), filter before
  `clearBlacks` in all four feed paths. Remote: `TerminalSession.attachTmux` turns it on and feeds the prefill
  before the attach line (not for a session just made). Local: `MacWorkspaceController.startLocalPanes` runs the
  capture with `MacLocalTmux.run` and passes `tmuxHistory` to `SwiftTermLocalProcessRuntime.start`.
- Find searches the terminal's own history where it keeps one (`tmuxFindTarget`, `MacLocalTerminalPaneView`);
  Select All already did off the alternate screen.
- Tests: `TerminalTmuxScreenTests` (filter, split reads, scroll rewrite, prefill, and a tmux 3.8 replay recorded
  on a throwaway server with `sh` and a neutral status line: with the filter all 60 lines in history in order;
  without, the alternate screen and none); four command-counting tests updated for the history read. All 901
  terminal tests pass.
- **The hole:** live against the Linux test VM (tmux 3.6), `LiveTmuxTests.historyIsTheTerminalsOwn`: 1–150 (history
  load and the attach screen) all present, but of `seq 1001 1060` printed at once, 1001–1032 never reached the
  terminal. A local probe: 60 of 60 sent, at most 915 of 1,000. tmux draws only its latest screen when output
  outruns it; skipped lines are only in tmux. The test fails, as it should, until control mode.

## Control mode (D83): next

- Research under way: iTerm2 (`sources/tmux/TmuxGateway.m`, `TmuxController.m`, `TmuxWindowOpener.m`,
  `TmuxStateParser.m`, `TmuxHistoryParser.m`, `TmuxDroppedOutputScanner.swift`, the key-name encoder, tests named
  for pitfalls) and Ghostty (`src/terminal/tmux/control.zig`, `output.zig`, `viewer.zig`; PRs #9803, #9860,
  #14276); tmux's man page and CHANGES. Behaviour and protocol only; no code copied (iTerm2 GPLv2+, Ghostty MIT).
- Sources so far: tmux wiki "Control Mode" (framing, `%begin/%end/%error`, `%output` octal escaping,
  `pause-after` flow control, `refresh-client -C/-A/-B`); iTerm2 tmux integration page (limits: size capped by
  the smallest client; 3.7 notes OSC 52 queries with tmux 3.6+, key reporting restored with tmux 3.5+); WezTerm
  has no control mode (issue #336 open); Ghostty's parser and viewer merged Dec 2025, no GUI yet.

## Also seen, not caused by today's work

- `LiveTmuxTests.claimedSessionSeesWhatATypedOneSees` fails on the Linux test VM: PATH in a claimed session adds
  `/opt/homebrew/bin` and the typed one repeats `~/.local/bin`. To look into.

## What other clients teach (research, 2026-10-19)

Read: iTerm2 `ec4517e` (the only complete client), Ghostty `c7cbc9b` (parser and viewer only), tmux master
`a550207` (3.8 latest). Sources downloaded to `~/Software/glass/tmp/tmux-cc-research/src/` (working folder).
- **Start:** `-CC` needs a tty (raw, but CR/LF translation stays; DCS `\eP1000p` first); `-C` on a pipe is clean.
  A blank line detaches. iTerm2 sends nothing until a `%begin/%end` arrives, so a stray DCS can't make it type into a
  shell; it ends commands with `\r` and probes with `phony-command`. Answer `%exit` (with `wait-exit`) by a newline.
- **Replies:** match `%begin/%end/%error` in order, not by number (the counter is server-wide); flags 0 = not ours.
  After an error the rest of that line gets no reply. Errors are routine (3.8: modal panes).
- **Restore a pane, one `;`-joined line:** `capture-pane -peqJN -S -H` (history + active screen), the same with `-a`
  (primary's visible lines when the alternate screen is on), `list-panes -F` state (`alternate_on`, saved cursor,
  `cursor_x/y`, `scroll_region_upper/lower`, `pane_tabs`, cursor/insert/keypad/wrap flags, mouse flags,
  `bracket_paste_flag` (3.7), `pane_key_mode` (3.5); 3.8 `#{pane_private_modes}`), `capture-pane -p -P -C` (an
  escape sequence in progress), `refresh-client -A '%P:continue'`. Drop the pane's `%output` until that reply: output
  queued before the capture arrives before its `%begin`.
- **Output:** `%output %P data` / `%extended-output %P age … : data` (with `pause-after`); bytes < 0x20 and `\` as
  `\ooo`, everything else raw, split at arbitrary bytes — decode to bytes, one streaming parser per pane.
- **Flow control (3.2+):** `refresh-client -f pause-after=N`; `%pause` → `-A '%P:continue'` and re-capture. Without
  it tmux disconnects a client 300 s behind; 3.8 also at 64 MB of unread replies.
- **Input:** let tmux encode keys: `send -lt %P <plain run>`, `send -t %P 0xNN` for other characters,
  `send -H -t %P 1b …` for control bytes, key names with `C-/M-/S-` for modified keys (3.2+); ≤ 1000 characters per
  command, several joined with `;`. Keys go to copy mode if the pane is in it (`copy-mode -q` at attach).
- **Sizing:** `refresh-client -C W,H` (3.3+: `-C @id:WxH`); never send a placeholder size (iTerm2 shrank windows so);
  the grid must equal the pane. `window-size` default `latest` decides among devices.
- **OSC:** `%output` is the pane's raw bytes: OSC 7, 8, 52, 133, 9/777 and titles arrive unchanged (inferred).
  Don't answer terminal queries — tmux already did. State from before attaching (cwd, title, prompt marks) isn't in
  a capture: read `#{pane_path}`, `#{pane_title}` after attaching.
- **Versions:** gate each feature on `#{version}`; minimum 3.2. The Linux test VM has 3.6, the Mac 3.8.
- **Copy:** Ghostty's I/O-free `Viewer.next(input) → [Action]` state machine tested on scripted transcripts;
  iTerm2's FIFO queue with per-command error tolerance; one-line restore batches; per-feature version gates.

## Plan: the control-mode client (D83), 2026-10-19

**Authorization:** the owner, "write up the plan, then build it". Local work; committing at his word.

**Shape.** One session, one window, one pane per tab, so no layouts. tmux runs as `-CC` on the PTY it runs on
today (the SSH shell's, or a local pane's), so reconnects, takeover, naming and the side channel stay as they
are; only the bytes on that PTY change meaning once tmux says `\eP1000p`.

1. **Core, I/O-free, in `GlassTerminalEmulator` (`TmuxControl*.swift`):**
   - **Framer:** bytes before the DCS are the shell's and go to the terminal; after it, `\r\n` lines; `%exit` and the
     ST end it, and bytes after go to the terminal again.
   - **Lines:** `%begin/%end/%error t n f` (a block closes only on a guard with its `%begin`'s time and number;
     flags 0 = not ours, skipped); `%output %P …` and `%extended-output %P age … : …` (octal `\ooo` decoded to
     bytes); `%pause`, `%continue`, `%session-changed`, `%session-window-changed`, `%window-pane-changed`,
     `%layout-change`, `%exit`; anything else ignored.
   - **`TmuxControlClient`:** `receive(bytes)`, `input(bytes)`, `resize(cols, rows)` → `[Action]`
     (`.terminal(Data)`, `.transport(Data)`, `.event`). States: shell → starting → restoring → live → exited. A FIFO of
     sent commands, matched in order; after an `%error`, the rest of that line's commands are failed without blocks.
   - **Start** (after the first `%session-changed` or block): `refresh-client -C cols,rows` and
     `refresh-client -f pause-after=30` (never a placeholder size), then `display-message -p '#{pane_id}'`.
   - **Restore**, one line: `capture-pane -p -e -q -J -N -S -H -t %P` (history and the active screen),
     the same with `-a` (the primary's screen while an app has the alternate one), `list-panes -t %P -F <state>`,
     `capture-pane -p -P -C -t %P` (an escape sequence in progress), `display-message -p -t %P
     '#{pane_current_path}'`. The pane's `%output` is dropped until its last reply. The terminal is rebuilt: cleared
     with its history; primary lines; the alternate screen with `?1049h` after placing the saved cursor; scroll
     region; cursor; modes (cursor, insert, keypad, wrap, mouse, SGR mouse, bracketed paste where tmux has the
     format); pending bytes; the folder as OSC 7. Unknown formats on older tmux expand empty and mean off.
   - **Live:** the pane's `%output` → terminal. `%pause` → `refresh-client -A '%P:continue'` and restore.
     The active pane or window changing → follow it and restore. `%exit` → exited.
   - **Input:** while live, `send -l -t %P -- '<run>'` for printable ASCII without `'`, `send -H -t %P xx …` for
     everything else (literal bytes, so the program gets exactly what the terminal encoded for the modes it saw);
     ≤ 1000 characters a command. Before live, held and sent once live. Resize → `refresh-client -C`.
2. **Replies to queries:** tmux has answered them. While control output is fed, what the terminal sends is
   dropped (`SwiftTermHostModel.answersTerminalQueries`, the engines' feeding flag, the coordinators' `send`).
3. **Remote (`TerminalSession`):** `tmux -V` over the side channel before attaching; 3.2 or later →
   `exec tmux -u -CC new-session -A -s NAME`, else today's line. Output → client → terminal (recorded decoded);
   keystrokes, AI and snippet commands and the startup command → client (the startup command waits for live);
   resize → client. A UserDefaults escape hatch (`terminalTmuxControlMode`, default on).
4. **Local (Mac):** `tmux -V` with `MacLocalTmux.run`; `-CC` in `MacLocalTmux.arguments`; the local view's
   `dataReceived`, the engine's `sendUserInput`, `sendLocalCommand` and `sizeChanged` go through the client.
5. **What tmux used to do for us, now the terminal's:** in control mode the tmux scroll (`scrollTmux`, the local
   one), tmux's Find and the tmux Select All stand aside; the terminal's own history serves all three. Route A's
   filter stays off (the program's own alternate screen and mouse must reach the terminal).
6. **Tests:** framer/lines/octal; client transcripts (scripted, including errors mid-line, `%exit` text inside a
   block, a split UTF-8 character, `%pause`, a pane change); restore into a headless SwiftTerm (primary, alternate,
   modes, cursor); input encoding; live against the Linux test VM (tmux 3.6) through a real PTY: `seq` bursts all present in
   order once, an alternate-screen app restored, keystrokes echoed; local with a private `-L` server (tmux 3.8).
7. **Then:** builds for Mac, iPhone/iPad and Vision Pro, the app against the Linux test VM, install.

**Known limits, said up front:** split panes or extra windows made by another client aren't shown (the active
pane is followed); a device of another size can resize the pane (`window-size latest`); bracketed paste of a
program already running is restored only on tmux 3.7+; tmux older than 3.2 keeps today's attach.

## Built (2026-10-19), uncommitted

- **Core** (`GlassTerminalEmulator`):
  - `TmuxControlClient.swift`: the client, the framer (`TmuxControlStream`), lines (`TmuxControlLine`) and
    `TmuxSendKeys`.
  - `TmuxPaneRestore.swift`: one-line restore. History `-J`; the screen trimmed, or exact `-N` for a program's
    alternate screen; `-a` for the primary behind it; state; pending `-P -C`; `history_size` 0 means no history.
  - `TmuxControlPipe.swift`: local tmux as `-C` on pipes.
- **Host model:** `SwiftTermHostModel.isTmuxControlClient` and `keepsHistoryUnderTmux`. The engines'
  `isFeedingOutput`; the coordinators drop the terminal's answers while control output is fed.
- **Remote** (`TerminalSession`):
  - `tmux -V` once a session (`TerminalTmux.versionCommand`); 3.2 or later gets `-CC` on the SSH PTY
    (`attachLine(control:)`).
  - Output, input, snippets, the startup command and resize all go through the client.
  - Input is held until tmux starts, and given up to the shell after 10 s if it never does.
  - The client ends when the session leaves connected.
  - Scroll, Select All and Find stand aside (`keepsHistoryUnderTmux`).
  - Escape hatch: `defaults write com.glasspowertools terminalTmuxControlMode -bool NO`.
- **Local** (Mac):
  - `MacLocalTmux.supportsControlMode` (cached `-V`).
  - `arguments(control:)` gives `-C`, and `SwiftTermLocalProcessConfiguration.tmuxControl` is set.
  - The engine starts `TmuxControlPipe` instead of SwiftTerm's process. The view reads tmux's bytes
    (`receiveTmuxBytes`), writes through `tmuxWriter`, and tells tmux sizes from `setFrameSize`.
- **Route A removed:** `TerminalTmuxScreen` and its plumbing and tests.

**Why local panes use pipes, measured:**
- With `-CC` on SwiftTerm's local PTY, a 900-row burst stopped short in 3–5 runs of 8 under the suite's load.
- The output arrived the moment tmux wrote anything, whether our command or another client's.
- A `poll` reader, even a slow one, never stalled; a plain shell through the same reader never stalled.
- The trace showed small partial reads (180–458 bytes) against tmux's writes of up to 8 KB.
- **Conclusion:** SwiftTerm's GCD reader on a PTY leaves data until the next write when tmux writes so.
- Over pipes, read until empty: 0 stalls in 8, then 8 of 8 full suites green.
- A "nudge" (an empty command after output stops) was tried and removed: it was treating a symptom.

**Also learned:**
- tmux 3.8's `kill-server` answered 0 and left the test servers running; `kill-session` ends them. The tests
  use it, and 468 stale test sockets and dozens of servers were cleaned up.
- Live tests that block the main actor starved the suite's timing tests: the control tests are nonisolated,
  and the pane test polls visible text, not Find.

**Validation:**
- `TmuxControlClientTests` 15; `TerminalTmuxControlSessionTests` 2.
- `LiveTmuxControlTests` (tmux 3.8): PTY ×4, pipes ×1.
- `LiveTmuxControlPaneTests`: the app's own local runtime over pipes.
- `LiveTmuxTests.controlModeKeepsEveryLine`: the Linux test VM, tmux 3.6, over SSH. 150 restored and 2,000 at once,
  2,150 of 2,150 in order.
- All 919 terminal tests pass.
- Not yet: the app itself on a device or simulator against tmux.

## 0.4.482 installed (2026-10-19, at his word) — and a slow first launch, fixed in 0.4.483

- **Installed:** the Mac and iPhone took 0.4.482. The Vision Pro was unavailable (asleep or not on the
  network), so it still has 0.4.481. No crash reports. All 26 local tabs reattached as `tmux -C`
  clients with `pause-after=30`.
- **What he saw:** "Why did it take so long? ... used to be instant." The app sat at 100% CPU for
  about 15 s after launch, then 20–30% while idle.
- **Cause, measured with `sample`:**
  - Every line output scrolled called `refreshAccessibilityViewport`, which read the whole buffer
    (`getBufferAsData`) for the last 40 lines. This happened in each Mac engine and in the local
    proxy's `scrolled`.
  - Under the old attach the buffer was one screen. Under control mode it holds the pane's history,
    so a restore of N lines cost O(N²).
  - Measured headless in a debug build: 1 pane of 1,500 lines took 10.5 s; 2,000 lines took 15.3 s;
    26 panes of 1,500 didn't finish in 2 minutes.
  - When idle, every chunk from a background tab (dev servers, spinners) re-read the tab's whole
    history.
- **Fix:**
  - `SwiftTermBufferText.lastLines`: reads from the buffer's end, with the same lines as before.
  - All three engines' `visibleText` use it.
  - The coordinators' and the local proxy's `scrolled` skip the refresh while output is read; each
    engine already refreshes once per chunk. The local view gained `isFeeding`.
  - After the fix: 1 pane in 0.6 s; 26 panes in 2.2 s (debug).
- **Tests:**
  - `TerminalBufferTextTests` (5) compare against the whole-buffer read.
  - `LiveTmuxControlPaneTests.reattachWithHistory`: 2,000 lines, under 5 s, every row present. It
    failed at 15.3 s without the fix.
  - All 925 terminal tests pass.
- **0.4.483 installed** on the Mac (22:03) and the iPhone; the Vision Pro was still unavailable.
  - Eight seconds after launch the app was at 27% CPU, then 9–14% while idle. Under 0.4.482 it had
    been at 100% for about 15 s, then 20–30%.
  - A `sample` shows the main thread mostly waiting; the whole-buffer reads are gone.
  - No crash reports. All 26 tabs are control-mode clients. Not committed.
