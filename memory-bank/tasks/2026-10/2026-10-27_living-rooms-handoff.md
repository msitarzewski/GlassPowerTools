# 2026-10-27 — Living rooms: the Tribeca loft arrives, and the host hook to build (handoff)

## State and authorization
**Phase 3 BUILT 2026-10-27 too** (the owner: "go ahead with phase 3"): the digital clock and the events, to the
contract in "Phase 3, as built" at the end; live screens stay dropped.

**BUILT 2026-10-27, phases 1 and 2** (the owner: "That's the one... get're done!"), and **seen working on his headset**
the same evening (0.4.540, the fixed loft from iCloud: "holy shit it works~!!!"); see "Built" at the end. Phase 3
waits for its own approval. What follows up to "Built" is the plan as handed over.

PLAN. Nothing in this repository's code has changed. This note was written by the GlassSpaceMaker session that
built the loft, at the owner's word on 2026-10-27 ("Add a file in its memory bank for the update instructions so
that session can build it"), so that a session opened here can go from PLAN to BUILD without reading the other
project. The owner approves BUILD here; the asset side is finished and needs nothing from this repository.

Earlier words that frame it: "Is there a way to animate these somehow? Maybe make a clock show system time? …
Cars moving, people walking. Occasional birds and planes (random)." (2026-10-27); "Tribeca facing Midtown at blue
hour, and yes plan the hook and I'll pass it on. What about audio?"; and the correction that changed the contract:
"We don't need displays and mice/keyboards. This is for a virtual office in my app. A clean desk is best."

## What arrives
Three files in the owner's Downloads folder. None belongs in this repository: rooms are the person's own files in
the library folder (D89), and a built-in is drawn in code.

| File | Size | What it is |
|---|---|---|
| `Loft.usdz` (sha256 begins `8cfe1a757dd12338`) | 72.6 MB | The Tribeca loft, 150 m up, blue hour, facing Midtown. `usdchecker --arkit` passes. |
| `Loft.sounds/` | 4.5 MB | Six AAC clips and `sounds.json` (below). Belongs beside `Loft.usdz`, same folder, same name. |
| `AnimTest.usdz` | 100 KB | The proof file: a car lapping a circle, a clock hand, a flapping bird, a waving arm. Phase 1 can be seen on it before the loft is copied. |

Where they go: iCloud Drive ▸ Glass Power Tools ▸ Environments, copied from a Mac in Finder (both the file and the
folder). The library lists the file and ignores the folder: `FocusEnvironmentFiles.kind(of:)` knows only
`usdz`, `reality` and the photo extensions (`Sources/GlassTerminal/FocusEnvironments.swift:95-131`), so
`Loft.sounds` is invisible to it and safe. In the simulator, which has no iCloud account, the library falls back
to the app's Application Support folder; `--demo-environment-room` already writes a room there and shows the path.

What the file says about itself (read with `usdcat` and `usdtree` on 2026-10-27):

```
defaultPrim = "root"   metersPerUnit = 1   upAxis = "Y"
timeCodesPerSecond = 24   startTimeCode = 1   endTimeCode = 14400      (one 600 s loop)

/root/cam_pov/cam_pov            Camera at the seat, 1.6 m up, facing north (USD −Z)
/root/moving                     Xform: 108 cars, 7 birds, 2 airliners, a helicopter, 2 ferries, strobes
/root/moving/…/snd_heli          Xform inside the helicopter
/root/clock                      Xform, the dial on the south wall at (1.85, 2.3, 4.95) in the room's frame
/root/clock/clock_hour           Xform (its Mesh child has the same name: rotate the Xform)
/root/clock/clock_minute         Xform
/root/clock/clock_second         Xform
/root/snd_city  /root/snd_rack  /root/snd_hvac  /root/snd_clock     Xforms, empty
```

The seat is the file's camera, which `FocusEnvironmentScenes.room(_:)` already reads as the start. There is no
`screen_<n>` quad and nothing on the desk but an arm lamp and a succulent: the app brings its own windows.

## The room-file contract (what every living room promises)
This is the contract the loft was built to. It supersedes the "Room file contract" section of the owner's
`GPT-LivingRooms-Plan.md` on one point: the `screen_<n>` quads are gone, with the monitors.

