# Technical context

Everything here was measured or read on 2026-09-10 from the working checkouts. No build of Glass
Power Tools exists. The sizes, entitlement groups and deployment targets below were re-measured on
2026-09-10 after the project moved to `~/Software/glass/GlassPowerTools`, and all of them still hold.

## Workspace layout

The project is `~/Software/glass/GlassPowerTools`. Every source application and shared package is a
**sibling directory** under `~/Software/glass/`, so the `../name` paths used throughout this memory
bank and `AGENTS.md` resolve correctly from the project root. Verified 2026-09-10.

| Path | What it is | Role |
|---|---|---|
| `../glas.sh` | Terminal, SFTP, port forwarding, workgroups | Input, Stage 2 |
| `../glassdb` | Databases | Input, Stage 3 |
| `../glassDT` | RDP and VNC | Input, Stage 4 |
| `../GlassConnectionKit` | `GlassConnectionKit`, `GlassConnectionUI`, `GlassHostCatalog` | Consumed from Stage 1 |
| `../GlasSecretStore` | Credentials, trust, mobility | Consumed from Stage 1 |
| `../GlassEditorKit` | Editing and syntax analysis | Library in Stage 1, interface Stage 5 |

The two surfaces Stage 1 must read before writing anything new are
`../GlassConnectionKit/Sources/GlassConnectionUI` and `../glassDT/Sources/GlassDesktopUI`. Both
confirmed present.

**Not inputs, and not to be read as current:**

- `../glassdb-connection-library` — **resolved 2026-09-10, archived as
  `../glassdb-connection-library.zip` and the directory removed.** It was a stale snapshot of the
  glassdb application (19,018 Swift lines against the live 22,244) whose name wrongly suggested a
  shared library. Proven a strict subset before archiving: no file in its memory bank was absent from
  live glassdb, which additionally held the September tasks, `releases/intents` and eleven further
  task notes; the source differed only by `HighlightedTextEditor.swift` against
  `GlassEditorAdapters.swift`, placing it before GlassEditorKit adoption. The live database source is
  `../glassdb`, and Stage 3 migrates from there. Do not unpack the archive to consult it.
- `../docs` — two **security and maturity audit reports** of glas.sh and glassdb dated 2026-07-16/17,
  with `file:line` citations and severity tiers. Not user documentation and not a journal. They cite
  GlasSecretStore at `~/Developer/GlasSecretStore/`, an old path, confirming they
  predate the current layout. Not an input to the merge, but not merely historical either: see the
  carried-forward findings below before Stage 2.

Git state across the siblings after 2026-09-10: `glas.sh`, `glassdb`, `GlasSecretStore`,
`GlassEditorKit` and `GlassConnectionKit` are Git checkouts; `glassDT` is not. This project is a Git
repository on `main` since 2026-09-10. Commits still happen only on the user's instruction. The user
notes glas.sh has an unmerged PR; local source is authoritative for this work.

## Sizes

| Source | Swift lines |
|---|---|
| `../glas.sh/glas.sh` | 31,393 |
| `../glassdb/glassdb` | 22,244 |
| `../glassDT/Sources` and `App` | 5,573 |
| `../GlassConnectionKit/Sources` | 2,223 |
| `../GlasSecretStore/Sources` | 2,124 |
| `../GlassEditorKit/Sources` | 8,128 |

Most of the application volume is capability-specific and should move largely intact. The risk
concentrates in application entry points, scene and window management, settings, and merging three
test suites.

## Identities and entitlements

| App | Bundle identifier |
|---|---|
| glas.sh | `sh.glas.app` |
| glassdb | `app.glassdb` |
| glassDT | `app.glassdt` |
| Glass Power Tools | `com.glasspowertools` |

All three existing apps declare the App Group `group.sh.glas.shared` and the Keychain access group
`$(AppIdentifierPrefix)sh.glas.shared`, signing team 7JQGQ7CRH8. A new bundle identifier
declaring those same two groups should inherit existing hosts and credentials in place. This is worth
doing because it is free, but it is **not load-bearing**: the user is the only user, so no import
path is built and no stage blocks on proving it.

## Deployment target and architecture

**Decided: 26.0 on macOS, iOS and visionOS, `arm64` only, no Intel slice.**

Observed in the sources: glas.sh 26.0 across the board; glassdb macOS 27.0 with iOS and visionOS at
26.0; glassDT 26.0 across the board. Only glassdb's macOS target moves, downward, so anything in it
depending on 27.0 must be found when that capability is migrated.

