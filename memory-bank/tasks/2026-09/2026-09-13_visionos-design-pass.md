# visionOS design pass — native HIG, on the Glass language already built

**Date** 2026-09-13 · **Owner** coordinating agent · **State** BUILD — passes 1 and 2 done; pass 1 still unverified on device
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

## Pass 2 — the user's list, from using build 0.3.81 on the headset

Recorded as given so nothing is lost. Struck through as each lands.

1. ~~**Setup modal overflows horizontally.**~~ Done. My own regression: `.frame(minWidth: 720)`
   on the sheet's `Form` asked for more width than the sheet that presents it, so every label was
   clipped at both edges — "Name" rendered as "me", "Address" as "dress". A visionOS sheet sizes
   itself; a minimum width is an instruction it cannot honour and does not refuse. Removed;
   `.controlSize(.large)` stays.
2. ~~**Inputs should align right like native inputs** — "I'd overridden that at one point but want
   to simplify. I want to keep the required interactions system though."~~ Done. Both capabilities
   carried `.labelsHidden().textFieldStyle(.roundedBorder).frame(width: 340, alignment: .leading)`
   on macOS, and the pickers carried the matching 340 pt box. That is not how any Apple platform
   lays out a form row, and on a narrow sheet it forced the content wider than its container. Now
   `.labelsHidden().multilineTextAlignment(.trailing)`, which is what the shell's own Name and
   Address fields already did. **Kept:** the Required badge and the validation messages — those are
   behaviour, not styling.
3. ~~**Move the small connection type icons under the machine name, tight leading, all
   platforms.**~~ Done. `GlassLibraryConnectionRow` gained a `badges` slot under the name; the
   kinds moved out of the trailing accessory, where they had been competing with Connect for the
   row's width and making the name truncate first. That competition is why the spatial sidebar had
   been shrinking its own controls to cope.
4. **Sidebars resizable on every platform, and positions remembered.** In progress.
5. **"+ Add a host" at the top of the sidebar with a hide/show toggle, like the Mac.**
6. **Settings in the top right.**
7. **Workgroups become a fleet-wide panel in the Connections sidebar, like Collections.**

5 and 6 are a re-arrangement of what pass 1 put in the bottom ornament, not a retreat from it — the
user's words were *"love the bottom ornaments on the connections window!"* The ornament stays; what
lives in it changes so the Mac's semantics carry over: Add Host belongs to the sidebar, Settings
belongs top-trailing.

7 is the largest of the seven: a new library scope alongside Collections, which lands in
`GlassLibraryNavigation` and `GlassLibraryScope` in GlassConnectionKit, not in this app alone.


## Pass 2 — implemented 2026-09-13, from the user driving builds 0.3.81 → 0.3.99

Seven items were asked for; six landed, and working through them surfaced four defects nobody had
asked about.

| | |
|---|---|
| Setup modal clipped horizontally | **Mine.** `.frame(minWidth: 720)` on the sheet's `Form` demanded more width than the sheet presenting it, so labels clipped at both edges — "Name" rendered as "me". A visionOS sheet sizes itself; a minimum width is an instruction it cannot honour and does not refuse. |
| Inputs not native | Both capabilities carried `.labelsHidden().textFieldStyle(.roundedBorder).frame(width: 340, alignment: .leading)` on macOS, and the pickers the matching box. No Apple platform lays a form row out that way. Now label leading, value trailing. **Required badges and validation kept** — behaviour, not styling. |
| Service icons under the machine name | `GlassLibraryConnectionRow` gained a `badges` slot. They had been competing with Connect for row width and making the name truncate first — which is *why* the spatial sidebar had been shrinking its own controls. |
| Sidebars resizable and remembered | Terminal, database and Workgroups windows had no `NSSplitView` autosave; every window reverted to its ideal width. **macOS only** — AppKit persists divider positions, SwiftUI exposes no equivalent, so this cannot be delivered on iPadOS or visionOS today. |
| Workgroups as a library panel | See below. |
| Settings top right / Add Host top of sidebar | Overtaken by **D24**, which settles where sidebar controls live. |
| Network/Tailscale panel | **Not done.** `TerminalTailscaleView` needs the same split as Workgroups and carries more state. |

