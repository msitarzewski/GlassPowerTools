# Stage 1 — the shell: one target, layers, host library, service picker

Owner `/root`. Planned 2026-09-10. **Status: planned, not started.** Every claim below about
existing code was read from the working checkouts on 2026-09-10; nothing about Glass Power Tools
itself exists yet.

## Task

- **Objective:** an application that builds and runs on Mac, iPad, iPhone and Vision Pro, lists
  every host in the shared catalog with an icon per service, offers Connect with a service picker,
  has one settings surface and one layering system proven on the connection detail view — and can
  connect to nothing.
- **Scope and authorization:** the plan is authorized and written. **Creating project files is
  not yet authorized**; it begins on the user's word. Three pre-steps below need the user's
  explicit instruction because they touch sibling repositories.
- **Owner and affected files:** this repository only. Siblings are read, not
  edited, with the pre-steps as the sole exceptions and only when instructed.
- **Acceptance:** the exit criteria at the end, each with evidence.

## Decisions already taken that shape this stage

From [decisions](../../decisions.md): one multiplatform target, hand-maintained project with
synchronized folders, 26.0 floor on `arm64`, layering foundational, visionOS leads, editor library
in from the start, existing App Group and Keychain group declared.

## Pre-steps that need the user's instruction

None of these is done by an agent on its own initiative.

| # | Action | Why | Rule it touches |
|---|---|---|---|
| P1 | Commit the GlasSecretStore working tree (12 files, incl. untracked `RDPCredentialStore.swift`) on its current branch or a new one | It is the only copy of the RDP credential store and the synchronizable-Keychain work; Stage 1 builds against it by local path; unrecoverable if lost | Never commit without instruction |
| P2 | Put `../GlassConnectionKit` under version control | The most-consumed package in the family is a plain directory; Stage 1 consumes it by local path | Never `git init` as an incidental task |
| P3 | Confirm GlasSecretStore and GlassConnectionKit test suites pass as they stand (`swift test` in each sibling; 90 and 38 tests per their notes) | Stage 1's credential and catalog behaviour is only as proven as the packages it consumes | Runs a build in a sibling; writes `.build` there |

P1 and P2 change nothing about the plan if declined; they change the recovery story. P3 is QA and
should simply be run first.

## Reuse: what exists, what Stage 1 consumes, what it must add

**Consumed unchanged, by local path, one copy each:**

| Package | Products used in Stage 1 | Evidence |
|---|---|---|
| `../GlassConnectionKit` | `GlassConnectionKit` (model, projection), `GlassConnectionUI` (library, frame, backdrop, chrome, settings shell, slider), `GlassHostCatalog` (`HostCatalogStore`) | `Package.swift`: three products, floors 26, Swift 6 |
| `../GlasSecretStore` | `GlasSecretStore` — `SecretStoreConfiguration`, `SecretAccessPolicy`, `SecretMobilityPolicy`, the SSH key and host-trust stores, `RDPCredentialStore` | working tree, see [technical context](../../techContext.md) |
| `../GlassEditorKit` | `GlassEditorCore` linked to prove the graph on all three platforms; `GlassEditorUI` waits for Stage 5 | `Package.swift`: products `GlassEditorKit`, `GlassEditorCore` |

**The shared surfaces Stage 1 builds on, with the parameters the shell must supply:**

- `GlassConnectionLibrary(items:selection:scope:searchText:order:columnAutosaveName:onActivate:row:detail:)`
  over `GlassLibraryItem<ID> { id, name, subtitle, searchTerms, tags, isFavorite, lastConnected,
  dateAdded, sortKeys }` — `GlassConnectionUI/GlassConnectionLibrary.swift`,
  `GlassConnectionKit/GlassLibraryProjection.swift`.
- `GlassLibraryConnectionRow(name:subtitle:isFavorite:favoriteSymbol:color:lastConnected:accessory:)`
  — the `accessory` slot is where the service icons and Connect control go.
- `GlassLibraryDetail(title:content:actions:)` — the detail view the layering system is proven on.
- `GlassNativeWindowFrame(showTitle:showControls:content:title:controls:)`,
  `GlassCanvasBackdrop(material:blurAmount:interactive:colorScheme:)`,
  `GlassWindowChrome.installTitlebarMaterial(in: NSWindow, materialStyle:)` (macOS titlebar
  material), `GlassTitlebarMaterialView`, `GlassSettingSlider(title:value:range:detents:…)`.