Grepping the projects also turns up `MACOSX_DEPLOYMENT_TARGET = 15.0`. It belongs to the vendored
`Packages/Citadel/Examples/CitadelCLI` sample project in both glas.sh and glassdb, not to any app
target, and does not contradict the paragraph above. Noted so it is not re-investigated.

## Dependencies to consolidate

Local packages: GlassConnectionKit (three targets), GlasSecretStore, GlassEditorKit (ten targets
including tree-sitter grammars), RDPKit, VNCKit, GlassRDPTransport, GlassVNCTransport. Remote
packages referenced by the siblings include GlasSecretStore and GlassEditorKit over HTTPS, plus
SwiftTerm, Citadel and swift-nio-ssh in glas.sh, and database drivers in glassdb.

The three apps currently pin different revisions of the shared packages. In one project this problem
disappears, which is one of the reasons to merge.

## The July 2026 audit findings, checked on 2026-09-10

The reports in `../docs` are two months old and most of what they raised has since been fixed.
Verified against current source rather than assumed:

| Finding | State on 2026-09-10 |
|---|---|
| SSH accepted any host key (`.acceptAnything()`) | **Fixed.** No occurrence in any live source. |
| Automatic downgrade to `SSHAlgorithms.all` on negotiation failure | **Fixed.** No occurrence outside vendored Citadel. |
| `SSHHostTrustKeychainStore` existed but was unused | **Fixed.** Used by glas.sh and glassdb. |
| MySQL connected with `tlsConfiguration: nil` | **Fixed.** `makeTLSConfiguration` is built and passed. |
| Recordings written with no file-protection policy | **Fixed.** `FileProtectionType.complete` / `completeUnlessOpen` applied. |
| `NSFaceIDUsageDescription` missing | **Fixed.** Present in the app and macOS `Info.plist`. |
| Credentials keyed by `username@host:port`, able to collide | **Likely addressed.** glassdb now keys through `CredentialStorageDescriptor`; not traced end to end. |
| Every input byte recorded, passwords included | **Resolved** (confirmed 2026-09-10 by the Stage 2 security review): input capture is opt-in per recording (`start(capturesInput: false)`), the UI states the password risk, a persistent indicator exists, `finalize()` runs on every disconnect path, files are `.completeUnlessOpen` while open and `.complete` when finalised. Moved byte-identical into `GlassTerminal`. |
| One-click AI commands trusting the model's own risk label | **Resolved** (same review): execution is gated by a deterministic `assess()` — control syntax, destructive/privilege/credential/network/interpreter utilities, control-character Unicode — behind a confirmation showing the exact command; the model's `riskLevel` is a badge only. Moved byte-identical. |

Every finding in the July reports is now closed or superseded. `../docs` can be deleted at the
user's discretion; nothing in it is still open.

## Shared package state on 2026-09-10 — read before Stage 1

**GlasSecretStore exists in three states, and only one has the RDP credential store.**

| Consumer | Reference | Revision | Has RDP credential store |
|---|---|---|---|
| glas.sh | GitHub, pinned | `1ffaa96` (2026-07-17, upstream `main`) | No |
| glassdb | GitHub, pinned | `9be45c9` (2026-08-05, upstream `main` tip) | No |
| glassDT | local path `../GlasSecretStore` | working tree: `9be45c9` content **plus uncommitted work** | Yes |

The local checkout is on branch `codex-completions` at `838e052`, a rebased twin of upstream's
`9be45c9`. Its working tree carries **12 uncommitted files**: untracked `RDPCredentialStore.swift`
and `RDPCredentialTests.swift` (446 lines), plus the synchronizable-Keychain edits to
`SecretStoreConfiguration`, `KeychainOperations` and `SSHKeyKeychainStore`. GlasSecretStore's own
task note (`../GlasSecretStore/memory-bank/tasks/2026-09/2026-09-08_glassdt-family-integration.md`)
records this as deliberate: "no publication or commit was made", 90 tests verified, and glas.sh and
glassdb pins "remain unchanged". `PROVENANCE.md` there names `9be45c9` as the base.

Consequence: Glass Power Tools consumes `../GlasSecretStore` by local path, because that is the only
copy with the RDP record Stage 4 needs and the only way to have one copy. **Committed 2026-09-10 as
`aa1b3f1` on `codex-completions` on the user's instruction; the tree is clean.** Upstream `main`
still lacks it; glas.sh and glassdb still pin the older upstream revisions.

