# Technical context

The sections from here to "Security posture to carry forward" were measured or read on 2026-09-10
from the working checkouts, before any build of Glass Power Tools existed, and are kept as that
survey; each later section is dated. For where things stand, start at "Current dependency state" and
read down. The sizes, entitlement groups and deployment targets below were re-measured on 2026-09-10
after the project moved to its present directory, and all of them still held.

## Workspace layout

Every source application and shared package is a **sibling directory** of the project, so the
`../name` paths used throughout this memory bank and `AGENTS.md` resolve correctly from the project
root. Verified 2026-09-10.

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
  GlasSecretStore at an older location outside this layout, confirming they
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

**Decided: 26.0 on macOS, iOS and visionOS, `arm64` only, no Intel slice.** Still so on 2026-10-17:
`Package.swift` declares `.macOS(.v26)`, `.iOS(.v26)`, `.visionOS(.v26)`, and every configuration in
`GlassPowerTools.xcodeproj` sets 26.0 and `ARCHS = arm64` (the app, its UI tests and five extensions).

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
| SSH / SFTP / tunnel integration tests | `192.0.2.6` (Parallels scratch VM, Linux 7.0.0-29-generic) | `<test account>` | ED25519 key at `~/.ssh/<test VM key>` | `echo ok` over BatchMode SSH; `Subsystem sftp /usr/lib/openssh/sftp-server`; no `AllowTcpForwarding` restriction |

Environment for the gated tests: `GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=<test account>
GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/<test VM key>`. Never record key material, passwords or the real
account and address here (rule 61); they are kept outside the repository. Since 2026-10-12 the
runner reaches the VM through a loopback tunnel (below, "Widgets, App Groups and the test runner").

## macOS accessibility crash under XCUITest (root-caused 2026-09-10)

