# The dock keeps a hand's length; the keyboard only when asked (0.4.603, 2026-11-05)

**Asks (the owner):**
- With a photo of the whole visionOS keyboard under a terminal: "can we hide this keyboard until i reques it?" Asked:
  everyone, or a setting? **A setting** (Automatic as before, or Only When Asked).
- "we are artificially constraining the dock size. if it will fit one more and i rezize to ftt, that should be the new
  max width. does this make sense!?" (It does: the hand sets the longest; the dock still fits its orbs within it.)
**Status:** built, tested; 0.4.603. Uncommitted.

## Keyboard
- The headset's diagnostics file had no "system keyboard hidden" line at all: `GCKeyboard` never reported a keyboard,
  so 0.4.599's rule (hide while one is connected) never applied; the photo is the full keyboard visionOS shows when it
  sees none.
- `GlassOnScreenKeyboard` (`com.glasspowertools.terminal.onScreenKeyboard`, this device) on `GlassSystemKeyboard`:
  `holdsBack` = a hardware keyboard or Only When Asked; `hidesSystemKeyboard` = holdsBack and not shown anyway. Keys ▸
  Show/Hide Keyboard whenever it holds back. Settings ▸ Terminal ▸ On-Screen Keyboard (visionOS). Terminals and remote
  desktops follow it (desktops type text with Keys ▸ Type Text…).
- Tests: `GlassSystemKeyboardTests.onlyWhenAskedHoldsItBack` (bitten: the setting ignored; not kept).

## Dock length
- `GlassOrbDockLongest` (geometry, tested): per orientation (`com.glasspowertools.orbs.dockLongest.horizontal|vertical`),
  `fromHand` takes the hand's length to the end of the orb nearest it (more than half shown: whole), past every orb the
  length itself, at least Connections', at most `largest` (Vision 4000; the Mac, the screen's room).
- Vision Pro (`GlassOrbDockView`): the resize task keeps it and fits within it (it had sprung back to the dock's own
  longest since 0.4.600). Mac (`windowDidEndLiveResize`): the same from the panel's content length; a column's stays
  within the screen.
- Tests: `GlassOrbDockGeometryTests.longestFromHand`, `.longestKeptApart`, `GlassMacOrbDockTests.longestDragged`
  (bitten: whole orbs only; the Mac ignoring it; one key for both). UI: `testAResizedDockKeepsItsLengthInWholeOrbs`
  (500 wide: one orb whole, the other past the end, an arrow) replaces `testAResizedDockGoesBackToFittingItsOrbs`.
- The 0.4.602 UI run failed `testAQuickDragOnAnOrbScrollsTheDock` once: Connections at -246 before the swipe. The
  simulator log showed the two test windows docking 44 ms apart; when the dock opens between them, the second is an
  orb docked out of sight and the dock scrolls to it (by design). `dockTwoTerminals` now brings a scrolled dock back to
  its start before any test measures.
