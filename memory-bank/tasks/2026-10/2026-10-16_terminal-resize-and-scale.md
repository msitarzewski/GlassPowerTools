# 2026-10-16: a terminal window that resizes, and one that scales — NEXT PRIORITY (D75, proposed)

**State:** built (2026-10-16): engine, setting and bar button 394fb47; window shape and ⌘+/⌘− 3feb28a; the visionOS
UI test 2914f3f. 0.4.463 for the devices — for the owner to try. Details under "Built" at the end.

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

## Built (2026-10-16)

**What the owner sees.** Scale Text (an `aspectratio` button) in a terminal window's bar — the Mac's toolbar, the iPad
bar, the Vision Pro toolbar ornament — switches the window between Resize and Scale (This Window's When Resized).
Settings ▸ Terminal ▸ Resizing sets every window; Window Settings has When resized with This Window. Under Scale:
- the terminal keeps the grid it had (a Mac window opened under Scale keeps Settings' initial size, fitted first);
- the window is held to the grid's shape (Mac: one pane only; a split window's panes each scale into their part);
- ⌘+ / ⌘− grow or shrink the window by a tenth, ⌘0 sizes it so the text is at its font's own size (Mac, Vision Pro);
  on iPad they do nothing under Scale (no API sizes an iPad window);
- the host is sent nothing as the window changes; turning Scale off re-grids to the window and sends that.

**Code.**
- `GlassTerminalEmulator/SwiftTermScale.swift` — `SwiftTermScaledGrid`, `SwiftTermScaleLayout` (content size, fit,
  zoomed window), `MacTerminalScaleView` (the Mac engines' `hostView` now; bounds scaled under Scale).
- `SwiftTermHostView.swift` — `TerminalHardwareKeyContainerView` gains an always-present `scaler` (transform);
  engines' `setScaling`/`keptGrid`/`currentGrid`/`zoomWindow`; `SwiftTermHostModel.scaledGrid` (published, async),
  `setScaling`, `zoomScaledWindow`; the coordinators (and the local PTY proxy) pass on only the kept grid.
- `GlassShell/GlassWindowAspectLock.swift` — the desktop's lock moved and shared (`GlassWindowAspect` math;
  visionOS chrome fixed or measured around a canvas; Mac one look per turn, and a lock wanting no shape now also
  releases a ratio another view set). `DesktopWindowAspect` keeps only the desktop's chrome and minimum.
- `GlassTerminal/TerminalResizeBehavior.swift` — the setting's values, `TerminalScaleToggle`, `TerminalScaling`
  (the window's modifier). Setting plumbing as Show previews': `TerminalWindowSettings.whenResized`,
  `SettingsManager.whenResized` (`whenResized` key), the iCloud preferences (optional), both settings views.

**Measured.** AppKit gives a view under scaled bounds the shown scale (`contentsScale` 2 × 0.504 = 1.008), so Mac text
is drawn for the pixels it covers; `wantsDynamicContentScaling` is visionOS-only (unavailable on macOS and iOS);
iPad's Metal drawing is scaled as a picture.

**Tests** (each fails without its change): `TerminalScaleTests` 7 (half the window keeps the grid and sends nothing;
a font change keeps it and the host hears only the kept grid; back to Resize re-grids; ⌘− halves the window and not
the grid, ⌘0 = the font's own size; layout sums); `GlassWindowAspectLockTests` 2; When Resized profile and sync tests.
Mac suites: terminal 862, shell 302, desktop 222. visionOS simulator: `GlassTerminalOrnamentUITests`
`testScaleTextIsInTheBarAndSwitchesTheWindow` (Scale Text once in the bar, Off → Scaling → Off, the terminal stays)
beside the bar's existing test, both passing. Not covered: the scaler as a window is resized (past the simulator's
runner) — on the headset and an iPad for the owner. On iPad, Scale Text is an item in the bar's Tools menu.

**Not done / known.** The kept grid is not remembered across relaunches. Under Scale a font change in Settings
re-grids SwiftTerm's buffer for a moment (the host never hears it) and shows no change, the window setting the text's
size. SwiftTerm soft-resets the terminal on every font set (`resize(cols:rows:)` → `softReset()`), Resize or Scale —
noticed here, not changed.

## iPad, after the owner's "Sure" (2026-10-16, evening)

He pointed out iPad windows are real windows now (iPadOS 26's windowing; Stage Manager since 16), and on trying more
there: "Sure. I think we can let users let us know if that doesn't work." Measured on an iPadOS 27.2 simulator in
Windowed Apps (no iPad device):
- **⌘+ grows the window** (fa7b8b6). iPadOS has no request that sizes a window; it acts on a scene's
  `sizeRestrictions.minimumSize`, and a smaller window grows to it — when the minimum changes again, not while it is
  held. So Increase (and Reset, when the font's own size is larger) raises the minimum to the size asked for and puts
  it back 0.3 s later; the person can still make the window smaller. +10% a step measured (468×716 → 511×758 →
  558×813), growing about its middle.
- **⌘− still does nothing on iPad:** a maximum below the window's size never shrank it (held 1, 2.5, 6, 10 s; min = max
  together; with and without a geometry request). `windowIdealSize`/`windowIdealPlacement`/`defaultWindowPlacement`
  are unavailable on iOS in the 27.2 SDK.
- **Sharp text** (6fd8fc2): SwiftTerm's iOS Metal renderer draws at the screen's scale whatever the view's
  (`backingScaleFactor` = `UIScreen.main.scale`, 1.20.0), so a scaled picture was soft. Under Scale an iPad terminal
  now draws with SwiftTerm's Core Graphics (as Vision Pro always does), its `contentScaleFactor` the screen's × the
  scale shown (rounded up to 1/16); Resize brings Metal back unless it had failed. Edge half-tones on a line of text at
  about 2× fell 3989 → 3202 pixels; Metal had also drawn that scaled terminal a row off.
- **Tests:** `GlassTerminalScaleIPadUITests` — `testIncreaseGrowsTheScaledWindow` (skips outside Windowed Apps) and
  `testScaledTextIsDrawnForThePixelsShown` (a DEBUG, `--ui-testing`-only marker of the renderer and pixels per point);
  each failed with its change reverted. Run with `~/Software/glass/tmp/ipad-test.zsh` on the simulator "Scale iPad
  27.2" (Windowed Apps on); captures in `~/Software/glass/tmp/ipad-scale/`.
- **Unverified:** whether a hardware keyboard's ⌘+ reaches the font actions inside the iPad bar's Tools menu (the UI
  test runner's typed shortcuts didn't, in Resize or Scale; the menu items do). Seen in passing: an item with a folder
  icon and no title in the iPad Tools menu.