**GlassConnectionKit is now under version control** — initialised 2026-09-10 on `main`, initial
commit `d48a5ff`, 47 files, on the user's instruction. It is the most-consumed package in the
family (all three apps by local path since 2026-09-08). `swift test` ran 21 tests in 3 suites on the
macOS host on 2026-09-10; the package's own note says 38, and the difference was not investigated.

**GlassEditorKit is clean.** glas.sh pins `5d8f003` = local `main` HEAD; glassdb pins `ae094a8`, an
ancestor. Local path consumption is safe.

## Where the shared catalog lives

All three apps read and write the same file:
`<App Group container for group.sh.glas.shared>/GlassHostCatalog/hosts.json`, via
`HostCatalogStore(fileURL:writerID:)` (`../glassDT/Sources/GlassDesktopUI/DesktopAppModel.swift:65-68`,
`../glassdb/glassdb/ConnectionManagerView.swift:272-277`,
`../glas.sh/glas.sh/ConnectionManagerView.swift:135`). It holds host identity and
`HostServiceLink { endpointID, kind, displayName, credentialID? }` per service — metadata only. Full
endpoint records (SSH server details, database connection, desktop connection) live in each app's
own store. So a new bundle identifier that declares the App Group opens the same `hosts.json` and
lists every host and its service kinds immediately, and can connect to none of them until the
capability that owns the endpoint record arrives. That is exactly Stage 1's scope.

## Layering state has drifted three ways

| App | Opacity default | Blur / frost | Where |
|---|---|---|---|
| glas.sh | `windowOpacity = 0.0` (fully transparent) | `blurBackground = 1.0`, `glassFrost = "ultraThin"`, `paintsTheme` | `SettingsManager.swift` |
| glassdb | `windowOpacity = 0.95` | `blurBackground = 1.0` | `SettingsManager.swift` |
| glassDT | `opacity = 1.0`, key `display.glass.opacity` | `frost = 0.25` | `DesktopSettingsView.swift` |

The *views* are already shared in `GlassConnectionUI` — `GlassNativeWindowFrame`,
`GlassCanvasBackdrop(material:blurAmount:)`, `GlassWindowChrome.installTitlebarMaterial(in:)`,
`GlassSettingSlider` — but the *state* feeding them is three different models with three different
defaults. Stage 1 owns one model (`GlassLayers`, D2: transparent-first with frost on).

**Migration limit found while building `GlassLayers`:** all three apps store those keys in their own
`.standard` defaults domain (glas.sh `SettingsManager.swift:205`, glassdb `:142`, glassDT via
`@AppStorage`), not in the App Group suite. A different bundle cannot read another app's
`.standard` domain on iOS or visionOS at all, and on macOS only outside the sandbox. So the legacy
migration is guaranteed only for keys already in the App Group suite or this app's own domain,
best-effort on the Mac, and otherwise falls back to the D2 default. Do not promise that a user's
current look carries over.

## Test hosts (user-provided, 2026-09-10)

| Purpose | Host | User | Auth | Verified |
|---|---|---|---|---|
| SSH / SFTP / tunnel integration tests | `192.0.2.6` (Parallels scratch VM, Linux 7.0.0-29-generic) | `michael` | ED25519 key at `~/.ssh/<test VM key>` | `echo ok` over BatchMode SSH; `Subsystem sftp /usr/lib/openssh/sftp-server`; no `AllowTcpForwarding` restriction |

Environment for the gated tests: `GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=michael
GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/<test VM key>`. Never record key material or passwords here.

## macOS accessibility crash under XCUITest (root-caused 2026-09-10)

