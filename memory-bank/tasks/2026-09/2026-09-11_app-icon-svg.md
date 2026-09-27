# App icon — SVG-first layers with light, dark and clear — W10, 2026-09-11

Worker W10. Requirement (user): the icon should have light, dark and clear modes like the
family's examples, authored SVG-first, and done carefully. The family contact sheet sets the convention:
LIGHT = near-white background, RED primary, GREY secondary; DARK = near-black background, RED
primary, WHITE secondary; CLEAR = the system's own rendition, "backdrop-dependent", not authored.
Not committed (coordinator commits).

## What replaced what

`App/GlassPowerTools.icon` held three raster layers aligned to the user's composite and a single
`automatic-gradient` fill — one appearance, no per-layer colour. It is now four hand-authored SVGs
with per-appearance fills, following the schema proven by the family's approved document
(an earlier approved `AppIcon.icon/icon.json`): top-level
`fill-specializations`, one group per layer, `glass: true`, and `{"solid": …}` per appearance.
The PNGs are deleted; `Assets/` holds only SVG.

## The four layers, top to bottom (index 0 renders on top — confirmed by render)

| Layer | Construction |
|---|---|
| `Prompt.svg` | Two round-capped strokes: the chevron `M420 357L490 412L420 464` at 36pt, and the underscore `M529 467H615` at 30pt. |
| `Screen.svg` | One rounded rect, x 283.4 y 274.4 w 455.6 h 272.7, r 20. |
| `Bezel.svg` | The monitor frame: outer rounded rect (x 246.6 y 239.3 w 531.6 h 347.0 r 34) with the screen aperture knocked out, `fill-rule="evenodd"`, so the red layer beneath shows through a true frame rather than being overpainted. |
| `Database.svg` | The neck (a 76-wide mini cylinder, y 573–604) plus one body cylinder (rx 114, ry 14, silhouette y 604–803) with two 8pt separator bands carved out along the disc curve at y 675 and 732, `fill-rule="evenodd"`. |

**The neck belongs to the Database layer**, not the bezel: it is the same secondary colour in both
appearances and it grows out of the disc stack, so it recolours with the database.

**Two earlier database attempts were wrong and were discarded**, both caught by rendering rather
than by reading the code. Three separate stacked cylinders read as floating washers, because the
gap between two cylinders is thin at the centre but as wide as the side offset at the edges (31pt
at the first attempt's proportions). Making the discs chunkier did not fix it. Carving separator
bands out of one body is what produces the classic database silhouette.

## Colours, and where each came from

| Role | Light | Dark | Source |
|---|---|---|---|
| Background | linear gradient 0.985 → 0.945 | linear gradient (0.18,0.19,0.21) → (0.075,0.08,0.095) | copied from the family's approved document |
| Screen (primary) | `srgb:0.90588,0.03529,0.03922` | same | **sampled from the user's own composite**, screen centre rgb(231,9,10) |
| Bezel, Database (secondary) | `srgb:0.62,0.62,0.63` | `srgb:1,1,1` | the contact sheet's grey-in-light / white-in-dark convention |
| Prompt | white | white | stays white on red in both |

The family's other red (`red-Default.png`, rgb(234,51,35)) was close but the user's own composite
red was preferred as the more faithful source.

## Verification

| Check | Result |
|---|---|
| `actool` compile, macOS, deployment 26.0 | **zero errors, zero warnings**; emits `Assets.car` + `GlassPowerTools.icns` |
| Appearance variants actually generated | **verified with `assetutil --info`**: `NSAppearanceNameAqua` ×5, `NSAppearanceNameDarkAqua` ×5, `ISAppearanceTintable` ×5; each of the four layers carries 3 variants, plus 2 gradients and 8 colours (4 layers × 2 appearances) |
| Rendered icon (light, through the real pipeline) | `scratchpad/w10/svg-v3-icns.png` — Liquid Glass specular and depth present |
| Light vs dark side by side | `scratchpad/w10/appearance-pair.png`, `appearance-light.png`, `appearance-dark.png` — **flat simulations I composited, not the OS rendering** |
| Flat geometry check at 1024 | `scratchpad/w10/svg-flat-v3.png` |
| App build, macOS Release 0.2.57 | passed; `Contents/Resources/` has both `Assets.car` and `GlassPowerTools.icns`; `CFBundleIconName = GlassPowerTools` |
| `swift test --build-system native` | **485 tests / 30 suites passed** |

**What I could not verify from the CLI:** the dark and tinted renditions *as the OS composites
them*. `iconutil` extracts only the default (light) rendition from the `.icns`, and `assetutil`
reports the catalogue's structure but does not render. The dark preview above is my own flat
composite of the same SVGs with the dark fills, so it proves the colour scheme, not the glass.
Seeing the real dark and clear renditions needs the installed app on a Mac in Dark Mode, or Icon
Composer's live preview. **Clear is not authored at all** — it is derived by the system from these
layers, which matches the user's own note on the contact sheet.

## Remaining

- Not installed (coordinator installs) and not pushed to iPhone or Vision Pro.
- `supported-platforms` kept as `{"circles": ["watchOS"], "squares": "shared"}` from the previous
  document, so iOS and visionOS keep building from the same file.
