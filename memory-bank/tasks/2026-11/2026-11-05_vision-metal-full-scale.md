# Vision Pro draws terminals with Metal at the headset's scale (D101, 0.4.605)

**Asked (2026-11-05):** offered three options after the SwiftTerm test app
(`2026-11-05_swiftterm-199-test.md`), he chose "go with option 1": keep SwiftTerm 1.20, carry the one-line scale
fix, and turn Metal on for Vision Pro. **Owner:** this session. **Authorization:** his choice; local build, tests
and install as usual. Not committed; reporting the bug upstream waits on his word.

## Changed

- `Packages/SwiftTerm/` (new): SwiftTerm v1.20.0 (`git archive`, `.swiftpm/` left out) with `PATCHES.md`:
  - S1 `Sources/SwiftTerm/iOS/iOSTerminalView.swift`: `backingScaleFactor()` on visionOS returns
    `traitCollection.displayScale`, 2 before a window.
  - S2 `Package.swift`: the build-info generator and plugin targets removed. `Sources/SwiftTerm/SwiftTermBuildInfo.swift`
    is new, hand-written for v1.20.0 and marked modified. In this repository the plugin would have run `git` on
    the app's own checkout.
  - `diff -rq` against the tag shows those three files and `PATCHES.md`, nothing else.
- `Package.swift`: `.package(path: "Packages/SwiftTerm")`.
  - `Package.resolved` and Xcode's copy (`sync-xcode-pins.py`): the swiftterm pin is gone, nothing else moved.
- `Tools/Licenses/components.json`: SwiftTerm is a vendored entry, with version 1.20.0.
  - `generate-acknowledgements.py` now passes a `version` through. `Acknowledgements.json` changed only by the
    note.
  - `Documentation/ThirdPartyLicenses/swiftterm/` is removed: it was the copy made from the pin.
- `THIRD-PARTY-NOTICES.md`: SwiftTerm moved to "Vendored in this repository".
- `Documentation/BUILDING.md`: no build-tool plugin now. The check-updates example tests swift-nio instead, and
  the section says vendored copies are listed.
- `Tools/Packages/check-updates.py`: `vendored_survey` and `vendored_markdown` find, for each vendored entry, the
  release tag at our revision and the newer ones.
  - Run 2026-11-05: SwiftTerm v1.20.0 → v1.99.2; RDPKit 0.3.1 → 0.8.0; tree-sitter-php v0.24.2 → v0.25.1. The
    others are the newest release or untagged commits.
  - `--notify` names them too.
- `Sources/GlassTerminalEmulator/SwiftTermHostView.swift`:
  - `SwiftTermRendererPreference.platformDefault`: Metal on visionOS by default.
  - The key is now `terminal.drawsWithMetalAtFullScale`. The old `terminal.drawsWithMetal` may hold the 10-29
    "off".
  - `visionDrawsWithMetal`.
  - DEBUG `markMetalDrawingForUITests`: `terminal-drawing-metal-<drawable px per pt>` on the terminal under
    `--ui-testing`.
- `Sources/GlassTerminal/TerminalRefreshCountsView.swift`: the Draw with Metal toggle defaults to
  `visionDrawsWithMetal`.
- Tests:
  - `UITests/GlassTerminalMetalUITests.swift` (new, visionOS): the demo terminal must read `terminal-drawing-metal-2.0`.
  - `TerminalCapabilityProbeTests.identity`: XTVERSION names `SwiftTerm 1.20.0+v1.20.0-modified`.
  - `glas_shTests` renderer test: visionOS expects Metal, like iOS. Its visionOS-only Core Graphics pixel check
    is removed, because a layer rendered into an image leaves Metal's drawing out.

## The Vision Pro terminal UI tests (visionOS 27.2 simulator)

**First run, Metal on:** Ornament 13/13, Paste, Schemes and Metal passed. 5 of 8 Selection tests failed, and
3 of 6 `GlassTerminalUITests` failed.

**Selection.**
- 4 of the 5 failures were my own test hook. The Metal marker overwrote the terminal's accessibility identifier,
  which is the selection tests' mark (`terminal-selection-active-<n>`). The marker now sits on an element of its
  own beside the terminal, only under `--ui-testing-mark-metal`.