Six identical `EXC_BAD_ACCESS` reports in AppKit `_accessibilityFindRoleFromProtocol` ←
SwiftUI `AccessibilityNode.resolvedRole`, no app frames, are triggered deterministically by
presenting `AddSSHKeyView` as a sheet from the server-form sheet (`ServerFormViews.swift:427`),
whenever the accessibility tree is then resolved (the runner's snapshot ~45 s after the click).
The view is byte-identical to glas.sh; the form alone is fine. Rule 12 in project rules; fix owned
by W3. *Superseded 2026-09-11 (rule 12): W4 bisected the crash to the SSH Key row's accessibility
label, not to the nested sheet; nested sheets are allowed. The sheet is presented at
`ServerFormViews.swift:621` today.* The engine reached the test VM from the iOS simulator through
key exchange to the host-trust prompt, so the simulator is not subject to the Mac's Local Network gate.

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

**Read again on 2026-10-17:** Xcode 27.2 (27B5019j) is still the toolchain, its compiler Swift 6.4;
the Mac runs macOS 27.2 (26B5112a). `Package.swift` is tools version 6.2 with the Swift 6 language
mode, and `GlassTerminal` and its tests default to main-actor isolation
(`.defaultIsolation(MainActor.self)`). The app target sets `SWIFT_VERSION = 6.0`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_STRICT_CONCURRENCY = complete` and approachable
concurrency. Simulator testing is on iOS and visionOS 27.2 runtimes since 2026-10-14: the ⚡ hold
passed on an older simulator and did nothing on the owner's iOS 27.2 phone, where the library's
SwiftUI-drawn ⚡ carries no accessibility identifier
(`tasks/2026-10/2026-10-14_all-windows-agents-clipboard.md`).

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
- **Terminal renderer** (*corrected 2026-10-17*; this line said Metal on the Mac): Metal on iPhone and
  iPad, Core Graphics on Vision Pro (`SwiftTermRendererPreference.platformDefault`,
  `Sources/GlassTerminalEmulator/SwiftTermHostView.swift:27`, applied only in the UIKit host), and an
  iPad under Scale draws with Core Graphics too (D75). The Mac draws with SwiftTerm's Core Graphics: its
  `TerminalView` starts with Metal off and nothing in the Mac host turns it on (`setUseMetal` is called
  only in the UIKit section, `SwiftTermHostView.swift:3087`/`:3104`).

## Release and hosting, 2026-09-25 (D38, D39)

**Built 2026-09-27 (`a1c07ec`, `8ddb1eb`); never run.** No release has been made and the site has
not been deployed (`activeContext.md`, 2026-10-12). Mac releases: Developer ID + notarization + Sparkle
(macOS-only dependency), feed `https://glasspowertools.com/appcast.xml`, made by
`Tools/Release/release-mac.sh` (the feed entry by `Tools/Release/appcast.py`, into
`site/static/appcast.xml`). The entitlements read `$(GPT_APS_ENVIRONMENT)`, `development` in
`Config/Identity.xcconfig`; the script archives with `production` and refuses a build without it, an
empty `GPT_SPARKLE_PUBLIC_KEY`, a missing Developer ID certificate or notarytool Keychain profile, or a widget not signed into the
app's App Group. Still the owner's: the Sparkle key (account `GlassPowerTools`), a Developer ID profile carrying the
CloudKit container, App Group and Keychain group, the CloudKit schema deployed to production, the first run,
and deploying the site (inventory B-R1–B-R4). The Developer ID certificate is in the Keychain (seen 2026-10-18; D38).
iOS, iPadOS, visionOS: TestFlight, then the App Store (D38; no tooling yet). The site is static:
`Tools/Site/build_site.py` builds `site/` into the ignored `_site/` and fails on a broken link or
anchor; where and how it is hosted is kept out of this repository (private infrastructure notes).
Procedure: `Documentation/BUILDING.md`, "Releasing the Mac app" and "The website".

## Dependencies, 2026-09-27

Every dependency is pinned to a revision in `Package.resolved`; Xcode's copy must match it
(`Tools/Packages/sync-xcode-pins.py`, `PackagePinAgreementTests`; the two files agreed when read on
2026-10-17). Notable versions (re-read 2026-10-17): swift-nio **2.104.0** and swift-log **1.16.1**
(taken 2026-10-12, 7116d9b), swift-nio-ssl 2.37.5, swift-crypto 4.5.2, BigInt 6.0.1, SwiftTerm
**1.20.0** (exact, D48; its build-tool plugin needs `-skipPackagePluginValidation` for `xcodebuild`),
swift-markdown 0.9.0 (exact), Sparkle 2.10.0 (exact, macOS only, D38), SwiftTreeSitter 0.25.0,
tree-sitter 0.25.10, postgres-nio 1.33.1, mysql-nio at the fork's recorded revision. Vendored: Citadel
`ae8562f`, swift-nio-ssh 0.3.7 (`6acaa1a`) with local patches including upstream's fix for
CVE-2026-43798 (`Packages/swift-nio-ssh/PATCHES.md`, N8, 2026-10-12), RDPKit 0.3.1 (`2032fdb`).

**Watching for newer releases (D48, 2026-10-07):** `Tools/Packages/check-updates.py` reports what is
newer, with release notes, commits and anything to review (new plugins, binary targets, unsafe flags,
dependencies, licence changes, major versions); `--test NAME` tests the app against a release in a
temporary worktree. A LaunchAgent (`Tools/Packages/install-weekly-check.sh`) runs it Mondays at
08:00 with `--test newer`; reports in `~/Library/Logs/GlassPowerTools/`. It never changes a pin.
First survey: 8 of 30 pins behind (swift-log 1.16.1 and swift-nio 2.104.0 allowed as declared, and
since taken; the rest indirect, including tree-sitter 0.27 and swift-crypto 5 below).

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
  blocks the runner. Tunnel through loopback for live SSH tests (`ssh -N -L 2223:localhost:22`, then
  `GPT_SSH_TEST_HOST=127.0.0.1 GPT_SSH_TEST_PORT=2223`; not 2222, which Citadel's own tests bind).
- A dead SFTP/SSH connection under Citadel surfaces as NIO `ChannelError.ioOnClosedChannel` or `.outputClosed`.


## Driver errors, Local Network and the locked Mac, 2026-10-13

- **The test runner is a ready-made Local Network denial.** Lacking the permission, it shows exactly what a denied
  app sees: connecting to a machine on the local or virtual network fails at once with EHOSTUNREACH ("No route to
  host", errno 65) from the SSH engine, MySQLNIO and PostgresNIO alike. That is how `GlassLocalNetworkAccess` was
  measured. A refused port is errno 61.
- **PostgresNIO 1.33 redacts its connect errors.** `PostgresConnection.connect` throws `PSQLError`, whose
  `description` is a fixed generic sentence and whose `localizedDescription` is "PostgresNIO.PSQLError error 1".
  The detail is in `String(reflecting:)`, `serverInfo[.message]` and `underlying` (a `NIOConnectionError` for
  transport failures, holding `dnsAError`/`dnsAAAAError` and `connectionErrors`). The older query API
  (`connection.query(_:_:)` returning `EventLoopFuture`) throws `PostgresError`, which reads well. GlassDBKit
  converts at connect (`PostgreSQLEngine.connectFailure`).
- **MySQLNIO** throws NIO's own errors for transport failures: `IOError`, and `SocketAddressError.UnknownHost`
  for a name that does not resolve. Its server refusals (`MySQLError`) read well.
- **Live database tests against the test VM:** tunnel its ports to loopback (for example
  `ssh -N -L 15432:localhost:5432`) and set `GPT_DB_TEST_HOST=127.0.0.1` with the port (`GPT_DB_TEST_PG_PORT`).
  A wrong-password test needs no credentials.
- **A locked Mac fails about 23 terminal tests** with EPERM, "mktemp failed" or `cannotCreateTemporaryFile`:
  files written with complete protection cannot be created or read while the screen is locked (B-X27). Check
  `CGSSessionCopyCurrentDictionary` → `CGSSessionScreenIsLocked` before blaming a change.

## System integration facts, 2026-10-13 (D72)

- **Services that show without being switched on:** declare them as Ghostty, iTerm2 and CotEditor do (read from the
  installed apps): `NSRequiredContext = {NSTextContent: FilePath}` and `NSSendTypes = [NSFilenamesPboardType,
  public.plain-text]`.
- **Content types:** `.command` is `com.apple.terminal.shell-script`, and `.sh` is `public.shell-script`. Both
  conform to plain text.
- **New macOS extension targets** in the hand-written project: `GlassPowerToolsFinder` (Finder Sync) and
  `GlassPowerToolsQuickActions` (an action extension, `com.apple.services`,
  `NSExtensionServiceAllowsFinderPreviewItem`). Both are sandboxed, use the team App Group (`GPT_WIDGET_GROUP`), and
  are embedded on the Mac only. The release script must sign them (B-R2). Two more followed the same evening, also
  Mac-only, sandboxed and on the team group: `GlassPowerToolsShare` (`Share/`, Share ▸ Send to a Machine, a37a981;
  it holds no credential and connects to nothing — the app sends the files) and `GlassPowerToolsFiles`
  (`FileProvider/`, the D72 phase 5 spike, 12f7e63: links `GlassSSHTransport`, 31 MB, also signed with the Keychain
  group; embedded but inert, no domain registered — `tasks/2026-10/2026-10-13_file-provider-spike.md`).
- **App Intents:** every intent in `GlassWidgetData` goes into the app's and the widget extension's metadata.
  Check `Metadata.appintents/extract.actionsdata` after a build. App Shortcuts live in the app target: all ten
  allowed are used (`App/GlassPowerToolsShortcuts.swift`, counted 2026-10-17), so a new one replaces another.
- **Controls:** a control template has no branches (`ControlWidgetTemplateBuilder`), so one intent per control.
  Controls exist on macOS 26 and iOS 18, not visionOS.
- **`swift build` compiles only the Mac:** code under `#if os(iOS) || os(visionOS)` is checked only by the
  `xcodebuild` builds for those platforms.

## Platform facts measured 2026-10-14 to 2026-10-17 (D74–D78)

**AppKit and SwiftUI windows on the Mac** (D77; `tasks/2026-10/2026-10-16_additive-sidebars.md`, measured on macOS
27.2 with probe apps, because animations don't run inside `swift test`):
- `NSSplitViewItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings` does what its header promises for
  a SwiftUI split view in a plain `NSWindow`, and **not in a SwiftUI `WindowGroup` window** (`AppKitWindow`, content
  an `AppKitWindowHostingController`): AppKit grows such a window by raising its minimum width, so it grew to the
  right only and never shrank. Setting the window's frame does work there, so the app moves it. A test or probe
  that uses a plain window does not cover a window scene.
- A minimum size SwiftUI holds on a window's whole content stops AppKit growing the window for a sidebar; on the
  detail column it does not.
- One toolbar click flips `isCollapsed` three times; resizing the window inside the KVO change left the sidebar
  laid out at no width (move on the next main-queue turn). A collapsed sidebar's view still reports the width it
  opens to.
- Opening, AppKit lays the sidebar out at full width and draws the window inside the call, before it slides the
  sidebar in and sends KVO; `.prior` arrives first.
- The split divider is an `NSSplitDividerView` (0.5 pt) beside the panes. Hidden, AppKit shows it again when the
  sidebar reopens; made transparent, it stays so. The split view itself takes the drag.
- A toolbar item is never narrower than 36 pt.
- A shell process cannot capture the screen; a probe app can photograph its own window with
  `CGWindowListCreateImage` reached through `dlsym`.

**Terminal scale** (D75; `tasks/2026-10/2026-10-16_terminal-resize-and-scale.md`, SwiftTerm 1.20.0):
- Setting SwiftTerm's font calls `resetFont()` → `resize(cols:rows:)` → `softReset()`, and cell height is whole
  points, so a font that fits the window would re-grid and soft-reset at every step: scaling the drawing is the way.
- AppKit gives a view under scaled bounds the scale it is shown at (`contentsScale` 2 × 0.504 = 1.008), so Mac text
  stays sharp. `wantsDynamicContentScaling` exists on visionOS only.
- SwiftTerm's iOS Metal renderer draws at the screen's scale whatever the view's, so a scaled iPad terminal was soft;
  Core Graphics with `contentScaleFactor` = screen × shown scale (to 1/16) is sharp.
- iPadOS 27.2 (simulator, Windowed Apps): no request sizes a window. Raising `sizeRestrictions.minimumSize` grows
  one, when it changes; a smaller maximum never shrank one. `windowIdealSize`, `windowIdealPlacement` and
  `defaultWindowPlacement` are unavailable on iOS, and no iOS API holds a scene's shape
  (`UIWindowSceneGeometryPreferencesIOS.h` has only orientations). Not tried on an iPad device.
- Vision Pro: `requestGeometryUpdate(.Vision(size:resizingRestrictions: .uniform))` holds a window to its shape;
  SwiftUI has no aspect lock for a window.

**Vision Pro** (D74 and the headset terminal; `tasks/2026-10/2026-10-14_all-windows-mac-layout-headset.md`):
- An app is never told where a person looks. Every look effect is a system hover effect; effects in one
  `HoverEffectGroup` show together, and a member left at the default `.activatesGroup` starts the group.
- A pinch is touch type `direct`, a trackpad `indirectPointer`. SwiftTerm's iOS edit menu (`UIMenuController`)
  never shows on visionOS.
- tmux 3.8 turns `mouse` on with no configuration (a private server started with `-f /dev/null` reports it), so a
  drag goes to tmux unless the app stands in the way.
- The visionOS simulator cannot drive looks, the trackpad or a held SwiftUI menu (the runner turns a hold into a
  tap); those are checked on the headset.

**iPhone and iPad, iOS 27.2** (`tasks/2026-10/2026-10-14_all-windows-agents-clipboard.md`): a toolbar's plain
button is drawn natively, so SwiftUI gestures on it never fire, and the library's SwiftUI-drawn ⚡ carries no
accessibility identifier; Metal drawing is invisible to `layer.render` and visible to `drawHierarchy`.

**3D** (D78; `tasks/2026-10/2026-10-16_3d-models.md`, SDK 27.2): `Model3D` and `PreviewApplication` are visionOS
only; `RealityView` with camera controls is macOS 15 / iOS 18 / visionOS; `quickLookPreview` is everywhere.
RealityKit picks the loader by file extension. Its camera starts inside the model until `cameraTarget` is set,
and the orbit camera frames its target by height (about 45% of the view), so the viewer aims at an unseen sphere
around the model. Vision Pro's Quick Look opens USDZ and Reality, not a bare USD layer. `Model3D` with
`scaledToFit3D()` drew nothing visible in a window. The Mac's Quick Look has USD extensions, none for `.reality`.
Not yet seen: the Mac viewer in the running app, AR Quick Look on a phone, the headset.

**Logs to read after the owner tries something:** `com.glasspowertools` / `sidebar` (each sidebar move and the
width held); `sh.glas` / `terminal-drop`, `terminal-selection`, `terminal-paste`, `terminal-model-link`. Use
`/usr/bin/log show --predicate 'subsystem == "…" AND category == "…"'` — zsh's builtin `log` shadows it.

## Device names (D81, 2026-10-17)

- `UIDevice.name` on iOS and iPadOS 16 and later, and on visionOS, answers with the kind of device ("iPhone", "Apple Vision
  Pro") unless the app has Apple's `com.apple.developer.device-information.user-assigned-device-name` entitlement,
  which Apple grants on request. Adding the key before the App ID has it breaks signing. On the Mac,
  `SCDynamicStoreCopyComputerName` gives the computer name with no entitlement (`GlassDeviceName.system`).

## The macOS screenshot VM (2026-10-17)

The website's Mac pictures are taken in a headless macOS 26 VM, never on the owner's screen (his ask: "screenshots and
all using the new sandbox"). The driver is Glass Project's, itself AutoPaper's: `Tools/Screenshots/macvm/macvm.sh`
(tart; Cirrus Labs' `macos-tahoe-base` image; VMs `glasspowertools-mac26`, `-clean` never booted, `-run` throwaway),
`vmtool.swift` compiled inside the VM, `wallpaper.py`, and `Tools/Screenshots/site_shots.sh`. Its key, Debug build and
raw captures are in the git-ignored `.scratch/`. Observed:
- **The app runs in the VM ad-hoc signed, without entitlements** (`macvm.sh build-app`: Debug, `CODE_SIGN_IDENTITY=-`,
  no `CODE_SIGN_ENTITLEMENTS`, no hardened runtime). A `--ui-testing <uuid>` run uses none of them: its catalog and
  storage are a folder of its own and it never attaches CloudKit. The sidebar says "Not synced on this build".
- **The screen starts at 1024 × 768 points**, whatever `tart set --display` says; `vmtool display set 1920x1200` gives
  1920 × 1200 at 2x (`site_shots.sh` sets it each run).
- **A capture from SSH raises "com.apple.sshd-session is requesting to bypass the system private window picker"**,
  although setup quiets the notice for `sshd-keygen-wrapper`; pressing its Allow (`vmtool press UserNotificationCenter
  Allow`) clears it, and `site_shots.sh` presses it around every capture.
- **A window-only capture (`screencapture -l`) draws the glass flat**, as over nothing (an opaque gray sidebar). The
  site's pictures are the screen in the window's frame (`-R`), cut out by the window-only capture's outline, over a
  desktop picture in the site's colours, so the glass shows a wash of it and nothing of Apple's wallpaper.
- **Window titles the shots find:** the library "All Connections"; `terminal` "alpha"; `database` "orders" (the open
  table); `diagram` "main"; `desktop` "bravo"; `editor` "ShippingAddress.swift".
- **The demo desktop says "The remote session is not ready."** on a Mac: as its window becomes key it sends the Caps
  Lock state, which its never-connected session refuses (as a real one should). `site_shots.sh` presses the banner's
  Dismiss.
- **The glass sidebar's own rim stays**: a 2-pixel highlight at its edge, brighter than both sides in dark and light
  alike, in terminal and database windows. AppKit's divider and our hairline (`separatorColor`, darker in light mode)
  are gone from both (D77 follow-ups, a100d04 and 929a183); a desktop window's left edge shows only the window
  border, the same as its right.
- The device pictures come from the simulators (`Tools/Screenshots/device_shots.sh`).

Added 2026-10-18, at the owner's ask ("78% transparency with about 50% medium glass. close the connections window so
users can see why this was built … all 4 services for each visionOS and macOS … session transfer with tmux and
workgroups"; then "run btop or something for the terminal examples"):
- **Every picture's glass is Opacity 78%, Glass 50%, Medium** (`--demo-glass 0.78,0.5,thin`; the third value is a
  `GlassLayerMaterial` raw value, `thin` being Medium). Shown both, he chose Opacity 78% over 22%: at 22% a terminal's
  text was faint over the simulator's bright room. A desktop's Opacity would fade its remote screen (W28), so the
  demo applies only its glass unless `--demo-fade-desktop`.
- **`--demo-close-connections`** closes the Connections window 5 s after the surface opens (`GlassDemoModeTask`,
  `dismissWindow()` from the library's own environment), so the glass shows the room or the desktop picture.
- **The terminal pictures run a btop-style screen** (`--demo-open btop`, `App/GlassDemoBtop.swift`): the demo
  session's resize sink hands the window's rows and columns to the drawing (`.demoScreen`), so it fits a Mac window,
  the headset and the iPhone, as a real full-screen program redraws. btop's default theme, its boxes lifted to read on
  glass; its "block" graphs, as braille read as faint dots at these sizes.
- **Active and Workgroups** (`active`, `workgroups`): made-up tmux sessions named and described by the real
  `runningDetails`, held against Active's refresh (`demoHoldsRunningSessions`); a saved workgroup whose machines are
  given in-memory terminal records, because a seeded host has only its catalogue entry (without them every row reads
  "Missing SSH connection"). The Mac's workgroup detail cuts its table off at 1440 × 900, so the site uses the Vision
  Pro picture.
- **Four windows at once works on the Mac, not in the visionOS simulator.** `workspace` opens a terminal, a
  database, a desktop and the editor one at a time; `site_shots.sh` tiles them on the VM's screen and cuts the picture
  out by all four outlines. On the headset the default opens each window in front of the last, and
  `defaultWindowPlacement` with `.leading`/`.trailing` turns the side windows toward the viewer and brings them close,
  so they ran off both edges of the simulator's fixed view; the placement's size was not honoured either. Tried and
  removed; the Vision Pro pictures are one service each.
- `macvm.sh start` once said "no VM named glasspowertools-mac26" while the simulators were busy; `tart list --quiet`
  listed it a moment later and a retry started it.
- **Glass shows whatever is behind it, so the VM's screen is cleared first** (`site_shots.sh`): desktop widgets hidden
  (`com.apple.WindowManager StandardHideWidgets`), a leftover "quit unexpectedly" report pressed OK, and notification
  banners closed before every capture (`macvm/close-banners.applescript`, each banner's Close action; macOS 26 posts
  "See what's new in macOS Tahoe" and it came back after Notification Center restarted). All three had shown through
  or over pictures. The Dock is hidden only for `workspace`, whose tiles reach the screen's bottom.
- **The crash behind that report** was the app's, in the database window's policy (0.4.476, 5c567dd): a re-apply
  set window properties to their own values, which still notifies SwiftUI's hosting view.

