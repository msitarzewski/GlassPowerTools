# Vision Pro: typing unseen in a restored terminal until a resize (2026-11-03)

**Report (the owner):** "when I go to a terminal that's been restored on vision pro when I type it's not showing
up. I have to resize the window to get it to paint again."
**Status: open.** A misplaced repaint band was found and fixed (0.4.592), but the headset's counts show it can't be
the cause: the headset draws the whole terminal for every band. His symptom is unexplained; 0.4.592 records whether
each terminal draws, for the next time it happens. Uncommitted.

## Evidence from the headset (0.4.591, the app's diagnostics file, copied with devicectl)
- 18:56:24 UTC: all eight terminal views left their windows and came back at once (`renderer awaitingWindow`, then
  `coreGraphics`, eight each, within 0.3 s), after seven quiet minutes; three tabs reconnected and were closed.
- 18:56:45–18:56:55: 21 keys sent to the terminal holding the keyboard, their echoes back in 27–65 ms on average;
  every key a **changed-line repaint** (27 + 20 of them), none skipped. 18:57:01–06: four whole repaints with no
  lines named, which is what a window resize asks for. So the repaints were asked for and he still saw nothing until
  the resize: they were placed where he couldn't see them, or not drawn.
- The file ends at 18:57:47 and the app was not running when copied (21:08), so nothing later is recorded.

## Cause found (the visionOS simulator, with the real SwiftTerm view)
- SwiftTerm 1.20 on iOS and visionOS draws each buffer line at its number × the cell height in the scroll view's
  space (`drawTerminalContents`, `firstRow = contentOffset.y / cellHeight`); the screen starts at `yDisp`.
  `TerminalRepaintBand.rect` measured the band from the view's top (`bounds.minY`), which is the screen's top only
  while the terminal's rows fill the view.
- With fewer rows — tmux's window at another device's size (`showTmuxGrid`, D83's foreign grid) — the view also
  shows lines from before the screen. Repro: `--demo-foreign-grid 12` (new, DEBUG) on `terminal-typing`: 12 rows in
  a 41-row view, `yDisp` 9, the view's top at 0, the cursor drawn at 340. Measured from the view's top, a change on
  a mid-screen row named rows 9 above it (from the debug log's numbers; the demo types on the last row, which the
  band's reach to the foot covered).
- **The simulator draws the whole terminal for every band** (a temporary log of the draw's clip: always the whole
  697-point view), so it can't show a misplaced band on screen. Whether the headset draws bands alone is unmeasured:
  0.4.592 counts it.

## Fix (0.4.592, Vision Pro only)
- `TerminalRepaintBand.rect(…, screenTop:, bounds:)`: the band from where SwiftTerm draws the screen's first row
  (`yDisp × cellHeight`), cut to the view; nil when wholly out of sight (the whole terminal is repainted then, as
  before).
- `ReviewingTerminalView.setNeedsDisplay`: the live-screen test is SwiftTerm's (`!canScroll || scrollPosition >= 1`,
  yDisp at the live screen), not the scroll offset, which rests elsewhere with fewer rows.
- Diagnostics, written to the headset's file every 5 s: `line repaints (screen lower)` (the case above),
  `drawn whole` and `drawn in part` (what the system drew, from `draw(_:in:)`'s clip).
- DEBUG only: `--demo-foreign-grid <rows>` (`TerminalConnectFlow.demoForeignGridRows`,
  `TerminalSession.demoForeignGrid`).

## Validation
- `TerminalRepaintBandTests` 6 + fingerprint tests 3: 9 pass. The new `screenLowerThanTheView` (the simulator's
  numbers) fails with the band measured from the view's top (2 issues), the file restored and compared.
- visionOS simulator, Debug: with the foreign grid the log shows `screenTop 153`, the cursor at 340, the band 323–697;
  without, `screenTop 0` and the band 323–374 around the cursor at 340, as before.
- Installed on the headset, read back 0.4.592 (592).

## His check, and what 0.4.592's counts say (21:34 UTC)
- His word at 21:34:42: "tried it, typing shows now". By the file's times it was not on 0.4.592: the install closed
  0.4.591 at 21:31:44 (its last line), and 0.4.592's first line is its launch at 21:34:51 (restored windows, "connect
  on show" for each terminal). Nothing ran in between. So his try was on 0.4.591, between 21:12 and 21:31, where the
  symptom didn't appear.
- 0.4.592's first 18 s (launch with restored windows, 17 keys typed at 21:35:04–09): **288 draws, all whole, none in
  part**, across 105 line repaints; `line repaints (screen lower)` 0. The headset, like the simulator, redraws the
  whole terminal whatever band is asked for. **The misplaced band can't have hidden his typing**, and the shorter-grid
  case didn't occur. The band fix stays (correct, harmless); the repaint-band feature's only effect on the headset is
  the repaints it skips when nothing changed.
- So in the 18:56 episode each key's repaint would have redrawn the whole terminal, yet nothing showed until a
  resize. Left: the terminal didn't draw (its view out of a shown window, or the window not updated on screen), or it
  drew where it isn't seen. Next time it happens, 0.4.592's file says which: keys and line repaints with no `drawn`
  counts means it never drew.

## Found, not changed
- **With tmux's window shorter than the view, the dots for the space past the pane are misplaced** on Vision Pro (seen
  in the simulator's pictures, `~/Software/glass/tmp/paint-repro/foreign12/`); iPhone and iPad use the same scroll
  view and likely match, not checked. `TmuxUnusedAreaView` dots everything below the grid's height from the view's top, but the pane's rows
  are drawn lower down (the lines above it are history), so the dots fall over the pane's last rows and the history
  above is undotted. The Mac draws the pane from the top. Fixing it means resting the screen at the top (a bottom
  inset for SwiftTerm's scroll view), which the iPhone's Metal drawing would also have to honour. For the owner.
