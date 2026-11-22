# 2026-11-21 — A tmux session's size held until a resize ends (0.4.633)

**Owner and authorization:** his question on a screenshot of a local tmux tab running Claude Code (the same answer
twice, the first copy's lines cut mid-word, blank rows in its table: "It's garbled output from a previous session
opening in tmux?"), then his word on the step I proposed: "yes, hold the size until the resize ends - seems like a
nice intermediary step. The /tui fullscreen screws us on scrollback iirc". Local edits, tests, VM runs; the Mac
install is standing. Committed and pushed 2026-11-22 at his word, with 0.4.634–0.4.638.

## What the screenshot showed
- Not a reopened session: the app had run since 2026-11-20 13:09, and that tab's Claude Code (2.1.330) started at
  13:13 on 11-21.
- Claude Code redraws on each new terminal size by erasing the rows on screen and printing its whole conversation
  again from the first line; the copy before is pushed into the history and never cleared (byte trace in
  anthropics/claude-code#107564, open on 2.1.310; many reports: #40555, #51828, #57145, #84247). Each copy is laid
  out for the width of its moment. In the screenshot: one laid out about 140 columns wide, then one about 96, in a
  terminal of 120. Lines wider than 120 broke at the edge mid-word; lines Claude Code padded with spaces to the old
  width (table rows) spilled a blank row. Claude Code's line breaks are real newlines, so no terminal rejoins them.
- What changed the size isn't in the app's log (it doesn't log tmux sizes).

## The cause on our side
- Both control-mode clients handed tmux every size as it came: the Mac's local tabs from the view's `setFrameSize` and
  SwiftTerm's `sizeChanged` (`SwiftTermHostView.swift`), SSH sessions from `TerminalSession.updateTerminalGeometry`
  (`Models.swift`). A window's drag gave tmux a size at every step, and each could be one more copy.

## Changed
- `TmuxResizeHold` (`Sources/GlassTerminalEmulator/TmuxResizeHold.swift`, new): once the pane is followed (`phase ==
  .live`), a new size waits until sizes stop changing for 250 ms and no window of the app is in AppKit's live resize
  (`NSWindow.inLiveResize`); then the last one goes, once. Before then (the attach, the pane being read) a size goes
  at once as before, and drops one held.
- The Mac view's two paths go through one hold (`resizeTmux`, `handTmuxSize`); `sizeChanged` now also passes on a
  `showGrid`, as `setFrameSize` did (safe: `showTmuxGrid` resizes SwiftTerm's model, which never calls the view's
  delegate back, checked in SwiftTerm's `Terminal.resize`). `TerminalSession` holds SSH sessions' sizes the same way.
- Help (`terminal-tmux.md`, "The terminal keeps the whole session"), RELEASE-NOTES 0.4.633.

## Checked
- New `TmuxResizeHoldTests` (3) and the session test (`TerminalTmuxControlSessionTests`: three sizes in a row write
  nothing, then one `refresh-client -C` with the last); 28 tests in the 3 suites pass. Each seen failing with its piece
  undone (`tmp/resize-hold/hold-bite.py`): the session handing every size on at once; a newer size not ending the
  earlier wait; a live resize not holding; a size handed on at once leaving the held one waiting.
- macOS VM (26.6, tmux 3.7c, Debug builds), a local tmux tab running a SIGWINCH counter (`tmp/resize-hold/winch.pl`),
  its window's right edge dragged 220 points by the VM tool (10 steps, 30 ms apart): the build before told the
  program three sizes (114, 96, 94 columns); this build one (94). Going full screen: one size (144 × 54); no count
  from the build before. `tmp/resize-hold/resize-check.zsh`.
- Found on the way: the sidebar doesn't change a terminal's size (showing it widens the window to the left; the pane
  stayed 94 columns), so it is no cause; my first answer to him named it, and was corrected.
- Not tried: an SSH tmux terminal live, iPad and Vision Pro window resizes (same hold, 250 ms, no live-resize signal
  there), Claude Code itself in the VM (no sign-in there).

- The terminal module whole: 1,317 tests pass (live tests skip on his Mac, `TMUX` set).
- 0.4.633 (633), Release, built for macOS, iOS and visionOS (Xcode-beta 27.3); installed 2026-11-21 15:31 on his Mac
  (read back from `/Applications`, running, no crash report), the iPhone and the headset (devicectl: "App installed").

## Next
- His use of it: a window resized with Claude Code in a tab should leave one copy, not several.
