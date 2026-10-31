# Focus Mode rooms in Apple's own format (2026-10-31)

**Ask (the owner):** "Should we spend some time making is a normal/expected flow/API/interface before releaseing it to
the wild?", then "Let's explore anything we can to make this simple for someone familiar with Apple's existing
tooling to build envs for us." Then, on the written proposal: "go ahead, hold the how-to and commit the rest", and
"Add the reality kit plan to the memory bank though, in case someone decides to read it". **Status:** the direction
is approved (D92); nothing built yet. The help describes what a room does, not how to make one, until version 1.

## Today's contract (living rooms, D89, 0.4.540+)
Names in the file (`moving`, `clock` + `clock_hour/minute/second`, `clock_digital`, `snd_<id>`, `event_<name>`) and two
sidecar folders beside it (`<Room>.sounds/sounds.json`, `<Room>.events/events.json`); Add Environment… copies only
the room file. Read by `Sources/GlassTerminal/FocusRoomLife.swift`; rooms load with `Entity(contentsOf:)`
(`FocusEnvironmentView.room(_:)`), USDZ or `.reality`.

## What Apple's tools give (checked on this Mac, Xcode 27.1)
- **Apple's own starting point:** Xcode's visionOS **Immersive Environment App** template (a sky dome, a ground with
  an attenuation map, and a `RealityKit.CustomDockingRegion` marking where the video player docks), loaded with one
  `Entity(named:in:)`.
