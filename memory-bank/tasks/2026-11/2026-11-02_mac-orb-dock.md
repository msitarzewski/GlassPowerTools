# The orb dock on the Mac (D95, 2026-11-02)

- **Owner:** "We should consider a dock on Mac, exactly like visionOS for the same reason!" Asked, he chose: the orb
  button docks a window (⌘M stays the Mac's); where the dock floats is a setting; Connections is in the dock.
- **Authorization:** design approved by his three answers; local build, tests, installs within the standing
  authorization. Commit, push and TestFlight on his word.

## Plan
1. Share the orb's face (`GlassSessionOrbFace`, `GlassSessionOrbTab`, the control and its button, the sphere's
   shading, the pulse, the flow layout) between Vision Pro and the Mac; the Vision Pro code keeps its behaviour.
2. The Mac's dock (`GlassMacOrbDock.swift`): the model (docked windows by their open session's id, their windows held
   weakly, hidden by `orderOut`), the panel (an `NSPanel` made here, rule 62; floating per the setting), the view
   (Connections, terminal windows, machines; drag to reorder; fits its orbs, snaps when resized).
3. `glassSessionOrb` on the Mac: reads its window; the button hides it into the dock. Every window kind: terminal
   (`MacWorkspaceView`), database, desktop, editor, Connections.
4. A window shown any other way (Active, Show All Windows, the Window menu) leaves the dock; one closed is forgotten.
5. Relaunch: terminal windows and Connections come back docked as they were left.
6. Settings ▸ Appearance ▸ Orbs on the Mac: where it floats, Fit Dock to Its Orbs, the dock's look.
7. Tests for the model; a look in the macOS VM; help and release notes.

## Built (0.4.577)
- **Shared with Vision Pro** (`GlassSessionOrbFace.swift`): the face, its tabs and services, the control and
  `GlassSessionOrbButton`, the sphere's shading, the pulse, the dock's flow layout and scroll room, and
  `GlassOrbMetrics` (each platform's sizes). `GlassOrbDrop` builds for the Mac too. The Vision Pro orb and dock read
  the same values they had (orb 112, icon 24, raise 14, fall 70); its code is otherwise unchanged.
- **The Mac's dock** (`GlassMacOrbDock.swift`): `GlassOrbDockModel` (docked ids, windows held weakly through
  `GlassDockableWindow`, faces kept current by their windows, a picture taken as a window with none docks;
  Connections apart; what the next launch puts back), `GlassOrbDockPanel` (an `NSPanel` of its own, floating per
  `GlassOrbDockFloat`, fitted to its orbs with the middle of its bottom edge kept, snapping when resized by hand),
  `GlassMacOrbDockView` (Connections, terminal windows, machines; drag to reorder; end arrows; grows to show a new
  orb up to three rows), `GlassMacSessionOrbView`, `GlassMacConnectionsOrb`.
- **Every window**: `glassSessionOrb` on the Mac reads its window and docks it; the button beside Show All Windows in
  the terminal window, the shared ⚡ toolbar (database, editor), the desktop window and Connections.
  `GlassLibraryWindows` finds a docked Connections; the app's Dock icon brings it back
  (`applicationShouldHandleReopen`). The terminal window's face: its tabs with `TerminalTabMark`, the tab in front's
  picture over its theme's colour (the Mac's picture is the text alone).
- **Settings ▸ Appearance ▸ Orbs** (Mac): Dock Floats, Fit Dock to Its Orbs, the Dock's Opacity, Glass and Material.
- Found on the way: the Show All Windows caption drew "⇧⌘" (Markdown took the backslash); doubled.

## Found in the VM and fixed
- A size set inside the dock's own update was put back: the fit is applied just after.
- The dock's own animated resize reads as a live resize; taken as the person's, a dock fitted to Connections kept
  that width and the next orb wrapped out of sight. One that ends at the dock's own size is ignored.
- A dock hidden while empty and shown again drew what it held as it went: its content is made afresh, as Show All
  Windows' panel does.
- Under the clear title bar the orbs sat low and the bar over the orb: the dock ignores the safe area; the bar is
  its own row.
- Moved by its background, a drag on an orb moved the dock rather than the orb: the dock moves by its bar alone.

## Validation
- `GlassMacOrbDockTests` (9): each of five breaks (fading counted as shown, a quit's close saved, the last run's list
  dropped, no picture kept, taken twice) failed its test; the file restored byte-identical.
