# 2026-10-16: a terminal window that resizes, and one that scales — NEXT PRIORITY (D75, proposed)

**State:** BUILD (2026-10-16, after ~10:30). Questions settled with the owner; plan below.

## Settled with the owner (2026-10-16, after the compaction)

1. **Platforms:** Vision Pro, Mac and iPad windows ("vision mac and ipad multi-window"). Not iPhone.
2. **How it's chosen:** a setting (all windows, or This Window) **and** a button in the window's bar.
3. **Which grid:** the one the terminal has when Scale turns on — "If I've resized to 200 x 100, and choose to
   scale, keep that setting, do not override my terminal's current state."
4. **Shape:** held to the grid's shape, as a desktop window is held to its display's.
5–6 (not asked; recommendations): see the plan.

## Plan (decided in BUILD; evidence from SwiftTerm 1.20.0)

**Scale draws the kept grid at the terminal's own font and scales the drawing; it never changes the font.**
SwiftTerm's font setter calls `resetFont()`, which calls `resize(cols:rows:)` from the view's frame
(`AppleTerminalView.swift:297–316`), and `resize` always ends in `terminal.softReset()` (`:2827`). Cell metrics are
quantized too: height `ceil(ascent + descent + leading)` points, width snapped to the pixel (`:410–438`), so a font
that fits a window leaves a band up to `rows` points tall. A font change per frame of a drag would soft-reset and
re-grid the terminal continuously. A scaled drawing has none of that and fills exactly.

- **Emulator (`GlassTerminalEmulator`):** the engine's view sits inside a scaling view. Under Scale the terminal's
  frame is its grid at its own cell size (`getOptimalFrameSize()`), so SwiftTerm's grid sums give the kept grid, and
  the scaling view fits that into the space (uniform scale, centred). iOS/visionOS: an always-present scaler view
  (transform), so the terminal's own `frame` stays untransformed (`resetFont` reads `frame`). Mac: a container whose
  bounds are scaled (AppKit converts events and drawing). Crisp text: the Core Graphics drawing (Mac remote,
  Vision Pro) asks for `wantsDynamicContentScaling` under Scale; iPad's Metal drawing is scaled — measure.
- **The host only ever hears the kept grid under Scale** (a font change re-grids for a moment; the coordinator
  doesn't pass it on, and the layout restores the grid).
- **Setting:** `TerminalWindowSettings.whenResized` ("terminal.whenResized": grid / scale), global in
  `SettingsManager`, synced like Show Previews, This Window override; reaches the engine through
  `SwiftTermRuntimeSettings`.
- **Bar button:** toggles This Window's override.
- **Shape:** the desktop's `DesktopWindowAspectLock` moves to GlassShell (shared), the terminal window passes its
  grid's shape and its measured canvas. Mac: only while the window shows one pane. iPad: no API holds a scene's
  shape or sizes it (`UIWindowSceneGeometryPreferencesIOS.h` has only orientations), so iPad centres the text.
- **⌘+ / ⌘− under Scale** (recommendation 6): the font can't change without re-gridding, so they size the window
  (Mac, Vision Pro); on iPad they are unavailable under Scale.
- **Limits** (recommendation 5): none beyond the window's own minimum; the drawing scales as far as the window goes.
- **Later:** remembering the kept grid with the window across relaunches.

## What the owner asked

> "It's becoming pretty clear that we need both a resize capability and a scale capability. For example I may want a
> 120 x 40 terminal, but with a much smaller window. Today that resize adjusts the 120 x 40, now just the window."

- **Resize** (today's only behaviour): the window's size sets the grid. A smaller window means fewer columns and rows,
  and the program (tmux, an agent's TUI) redraws to fit.
- **Scale** (new): the grid stays — 120 × 40 — and the window's size scales the text to fit it. A smaller window means
  smaller text, not fewer columns.

## What the code does today (pointers, read before designing)

- The grid follows the view: SwiftTerm's `processSizeChange` (`Apple/AppleTerminalView.swift` ~:385) computes
  `cols = width / cellWidth`, `rows = height / cellHeight` and resizes the terminal (it also drops the selection). The
  session sends the new size to the host (`TerminalSession.updateTerminalGeometry`, `Models.swift`).
- iOS/visionOS: `TerminalHardwareKeyContainerView.layoutSubviews` (`SwiftTermHostView.swift`) sizes the terminal view
  to a whole number of rows.
- Font size: per terminal `SwiftTermHostModel.fontSizeOverride` / `resolvedFontSize` / `adjustFontSize(by:)`
  (`SwiftTermHostView.swift` ~:331), the font menu in `TerminalWindowView.fontSizeMenu`; per window
  `TerminalWindowSettings.fontSize` (W22) in `TerminalWindowProfile`.
- The Mac already fits a window to a grid at open: `SwiftTermHostModel.fitMacWindowToTerminalGrid(columns:rows:)`
  (~:551), used by `TerminalWindowView`'s `onResize` for the configured initial geometry
  (`session.currentTerminalGeometry`, Settings ▸ Terminal's initial columns × rows).
- Vision Pro window sizing: `GlassWindowSizer` (GlassShell), the desktop's shape lock (`DesktopWindowAspectLock`, a
  `.uniform` resize restriction) — the desktop already keeps a fixed picture in a resizable window, the nearest
  precedent for "scale".

## Open questions to settle with him first (restate and ask; he dictates by voice)

1. **Which platforms first?** Likely Vision Pro (windows in space) and the Mac; iPhone/iPad have little room to scale.
2. **How is the choice made?** A per-window setting ("When the window is resized: Change rows and columns / Scale the
   text"), a toggle in the window's bar, a modifier held while resizing on the Mac, or all of these.
3. **Which grid does Scale keep?** The grid at the moment Scale is chosen, a typed columns × rows, or the initial
   geometry setting.
4. **Shape:** with Scale, should the window hold the grid's aspect (as a desktop holds its display's, D-W38 `.uniform`),
   or letterbox the text inside a free-shaped window?
5. **Limits:** a minimum legible font size; what happens when the window is made larger than the grid at the largest
   size.
6. Does the font size menu (⌘+ / ⌘−) under Scale change the window's size, the grid, or nothing?

## Likely shape (a proposal, not decided)

A per-window mode in `TerminalWindowSettings` (synced, This Window override, like Show previews), defaulting to today's
Resize. Under Scale, the view computes the font size from the window's size and the kept grid (cells × cell metrics at
size 1, scaled to fit), sets it as the terminal's font size (a `fontSizeOverride` the user didn't make), and never
calls the grid resize; the session keeps sending the kept geometry. On Vision Pro the window could be held to the grid's
aspect with `.uniform`, as the desktop is. Tests: a pure "font size for (window size, grid, cell metrics at 1 pt)"
function, unit-tested; the Mac with an offscreen hosted terminal (`TerminalFindTests.HostedTerminal`) to show the grid
stays 120 × 40 as the frame shrinks.
