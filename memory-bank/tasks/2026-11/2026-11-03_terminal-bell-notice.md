# A terminal's bell, rung out of sight, marked in orange until seen (2026-11-03)

**Ask (the owner):** "We can detect when a terminal sends a bell, right? Let's add an indicator when that happens. If
the window is in the doc, turn the icon for that tab a shade of orange. If the tab is visible in an open window, but
not selected, show an orange glow under the tab. You decide how to address expose and coverflow. :)"
**Status:** built and tested (0.4.593); uncommitted.

## Where the bell is kept
- `TerminalBellNotice` (GlassTerminalEmulator, `@Observable`): `isUnseen`, `ring()`, `isInSight` (true clears it,
  and a bell then leaves nothing). On `SwiftTermHostModel.bellNotice`, so a terminal whose window is in the dock (no
  view on visionOS, an ordered-out window on the Mac) still records it.
- Rung from all three bell paths: the iOS/visionOS and Mac coordinators' `bell(source:)`, and the Mac local shell's
  delegate proxy. The window's own sound/flash (`onBell`) is unchanged.
- **Not tied to Settings ▸ Bell enabled.** That setting is off by default and is the sound and flash; tied to it, no
  one would have seen the mark (first built that way, found in the simulator, undone).
- In sight: iOS/visionOS `TerminalWindowView` — its tab in front (`isTerminalActive`), scene active, the window not
  its orb (`glassWindowOutOfSight`); off on disappear. Mac: `MacWorkspaceView` tells each tab
  (`MacWorkspaceController.setInSight`) from the selected tab and the window's occlusion state (docked, minimized,
  hidden: not visible), and not while Terminal Overview is up; a pane made later takes the tab's state
  (`observeOutput`). The Mac's `isTerminalActive` is the focused pane of a split, so it can't serve there.

## How it shows (`GlassBell`, GlassShell)
- Orange (`Color.orange`). Icons: `TerminalTabMark(rang:)` — orange, with an orange glow behind, because Claude
  Code's own mark is already orange (#D97757; OpenCode's and Mistral's too) and a plain recolour would not show.
- **Dock and orbs:** each tab's icon on the ring (Vision: `TerminalSessionMark(showsBell:)` in the window's own face and
  the capability's dock icon; Mac: `MacTabOrbMark`, read live because a docked Mac window draws nothing and its kept
  face would stand still). A window alone on its orb has no ring of tabs: `GlassSessionOrbFace.rang` (a closure, read
  as the orb draws) gives it an orange rim (`GlassSessionOrbBellRim`), both platforms.
- **Open window, tab not in front:** `glassBellGlow` beneath the row — Vision Pro's sidebar ornament row (full width),
  the Mac's sidebar row (weaker, 0.42: the headset's 0.7 read as a highlighter on the light sidebar). iPhone: the
  title's switcher glows while another terminal rang, and that terminal's menu item is a bell. iPad: the system draws
  its tab sidebar, so the tab's symbol becomes an orange bell. The Duo's fold cards glow beneath.
- **Exposé and coverflow (my choice):** a tile stands for its tab, so it glows beneath as a tab does — Show All Windows'
  cards (`GlassOpenSession.bellRang`/`hasUnseenBell`), a window's grid (`GlassOverviewItem.bellRang`), the Mac's
  overview, carousel and Show All Windows (`MacTerminalExposeTabTile`). Tiles of glass terminals are see-through, and
  the glow filled them: `outside` masks the tile's own shape out. Vision Pro's carousel stands each tile in real
  depth clipped to itself, cutting the glow off: there the tile's edge lights instead (`glassBellEdge`). Never on a
  reflection.
- VoiceOver: "Bell rang" in the value of Vision Pro's rows, Mac rows, grid tiles, All Windows cards, the iPhone menu
  and the Duo's cards. Not in the Mac's overview/Show All Windows tiles (their value comes from `MacTerminalExposeTile`).

## Validation
- `TerminalBellNoticeTests` (2): the rules, and SwiftTerm's own Mac view reading a BEL in output, through the host's
  coordinator, to the model with no window (an OSC 7 ended by BEL is not a bell). Seen failing with the Mac
  coordinator's `ring()` removed, and with the in-sight rule removed; restored and compared.
- Package tests: 3,338 pass (macOS).
- Builds: visionOS and iOS simulators (Debug), Mac (Debug, for the VM).
- visionOS simulator (`--demo-bell <tabs>[@<s>]`, DEBUG): the sidebar row glowing under bravo; Grid's two rung tiles
  glowing outside; Carousel's front tile's edge; the orb's ring with bravo's icon orange. Pictures in
  `~/Software/glass/tmp/paint-repro/bell-*`.
- macOS VM (`~/Software/glass/tmp/bell-shots/mac.sh`): bravo's sidebar row glowing; in the dock, bravo's tab icon
  orange beside alpha's grey. First runs showed nothing: the bell rang while bravo was in front (VM steps are slow),
  which is seen as it rings — the bell moved to 35 s.
- Found: a window that follows activity brings forward the tab that rang (a BEL is output), which is then in sight.
- Not seen: iPhone, iPad and the Duo's surfaces on screen (compiled only); the Mac's Show All Windows and overview
  tiles; the headset and his Mac (0.4.593 to install).
