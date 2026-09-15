# September 2026

- 2026-09-10: Glass Power Tools created as a project. Decision to merge glas.sh, glassdb and glassDT
  recorded with its evidence and its accepted cost. Memory bank, project guide and the staged
  [merge plan](2026-09-10_merge-plan.md) written.
- 2026-09-10: Stage 0 complete. The editor is built in as a library with its interface last; data
  migration is not a constraint; capability order is SSH and SFTP, databases, remote desktop, editor;
  the floor is 26.0 everywhere on `arm64` only; and the layering system is foundational rather than a
  later pass. No code, no project structure, no build. Stage 1 is unblocked.

- 2026-09-10T17:32:27Z: Session handoff written for compaction. Stage 0 complete, Stage 1 unblocked, no code yet.

- 2026-09-10: Memory bank reconciled with the workspace at the start of a fresh session. The project
  path was corrected from `~/Software/glasspowertools` to `~/Software/glass/GlassPowerTools` in the
  active context, decisions and merge plan. A workspace layout section was added to
  [technical context](../../techContext.md): the six sibling inputs, the two siblings that are not
  inputs (`glassdb-connection-library`, a stale glassdb snapshot, and `docs`, July evaluation
  reports), and per-sibling Git state. Sizes, entitlement groups and deployment targets re-measured
  at the new location and unchanged. Still no code, no project structure, no build.

- 2026-09-10: The July 2026 audit reports in `../docs` were checked against current source rather
  than assumed stale. Most findings are fixed: no `.acceptAnything()` or `SSHAlgorithms.all` remains
  in any live source, `SSHHostTrustKeychainStore` is wired into glas.sh and glassdb, MySQL builds a
  real TLS configuration, recordings carry file protection, and `NSFaceIDUsageDescription` is
  present. Two remain unresolved and are now a Stage 2 checklist in
  [technical context](../../techContext.md): keystroke recording consent in
  `SessionRecorder.recordInput`, and one-click AI execution trusting the model's own `riskLevel`.
  Both live in glas.sh, which Stage 2 moves in without rewriting.
- 2026-09-10: `glassdb-connection-library` archived to `../glassdb-connection-library.zip` by the
  user and the directory removed, after being proven a strict subset of live glassdb. One of the two
  documented traps is now gone; `../docs` stays until Stage 2 closes the two open findings.

- 2026-09-10: Project model decided by the user — one multiplatform target, hand-maintained
  project with synchronized folders, following glas.sh rather than glassDT's XcodeGen template.
  Recorded in decisions, system patterns and the merge plan.
- 2026-09-10: [Stage 1 planned](2026-09-10_stage-1-shell.md). Found while planning: all three apps
  share `<App Group>/GlassHostCatalog/hosts.json`; layering *views* are shared but layering *state*
  has three defaults; GlasSecretStore is in three revisions with the only RDP credential store
  sitting uncommitted in the local working tree; GlassConnectionKit has no version control. Three
  pre-steps and six decisions await the user. No code yet.
- 2026-09-10: **BUILD begins.** User approved Stages 1–5 end to end with parallel agents and
  function/unit/UI/security testing. P3 ran: GlasSecretStore 90 tests passed, GlassConnectionKit 21
  passed (`swift test`, macOS host). Package skeleton laid down; the three local packages resolve in
  one Swift 6.4 graph. Stage 1 fanned out to three workers with exclusive ownership: project file
  (`GlassPowerTools.xcodeproj`, `App/`, `Platforms/macOS/`, `UITests/`), `Sources/GlassLayers`,
  `Sources/GlassShell`. Each writes its own task note here. D1 Git actions still await the user.
- 2026-09-10: On the user's instruction: GlasSecretStore's uncommitted RDP credential work
  committed (`aa1b3f1`), GlassConnectionKit put under version control (`d48a5ff`), this project
  initialised on `main`. The one-module-per-capability carve for Stages 2 and 3 approved; see
  [groundwork](2026-09-10_stage-2-3-groundwork.md) and [decisions](../../decisions.md).
- 2026-09-10: Carve refined on the user's instruction: engines (`GlassSSHTransport` extracted from
  glas.sh with tunnel and SFTP APIs for every capability; `GlassDBKit`; RDP/VNC kits) are
  first-class shared modules; each app's UI/session layer is one capability module. Capabilities
  never depend on each other. Recorded in [decisions](../../decisions.md).
