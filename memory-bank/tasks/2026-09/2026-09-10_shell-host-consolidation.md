# Shell: one row per host, every service's icon — and the visionOS row fix

Worker: shell-host-consolidation. 2026-09-10. **Status: built, unit-tested, visionOS row proven
on the simulator; iOS UI run in progress at report time (see Results). Not committed.**

## Root cause (evidence)

The user's iPhone showed `juliet / Terminal` and `juliet / Desktop` as two rows. The shared
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
  Pro's `oscar`, which shows as one host with two services, is a record that *was* paired there;
  the iPhone's `oscar` was not. Both shapes exist in real data.

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
| `swift test --build-system native --filter GlassShellTests` | **27 tests, 4 suites, passed** (9 new: same name different case; alias overlap; unrelated + loopback; already-single record untouched; preferences migrate; delete all members; add→canonical / remove→owner; picker + connect hands owning record; consolidateRecords) |
| visionOS Simulator (Vision Pro, OS 27.0), app seeded `juliet:ssh\|juliet:rdp\|oscar:rdp+ssh`, `simctl io screenshot` | `scratchpad/shots/vision-consolidated-row.png`: **two rows** (juliet, oscar), each "Desktop · Terminal" with two icons, an icon-only Connect and "Never" on one line; no wrapping |
| iOS Simulator UI suite `GlassShellLibraryUITests` (incl. the new case) | The UI test target in the working tree does not compile because of another worker's in-progress `UITests/GlassTerminalUITests.swift:291` (main-actor key path). Run from a verbatim copy of the tree without that file — result recorded in the report |
| macOS / iOS device rows | not run |
