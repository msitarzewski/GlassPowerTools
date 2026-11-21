# 2026-11-19 — The Mac's dock after a relaunch: windows missing from it, a drag that didn't take (0.4.627–0.4.631)

**Owner and authorization:** his report, below; local edits, tests and VM runs, and the install on his Mac (the
standing "install Mac builds when ready", and his "install it on the mac when ready" this evening). Not committed, not
released: the release of 0.4.624 onward is held at his word.

## His report
- After installing 0.4.626, the app relaunched with six terminal windows in a vertical dock: "the dock only showed 4
  orbs, even though there were 6 in there... even after I tried to resize. I clicked an orb and was then able to resize
  to show 5. In addition, adding the 6th back made room." Asked how it should be: "Just make it launch at whatever I
  set it to or smaller as necessary maybe?" That is the design already (`GlassOrbDockLongest`, 2026-11-05): the dock
  keeps the length a drag leaves it at, to the nearest whole orb, and fits its orbs within it.

## What was found
- His Mac's log kept only the minutes after the relaunch (the dock logged at info level, which isn't kept): his later
  drags, `dragged to 156x998: longest 998`, then `156x1150`, were taken. The drags that failed left nothing.
- The code had three ways a drag could fail or the length be lost, none seen in the VM:
  - `placings`, a count of the dock's own moves, gated `windowDidEndLiveResize`. A spring whose display link stopped
    (its view replaced by `hide()` mid-spring) never took its count back, and every drag after it was ignored until
    the next orb came or went and started a new spring. That matches "clicked an orb and was then able to resize".
  - A spring under way kept setting the frame while a hand dragged the edge.
  - Any live resize not under `placings` was taken for the person's and kept as the length, AppKit's own included.
- VM (`glasspowertools-mac26`, six local tmux terminal windows docked, vertical, kept length 420): after a relaunch the
  dock came back at the kept length (4 of 6) and a bottom-edge drag straight after took (all 6, kept 656–706). With
  the dock against the top of the screen, a top-edge drag could add only 33 points, less than half an orb, so it
  sprang back as designed: his dock also sits near the top of his screen.

## Changed
- `GlassOrbDockMotion` (`GlassOrbDockGeometry.swift`): the dock's own moves against a hand's. A hand on the edge
  (a live resize begun with the mouse button down) stops a spring under way; the dock fits itself again only once it
  lets go; only a hand's drag changes the kept length; a spring counts as the dock's own for its length plus half a
  second, never longer.
- `GlassOrbDockPanel` (`GlassMacOrbDock.swift`): the count is gone; `stopSpring()` (also as the dock hides),
  `setOwnFrame`, `windowWillStartLiveResize`; the end of a drag uses the orbs the dock last asked for. "dock edge taken
  by hand", "dock dragged to … longest …" and "dock resized, not by hand" are logged at notice level, which is kept.
- Help (`library-connect.md`, Arrange the dock on Mac) and RELEASE-NOTES 0.4.627.

## Checked
- `GlassOrbDockGeometryTests` and `GlassMacOrbDockTests`: 30 passed. The three new tests each fail with their piece
  broken (no time bound on a spring; a hand not stopping the spring; any live resize taken for a hand).
- VM: relaunch with six docked, the kept length honoured, a drag right after taken and kept; the new log lines read
  back.
- Not reproduced: the ignored drag itself. If it happens again, `log show --predicate 'category == "orb-dock"'` now
  keeps what the dock saw.

## A wrong theory (0.4.628, undone)
- Installed 0.4.627 (23:02, by the detached installer, which relaunches the app from a background process: it comes
  back without coming forward). He: "Just did it again. Reloaded with 4 in the dock. I couldn't resize it. Dropped an
  orb in there and resized it to 6, no problem." His Mac's log: five windows docked (`docking` ×5), the dock drew four
  (`dock holds` stopped at four, the fifth docking 12 ms after the last redraw); his drag was taken and kept
  (`dock dragged to 156x1049: longest 1049`) but the dock fitted four orbs (677), its orbs' list unchanged; nothing
  redrew it for 30 s, until a window he docked did, with all six.
- The dock's view read what it holds, its orbs' sizes and its kept length inside a `TimelineView(.periodic(by: 1))`
  around the whole dock. On his Mac (macOS 27.3) neither its ticks nor a change to what it read inside redrew it for
  those 30 s (seen in the log). That the app was in the background then, and that this is why, is inferred: the
  installer's relaunch doesn't bring it forward, and a click that did ended it; not seen directly. In the VM (macOS 26)
  it redrew every second throughout, in front and behind, which is why no VM run showed it (a temporary log in the
  view, removed: "drawn 5 of 5" each second).
- Changed then: those reads moved into the view's body, a one-second task in place of the TimelineView. Installed as
  0.4.628, the relaunch (app in front this time) came back the same. **Wrong, and undone in 0.4.631**: the dock was
  redrawing all along (below).

## The cause, found on his Mac with a diagnostic (0.4.629–0.4.631)
- 0.4.629 and 0.4.630 logged, each second and on each redraw, what the dock held, what it drew, each orb's dots, the
  size it computed, the size it asked its panel for and what the panel did (temporary "DIAG" lines, removed). Each
  installer relaunch reproduced it (four of four tonight). The log, 23:49:22: the view drew all five and computed
  156x813 for them; the panel had last been asked for 152x677 (four orbs) and was never asked again. SwiftUI, the same
  instant: "onChange(of: Fitted) action tried to update multiple times per frame" and "onChange(of: Array<String>)
  action tried to update multiple times per frame" (the "dock holds" handler). The same pair at 23:44:45, and
  "onChange(of: Moving)" (the orbs' liquid, `.task(id:)`) at each relaunch since 23:02.
- So: five windows put back within about 0.2 s; SwiftUI ran the dock's `onChange` handlers for the third and fourth,
  then dropped the fifth's as a second run in one frame and kept its value as seen, so it never came again. The panel
  kept four orbs' size with the fifth scrolled out of sight; a drag fitted the orbs the panel had last been given, the
  four, and sprang back. A window docked later changed the value again, and all fitted.
- Fixed (0.4.631): `GlassMacOrbDockView.passOn` compares the size, orbs and ids with what it last passed on (a box,
  `PassedOn`) each time the dock is drawn, and passes any difference on just after (`DispatchQueue.main.async`): the
  panel's fit, the "dock holds" log, the jelly and the scroll to a new orb. Drawn each second, a difference can't stay
  unpassed. The two `onChange` handlers are gone; the TimelineView is back as it was.
- `GlassOrbDockMotion` (0.4.627) stays: it wasn't the cause, but each of its three cases can happen (tested, each test
  seen failing without its piece), and its notice-level lines are what to read if a drag is ignored again.
- **Verified on his Mac (0.4.631, 2026-11-20 00:09):** the installer's relaunch put five windows back within 0.25 s
  (the burst that failed four times before); the dock logged all five and fitted 156x813, its window measured
  156x813, and no "onChange(of: Fitted)" fault. The VM (five ringed windows, three relaunches; docking one at a time)
  fitted every time.
- Not fixed: the orbs' liquid `.task(id: Moving)` dropped the same way at relaunch; at most an orb doesn't wobble as it
  lands. Noted for later.
