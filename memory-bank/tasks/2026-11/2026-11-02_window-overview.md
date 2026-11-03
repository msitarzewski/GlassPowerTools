# 2026-11-02 — A window's overview as Show All Windows; the carousel removed (D96)

## Task
- **Scope and authorization:** his ask and three answers (D96). Local implementation, validation, docs; commit,
  push and TestFlight only at his word.
- **Owner:** this session. Files: `macOS/MacTerminalOverview.swift` (rewrite of `MacTerminalOverview`; the old
  item/session/navigation types it alone used go), `macOS/MacTerminalExposeView.swift` (tile, caption, agent mark,
  header, backdrop shared, no longer private), `macOS/MacWorkspaceView.swift`, `macOS/MacWorkspaceCommands.swift`,
  `Models.swift` (`OpeningView` without carousel, decoding it as grid; `gridCardWidth` gone),
  `VisionTerminalWorkgroupView.swift`, `TerminalWindowView.swift`, `WorkgroupRestoration.swift`,
  `WorkgroupEditorView.swift`, settings text, tests, help.
- **Reuse:** Show All Windows' own pieces — `MacTerminalExposeModel.groups/tile/filtered/selection`,
  `MacTerminalExposeLayout` (`GlassAllWindowsLayout`), `MacTerminalExposeNavigation`, the tab tile, caption, agent
  mark, header and backdrop — rather than a second drawing of the same thing.
- **Validation:** build all three; package tests (terminal, shell); the macOS VM (a window with several tabs:
  overview, typing, arrows, Return, Esc, idle fade); the Vision Pro simulator (Terminal View menu without Carousel).

## Built (0.4.583)
- `MacTerminalOverview` rewritten on Show All Windows' pieces: one group (the window, titled as Show All Windows
  titles it), a `MacTerminalExposeTabTile` per tab, `MacTerminalExposeHeader` (its own hint), the backdrop,
  `MacTerminalExposeLayout`, `MacTerminalExposeNavigation`, the same keys; the This workgroup switch and Auto-focus on
  activity under the tiles; the idle fade kept. Blur previews applies. Gone: the carousel, the card-size slider
  (`LayoutPreset.gridCardWidth`), the sessions open elsewhere (`MacOverviewSessions`, `MacOverviewItem`,
  `MacTerminalOverviewNavigation`, `GlassSessionCard`).
- Shared out of Show All Windows, its behaviour unchanged: `MacTerminalExposeGroupCard`,
  `MacTerminalExposeTileChrome`; tile, caption, agent mark, header, empty and backdrop no longer private.
- Mac: Terminal Overview on ⌥⌘G (was Terminal Grid); Terminal Carousel (⌥⇧⌘G) and its Command Center entry gone.
- Vision Pro: `OpeningView` is tabs and grid; the carousel branch, its naming surface and comments gone; a pinch on
  Terminal View goes tabs ↔ grid. "carousel" in a saved workgroup decodes as `.grid`; anything else unknown still
  fails, as before.
- Found on the way, in the VM: ⌫ did nothing in Show All Windows' find (the Mac sends it as the Delete command, not
  a key press). `.onDeleteCommand` in both.
- Found on the way, in a test run: `remoteChangeForAnotherModel` raced its own queued notices (a bare 100 ms). The
  model counts notices taken (`remoteChangesTaken`); the test waits for five taken without a sync. Red with the
  guard removed (30 s), 15/15 green under full CPU load.

## Validation
- Tests: terminal 1086, shell 386, connection UI 67 pass. `workgroupSavedForTheCarouselOpensInTheGrid`;
  `optionCommandGIsTerminalOverviewAlone` (⌥⇧⌘G free).
- macOS VM: View menu has Terminal Overview only; ⌥⌘G drew the window's three tabs as Show All Windows does; typing
  "zs" found two; ⌫ took back a letter (and in Show All Windows); ← and → moved the selection; Return opened the tab;
  idle, the controls and toolbar faded. Vision Pro simulator: tabs and grid draw. Not seen: the Terminal View menu
  opened on the headset (its list is `allCases`, pinned by the test).
- 0.4.583 on the Mac, iPhone and Vision Pro, each read back 583; no new Mac crash report.
- The App Store description file says "Tabs or a live grid"; App Store Connect is not updated (his word).

