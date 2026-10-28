# 2026-10-26 — Focus Mode environments on Vision Pro (D89)

## Objective and authorization
The owner, 2026-10-22: his own environments in Focus Mode, per window over the app's setting, and a Sketchfab browser
(answers: iCloud, 360° photos too, the registration request drafted for him). 2026-10-26: "Go ahead and build the
upload interfaces and the environment library", "can you make a few that will become part of the library of
environments by default?", and "This environment feature should only be on visionOS … The user may manage their
library from mac". Authorizes the build, its tests and a build for his devices. Not committed.

## What was there
`FocusEnvironmentView` was an empty `RealityView` with `.preferredSurroundingsEffect(.systemDark)` in a progressive
immersive space (`GlassTerminalScenes.swift`), opened by the moon in a Vision Pro terminal's bar.

## Built
- `GlassTerminal/FocusEnvironments.swift` — `FocusEnvironment`, `FocusBuiltInEnvironment`, `FocusEnvironmentFiles`
  (which files are environments, iCloud's `.Name.icloud` stand-ins, identifiers `builtin.<name>` / `file:<name>`, names
  for added files, the 2:1 check), `FocusEnvironmentLibrary` (iCloud Drive ▸ Glass Power Tools ▸ Environments, else
  Application Support; watched with `NSMetadataQuery`; adding checks a 3D file's bytes with `GlassEditorFileKind` and a
  picture's size; coordinated copies and deletes), `FocusEnvironmentImportProblem` (refusals in words).
- `GlassTerminal/FocusEnvironmentArt.swift` — the built-ins drawn in code from fixed seeds: equirectangular skies
  (8192 wide on the headset, 4096 in Debug), floors whose edge is the sky's ground colour, Grid's repeating cell, and
  library previews ray-cast from a standing person's eyes. Night Sky (stars round at any altitude, a Milky Way with
  a dark lane), Dusk (the sun set ahead, three seamless ridges), Grid (a lit floor grid to a teal horizon), Studio.
- `GlassTerminal/FocusEnvironmentView.swift` — `FocusEnvironmentStage` (the one environment shown, and a note),
  the space's content swapped in place when the choice changes. The note — downloading, making one, why one can't be
  shown, or that a 3D file is smaller than a room — is drawn at the top of the window that opened Focus Mode: placed
  in the space it stood behind the window, unseen. A sky is a 900 m inside-out sphere turned a quarter (measured, below). A 3D file wider
  than 2.5 m is a room, placed around the person with its floor at their feet; anything smaller stands on the floor
  1.5 m ahead (`FocusRoomPlacement`). Built-in skies are cached in Caches as PNG.
