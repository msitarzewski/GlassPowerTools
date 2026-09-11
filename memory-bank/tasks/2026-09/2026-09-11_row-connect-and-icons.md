# Library row, connect control, service icons, detail action bar, Delete — W9, 2026-09-11

Worker W9. Baseline `b932dd8`. Not committed (coordinator commits).

User requirements, verbatim:

> "Remove the word connect, remove the last ocnnected [never] and the number of services
> connected. The glance at the icons reveals how many services are connected. This is a unilateral
> move (all platforms). Move the dropdown into the button... a click/tap on the Play itself loads
> all services. A click/tap/pinch on the arrow allows a single service to become active. Were are
> these icons from? use the circle-stack from hero icons, please for the DB. The others are fine.
> Also fleet wide."

> "I expect these buttons on Mac... are we using Apple HIG/UX patterns in this panel? I see missing
> background. Seems like a miss." / "Check all platforms."

> "Let's move delete into the edit modal or in a right/context click/pinch."

## What changed

**Row (kit + shell).** `GlassLibraryConnectionRow` no longer draws a "last connected" value, and
its `subtitle` is now optional. The `lastConnected` parameter is **removed from the kit API**. The
shell passes no subtitle, so a row is the host's name plus its service icons and the connect
control. `GlassShellModel.subtitle(for:)` stays: `GlassLibraryItem.subtitle` still carries it (the
projection and tests use it), the row just does not draw it.

**Connect control (shell).** `GlassShellConnectControl` is a split control with no text on any
platform:

| Region | Identifier | Does |
|---|---|---|
| play glyph | `host-connect` | `model.connectAll(hostID:)` — opens **every** service on the host |
| chevron | `host-connect-menu` | menu of the services; each opens only itself (`host-connect-menu-<kind>`) |

A host with one service is a plain prominent play button, no chevron. SwiftUI has no native split
button (`Menu(primaryAction:)` opens its menu only on a long press off macOS), so the two halves
are drawn in one accent capsule with a hairline between them; each half is its own hit region, so
the chevron works with a click, a tap and a visionOS pinch. Verified by a UI test that passes on
all three platforms.

**`GlassShellModel.connectAll(hostID:)`** opens each service in the host's order through its
capability, and records **no** "last used" service, because the user chose the machine and not one
service. `connect(hostID:endpointID:)` still records it. Both funnel into one private `open(_:on:)`,
so outcome reporting and the "last connected" stamp are unchanged. A kind with no capability in
this build reports itself and the remaining services still open.

**Database icon.** Was SF Symbol `externaldrive`; now Heroicons v2 `circle-stack`. Terminal
(`terminal`) and desktop (`display`) keep their SF Symbols. New kit types: `GlassServiceSymbol`
(`.system(String)` / `.circleStack`), `GlassServiceIcon` (draws either at text size, tinted by the
foreground style), and `HeroiconCircleStack: Shape`. `GlassServicePresentation.symbolName(for:)`
is replaced by `symbol(for:)`; every draw site (row icons, detail service rows, connect menu) uses
`GlassServiceIcon`.

**Detail action bar (kit).** `GlassLibraryDetail` painted `.bar` behind a content-sized `HStack`,
so the window's layered theme showed through at both ends. It now has a `Divider()` above and the
actions row is `.frame(maxWidth: .infinity, alignment: .trailing)` **before** `.background(.bar)`,
with 20/12 padding — the actions sit trailing, as the family's sheets place Cancel and their
primary action, so the two bars read as one pattern.

**Delete.** Removed from the detail's action bar (which keeps Connect and Edit). It now reaches the
user two ways: the library row's context menu (`host-delete`, right-click / long-press / pinch),
and a destructive "Delete Host…" section at the bottom of the sheet in `.editHost` mode only
(`host-editor-delete`), behind the same confirmation (`host-delete-confirm`). "Remove Service" stays
in the service row's context menu. A host with no services gets copy that does not say "its 0
service links".

**Settings Done on iPhone (regression fixed).** The compact settings list (`pushList`, added in
`b932dd8`) pushes each page onto the sheet's stack, leaving the presenter's Done button behind on
the root — the sheet became undismissable from a page, and two iPhone tests failed on
`missing settings-done`. `GlassShellSettingsView` now attaches its own Done (via
`@Environment(\.dismiss)`) to each page on compact iOS only, so no duplicate appears in the
segmented layouts.

