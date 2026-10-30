# 2026-10-28 — The family's icons in one style (exploration, parked)

`<work>` is the working-files folder outside the repository. Nothing in any project was changed; every picture is a
mockup from copies. **Parked at the owner's word** ("Let's come back to this. Make a note.").

## How it went
1. "what would our icon look like with the red background from Glass Space Maker (both Mac and Vision Pro)?" — our
   icon on Glass Space Maker's red gradient (light `srgb 0.886,0.027,0.027 → 0.690,0.004,0`; dark
   `0.690,0.004,0 → 0.490,0.063,0.063`). The red screen merged into the red.
2. Screen variants on red: red, graphite, dark graphite, cobalt. **His pick, "I kinda think I love this":** light =
   the red background with a **dark graphite** screen; dark = **near-black** background (`0.11,0.115,0.125 →
   0.035,0.038,0.045`) with the **red** screen. Vision Pro (one appearance) shown both ways.
3. "Let's see the whole suite like this" — the rule: light, red background with the main element graphite; dark,
   near-black with the main element red; silver, gray and white parts kept. The suite, corrected by him ("Glas.sh,
   GlassDB, and GlassDT are all deprecated … missing AutoPaper, AudioPaper, Brew Browser, and Agency Agents App"):
   Glass Power Tools, GlassProject, GlassHealth, GlassImageTools (Vision only), Glass Space Maker, AutoPaper,
   AudioPaper, Brew Browser, Agency Agents.
4. "stylize the brew browser box like the Glass Space Maker icon, and Fill the brain on the Agency Agents icon":
   Brew's box as white-framed graphite (light) or red (dark) panels, each panel with its own frame layer so a flap
   hides the edge behind it, barley white in both; Agency's brain filled (graphite/red) under a silhouette traced
   from its own curves, its outline and folds white.
5. "What other color than red would look good back there? Modern, translucent maybe?" — cobalt, midnight indigo,
   teal, violet, slate, and macOS 26's Clear style. Then "the slate row with cobalt instead of charcoal": slate
   background (`0.62,0.65,0.71 → 0.36,0.39,0.45`) with every graphite element in cobalt (the family's `#0047AB`).
   **Where it stands:** he liked the suite on one page; red/graphite and slate/cobalt are the two live directions.

## Open when it resumes
- The direction: red (light) + black/red (dark), or slate/cobalt (light) with a dark to match (black with cobalt, or
  black with red); Vision Pro red or black.
- Agency Agents' gray circuits are the weakest part on red and on slate: white, as in dark, proposed.
- Glass Space Maker is the other session's project: hand it the recipe rather than change it from here.
- Making it real starts with Glass Power Tools: `App/GlassPowerTools.icon` (light background, the screen and
  database as a layer per appearance) and the Vision layers (`App/Assets.xcassets/GlassPowerTools.solidimagestack`).

## Found on the way (real, for the shipped icon)
- **Apple's renderer ignores `image-name-specializations`.** `ictool` drew the default `image-name` in dark too;
  a layer per appearance with `hidden-specializations` (`[{value:false},{appearance:dark,value:true}]` and the
  reverse) renders correctly. Our shipped icon names `database.png` (brighter) for dark that way, so its dark
  rendition likely shows the light database art. Unverified in the compiled `Assets.car` and the real Dock.
- A partly transparent background is made opaque by the renderer: translucency is only the system's Clear style.
- `ictool` lives in `Icon Composer.app/Contents/Executables/ictool`; `xcrun ictool` is a different tool.
  `--export-image --platform macOS --rendition Default|Dark|ClearLight|ClearDark`. Its Clear exports draw a flat gray
  backing, not the wallpaper.

## Artifacts (`<work>`)
- `red-icon/`: `icon-red-variants.png`, `icon-mixed.png`, `Mixed.icon` (the red/graphite light, black/red dark icon),
  `recolor.py`.
- `suite/`: `suite.png` (the whole suite), `restyle.png` (Brew and Agency before/after), `build.py`, `build2.py`,
  `restyle.py`, `vision.py`, the `.icon` copies.
- `palette/`: `palette.png` (six backgrounds and Clear), `slate-cobalt.png`, `palette.py`, `slate_cobalt.py`.