- macOS VM (Debug, `--ui-testing`), seen in captures: dock a two-tab terminal window (ring of two dots, its picture over
  its theme), dock Connections (count badge), bring each back by its orb (same frame), dock again with Connections
  in the dock (fits 305), bring back through Show All Windows, a hand resize into a column (174 × 366), the demo
  database docked onto its machine's orb and back by its dot with its tabs and SQL as they were, Active's count kept,
  Settings ▸ Appearance ▸ Orbs drawn. A second instance of the same run put Connections back in the dock.
- Also in the VM: an orb dragged onto another took its place, and the bar moved the dock by the distance dragged.
- Package tests: 3,313, all pass. 0.4.577 built for all three and installed on the Mac, Vision Pro and iPhone, each
  read back 0.4.577 (577); no new Mac crash report.
- Not seen: a terminal window put back docked after a relaunch (the demo's tabs are not in tmux, so nothing reopens
  them), Above All Windows, the desktop window docked, hover names on a real pointer, the owner's glass settings.

## Status
- Uncommitted. Next: his look on the Mac. Commit, push and TestFlight on his word.

## 0.4.578: Connections as on Vision Pro (his ask, from his screenshot)
- "let's make the connections version follow the vision model (all white circle, connection count and centered with
  the other orbs. We also have an orb icon we use in vision (it's circles?)." The orb is `GlassPowerToolsOrb` (the
  icon's layers on white), now `universal` in the asset catalog; the count is Active's bolt and number on the rim;
  the circle on the orbs' line, its name and count out of the layout.
- His screenshot also showed a band across the dock's top: the window policy's title bar material, full strength
  for a title the dock doesn't have. The dock now paints as a presented panel (`GlassLayeredPanel`), to its top edge.
- The count in clear glass read as cut in two (half on the circle, half on the dock): solid material with an edge.
- Checked in the macOS VM, dark and light. Not seen: the name on a real pointer's hover.
- 0.4.578 built for all three and installed on the Mac, Vision Pro and iPhone, each read back 0.4.578 (578); no new
  Mac crash report. Orb tests (48) pass.

## 0.4.579: a compact dock, names above it (his ask, from his screenshot)
- "Seems like this takes up a lot more space than it should. Let's remove that bottom tab and keep the edges of the
  dock the same distance from the windows. The label for connections doesn't line up with the window name in the
  dock." Asked where names go once the dock keeps no room for them, he chose **above the dock**, as the Mac's Dock.
- Each orb's cell reaches as far as its dots do, the same each way (`size(ring:)`; two tabs above and below leave it
  as narrow as the orb), plus 6 points; the dock 10 more. No room kept for names; the bar is gone and an empty part of
  the dock moves it (`GlassOrbDockMover`); orbs no longer stand above their cells' middles on the Mac.
- Names: the orb or dot under the pointer reports itself (`point`); the dock shows its name in a small child window
  of its own just above its top edge, over what it names, below when there is no room above, beside a dock taller
  than wide, level with the orb (`GlassOrbDockPanel.showName`).
- `vmtool move x y` added, to point without clicking.
- Validation: `evenEdges` measures from Connections' circle and a ring's outermost dots; it failed with room kept
  below a ring, with a wider side, and with a two-dot ring kept as wide as a full one. VM (dark): edges even, the dock
  183 × 156 (was 305 × 194), Connections, a window and a dot each named above it on one line, a drag on an empty part
  moved the dock by what was dragged.
- Also in the VM: a dock resized into a column names an orb beside it, level with the orb. Shell tests 384 pass.
- 0.4.579 on the Mac, read back (579), no new crash report. The iPhone and Vision Pro stay on 0.4.578: nothing of
  theirs changed.

## 0.4.580: Shrink to Orb is the orb's circle (his ask, from his screenshot)
- "Take a look at the vision pro "circle" icon (puts the window in the dock). That should be the standard here, not
  the two arrows. I think the Desktop, Database, and Editor need the same tweak on all platforms."
- The Vision Pro terminal's view menu drew the orb as `circle.circle`; the shared Shrink to Orb button
  (`GlassSessionOrbButton`: every Mac window's toolbar, and the bars of Vision Pro desktops, databases, editors and
  one-tab terminals) drew `arrow.down.right.and.arrow.up.left`, which is also Active's Take Over. One symbol now,
  `GlassSessionOrbButton.symbolName`, used by both. iPhone and iPad have no orbs.
