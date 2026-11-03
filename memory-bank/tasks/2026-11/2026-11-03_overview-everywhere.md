# 2026-11-03 — A window's overview and carousel on iPhone, iPad and Vision Pro (D99)

## Task
- **Scope and authorization:** his report ("both seem to be missing coverflow and the new expose") and his two
  answers (D99). Local implementation, validation, docs, and installs on his devices as before; commit, push and
  TestFlight only at his word.
- **Owner:** this session. Files: GlassShell (new `GlassCarousel.swift`, `GlassTabOverview.swift`; navigation moved
  beside `GlassAllWindowsLayout`), GlassTerminal (`macOS/MacTerminalOverviewCarousel.swift` onto the shared row,
  `macOS/MacTerminalExpose.swift` typealias, `VisionTerminalWorkgroupView.swift` for iOS and visionOS, a
  cross-platform `TerminalOverviewStyle`), tests, help, release notes.
- **Reuse:** the Mac's `MacTerminalCarouselGeometry`/`Placement`/`MacTerminalCarousel` and
  `MacTerminalExposeNavigation` (moved, not copied); All Windows' card off the Mac (`GlassAllWindowsCard`: picture
  each second, mark, caption, backdrop) and `GlassAllWindowsLayout`; the headset grid's drag, drop and tab menus.
- **Validation planned:** package tests (shell, terminal); the carousel's tests moved with it and still biting; the
  Mac carousel unchanged in the macOS VM; iPhone and iPad simulators (button, grid, carousel, swipe); the Vision Pro
  simulator (grid, carousel depth); then his devices.

## Built (0.4.590)
- GlassShell: `GlassCarousel.swift` — `GlassCarouselGeometry`/`GlassCarouselPlacement` (moved from the Mac),
  `GlassCarouselRow` (flow, drag, tap, caption, accessibility; the Mac's trackpad through `scrollMonitor`), and for
  Vision Pro `depthPose` with `GlassCarouselDepthPlacement` (rotation3DEffect and offset(z:), animated by `d`).
  `GlassTabOverview.swift` — `GlassOverviewItem` (with `filtered`), `GlassOverviewTile` (All Windows' card with a
  selection ring), `GlassOverviewGrid` (one group in `GlassAllWindowsLayout`), `GlassOverviewFindField`; All
  Windows' group plate shared (`GlassAllWindowsGroupPlate`). `GlassAllWindowsNavigation` beside the layout.
- GlassTerminal: `TerminalOverviewStyle` (the Mac's key) and `TerminalViewChoice`; `TerminalWindowOverview` (iOS and
  visionOS: find, grid or carousel, keys, Vision Pro's drag/drop and tab menus, a tile backed by its terminal's canvas
  on Vision Pro, the window's theme page on iPhone and iPad); `TerminalViewMenu`. `VisionTerminalWorkgroupView`: the
  presentation on iPhone and iPad too, the overview over the tabs, Terminal View at the top left; Vision Pro's old
  grid (`spatialOverview`, `overviewCard`, `draggableCard`, `VisionTerminalPreview`) replaced; the picker lists
  Tabs, Grid, Carousel, Orb. The Mac's carousel is a wrapper on the row; its old names are typealiases.
- Demo: `--demo-carousel`; `terminal-agents-grid` opens the overview on iPhone and iPad too.
- Found and fixed: the iPhone's title ran under the bar's buttons with a long name (before this too); Terminal View
  went to the left and the title keeps to the room between the sides (`switcherRoom`).
- Not mine but from my builds: the scheme's pre-action took Mermaid 12.3.0 (`Tools/Mermaid/update-mermaid.sh`) and
  regenerated the acknowledgements; `AcknowledgementsTests` and the preview tests pass with it.

## Validation
- Tests: terminal 1099, shell 391, layers 56 pass. New: `GlassTabOverviewTests` (4), `TerminalViewChoiceTests` (5).
  Each seen failing with its piece broken (the front lifted twice the reach, then lifted short of a neighbour's edge;
  find returning all; the overview's style ignored), then restored and compared.
- Simulators (screens in the working-files folder, `d99/`): iPhone 17 Pro grid and carousel; iPad Pro 13 carousel;
  Vision Pro grid and carousel in depth (front out of the window, neighbours turned into the room, content behind the
  plane drawn). macOS VM: the Mac's carousel on the shared row — open, arrows, a click beside the front, a drag
  (settles), a scroll, Return — as before.
- Not seen: a real swipe on a phone, a pinch-drag on the headset, VoiceOver.

- 0.4.590 (Release, development signed) installed and read back on the Mac (running, no new crash report), iPhone
  and Vision Pro (590).

## State
- Installed for his look. Next: his check on the phone and headset (the depth's lift and turn are tuned from the
  simulator). Commit, push and TestFlight at his word.