- 2026-09-10: **Stage 1 verified and committed** (`fe20956`). 40 unit tests; three platforms
  build; UI suites macOS 5/5, iOS 5/5, visionOS 4 + 1 reasoned skip (Appearance toggle press on
  visionOS being adapted); 11 security findings fixed. macOS UI root cause: `tap()` does not drive
  SwiftUI under Xcode 27 beta, `click()` does — no product change. Device installs and the 1.8
  proof wait on the user's provisioning step. Notes: `2026-09-10_stage-1-{project,layers,
  shell-module,integration,security-review,macos-uitests}.md`.
- 2026-09-10: **Stage 2 started.** W1 extracts `GlassSSHTransport` (API surface first), W2 moves
  glas.sh into `GlassTerminal`; real SSH test host recorded in technical context. Plan:
  [Stage 2 note](2026-09-10_stage-2-ssh-terminal.md).
- 2026-09-10: **Stage 2 engine and move landed** (`6e5ffe6`…`5f12575`): `GlassSSHTransport` with
  61 tests and a clean security review; glas.sh moved in as `GlassTerminal` with 338 tests.
  **1.8 proven on the iPhone** after the user's Xcode signing step; macOS signs without override.
  Defect found from the device screenshot: one row per service instead of per host — shell
  consolidation in progress. Wave 2 (W3, integration, consolidation) running. Stage 3 and 4 notes
  drafted.
- 2026-09-10: **Stage 2 W3 landed** (`ded6ad2`): `ConnectionManagerView` (3,697 lines) deleted
  after re-homing workgroups, Tailscale, server actions and local terminal; layering proven on
  the connection panel sheets and visionOS terminal chrome; settings merged (pending three shell
  hooks); user requirement "choose a key file" delivered with `SSHPrivateKeyImport` and
  ssh-keygen-fixture tests. 347 tests, one inherited failure now being root-caused by a narrow
  worker. Consolidation worker adding the hooks and the visionOS row fix; integration worker
  driving a real session.
- 2026-09-10: The one failing moved test root-caused (`46e63e6`): glas.sh's unmerged PR builds a
  multi-line workgroup startup command that its own committed ticket guard rejects. Fixed with a
  single-line group command; 348 terminal tests all pass. The same fix applies to glas.sh's PR
  branch — for the user to carry over.
- 2026-09-10: **One row per host** (`7ebe746`): same-machine catalog records grouped in the shell
  with every service icon; visionOS row fixed; three capability hooks added; 29 shell tests. W3
  wiring the terminal's pages/toolbar/actions and moving shell services; integration driving a
  real session.
- 2026-09-11: Session paused for a terminal restart at `bf88fc9` (tree clean). Stage 2 built and
  unit-verified (461 tests); UI green on iOS/visionOS, four macOS failures and four integration
  defects open — listed in the active context with owners. Local Network grant still needed.
- 2026-09-11 — Resumed after terminal restart. Local Network grant confirmed; engine real-host suite 5/5 after one fix (`list` omitted `.`/`..`), engine module 62/62 — [transport note](2026-09-10_stage-2-transport.md). Read-only close-out review recorded — [close-out review](2026-09-10_stage-2-closeout-review.md); cleanup queued to W4. W4 working the macOS causes and integration defects — [W4 note](2026-09-10_stage-2-w4.md) (written by W4).
- 2026-09-10 evening — W5: system-wide tag field (kit `GlassTagField`, shell vocabulary, host editor); kit 51/51, package 461/25, macOS + iPhone UI green — [shell tags](2026-09-10_shell-tags.md). Coordinator: macOS App Sandbox removed; `GlassLayeredPanel(role:)`; kit `sidebarActions` + adaptive `GlassSettingsSections` (all uncommitted; wiring with W4).
- 2026-09-11 — W6: host-level address (kit `HostProfile.address`, shell editor/detail/grouping, capability hooks, terminal form read-only address + write-back, sync); package 469/28, iPhone UI 7/8 (VM down), macOS XCUITest blocked by automation mode — [host address](2026-09-10_host-address.md). Third /Applications build installed.
- 2026-09-11 — W7: address collected on the host before any service setup (no field in the terminal form), Add SSH Key as a HIG sheet, Services row overflow menu; package 472/28, macOS and iPhone UI suites green with the real host — [service setup and key window](2026-09-11_service-setup-and-key-window.md). Rules 12 superseded, 15 added.
- 2026-09-11 — W9: library row stripped to icons + a wordless split connect control (play connects every service, chevron picks one), Heroicons circle-stack vendored for the database, Delete moved to the context menu and the edit sheet, detail action bar full width; package 485/30, macOS 14/14 and iPhone 13/13 with the real host — [row connect and icons](2026-09-11_row-connect-and-icons.md).
- 2026-09-11 — App icon rebuilt as an Icon Composer document with per-appearance artwork (light/dark authored, clear derived); SVG-first attempt kept in history. Shipped in 0.2.60 — [app icon](2026-09-11_app-icon.md).
- 2026-09-12 — Stage 3 planned from two full read-only surveys of glassdb (kept under `surveys/`): [Stage 3 plan](2026-09-12_stage-3-database-plan.md). Five decisions need the user, chiefly the tunnel becoming the host's own SSH service, where SQLite lives, and parity vs parity-plus.
- 2026-09-12 — **Stage 3 waves 1–2 built and proven against real servers.** Engine moved as `Sources/GlassDBKit` minus its tunnel manager, **keeping swift-crypto 4.5.2** so the survey's top risk dissolved — [kit move](2026-09-12_stage-3-kit-move.md). Floor stays 26.0: exactly one API, at macOS **26.1** not 27.0, guard extracted to `GlassLayers` (D12) — [floor sweep](2026-09-12_stage-3-floor-sweep.md). D7's forward brokered by the shell so capabilities never import each other — [shell forward](2026-09-12_stage-3-shell-forward.md). glassdb's app files in as `Sources/GlassDatabase` with the Database tab live, D14's trust prompt, and read-only enforced **on the connection** because five write paths bypass `executeQuery` (D15) — [capability](2026-09-12_stage-3-capability.md). Real MySQL 8.4.11 + PostgreSQL 18.6 on the VM, write-protected fixture and disposable scratch per engine — [VM databases](2026-09-12_stage-3-vm-databases.md). Package **592 / 45**, 12 gated live tests, app builds on three platforms.
  **Found only by running against a real server and a realistic least-privilege account:** two independent PostgreSQL foreign-key defects — an owner-scoped view returning nothing, and composite keys returning a cross product asserting relationships that do not exist. Both fixed. **Open:** D13 (no way to trust a self-signed database certificate — needs a CA-only mode *and* a CA import), and two unexplained ~10s tunnel failures, instrumented with a three-signature discriminator table and a counter baseline. Three hypotheses proposed, all three refuted by measurement.
- 2026-09-12 (afternoon) — **Stage 3 shipped to `/Applications` (0.3.56 → 0.3.67) and corrected in use.** Closed the two unexplained ~10s tunnel failures: the SSH forward dropped a **server-first** protocol's opening bytes, because the channel was wrapped after the open rather than inside the initializer — [note](2026-09-12_ssh-forward-server-first.md). Every test passed it, including the live tunnel test. UI and record-editor validation work, including a `tinyint` misread as boolean that **would have saved 0 over real data** — [note](2026-09-12_ui-and-validation.md). Package 615/48; **nothing committed**. Remaining Stage 3 work **re-planned against the code that now exists**, with `file:line` anchors, in the [plan](2026-09-12_stage-3-database-plan.md): two original estimates were wrong (AI on iOS already done; the audit viewer has no store to view). Rules 22 and 23 added, and decisions D16–D17.
- 2026-09-12 (evening) — **Stage 3 R1–R8 closed**, three workers in parallel: [SQL drafts](2026-09-12_sql-drafts.md), [rows and audit](2026-09-12_rows-and-audit.md), [certificate trust](2026-09-12_certificate-trust.md). 711 tests / 61 suites, **no known issues**. R6 turned out to be *one implementation pasted twice* (650 lines deleted), not two implementations. R7 needed a capability-level test to distinguish "the engine can" from "a saved record reaches it". Remaining work is a device and UI pass, not code.

## 2026-09-13 (later) — GlasSecretStore absorbed; D23; the last standing UI failure closed

[Task note](2026-09-13_secretstore-absorbed.md) · [D23](../../decisions.md)

`Sources/GlasSecretStore` is in-repo (15 source + 9 test files, no import changed). Answering the
open "should pinned host keys sync?" question exposed that host trust did not work at all: the trust
prompt's four write paths were on a configuration `validateMobility` refused. D23 makes host trust
eligible, moves the eligible set onto `SecretStoreConfiguration.synchronizableServices`, and gives
pins one configuration name.

`testCollectionsAreChipsAndFeedTheSystemWideVocabulary`, failing since Stage 2, is fixed — two stale
test assumptions, no product defect.

**Verified by running:** package 946 tests / 90 suites (3 skipped with a measured reason); macOS,
iOS and visionOS app builds; 5 real-host SSH tests; 21 live database tests; the macOS database UI
suite 7/7 against real MySQL 8.4.11 and PostgreSQL 18.6; and the real-host terminal UI test driving
the D14 trust prompt for the first time.

## 2026-09-13 (later still) — visionOS design pass 1

[Task note](2026-09-13_visionos-design-pass.md)

Native visionOS HIG on the Glass language already in place. The premise that the source apps carry
the spatial vocabulary was measured and found false — HIG conformance is new work everywhere; what
they did carry is `GlassLayers`, and it stays. Two faults were the app overriding the platform: a
`Material` painted across the window covering visionOS's real glass, and the ornament inset applied
when no ornament is shown. Plus ornament toolbar, gaze-scale metrics, hover, type scale, empty state
and sheet sizing.

macOS UI 25/25 throughout — no Mac metric moved. **Unverified on the headset**, which was locked for
the whole pass.

## 2026-09-13 (evening) — 0.3.81 → 0.3.99, driven from the running app

[Design pass](2026-09-13_visionos-design-pass.md) · [Test pollution](2026-09-13_test-pollution.md) ·
[D24, D25](../../decisions.md)

The user ran the builds and reported what they saw; nearly everything here was found that way.
Workgroups restored to the library sidebar as a contributed panel; the family's sidebar toolbar
arrangement copied from glassdb rather than reinvented (D24); deleting a machine now deletes what its
capabilities stored (D25); UI tests stopped writing into the real saved-server list, and the 122
entries that had accumulated there were cleaned out.

948 tests / 90 suites. **Open:** the glass is over-transparent and needs a look decision; the
Tailscale panel; SSH key records over CloudKit; abandoned test defaults suites.

## 2026-09-14 — Stage 4 W1: the engines moved

[Stage 4 and 4.5 plan](2026-09-13_stage-4-plan.md)

`Packages/RDPKit` (vendored fork, LICENSE + patch record + capability ledger intact, `Examples/`
left behind), `Sources/VNCKit`, `Sources/GlassRDPTransport`, `Sources/GlassVNCTransport`,
`Documentation/ThirdPartyLicenses/`, and a new root `THIRD-PARTY-NOTICES.md`.

**Proven, not reasoned:** `Package.resolved` is byte-identical after the move — no new package
entered the graph, swift-nio stays 2.102.0 and swift-nio-ssl 2.37.4. RDPKit's two `exact:` pins were
relaxed to `from:` and the change recorded in `GLASSDT-PATCHES.md`, so a nested package no longer
freezes NIO for the SSH and database stacks.

**Tests: root package 985 / 96 (was 948 / 90), RDPKit 1014 in its own package — 1,999 total.**
macOS, iOS Simulator and visionOS Simulator all build. ZRLE decodes real byte vectors through the
system zlib, so the restated `linkedLibrary("z")` is verified rather than assumed.

Also: the glass default moved to `.regular` (sidebar weight) with a one-time adoption for untouched
stored state, and the three `.ultraThin` literals in `GlassLayerLegacy` now follow the default — an
absent material key is not a user choice. A new test migrates the **real** settings still held by
`sh.glas.app` and `app.glassdb` rather than invented fixtures.

## 2026-09-14 — the remainder planned

[The remaining work](2026-09-14_remaining-work-plan.md)

D26 stages 1–5, Stage 4 W3–W6, Stage 4.5 items 3–8, the carried items and Stages 5–6, each with its
reuse anchor at `file:line` and the precise edits it implies. **Nothing built.**

Measured corrections: D26 needs no identity migration (`EndpointID.rawValue` is already every
capability's record UUID); the database's `ConnectionPersistenceStore` is the seam the other two
capabilities should adopt; stage 1 shrinks stage 2 to Keychain cleanup alone; and the abandoned test
defaults suites are **17,905**, left as empty 42-byte plists by `removePersistentDomain` rather than
by tests failing to clean up.

## 2026-09-14 (evening) — D26 stage 1 seam; D27 and D28

[The remaining work](2026-09-14_remaining-work-plan.md) · [D27, D28](../../decisions.md)

`ServerPersistenceStore` landed (`0eee30e`); the terminal's write path is async because the catalog
is an actor. 1146 tests / 117 suites.

**D27:** servers created by SSH config import and the standalone Add Server form have no host record
and are already invisible in the library; both forms now raise the record behind the scenes.
**D28:** credential usage is derived from the service configuration, never stored in a table — only
SSH keys are shared, and detaching one from the key side has two consequences that must be stated at
the point of choice.

Also swept 35,865 abandoned test defaults plists and 23 test host catalogs from the developer Mac.

## 2026-09-14 (evening) — D27 and D28 planned from a full surface survey

[D27/D28 plan](2026-09-14_d27-d28-plan.md)

Every construction of a saved record enumerated across the three capabilities: **D27 has exactly two
live targets** (Add Server incl. the Tailscale draft, and `ssh_config` import); Tailscale Quick
Connect is transient, and the database and desktop have no link-less path.

Two findings the survey produced that the design did not anticipate: **`RDPFileImporter` has zero
references anywhere in the repository** (212 lines, moved in Stage 4 W1, never wired — the eighth
occurrence of the defect class), and **`normalizeSelectedSSHKey` silently re-attaches the first key
in the library** to any service still set to key auth with no key, so a naive detach would undo
itself later. D28's index already exists ad hoc in two places and gets extracted rather than
rewritten.
