# Stage 1 — why the macOS UI tests failed, and the fix

Owner: macOS UI-test worker, 2026-09-10, on top of `17e79be` plus the integration worker's
uncommitted `press(_:)` change. **Status: macOS 5/5, iOS 5/5, visionOS 4 passed + 1 skipped, all on the same final tree.**

## Root cause, with evidence

`XCUIElement.tap()` compiles on macOS but, under Xcode 27.0 (27A5252f) on macOS 27.0 with a SwiftUI
app, it does not drive SwiftUI controls. The runner synthesizes the event, then waits its full 5 s
idle timeout, and the control never acts. `click()` on the same element works within a second.

Measured with a throwaway probe (`_MacClickProbeUITests`, deleted) against the real app, isolated
store, same element `connection-library-add-host-empty`:

| Gesture | Result |
|---|---|
| `element.tap()` | runner logs `Tap … Button`, ~10 s stall, `host-editor-name` never exists, `sheets = 0` |
| `element.click()` immediately after | `Click … Button`, sheet present in ~2 s, `host-editor-name` exists, `sheets = 1` |
| `radioButtons["Appearance"].click()` in the Settings window | page switches (`value 0 → 1`), `layers-paints-theme` present in ~1.7 s |

Ruled out first, so nobody re-checks: the app idles at 0.0 % CPU with no hot frames (no render
loop); the runner resolves every element rect on display 1 of the two attached displays; keystrokes
(`⌘,`) always worked; `app.activate()` makes no difference; the window's `Disabled` flag in the AX
tree is normal for a window element and unrelated. Nothing in `GlassLayeredWindow`,
`GlassWindowLayerPolicy` or the reader intercepts the mouse — both are `.background`s and the reader
returns `nil` from `hitTest`. **No product code changed.**

So the family rule for XCUITest on macOS is: activate elements with `click()`; `tap()` is
touch-only. The suite's `press(_:)` helper routes this per platform.

## Second macOS difference

Static text on macOS exposes its string as the AX **`value`**, not `label` (see the captured trees:
`StaticText … value: 'Settings Section'`). The placeholder-copy assertion used
`label CONTAINS`; it now checks `label … OR value …`. Same fix applies to any future text assertion.

## iOS toggle race (from the coordinator's iOS run)

`testAppearanceOpacityPersistsAcrossRelaunch` read the Switch value synchronously after tapping it
and saw `"0" == "0"`. Two causes, both fixed: the value updates asynchronously, so the test now
waits with an `XCTNSPredicateExpectation` for it to change; and on iOS a Form `Toggle` is exposed as
one Switch element spanning the whole row, so a press at its center lands on the label and does not
toggle — proven by the same wait still expiring (`XCTWaiterResult 2`) after the async fix alone.
iOS now presses at the trailing edge (`dx: 0.92`); macOS keeps a centre click on the CheckBox;
**visionOS keeps a centre tap** — on the visionOS simulator the edge press does not flip the Switch
(the value wait expired and the runner restarted the app), while the centre tap always did. The test targets the control itself (`switches` / `checkBoxes`, falling back to the
identified element).

## Files changed

- `UITests/GlassShellLibraryUITests.swift` only: kept the integration worker's `press(_:)` (click
  on macOS, tap elsewhere), routed the three navigation-bar back presses through it, label-or-value
  predicate for the placeholder copy, asynchronous toggle check.
- Probe files created and deleted: `_MacClickProbeUITests.swift`.

## Results

macOS, `-only-testing:GlassPowerToolsUITests`, derived data `scratchpad/dd-mac-smoke`, build-time
`noKVS.xcconfig` (the project's iCloud KVS entitlement untouched):

| Test | Result |
|---|---|
| `LaunchSmokeUITests.testMainWindowAppears` | passed (2.2 s) |
| `testAddHostAddServiceConnectPlaceholder` | passed (23.5 s) |
| `testAppearanceOpacityPersistsAcrossRelaunch` | passed (16.0 s) |
| `testFavoriteAppearsInFavoritesScope` | passed (13.3 s) |
| `testSearchFiltersRows` | passed (18.4 s) |

**5 executed, 0 failures.** Log: `scratchpad/mac-final-uitests.log`; bundle
`scratchpad/results-mac-final.xcresult`.

iOS, iPhone 17 Pro Max (iOS 27.0) simulator, derived data `scratchpad/dd-ios`, full suite on the
final tree:

| Test | Result |
|---|---|
| `LaunchSmokeUITests.testMainWindowAppears` | passed (4.6 s) |
| `testAddHostAddServiceConnectPlaceholder` | passed (29.4 s) |
| `testAppearanceOpacityPersistsAcrossRelaunch` | passed (35.7 s) |
| `testFavoriteAppearsInFavoritesScope` | passed (21.0 s) |
| `testSearchFiltersRows` | passed (31.2 s) |

**5 executed, 0 failures.** Log `scratchpad/ios-final2-uitests.log`, bundle
`scratchpad/results-ios-final2.xcresult`. The macOS Appearance test was re-run after the final edit
and passed again (16.1 s), so the macOS 5/5 above stands on the same tree. visionOS was run by the
coordinator on the earlier tree and again by me on the final tree (Apple Vision Pro, OS 27.0,
derived data `scratchpad/dd-vision`, log `scratchpad/vision-final2.log`):

| Test | Result |
|---|---|
| `LaunchSmokeUITests.testMainWindowAppears` | passed (22.7 s) |
| `testAddHostAddServiceConnectPlaceholder` | passed (32.0 s) |
| `testAppearanceOpacityPersistsAcrossRelaunch` | passed (32.2 s) |
| `testFavoriteAppearsInFavoritesScope` | passed (19.9 s) |
| `testSearchFiltersRows` | skipped, with the integration worker's recorded reason |

**5 executed, 1 skipped, 0 failures.** iOS full suite re-run after the visionOS change
(`scratchpad/ios-final3-uitests.log`): smoke 5.3 s, add-host/… 29.6 s, appearance 36.5 s, favorites
21.1 s, search 32.2 s — **5/5 passed**. macOS is unaffected by the change (its branch is untouched).

Per-platform toggle press, recorded once so it is not re-derived: macOS centre `click()` on the
CheckBox; iOS trailing-edge tap (`dx: 0.92`) on the row-wide Switch; visionOS centre `tap()`.