- `GlassSettingsSections(selection:options:title:pickerIdentifier:content:)` — the settings shell;
  glassDT's pages are `general, appearance, privacy, about`
  (`DesktopSettingsView.swift:148`).
- `HostProfile { id, displayName, aliases, services: [HostServiceLink], tags, … }`,
  `HostServiceLink { endpointID, kind, displayName, credentialID? }`,
  `HostServiceKind { rdp, ssh, database }` — `GlassConnectionKit/HostProfile.swift`.
- `HostCatalogStore(fileURL:writerID:)` with `snapshot`, `upsert`, `delete`, `pair`, `unpair`.

**Present in the packages but deliberately unused by this app** (they exist only to keep three
processes agreeing, and stay in the package until Stage 6 because the three apps still consume it):
`GlassConnectionLink`, `EndpointAppVisibility`, `HostPublication`, `HostCatalogDeletionOutbox`,
glassDT's dual local/shared catalog and its `pairedSection` (`DesktopLibraryView.swift:291-300`),
glassdb's `publishFamilyHosts`.

**The gaps — what Stage 1 must write:**

1. A shell composition root, following glassDT's thin pattern (`App/glassDTApp.swift`: an app
   model in `@State`, Keychain access group read from Info.plist, `--ui-testing <uuid>` for isolated
   storage, `Settings` on macOS, a library `WindowGroup`, capability windows registered separately).
2. A host-library adapter projecting `HostProfile` → `GlassLibraryItem<HostID>`; the three existing
   adapters (`glas.sh/ConnectionLibrary.swift`, `glassdb/ConnectionManagerView.swift`,
   `glassDT/DesktopLibraryView.swift`) each project their own endpoint type, so none is reusable
   as-is, but their scope/mode/collection handling is the family behaviour to preserve.
3. The service picker.
4. One layering state model.
5. Shell-owned preferences: favorites, collections and last-used service **per host**. The
   catalog schema has no last-used field and `isFavorite` is projected from each app's own store
   today. **Verify on first build where `GlassLibraryProjection` collections persist** before
   deciding whether the shell stores these beside the catalog or inside it.

## Work breakdown

### 1.1 Project skeleton — copy glas.sh's shape

