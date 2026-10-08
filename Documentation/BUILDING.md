# Building and testing

## Requirements

- A Mac with Apple silicon. The app is built for `arm64` only.
- Xcode 27 or later (the project is developed with Xcode 27.2 and Swift 6.4). The package manifest
  needs Swift tools 6.2.
- Deployment floor: macOS 26, iOS and iPadOS 26, visionOS 26.
- Python 3 and `curl`, used by the build's pre-action (below). `npm` only when Mermaid moves to a
  new version.

## The project

`GlassPowerTools.xcodeproj` is the project of record: one multiplatform app target (Mac, iPad,
iPhone, Vision Pro), a widget extension and a UI-test target. Almost all code lives in the Swift
package at the repository root (`Package.swift`), whose modules the app target links:

| Folder | What it is |
|---|---|
| `App/`, `Platforms/macOS/` | The app's entry point, Info.plists and entitlements |
| `Sources/` | The package's modules: the shell, each capability, their engines, the editor |
| `Packages/` | Third-party code carried in the repository, each with its licence and a record of local changes (`PATCHES.md`, `GLASSDT-PATCHES.md`) |
| `Tests/`, `UITests/` | Package tests (Swift Testing and XCTest) and XCUITest suites |
| `Widgets/` | The widget extension |
| `Config/Identity.xcconfig` | Signing team, bundle identifier, iCloud container, App Group and keychain group |
| `Tools/` | Build and maintenance scripts |
| `memory-bank/` | The project's working notes: decisions, rules, progress and task records |

## Signing under your own team

The identifiers in `Config/Identity.xcconfig` are this project's. To build under your own Apple
Developer team, do not edit that file; create `Config/Identity.local.xcconfig` (it is git-ignored)
and override what you need:

```
GPT_DEVELOPMENT_TEAM = ABCDE12345
GPT_BUNDLE_ID = com.example.glasspowertools
GPT_ICLOUD_CONTAINER = iCloud.com.example.glasspowertools
GPT_APP_GROUP = group.com.example.glasspowertools
GPT_KEYCHAIN_GROUP_SUFFIX = com.example.glasspowertools.shared
GPT_KVSTORE_SUFFIX = com.example.glasspowertools
```

The entitlements files, the Info.plists and the code (`GlassAppIdentity`) all read these, so nothing
else needs to change. Your team needs the iCloud container and App Group registered for the app ID.

## Building

Open the project in Xcode and run the **GlassPowerTools** scheme, or from the command line:

```sh
xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools \
  -configuration Release -destination 'generic/platform=macOS' \
  -skipPackagePluginValidation build
```

Use `generic/platform=iOS` or `generic/platform=visionOS` for the other platforms.

SwiftTerm carries a build-tool plugin that runs `git` on SwiftTerm's own checkout to record its
version in a generated file (it reaches no network). Xcode asks once to trust it (**Trust & Enable**);
`xcodebuild` needs `-skipPackagePluginValidation`. `swift build` runs it without asking.

