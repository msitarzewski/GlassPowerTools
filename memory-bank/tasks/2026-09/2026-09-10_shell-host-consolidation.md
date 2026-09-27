# Shell: one row per host, every service's icon — and the visionOS row fix

Worker: shell-host-consolidation. 2026-09-10. **Status: built, unit-tested, visionOS row proven on the
simulator, iOS UI suite green on a copy of the tree. Not committed.**

## Root cause (evidence)

The user's iPhone showed `bravo / Terminal` and `bravo / Desktop` as two rows. The shared
catalog was written by three apps that never shared host identity:

- `../GlassConnectionKit/Sources/GlassHostCatalog/HostCatalogStore.swift:91-125`
  (`applyPublication`): a publication matches an existing record **only by endpoint id**
  (`services.contains { $0.endpointID == service.endpointID }`); otherwise it creates a new
  `HostProfile` whose id is the endpoint's id (`:115`). There is no matching by display name or
  alias anywhere in the store.
- glas.sh publishes `HostPublication(hostName: saved.name, aliases: [saved.host])`
  (`../glas.sh/glas.sh/ConnectionManagerView.swift:116-119,140`); glassdb the same
  (`../glassdb/glassdb/ConnectionManagerView.swift:262-265,286`); glassDT the same
  (`../glassDT/Sources/GlassDesktopUI/DesktopAppModel.swift:227,262-264`).
- So one machine saved in glas.sh and in glassDT is two records with the same name and alias and
  different ids. The only thing that ever merged them was explicit pairing in the UI. The Vision
  Pro's `alpha`, which shows as one host with two services, is a record that *was* paired there;
  the iPhone's `alpha` was not. Both shapes exist in real data.

## Design

Presentation-level consolidation in the shell; **hosts.json is not rewritten** in this stage.

- `GlassShellHost` (new, `Sources/GlassShell/GlassShellHost.swift`): the library's host — one or
  more catalog records (`members`, canonical first) with the union of their services (deduped by
  endpoint), aliases and tags. Canonical = oldest `createdAt`, tie-break by id. `member(owning:)`
  finds the record that holds an endpoint.
- `GlassShellHostGrouping.group(_:)`: union-find over records; two records join when their
  normalised display names are equal (trimmed, case-folded, canonical composition, trailing
  `.local` dropped) **or** they share a non-loopback alias. `localhost`/`127.0.0.1`/`::1`/`0.0.0.0`
  never link records.
- `GlassShellModel`: `hosts: [GlassShellHost]`, `records: [HostProfile]` (as stored, for
  diagnostics); `host(_:)` resolves a canonical **or member** id; `canonicalID(for:)`. Favorites,
  last-connected and last-used key on the canonical id; preferences recorded against a member id
  before grouping migrate once on load (`migratePreferencesToCanonicalHosts`: favorite if any
  member was, latest connection wins, its last-used service). `addService` → canonical record;
  `removeService` → the owning record; `deleteHost` → every member; `updateHost` renames every
  member (so the group survives) and applies aliases/tags to the canonical; `connect` hands the
  capability the **owning record**, since the capability's own store is keyed by that endpoint id.
- `consolidateRecords(of:)`: the Stage 6 operation — moves every member service to the canonical
  record, unions aliases/tags, tombstones emptied members. Written and tested, **not reachable
  from any UI**.
- Settings → General shows "Catalog records" only when it differs from the host count, with a
  one-line explanation. Nothing else in the main UI mentions records.
- `--ui-testing-seed-hosts "name:kind+kind|name:kind"` (DEBUG, only with `--ui-testing`, only
  into a non-Group-Container catalog, only when empty) seeds records for UI tests.

### visionOS row (coordinator's added defect)

`GlassShellLibraryView.row` on visionOS uses a compact accessory: the service icons in one row and
`GlassShellConnectControl(compact: true)` — icon-only Connect (`labelStyle(.iconOnly)`,
`.fixedSize()`, press-and-hold still opens the picker) — wrapped in
`.fixedSize(horizontal: true, vertical: false)` so nothing wraps. Wide platforms keep the labelled
button, now `.lineLimit(1).fixedSize()`. "Never"/last-connected is the kit row's trailing text and
stays; it fits once the accessory is single-line.

## Capability hooks (coordinator's addition for W3)

`GlassCapability` gains three requirements with defaults: `settingsPages: [GlassCapabilitySettingsPage]`
(`[]`), `libraryToolbarItems() -> AnyView` (empty), `serviceDetailActions(service:host:) -> AnyView`
(empty; `host` is the catalog record that owns the service). `GlassCapabilitySettingsPage
{ id, title, systemImage, makeView }`. `GlassCapabilityRegistry` adds `registered` (kind order),
`settingsPages`, and `serviceDetailActions(service:host:)`, which asks only the owning kind.

