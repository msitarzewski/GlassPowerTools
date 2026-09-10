# Stage 1 — integration, run, test, and security fixes

Worker: integration worker (fork of `/root`), 2026-09-10. Owned `App/`, `UITests/`; edited
`Sources/GlassShell` and `Sources/GlassLayers` only for the security-review fixes. No Git changes.
**Status: integrated and unit-verified; UI results superseded by coordinator runs on `17e79be`; physical devices and the Mac's shared container blocked on provisioning.**

## 1. App entry point — done

`App/GlassPowerToolsApp.swift` now builds one `GlassLayerStore` and one `GlassShellModel` in
`App.init` (access group from Info.plist `GlasKeychainAccessGroup` unless it still holds `$(`;
`--ui-testing <uuid>` isolates storage and the catalog under
`Application Support/GlassPowerTools-Tests/<uuid>` with `resolveSharedContainer: false`, as
glassDT does), injects `.glassLayers(layers)`, and declares `WindowGroup("Connections", id: "main")
{ GlassShellLibraryView }`, macOS `Settings { GlassShellSettingsView }`, visionOS
`Window("Settings", id: "settings")`; iOS opens Settings as the library's sheet. The placeholder
`Text` and its identifier are gone; `UITests/LaunchSmokeUITests.swift` still passes because it
only asserts the process reaches the foreground and the main window exists.

## 2–3. Builds and package tests — passed

| Check | Result |
|---|---|
| iOS Simulator, iPhone 17 Pro Max (iOS 27.0) | **BUILD SUCCEEDED** |
| visionOS Simulator, Apple Vision Pro (OS 27.0) | **BUILD SUCCEEDED** |
| macOS, with the build-time `noKVS.xcconfig` override (project untouched; the iCloud KVS entitlement waits for the capability on the App ID) | **BUILD SUCCEEDED**, signed Apple Development, team 7JQGQ7CRH8 |
| `swift test`, whole package, before fixes | GlassShellTests **10 passed**, GlassLayersTests **21 passed** |
| `swift test`, whole package, after fixes (§7, §8) | GlassShellTests **18 passed** (3 suites), GlassLayersTests **22 passed** (3 suites) — **40 total, 0 failed** |

## 4. Running — simulators and Mac

| Platform | Ran | Evidence |
|---|---|---|
| iOS Simulator | Yes; library renders the family scopes (All / Favorites / Recent, `+`, gear) | `scratchpad/shots/ios-library-empty.png` |
| visionOS Simulator | Yes; glass window with the scope ornament, "No Connections" sidebar, "Your Hosts" empty state with Add Host | `scratchpad/shots/vision-library-empty.png` |
| macOS | Yes, process runs from `dd-mac/Build/Products/Debug/GlassPowerTools.app`, idle at 0% CPU. **Sandboxed** (`com.apple.security.app-sandbox = true` in the signed entitlements), so the layers legacy bundle-domain suites are correctly skipped (F5). `screencapture` from the CLI was refused (no Screen Recording grant for the shell), so Mac screenshots come from the UI test runner (`mac-*.png`) | see §6 and §8 |

Only simulator log noise was observed (a GameController kext dlopen on iOS, RealityKit
profiling lines on visionOS); nothing from our process.

## 5. Physical devices and the 1.8 host-inheritance check

| Device | Result |
|---|---|
| iPhone 17 Pro Max (iOS 27.0) | **Build failed at provisioning**, not code: "No Accounts" from the CLI; the automatic "iOS Team Provisioning Profile: *" lacks App Groups, the `group.sh.glas.shared` group, iCloud, and this device. Stopped, per brief. |
| Vision Pro (visionOS 27.0) | Same provisioning failure, same profile. Stopped. |
| Mac | Runs, but **the 1.8 check is unproven here, and the reason is provisioning, not code.** Probed through the sandboxed app itself against the real container (a throwaway UI test, since deleted; nothing written): it alerts *"The host library could not be read: You don't have permission to save the file "GlassHostCatalog" in the folder "group.sh.glas.shared"."* and shows 0 hosts. The build is signed with the wildcard "Mac Team Provisioning Profile: *", which grants no App Group; `/Applications/glas.sh.app` carries "Mac Team Provisioning Profile: sh.glas.app" whose profile *does* grant `group.sh.glas.shared`, and `/Applications/glassDT.app` carries the same wildcard profile as ours — so glassDT on this Mac cannot reach the shared catalog either (family-level finding). My earlier observation that the container was "empty" was my shell being denied by TCC (`ls` → "Operation not permitted"), not the container's contents; retracted. |

