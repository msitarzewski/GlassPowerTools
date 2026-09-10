# Stage 1 — `GlassShell` module

Owner: shell worker (fork of `/root`). Written 2026-09-10. Files: `Sources/GlassShell/`,
`Tests/GlassShellTests/`. Status: **built and unit-tested; not yet wired into an app target.**

## What was copied versus written

| From | Reused as |
|---|---|
| `../glassDT/Sources/GlassDesktopUI/DesktopAppModel.swift` | Shape of `GlassShellModel` (init parameters, `load`, `hasSharedContainer`/`hostLibraryStatus`, `errorMessage`), minus the local/shared dual catalog, `HostPublication`, deletion outbox, `pairService`/`unpair`, and the RDP-specific credential access |
| `../glassDT/Sources/GlassDesktopUI/DesktopLibraryView.swift` | Shape of `GlassShellLibraryView`: `GlassConnectionLibrary` call, toolbar actions, presentation anchor with alerts, context menu, `GlassLibraryDetail` sections. `pairedSection` and `PairServiceView` replaced by the Services section and `GlassShellServiceEditor` ("Add a service…"); `onOpenURL` / `GlassConnectionLink` routing removed |
| `../glas.sh/glas.sh/ConnectionLibrary.swift` | Scope semantics only; the kit already owns all/favorites/recent/collections. glas.sh's `workgroups` and `network` scopes are capability scopes and arrive in Stage 2 |
| `GlassConnectionUI` | Everything visual: library, row, detail, settings sections |

New: `GlassShellPreferences` + store, `GlassCapability` / `GlassCapabilityRegistry` /
`GlassServicePresentation`, `GlassShellPlaceholderRequest` / `GlassShellPlaceholderSession`,
`GlassShellConnectControl` (the service picker), `GlassShellHostEditor`, `GlassShellServiceEditor`,
`GlassShellSettingsView`.

## Gap 5 decision — where favorites, collections and last-used live

Evidence: `GlassLibraryProjection` derives collections from `GlassLibraryItem.tags` and states "a
projection never persists records"; `HostProfile` carries `tags` but no favorite, last-connected or
last-used field; each existing app keeps favorites on its own endpoint record.

Decision, implemented:
- **Collections = `HostProfile.tags`** in the shared catalog. Same derivation as every sibling, so
  a collection made here is visible to the family, and no schema change.
- **Favorites, `lastConnected`, last-used service, and the catalog `WriterID`** live in
  `<storageDirectory>/shell-preferences.json` (`GlassShellPreferences`, versioned, atomic,
  complete file protection). Per install, keyed by `HostID`. A schema change to the shared
  catalog would break the three apps' decoding; this avoids it.

## Public API as implemented

- `GlassShellModel(storageDirectory:sharedContainerURL:resolveSharedContainer:accessGroup:layers:registry:)`
  — `hosts`, `items`, `isLoaded`, `errorMessage`, `hasSharedContainer`, `hostLibraryStatus`,
  `preferencesProblem`, `placeholderRequest`, `catalog`, `catalogFileURL`, `writerID`, `layers`,
  `registry`, `secretConfiguration`; `load()`, `host(_:)`, `services(for:)`, `serviceKinds(for:)`,
  `isFavorite`, `lastConnected`, `lastUsedService(for:)`, `addHost`, `updateHost`, `deleteHost`,
  `addService(kind:displayName:to:)`, `removeService`, `toggleFavorite`, `connect(hostID:)`,
  `connect(hostID:endpointID:)`.
- `GlassCapability` (protocol), `GlassCapabilityRegistry`, `GlassServicePresentation`.
- Views: `GlassShellLibraryView(model:)`, `GlassShellSettingsView(model:)`,
  `GlassShellConnectControl(model:hostID:prominent:)`, `GlassShellHostEditor`,
  `GlassShellServiceEditor`, `GlassShellPlaceholderSession`.
- `GlassShellSettingsPage { general, appearance, privacy, about }`.

Catalog path: `<App Group container>/GlassHostCatalog/hosts.json`, same file the three apps use.
`SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup:, useDataProtectionKeychain: true,
mobilityPolicy: .deviceOnly)` is built at init; no secret is read in Stage 1.

## Accessibility identifiers

`connection-library-add-host`, `connection-library-add-host-empty`, `connection-library-settings`
(non-Mac), `host-row-<name>`, `host-service-<kind>`, `host-connect`, `host-connect-menu` (Mac),
`host-connect-menu-<kind>`, `host-service-connect-<kind>`, `host-add-service`, `host-favorite`,
`host-edit`, `host-delete`, `host-delete-confirm`, `host-editor-*`, `service-editor-*`,
`settings-sections`, `settings-done`, `placeholder-session`, `placeholder-done`.

**Not achievable from outside the kit:** `connection-library-search`. `GlassLibraryResults` owns
`.searchable` with prompt "Search connections..."; UI tests should target that placeholder, or the
kit gains an identifier parameter later.

## Tests — `swift test --filter GlassShellTests`

10 tests, 1 suite, passed (0.04 s), all against temporary directories: existing sibling-written
catalog is read in place; projection determinism and tag→collection derivation; add/remove service
persists through relaunch; connect chooses sole → last-used → first and falls back after removal;
registered capability receives `open` instead of the placeholder; preferences round trip including
`WriterID` stability; corrupt preferences reported; unavailable container gives the honest status
and a local catalog; delete tombstones and clears preferences; name validation.

`swift build` (macOS host) passes. `xcodebuild -scheme GlassShell` for `generic/platform=iOS Simulator` and `generic/platform=visionOS Simulator`: BUILD SUCCEEDED, re-run against the real GlassLayers.

## GlassLayers integration — done

The real `GlassLayers` module landed mid-task. The temporary stub was deleted, the three views and
the model import `GlassLayers`, and the build and all 10 tests pass against the real
`GlassLayerStore`, `GlassLayeredWindow { }`, `GlassLayeredPanel { }` and `GlassLayerControls()`.
About now shows `GlassLayerStore.migrationSource`.

## Integration notes for the app entry point

```swift
@State private var layers = GlassLayerStore()            // from GlassLayers
@State private var model: GlassShellModel                 // init in App.init:
//   accessGroup from Info.plist "GlasKeychainAccessGroup" (skip if it still contains "$("),
//   `--ui-testing <uuid>` → storageDirectory + sharedContainerURL under a temp dir with
//   resolveSharedContainer: false, exactly as glassDT does.
WindowGroup("Connections", id: "main") { GlassShellLibraryView(model: model) }
#if os(macOS)
Settings { GlassShellSettingsView(model: model) }
#else
Window("Settings", id: "settings") { NavigationStack { GlassShellSettingsView(model: model) } }
#endif
```
Capabilities register with `model.registry.register(_:)` and declare their own `WindowGroup`s.

## Open items

- `GlassShellSettingsView.general` is minimal (library status, host count, preferences problem).
- The visionOS `TabView` path of `GlassConnectionLibrary` renders the detail per tab; the
  `GlassLayeredPanel` wrap applies inside each. Verified by compile only.