## 0.4.584 (Mac): the carousel as an album view (D97)
- His "i really wanted the carousel to work like the old album view in itunes", then "i dare you 😂 sick live
  animations, agent like expose?". New `macOS/MacTerminalOverviewCarousel.swift`: `MacTerminalOverviewStyle` (Grid |
  Carousel, `terminal.overviewStyle`, this Mac's), `MacTerminalCarouselGeometry` (place, turn, depth, scale by
  distance from the front; click mapping; settling), `MacTerminalCarouselPlacement` (a `GeometryEffect` animated by
  that distance, so a tab passes through the middle), `MacTerminalCarousel` (Show All Windows' tiles, reflections,
  the front's name below; trackpad via a local scroll monitor, drag with fling, wheel, arrows, click), Reduce Motion
  slides without turning.
- Auto-focus on activity holds the front 3 s in the carousel (`MacTerminalActivitySelection.carouselHold`): with
  several agents printing, following each at once swung the row every half second (seen in the VM).
- `vmtool scroll x y dx dy`: a pixel-precise swipe, to drive it.
- Validation: `MacTerminalCarouselTests` (6) failed with the old even spacing and with a click mapping that ignored
  the stacking; `carouselHoldsTheFrontBeforeFollowingTheNext` failed without the hold. Terminal 1093, shell 386
  pass. VM (agents demo): the row draws turned toward the front with reflections, agent marks and the activity wave;
  a swipe caught mid-flow; → → ← stepped 1, 2, 1 exactly (Auto-focus off); a click on a side tab brought it forward;
  typing narrowed; Return opened. Not seen: a real trackpad's momentum (the VM's swipe has none), the headset.
- The thumbnail question: recommended one tile in GlassShell for all the views, as the next step; not started.
- 0.4.584 on the Mac, read back (584), no new crash report. iPhone and Vision Pro stay on 0.4.583 (nothing of theirs).

## 0.4.585 (Mac): neighbours clear of the front (his screenshot)
- His "lol." with a screenshot of the carousel on his Mac: glass terminals, Blur previews on. The first tab either
  side tucked 0.1 of a tile under the front (gap 0.62), and through the glass showed as dark bands down its edges.
  The gap is now worked out from the neighbour's projected near edge (`nearHalf`) plus 3%.
- `neighboursClearTheFront` projects each corner of the first neighbour with the transform the row draws with
  (`MacTerminalCarouselPlacement.effectValue`), turning and not: clear of the front. Failed on both sides with 0.62.
  Terminal tests 1094 pass. VM: the neighbours stand just clear, both sides. On the Mac, read back 585.

## 0.4.586 (Mac): side tabs face the middle (his comparison with Apple's)
- "This is the apple version... should the rear windows be angled like this vs out?" Apple's album view turns each
  cover to face the middle: outer edge toward you, inner edge back. Ours faced out (the turn's sign backwards).
  `angle` flipped; the gap now from the inner edge's projected reach (`innerHalf`, going back so smaller), clicks
  from the outer's (`outerHalf`).
- `facesTheMiddle` measures on the transform that each neighbour's outer edge is drawn taller than its inner; it
  failed on both sides with the old turn. Terminal tests 1094 pass. VM: as Apple's. On the Mac, read back 586.

## 0.4.587 (Mac): a larger front (his "do we need to make the focused one larger? or nah?")
- Answered yes, unlike Apple's (a front read, not glanced at), by growing the whole row into the band rather than
  shrinking the neighbours: the tile is the band's height over 1.38 (was 0.56 of it), placed below the neighbours'
  outer edges (`outerEdgeHeight`, drawn taller) with the reflection's brightest part inside and the rest fading
  behind the name (`rowCenter`). His window: about 165 points tall before, height-limited.
- `tileSize` measures on the transform that the outer edges and the reflection's top stay in the band, and that the
  front fills it; failed with the old size and with the row placed at the top.
- A test settled on the way: `workspaceUsesNativeTitle` waited a bare 300 ms for the sidebar's slide (0.25 s, the
  window following after) and caught it mid-slide once. It now waits for it to settle (30 s deadline); failed with
  the title bar's sidebar follower disabled; the terminal suite passed twice under full CPU load.
- Terminal tests 1094 pass. VM: front 445 points wide in a 1024-point window (width-limited there). On the Mac,
  read back 587.