## Icon provenance

The genuine MIT-licensed asset, not a lookalike. There was no local copy (searched `~/Software`,
npm/pnpm/yarn caches), so it was fetched from upstream and vendored:

- `../GlassConnectionKit/Vendor/heroicons/circle-stack.svg` — Heroicons v2
  `optimized/24/outline/circle-stack.svg`, Tailwind Labs.
- `../GlassConnectionKit/Vendor/heroicons/LICENSE` — the project's MIT licence.

`HeroiconCircleStack.path(in:)` is that file's single `d` attribute translated one-for-one into
`Path` (24×24 viewport, 1.5 stroke, round caps and joins). The `d` string is quoted in the doc
comment so it can be diffed against upstream. `Vendor/` sits outside `Sources/`, so SwiftPM does
not treat it as an unhandled resource.

## Sibling call sites the kit change breaks

Removing `lastConnected:` from `GlassLibraryConnectionRow` is a source break for three call sites.
**Not edited** (out of scope, and the fleet-wide change is the user's intent). Each needs the
argument dropped:

| Repo | File:line |
|---|---|
| glassdb | `glassdb/ConnectionManagerView.swift:756-760` |
| glassDT | `Sources/GlassDesktopUI/DesktopLibraryView.swift:48-49` |
| glas.sh | `glas.sh/ConnectionManagerView.swift:3385-3387` |

Their own `lastConnected` model properties are untouched and still used elsewhere (widgets, sort
orders); only the row argument goes. They also inherit the detail action-bar fix and, once they
adopt `GlassServiceIcon`, the circle-stack.

## Verification

| Check | Result |
|---|---|
| Kit `swift test` | **passed**: 17 + 13 + 23 tests |
| Package `swift test --build-system native` | **passed: 485 tests / 30 suites** (483 before, +2 new) |
| Builds: macOS, iOS Simulator, visionOS Simulator (`build-for-testing`) | all **exit 0** |
| macOS UI, all suites, real host (`results-w9-mac4.xcresult`) | **14 / 14 passed**, including the live-shell connect |
| iPhone 17 Pro Max UI, all suites, real host (`results-w9-ios3.xcresult`) | **13 / 13 passed** (`** TEST SUCCEEDED **`), live shell in 192 s |
| visionOS UI, all suites, real host (`results-w9-vision2.xcresult`) | **11 passed, 1 skipped** (search, known), **1 failed**: `testConnectsToRealHostThroughTheShell` — XCUITest's "Failed to received invalid scene ID (nil) from Accessibility", the pre-existing simulator fault, unchanged by this work |

New tests: `connectAllOpensEveryService` and `connectAllReportsUnavailableKinds` (unit, with a
recording fake capability); `testRowConnectControlIsSplitAndCarriesNoLabel` and
`testDeleteHostLivesInTheEditSheetNotTheActionBar` (UI, all three platforms).

Screenshots (own window only), exported from the result bundles:
`att-w9-mac6/…209D23EB….png` (row: name, three icons including the circle-stack, split play|chevron,
no words, no date, no subtitle), `att-w9-mac/…82571BA1….png` (Delete Host… at the bottom of the
edit sheet with its footer), `att-w9-mac/…CB3D0BF5….png` (two rows in the library).

### Two run traps worth keeping

- **Use `scratchpad/dd-uitest` for macOS UI runs.** A fresh derived-data path produces a binary at
  a new location that macOS has not granted Local Network access, and the real-host test fails with
  "Could not reach 192.0.2.6:22" even though the VM is up. Same tree, same tests, passing path.
- `dismissSystemPasswordPrompt()` asked for `com.apple.springboard`, which does not exist on macOS
  and failed five macOS tests outright. Now guarded to the touch platforms.

## Observations, not changed in this pass

- The connect-failure alert suggests granting Local Network access for **any** timeout. When the
  address simply has nothing behind it (the user's host said `192.0.2.6`; the VM is at
  `192.0.2.6`) the hint is misleading. Worth gating on "the host is on a local subnet **and** the
  app was actually denied" — not trivial, so not done here.
- "Delete Host…" carries `role: .destructive`; macOS renders a plain destructive button without red
  tint. Left native per project rule 15.

## Remaining

- The three sibling call sites above compile-break until updated.
- visionOS real-host UI test still blocked by the simulator's scene-ID fault.
