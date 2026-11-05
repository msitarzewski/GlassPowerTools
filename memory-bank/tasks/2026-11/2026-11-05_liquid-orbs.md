# The orbs as liquid: jelly wobble, ripples, a springing dock (0.4.601, 2026-11-05)

**Asks (the owner):**
- "can we give the dock resize animation and the pulsing actual liquid effcts with metal or relaity kit? like awesome
  water effects, not cheesy anmations." Then: "Like a snap to wobble jelly feel? hah"
- His choices (asked): **Metal shaders + glass** over RealityKit 3D orbs ("try 1. it might suck or take too much GPU.
  We live in wow times, let's see it represneted in that dock and the app!"); the busy pulse as **drops falling in**
  (rings across the picture, the rim shivering as each arrives); a dock change as **a wave through the row**.
- He also said "Go ahead and commit here" first: 0.4.592–0.4.600 committed as `5ebfd0be` (not pushed).

**Status:** built, tested; 0.4.601. Uncommitted. Not yet seen on the headset or his Mac.

## What it is
- `GlassOrbJelly.swift` (GlassShell, pure, tested): a drop's rim as modes 2–5 (`GlassDropletDeformation`), Rayleigh's
  frequencies (ωₙ² ∝ n(n−1)(n+2), the oval about 3 Hz), damping growing with n; area kept exactly (`mean`). A push
  (`GlassJellyKick`) starts from round (sin) and has died within `settle` (1.4 s). `GlassOrbJelly.wave` bumps the
  orbs along the line, 0.62× and 70 ms later each orb further on; a landing is squashed from above at
  `landingDelay` (0.28 s, the fall's end). `GlassOrbJellyField` turns a line change into kicks (landed, left, carried).
  `GlassOrbPulseClock`: a drop every 1.5 s while busy, rings for 1.25 s, the rim's shiver (0.02, mostly 3 and 4 lobes,
  each drop its own way, each orb a random turn) for 0.5 s after a ring reaches the rim at 0.8 s.
- `Resources/GlassOrbLiquid.metal` (`.process` in Package.swift): a SwiftUI `layerEffect` that stretches the picture
  with the rim and refracts it through a ring wave (`waterAt`), with glints on faces turned to the upper-left light and
  caustics where the surface curves like a lens.
- `GlassOrbLiquid.swift`: `GlassDropletShape` (InsettableShape, 96 points), `GlassOrbLiquidSource` (per orb: dock
  kicks via `\.glassOrbKicks`, its own landing when shrunk where it stands, the pulse; schedules `live`/`rimLive`),
  `GlassOrbLiquidWarp` (picture), `GlassOrbLiquidRim` (shading, cut, Apple's glass in the drop's shape: `glassEffect`
  on the Mac, `glassBackgroundEffect` on Vision Pro). The rim redraws only while pushed or shivering; the picture
  while rippling too. 60 fps on the Mac, 90 on the headset. Reduce Motion / Low Power Mode: round, a glowing rim.
- Wired into `GlassSessionOrbView` (visionOS), `GlassMacSessionOrbView`, both Connections orbs, both docks (field,
  `.animation(GlassOrbJellyMotion.slide)` for neighbours). `GlassOrbDropArrival` keeps the fall, hands the squash to
  the physics, lost its white ring. `GlassSessionOrbPulse` is now the still fallback only. The Mac panel springs
  (`Spring(duration: 0.5, bounce: 0.45)`, stepped by a display link, ended at 0.9 s; it was a 0.28 s ease).
- DEBUG: `--demo-orb-busy` (every orb busy), `--demo-orb-solid` (liquid off, to measure).

## Validation
- Unit (`GlassOrbJellyTests` 11, `GlassMacOrbDockTests.springsToItsOrbs`): each seen failing under a break (mean
  dropped, cos for sin, non-Rayleigh frequencies, no falloff, the gap misplaced, drops after quiet, a shiver before the
  rim, carries ignored, no bounce, the rim always redrawn, no next rim change, every shiver one way). Package 3,364 pass.
- Vision Pro simulator, filmed (`simctl io recordVideo`, `--demo-orb-busy --demo-dock-carry`): the carried orb lands
  flattened, stretches tall, settles round in about a second; its neighbour bumps. First pass showed the shiver too
  big (0.028, lumpy) and in step on both orbs: cut and desynchronised. Ripples bend the terminal's text; on a dark
  picture their light is faint.
- macOS VM (`<work>/liquid/vm-liquid.zsh`): the panel overshoots and settles growing and shrinking; the
  ripples read clearly as rings of light on a black picture; Reduce Motion gives the glowing rim. Cost, app CPU in the
  VM with a busy docked agent terminal: solid 20–32 %, liquid 22–40 % (two runs each): about 3–5 % of a core. The VM
  has no GPU counters; the headset and his Mac are unmeasured.
- A VM crash report at 09:07 was a launch without `--ui-testing` (CloudKit container init in the ad-hoc Debug build),
  not this change.

- **Installed 0.4.601**, read back: headset, iPhone and Mac (running; no new crash reports), 2026-11-05.

## 0.4.602 (Vision Pro): the glass broke up on the headset
- His picture: the Connections orb's glass in white shards "after a scroll", then "it's in h and v modes on VP. Works
  fine on Mac" and "It's the same pattern on all previews". The simulator drew it whole before and after a scroll (the
  vertical-dock scroll test, filmed). Cause, by elimination: Vision Pro's `glassBackgroundEffect` given a shape other
  than its own (Connections had no shader, only the drop-shaped glass).
- Fix: `GlassOrbLiquid.shapesGlass` false on visionOS. The glass, its cut and the sphere's light are the system's circle
  again; `GlassOrbLiquidSquash` stretches the whole orb to the drop's oval (mode 2, a transform, as the landing's squash
  was since 0.4.512); the shader gets a round drop (ripples only); no rim shiver on Vision Pro. Filmed in the simulator:
  lands wide, stretches tall, round within a second. Built and installed as 0.4.602 on the headset, read back.

## Open
- See it on the headset and his Mac; GPU there (Instruments' Metal trace on the headset if wanted).
- Whether the ripples should read more strongly on dark pictures.
