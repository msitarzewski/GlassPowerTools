# 2026-11-02 — The Mac's orb dock in Liquid Glass (D98, 0.4.588)

**Owner's ask (late evening):** the dock "use a liquid texture like Apple's", the orbs' dots "liquid drops like
buttons vs the gray background", Connections the same ("Thoughts?"), and the motion: "pretty low framerate … no
actual liquid feel other than what looks like a 4 bit color animation". Screenshots: the dock on a pale wallpaper
("full glass on light"), Control Center in its Clear look ("Like this!"), the dock over a photo ("as flat as flat
is").

**Authorization:** his "let's make…" for the look; Connections answered yes (his question). Local build, VM checks
and a Mac install, as for every build this session. No commit, push or TestFlight.

## What was measured (VM, macOS 26.6; his Mac is 27.2)
- Probes, in the working-files folder: `glass-probe` (nine kinds of glass over stripes, pale, dark/light),
  `glass-probe2` (six dock mockups; then panel styles; then key state and forced-active attempts).
- SwiftUI materials and both glass APIs all sample the desktop behind a clear panel. On an even pale wallpaper in
  dark mode every one is an even grey, Apple's glass included.
- Clear Liquid Glass, as Control Center's, only in the key window of the active app (`titled-key*.png`); every other
  window gets the frosted inactive glass. `appearsActive`, `controlActiveState` and an `isKeyWindow` override did
  nothing on 26.6 (`active-probe*.png`). Other developers report the same (D98 lists them).

## Changed
- `Sources/GlassLayers/GlassLiquidSurface.swift` (new): `GlassLiquidLook`, `GlassLiquidSurface`, `glassLiquidKind`.
- `Sources/GlassShell/GlassMacOrbDock.swift`: the dock's look is the liquid surface (corner 26) with
  `appearsActive` set; drops of the dock's glass (orb with a 4 pt glass rim round its picture, dots, Connections with
  `GlassPowerToolsMark`); `GlassOrbBud`; no window shadow; the fit animated through `animator()` beside the orbs'
  animations (`placings` count, `fitDuration` 0.28); end arrows wait for the size to settle; rows at `fit` width.
- `Sources/GlassShell/GlassSessionOrbFace.swift`: `GlassOrbFlowLayout.widthAtLeast`.
- `Sources/GlassTerminal/TerminalTabMark.swift`: breathing by `phaseAnimator` (full ↔ 0.3, 1.4 s).
- `App/Assets.xcassets/GlassPowerToolsMark.imageset` (new): the icon's prompt, screen and database layers, light and
  dark, without the white.
- Tests: `GlassLiquidLookTests` (3), `GlassMacOrbDockTests.dotsBudOutOfTheirOrb`.

## Validation
- Shell 387, layers 56, terminal 1094 pass (SwiftPM, `--scratch-path` in the working-files folder).
- `GlassLiquidLookTests` bite: the kind fixed to Clear and the dim not scaled by Glass failed two tests; the paint
  ignored failed two.

## 0.4.588 on his Mac, then 0.4.589
- 0.4.588 installed and read back (588), no new crash report. His screenshots: frosted glass on 27.2 too; a dark
  crescent under Connections; "The icons animate on hover, but up and to the left?"
- Filmed at 60 fps in the VM (`screencapture -v` in the guest, frames by ffmpeg; `vm-liquid-video.zsh` in the working-files folder): leaving a
  dot made its glass shrink to a speck and regrow — the `GlassEffectContainer` takes a drop whose z-order changed for
  a new one and materializes it; the count lay under the container's glass; while the dock grew, its rows wrapped
  into a column at the widths along the way (Connections centred, an arrow flashing).
- 0.4.589: no container; z-order as before; the solid count back; rows laid out at the width the dock grows to
  (`GlassOrbFlowLayout.widthAtLeast`, shared with Vision Pro, default 0 there); end arrows only once the dock's size has
  held 450 ms. Filmed again: Connections still, no arrow, no pop.
- `dotsBudOutOfTheirOrb` rewritten for no container (starts at the rim, rests clear); bites with the start at 0.
- Found, not fixed: the first drag of the dock that starts in its top strip (its clear title bar) after a ringed orb
  docks lands 15 pt off; later drags, and a first drag from its bottom, are exact. The same with the old blocking
  resize. A debug log of every dock move is in (`dock moved to …`).

## Released (2026-11-03)
- His "this is fine. ship it." on 0.4.589: committed and pushed (c869a828); released as the Mac's 0.4.589 (notarized,
  GitHub release v0.4.589, the feed entry). The help's Mac dock section brought in line with the glass.

## Next
- His choice for the frosted look (D98, Open). The first-drag offset. The site live once he runs provision.