- `metersPerUnit = 1`, Y-up, one camera named `cam_pov` at the seat.
- An Xform named `moving` holds everything animated. Never walkable, never a collider.
- One timeline at 24 fps, a seamless loop, stated by `startTimeCode`/`endTimeCode`. The loft's is 600 s, with
  birds and aircraft scattered irregularly so they read as occasional.
- An Xform named `clock` with child Xforms `clock_hour`, `clock_minute` and optionally `clock_second`. The hands
  carry **no** time samples. Each hand's pivot is the dial's centre; as loaded it points to 12; its local +Z is the
  dial's normal pointing into the room. The host rotates each about its local Z; a negative angle is clockwise as
  seen by someone facing the dial.
- Sound emitters: empty Xforms named `snd_<id>` where a sound comes from. One may sit inside `moving` (the loft's
  `snd_heli` rides the helicopter) so its sound travels.
- A sidecar folder `<Room>.sounds/` beside the file, holding `sounds.json` and `.m4a` files (AAC 48 kHz; mono for
  spatial emitters; stereo for beds).
- No monitors, keyboards, mice or wall displays (the owner, 2026-10-27).

The loft's `sounds.json`, as shipped:

```json
{
  "version": 1,
  "sounds": [
    { "id": "city",  "file": "city_blue_hour.m4a",  "entity": "snd_city",  "kind": "ambient", "gain": -14, "loop": true },
    { "id": "rack",  "file": "server_fans.m4a",     "entity": "snd_rack",  "kind": "spatial", "gain": -22, "loop": true },
    { "id": "hvac",  "file": "hvac_hum.m4a",                               "kind": "channel", "gain": -30, "loop": true },
    { "id": "clock", "file": "clock_tick.m4a",      "entity": "snd_clock", "kind": "spatial", "gain": -30, "loop": true },
    { "id": "heli",  "file": "helicopter_pass.m4a", "entity": "snd_heli",  "kind": "spatial", "gain": -8,  "loop": false, "every": [180, 600] },
    { "id": "siren", "file": "siren_distant.m4a",   "entity": "snd_city",  "kind": "spatial", "gain": -24, "loop": false, "every": [240, 900] }
  ]
}
```

Rules: `kind` is `spatial` (a `SpatialAudioComponent` on the named entity), `ambient` (an
`AmbientAudioComponent`, a world-locked bed) or `channel` (a `ChannelAudioComponent`, head-locked, on the room's
root, no entity needed). `gain` is decibels at or below 0, clamped to −60…0. `every` makes a one-shot: wait a
uniform random number of seconds in that range, play once, repeat. A sound whose entity is missing logs and is
skipped. A missing folder is a silent room, not an error.

## Why the host has to do it
A USDZ can carry motion (time-sampled transforms, UsdSkel, blend shapes; verified with Blender 5.2.3 and
`usdchecker --arkit` on `AnimTest.usdz`), and Focus Mode loads such a file today, but nothing under `Sources/`
calls `availableAnimations` or `playAnimation`, so the loft stands still. Two things no file can carry: the time
of day (nothing in USD knows it) and sound (RealityKit plays audio only when code asks). Three small abilities,
below.

## Analyzed (re-verified 2026-10-27 at commit cc9d80b9)
- `Sources/GlassTerminal/FocusEnvironmentView.swift:337` `FocusEnvironmentScenes.room(_:)` loads with
  `Entity(contentsOf:)`, measures bounds, finds the USD camera. `:323` `struct LoadedRoom`.
- `FocusEnvironmentView.swift:117` the load path waits for an iCloud download (`waitForDownload`, `:161`), then
  `room(file)` → `library.fit(for:)` → `walking.show(nil, room:fit:walks:)`.
- `Sources/GlassTerminal/FocusEnvironmentWalking.swift:114` `install(in:content:)` subscribes to
  `SceneEvents.Update` and runs every frame: the per-frame hook the clock needs already exists.
- `FocusEnvironmentWalking.swift:131-150` `show(_:room:fit:walks:)` clears `content` and `roomHolder`, adds
  `loaded.model` at `:140`, then `makeStandable` (`:194`) builds a static collision mesh for every mesh
  descendant (`descendants(of:)`, `:361`). Cars, birds and clock hands would get colliders too: wasted work, and a
  pinch could land on a bird.
