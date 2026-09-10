# Stage 1 security review

Reviewer `/root` fork `stage1-security`, 2026-09-10. **Read-only.** Reviewed commit `c722a90`
(`Sources/GlassShell`, `Sources/GlassLayers`, `App/`, `Platforms/macOS/`, `Package.swift`) plus
the consumed kit code they call. Every line cited was read; "Confirmed" means the path was traced in
code, "Plausible" means the trigger is reasoned, not reproduced. No code was edited.

Checks run: `swift build` → **0 warnings** in `Sources/GlassShell`, `Sources/GlassLayers`, `App/`.
`grep -rnE "TODO|FIXME|fatalError|try!|as!|unsafe" Sources App` → **no hits**.
`grep -rnE "print\(|Logger\(|os_log|NSLog" Sources App` → **no logging at all** in Stage 1 code.

## Findings

| # | Sev | Where | What | Why it matters | Suggested fix |
|---|---|---|---|---|---|
| F1 | **High** · Confirmed path, Plausible trigger | `Sources/GlassShell/GlassShellModel.swift:87`, `GlassShellPreferences.swift:44-50,58` | On any preferences decode failure — or a file written by a **newer** version — the model immediately overwrites `shell-preferences.json` with fresh defaults (`try? preferencesStore.save(loaded.preferences)`), including a **new `WriterID`**. The file is written with `.completeFileProtection` (`:58`), so on iOS a launch before first unlock (prewarming, background scene restoration) makes the read fail with a permission error, which is treated as corruption. The save fails silently while locked (`try?`), and the next `persistPreferences()` after unlock writes defaults-plus-one-change over the user's real favorites and last-used services. A newer-version file is likewise destroyed on downgrade. | Silent, permanent loss of user preferences and churn of the catalog writer identity, from a routine iOS launch. Contradicts the store's own comment ("reports it rather than silently discarding"). | Never overwrite on load failure. Keep defaults in memory, mark the store read-only until the user resets, and move the unreadable file aside (`shell-preferences.json.unreadable-<timestamp>`) before the first later save. Distinguish `NSFileReadNoPermissionError`/`EACCES` from decode errors. Use `.completeUntilFirstUserAuthentication` for this file — it holds no secrets and is read at launch. Refuse to write when `version > currentVersion`. |
| F2 | **Medium** · Confirmed | `Sources/GlassShell/GlassShellModel.swift:146-154` with kit `HostCatalogStore.swift:50-64` | `updateHost` rebuilds the whole `HostProfile` from the model's in-memory copy — including `services: existing.services` — and `upsert` replaces the record wholesale inside the lock. Services paired or published by glas.sh/glassdb/glassDT between this app's last `load()` and the user's Save are dropped from `hosts.json`. | Cross-process clobber of another app's service links, the one thing the family's lock-and-reload design exists to prevent. The model reloads on scene-active, so the window is small but real. | Add a field-level edit in the kit — `HostCatalogStore.update(hostID:) { inout HostProfile }` or `rename(hostID:displayName:aliases:tags:)` via the existing private `mutate` — and call that. Until the kit changes, the shell can at least re-`snapshot()` immediately before building `updated` and carry the fresh `services`. |
| F3 | **Medium** · Confirmed | `Sources/GlassShell/GlassShellModel.swift:208-215`; shown at `GlassShellLibraryView.swift:135` | `connect(hostID:endpointID:)` stamps `lastConnected = Date()` **before** deciding whether a capability exists. With the Stage 1 empty registry every Connect goes to the honest placeholder yet the host detail then says "Last connected: 2 minutes ago" and the row sorts as recently used. | Simulated state: the product rule is that nothing presents as connected when nothing connected. Recording `lastUsedEndpointID` is fine — the user chose it. | Set `lastConnected` only on the capability path (or have the capability report success). Keep `lastUsedEndpointID` as is. |
| F4 | Low · Confirmed | `Sources/GlassShell/GlassShellLibraryView.swift:96-105` | When the App Group container is unavailable the model falls back to a private catalog and sets `hostLibraryStatus` (`GlassShellModel.swift:83`), but the empty library shows only "Your Hosts / Every machine you own…". The status appears in Settings › General and in a host's detail — and with a broken entitlement there are no hosts to select. | A signing or entitlement fault looks like an empty library; the user has no cue that their hosts exist elsewhere. Not silent in code, silent in the UI that matters. | Show `hostLibraryStatus` in `emptyDetail` when `!model.hasSharedContainer`. |
| F5 | Low · Confirmed | `Sources/GlassLayers/GlassLayerStore.swift:46-55`, `GlassLayerLegacy.swift:48`; `Platforms/macOS/macOS.entitlements` (sandbox on) | On macOS the store reads `UserDefaults(suiteName:)` for `sh.glas.app`, `app.glassdb`, `app.glassdt`. The shipped Mac target is sandboxed, so these reads are denied: dead code that emits sandbox-violation log lines on every fresh launch. | Console noise that looks like an attempted cross-app read; misleading during later security triage. Same-developer data, so not a privacy issue. | Drop the bundle-domain suites, or gate them on `!ProcessInfo.processInfo.environment.keys.contains("APP_SANDBOX_CONTAINER_ID")`. |
| F6 | Low · Confirmed | Kit `HostCatalogError` (`HostCatalogStore.swift:16`), `HostProfileError` (`HostProfile.swift:39`) surfaced by `GlassShellLibraryView.swift:168-174` and the editors | Neither enum adopts `LocalizedError`, so an over-long name (>1024 bytes), 65th alias or duplicate endpoint reaches the user as "The operation couldn't be completed. (GlassHostCatalog.HostCatalogError error 5.)". | Validation is correct (the kit bounds every field) but the user cannot tell what was rejected. UX, not exposure. | Map kit errors to `GlassShellError` cases with text, in the shell. |
| F7 | Low · Confirmed | `Sources/GlassLayers/GlassLayerStore.swift:31-41` | A corrupt `glass.layers.state` value is silently discarded and the **legacy migration re-runs**, possibly replacing the user's chosen look with a migrated one, and `persist()` overwrites the corrupt value. Appearance only; nothing sensitive. | Same "decode failure rewrites data" pattern as F1, harmless here. | On decode failure fall back to `.default` with `migrationSource = .none` rather than re-migrating. |
| F8 | Info | `Sources/GlassLayers/GlassLayerEnvironment.swift:5` | `EnvironmentKey.defaultValue` uses `MainActor.assumeIsolated`, which traps if the static is first touched off the main actor (e.g., a test reading `EnvironmentValues` on a background task). The app injects the store at the root, so production never hits it. | Latent crash in tests only. | Make the default `nonisolated(unsafe)`-free by constructing lazily inside `body` access, or document the constraint in the tests. |
| F9 | Info | `App/GlassPowerToolsApp.swift:28-29` | `--ui-testing <uuid>` directories under Application Support are never removed. | Accumulating test state on a developer device; `#if DEBUG` only, `resolveSharedContainer: false`, never touches the App Group — isolation itself is sound. | Have the UI test runner delete its directory in `tearDown`. |
| F10 | Info | `Package.swift`, `Package.resolved` (swifttreesitter 0.25.0, tree-sitter 0.25.10) | `GlassEditorCore` is linked but never imported in Stage 1, bringing tree-sitter C grammars into the binary as unreachable code. | Accepted in `techContext.md` (D6, plan 1.2). Unreachable, so no exposure today; it becomes reachable in Stage 5 and should be reviewed then as untrusted-input parsing. | None now. |
| F11 | Info | `Platforms/macOS/macOS.entitlements` | `network.client` and `files.user-selected.read-only` are granted before anything uses them. | Not over-broad for the product (Stage 2 needs both), but Stage 1 could ship without them. | Leave; note that Stage 2 is when they become load-bearing. |