Six identical `EXC_BAD_ACCESS` reports in AppKit `_accessibilityFindRoleFromProtocol` ←
SwiftUI `AccessibilityNode.resolvedRole`, no app frames, are triggered deterministically by
presenting `AddSSHKeyView` as a sheet from the server-form sheet (`ServerFormViews.swift:427`),
whenever the accessibility tree is then resolved (the runner's snapshot ~45 s after the click).
The view is byte-identical to glas.sh; the form alone is fine. Rule 12 in project rules; fix owned
by W3. The engine reached the test VM from the iOS simulator through key exchange to the host-trust
prompt, so the simulator is not subject to the Mac's Local Network gate.

## Security posture to carry forward

- RDP pins the server certificate; the flow is implemented and tested.
- VNC has no server authentication in any security type currently implemented, and the session is
  unencrypted. Two agreed follow-ups: show whether a session is encrypted, and offer an SSH tunnel
  for VNC. In one application the tunnel is nearly free, because SSH already exists.
- Merging removes process boundaries between protocol parsers and live session memory. The parsers
  are memory-safe Swift, but zlib, VideoToolbox, CommonCrypto, tree-sitter and a small number of
  deliberate unsafe blocks are not. If real containment is wanted later, move an engine into an XPC
  service; that is one piece of infrastructure here, and would have been three.


**Local Network (updated 2026-09-11):** the grant for the terminal app is now in place; ad-hoc-signed binaries reach `192.0.2.6:22`. The engine's real-host suite passes 5/5 (see the Stage 2 transport note).

**macOS App Sandbox (found 2026-09-10 evening, fixed):** the Stage 1 project's
`Platforms/macOS/macOS.entitlements` carried `com.apple.security.app-sandbox`, `network.client`
and `files.user-selected.read-only`, which glas.sh's macOS entitlements never had. The sandbox broke
The Mac local terminal (`zsh: can't set tty pgrp: operation not permitted`) and would have blocked
the SSH agent socket, `~/.ssh` reads and file-promise drags. The file is now byte-identical to
glas.sh's: App Group, Keychain group, iCloud KVS, hardened runtime on, no sandbox.

---

## Current dependency state, 2026-09-15

The "Dependencies to consolidate" section above is the pre-merge survey and is kept as the record of
what was found. This is where things actually are.

**No sibling package remains a dependency.** GlasSecretStore, GlassConnectionKit and GlassEditorKit
were absorbed; `../glas.sh`, `../glassdb`, `../glassDT` and those three are historical records.

**Sixteen tree-sitter grammars, every one fixed to an exact upstream commit** (checked against
upstream 2026-09-26; `THIRD-PARTY-NOTICES.md` carries the commits and the detail):

| Grammar | How | Why |
|---|---|---|
| JSON, Bash, TOML, HTML, Go, C | pinned dependency (`revision:`) | upstream's manifest builds it correctly |
| YAML | vendored, scanner patched | upstream's manifest drops `scanner.c` when it is a dependency (a relative `fileExists`); the scanner also carries a bounds fix (pen H-2) |
| Markdown | vendored, scanner patched | unbounded copy into a 1024-byte buffer in `serialize()` (pen H-1) |
| Markdown inline | vendored, unmodified | same repository and commit as Markdown |
| SQL | vendored, scanner patched | `serialize()` consumes its own state (pen M-5); still on upstream HEAD |
| Python, JavaScript, Rust, PHP | vendored, unmodified | upstream's manifest compiles `parser.c` and not `scanner.c` |
| Swift | vendored, generated `parser.c` | upstream publishes no generated parser |
| XML | vendored, one include path changed | upstream's shared header sits outside the grammar's directory |

Markdown and SQL were once pinned for a day and the patches were lost with the switch; the markdown
one aborted a whole test target that day without anyone noticing, because a crashed target prints no
failure line and no count (rule 25). `ScannerOverflowPenTests` guards the markdown and YAML fixes.

**Licences and acknowledgements** (2026-09-26): `Tools/Licenses/components.json` lists every
third-party component; `Tools/Licenses/generate-acknowledgements.py` copies each pin's licence and
NOTICE files into `Documentation/ThirdPartyLicenses/<id>/` and writes
`Sources/GlassShell/Resources/Acknowledgements.json`, shown at Settings ▸ About ▸ Acknowledgements.
`Tools/Mermaid/update-mermaid.sh` lists the licences of every package inside a new Mermaid and
refuses the update if one is of a kind not yet reviewed. `AcknowledgementsTests` fails when a pin, a
vendored package or the Mermaid version is not covered, and when the two `Package.resolved` files
disagree.

**`.git` is 13 MB.** SQL's generated `parser.c` is 41 MB in the working tree and **2.6 MB**
committed, which is the measurement that reversed a recommendation to fork rather than vendor.

**D26 storage, as built:** a capability's records live on their service links in the host catalog —
`UserDefaultsKeys.servers`, `glassdb.connections` and `connections.json` are no longer production
stores. SSH key *records* live in the Keychain beside their material
(`sshKeysRecordService`, synchronizable), routed to the device-bound configuration when the key is
Secure Enclave.


## Toolchain, 2026-09-19 — Xcode 27.2 and what it broke

**Xcode 27.2 (27B5019j)** replaced 27.0 overnight, and two things stopped working that have
nothing to do with this code:

- **Every build failed** with `cannot execute tool 'metal' due to missing Metal Toolchain`.
  SwiftTerm ships a `.metal` shader, so this is not optional for any target that links it.
  `xcodebuild -downloadComponent MetalToolchain` fixes it — 839 MB, and it takes a few minutes.
- **The simulator disappeared.** `/Library/Developer/PrivateFrameworks/CoreSimulator.framework`
  did not exist, so `xcodebuild test` on any simulator failed to load `IDESimulatorFoundation`
  and `xcrun simctl` listed nothing. The fix needs admin: **`sudo xcodebuild -runFirstLaunch`**.
  Without it there is no iPhone UI testing at all, which is where this project's defects are
  found (rule 46).

The 2026-09-18 report that "macOS UI automation cannot start" — *Timed out while enabling
automation mode*, on every test including the launch smoke test — was almost certainly the same
update in flight, and did not recur afterwards.

**A simulator test runner does not receive `TEST_RUNNER_*` environment on this toolchain.** The
live fixtures (`GPT_SSH_TEST_*`, `GPT_DB_TEST_*`) are read with `ProcessInfo.processInfo.environment`
in the runner, which on macOS inherits the shell's. Every live UI test is therefore **macOS-only
in practice**, and the database and desktop have no phone-side coverage at all until a
configuration can be seeded the way `--ui-testing-seed-project` seeds one for the editor.


## macOS 27.2 beta (26B5091g) — observed 2026-09-21

The Mac moved to 27.2 during the day. One behaviour change found so far: **Swift Charts places a
categorical y-axis label at the top edge of its band** and ignores `AxisValueLabel(centered:)`
under every preset, so a horizontal bar chart's names sit on the bar below. The overview charts
now name their bars with annotations instead
([task note](tasks/2026-09/2026-09-21_charts-on-macos-27-2.md)). Chart layout on this machine can
be measured headless with an `ImageRenderer` probe — `Tools/ChartProbe` is the shape of it.

## Editor and grid engines, 2026-09-25

- **Mac editor text system: TextKit 1** with non-contiguous layout (D36) — `GlassTextView.makeTextKit1()`,
  `GlassEditorAppKitEngine(textSystem:)` defaulting to `.textKit1`; iPhone, iPad and Vision Pro stay
  on TextKit 2. Highlighting ceiling 2 M UTF-16 units, checked before parsing (rule 58); runs on lines
  over 20,000 characters dropped; lines over 100,000 force wrapping (and Preview-only on a phone);
  unwrapped means a finite 100,000 pt container.
- **Mac editor save panel:** `NSSavePanel` via `GlassEditorSavePanel` for a never-saved document;
  other platforms use SwiftUI's `fileExporter` (rule 60).
- **Database grid:** SwiftUI `LazyVStack` in `TableDetailView.dataGrid`. Since 0.4.218: displayed-row
  indices memoized (`GridDisplayedRowsMemo`), the horizontal scroll offset only on frozen cells
  (`gridFrozen`), one tap gesture per cell on the Mac (`gridTap`, click count decides). Timing
  harness: `GPT_GRID_TIMING=1 GPT_GRID_PAGE=1000 GPT_GRID_STEPS=1500 swift test -c release --filter
  GridScrollTimingTests` (real view, real SQLite in the managed folder; needs the Mac to itself).
  `NSTableView` remains the proposed next step if numbers require it.
- **Terminal renderer:** SwiftTerm's Metal renderer on the Mac and iPhone; CoreGraphics on Vision Pro.

## Release and hosting, 2026-09-25 (D38, D39)

Not built yet. Mac releases: Developer ID + notarization + Sparkle (macOS-only dependency), feed
`https://glasspowertools.com/appcast.xml`; `aps-environment` must be `production` in release builds
(`Platforms/macOS/macOS.entitlements` says `development`); a Developer ID profile must carry the
CloudKit container, App Group and Keychain group. iOS, iPadOS, visionOS: TestFlight, then the App
Store. The site is static, built into `_site/`; where and how it is hosted is kept out of this repository
(private infrastructure notes).

## Dependencies, 2026-09-27

Every dependency is pinned to a revision in `Package.resolved`; Xcode's copy must match it
(`Tools/Packages/sync-xcode-pins.py`, `PackagePinAgreementTests`). Notable versions: swift-nio
2.103.0, swift-nio-ssl 2.37.5, swift-crypto 4.5.2, BigInt 6.0.1, SwiftTerm **1.20.0** (exact, D48;
its build-tool plugin needs `-skipPackagePluginValidation` for `xcodebuild`),
swift-markdown 0.9.0 (exact), tree-sitter 0.25.10, postgres-nio 1.33.1, mysql-nio at the fork's
recorded revision. Vendored: Citadel `ae8562f`, swift-nio-ssh 0.3.7 (`6acaa1a`), RDPKit 0.3.1.

**Watching for newer releases (D48, 2026-10-07):** `Tools/Packages/check-updates.py` reports what is
newer, with release notes, commits and anything to review (new plugins, binary targets, unsafe flags,
dependencies, licence changes, major versions); `--test NAME` tests the app against a release in a
temporary worktree. A LaunchAgent (`Tools/Packages/install-weekly-check.sh`) runs it Mondays at
08:00 with `--test newer`; reports in `~/Library/Logs/GlassPowerTools/`. It never changes a pin.
First survey: 8 of 30 pins behind (swift-log 1.16.1 and swift-nio 2.104.0 allowed as declared; the
rest indirect, including tree-sitter 0.27 and swift-crypto 5 below).

Held back, with the reason:

| Dependency | Newest | Why not taken |
|---|---|---|
| tree-sitter | 0.27.0 | SwiftTreeSitter (latest tag and `main`) allows only 0.25.x |
| swift-crypto | 5.0.0 | postgres-nio's latest release and mysql-nio (upstream and the fork) allow only `< 5.0.0`; Citadel's and swift-nio-ssh's vendored manifests say the same |

## UIKit editor tests on the iOS simulator, 2026-10-12

`Tests/GlassEditorUIKitTests` holds tests of the UIKit editor (`GlassTextViewIOS`, `GlassEditorUIKitEngine`); on a
Mac the target is empty. `GlassPowerTools-Package` cannot run them on iOS, because other test targets (for example
`GlasSecretStoreTests`, which uses `homeDirectoryForCurrentUser`) do not compile for iOS. Run them through a scheme
holding only that target, in the git-ignored `.swiftpm/xcode/xcshareddata/xcschemes/EditorUITests.xcscheme`: a
`TestAction` with one `TestableReference` whose `BuildableReference` has `BlueprintIdentifier`, `BuildableName` and
`BlueprintName` all `GlassEditorUIKitTests` and `ReferencedContainer="container:"`. Then:
`xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme EditorUITests -destination 'platform=iOS
Simulator,name=iPhone 17' -clonedSourcePackagesDirPath <resolved SourcePackages> -packageAuthorizationProvider netrc
-skipPackagePluginValidation -onlyUsePackageVersionsFromResolvedFile`.

## Widgets, App Groups and the test runner, 2026-10-12

- The widget extension is built for macOS, iOS and visionOS and embedded in all three apps. Xcode's automatic signing
  gives the Mac extension the team's wildcard profile, which cannot grant a `group.` App Group: the sandbox denied the
  file (Cocoa 257). On a Mac the widget snapshot therefore uses a team-prefixed group, `GPT_WIDGET_GROUP`
  (`Config/Identity.xcconfig`), which needs no profile; iOS and visionOS extensions have an explicit profile with
  `group.sh.glas.shared`. `GlassWidgetStore` reads the `GlassWidgetGroup` Info.plist key.
- App Intents defined in a Swift package work with Xcode 27.2: `Metadata.appintents` lists them in both the app and
  the extension when each declares an `AppIntentsPackage` that includes the package's.
- `swift test` cannot reach a VM on a local or virtual network ("No route to host"): macOS's Local Network permission
  blocks the runner. Tunnel through loopback for live SSH tests (`ssh -N -L 2222:localhost:22`, then
  `GPT_SSH_TEST_HOST=127.0.0.1 GPT_SSH_TEST_PORT=2222`).
- A dead SFTP/SSH connection under Citadel surfaces as NIO `ChannelError.ioOnClosedChannel` or `.outputClosed`.

