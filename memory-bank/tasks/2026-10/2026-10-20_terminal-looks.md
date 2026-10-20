# Terminal looks: backgrounds and glowing text (2026-10-20)

**His ask:** "We look at these terminals all day long, so I was hoping for some inspired ideas to keep them
interesting."
- He thought aloud about backgrounds that distort (pixelation, Matrix animation, blurs, images).
- He wants an image dropped into a window to become the background for every terminal in it.
- He wants glowing text: vaporwave, green, amber, Matrix.

Then: "document the direction in the memory bank, then build an experiment yes … live in general after you test in
the VM".

**Authorization:** an experiment, built into the app.
- Test it in the macOS VM, then install it ("live").
- Commit only on his word.

**Decision:** D84.

## Direction

- **The look is ours.** Inspired by CRT-era terminals and their culture, written from scratch: our own shaders and
  palettes.
- **No third-party code or assets** under licences the App Store build can't carry (D82).
- **Fonts:** a retro font only under OFL or MIT, after reading its licence.
- **Text first.** People read these windows all day:
  - Every effect sits behind the text, or around it, never over it.
  - A readability guard keeps contrast: a scrim between the background and the text, set from the background's
    brightness.
- **Motion that means something:**
  - The background can follow the terminal's activity: rain that quickens with output, a glitch when a command fails,
    a glow when an agent waits for input.
  - Otherwise it stays calm.
  - Unfocused windows quieten.
- **Ground rules:**
  - Still under Reduce Motion, in Low Power Mode and in windows that can't be seen.
  - Flicker is capped (photosensitivity).
  - What can be selected, and what VoiceOver reads, never changes.
- **Glass stays** ("Glass is the point" memory). A background is drawn over the window's canvas (its glass and
  Opacity) at its own Intensity, under the text, and is never forced opaque.

## What the platforms allow

- **Effects behind the terminal: easy, every platform.**
  - Terminals are transparent over the window's glass.
  - A view behind them is ordinary SwiftUI: Metal shaders (`colorEffect`, `layerEffect`), `TimelineView`
    animation, `.blur`, images.
- **Effects on the terminal's text: not through SwiftUI.**
  - Apple's documentation for `VisualEffect` says views backed by AppKit or UIKit render a placeholder in a filtered
    layer.
  - So a true glow (bloom), curvature or scanlines over the text need the text's pixels: a post-process pass in
    SwiftTerm's Metal renderer on iPhone and iPad, and possibly a Core Image `backgroundFilters` bloom on the Mac
    (to prototype).
  - The Mac draws with Core Graphics (`techContext.md`, Terminal renderer, measured 2026-10-19).
- **Standard CRT techniques for later:**
  - scanline and pixel masks that fade out where the screen's density would cause moiré;
  - bloom from a blurred copy;
  - barrel curvature, with input mapped through it;
  - burn-in from an accumulated texture that fades;
  - a phosphor colour map (luminance onto one colour, keeping a little of the original hue).
- **A conflict:** dropping a file on a terminal types its path (drop typing, `2026-10-16_drop-typing.md`). Setting a
  background needs its own place or gesture.

## Ideas, for him to pick from

1. **Backgrounds:**
   - an image (blurred, pixelated, tinted toward the theme);
   - Matrix rain;
   - a vaporwave sunset grid;
   - slow plasma;
   - a starfield.
2. **Glowing palettes:** phosphor green, amber, Matrix, vaporwave. Colours are theme presets; the glow comes with the
   pixel pass.
3. **Production looks different:** a tint or pattern per host.
4. **The background reacts:** speed with output, a glitch on a failed command, a breathing glow when an agent waits.
5. **Unfocused windows calm down.**

## The experiment (built 2026-10-20)

**What it is:** This Window gains two sections. Each row is one of the window's settings (W22), with ↺; nothing
changes for a window that sets none.
- **Look**
  - Start From: Digital Rain, Synthwave, Amber Phosphor, Green Phosphor, None.
  - Background: None, Picture, Digital Rain, Synthwave, Phosphor Screen.
  - For a picture: a well to drop on, Choose…, and Remove; then Blur, Pixelate, and Tone to Theme.
  - Intensity, Quicken with Output (rain), and Readability.