- `Sources/GlassTerminal/FocusEnvironments.swift:369` `fitFile(for:)` keeps `<file name>.json` in "Environment
  Fits" beside the library; `:113` `entry(named:)` and `:95` the extension sets.
- `Sources/GlassTerminal/FocusRoomFit.swift` `FocusRoomFit: Codable`, decoded with `JSONDecoder`: the sidecar
  pattern to copy for sound.
- `Sources/GlassTerminal/TerminalAudioManager.swift` the bell is `AudioServicesPlaySystemSound`; its header
  records that RealityKit spatial audio needs a Volume or an ImmersiveSpace. Focus Mode is an ImmersiveSpace, so it
  is the one place in the app where RealityKit audio works.
- `Sources/GlassTerminal/Constants.swift:36` `focusEnvironment`, `SettingsView.swift:598`, and the sync's optional
  field sent only from Vision Pro (`2026-10-26_focus-environments.md`): the pattern for a sound level.
- `Tests/GlassTerminalTests/FocusEnvironmentTests.swift` suite "Focus Mode environments": where the tests go.
- `Sources/GlassDesktop/DesktopAudioPlayer.swift` AVAudioEngine for remote-desktop audio: not reusable here.
  Spatialisation needs `AudioFileResource` on entities, not PCM into an engine.

## Reuse strategy
- Extend `LoadedRoom` (`FocusEnvironmentView.swift:323`) with `sounds: FocusRoomSounds?`, read in `room(_:)`, so
  one function keeps knowing a room's files.
- Extend `FocusWalking.show` (`FocusEnvironmentWalking.swift:131`) to start motion and sound after
  `roomHolder.addChild(loaded.model)` (`:140`) and to stop both before the next room shows.
- Extend the `SceneEvents.Update` closure (`:114`) with one call: `self?.clock?.tick(now: .now)`.
- Extend `makeStandable` (`:194`) to skip the `moving` and `clock` subtrees.
- Extend settings with one level, following `focusEnvironment`.
- Respect Reduce Motion (`UIAccessibility.isReduceMotionEnabled`): no subtree animation, the clock still runs,
  sound unaffected.
- One new file, `Sources/GlassTerminal/FocusRoomLife.swift`, for the clock maths, the manifest and the soundscape.
  Cannot extend `FocusEnvironmentWalking.swift`: it is locomotion, 511 lines, and these are a separate concern with
  pure logic that tests should reach without a scene. Cannot extend `FocusRoomFit.swift`: a fit is per-device
  configuration the person writes; motion and sound are content the file ships. One file, not three.

## Steps

