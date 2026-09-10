# Stage 1 — integration, run, test, and security fixes

Worker: integration worker (fork of `/root`), 2026-09-10. Owned `App/`, `UITests/`; edited
`Sources/GlassShell` and `Sources/GlassLayers` only for the security-review fixes. No Git changes.
**Status: integrated; simulators and Mac verified; physical devices blocked on provisioning.**

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
| `swift test`, whole package, after fixes (§7) | GlassShellTests **15 passed** (1 suite + the new "security fixes" suite), GlassLayersTests **22 passed** (3 suites) — **37 total, 0 failed** |

## 4. Running — simulators and Mac

| Platform | Ran | Evidence |
|---|---|---|
| iOS Simulator | Yes; library renders the family scopes (All / Favorites / Recent, `+`, gear) | `scratchpad/shots/ios-library-empty.png` |
| visionOS Simulator | Yes; glass window with the scope ornament, "No Connections" sidebar, "Your Hosts" empty state with Add Host | `scratchpad/shots/vision-library-empty.png` |
| macOS | Yes, process runs from `dd-mac/Build/Products/Debug/GlassPowerTools.app`. **Sandboxed** (`com.apple.security.app-sandbox = true` in the signed entitlements), so the layers legacy bundle-domain suites are correctly skipped (F5). `screencapture` from the CLI was refused ("could not create image from display": no Screen Recording grant for the shell), so Mac screenshots come from the UI test runner (`mac-*.png`) instead | see §6 |

Only simulator log noise was observed (a GameController kext dlopen on iOS, RealityKit
profiling lines on visionOS); nothing from our process.

## 5. Physical devices and the 1.8 host-inheritance check

| Device | Result |
|---|---|
| iPhone 17 Pro Max (iOS 27.0) | **Build failed at provisioning**, not code: "No Accounts" from the CLI; the automatic "iOS Team Provisioning Profile: *" lacks App Groups, the `group.sh.glas.shared` group, iCloud, and this device. Stopped, per brief. |
| Vision Pro (visionOS 27.0) | Same provisioning failure, same profile. Stopped. |
| Mac | Runs. **The 1.8 check cannot be proven on this Mac**: `~/Library/Group Containers/group.sh.glas.shared/` exists but is **empty** — no `GlassHostCatalog/hosts.json` anywhere under `~/Library`, even though glas.sh (2026-09-05), glassdb (2026-09-04) and glassDT (2026-09-10) are installed with the App Group. None of the three has written a catalog on this machine. So the merged app correctly shows an empty library here, and "existing hosts appear" can only be demonstrated on the iPhone or Vision Pro once provisioning exists. The real container was read-only observed; nothing was written to it. |

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

UI_RESULTS_PLACEHOLDER

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