- `GlassPowerTools.xcodeproj`, hand-maintained. One app target, `com.glasspowertools`,
  `SDKROOT = auto`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`,
  `ARCHS = arm64`, all three deployment targets 26.0, Swift 6 language mode, strict concurrency.
- Synchronized folders for every source group: `GlassPowerTools/` (app), `Platforms/macOS/`
  (overlay), `GlassPowerToolsTests/`, `GlassPowerToolsUITests/`. No explicit file references.
- `Platforms/macOS/` carries `macOS.entitlements`, `Info.plist`, `Assets.xcassets`,
  `AppIcon.icon`, applied with `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`,
  `INFOPLIST_FILE[sdk=macosx*]`, and `platformFilter = macos` on the assets — exactly as
  `glas.sh.xcodeproj` does.
- Entitlements on every platform: `com.apple.security.application-groups: [group.sh.glas.shared]`,
  `keychain-access-groups: [$(AppIdentifierPrefix)sh.glas.shared]`. macOS adds the sandbox,
  network client and user-selected read-only keys glassDT uses. **iCloud KVS identifier: decision
  D3 below.**
- Info.plist keys from glas.sh: `GlasKeychainAccessGroup`, `NSFaceIDUsageDescription`,
  `NSLocalNetworkUsageDescription`, scene manifest with multiple scenes. **No URL schemes**
  (`glassh`, `glassdb`, `glassdt` were cross-app routing; decision D4).
- Widget extension: **not in Stage 1.** `glasWidgets` renders server health written by glas.sh
  into the App Group defaults; it arrives with the SSH capability in Stage 2.

### 1.2 Package graph

Local path references `../GlassConnectionKit`, `../GlasSecretStore`, `../GlassEditorKit`. A root
`Package.swift` in this repository declares the shell modules (as glassDT does), so the app target
links products, not folders.

### 1.3 Shell modules

| Module | Owns | Tests |
|---|---|---|
| `GlassShell` | App model; `HostCatalogStore` at `<App Group>/GlassHostCatalog/hosts.json` with this app's `WriterID`; credential boundary via `SecretStoreConfiguration` for the shared access group; scene registry that capabilities add windows to; settings shell with `general`, `appearance`, `privacy`, `about`; shell preferences (favorites, collections, last-used service) | Projection determinism, last-used selection, preference persistence, catalog round trip against a temp file |
| `GlassLayers` | One state model — opacity, blur/frost, material, whether the theme paints — persisted once; SwiftUI environment injection; bridges to `GlassNativeWindowFrame`, `GlassCanvasBackdrop`, `GlassWindowChrome.installTitlebarMaterial` and the title bar on all platforms; `GlassSettingSlider`-based controls | State persistence and migration from the three legacy key sets (`windowOpacity`/`blurBackground`/`glassFrost`, `display.glass.opacity`/`frost`) so a user's current setting survives |
| App target | Entry point, scenes, platform overlay, assets | UI tests |

Rules: `GlassShell` depends on the three packages and `GlassLayers`; nothing depends on the app
target; no capability exists yet to depend on anything.

### 1.4 Scenes

Library window with id `"main"` (glas.sh's id, kept so muscle memory and future window recovery
carry over; `glas_shApp.swift:99,158`). `Settings` scene on macOS; a `Window("Settings",
id: "settings")` on iOS and visionOS as glas.sh does (`:258`). A registry so Stage 2 can add
`WindowGroup(id:for:)` scenes without editing the shell. Window recovery
(`WindowRecoveryManager`) and iCloud settings sync (`ICloudSettingsSyncService`) are glas.sh
shell services that move in Stage 2 with its settings.

### 1.5 Host library

- Items: every non-deleted `HostProfile` from `snapshot()`, name from `displayName`, subtitle
  from the service kinds present, search terms from aliases and tags, favorites and
  `lastConnected` from shell preferences.
- Row accessory: one SF Symbol per `HostServiceKind` present (`terminal` for ssh,
  `externaldrive` for database as glassDT uses; rdp gets its own), then the Connect control.
- Detail: `GlassLibraryDetail` with the host's services listed, an **"Add a service…"** action in
  place of "Paired Services", and per-service actions. Adding a service in Stage 1 creates a
  `HostServiceLink` with a kind and a display name and nothing behind it; the capability that owns
  the endpoint record fills it in later.
- Family behaviour preserved from all three adapters: scope switching (`glass-library-scope-*`
  identifiers are set by the kit), search, collections, favorites, selection restoration, compact
  adaptation on iPhone, the column autosave name on Mac.

### 1.6 Service picker

- Connect opens the last-used service for the host; a host with one service behaves as today.
- More than one service: a chevron `Menu` beside Connect on Mac; press-and-hold on iOS and
  visionOS. Both list the services with their icons.
- In Stage 1 "opening" a service records it as last-used and shows an honest placeholder stating
  that the capability is not yet present. No fake session.

### 1.7 Layers — proven on the detail view

The detail view, the library window frame and its title bar all draw from `GlassLayers` state.
Changing opacity or frost in Settings → Appearance changes them live on every platform, including
the macOS title bar material. This is the Stage 1 proof; the SSH connection panel is the Stage 2
proof. **Default values: decision D2.**

### 1.8 First build check — existing hosts appear

Run on the Mac, the iPhone 17 Pro Max and the Vision Pro. The library must list the hosts that
glas.sh, glassdb and glassDT already show, from the same `hosts.json`, without any migration. If
they do not appear, the App Group entitlement or signing is wrong, and that is fixed before
anything else.

## Validation

| Check | How | Claim it supports |
|---|---|---|
| Sibling packages green | P3: `swift test` in `../GlasSecretStore` and `../GlassConnectionKit` | The consumed code is what its notes say |
| Builds | Debug build for macOS, iOS Simulator, visionOS Simulator | Graph resolves; 26.0 floor holds |
| Runs | Install on Mac, iPhone, Vision Pro | Not simulator-only |
| Hosts in place | Existing hosts listed on all three devices | App Group inheritance, no migration |
| Shell unit tests | Projection, last-used, preferences, layer state and legacy-key migration | Deterministic behaviour |
| UI tests | Port the library lifecycle, search, collections and favorites test from `glas.sh/glas.shUITests/ConnectionLibraryUITests.swift` (1,457 lines) and glassDT's `LibraryWorkflowTests.swift`, keeping the `connection-library-search`, `connection-library-settings` and `connection-library-add-server-*` identifiers so later capability tests port unchanged | Same navigation and actions across consumers |
| Layers | Screenshot the detail view at three opacity settings on each platform; confirm the macOS title bar changes | Layering is one system |
| Accessibility | VoiceOver pass on the library and service picker on iOS and visionOS | Family UI rule |

Not run means not run. A simulator build is not a device result.

## Decisions for the user, in order of when they block

| # | Decision | Blocks | Proposal |
|---|---|---|---|
| D1 | P1–P3 above | 1.2 | Do all three |
| D2 | Layer defaults, visionOS-first: glas.sh ships fully transparent (`0.0`), glassdb `0.95`, glassDT `1.0` with frost `0.25` | 1.7 | Adopt glas.sh's transparent default with frost on, migrate each legacy key set so nobody's current look changes |
| D3 | iCloud KVS identifier: reuse `$(TeamIdentifierPrefix)sh.glas.app` and inherit glas.sh's synced settings, or start clean | 1.1 | Reuse; it is free and Stage 2 merges those settings anyway |
| D4 | URL schemes: drop `glassh`/`glassdb`/`glassdt`, or accept them so old links still open | 1.1 | Drop; they existed for cross-app routing and nothing else produces them |
| D5 | Display name and product name for the app bundle | 1.1 | "Glass Power Tools" |
| D6 | Whether `GlassEditorUI` links in Stage 1 or waits for Stage 5 | 1.2 | Wait; linking without use proves nothing |

## Risks specific to this stage

| Risk | Response |
|---|---|
| Building against an uncommitted GlasSecretStore tree | P1 |
| GlassConnectionKit unversioned | P2 |
| Favorites and collections have no obvious owner once endpoints live in capabilities | Verify persistence on first build (gap 5) before designing shell preferences |
| Existing hosts do not appear on a device | Stop and fix signing or entitlements before any UI work |
| The shell grows capability assumptions because there is no capability to push back | Keep 1.5–1.7 honest: placeholders say so, nothing simulates a session |
| The three legacy layer key sets are migrated wrongly and a user's look changes | Migration tests per key set, with the three defaults as fixtures |

## Follow-ups found while testing (not Stage 1 blockers)

- **visionOS search is not reachable by accessibility.** `GlassConnectionUI`'s `.searchable` on
  the visionOS `TabView` navigation exposes no search-field element, so `testSearchFiltersRows` is
  skipped there with a stated reason (verified on iOS and macOS). This is a kit-level VoiceOver gap
  on the platform that leads the design; fix in `../GlassConnectionKit` when the kit is next opened
  for changes, and un-skip the test.
- **visionOS in-test screenshots are 1×1** (XCUIScreen on the visionOS simulator). Visual evidence
  on visionOS is taken with `simctl io screenshot` outside the test.
- **Slider drags cannot be synthesized** on the visionOS simulator or macOS; the Appearance
  persistence test uses the theme toggle everywhere and the slider on iOS only.

## Exit criteria

1. Builds and runs on Mac, iPhone and Vision Pro from one target.
2. Lists the existing hosts with an icon per service; Connect and the picker behave per 1.6.
3. "Add a service…" exists and "Paired Services" does not.
4. One settings surface; changing Appearance changes the detail view and title bar live.
5. Shell unit tests and the ported library UI tests pass, on device where they can.
6. The task note records what was actually moved from `GlassConnectionUI` and `GlassDesktopUI`
   versus newly written, and which decisions D1–D6 were taken.

## Current state and next action

Planned. Awaiting the user's word to create the project, and decisions D1–D6 (each has a
proposal; D1 needs explicit instruction because it is Git work in sibling repositories).
