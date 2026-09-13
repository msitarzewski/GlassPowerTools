# visionOS design pass — native HIG, on the Glass language already built

**Date** 2026-09-13 · **Owner** coordinating agent · **State** BUILD — pass 1 done, unverified on device
**Authorization:** the user, from the physical headset: *"pay attention to the design. it's terribly
off… These are functional, but don't provide that polished magic visionOS experience."* Scope agreed:
**native visionOS HIG conformance plus the Glass/transparency/theme controls**, with visionOS-first
as the goal rather than a later wish. Sequenced **before Stage 4**, so the desktop capability is
built into the right patterns instead of inheriting the flat ones.

## The premise, corrected by measurement

The expectation was that glas.sh, glassdb and glassDT already carry most of the spatial language.
**They do not.** Counted across every Swift file:

| | `glassBackgroundEffect` | `.ornament` | `hoverEffect` |
|---|---|---|---|
| glas.sh | 4 | 9 | 2 |
| glassdb | 0 | 0 | 0 |
| glassDT | 0 | 0 | 0 |
| **Glass Power Tools** | 3 | 6 | 2 |
| GlassConnectionKit | 3 | 4 | 0 |

glas.sh's spatial vocabulary is essentially what already moved across — one ornament in
`VisionTerminalWorkgroupView`, a couple of glass surfaces, and the `focus-environment`
`ImmersiveSpace`, which is here as `FocusEnvironmentView`. There is nothing richer left to absorb.

**What the source apps did carry, and what is genuinely already in place, is the Glass language
itself:** `Sources/GlassLayers` (987 lines) — `GlassLayerState`'s two independent dimensions
(theme `opacity`, system-material `frost`), the four frost materials mapped to glas.sh's persisted
`glassFrost` values, `GlassLayeredWindow`, `GlassLayeredPanel`, the layer controls and the store.
That is good and stays; it is the substrate this pass builds on.

So: **HIG conformance is new work in all four codebases.** Saying otherwise would have set the wrong
expectation about how much of this is assembly versus design.

## What the headset actually shows

From captures taken on **My Vision Pro** (physical, not the simulator — the flatness is invisible
anywhere else):

1. **Primary actions are inside the window.** `GlassConnectionLibrary.withLibraryToolbar` places
   them with `.toolbar(placement: .primaryAction)`, which on visionOS renders in the window's own
   nav bar — three ~30 pt circles jammed into the top-right corner of the content. Apple's pattern
   is an **ornament attached below the window**.
2. **iOS type scale at visionOS reading distance.** Row names, "This Apple Vision Pro" and form
   footnotes are illegible at ~1.3 m.
3. **No hover effects on the library.** `hoverEffect` appears twice in the whole product and neither
   is on a row. visionOS is gaze-driven; a row that does not respond to look feels dead.
4. **Depth unused.** Everything sits at z = 0 on one plane — no elevation on modals, no layering.
5. **Empty state** is a small `ContentUnavailableView` card adrift in a large detail pane.
6. **Sheets** are iOS inset-grouped forms with pill Cancel/Save in the corners, presented small.

**Not a fault, and not to be "fixed":** the vertical rail on the left is the system's own visionOS
tab-bar ornament, produced by `visionNavigation`'s `TabView` + `.tabItem`. It renders as collapsed
icons until gazed at. That is correct native behaviour.

**Also not a fault:** the small dot near the centre is the user's deliberate eye-tracking reticle.

## Where the work lands

| Surface | Owner | Change |
|---|---|---|
| Library shell, scope rail, results, rows | `../GlassConnectionKit/Sources/GlassConnectionUI` | ornament for primary actions; row metrics and hover; empty state |
| Glass materials, elevation, panels | `Sources/GlassLayers` | visionOS elevation/depth helpers on the existing state model |
| Composition, sheets, settings | `Sources/GlassShell` | sheet presentation and sizing |
| Terminal and database surfaces | `Sources/GlassTerminal`, `Sources/GlassDatabase` | same treatment, after the shell is right |

`GlassConnectionKit` is a **live dependency and freely editable** — unlike the obsolete source apps.

## Validation, and how to actually get a picture

Every visionOS judgement comes from a capture on the **physical headset**. The UI suite runs there:
`-destination 'platform=visionOS,id=00000000-0000000000000A01'`, proven this session (a full run:
10 passed, 2 failed). The headset must be **unlocked** — a locked one stops the run at
*"Unlock My Vision Pro to Continue"* and xcodebuild waits rather than failing.

**Two capture facts, both measured, both non-obvious:**