Not findings, checked: Keychain access group is applied only after the `$(` placeholder check
(`App/GlassPowerToolsApp.swift:32-33`); the UI-test path passes `accessGroup: nil`
(`:38`), so an isolated run's Keychain namespace is the app's own, not `sh.glas.shared`.
`serviceNamePrefix: "sh.glas"` matches glas.sh (`KeychainManager.swift:268`), glassdb
(`:153`) and glassDT (`DesktopAppModel.swift:89`), so credentials will be found by capabilities
later. `useDataProtectionKeychain: true` and `mobilityPolicy: .deviceOnly` are the hardened
choices. **No secret is read, written or logged anywhere in Stage 1.**

## What is sound (do not re-review)

- **`HostCatalogStore` (kit)**: every operation takes an exclusive `flock` on a sidecar, reloads
  the file inside the lock, validates before and after, writes atomically, and refuses files over
  8 MiB or 10,000 hosts or an unknown schema version (`HostCatalogStore.swift:250-307`). A failed
  or partial load throws and nothing is written — a partial load never implies deletion. Deletion
  is a tombstone; `merge` cannot resurrect one. The shell's `addService`/`removeService`/
  `deleteHost` go through the kit's in-lock `mutate`, so they cannot clobber other writers (F2 is
  the one exception, and it is `upsert`, not `mutate`).
- **Field bounds** are enforced by `HostProfile.validate` (`HostProfile.swift:84-109`): names
  ≤ 1024 UTF-8 bytes, ≤ 64 aliases/tags, ≤ 128 services, no empty strings, no duplicate endpoints.
  The service kind comes from an exhaustive `Picker` over `HostServiceKind.allCases`; an invalid
  kind is unrepresentable.
- **The Connect placeholder is honest** (`GlassCapability.swift:61-83`): it states the capability
  is absent and that nothing connected; no session object exists. (F3 is the one leak.)
- **`GlassWindowLayerPolicy`** (`GlassWindowLayerPolicy.swift:16-27`) changes only `isOpaque`,
  `backgroundColor`, `titlebarAppearsTransparent` and the passive material's alpha/hidden. It
  never touches `alphaValue`, `styleMask`, `ignoresMouseEvents` or the traffic lights, and the
  reader view returns `nil` from `hitTest`. `installTitlebarMaterial` idempotence is covered by
  the kit's `WindowChromeTests.swift:16-17`. **Reduce Transparency** forces opaque + frosted
  (`GlassLayeredWindow.swift:111-116`) and disables the controls.
- **`--ui-testing` isolation** is `#if DEBUG`, requires a valid UUID, never resolves the App
  Group, and uses a separate Keychain namespace.
- **Entitlements**: macOS is sandboxed with hardened runtime; App Group and Keychain group are the
  family's; iCloud KVS reuses glas.sh's identifier by decision D3 (no iCloud containers declared).
  `NSLocalNetworkUsageDescription` and `NSFaceIDUsageDescription` are present and unused in
  Stage 1 — harmless.
- **Concurrency**: the model is `@MainActor`, the store is an actor, all mutations await the
  actor then reload; concurrent `load()` calls converge on the file's state.

## Out of scope here — Stage 2 (carried from `techContext.md`)

Not reviewed because the code has not moved yet: keystroke recording consent in glas.sh's
`SessionRecorder.recordInput`, and one-click AI command execution trusting the model's own
`riskLevel`. Both move in Stage 2 and must be closed there.