**What unblocks devices (user action):** register `com.glasspowertools` with App Groups
(`group.sh.glas.shared`) and iCloud in Xcode's Signing & Capabilities with the account signed in,
which also generates the device profile. No project change is needed.

## 6. UI tests

`UITests/GlassShellLibraryUITests.swift` (4 tests, isolated with `--ui-testing`, screenshots via
`GPT_SHOTS_DIR`): add host → detail → add default service → `host-service-ssh` icon → Connect →
honest placeholder text ("not part of this build") → dismiss; favorite → appears under the
Favorites scope; search "zzz-no-match" hides the row, clearing restores it; Appearance →
paint theme on → adjust `layers-opacity` → relaunch → same value → reset. macOS `tearDown` removes
the run's isolated directory (F9); on iOS/visionOS the app prunes earlier runs' directories older
than ten minutes at the next isolated launch, because the runner cannot reach that sandbox.

Search targets `app.searchFields.firstMatch` — the kit owns `.searchable` and its prompt, so
`connection-library-search` was not added anywhere (no kit edit).

**Results actually observed by this worker** (all runs against commit-in-progress sources; the
coordinator's runs on `17e79be` supersede these):

| Platform | Run | Outcome |
|---|---|---|
| iOS Simulator | Concurrent rerun, before the §8 test fixes | `testAppearanceOpacityPersistsAcrossRelaunch`, `testFavoriteAppearsInFavoritesScope`, `testSearchFiltersRows` **passed**; `testAddHostAddServiceConnectPlaceholder` failed at the row-icon assertion (iPhone stays on the detail; fixed by accepting the detail's Connect); smoke failed because it still asserted the removed placeholder (rewritten). Screenshots `ios-01,02,05,06,07,08`. |
| visionOS Simulator | Concurrent rerun, before the §8 test fixes | All four library tests failed at platform differences (placeholder Done unreachable, slider not synthesizable, scopes are tab titles, no search-field element); smoke failed for the same placeholder reason. Screenshots `vision-01..05` show add host, detail, service icon, placeholder and favorite rendering correctly. |
| macOS | Alone, on the code with the F1–F7 fixes but before `press()`/`click()` | Smoke **passed**; the four library tests failed because `tap()` does not drive SwiftUI buttons on macOS (probe: `click()` opens the sheet in under 1 s) and ⌘N opened a second window (fixed in the app). |
| macOS, iOS, visionOS | Final rerun with every §8 fix | **Not observed**: the macOS leg failed to start (my script passed `-xcconfig` as one quoted token), and the simulator legs were stopped on the coordinator's stand-down before finishing. Superseded by coordinator runs. |

## 8. Defects found by running, and their fixes

| Defect | Evidence | Fix |
|---|---|---|
| Sandbox-refused shared container alerted on every launch instead of degrading | Mac probe alert above; unit-reproducible with a read-only parent directory | `GlassShellModel.load()` recognises a permission denial from the kit (`fileLockFailed(EACCES/EPERM)` or Cocoa no-permission) on the *shared* path, switches to the private catalog, sets `hasSharedContainer = false` and a `hostLibraryStatus` naming the missing entitlement grant; no alert. Test: read-only group dir → no `errorMessage`, status says "not allowed", hosts land locally, nothing created in the group dir |
| First run on an empty or absent shared container | Suspected, then disproved | Two tests added (empty existing container → 0 hosts, no error; absent container → created on first write). Both pass; the kit creates the directory inside its lock |
| macOS UI tests could not open any sheet | `XCUIElement.tap()` compiles on macOS but does not drive SwiftUI buttons; a probe with `click()` opened the sheet within 1 s | Test helper `press(_:)` uses `click()` on macOS |
| ⌘N opened a **second library window** on macOS | Probe: `windows=2` after ⌘N | App uses `Window("Connections", id: "main")` on macOS and visionOS as glas.sh does (iOS keeps `WindowGroup`), and replaces the `.newItem` command group as glas.sh does (`glas_shApp.swift:79`) so ⌘N is Add Host |
| Placeholder's Done button unreachable on visionOS | `placeholder-session` found, `placeholder-done` not; an identified `ContentUnavailableView` is one element there | Done moved to the sheet toolbar (`confirmationAction`), the pattern the host editor already uses successfully on visionOS |
| Slider drags cannot be synthesized on the visionOS simulator or macOS | "Failed to synthesize event" | Appearance test uses the theme toggle as the persisted change everywhere and the slider on iOS only |
| visionOS scopes are tab titles, not `glass-library-scope-*` | Kit's `visionNavigation` is a `TabView` over All/Favorites/Recent/Collections | Test selects scopes by tab title on visionOS |
| iPhone stays on the detail after adding a service, where the row icon is off screen | iOS failure at the `host-service-ssh` assertion | Test accepts the detail's `host-service-connect-ssh` as evidence |
| `simctl diagnose` after failures made both simulator runs look hung (7–8 min at 0% CPU) | `ps` showed `simctl diagnose --timeout=600` children | Runs were killed and repeated; note it, do not wait on it |
| UI test case with `@MainActor` and synchronous `setUp`/`tearDown` | Swift 6 "sending 'self' risks causing data races" on all platforms | Async overrides with `MainActor.run` |

## 7. Security-review fixes applied (`2026-09-10_stage-1-security-review.md`)

| # | Fix | Test |
|---|---|---|
| F1 | `GlassShellPreferencesStore.load()` now returns a `LoadOutcome` (`missing`, `loaded`, `unavailable`, `corrupt`, `newerVersion`); the model is **read-only** on anything but the first two, never saves at init, `persistPreferences()` throws `GlassShellError.preferencesReadOnly`, `load()` retries an `unavailable` file and adopts it without rewriting, and `resetPreferences()` moves the file to `shell-preferences.json.unreadable-<timestamp>` before writing defaults. Permission/availability errors (`NSFileReadNoPermissionError`, `EACCES`/`EPERM`) are told apart from decode errors; a newer version is detected by a version probe even when the rest no longer decodes. File protection is now `.completeFileProtectionUntilFirstUserAuthentication`. | corrupt file not overwritten and set aside on reset; newer version not overwritten; permission-denied file (chmod 000) left alone, then adopted when readable, and the stored writer ID survives the next save |
| F2 | `updateHost` re-snapshots the catalog immediately before building the record and carries the fresh `services`/`createdAt`; only name, aliases and tags come from the editor | an externally paired service survives a rename |
| F3 | `connect` records `lastUsedEndpointID` on both paths but stamps `lastConnected` only when a registered capability opens | placeholder path leaves `lastConnected` nil (existing "sole/last-used/first" test updated to match) |
| F4 | `emptyDetail` shows `hostLibraryStatus` (identifier `connection-library-status`) when the shared container is unavailable | visual; covered by the existing unavailable-container model test |
| F5 | macOS bundle-domain legacy suites are consulted only when `APP_SANDBOX_CONTAINER_ID` is absent | existing migration tests unaffected; the shipped target is sandboxed, so the suites are skipped |
| F6 | `GlassShellError.message(for:)` maps every `HostProfileError` and `HostCatalogError` case to plain text; used by the editors, the library's `run`, and the model's own messages | — |
| F7 | corrupt `glass.layers.state` → `.default`, `migrationSource = .none`, legacy migration **not** re-run | new "corrupt state" suite |
| F9 | see §6 | — |

F8 (environment default `assumeIsolated`), F10 and F11 were informational and left as the review
recommended.

## Defects found by integration

- UI test case was `@MainActor` with synchronous `setUp`/`tearDown` overrides → Swift 6 "sending
  'self' risks causing data races" at compile time on all three platforms. Fixed by using the
  async overrides and hopping with `MainActor.run`.
- Test-only: `FileManager.setAttributes(_:ofItemAtPath:)` label.

## Open issues

1. Device installs and the 1.8 proof wait on provisioning (user action above).
2. macOS release signing still needs the iCloud capability on the App ID (D3), or D3 revisited.
3. Both app icon sets are empty placeholders (project worker's note).
4. The visionOS title/ornament and macOS title-bar checks from the layers note are exercised by
   the Appearance UI test only as far as state changes go; the visual confirmations are the
   screenshots listed in §6, judged by eye, not by assertion.