- **Text:** Text Palette (Theme's Own, Green Phosphor, Amber Phosphor, Digital Green, Vaporwave), Text Glow, Glow
  Color.

**How:**
- **Shaders:** `Resources/TerminalBackdrops.metal` (rain, synthwave, phosphor screen, pixelate, duotone, scanlines),
  compiled by SwiftPM into GlassTerminal's bundle and used through `ShaderLibrary.bundle`.
- **`TerminalBackdropView`:**
  - It sits between the canvas and the text: in `TerminalWindowView`'s canvas (Mac SSH panes, iPhone, iPad, Vision
    Pro) and the Mac local pane's background.
  - It carries the scrim.
  - It has its own clock, which eases between speeds.
  - It stops under Reduce Motion, Low Power Mode and with the scene in the background, and runs at 8 fps in an
    unfocused window.
- **`terminalTextLook`:** the terminal view itself gets the following.
  - A monochrome phosphor is `saturation(0.15)` and `colorMultiply`. Core Animation filters do work on the AppKit view
    (measured in the VM), so every colour follows, 24-bit too; a palette of 16 never reached btop.
  - The glow is a SwiftUI shadow, which follows the glyphs since the terminal's background is clear.
  - The filter is applied only while a phosphor is chosen. Choosing or clearing one rebuilds the view once (checked
    in the VM: content intact).
- **Pictures:** `TerminalBackgroundPictures` keeps them in Application Support (a run's own folder under UI tests),
  scaled to 2560 px, as JPEG, named `<UUID>.jpg`. A setting holding anything else is refused, since a saved Workgroup
  brings it from other devices.
- **The readability guard:** `TerminalReadability` raises the scrim until text is at 4.5:1 against the backdrop's
  bright parts (a picture's 90th-percentile luminance).
- **Output signal:** `SwiftTermOutputActivity`, its own observable object on the host model, so only the backdrop
  redraws (start and stop of a burst, not per chunk).

**Tested:**
- `TerminalLooksTests` (12): defaults, presets, picture names, import and scaling, refusal of non-pictures and of
  oversized files, brightness, palettes, the scrim's maths, the compiled shader functions, the output signal, and the
  clock.
- All 937 terminal tests and the 53 layers tests pass.
- **The VM** (macOS 26, Debug): the looks captured over the btop demo, all as intended after two fixes (the synthwave
  grid's inverted lines, the guard over-dimming synthwave).
- **This Window's controls** were found by accessibility, each labelled with its ↺.
- **Runtime palette switch:** pressing ↺ on Text Palette rebuilt the terminal with its content. No crash reports.

**Limits seen:**
- Vaporwave is a palette of 16, so 24-bit colours keep their own.
- The rain's glyphs are blocky 5 × 7 patterns, not a font.
- The sheet is a fixed height, so the Look rows need a scroll.
- **A demo race:** `--demo-close-connections` together with `--demo-look` opened no terminal window. The shot script
  minimises Connections instead; the cause wasn't chased.
- **Not done yet:** the per-host tint, the glitch on a failed command, and the agent-waiting glow. iPhone, iPad and
  Vision Pro were built but not looked at.

## After his first look (2026-10-20, 0.4.484 → 0.4.485)

- **He reacted:** "Holy shit on a stick. This is AMAZING."
- **"The preview in expose don't show the amazing terminals":** a preview is a snapshot of the terminal's own drawing,
  and the look surrounds it.
  - `MacTerminalPreview`, the one renderer of Mac pictures, now draws the backdrop (still, never animated) and the
    text look (phosphor and glow) around the snapshot, at the picture's scale (`previewSourceSize`).
  - Checked in the VM: an amber card in Show All Windows.
  - iPhone, iPad and Vision Pro previews still show the plain terminal.
- **His other Claude session noticed:** faint text (dim lines, dimmed diffs) washed out where it crossed a picture's
  sun. Fixes:
  - **`glassCeiling`:** a backdrop's pixels brighter than the text can be read over are darkened to that level, pixel
    by pixel, keeping their colour. The sun stays a sun.
  - **The level** (`TerminalReadability.ceiling`) keeps body text at 4.5:1 and dim text (55 % of the text's colour)
    at 2.5:1, after the window's Readability scrim.
  - **Under dark text** the old whole-backdrop scrim raise still applies.
  - In the VM, the sun behind btop's process list went from a bright disc to a golden one the text reads over.
  - One test added (13).
- **Demo:** `--demo-look` now reaches `terminal-tabs` and `all-windows` (`requestDemoTabs(windowSettings:)`).

