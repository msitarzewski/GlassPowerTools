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
  GlasSecretStore at `/Users/ann/Developer/GlasSecretStore/`, an old path, confirming they
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
| SSH / SFTP / tunnel integration tests | `192.0.2.6` (Parallels scratch VM, Linux 7.0.0-29-generic) | `michael` | ED25519 key at `~/.ssh/scratch_vm` | `echo ok` over BatchMode SSH; `Subsystem sftp /usr/lib/openssh/sftp-server`; no `AllowTcpForwarding` restriction |

Environment for the gated tests: `GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=michael
GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/scratch_vm`. Never record key material or passwords here.

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