1. **The visionOS simulator cannot screenshot through XCUITest at all.** Every `snap()` fails with
   *"Failed to get screenshot: Unable to take a screenshot - remote interface does not have this
   capability."* So the UI suite produces no images there, and a suite that captures on every step
   **fails on the simulator for that reason alone** — nothing to do with the app.
2. **`xcrun simctl io <udid> screenshot out.png` works fine.** So the iteration loop when the
   headset is unavailable is: build for the simulator, `simctl install`, `simctl launch`,
   `simctl io … screenshot`. That shows *layout* — ornaments, metrics, type scale — which is enough
   to iterate on. It cannot show how the glass sits in a real room, which is what the headset is for.

## Open before implementation

- Two on-device UI failures (`testCollectionsAreChipsAndFeed…`, `testAddServiceCollectsTheAddressOnTheHost`)
  both pass on macOS, so they are device-specific — most likely the documented visionOS secure-field
  focus hazard. To be diagnosed from the result bundle, not guessed at.


## Pass 1 — implemented 2026-09-13

Two of these were the app **fighting** the platform rather than failing to use it, which is why the
window looked flat rather than merely plain.

### The window was painting over the system glass

With the default Glass state (theme `opacity` 0, `frost` 1) `GlassLayerBackground` filled the whole
window with `RoundedRectangle.fill(.ultraThinMaterial)`. A `Material` is a **2-D simulation** of
glass: on a Mac it samples the desktop behind the window and convinces completely, which is why this
was never wrong before. In a headset it composites as an even translucent sheet with no specular
edge and no response to the room's light — and laid across the whole window it *covers* visionOS's
real window glass with a convincing-looking grey rectangle.

On visionOS the system surface is now the frost (`GlassLayeredWindow.frost`). The theme paint still
composites over it, so all four `opacity` × `frost` combinations survive, including fully clear.
`GlassLibraryDetail`'s action bar had the same fault one control smaller — `.background(.bar)` is a
material too — and now uses `glassActionBarSurface()`, which keeps `.bar` everywhere else. The
divider above it was already doing the separating.

### The seam was our own padding

`GlassNativeWindowFrame` insets content by 22/34/26 pt to keep it clear of the title and control
ornaments — and applied that inset **even when neither ornament is shown**. The library shows
neither, so its `NavigationSplitView` floated inside the window and visionOS drew its sidebar surface
inside the inset: a darker rectangle with a visible seam on all four sides, stopping short of the
window's bottom edge. The inset now follows the ornaments that justify it; a live canvas, which does
show them, keeps its padding.

Removing the frost is what *exposed* this — with a grey plate over everything, the seam was invisible.

### The rest of pass 1

| | Before | After |
|---|---|---|
| Primary actions | `.toolbar(.primaryAction)`, ~30 pt circles inside the window's top-right | `.ornament(.scene(.bottom))`, glass capsule, `.controlSize(.large)` |
| Spatial sidebar | system default width; row contents shrunk to fit it | 320–460 pt, so the row carries a full-size control |
| Row Connect | `compact` → `.caption`, 4 pt padding | `.body`, 9–12 pt padding, past the 60 pt gaze target |
| Row title / subtitle | `.headline` / `.caption` | `.title3` / `.callout`, **visionOS only** |
| Row interaction | none | `hoverEffect(.highlight)` |
| Empty detail | small `ContentUnavailableView` card adrift | given the pane, `.title3`, prominent extra-large Add Host |
| Host sheet | 620–680 × 560, iOS control metrics | 720–800 × 640, `.controlSize(.large)` |

`GlassSpatialMetrics.swift` (new, in the kit) holds the numbers in one place — Apple's 60 pt gaze
target, the row fonts, ornament insets — with `glassGazeHighlight()`, `glassSpatialRowMetrics()` and
`glassActionBarSurface()` as no-ops or pass-throughs off visionOS. **No macOS metric changed**, by
construction and by test.

### Verified

- `swift build`, and the app builds for macOS, iOS Simulator, visionOS Simulator and visionOS device.
- Package suite **946 tests / 90 suites** passing.
- **macOS UI 25 passed / 0 failed** after the row, metric and ornament changes.
- Simulator captures at each step (`simctl io … screenshot`), which is what caught both structural
  faults.

### Not verified, and this is the gap

**Nothing here has been seen on the headset.** It was locked from the first change onward
(*"Unlock My Vision Pro to Continue"*), and the simulator renders glass differently from hardware —
the very thing pass 1 changed. The frost and inset fixes in particular need a physical capture before
anyone calls them right.

### Next

- Device capture of the library, the host detail and the Edit Host sheet.
- The two on-device UI failures, still undiagnosed.
- Terminal and database surfaces, once the shell's language is settled.