- `GlassTerminal/FocusEnvironmentLibraryView.swift` — Settings ▸ Terminal ▸ Focus Mode (also All Terminals in a
  terminal's settings): the library as pictures, the chosen one marked, Add Environment… (Files), drop onto it, delete
  one's own (pinch and hold), footer saying where the files are. Previews: built-ins drawn, photos made small, rooms by
  Quick Look's thumbnailer.
- `SettingsManager.focusEnvironment` (saved; synced as an optional field, sent only by Vision Pro); window setting
  `terminal.focusEnvironment` with a This Window row; the moon's pinch-and-hold menu chooses the window's and opens
  Focus Mode; This Window or Settings changing it while open changes it in place.
- `App/GlassPowerTools.entitlements` (iOS and visionOS): `CloudDocuments` and the ubiquity container (the profiles
  already allow both: `icloud-services *` and the container, read from the installed headset build's profile).
  `App/Info.plist`: `NSUbiquitousContainers`, public, named Glass Power Tools. The Mac's entitlements are unchanged.
- Debug: `--demo-focus <environment>` opens Focus Mode around the demo window; `--demo-sky-turn <degrees>`;
  `--demo-settings-tab terminal`.

## Validation
- `FocusEnvironmentTests` (14): files, identifiers, names, the 2:1 check, adding (a photo, a Reality file; a 3:2
  picture, a fake USDZ and a text file refused in words), deleting, iCloud stand-ins, sync, sending only from Vision
  Pro, skies deterministic and seamless, floors meeting their skies, Dusk's sun at the picture's middle, Grid's cell,
  previews. Seen failing with four breaks (stand-ins ignored, the 2:1 check removed, the sun moved a quarter, the
  ridges not wrapping); sources restored from copies.
- visionOS simulator: each built-in captured in Focus Mode (`--demo-focus`). The sky's orientation measured with a
  marked 360° photo put in the library folder: RealityKit's sphere puts a picture's middle on the person's right; a
  quarter turn put ahead, left, right and above where they belong, not mirrored. That also showed one's own photo
  listed and shown.
- A room in the simulator: a 6 × 3 × 6 m room with a desk, made with ModelIO and `usdzip`, put in the library folder
  and opened: walls and ceiling around the window, the desk under it. First made without `metersPerUnit`, which USD
  reads as centimetres: RealityKit drew it 6 cm across, at the feet, unseen; Apple's iMac model, placed around the
  person, was unseen from inside. Hence the object placement (`FocusRoomPlacement`, unit-tested).
- `FocusEnvironmentUITests` on the visionOS simulator: the library in All Terminals, its five built-ins, Add
  Environment…, Dimmed Room chosen first, Night Sky chosen and marked, This Window following it. Seen failing with
  This Window's row not following All Terminals ("This Window shows Environment, Dimmed Room"); source restored.
- Terminal (1,006) and shell (361) unit suites pass.
- 0.4.529 installed on the Mac, iPhone and Vision Pro (versions read back; no new crash report); signed with
  `CloudDocuments` and the ubiquity container, no change to the developer account. 0.4.530 adds the note on the window and
  objects ahead; installed on all three (versions read back; no new crash report). The UI test passes again on it,
  and the terminal (1,007) and shell (361) suites.

- Focus Mode still opens partway immersed (`.progressive`, unchanged): the lower part of the view stays the room until
  the Digital Crown is turned, as Dimmed Room always did, so a floor or an object on it shows only then.

## Open Immersed (the owner, 2026-10-26: "Leave immersion to the user... in that same panel in the main settings. [ ] Open Immersed.")
- `SettingsManager.focusOpensImmersed` (off by default, as Focus Mode always opened; saved; synced as an optional field
  sent only from Vision Pro — `sentFromVisionPro`, which replaced `syncedFocusEnvironment`). A toggle under Add
  Environment… in Settings ▸ Terminal ▸ Focus Mode (`focus-environment-opens-immersed`).
- The space's style: `FocusEnvironmentStage.immersion(opensImmersed:)` — `.progressive` as before, or
  `.progressive(...1.0, initialAmount: 1.0)`: only the top and the start are set, so the Digital Crown keeps the system's
  own lowest amount (undocumented; a developer forum report puts it near half). `GlassTerminalScenes` reads the setting.
- Debug: `--demo-focus-immersed` sets it for the run, unsaved.
- Seen in the simulator: Night Sky partway shows the simulator's room (sofa, table) below the horizon
  (`<work>/focus-partway.png`); immersed, the ground reaches the feet (`<work>/focus-immersed.png`) — set after launch, so the
  scene follows the setting without a relaunch. Unit test (kept on the device) and the UI test (off at first, turns on)
  pass; each seen failing with its break (not saved; the toggle bound to a constant).

## Try Out, fits and moving about inside: built (the owner, 2026-10-26: "Yes, build all three.")
- `GlassTerminal/FocusRoomFit.swift` (all platforms, unit-tested on the Mac): `FocusRoomUnits` (what a file's numbers
  are really in), `FocusRoomFit` (units, a size 0.25–4× on a slider of even doublings, a floor raised or lowered up to
  5 m, a start spot in the file's own coordinates; stored as JSON, kept to its ranges on reading), `FocusRoomPose`
  (scale and offset of a fitted model, `FocusRoomPlacement` applied at the fitted size), `FocusWorldPose` (the world's
  pose around the person: `init(placing:under:)` is Mirador's `originForSpot` for a world that moves; floors come up
  to the person's), `FocusLocomotion` (Mirador's numbers: 20° down for the ring, 12 cm lift to cancel, 3 cm dead
  zone, 8° swing for a 45° turn, 0.15 s fade; `handHeading`, `turn(swingFrom:to:)`, `turning`).
- `FocusEnvironmentLibrary` keeps a 3D file's fit as `<file name>.json` in "Environment Fits": in iCloud, the app's
  container beside Documents (synced, not shown in Files); on the device, beside the library folder. Deleted with its
  file; a fit that changes nothing is no file. `ready()` waits for the library's folders, so Focus Mode opened as the
  app starts no longer falls back to Dimmed Room for one of the person's own (found while testing).
- `GlassTerminal/FocusEnvironmentWalking.swift` (visionOS): `FocusWalking` — the world entity that moves; a forced
  floor, unseen, 400 m, in the world at y = 0, to pinch; under a room or an object a dark floor fading out over 30 m;
  16 far walls and a ceiling round the person to pinch and swing; Mirador's ring (head aim, 20° down, raycast onto
  whatever can be stood on) and target (green disc, white arrow, grey when cancelled); a room's surfaces made into
  static mesh colliders after it shows, so its floors, stairs and landings can be stood on (a pinched surface whose
  normal is at least 0.6 up lands; a wall or ceiling turns); moves through a 0.15 s fade of the world's opacity.
  `FocusHeadTracker`: ARKit world tracking while the space is open — supported in the simulator and needing no
  authorization (logged: `supported true, needs []`), so no question to the person and no Info.plist reason.
- `FocusEnvironmentView` rebuilt on it: rooms load as `LoadedRoom` (bounds, the file's `metersPerUnit` from the
  entity's scale, its first `PerspectiveCamera` as a start: under it at eye height less 1.6 m, facing as it faces)
  and are placed by their fit; the stage carries `tryingOut`, `fit`, `room` facts and the walking.
- `GlassTerminal/FocusEnvironmentFitView.swift` (visionOS): Try Out's window (`focus-environment-fit`, a value of
  the environment's identifier): size in words, "Its numbers are in" (as the file says, named; or metres,
  centimetres, millimetres, inches, feet), Size slider, Floor slider, Start Here / Forget Where to Start, how to move,
  Reset and Done. Opens the space all the way round (the scene's style reads `tryingOut`) or swaps the open one; Done
  or closing keeps the fit and leaves the space as it found it. Opened from Settings ▸ Terminal ▸ Focus Mode: "Try
  Out and Fit “Name”…" under the grid when a 3D room is chosen, and in a room card's pinch-and-hold menu.
- The object note now points at Try Out instead of only the Crown.
- Debug: `--demo-environment-room` writes a test room with `Entity.write(to:)` (6 × 3 × 6 m, doorway, a 1.2 m
  platform with steps, a desk, a camera by the door); `--demo-try-out <id>`; `--demo-teleport x,y,z,heading°` and
  `--demo-walk-target …` do what a pinch there would.

Validation:
- `FocusRoomFitTests` (12) and the fit storage test pass; seen failing with four breaks (the turn's sign, the dead zone,
  a stored size unclamped, fits kept among the environments); sources restored byte for byte.
- `FocusEnvironmentUITests.testTryOutFitsARoomAndKeepsTheFit`: Try Out opens on the test room, "6.1 m wide, 3.0 m
  tall, 6.1 m deep"; Centimetres makes it "6 cm wide" at once; Done closes; relaunched, still 6 cm; Reset brings it
  back. Passes with the library test. Seen failing with Done not keeping the fit ("the fit wasn't kept: Size, 6.1 m
  wide…"); source restored byte for byte.
- Simulator captures (`<work>/focus-walk/`): the room around the window from the file's camera (`room-start`); a
  teleport onto the platform landing at 1.2 m (log) and, turned round, the room seen from up there (`room-platform2`);
  the target with its arrow 30° left (`room-target2`); Try Out's window over the room, immersed (`tryout2`).
- Not seen: a real pinch, the ring following the head (the simulator's head doesn't look down), a swing turning,
  iCloud carrying a fit, the headset.

## Fitting a 3D file, and moving around inside (asked 2026-10-26; the research)
His words: "random people's 3D files ... don't always set the default camera or size to be human scale", a "try out"
room with sliders for scale, the Mirador gallery's locomotion once the size is right, "We'd need to force a floor", and
"What settings come in a usdz, can we start with those for scale?"
- What a USDZ says, read with `usdcat` from five real files (Apple's iMac, a Three.js export, Object Capture scans, a
  statue): `metersPerUnit` (0.01 or 1), `upAxis` (Y), `defaultPrim`, `customLayerData` (creator; Apple's
  `preferredIblVersion`), `doc`. No camera in any of them; nothing about eye height or where the floor is.
- What RealityKit does with it, measured on the Mac (`<work>/usdmeta/probe.swift`): applies `metersPerUnit` as the root's
  scale (the iMac's root 0.01, so 55 cm, its true size); stands a Z-up file upright itself (the root turned −90° about
  X); loads a USD camera as a `PerspectiveCamera` entity at its own position (one at (200, 160, 500) cm came in there).
- Mirador's locomotion (github.com/msitarzewski/miradorxr, `src/xr`: `FloorTeleport.jsx`, `lib/teleport.js`, `lib/floorTarget.js`,
  `hooks/useGalleryNavigation.js`, `FadeCurtain.jsx`; mapped once already for another of the owner's
  projects): look down for a ring, pinch the floor for
  a target, move the hand to choose a facing (3 cm dead zone), lift it 12 cm to cancel, release to go through a
  0.15 s fade; a flick of 8° on the sky turns 45°. Native equivalents: an invisible floor at the person's feet with
  `DragGesture(minimumDistance: 0)` targeted to it (the spot is where the eyes were at the pinch; the hand's movement
  is the gesture's), RealityKit's spotlight hover effect for the ring (the system draws it, the app never learns where
  the eyes are), the world moved by the inverse of the person's new place (Mirador's `originForSpot`), the head's
  position from ARKit world tracking while the space is open (whether that asks permission is not yet checked).
  visionOS fades a fully immersive space when the person walks about 1.5 m from where they began (Apple's user guide;
  developer forum 813585), so teleporting is how a room is crossed.

## Not seen
iCloud Drive (the simulator has no account), a drop from Files, the headset itself.

## Floor only, and fine positioning asked for (2026-10-28)
The owner: "we need to enforce a 'floor only' locomotion. Sometimes I get moved to the top of the desk surface
(clearly not the floor) and it's a pain. How can we allow micro adjustments? Right now it's almost impossible to get
the right position as it relates to the desk surface."
- **Floor only (0.4.543, built):** a pinch lands only on a level surface within 12 cm of the floor
  (`FocusLocomotion.canLand`, `floorTolerance`, tested; a rug or a threshold is the floor, a desk's top or a step is
  not). Pinching a desk shows the target greyed and goes nowhere; the look-down ring shows on the floor only. A room's
  platforms and stairs can't be landed on any more (the simulator's test room's platform included). Seen in the
  simulator: `--demo-teleport` toward the test room's desk top "not the floor, no landing", toward its floor landed.
  `FocusRoomFitTests.floorOnly` fails with the height check out.
- **Fine positioning, his choice of four:** a nudge pad (a small window from the moon's menu: 2 cm steps, hold to
  repeat, 1° turns, the room 1 cm up or down, Keep This Spot as the room's start) and slide by hand (pinch the floor
  at your feet and drag: you move with the hand at half its movement, no fade). Not built yet: he turned to git.

## Fine Position, and the floor a pinch must find (2026-10-28, 0.4.545)
The owner: "commit and push, then build the nudge pad"; then "Let's create a build and ship it when you're ready."
- **Found on the way, a defect of 0.4.543:** floor-only measured from the floor forced under the environment, which a
  room places at its lowest point. The loft's sky reaches 5998 m below its floor and Rain Garden's 398 m (measured on
  the Mac with RealityKit, `Entity(contentsOf:)` and `visualBounds`), so in both every pinch on the floor showed the
  greyed target and went nowhere. Now measured from the floor the person stands on (`FocusWalking.raise`): every start
  and landing puts it there. The simulator's test room had no sky, so 0.4.543's check passed; `--demo-room-sky` gives
  it one 40 m down.
- **The room's height sticks:** the fit's floor was undone by any start (a start was placed at the person's feet), so
  Try Out's floor slider only lasted while it was open. Now a room raised 3 cm stays 3 cm up wherever the person starts
  or lands (`FocusRoomPose.raise`, `pose(startingAt:under:)`, `FocusWorldPose(placing:under:raised:)`), and Start Here
  and Keep This Spot keep the room's floor under the head, not the person's (`start(standingIn:head:)`).
- **Fine Position** (`FocusEnvironmentNudgeView`): a `Window` from the moon's pinch-and-hold menu while Focus Mode is
  open, placed by the system as a utility panel (below the window, near the hands), sized to its content. A pad:
  turns of 1° in its top corners, steps of 2 cm the way the person faces (`FocusLocomotion.nudging`, no fade), every
  button repeating while held (`buttonRepeatBehavior`); "From where you start" read back after each move
  (`FocusOffset`, the stage's `moves`); the room 1 cm up or down (`FocusRoomFit.raised(by:)`, kept a second after the
  last press); Keep This Spot (kept at once). It closes with Focus Mode. Nothing in the way is checked: lining a desk
  up may mean standing in it.
- **Tests:** unit, 5 new (by hand and round trips: a raised room kept and opened again; the loft's measure), each
  seen failing with its part broken; terminal 1043. UI: `testFinePositionStepsTurnsRaisesAndKeepsTheSpot` (from the
  moon's menu; steps, turn, a 2 s hold past one step, Keep, height up and back) and `testAFloorUnderASkyIsLandedOn`
  (`--demo-teleport` read back as "1.5 m ahead"); both fail with their part broken (hold stepped once, 8 cm; the old
  floor refused the landing). Focus Mode's UI tests 5 of 5. Captured: the panel below the terminal window, the menu.
- **Not seen:** the headset. Slide by hand, his second choice, not built.

## Open
- Sketchfab: KitBash bought it from Epic in August 2026; its Download API's future is unannounced. Not built.
- Live data in environments: proposed to the owner.