- **Apple's samples** (Diorama, Destination Video, downloaded from developer.apple.com outside the repository): environments use
  `RealityKit.AmbientAudio`, `SpatialAudio`, `Reverb` (Destination Video's studio: "REAudioReverbPresetMuseum"),
  `VirtualEnvironmentProbe` (light and dark lighting), `SceneUnderstanding` on floors, `VFXEmitter`, and
  `CustomDockingRegion`; sounds are `RealityKitAudioFile` prims; custom components are
  `RealityKitCustomComponent` prims with `info:id = "<Module>.<Type>"` and plain fields. Diorama's code starts its
  sounds itself, by prim path from its own bundle (no use to a file from iCloud).
- **`xcrun realitytool`** compiles a Reality Composer Pro asset folder (`.rkassets`) to a `.reality` for a platform
  (`compile`), and turns custom component Swift into a schema (`create-schema`). Reality Composer Pro itself isn't
  installed here.

## Tried (a test room written by hand in RCP's format, outside the repository, loaded as Focus Mode loads one)
- Compiled with `realitytool` (macOS and the visionOS simulator) and as plain USDA/USDZ: the time-sampled animation,
  an **Audio Library** holding `Hum.wav` on an **AmbientAudio** emitter, and a **Reverb** all arrive. So a room can
  carry its own sounds, inside the one file, with no folder beside it; the app can play each emitter's library.
- A **custom component of our own** (`GlassRoom.FocusClockHandComponent`, field `hand = "minute"`): in the compiled
  `.reality`, RealityKit filled in the app's registered Swift type, no schema needed. In **plain USD** it crashed
  RealityKit on the Mac: unregistered, an assertion when its components were read; registered, a crash converting it at
  load (crash reports `probe-2026-10-31-*.ips`). The app on the visionOS simulator opened the same USDZ and `.reality`
  without crashing (it reads none of those components today: "2 animations … 0 sounds").
  → Our own components should come only in compiled `.reality`; a USDZ carrying them must be refused or checked
  before the app ever registers those types (to be re-checked on visionOS once registered).
- The docking region didn't show on macOS (a visionOS component, presumably); unchecked on visionOS.

## What Apple's documentation says (research agent, 2026-10-31; links in its report, summarised)
- **Reality Composer Pro 3** (2026) is a standalone app; RCP 2 is removed. Its output for apps is one **.reality**
  ("Export To > Reality"). "Exporting doesn't preserve … many names": a convention of entity names breaks; components
  survive. (developer.apple.com/documentation/realitycomposerpro, migrating-older-projects.)
- **Nothing plays by itself on visionOS 26.** Animation needs an `AnimationLibraryComponent` and a play call; visionOS
  27 adds `automaticallyPlaysDefaultAnimation` (RCP 3's Auto Play). Audio components only shape sound; something must
  start it (the app, a Sequence's Play Audio action, or Script Graph). The app targets visionOS 26, so it plays the
  defaults itself either way.
- **Sequences** (RCP 3): Play Audio, Enable/Disable, Motion Path, Billboard; Repeat Forever.
- **Script Graph** (visionOS 27, beta Swift package, the room's own JavaScript): would run an author's code inside an
  app that holds SSH credentials. Not proposed.
- **Custom components** in RCP 3 come from a **plugin** (a Swift module the author points RCP at, after trusting
  it); the module, type and property names are the contract (`info:id = "<Module>.<Type>"`). In a loaded .reality the
  component arrives only when the app registered the same module-qualified type; otherwise silently absent.
- **Environment guidance** (WWDC24 10087, 10115; WWDC25 305; WWDC26 234; Destination Video): bake to unlit, a
  Virtual Environment Probe, a Reverb preset (recommended even without audio), a docking region, scene-understanding
  tags; budgets around 200K triangles, 250 MB of textures, 200 entities, 100 draw calls. `ReverbComponent` works only
  in an immersive space (Focus Mode is one). USD lights are ignored by RealityKit; RCP's own lights carry over.
- **Packaging:** one .reality (several scenes allowed, `#Scene` in the URL); no Apple multi-file package type found.

## The plan (direction approved 2026-10-31, D92)
**A room is one `.reality` file exported from Reality Composer Pro 3,** built the way Apple's Immersive Environment
template and Destination Video studio are, with our components where it wants a clock or something now and then.

**Apple's components, honoured by the app** (no plugin needed):
- Motion: each entity's `AnimationLibraryComponent` default plays round and round; the room's Sequences play.
- Sound: each emitter's Audio Library plays as the author set it (Spatial, Ambient or Channel; looping, random
  start), at Room Sound.
- Acoustics and light: the Reverb preset, the Virtual Environment Probe, the editor's own lights.
- Floors: collision the author adds, where present, rather than floors guessed from every surface.

**Our components, one plugin:** a Swift module with a fixed name (`GlassRoomKit`), built as a Reality Composer Pro 3
plugin and into the app (module, type and property names are the contract; a rename silently breaks old rooms):
- Clock hand (hour, minute or second), turned to the device's time.
- Digital clock: where the time and date panel goes.
- Now and then: a sound to play, or an entity to show, at random times between two limits.
- Start: where you stand when the room opens, and which way you face.

**Adding a room:** Add Environment takes the one file, sounds and all. Try Out lists what the room has. A plain USDZ
keeps working as today, with today's names (for Blender); a USDZ carrying our components is refused, with the reason.

**Stays out:**
- Terminals are never placed by the room (the owner: "Let's not lock terminals, that defeats the vision I think");
  no `DockingRegion` for them. A room sets only where you stand.
- No code in rooms: Script Graph would run the author's JavaScript inside an app holding SSH credentials (and needs
  visionOS 27 and a beta package).
- Video and other screens: a later experiment ("Leave the video work for a later experiment").
- visionOS 27's Auto Play isn't relied on; the app (visionOS 26) starts motion and sound itself.

**Steps** (each useful alone):
1. Play what Apple's components describe, and Try Out's list of what a room has; checked on Destination Video's studio
   and a test room in the simulator.
2. Check rooms on the way in (refuse a USDZ carrying our components); confirm on visionOS that a compiled room with
   them loads safely once the app registers their types.
3. Build the plugin (needs Reality Composer Pro 3 installed).
4. Remake the Loft in the new format as the proof; keep today's names working.
5. Publish version 1: help, a sample room, the plugin.

**Open (the owner's):** installing Reality Composer Pro 3 on the Mac; the plugin's licence (MIT for room authors, or
GPLv3 like the app); a Feedback report to Apple for the plain-USDZ crash.

## Written up (2026-10-31)
The proposal is the owner's doc "Focus Mode rooms in Apple's own format" (private Claude Docs link, not recorded in
the repository): findings table, the format, what stays out (terminals unlocked, no room code, video later), five
steps, and his decisions: the direction; holding the help's "Make a room of your own" off the site until version 1
(recommended); installing Reality Composer Pro 3 here; the plugin's licence (MIT or GPLv3); a Feedback report for
the plain-USDZ crash.