- Seen: the macOS VM (dark), the circle in a terminal's and a database's toolbar, before Show All Windows; the Vision
  Pro simulator, the circle first in a database's and a one-tab terminal's bar. Desktops and editors draw the same
  button and were not pictured. No logic changed, so the unit tests were not rerun; all three platforms built.
- 0.4.580 on the Mac (read back 580, no new crash report) and the iPhone (read back 580). The headset was not
  available; it stays on 0.4.578 until it is.

## 0.4.581: the dock grows from Connections; the corners; the scroller (his asks)
- "Let's tweak the Mac dock to grow from the Active orb out... it should act as the root position." The panel kept
  the middle of the dock's bottom edge, so it spread both ways and Connections slid left with each orb. Now it keeps
  Connections' middle (`GlassOrbDockPanel.root`, from `GlassMacOrbDockView.root(of:width:)`, placed by
  `frame(of:placing:at:)`): orbs reach right, a taller row grows evenly above and below, rows go below, the screen's
  edge only holds it back. The person's moves and resizes set the root (`windowDidMove`, `windowDidEndLiveResize`,
  the dock's own frames excluded by `placing`); kept on this Mac (`orbs.dockRoot`; the old bottom-middle
  `orbs.dockPlace` read once for the first root, then removed).
- "We also need to see what's causing this odd corner display. Did we add an artificial black border for some
  reason?" No border: `GlassCanvasBackdrop` drew its frost rounded at 24 points always, over paint the window's own
  corners shape; the dock's utility panel rounds more tightly, so a crescent of bare theme paint showed in each
  corner (seen in the VM before the fix). The frost now takes the paint's radius (`GlassLayerBackground`), none in a
  window. The thin outline along the edges is the system's own, on every window.
- Found in the VM on the way: with a mouse attached the Mac shows a `.hidden` scroller; as an orb came while the dock
  was still Connections' width, the orbs wrapped, the scroller showed and took ~15 points, and they stayed in a
  column under it. `.scrollIndicators(.never)`.
- Validation: `growsFromConnections` (Connections' drawn middle stays on the root through orbs coming and going and a
  wrap; left edge fixed; row grows evenly); it failed with the dock centred on Connections (the old way) and with
  Connections' middle misplaced in its row. Shell tests 385 pass (a fresh scratch path: SwiftPM's `.build` held the
  Metal toolchain's old mount path; its build description moved aside to `tmp/stale-xcbuilddata`, still stale).
  VM: the dock 107 wide alone, 183 with a terminal, the same left edge and top; dragged −200, −100 exactly; the root
  saved (311,233) and a relaunch put Connections there; corners over the wallpaper one clean curve.

## 0.4.582: springs back to show every orb (his ask, from his screenshot)
- "I think it should also spring back to the shape that shows all of the orbs. [a column of two orbs in a dock
  three times their height] so this can't happen." Cause: on letting go, the dock asks for the size around its
  orbs; dragged taller than a dock already showing them all, that size was the same as before, the view's
  `onChange` never fired, and the panel stayed as dragged. Now `windowDidEndLiveResize` computes the shape itself
  from the orbs shown and applies it (the view's own ask that follows is the same).
- Taken literally, "shows all of the orbs": a resized dock is as wide as made and as tall as every row (it had kept
  the whole rows nearest the height given, as on Vision Pro, and three rows at most before a resize); only past the
  screen's height (`GlassOrbDockPanel.tallest`) the whole rows that fit, the rest scrolled to. The grow-to-show
  step for a new orb (`GlassOrbFlow.showing`) is gone from the Mac: nothing is hidden to grow to.
- Validation: `showsEveryOrb`; it failed with the given height kept and with no screen limit. Shell tests 386 pass.
  VM, before (0.4.581): narrowed to a column the dock kept one row (125) and hid the terminal's orb; a dock showing
  both, dragged 300 down, stayed 501 tall. After: the column sprang to 107 × 201 and both drags back to 201, left edge
  and top unmoved. (A VM crash report on that run was the ad-hoc test build relaunched by macOS at login without
  `--ui-testing`, trapping in `CKContainer` with no entitlements: the VM's, not the product's.)
- 0.4.582 on the Mac, read back (582), no new crash report.