### Phase 1: motion and the clock (about 80 lines)
1. `FocusRoomLife.swift`: `enum FocusRoomClock` with
   `static func angles(at date: Date, in calendar: Calendar) -> (hour: Double, minute: Double, second: Double)`
   in radians, clockwise, sweeping (hour = 2π·(s mod 43200)/43200, minute = 2π·(s mod 3600)/3600,
   second = 2π·(s mod 60)/60, with s = seconds since local midnight). A `final class FocusRoomClockHands` finds
   `clock_hour`, `clock_minute`, `clock_second` with `findEntity(named:)` (the first match is the Xform; its Mesh
   child carries the same name, so check that the match's parent is `clock`), remembers each hand's rest
   orientation, and `tick(now:)` sets `hand.orientation = rest * simd_quatf(angle: -Float(angle), axis: [0, 0, 1])`.
2. `FocusWalking.show`, after `:140`: unless Reduce Motion is on, for each of `loaded.model.availableAnimations`
   call `playAnimation(animation.repeat(), transitionDuration: 0)`, keep the controllers in
   `motion: [AnimationPlaybackController]`, and set `controller.time = .random(in: 0..<controller.duration)` so
   every session starts somewhere else in the 600 s loop (this is what makes the birds and planes feel occasional).
   RealityKit exposes a USDZ's time samples as one animation on the root, so this plays the whole file.
3. Clock: `clock = FocusRoomClockHands(in: loaded.model)` in `show`; `clock?.tick(now: .now)` from the Update
   closure. Set `clock = nil` and stop `motion` at the top of `show`.
4. `makeStandable`: skip every entity under one named `moving` or `clock` (a parameter on `descendants(of:)`, or a
   filter on ancestry).
5. Tests, in `FocusEnvironmentTests`: angles at 03:00:00 (hour π/2, minute 0), 09:30:00 (hour 2π·9.5/12),
   23:59:30 (minute 2π·59.5/60), with a fixed time zone; the skip rule on a tiny entity tree. Manual, on
   `AnimTest.usdz`: the car circles, the hand turns, the bird flaps, the arm waves; pinching the floor still
   teleports; with Reduce Motion on, still, and the clock runs.

### Phase 2: sound (about 150 lines and one setting)
6. `FocusRoomSounds: Decodable` (`version`, `sounds: [Sound]`; `Sound` has `id`, `file`, `entity?`, `kind`,
   `gain`, `loop`, `every?`) with `static func read(beside file: URL) -> FocusRoomSounds?` resolving `Loft.usdz`
   to `Loft.sounds/sounds.json`. Call it from `room(_:)`. If the folder's files are iCloud stand-ins, start
   downloading them (`startDownloadingUbiquitousItem`, as `FocusEnvironments.swift:423` does for a room) and
   treat this opening as silent.
7. `final class FocusRoomSoundscape`, created in `show` after motion: per sound, load
   `AudioFileResource(contentsOf:configuration: .init(shouldLoop: loop))` off the main thread, set the component
   its `kind` names on the named entity (or the model root for `channel`) with `gain + master`, and
   `entity.playAudio(resource)`. One-shots run a `Task` each: sleep a random interval from `every`, play once,
   repeat. `stop()` cancels every task and stops every controller; `show` calls it first, and the view calls it
   when the space closes.
8. Setting `focusEnvironmentSound: Double` 0…1 (default 0.7) in `SettingsManager`, synced like
   `focusEnvironment` (sent only from Vision Pro), with a slider in Settings ▸ Terminal ▸ Focus Mode. Master gain
   is `20·log10(level)` dB; 0 stops everything.
9. Tests: the manifest above decodes; gain clamps; `every` picks inside its bounds; `read(beside:)` names the
   folder correctly; a sound whose entity is missing is skipped. Manual, on the loft: the city stays at the
   windows as the head turns, the helicopter's sound crosses with it, the slider at 0 silences, closing the space
   silences.

### Phase 3: later, each its own approval
10. A digital clock and date panel: the two-parameter `RealityView` with `attachments`, anchored at an entity
    named `clock_digital` (the loft has none yet).
11. Truly random events: small event USDZs in `<Room>.events/`, placed at `event_*` anchors and played on random
    timers (one `Entity(contentsOf:)` each, hidden until played).
12. Live screens are **dropped**: the owner's clean-desk rule; the app's own windows are the screens.

## Integration
- Rooms without `moving`, `clock` or a `.sounds` folder behave exactly as today: no animations to play, no hands
  found, nothing to read. Ridge Studio, the built-ins and the person's other files are unchanged.
- Tear-down order in `show`: soundscape stop, motion stop, clock nil, then `content.children.removeAll()` as now.
- Try Out (`FocusEnvironmentFitView`) shows rooms through the same `show`, so motion and sound run there too,
  which is what a person fitting a room wants to see.

## Risks
- Playing before the entity is in a scene: play after `roomHolder.addChild`, never in `room(_:)`.
- A file that keys its clock hands would fight the host: the contract forbids it (the loft's hands carry no
  samples); the host could also skip the clock when a hand has an animated ancestor, if that ever bites.
- Collider cost on big rooms: skipping `moving` also keeps `generateStaticMesh` away from skinned meshes, whose
  bind pose would be wrong to stand on anyway. The loft is 1.0 M faces with 767 k animation samples.
- `AmbientAudioComponent` with a stereo file: verify on the headset; fall back to `channel`.
- The `.sounds` folder may arrive from iCloud after the room: the next opening has it.
- Spatial audio only inside the ImmersiveSpace, never in the window-hosted RealityViews.

## Budgets
Phase 1: one session, ~80 lines plus tests. Phase 2: one to two sessions, ~150 lines, one setting, tests. No new
dependencies.

## What to look for on the headset
From the seat: Midtown as dark towers with warm window glitter, headlight streams on the avenues, a bird now and
then, an airliner crossing high, the helicopter over the Hudson with its sound moving; the wall clock to the left
of the tall shelves reading the headset's time; a pinch on the floor still teleporting, and nothing standable on a
car. Reduce Motion on: the city still, the clock running, the sound unchanged.

## Where the asset work lives
The loft and Ridge Studio are built in the GlassSpaceMaker project (Blender 5.2 headless, Cycles bakes to
lightmaps, USDZ export); that project's own memory keeps the pipeline. The owner's `GPT-LivingRooms-Plan.md` in
Downloads is the first draft of this note and is superseded by it.

## Built (2026-10-27, this repository's session)
- `Sources/GlassTerminal/FocusRoomLife.swift` (new): `FocusRoomClock` (angles, pure), `FocusRoomSounds` (the manifest,
  `read(beside:)`, gains, waits, `playable`), `FocusRoomLife.standableDescendants`, `FocusRoomClockHands`, and
  `FocusRoomSoundscape` (visionOS: each sound on an entity of its own under its emitter, so two sounds on `snd_city`
  keep their own gains; loops paused at Room Sound 0; one-shots skipped then).
- `FocusEnvironmentWalking.swift`: `startLife` after the room is in the scene (motion from a random time in its loop
  unless Reduce Motion is on; clock; sounds), `endLife` before the next environment and as the space closes; the
  clock ticks from the existing `SceneEvents.Update`; `makeStandable` skips `moving` and `clock`.
- `FocusEnvironmentView.swift`: `LoadedRoom` carries its file and sounds (read off the main thread); Room Sound
  followed live. The immersive space now has `SettingsManager` in its environment (`GlassTerminalScenes`).
- Room Sound: `SettingsManager.focusEnvironmentSound` (0.7), `UserDefaultsKeys.focusEnvironmentSound`, the sync's
  optional field (validated 0…1, sent only from Vision Pro), a slider in Settings ▸ Terminal ▸ Focus Mode.

### Validation
- `FocusRoomLifeTests`, 9 tests (the clock's angles, the hands turning about their own Z and not their meshes, nothing
  moving to stand on, the loft's `sounds.json` as shipped, gains, waits, a missing emitter skipped, the folder beside
  the file and an iCloud stand-in, Room Sound kept and synced). Each seen failing with its logic broken (two rounds of
  mutations; sources restored byte for byte). Terminal 1033 and shell 371 unit tests pass.
- `FocusEnvironmentUITests`: Room Sound's slider at 70% (fails with the slider removed); both tests pass.
- visionOS simulator, files copied into the app's own environments folder (no iCloud there):
  - `AnimTest.usdz`: 2 animations playing (captures 3 s apart: the hand turned, the arm waved, the car moved);
    "clock false", as its hand is time-sampled, not a `clock`.
  - `Loft.usdz` (sha256 `8cfe1a757dd12338…`): 2 animations, a clock, 6 sounds; 151 surfaces to stand on; `city`,
    `rack`, `hvac` and `clock` logged playing; Midtown from the seat (`<work>/captures-living/loft-1.png`).
  - **The loft's clock shows no hands, and the app cannot show them:** in the file, every hand and the cap sit
    between the dial and the wall. The dial is 3 cm thick at y = −4.95 (Blender's frame), its printed face toward
    the room (+Y); `clock_hour` is at −0.026, `clock_minute` −0.036, `clock_cap` −0.045, `clock_second` −0.046, and
    the south wall's face at −5.00. The fix is the asset's: those four offsets positive (in front of the dial).
    - **Fixed in the asset, 2026-10-27 evening (the GlassSpaceMaker session):** the four offsets are now +0.026, +0.036,
      +0.046 and +0.045, in front of the dial's face at +0.015; re-exported, `usdchecker --arkit` passes, and a render
      from the clock wall shows all three hands and the cap at 12. The `Loft.usdz` in the owner's Downloads is the fixed file
      (72.6 MB, sha256 begins `2d7d87e65d31ed3f`); copy it over the one in Environments. `Loft.sounds/` is unchanged.
  - A test copy with exactly that change (`<work>/loft-usd/LoftHandsOut.usdz`, `usdchecker --arkit` passes; not the
    owner's file) read the time: captured 20:39:42 and 20:40:03, the clock read about 8:39:45 and 8:40:05, the
    second hand sweeping clockwise (`<work>/captures-living/handsout-1-clock.png`, `-2-clock.png`).
- Beds that loop stream (`AudioFileResource` `.stream`); one-shots preload. Decoded whole, the loft's six come to
  about 70 MB (computed: the 120 s stereo city alone is about 46 MB). The app with the loft open in the simulator:
  381 MB, peak 454 MB (`footprint`; the simulator, not the headset; no preload build measured beside it).
- `siren` logged playing once about 20 minutes in, so one-shots run; `heli` not yet seen.
- Not seen: sound heard (the simulator logs playing; the headset is the ear); Reduce Motion; the loft from iCloud on
  the headset; the headset's memory with the loft.
- **21:34, the asset fixed:** The loft in the owner's Downloads rewritten (sha256 `2d7d87e65d31ed3f…`, 72,588,735 bytes,
  `usdchecker --arkit` passes) with all four offsets positive (hour 0.026, minute 0.036, cap 0.045, second 0.046),
  in front of the dial. Put in iCloud Drive ▸ Glass Power Tools ▸ Environments with `Loft.sounds/` at 21:44 for the
  owner's headset; the loft there before (15:57, 75.7 MB, sha256 `f76e409c71f039d7…`, an earlier build, no sounds)
  is kept in `<work>/icloud-backup-2026-10-27/`. 0.4.540, with this, is the owner's to try.
- **On the headset (2026-10-27, about 21:50):** the owner, in the fixed loft from iCloud on 0.4.540: "holy shit it
  works~!!!". Not yet reported part by part (the clock, each sound, Room Sound, Reduce Motion), and the headset's
  memory with the loft is unmeasured.

## Phase 3, as built (2026-10-27, this repository's session)
The plan gave each piece a sentence; the contract below is this session's, for the asset side to build to.

**The digital clock and date panel.** An empty Xform named `clock_digital` at the panel's centre, its local +Z facing
into the room and +Y up (as the wall clock's dial). The host shows the time (the device's 12- or 24-hour form) and
the weekday and date on a dark rounded face, 0.5 m wide, times the Xform's own scale; it follows the room's fit. It
is a SwiftUI attachment of the space's `RealityView` (`FocusRoomDigitalClockView`), placed by
`FocusRoomLife.placeDigitalClock`. A room with no `clock_digital` has none.

**Events now and then.** `<Room>.events/` beside the file (as `.sounds`), with `events.json`:

```json
{
  "version": 1,
  "events": [
    { "id": "flock", "file": "flock.usdz", "anchors": ["event_sky_west", "event_sky_east"], "every": [120, 600] },
    { "id": "ferry", "file": "ferry.usdz", "anchors": ["event_river"], "every": [300, 900], "seconds": 45 }
  ]
}
```

- `file`: a USDZ (or Reality) file in the folder, a plain name. Its root is placed at the anchor's origin, facing as
  the anchor faces, so author it around (0, 0, 0). Its own motion (time samples, skeletons) plays once each time.
- `anchors`: empty Xforms named `event_<name>` in the room; each time, one present in the room is chosen at random.
- `every`: `[from, to]` seconds between showings, chosen at random each time.
- `seconds` (optional): how long it stays; by default as long as its motion lasts, else 10 s; at most 600.
- Loaded once and hidden until it happens; hidden again after. None with Reduce Motion. An event whose anchors are
  all missing, whose file names a path, or whose `every` is back to front is skipped and logged. Nothing under an
  `event_` Xform or `clock_digital` is stood on.

### Validation
- `FocusRoomLifeTests` 13 (four new: the panel placed and sized, events read and filtered, how long one stays, the
  folder beside the file; two extended: nothing under `clock_digital` or an `event_` anchor stood on, a sound named by a
  path skipped). Six mutations, each caught; one gap found by them (the bad-path and back-to-front events named an
  anchor the test room lacked) and the test data fixed. Terminal unit tests 1037.
- `FocusEnvironmentUITests.testARoomWithADigitalClockShowsTheTime`: the simulator's test room (now with a
  `clock_digital`, `event_left`, `event_right` and an orb event every 3–6 s, `--demo-environment-room`) shows the panel;
  it fails with the anchor renamed. All three Focus Mode UI tests pass.
- Captures (`<work>/captures-living/phase3-*.png`): the panel on the test room's far wall reading "10:09 PM / Tuesday,
  October 27" at 22:09; the orb's place orange in four of eight captures 2 s apart and bare wall in the others; the log
  names both anchors.
- Not seen: the loft, which has neither a `clock_digital` nor events yet (the asset side's to add); the headset.
