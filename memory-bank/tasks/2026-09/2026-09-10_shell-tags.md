# Shell tags: system-wide tag vocabulary and token editor — 2026-09-10/11

Worker W5. User requirement: "system wide tags, are essential. labels, groups, clients... comma
separated is a non starter". Not committed (coordinator commits; the kit stays uncommitted for the
user).

## Assumption (stated, not decided by the user)

Tags are **one flat, system-wide vocabulary**. Labels, groups and clients are uses of tags, not tag
types. Nothing in the model contradicts this: `HostProfile.tags: [String]` and
`EndpointProfile.tags: [String]` are plain string lists, and the library sidebar's Collections
scope is already derived from those tags (`GlassLibraryProjection`). If typed tags are wanted
later, the vocabulary type is the place to add a kind.

## Reuse check

- `HostProfile.aliases`/`.tags`, `EndpointProfile.tags` (`../GlassConnectionKit/Sources/GlassConnectionKit/HostProfile.swift:54,56`, `EndpointProfile.swift:159`) — model unchanged.
- `GlassShellHost.tags` is already the case-insensitive union of consolidated members' tags (`Sources/GlassShell/GlassShellHost.swift:44-55`) — the vocabulary builds on it.
- No token/tag field existed in the kit or any sibling; glassDT's editor has the same comma-separated drift (`../glassDT/Sources/GlassDesktopUI/ConnectionEditor.swift:52`, not edited).
- Endpoint tags are not reachable from the shell model today (it exposes hosts and service links, not `EndpointProfile`s), so the vocabulary is host tags only; a capability that edits endpoint tags should feed them in when that surface exists.

## Changed files

| Path | Change |
|---|---|
| `../GlassConnectionKit/Sources/GlassConnectionUI/GlassTagField.swift` (new) | `GlassTagList` (normalise: trim, drop empties, case-insensitive dedupe keeping first spelling and entry order; `adding` splits on commas/newlines), `GlassTagSuggestions.matches` (prefix before substring, excludes chosen, limit 8, empty query offers the vocabulary), `GlassTagField` (chips with Remove buttons, trailing plain text field: Return/comma commit, Backspace on empty removes last chip, suggestions shown while focused as "Add <tag>" buttons), `GlassTagFlowLayout` (wrapping `Layout`). Identifiers: `<base>`, `<base>.input`, `<base>.tag.<n>` (label "<tag>, tag"), `<base>.tag.<n>.remove` (label "Remove <tag>"), `<base>.suggestions`, `<base>.suggestion.<n>`. |
| `../GlassConnectionKit/Tests/GlassConnectionUITests/GlassTagFieldTests.swift` (new) | 3 tests: normalisation, comma/newline commit, suggestion ranking/exclusion/limit. |
| `Sources/GlassShell/GlassShellTagVocabulary.swift` (new) | `GlassShellTagVocabulary.tags(in:)` and `GlassShellModel.tagVocabulary`: union of every host's tags, deduped, sorted case-insensitively. |
| `Sources/GlassShell/GlassShellEditors.swift` | Host editor: "Also known as" and "Collections" are `GlassTagField`s in their own form sections; state is `[String]`; collections get `model.tagVocabulary` as suggestions; `split(_:)` removed. Service editor unchanged (it exposes no tags). |
| `Tests/GlassShellTests/GlassShellTagVocabularyTests.swift` (new) | 2 tests. |
| `Tests/GlassShellTests/GlassShellModelTests.swift:186` | One line (W4's file, necessary to compile): the `split` assertion now goes through `GlassTagList.adding`; added `import GlassConnectionUI`. |
| `UITests/GlassShellTagFieldUITests.swift` (new) | End-to-end: two chips typed with Return, comma commit, case-insensitive duplicate dropped, Backspace removal (macOS), alias chip, save; second host sees "Add Clients" suggestion on focus, picks it, chosen tag no longer offered; Clients collection appears in the sidebar. Screenshots `tag-field-two-chips`, `tag-field-suggestions`. |

`UITests/GlassShellLibraryUITests.swift` needed no change: no test typed a comma-separated string.

## Root cause found while testing

AppKit's field editor consumes Backspace before SwiftUI's `onKeyPress` sees it, even on an empty
field, so the first macOS run failed at "Backspace removed Lab". `GlassTagField` now installs a
local `NSEvent` key-down monitor (keyCode 51, no Command/Option/Control) that is live only while
the field is focused and empty; `onKeyPress(.delete)` stays for hardware keyboards on iOS/visionOS.

## Verification (all real runs; logs and result bundles in the session scratchpad)

| Run | Result |
|---|---|
| Kit `swift test` (`../GlassConnectionKit`) | **passed: 51 tests / 9 suites** (17 + 13 + 21; includes the 3 new `GlassTagFieldTests`) |
| Whole package `swift test --build-system native` (scratch path `build-w5`) | **passed: 461 tests / 25 suites** (`w5-swift-test.log`); includes 2 new vocabulary tests and the adjusted model test |
| App builds, Debug, derived data `dd-w5` | macOS **passed**; iOS Simulator **passed**; visionOS Simulator **passed** (`w5-app-builds.log`; xcodebuild `-quiet` printed its spurious "exit code 0 but produced no further output" line on each — exit 0, products present) |
| macOS `GlassShellLibraryUITests` | **passed 5/5** (`results-mac-w5.xcresult`) |
| macOS `GlassShellTagFieldUITests` | first run **failed** at Backspace (above); after the monitor **passed 1/1** (`results-mac-w5b.xcresult`): two chips typed with Return, comma commit, case-insensitive duplicate dropped, Backspace removes last chip, alias chip, save; second host sees "Add Clients" on focus, picks it, "Add Lab" remains; Clients collection in the sidebar |
| iPhone 17 Pro Max simulator (iOS 27.0) `GlassShellLibraryUITests` | **passed 5/5** (`results-ios-w5.xcresult`) |
| iPhone `GlassShellTagFieldUITests` | first run **failed** only at the final sidebar assertion (iPhone was on the pushed detail); test now pops back to the scopes list on iOS; **passed 1/1** (`results-ios-w5b.xcresult`) |
| visionOS UI run | **not run** (not in the brief); the app builds for visionOS and the field uses standard controls |

Screenshots (element/own-window captures only): `scratchpad/shots-w5/mac-tag-field-two-chips.png`,
`mac-tag-field-suggestions.png` (exported from the xcresult: on macOS the `GPT_SHOTS_DIR` copy was
not written although the attachments were), `ios-tag-field-two-chips.png`,
`ios-tag-field-suggestions.png`. Judged by eye: chips "Clients ⊗" / "Lab ⊗" in a tinted capsule
with the input trailing; suggestions as "+ Clients" / "+ Lab" outlined capsules under the input;
form sections "Also known as" / "Collections" on both platforms.

## Remaining

- visionOS: build passes; no UI run of the field yet (ornament/hover look unverified by eye).
- On macOS, `GPT_SHOTS_DIR` was empty after both runs while the XCTest attachments were present;
  not investigated (the helper is W4's file).
- Endpoint tags are not part of the vocabulary until a capability exposes `EndpointProfile.tags`
  to the shell.
- glassDT's own editor still uses a comma-separated field (not edited; Stage 4 replaces it).