- **`testDraggingAnEndOfTheSelectionMovesIt`** then still failed:
  - It failed with Metal and with Core Graphics. It passed at HEAD, and with S1 reverted.
  - **Cause: S1's half-point cells** move which letter lies at the terminal's middle, where the runner presses.
    It was column 64, the last letter of "screen", and became column 68, inside "select".
  - The drag then started at column 69, and the selection ran from 66 to 72 (end exclusive). That is 3 columns
    from both ends, out of reach of each (SwiftTerm's rule, and ours, is under 3). The log line
    `end drag refused …` (new, in `gestureRecognizerShouldBegin`) showed it.
  - The app behaves as designed. The test relied on where the middle fell.
  - Now it uses a `terminal-tmux-short` demo (no word over four letters, so any cell of a word or the space
    after it is in reach), and expects the count to grow from whatever was selected.
- `testAHoldSelectsTheWordHeld` still asserts the 6 letters of the word at the middle. That holds while the
  middle is in "select" or "screen", so it is the same kind of luck; not changed.

**`GlassTerminalUITests`.**
- **Advanced** and **settings pages** failed at HEAD too (checked on a worktree of `b28c27aa` with its own
  simulator):
  - Advanced: the Port row is below the sheet's fold and SwiftUI hadn't built it; the test now uses `reveal`.
  - Settings: the sidebar exposes each row as text. The test now looks for that too, and no longer presses a
    Done that the visionOS Settings window has never had.
- **testAddServiceCollectsTheAddressOnTheHost** passed at HEAD and failed here, though its screenshot showed
  the address. The system's Save Password alert came after the test's one look for it and covered the app's
  tree (the dump is the alert alone). The address check now answers "Not Now" whenever the alert is up.

**Final run, with all of the above, Metal on: 27 passed, none failed.** Metal 1, Ornament 13, Selection 8,
`GlassTerminalUITests` 3 (its other 3 need a live SSH host and skip), Paste 1, Schemes 1.
- The reworked drag test bites. With end drags refused (`return near && false`) it failed, "4 is not greater
  than 4". With the file restored (cmp identical) it passes.

**0.4.606** (the refusal log line; the rest of the change since 605 is DEBUG-only and UI tests): built for all
three. Installed and read back 0.4.606 (606) on the Mac, Vision Pro and iPhone. No new Mac crash report. The
temporary HEAD worktree is removed.

## Found, then fixed: `GlassTerminalTests` on Vision Pro and iPhone (2026-11-06)

**Found (2026-11-05):** the target did not build for visionOS, so its UIKit tests (the renderer test among them)
never ran anywhere. **Asked:** his "fixed that." in reply to "I haven't fixed that" (read as "fix that"; nothing in
the tree had changed since). Test files only; no app code changed.

**To build** (each failure seen in the visionOS build log, in turn):
- `TerminalAgentBackdropRenderTests`: imported AppKit for `NSBitmapImageRep`. It now reads the drawing's pixels
  through Core Graphics and runs everywhere.
  - The drawing is 8-bit sRGB; AppKit's `colorAt` called its values calibrated RGB and converted them again. The
    Mac's readings went from 0.313 and 0.729 (inflated) to 0.243 and 0.667, the image's own; Vision Pro reads the
    same. Thresholds 0.2 and 0.12 kept. The probe that showed it was deleted.
- `SFTPBrowserHelperTests`: the table-sort test uses the Mac's `Table` row and sort types, now `#if os(macOS)`.
- `LiveProcess`: `GlassSpawn` is the Mac's (the app starts programs there only). Off the Mac the helper sets the
  same spawn attributes itself; a simulator runs on the Mac and starts the Mac's programs.
- `TestDefaults`: `homeDirectoryForCurrentUser` is unavailable on visionOS; there the simulator's own home.

**First run on the visionOS 27.2 simulator: 737 tests, 13 failed.** None was a fault in the app:
- `glas_shTests`, 5 UIKit tests: each asked for the app's window scene, and a package's test process has none.
  `testWindow(frame:)` uses a scene when there is one, else a window of its own (deprecated `init(frame:)`, one
  warning).
  - **`visionWorkgroupRepeatedPresentationTransitionsRetainTerminals`:** with a window of its own the run
    stopped. visionOS asserts that an ornament has a scene ("Invalid condition not satisfying:
    builder.identifier", `xctest-2026-11-06-071914.ips`). It is now `.enabled` only with a window scene, and
    skips with that reason.
  - **`visionPreviewIsBoundedReadOnlyAndPreservesGeometry`:** asked once, and the picture comes the next turn
    since 0.4.537 (drawn after SwiftUI's update). It now waits for it. Its pixel check fails with no scene:
    the picture is the window as composited (`drawHierarchy`), which needs a display, and Metal's drawing is in
    nothing else.
    - **Not a D101 regression:** the real app's dock (`--demo-open dock --demo-dock-alone`, captured with Metal
      and with Core Graphics, `<work>/swiftterm-bench/shoot-dock.sh`) shows the btop terminal's picture the same
      under both (largest difference 2 of 255).
    - The pixel check is now its own test, `visionPreviewShowsTheTerminalsDrawing`, which skips with no window
      scene.
    - Seen in passing: the agent stack's orb in the dock demo is empty under both renderers. Not looked into.
- `WorkgroupMacTerminalsTests.macRecordsItself`: only a Mac claims a workgroup's local terminal
  (`upsertLayoutPreset`, `#if os(macOS)`). Off the Mac the test now expects nothing recorded.
- `TerminalTmuxTests` `unlisted`, `reconnect`, `startupOnlyWhenCreated`: off the Mac a terminal in tmux also reads
  its session's name once attached (`readsTmuxPane`). `asksTheHost` leaves that read out, as it does `tmux -V`.
- `TerminalTmuxTests` `scrollingLive`, `historyLive`: the tmux socket in the simulator's temporary folder was 139
  characters (the limit is 104). They now use `/tmp/gpt-…`, as `listingLive` already did.
- `SSHPrivateKeyImportTests`, 3 tests: ssh-keygen started from the simulator stops, "No user exists for uid 501"
  (its failure message now carries ssh-keygen's output). Now `.enabled` on the Mac only, saying why.

**iPhone (iOS 27.2 simulator, iPhone 17), first run:** 737 tests, one failed.
`ShownTerminalsReconnectTests.activeReconnectsAReopenedTerminal` was written for Vision Pro and the Mac. On iPhone
and iPad a slot connects as it is shown (`slotsConnectWhenShown`, W4b), and `reconnectIfDropped` leaves it alone.
The test now expects that on iOS.

**Final runs, all of the above:**
- **visionOS 27.2 simulator:** 738 tests, none failed (718 passed). Skipped with their reason: the two that need a
  window scene, the three that need ssh-keygen, and the live-SSH ones (no `GPT_SSH_TEST_HOST`, as on the Mac).
- **iOS 27.2 simulator, iPhone 17:** 737 tests, none failed. The renderer test and
  `iOSTerminalWorkgroupPresentationRemainsResponsive` passed, both for the first time since glas.sh. Skipped: the
  three ssh-keygen tests and the live-SSH ones.
- **Mac** (`swift test --filter GlassTerminalTests`): 1,110 tests, none failed.
- Command: `xcodebuild build-for-testing` / `test-without-building -workspace .swiftpm/xcode/package.xcworkspace
  -scheme TerminalTests` (a one-target scheme, git-ignored) with a simulator destination.
- **Still not run:** the two window-scene tests. They need an app-hosted unit-test target, which the project does
  not have. Asked of him.

**Bites** (each broken, run, restored, cmp identical):
- Vision Pro, one build with four breaks: `visionDrawsWithMetal = false` failed the renderer test (`backend ==
  .metal`); claiming on every platform in `upsertLayoutPreset` failed `macRecordsItself` (two checks); dropping the
  pane-read clause failed the three tmux counts; thresholds of 0.99 failed both backdrop checks (0.667, 0.243).
- iPhone: removing the slot exemption in `reconnectIfDropped` failed the iOS branch.

## Validation

- **Package tests (Mac):** `swift test --disable-keychain --scratch-path <work>/spm-probe`, 3,368 tests in 19 runs,
  none failing. The Acknowledgements suite passed, and `generate-acknowledgements.py --check` reports it up to date.
- **XTVERSION bites:** with `SwiftTermBuildInfo.tag` set to nil, the reply was `SwiftTerm+5d1440684414-modified:`
  and the test failed. With the file restored (cmp identical) it passes.
- **`GlassTerminalMetalUITests` (visionOS 27.2 simulator):** passed (16 s). With S1 reverted to upstream's file
  it failed with `"terminal-drawing-metal-1.0" is not equal to "terminal-drawing-metal-2.0"`. With S1 restored
  (cmp identical) and the app rebuilt, it passed again (15 s).
- **The real app's demo terminal (`--demo-open agent`, Metal, then Core Graphics):** captured on the visionOS
  simulator with `<work>/swiftterm-bench/shoot-app.sh`. The Core Graphics run used the launch argument
  `-terminal.drawsWithMetalAtFullScale '<false/>'`.
  - With continuous output (`agent-busy`), Refresh Counts read "Metal frames 39 a second" and no repaints under
    Metal, and "Metal frames 0", "Terminals drawn whole 19 a second" under Core Graphics.
  - Text, colours, cursor and glass are the same. In the terminal area no pixel differs by more than 24 of 255;
    at 4× the two are equally sharp.
- **0.4.605 Release:** built for macOS, iOS and visionOS. The visionOS log compiled
  `Packages/SwiftTerm/.../iOSTerminalView.swift` and no SwiftTerm checkout.
  - Installed on the Mac (detached install script), Vision Pro and iPhone. All three read back 0.4.605 (605).
  - No new Mac crash report.
- **Private-data scan of today's diff and new files:** nothing. The only home paths in `Packages/SwiftTerm` are
  its author's own, in his public tests and sample app.