`GlassShellSettingsView` selects over `GlassShellSettingsSelection { .shell(page) | .capability(id) }`
— the shell's four pages first, then every registered capability's pages in kind order; a
capability page renders inside the same `GlassSettingsSections` picker (`settings-sections`
identifier unchanged) with `settings-page-<id>` on its content. `GlassShellLibraryView` renders
every registered capability's `libraryToolbarItems()` before Add Host in `toolbarActions`, and
`serviceDetailActions` beside each service's Connect in the detail (identifiers unchanged).

Tests (`GlassShell capability hooks`, 2): a registered capability's page joins the selection after
the shell's pages in kind order; detail actions are requested from the owning capability only.
Suite total: **29 tests, 5 suites, passed**.

## Why not merge on disk now (Stage 6 plan)

glas.sh, glassdb and glassDT read `hosts.json` by their own record ids and by endpoint id. Moving
an endpoint to another record (what `consolidateRecords` does) would still let them *find* the
endpoint (they match by endpoint id) but would delete the record whose id their pairing UI holds,
and any app that later republishes would recreate it — churn until they stop writing. When the
three apps are retired (Stage 6) or made read-only against the catalog, run `consolidateRecords`
for every consolidated host once, then drop the grouping to a plain identity map.

## Files

- New: `Sources/GlassShell/GlassShellHost.swift`, `Tests/GlassShellTests/GlassShellConsolidationTests.swift`
- Changed: `Sources/GlassShell/GlassShellModel.swift`, `GlassShellLibraryView.swift`,
  `GlassShellEditors.swift` (editors take `GlassShellHost`), `GlassShellSettingsView.swift`,
  `UITests/GlassShellLibraryUITests.swift` (`launch(extraArguments:)`,
  `testSameMachineRecordsAreOneRowWithAllServiceIcons`)

## Results

| Check | Result |
|---|---|
| `swift build --build-system native` (whole package) | Build complete |
| `swift test --build-system native --filter GlassShellTests` | **29 tests, 5 suites, passed** (9 consolidation + 2 hook tests new; consolidation: same name different case; alias overlap; unrelated + loopback; already-single record untouched; preferences migrate; delete all members; add→canonical / remove→owner; picker + connect hands owning record; consolidateRecords) |
| visionOS Simulator (Vision Pro, OS 27.0), app seeded `bravo:ssh\|bravo:rdp\|alpha:rdp+ssh`, `simctl io screenshot` | `scratchpad/shots/vision-consolidated-row.png`: **two rows** (the Mac, the Linux server), each "Desktop · Terminal" with two icons, an icon-only Connect and "Never" on one line; no wrapping |
| iOS Simulator (iPhone 17 Pro Max, iOS 27.0) UI suite `GlassShellLibraryUITests` | **6/6 passed** across two runs on a verbatim copy of the tree excluding another worker's in-progress `UITests/GlassTerminalUITests.swift` (which does not compile at :291, main-actor key path — not mine): appearance, favorites, search, smoke and the new `testSameMachineRecordsAreOneRowWithAllServiceIcons` (one row each for `bravo` and `alpha`, two `host-service-ssh` and two `host-service-rdp` icons); `testAddHostAddServiceConnectPlaceholder` re-pointed and passing (below) |
| Stage 2 side effect found | `testAddHostAddServiceConnectPlaceholder` expected the placeholder after Connect on an SSH service, but since `5f12575` the app registers `GlassTerminalCapability` for `.ssh`, so Connect opens the terminal's server form. The placeholder contract is for kinds no capability owns; the test now seeds a `database` service (`--ui-testing-seed-hosts "dbhost:database"`) into a fresh isolated store for that step. Seeded relaunches must use a new `runID`: the seeder fills only an empty catalog |
| macOS / iOS device rows | not run |

## Final iOS run and an observation outside my scope

- Final `GlassShellLibraryUITests` run after the hooks (fresh copy, iOS 27.0): add-host/placeholder,
  appearance, favorites and the consolidation case **passed**; `testSearchFiltersRows` was
  interrupted mid-run by the test runner restarting ("Restarting after unexpected exit, crash, or
  test timeout" while waiting for `host-editor-save`, no assertion, no app crash report for the
  simulator) and **passed on an immediate solo re-run (32.5 s)**. Treated as runner flakiness; the
  test is unchanged from the version that passed every earlier run.
- **Not mine, for the coordinator:** five `GlassPowerTools` crash reports between 18:04 and 18:22
  (`~/Library/Logs/DiagnosticReports`, some under `Retired/`) are all the **macOS** app —
  `EXC_BAD_ACCESS` in `CoreFoundation ___CFBasicHashFindBucket_Linear ← CFDictionaryGetValue ←
  AppKit _accessibilityFindRoleFromProtocol ← SwiftUI AccessibilityNode.resolvedRole` — while an
  accessibility client walks the tree, with no frame from GlassShell/GlassLayers/GlassTerminal in
  the faulting thread. I ran no macOS builds or tests; these coincide with another worker's macOS
  UI-test runs. Same signature five times, so it is reproducible there and worth a look by whoever
  owns the macOS runs (possibly an AX role lookup on a SwiftUI element from the terminal move).
