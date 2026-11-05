# The dock a row or a column; Focus Mode the app's (0.4.600, 2026-11-05)

**Asks (the owner):**
- "We need to provide an orientation selection for the dock. horizontal or vertical, then honor that when
  adding/removing windows/sessions. Right now clicking the orb icon puts the window into the dock, but because the dock
  'window' shrunk when the window was moved out of the dock, it gets reinserted on a new row. That's not expected
  behavior. Maybe it does that because i've resized it at some point?" His choices (asked): past the limit **scroll
  along it**; a hand resize **not kept, fit the orbs**; **both** docks (Vision Pro and Mac).
- "I see another issue with focus environemnts... they need to persist. It seems that they're attached to the window.
  It needs to be an app level switch. When I set an envirnemnt, I want that environment to persist between moving
  windows to and from the dock", then "What do you mean from one tab? In vision, aren't Windows treated as entities?"
  (about the moon fix, 0.4.598).
**Status:** built, tested; 0.4.600. Uncommitted.

## Cause (dock)
- The dock's orbs flowed into rows (`GlassOrbFlow`) within the size it was left at (`com.glasspowertools.orbs.dockSize`,
  kept as the person's whenever the dock saw a size it hadn't asked for, `GlassOrbDockView.resized`). The headset's kept
  size was **1514 × 414** (its settings file, copied with devicectl): one row holding Connections and about four ringed
  orbs, so the next window docked wrapped to a new row and the dock grew a row (`GlassOrbFlow.showing`). Whether he had
  resized it or the dock's own shrink was taken for a resize, the log can't say (the dock logs to the system log only).

## Fix (dock)
- `GlassOrbDockOrientation` (GlassShell geometry; `com.glasspowertools.orbs.dockOrientation`, horizontal until chosen)
  and `GlassOrbLine` (frames in one line, the dock's fitted size: every orb, or the whole orbs that fit in the longest,
  one orb thick) replace `GlassOrbFlow`; `GlassOrbLineLayout` replaces `GlassOrbFlowLayout`; scroll views along the
  line; end arrows left/right or top/bottom (`orb-dock-more-left/right/above/below`).
- **Vision Pro** (`GlassOrbDockView`): a row up to 1700 points, a column up to 1340; a hand resize goes back to the fit
  when the hand lets go; the kept size is now the last fit (where it opens next); `isTall` is vertical (windows come
  back beside it). DEBUG: `--demo-dock-longest N`.
- **Mac** (`GlassMacOrbDockView`, `GlassOrbDockPanel`): a row up to 1100, a column up to the screen's room; a dragged
  edge keeps Connections' place and springs back to the fit; `resizedByHand` and the kept size gone; names beside a
  vertical dock; it grows from Connections as before (right for a row, down for a column).
- Settings ▸ Appearance ▸ Orbs: **Dock** Horizontal/Vertical on both; **Fit Dock to Its Orbs** gone; "Windows From a
  Vertical Dock".

## Cause and fix (Focus Mode)
- `TerminalWindowView.handleTerminalDisappear` dismissed the immersive space when the view that had opened it went away,
  which docking does: Focus Mode closed. And the environment was per window (This Window ▸ Focus Mode, and the moon's
  menu wrote the window's override), so another window, or one coming back, could bring its own.
- Now: Focus Mode isn't closed by a view going away; `FocusEnvironmentView` closes it once the last terminal session is
  gone (no moon left), not when opened with none (Try Out). The environment is the app's: `focusEnvironmentID` is
  `settingsManager.focusEnvironment`; the moon's menu sets and saves it; This Window's Focus Mode section and
  `TerminalWindowSettings.focusEnvironment` removed.

## Validation
- Unit: `GlassOrbDockGeometryTests` (row, column, fits, dockedAgain, orientationSetting; each failing under a break: the
  gap removed, the longest ignored, the default vertical; a line that wraps after three fails dockedAgain);
  `GlassMacOrbDockTests` (evenEdges, growsFromConnections for both, columnFitsItsOrbs). Package 3,352 pass.
- UI, Vision Pro simulator (11 pass): `testTheDockIsARowOrAColumn`, `testAQuickDragOnAnOrbScrollsTheDock`,
  `testAResizedDockGoesBackToFittingItsOrbs`, `testTheDockShowsArrowsWhereThereIsMore`,
  `testAWindowDockedAgainGoesBackIntoTheRow`, `testAWindowFromATallDockComesBackBesideIt` (vertical),
  `testHoldingConnectionsInTheDockOpensItsMenu`, `GlassOrbRelaunchUITests.testAVerticalDockStandsInAColumn`,
  `FocusEnvironmentUITests.testFocusModeStaysOpenAsTheWindowGoesIntoTheDockAndBack`, `testTheLibraryChoosesForEveryWindow`,
  `testEveryTabsMoonOffersFinePositionWhileFocusModeIsOpen`.
- The Focus dock test, opened by `--demo-focus`, passed with the old closing put back (the demo can open it from a view
  that isn't the one shown); rewritten to open it with the moon and dock with Shrink to Orb, it **fails with the old
  closing** ("Focus Mode closed with the window in the dock") and passes with the fix.
- The re-docking UI test can't fail on the old code in the simulator (the simulator never kept a wrong size); its guard
  is the geometry test.
- Mac: the macOS VM, below.
- **macOS VM** (`~/Software/glass/tmp/dock-orient/vm-dock-line.zsh`, the Debug app): a row, Connections and a terminal
  docked 183 × 156; the terminal brought back (Show All Windows), 107 × 125; docked again, 183 × 156, the same row; the
  corner dragged out and up, back to 183 × 156 (Connections where the drag left it). A column: 107 × 269 → 107 × 125 →
  107 × 269; dragged, 107 × 269. Pictures `row-again-crop.png`, `column-again-crop.png`.
- **Installed 0.4.600**, read back: headset, iPhone and Mac (no new crash reports), 2026-11-05.
- On the headset: windows' own environments are no longer read; the app's is Settings ▸ Terminal ▸ Focus Mode's until
  he chooses one from a moon.