The scheme's build pre-action runs `Tools/Mermaid/update-mermaid.sh`, which asks the npm registry for
the latest Mermaid (used by the editor's Markdown preview), verifies the download's checksum, and
takes a new version only when every package inside it carries a licence already reviewed. Offline,
the build continues with the copy it has.

The macOS app is not sandboxed: a terminal needs to start local shells and reach the user's files and
tools. Release builds use the hardened runtime.

**If a build stops at "Downloading binary artifact … Sparkle":** SwiftPM looks for GitHub credentials
in the Keychain before downloading Sparkle's prebuilt framework, and with more than one saved entry it
waits on a Keychain prompt. The download is public; skip the lookup with `swift build
--disable-keychain`, or `-packageAuthorizationProvider netrc` for `xcodebuild`.

## Releasing the Mac app

`Tools/Release/release-mac.sh <version> <build>` archives, signs with Developer ID, notarizes,
staples, signs the Sparkle update and adds it to `site/static/appcast.xml`, then makes the disk image.
It needs the Developer ID certificate, Apple notarization credentials in the environment, and
Sparkle's EdDSA key: create it once with Sparkle's `generate_keys --account GlassPowerTools`, keep
the private half in the login Keychain, and put the public half in `GPT_SPARKLE_PUBLIC_KEY` in
`Config/Identity.xcconfig`. Until then the app does not update itself, and the script refuses to run.

## The website

`python3 Tools/Site/build_site.py` builds glasspowertools.com into `_site/`: the pages in
`site/pages/`, the help in `site/help/` (one `registry.json` drives its sidebar, search, sitemap and
`llms.txt`), `SECURITY.md`, and the update feed. The build refuses to finish if a help link or anchor
does not resolve or a page carries an address outside the documentation ranges. Preview it with
`python3 -m http.server -d _site 8090`.

## Tests

The package tests are fast and need no network:

```sh
swift test
```

**Unlock the screen first.** Several stores write files with complete data protection, which are
unreadable while the Mac is locked; a locked screen shows up as permission and `mktemp` failures.

UI tests run through Xcode or `xcodebuild test` against a simulator, for example:

```sh
xcodebuild test -project GlassPowerTools.xcodeproj -scheme GlassPowerTools \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:GlassPowerToolsUITests/EditorOnIPhoneUITests
```

UI tests launch the app with `--ui-testing <uuid>`, which gives the run its own storage and settings
and keeps it away from iCloud; nothing a test does reaches your own library.

### Live tests against real servers

Some suites talk to a real SSH server and real MySQL and PostgreSQL servers. They are skipped unless
their environment variables are set, so a plain `swift test` passes without them. Use a disposable
virtual machine: the tests create and drop tables and files.

| Suite | Variables |
|---|---|
| SSH transport, remote editing | `GPT_SSH_TEST_HOST`, `GPT_SSH_TEST_PORT`, `GPT_SSH_TEST_USER`, and `GPT_SSH_TEST_KEY_PATH` or `GPT_SSH_TEST_PASSWORD` |
| Databases | `GPT_DB_TEST_HOST`, `GPT_DB_TEST_MYSQL_*` and `GPT_DB_TEST_PG_*` (user, password, port, database, scratch database; `GPT_DB_TEST_MYSQL_CA_PATH` and `GPT_DB_TEST_MYSQL_TLS_SERVER_NAME` for the TLS tests) |

Keep the values in a file outside the repository and load it into the shell before running:

```sh
set -a; source ~/.config/gpt-db-test.env; set +a
swift test --filter LiveDatabaseIntegration
```

Give the database tests a least-privilege user that owns only the test databases.

### Vendored packages

`Packages/Citadel`, `Packages/swift-nio-ssh` and `Packages/RDPKit` have their own test suites. Run
them in a copy, so their own `Package.resolved` files are not rewritten:

```sh
cp -R Packages/Citadel /tmp/citadel && (cd /tmp/citadel && swift test)
```

## Dependencies

Dependency revisions are pinned in `Package.resolved`, and Xcode keeps its own copy under
`GlassPowerTools.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`. After updating:

```sh
swift package update
python3 Tools/Packages/sync-xcode-pins.py
xcodebuild -resolvePackageDependencies -project GlassPowerTools.xcodeproj -scheme GlassPowerTools
python3 Tools/Licenses/generate-acknowledgements.py
```

Pins move only on purpose. To see what is newer, and to test the app against it without touching
this checkout:

```sh
python3 Tools/Packages/check-updates.py                     # newer releases, notes, what to review
python3 Tools/Packages/check-updates.py --test swiftterm    # tests and app builds against the newest
python3 Tools/Packages/check-updates.py --test newer        # the same for every direct dependency
sh Tools/Packages/install-weekly-check.sh                   # run it every Monday (--remove to stop)
```

The report flags what a person should look at before taking a release: a new build-tool plugin,
binary target, unsafe flag or dependency in its manifest, a changed licence, a new major version.
`--test` works in a temporary worktree holding this checkout's committed and uncommitted state, runs
every test target and builds the app for macOS, iOS and visionOS; `--platforms none` skips the app
builds. Device behaviour still needs a person on each device.

`PackagePinAgreementTests` fails if the two pin files disagree, and `AcknowledgementsTests` fails if a
dependency has no entry in `Tools/Licenses/components.json`. Adding a dependency means adding its
entry there and running the generator, which copies its licence into
`Documentation/ThirdPartyLicenses/` and refreshes the list shown in Settings ▸ About ▸
Acknowledgements.