### Workgroups is a contributed panel, not a window

glas.sh had it in the sidebar all along: `ConnectionLibraryMode` carried `workgroups` and `network`
beside the four scopes, and `libraryResults`/`libraryDetail` switched on it. The merge moved it to a
window of its own, which is what made it stop feeling fleet-wide.

**The slot for it already existed here and nothing called it.** `GlassLibraryNavigation` takes an
`extras` builder documented verbatim as *"Apps can append Workgroups, Network, or other specialized
sections without duplicating the common categories"*, and `GlassConnectionLibrary` used the
no-extras convenience at both call sites.

`GlassLibraryPanel` is contributed through `GlassCapability.libraryPanels()`, so the shell never
learns a capability's surfaces by name. One `openPanelID` rather than two pieces of state, so "a
panel is open" and "which scope is selected" cannot disagree. Handled in all three navigation
shapes: sidebar section on Mac and iPad, a push on the iPhone stack, and **a tab in the visionOS
tab-bar ornament** — the platform's own answer to the question glas.sh answered with a section.
`TerminalWorkgroupsView` gained a `presentation` (`.results` / `.detail` / `.standalone`) over a
shared `TerminalWorkgroupsModel` on the runtime, because the two halves now occupy two columns.

### Found while working, not asked for

- **The caret was black on blue.** `foregroundStyle` set on the enclosing `HStack` reached the play
  triangle (a plain `Button`) and not the chevron, because `.menuStyle(.borderlessButton)` supplies
  its own label colour — and setting it on the label content does not win either, since the style is
  applied afterwards. A `ButtonStyle` is the hook that is not overridden: `GlassOnFilledLabelStyle`
  and `.glassMenuOnFilled()` now carry it for the whole family.
- **The app introduced itself as "glas.sh"** in its own quit dialog. `GlassProduct.displayName`
  reads `CFBundleDisplayName` and falls back to a literal; ten user-visible strings use it. Storage
  identifiers and provenance comments deliberately keep the old names — renaming a key orphans what
  it points at, and rewriting a comment that records where a behaviour came from makes it a lie.
- **"Open Folder Here"** opened Finder with the folder *selected in its parent*
  (`activateFileViewerSelecting`) rather than opening it. Now `open`. The remote half needed almost
  nothing: the shell already reports its directory over OSC 7 — the value the AI assistant uses —
  so `SFTPBrowserContext` gained an `initialPath` and the browser applies it before the first
  listing.
- **UI tests were writing into the real store.** See below.

### The glass went too far, and is still wrong

The user asked for the columns to stop being opaque white and honour the transparency settings.
`List` and `Form` each paint their own scroll background, so they were covering the window's layer —
and every pixel they missed showed the desktop, which was the hairline at the column divider and the
band under the footer. Hiding those backgrounds fixed the seams and **over-corrected**: at the
default `ultraThin` material the columns read as bare wallpaper. The user's verdict: *"Now this is
broken?!"*

**Open.** Either a thicker default material (`.regular` is what a sidebar uses) or opaque columns.
Not decided, and deliberately not changed unilaterally — it is a look, not a defect.

## Capture and deployment notes

- The **visionOS simulator cannot screenshot through XCUITest at all** ("remote interface does not
  have this capability"), so a suite that captures on every step fails there for that reason alone.
  `xcrun simctl io <udid> screenshot` works: build, install, launch, screenshot.
- **Install to `/Applications`.** Builds went to a scratch directory for the first half of the
  session while the user launched the app normally — so they were looking at **0.3.69 from the
  previous day** while being told about the day's changes, which produced a "did you revert more
  than you expected?" that cost real time. Every build since 0.3.86 replaces
  `/Applications/GlassPowerTools.app` and the version is read back off the installed bundle.
