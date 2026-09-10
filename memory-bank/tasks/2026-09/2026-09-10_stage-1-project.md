# Stage 1 — project file, app target, platform overlay, UI test target

Worker: project-file worker under coordinator `/root`. Done 2026-09-10. **Status: delivered and
verified on three destinations; one open item on macOS signing that is the user's to close.**

## Owned and written

- `GlassPowerTools.xcodeproj/project.pbxproj` — hand-authored, `objectVersion = 77`, authored
  sequential identifiers (`6A000000000000000000ABxx`), copied in style from
  `../glas.sh/glas.sh.xcodeproj/project.pbxproj`.
- `GlassPowerTools.xcodeproj/xcshareddata/xcschemes/GlassPowerTools.xcscheme` — shared scheme:
  builds the app, tests `GlassPowerToolsUITests`.
- `GlassPowerTools.xcodeproj/project.xcworkspace/contents.xcworkspacedata`.
- `App/` — `GlassPowerToolsApp.swift` (minimal `@main`, `WindowGroup("Connections", id: "main")`,
  macOS `Settings`; imports `GlassShell` and `GlassLayers` to prove linking), `Info.plist`,
  `GlassPowerTools.entitlements`, `Assets.xcassets` (AccentColor, empty `AppIcon` set).
- `Platforms/macOS/` — `Info.plist`, `macOS.entitlements`, `Assets.xcassets` (`MacAppIcon` set
  only).
- `UITests/LaunchSmokeUITests.swift` — launches the app and asserts the placeholder in the main
  window.

## What was copied from glas.sh versus authored

| Copied | Authored |
|---|---|
| Project-level Debug/Release settings block (warnings, `ARCHS = arm64`, testability, sandboxing) | Object graph: one app target, one UI test target, no widget, no Citadel / RealityKitContent / swift-nio-ssh, no remote packages |
| App-target settings: `SDKROOT = auto`, `SUPPORTED_PLATFORMS`, per-SDK `TARGETED_DEVICE_FAMILY`, per-SDK entitlements and Info.plist, runpaths, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency, member-import visibility | `PRODUCT_BUNDLE_IDENTIFIER = com.glasspowertools`, `INFOPLIST_KEY_CFBundleDisplayName = "Glass Power Tools"`, `SWIFT_STRICT_CONCURRENCY = complete`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1` |
| Synchronized-folder pattern with membership exceptions for plists, entitlements and the Mac catalog | Single local package reference `relativePath = .` linking products `GlassShell` and `GlassLayers` (the glassDT pattern; the sibling packages come through the root `Package.swift`) |
| Info.plist keys (`GlasKeychainAccessGroup`, Face ID and local-network strings, scene manifest, launch screen, orientations); macOS copyright and category | URL types removed (D4) |
| Entitlements: App Group, Keychain group, iCloud KVS identifier (D3) on all platforms; macOS sandbox, network client, user-selected read-only from glassDT | — |

## Verified

| Destination | Command | Result |
|---|---|---|
| `platform=iOS Simulator,name=iPhone 17 Pro Max` (iOS 27.0) | `xcodebuild build` | **BUILD SUCCEEDED**, "Sign to Run Locally" |
| `platform=visionOS Simulator,name=Apple Vision Pro,OS=27.0` | `xcodebuild build` | **BUILD SUCCEEDED** |
| `platform=macOS`, project as written | `xcodebuild build` | **BUILD FAILED at signing only**: "Provisioning profile 'Mac Team Provisioning Profile: *' doesn't include the iCloud capability / the com.apple.developer.ubiquity-kvstore-identifier entitlement". `-allowProvisioningUpdates` cannot fix it from the CLI: "No Accounts: Add a new account in Accounts settings." |
| `platform=macOS`, diagnostic xcconfig substituting the same macOS entitlements minus the KVS key (project untouched) | `xcodebuild build -xcconfig` | **BUILD SUCCEEDED**, signed "Apple Development: Michael SITARZEWSKI (U534M2T29Q)", team 7JQGQ7CRH8; signature carries `com.apple.security.app-sandbox`, `application-groups = group.sh.glas.shared`, `network.client`, `keychain-access-groups = 7JQGQ7CRH8.sh.glas.shared` |
| UI smoke test, iOS Simulator | `xcodebuild test -only-testing:GlassPowerToolsUITests` | **TEST SUCCEEDED**: `LaunchSmokeUITests.testMainWindowAppears` passed (7.2 s) |
| `plutil -lint project.pbxproj` | | OK |
| `xcodebuild -list` | | targets `GlassPowerTools`, `GlassPowerToolsUITests`; scheme `GlassPowerTools` |

Not run: UI test on visionOS Simulator and on macOS; any physical-device build or install; Release
configuration. A simulator build says nothing about device behaviour.

Only warnings from our files: the `appintentsmetadataprocessor` notice that no AppIntents
dependency exists (expected). All other warnings are inside `../GlassEditorKit`'s vendored
tree-sitter grammars and its `AtomicSaver.swift`, none of them ours.

## Findings the integration pass must know

1. **Scheme name is `GlassPowerTools`.** Bundle id `com.glasspowertools`. Unit tests live in the
   SwiftPM package (`swift test` at the repo root); the Xcode project has no unit-test target by
   design.
2. **macOS signing needs the App ID configured once.** `com.glasspowertools` is a new App ID. The
   automatic Mac team profile already grants App Groups and Keychain sharing (proven above), but the
   iCloud KVS entitlement chosen in D3 requires the iCloud capability on the App ID. That is a
   one-time action in Xcode's Signing & Capabilities with a signed-in account, or in the developer
   portal. Until then, a macOS build from the CLI must use the diagnostic xcconfig, or D3 is
   revisited. Nothing in the project was changed to work around it.
3. **`platformFilter = macos` on a Resources build file does not keep the Mac asset catalog out of
   the iOS actool invocation.** The iOS build compiled both `App/Assets.xcassets` and
   `Platforms/macOS/Assets.xcassets` and failed on two icon sets named `AppIcon`. Resolved the way
   glassdb does it: the Mac set is `MacAppIcon.appiconset` and the target sets
   `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*] = MacAppIcon`. The Mac catalog carries no
   AccentColor; the universal one in `App/` applies everywhere.
4. **Both icon sets are empty placeholders.** No artwork was created; add images before any
   device install that needs an icon.
5. **Concurrent workers' files raced two builds** (`GlassShellModel.swift` initializer error, then a
   transient `_TemporaryLayersStub.swift`). Both resolved themselves on re-run; neither was in
   this worker's scope. The final three-platform results above are against the tree as it stood at
   14:56–14:57 local time.
6. `App/GlassPowerToolsApp.swift` is deliberately minimal; the integration pass replaces its
   scene bodies. Keep the `"main"` window id and the `glasspowertools-main-placeholder`
   identifier until the real library view has its own identifiers, or update
   `UITests/LaunchSmokeUITests.swift` in the same change.

## Rules honoured

No Git state changes, no XcodeGen, no session URLs, no secrets, no edits outside the owned paths,
no sibling edits. Build artefacts live under the session scratchpad, not in the repository.
