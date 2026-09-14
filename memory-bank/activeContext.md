# Active context

## Merge decided and scoped; nothing built — 2026-09-10

Owner `/root`, state PLAN. The user decided to merge glas.sh, glassdb and glassDT into one
application, Glass Power Tools, bundle identifier `com.glasspowertools`, in a fresh directory at
`~/Software/glass/GlassPowerTools`. This memory bank and `AGENTS.md` are the only contents: **no
code, no Xcode project, no build.** The three source applications remain the working software and
must keep building.

**Authorization so far:** create this memory bank and the merge plan. Building starts on the user's
word. Do not initialise Git, commit, publish, or touch the existing public repositories.

## The four questions are answered

1. **GlassEditorKit is in.** It is a full capability, built in from the start as a library. Its
   *interface* is built last, after the other three. The user has SFTP interface ideas intended to
   make editing shine, so the SFTP surface should be designed with that in mind.
2. **Data migration is not a constraint.** The user is the only user. Declaring the existing App
   Group and Keychain access group is still worth doing because it is free and keeps current hosts,
   but no import path is to be built and nothing blocks on proving it.
3. **Capability order: SSH and SFTP, then databases, then remote desktop, then the editor
   interface.**
4. **One floor: 26.0 on every platform, Apple Silicon only.** `arm64` alone; no Intel slice. The
   floor exists to reach visionOS capabilities, not for tidiness: this project began as a world-class
   SSH tool for visionOS and the rest followed with the same intent. **visionOS leads the design and
   the other platforms adapt from it**, including the shell, the layering system and the library.

## New requirement: layers from the start

The Glass layering and transparency system is foundational, not a later polish pass. It must be in
the shell before capabilities arrive, and it covers window transparency **including title bar
backgrounds**, not only a session canvas. The two surfaces to prove it on first are the **SSH
connection panel** and the **connection detail view**.

This reuses existing work rather than inventing it: the titlebar material already extracted into
GlassConnectionUI and consumed by all three apps, plus glassDT's window frame, canvas backdrop,
opacity and background frost. Read those before writing anything new.

## Session handoff — 2026-09-10T17:32:27Z

The session that created this project ends here for compaction. Everything above is current. To
resume:

1. Read `AGENTS.md`, this file, then `tasks/2026-09/2026-09-10_merge-plan.md`.
2. Stage 0 is complete and nothing blocks Stage 1. Do not reopen the four settled decisions.
3. Begin Stage 1: the application targets, the layering system, the host library and the service
   picker. No capability code moves yet.
4. Before writing any shared surface, read what already exists rather than starting blank:
   `../GlassConnectionKit/Sources/GlassConnectionUI` for the library, detail, settings shell,
   settings slider and titlebar material; `../glassDT/Sources/GlassDesktopUI` for the window frame,
   canvas backdrop, opacity and frost. Move these in; do not rewrite them.
5. The three source applications are inputs only. Nothing in `../glas.sh`, `../glassdb` or
   `../glassDT` is edited, moved or reset by this work.

**State of the working software at handoff:** all three applications build and are installed on the
user's Mac, iPhone 17 Pro Max and Vision Pro. glassDT was worked on heavily on 2026-09-09 and 10;
its own memory bank at `../glassDT/memory-bank/activeContext.md` holds that detail and its open
items.

## Session start — 2026-09-10, relocation reconciled

The project is at `~/Software/glass/GlassPowerTools`, not `~/Software/glasspowertools` as the
previous session recorded. The source applications and shared packages are siblings under
`~/Software/glass/`, so every `../name` reference in this bank and in `AGENTS.md` still resolves.
The stale absolute path is corrected here, in [decisions](decisions.md) and in the
[merge plan](tasks/2026-09/2026-09-10_merge-plan.md); the new layout is recorded in
[technical context](techContext.md).

Re-verified at the new location rather than assumed:

- All six sibling paths resolve, including the two surfaces Stage 1 must read first,
  `../GlassConnectionKit/Sources/GlassConnectionUI` and `../glassDT/Sources/GlassDesktopUI`.
- Every line count in [technical context](techContext.md) is unchanged: 31,393 / 22,244 / 5,573 /
  2,223 / 2,124 / 8,128.
- All three apps still declare `group.sh.glas.shared`; deployment targets are unchanged, glassdb's
  macOS 27.0 included.

Two siblings are new to this bank and are **not** inputs: `../glassdb-connection-library` is a stale
snapshot of glassdb, and `../docs` holds evaluation reports from 2026-07-17. Both are described in
[technical context](techContext.md) so neither is mistaken for current during Stage 3.

Nothing else changed. Stage 0 remains complete, no code exists, and the four settled decisions are
not reopened.

## Project model decided; Stage 1 planned — 2026-09-10

The user approved **one multiplatform application target with a hand-maintained project**, recorded
in [decisions](decisions.md) and reflected in [system patterns](systemPatterns.md) and the merge
plan. Stage 1 is planned in detail in
[the Stage 1 task note](tasks/2026-09/2026-09-10_stage-1-shell.md), grounded in the shared
packages' actual APIs, the three apps' library adapters and composition roots, and where the
catalog and layering state live today (all recorded in [technical context](techContext.md)).

Two findings from that planning need the user, not an agent:

- **`../GlasSecretStore` has 12 uncommitted files including the untracked RDP credential store.**
  It is the copy Stage 1 must build against and the only one with that work. Committing it is the
  user's call (pre-step P1).
- **`../GlassConnectionKit` is not under version control.** Pre-step P2.

## BUILD authorized — 2026-09-10

The user approved the Stage 1 plan and authorized building **Stages 1 through 5 end to end** with
function, unit, UI-automation and security testing, using parallel agents, then a sweep for TODOs
and stubs. Decisions D2–D6 are taken at their proposals (transparent-first layers with frost and
legacy-key migration; reuse glas.sh's iCloud KVS identifier; drop the three URL schemes; display
name "Glass Power Tools"; `GlassEditorUI` waits for Stage 5). **D1 executed on the user's explicit
instruction**: GlasSecretStore committed (`aa1b3f1`), GlassConnectionKit initialised (`d48a5ff`),
this project initialised on `main`. P3 passed: GlasSecretStore 90 tests, GlassConnectionKit 21.
The one-module-per-capability carve is approved. The user notes glas.sh has an unmerged PR; local source is authoritative for this work.

Toolchain observed: Xcode 27.0 (27A5252f), Swift 6.4. Simulators: iPhone 17 family on iOS 27.0,
Apple Vision Pro on visionOS 26.4 / 26.5 / 27.0. Physical: iPhone 17 Pro Max (iOS 27.0), Vision
Pro (visionOS 27.0), Mac (macOS 27.0). One Apple Development signing identity.

Coordinator `/root` owns this file, progress, toc, decisions and the monthly README. Workers own
the directories named in their briefs and write their own task notes under `tasks/2026-09/`.

## Stage 1 modules landed — 2026-09-10

All three workers reported and their output is committed (`7f4d521` shell, `cb8a84b` layers,
`GlassPowerTools.xcodeproj` after). GlassShell 10 tests, GlassLayers 21 tests, iOS and visionOS
simulator builds green, iOS launch smoke UI test green. **macOS is blocked on signing only:** the
iCloud KVS entitlement (D3) needs the iCloud capability enabled once on App ID
`com.glasspowertools` — user action. App Group and Keychain group sign fine on macOS.

## Stage 1 integration state — 2026-09-10, commit `17e79be`

Integration, security review and fixes are committed. Verified: whole package `swift test` 37
passed; iOS, visionOS and macOS (build-time KVS override) all build; iOS smoke UI test passes;
macOS smoke passes when run alone. Simulator screenshots of the library, host detail, service icon,
placeholder connect, favorites, search and Appearance are in the session scratchpad and judged by
eye; visionOS in-test screenshots come out 1×1 (XCUIScreen limitation on the visionOS simulator),
so visionOS visual evidence is the `simctl` shot.

**Open on macOS:** the four `GlassShellLibraryUITests` interaction tests fail because synthesized
clicks do not take effect (keystrokes do; app idles at 0 % CPU; no overlay in our composition; main
window marked Disabled in the AX tree). A worker is finding the root cause — window activation,
beta click synthesis, or a real product defect — with the rule that product code changes only for
a proven defect. iOS and visionOS library suites are re-running after that worker's macOS-only probe
briefly broke their builds.

**Needs the user (both are Apple-account actions the CLI cannot do):**
1. Enable the iCloud capability on App ID `com.glasspowertools` so macOS signs with the KVS
   entitlement as designed (D3); until then macOS builds use `noKVS.xcconfig` at build time.
2. Open the project in Xcode signed in, so automatic provisioning registers App Groups, iCloud and
   the iPhone/Vision Pro devices; device installs and the 1.8 host-inheritance check wait on this.
   On this Mac the group container `group.sh.glas.shared` exists but holds no `hosts.json` — none of
   the three apps has written a catalog here — so 1.8 can only be shown on a device.

## Stage 2 in progress; 1.8 proven — 2026-09-10 evening, commit `5f12575`

**1.8 passed on the iPhone 17 Pro Max and on the Vision Pro** (user screenshots of both; visionOS shows `Michael`, `juliet`, `oscar`; the Vision Pro's catalog already holds `oscar` as one host with two services while the iPhone's holds two records — real data has both shapes). **visionOS defect:** the sidebar row's Connect label wraps vertically; routed to the shell worker. After the user enabled automatic signing in Xcode,
per-App-ID managed profiles appeared (iOS/visionOS: 8 devices; macOS), the app installed on the
iPhone and the Vision Pro, and the user's screenshot shows the existing hosts (`juliet`, `oscar`)
from the shared catalog — no migration. macOS now signs with the real profile and no override.

**Defect exposed by that screenshot (user requirement: "one line per host, multiple icons"):** each
host appears once *per service* — the three source apps each published their own `HostProfile` for
the same machine, and only pairing ever tied them. A shell worker is consolidating same-machine
records into one row with every service icon, presentation-level only (the source apps still read
`hosts.json` by their own IDs until Stage 6).

**Consolidation landed (`7ebe746`):** one row per host with every service icon, on all platforms;
visionOS row fixed (simulator screenshot judged by eye: `juliet` / `oscar`, "Desktop · Terminal",
two icons, icon-only Connect). Root cause recorded: the catalog matches only by endpoint id and
each app publishes its own record per saved endpoint. `hosts.json` is not rewritten; the on-disk
merge is written, tested and unwired until Stage 6. Three `GlassCapability` hooks are in the shell
(settings pages, library toolbar items, per-service detail actions).

**Stage 2 build (`410d0fc`) installed on the iPhone (launched) and the Vision Pro (installed;
launch unconfirmed, device asleep) on 2026-09-10; the Stage 1 sibling worktree is removed.**

**Stage 2 UI suites on `410d0fc`:** iOS 6 passed / 1 skipped (real-host, no env), visionOS
5 passed / 2 skipped (search, real-host), **macOS 4 failed** — detail controls not hittable after
the Stage 2 library additions (capability toolbar items, per-service actions, layered panel wraps,
`Window` scene); no crash reports during the run. Assigned to W3 with the trace. Whole package unit
suite 461/461.

**Stage 2 state:** `GlassSSHTransport` engine complete (61 unit tests, security review clean of
High/Medium and all Low fixed, both July audit items confirmed resolved). glas.sh moved in as
`GlassTerminal` (36,441 lines; 338 tests, one inherited failure; builds on all three platforms).
Wave 2 running with exclusive ownership: **W3** (`Sources/GlassTerminal`: re-home the four features
stranded in `ConnectionManagerView`, layering proof on the connection panel, settings merge,
legacy-toggle warning), **integration** (`UITests/GlassTerminalUITests.swift`: real session against
`192.0.2.6` through the shell on the Mac), **consolidation** (`Sources/GlassShell`,
`UITests/GlassShellLibraryUITests.swift`).

**Still needs the user:** Local Network grant for Ghostty (real-host CLI tests, errno 65); the app
itself may show its own Local Network prompt on first connect — accept it; the Vision Pro
launch (device asleep). `../docs` may be deleted; nothing in it is open.

## Session handoff — 2026-09-11T00:18:24Z (terminal restart)

**Tree clean at `bf88fc9`.** If `memory-bank/tasks/2026-09/2026-09-10_stage-2-w3.md` shows an
uncommitted "Phase 3 (interrupted)" section on resume, it is W3's interim note written after this
handoff — read it, commit it. All agents end with the session; resume work as fresh workers from
the notes, not by resuming agents.

### Where things stand

- **Stage 1: complete and verified** on simulators and on the user's iPhone and Vision Pro (1.8
  proven: existing hosts appear from the shared catalog). Exit criteria met except app icons
  (placeholders) and the visionOS search accessibility gap (kit follow-up).
- **Stage 2: built, unit-verified, integration partly verified.** Engine `GlassSSHTransport` (61
  tests, security review clean). glas.sh moved in as `GlassTerminal` (348 tests). Whole package
  **461 tests / 23 suites pass**. Builds on macOS (real profile, no override), iOS Simulator,
  visionOS Simulator; Stage 2 build installed on both devices. UI suites on `410d0fc`: iOS 6/7,
  visionOS 5/7 (reasoned skips), **macOS 4 failures (detail controls not hittable)**.
  Real-host session from the iOS simulator reaches the VM through key exchange to the host-trust
  prompt, then fails on reconnect (defect below).

### Open defects, all assigned to a W3-type worker on resume (owns `Sources/GlassShell`,
`Sources/GlassTerminal`, `UITests/`)

1. **macOS UI regression:** after the Stage 2 library additions (capability toolbar items ahead
   of Add Host, per-service actions beside Connect, `GlassLayeredPanel` wraps, `Window` scene),
   the detail's buttons are "Not hittable" and rows aren't found under XCUITest on macOS only.
   Trace: `scratchpad` is gone with the session — reproduce with the macOS UI suite; capture the AX
   tree via `xcresulttool export attachments`.
2. **macOS crash, deterministic:** `ServerFormViews.swift:427` presents `AddSSHKeyView` as a sheet
   on the server-form sheet → AppKit accessibility recursion segfault. Present via `openWindow` or
   popover on macOS (project rule 12); then let `UITests/GlassTerminalUITests.swift` run past the
   key sheet on macOS.
3. **Post-trust reconnect fails:** `TerminalConnectFlow.swift:706` → `SessionManager.reconnect` →
   `origin(for:)` (:343-352) throws `sessionNotRegistered` (:885) because the connect-failure path
   (:587-599) unregisters the session on the trust-challenge error; glas.sh kept it. Unit test.
4. **`lastConnected` stamped on open, not success** (`GlassShellModel.swift:377`): add a result
   path from `GlassCapability.open` and stamp only on connected.
5. **Verify capability settings pages appear** (Connections/Terminal/Snippets) on the current
   tree; they were missing at `9f58a61`, before the wiring commit `410d0fc`.

### Then, to close Stage 2

Run: whole package tests; UI suites on iOS, visionOS, macOS; the terminal UI test with
`TEST_RUNNER_GPT_SSH_TEST_HOST=192.0.2.6 …_USER=michael …_KEY_PATH=$HOME/.ssh/scratch_vm` on the
iOS simulator (reaches the VM) and macOS; the engine's gated CLI suite
(`GPT_SSH_TEST_*`, `swift test --build-system native --filter SSHTransportIntegrationTests`) —
**blocked until the user grants Local Network to the terminal app (was Ghostty)**; then the parity
checklist in the Stage 2 note (SFTP, forwards, workgroups, widget on device, iCloud sync live),
device re-install, progress/README, and commit.

### Still needs the user

- Local Network grant for the terminal app driving the session (System Settings → Privacy &
  Security → Local Network). Verified blocked by `errno 65` from ad-hoc-signed binaries.
- Report what the Stage 2 build shows on the iPhone (one row per host, two icons) and Vision Pro.
- `../docs` may be deleted; every July finding is closed.

### After Stage 2

Stage 3 (database) and Stage 4 (desktop) notes are drafted and indexed; Stage 3's dependency gate
already passes. Stage 5 (editor interface, spatial workspace, VNC-over-SSH, VNC kind) follows.
Then the TODO/stub sweep the user asked for across all created code, with the same testing.

## Next action

On resume: read this file, the Stage 2 note, the W3, integration and consolidation notes; commit
any interim W3 note; launch one worker for defects 1–5 with the ownership above and one read-only
reviewer for the Stage 2 close-out; run the verification list; then Stage 3.

## Resumed — 2026-09-11T00:27Z, tree clean at `13fed7f`

Recovery matched the handoff; no discrepancy. **Local Network is no longer blocked:** an
ad-hoc-signed TCP probe built in the session scratchpad reaches `192.0.2.6:22` and reads the
OpenSSH banner, so the engine's gated CLI suite (`SSHTransportIntegrationTests`) is running in a
separate scratch build path. Two agents launched: **W4** (owns `Sources/GlassShell`,
`Sources/GlassTerminal`, `UITests/`, `App/GlassPowerToolsApp.swift`; task note
`tasks/2026-09/2026-09-10_stage-2-w4.md`) for the three macOS causes and integration defects 1–4
plus the settings-page check; and a **read-only Stage 2 close-out reviewer** (parity checklist,
TODO/stub scan, security spot-check, dead code). Coordinator `/root` still owns this file.

## User feedback on the first /Applications build — 2026-09-10 evening

Release build from W4's in-flight tree installed at `/Applications/GlassPowerTools.app` (0.1.0,
signed, launches). The user's five macOS crash reports were all the sheet-on-sheet accessibility
recursion (defect 1, fixed in W4's tree). New user requests, all in flight:

1. **"+" left of the sidebar toggle** (library window and terminal window). Kit change made by
   the coordinator in `../GlassConnectionKit` (uncommitted): `GlassConnectionLibrary.sidebarActions`.
   Shell/terminal wiring assigned to W4 (phase 3).
2. **Settings modal tabs**: no "Settings Section" label; vertical tabs on compact iPhone; leading
   ornament on visionOS. Done in the kit's `GlassSettingsSections` (uncommitted); kit builds on all
   three platforms, 48 kit tests pass. UI-test adjustments, if any, assigned to W4.
3. **macOS App Sandbox removed** from `Platforms/macOS/macOS.entitlements` (matches glas.sh; the
   sandbox broke the Mac local terminal). Recorded in techContext.

Next: when W4 reports green, rebuild Release and reinstall to /Applications; then commit (the
user authorized commits for this project's work) and note the kit's uncommitted diff for the user.

**W5 launched (2026-09-10 evening):** system-wide tag field. Owns the new kit file
`GlassConnectionUI/GlassTagField.swift` (+ kit tests), `Sources/GlassShell/GlassShellEditors.swift`,
new `GlassShellTagVocabulary.swift` (+ test), and only the tag-typing lines of
`UITests/GlassShellLibraryUITests.swift`. W4 notified. Task note: `tasks/2026-09/2026-09-10_shell-tags.md`.

**W5 done (2026-09-10 evening, uncommitted):** `GlassTagField` in the kit (chips, Remove, Return/comma
commit, Backspace removes last, suggestions from one system-wide vocabulary; flow layout), 3 kit
tests (kit 51/51); `GlassShellTagVocabulary` + `GlassShellModel.tagVocabulary` (2 tests); host editor
uses the field for aliases and collections; new `UITests/GlassShellTagFieldUITests.swift`. Whole
package 461 tests / 25 suites pass in W5's scratch build; macOS library 5/5 + tag test 1/1; iPhone
5/5 + 1/1; visionOS builds, no UI run. Mac screenshots judged by eye: chips as tinted capsules with
×, suggestions "+ Clients / + Lab" under the input. Note: `tasks/2026-09/2026-09-10_shell-tags.md`.
Real defect found and fixed: AppKit's field editor consumes Backspace before `onKeyPress`, so the
field uses a local NSEvent monitor only while focused and empty.

## Late evening 2026-09-10 — W4 lost to the session rate limit; W6 launched

W4 (macOS regression + defects + cleanup + phase 3) was terminated by the API session limit before
its final report. **All four phase-3 edits are present in the tree** (sidebar "+" placements, 3 pt
canvas margin with `TerminalCanvasMetrics`, `GlassLayeredPanel(role: .embedded)`, window sizing);
its note's verification table is current only up to the phase-2 queue. W4's last visionOS run found
the kit's hand-built settings `.ornament` absent from the accessibility hierarchy; the coordinator
replaced it with a native `TabView` (visionOS renders tabs as the leading ornament; kit builds).
Open from W4: the macOS accessibility crash after the connection-failure alert (only under XCTest
diagnostics), and the macOS real-host UI test blocked on the app's own Local Network prompt.

**W6 launched** for the host-level address requirement (see projectbrief): owns
`HostProfile.swift` (+ kit tests), `Sources/GlassShell/**`, the terminal capability/connect
flow/server form, tests and UITests; note `tasks/2026-09/2026-09-10_host-address.md`.

**Still Stage 2.** Everything since the resume is Stage 2 close-out plus shell fixes the Stage 2
build exposed on real use (sandbox, panel role, tags, address, "+", settings tabs, margin). Stage 3
starts when the Stage 2 verification list is green and the tree is committed.

**Second /Applications build (late 2026-09-10):** Release from the tree with W4's phase 3 + W5's
tags + the sandbox removal; installed, launches, no crash. Verified by eye from own-window captures
(`scratchpad/mac-library-now.png`, `mac-detail-now4.png`): "+" sits left of the sidebar toggle;
the detail is a flat column with the standard action bar, no card, no white corner (panel role fix
confirmed). Found and queued to W6: Services rows overflow at the 900-pt minimum width; "Connect
opens" shows a bare endpoint name. Scripted System Events clicks register as double-clicks (they
opened the connect sheet); a real single click selects — not a defect. The terminal cannot read
the App Group container (TCC), so catalog contents are only inspectable through the app.

## W6 done — 2026-09-11 early (uncommitted → committed in the next checkpoint)

Host-level address landed: `HostProfile.address: String?` in the kit (schema stays 1; absent on the
wire when nil; lenient decode; catalog publication preserves it; 53 kit tests), shell `Address`
field under Name, detail row, same-address grouping (loopback excluded), capability hooks
`GlassCapabilityHostAccess` / `hostAddressDidChange`, terminal server form shows the address
read-only ("From the host …") when the host has one and writes an entered value back when it has
none, `GlassTerminalHostAddressSync` propagates edits. Seed syntax `name@address:kind`. Detail
Services rows restructured (name/kind stacked, actions trailing, `ViewThatFits`); "Connect opens"
shows the kind first. Results: whole package **469 tests / 28 suites** (twice); iOS/visionOS/macOS
builds; iPhone UI 7/8 — the real-host test ran the full address flow (screenshot judged by eye:
"192.0.2.6 / From the host scratch", no Host field) and then failed only because **the VM is
down** (`nc` times out from the Mac too). **macOS XCUITest is blocked** on this machine: every
launch fails "Timed out while enabling automation mode" (four attempts by W6); the coordinator is
re-checking with the smoke test. Third /Applications build installed and launched.

**Needs the user:** bring the VM at 192.0.2.6 back; if the macOS smoke test still times out,
run `sudo launchctl kickstart -k system/com.apple.testmanagerd` or re-grant Automation /
Accessibility to the Xcode test runner in System Settings.

**visionOS settings sections (2026-09-11 01:00):** the TabView-as-ornament attempt was invisible to
XCUITest inside the settings sheet (tree captured, no tab bar anywhere); the kit now renders a
leading column of vertical tabs on visionOS. Both affected visionOS tests pass
(`testAppearanceOpacityPersistsAcrossRelaunch`, `testTerminalSettingsPagesAppearInTheShellSettings`);
visionOS suite otherwise green apart from the reasoned skips (search; real host, VM down). Visual
check of the visionOS column still owed (in-test shots are 1×1; simulator shut down after the run).
Rule 14 added. UI-test helpers attach the accessibility tree on a settings-page miss.
**macOS XCUITest remains blocked** ("Timed out while enabling automation mode", coordinator
confirmed twice after clearing stale processes) — user action: kickstart `testmanagerd`.

**2026-09-11 ~01:20 — VM back; real-host runs:** engine suite 5/5 again; **iPhone terminal suite
2/2 with the real host** — `testConnectsToRealHostThroughTheShell` passed end to end (host address
entered once, terminal form read-only, key auth, live shell), settings pages pass. macOS automation
mode recovered on its own (smoke passed); full macOS UI run with the real host in progress.

**2026-09-11 ~01:45 — full macOS UI run with the real host (automation mode recovered on its own):
10 passed / 1 failed.** Library 5/5, tag field 1/1, smoke 1/1, terminal chrome 1/1, settings pages
1/1. `testConnectsToRealHostThroughTheShell` failed: after `host-service-connect-ssh` was clicked
no terminal window opened within 45 s (element tree at failure: windows=1, no sheet/alert, no
trust prompt) — consistent with W4's earlier observation that the test build hits the app's own
**Local Network prompt** (a system dialog outside the app's tree) and the attempt fails while it is
pending. Needs the user to click Allow once for Glass Power Tools (from the /Applications build:
connect to 192.0.2.6, accept the prompt), then rerun the macOS terminal suite. Open polish item
from the capture (`scratchpad/att-mac-full/B1C16699….png`): the detail's Services row actions
(Connect / SFTP / Edit / Details / Delete) still overflow at the 900-pt minimum width — W6's
`ViewThatFits` did not wrap; the trash button clips at the trailing edge.

## W7 done — 2026-09-11 ~08:30

No address field in any service setup: the shell gates a capability's setup on the host's address
(`GlassShellAddressRequest`, "Address for <host>" prompt with Cancel/Continue; a saved service's
address is adopted when exactly one is known; disagreements are left to the user), the terminal form
always shows the address read-only from the shell, write-back removed. Add SSH Key is a sheet on
every platform using the server form's pattern (Key / Private Key sections, Choose File… first,
bounded paste area, detection footer; the separate macOS window and rule 12 are gone). Services row
collapses capability actions into a ⋯ menu when narrow. Results: package **472 tests / 28 suites**
(twice); **macOS UI all suites with the real host green, including the real-host connect (the
Local Network grant is in place)**; iPhone all suites green after a rerun of two tests W7's own
`pkill` had disturbed; new address-step test passed alone twice, flaked once under load in the full
suite (recorded, not masked). Screenshots judged by eye: key sheet and address prompt match the
server-form pattern. Note: launching the Release build adopted the saved terminal address onto the
real `oscar` record (designed behaviour). Open: `GlassTerminalLibraryEntries.swift` "Set Up…" bypasses
the shell's address gate for legacy records; the ⋯ menu's items not captured; W4's post-failure
accessibility recursion; visionOS UI suite not re-run since W7; widget on device; live iCloud sync.

**visionOS full suite with the real host (2026-09-11 ~09:00, `scratchpad/vision-ui-root5.log`):**
**real-host connect passed on visionOS too** (live shell, 192 s), address-step test, settings pages,
tag field, favorites, consolidation, appearance persistence, smoke all passed; search skipped (known).
One failure: `testAddHostAddServiceConnectPlaceholder` at `GlassShellLibraryUITests.swift:98` — the
Add Host sheet's name field did not appear within 10 s on the suite's first test; passed alone
earlier today. Rerunning alone. The placeholder flow itself is about to be replaced by the
one-and-done setup (see the new requirement below).
Rerun alone: `testAddHostAddServiceConnectPlaceholder` **passed** on visionOS (49 s) — first-test
load flake, not a regression. visionOS suite is therefore green with the real host apart from the
search skip. **W8 launched** for the one-and-done setup (see projectbrief); owns `Sources/GlassShell/**`,
the terminal capability/connect flow/server form/library entries/scenes, tests, UITests; note
`tasks/2026-09/2026-09-11_one-and-done-setup.md`.

**Device installs (2026-09-11 ~09:15):** the committed tree `3f1c6b6` built Release from a clean
worktree (`scratchpad/wt-device`, sibling packages symlinked beside it) and installed on the
iPhone 17 Pro Max (launched) and the Vision Pro (installed). Widget-on-device and live iCloud sync
still to be observed by the user. W8's one-and-done build will be installed the same way.

## W8 verified and committed — 2026-09-11 (coordinator finished W8's runs)

W8 (one-and-done setup) ran out of credits after its macOS run; the coordinator completed the
verification. **Package 483 tests / 30 suites. macOS UI 12/12 with the real host. iPhone 13/13
with the real host. visionOS 10 passed, 1 skipped (search), 1 failed.**

Real defects found while finishing the runs, all fixed:
- **iPhone popped to the scope list after saving a service.** Reloading the items behind a
  presented sheet rebuilds the compact stack and drops the detail. Fixed in the kit's
  `reconcileSelection()`: a selection that survives a reload re-pushes its detail.
- **Compact Settings was a stacked list + page.** Now the Settings-app pattern: a `List` of
  `NavigationLink` rows pushing each page (kit `GlassSettingsSections.pushList`). iPad/Mac keep the
  segmented control, visionOS the leading column.
- **Test-side**: the diagnostic dump crashed on iOS 27 enumerating `app.buttons` over a SwiftUI
  Picker (macOS-only now); the detail's Address row is a child static text on macOS and the
  element's value on iOS (one `detailShowsAddress` helper); a sheet presented while the previous
  one animates away is swallowed on iOS (settle + retry); SwiftUI list rows are built lazily, so
  visionOS needed `reveal()` to scroll a row into existence; and visionOS raises the system
  "Save Password?" alert after a save, which covers the app (`dismissSystemPasswordPrompt`).

**Open (visionOS only):** `testConnectsToRealHostThroughTheShell` fails with XCUITest's
"Failed to received invalid scene ID (nil) from Accessibility" when pressing Add SSH Key inside
the host sheet — a simulator accessibility fault on a nested sheet, not an app assertion. The same
test passed on visionOS before the nested-sheet change and passes on macOS and iPhone now.

**Builds from `8fb17f9` (2026-09-11 midday):** Mac `/Applications` 0.2.45 (launched), iPhone 0.2.43
(launched), Vision Pro 0.2.43 (installed). Version numbers now come from the commit count; the Mac's
45 was stamped by hand from the same commit. One trap recorded: a failed Release build leaves the
previous app in derived data, so an install step gated only on the log's exit line can silently
ship the old binary — check `CFBundleShortVersionString` after every install (this happened once,
caused by `navigationBarTitleDisplayMode` being iOS-only in the kit's new compact settings list).

**Preview builds 0.2.46 (2026-09-11 ~13:00):** built from W9's in-progress working tree (compiles;
macOS UI green on W9's runs, iPhone had one failing settings-pages test at the time, visionOS not
yet run). Installed and version-verified on the Mac (`/Applications`, launched), iPhone (launched)
and Vision Pro. Coordinator's own capture of the Mac window confirms W9's row work by eye: no
"Connect" text, no last-connected, no services subtitle, merged play+chevron control, circle-stack
database icon, and the detail action bar now spans the full width with its material.

## W9 done — 2026-09-11 afternoon (committed)

Library row: name + service icons + one split control, no words — play runs `connectAll` (every
service; records no "last used" because the machine was chosen), chevron is its own hit region on
all three platforms and picks one. `lastConnected` removed from the kit row API; no subtitle.
Delete left the detail action bar for the row's context menu and a destructive "Delete Host…"
section in the edit sheet (`.editHost` only). Detail action bar spans full width with a divider,
matching the sheets. **Database icon is the genuine Heroicons `circle-stack`**: vendored at
`../GlassConnectionKit/Vendor/heroicons/{circle-stack.svg,LICENSE}` (MIT, Tailwind Labs) and
translated one-for-one into `HeroiconCircleStack`.

Results: kit 53 tests, package **485 / 30 suites**, builds on all three platforms, **macOS UI 14/14
with the real host**, **iPhone 13/13**, visionOS 11 passed / 1 skipped / 1 failed (the pre-existing
XCUITest scene-ID simulator fault on the real-host test).

Two regressions W9 found and fixed: `dismissSystemPasswordPrompt()` asked for `com.apple.springboard`,
which does not exist on macOS and failed five macOS tests; and the compact settings `pushList` left
the presenter's Done on the root, so a pushed page could not be dismissed on iPhone (the settings
view now carries its own Done on compact iOS).

**Sibling call sites broken by dropping `lastConnected:` (not edited, user's call):**
`../glassdb/glassdb/ConnectionManagerView.swift:756-760`,
`../glassDT/Sources/GlassDesktopUI/DesktopLibraryView.swift:48-49`,
`../glas.sh/glas.sh/ConnectionManagerView.swift:3385-3387`.

**Run trap:** macOS UI runs must reuse `scratchpad/dd-uitest` — a fresh derived-data path produces a
binary without the Local Network grant, and the real-host test then fails as if the VM were down.

**0.2.47 deployed (2026-09-11):** Mac `/Applications`, iPhone and Vision Pro all on 0.2.47 from
`98a6094`, each version read back from the installed bundle.

**App icon, SVG-first (2026-09-11, W10):** `App/GlassPowerTools.icon` is four hand-authored SVG
layers (Prompt, Screen, Bezel, Database) with `glass: true` and per-appearance solid fills —
light: near-white gradient + grey secondaries; dark: near-black gradient + white secondaries; red
screen `srgb:0.906,0.035,0.039` sampled from the user's composite. Clear/tinted are derived by the
system, not authored. Schema copied from the family's approved document at
`~/Software/icon-lab/archive/2026-09-06/approved-source-icons/.../AppIcon.icon/icon.json`.
`actool` compiles clean; `assetutil --info` shows Aqua, DarkAqua and Tintable variants for all four
layers. **Limitation recorded:** the CLI cannot render the dark or clear renditions as the OS
composites them (`iconutil` extracts only the default; `assetutil` reports structure). Dark was
verified as a flat colour composite only — real dark/clear need the installed app or Icon Composer.

## App icon shipped — 2026-09-11, 0.2.60

`App/GlassPowerTools.icon` is an Icon Composer document with three layers of the user's delivered
renders. Dark uses the artwork as delivered; light uses variants whose **neutral** pixels are gamma
curved (γ 1.75) so the bezel and discs stay white with their own shading reading against a
near-white ground; the prompt glyph is the white artwork in both. Clear and tinted are the system's.
Full detail, geometry and the three findings are in
[the app icon note](tasks/2026-09/2026-09-11_app-icon.md); rule 17 records the standing constraints.

**All three are on 0.2.60** (Mac, iPhone launched, Vision Pro installed; each version read back
from the installed bundle).

### Stage 2 close-out still open
Widget on a device; live iCloud sync; the visionOS real-host UI test blocked by XCUITest's own
scene-ID fault; the three sibling call sites that break on the kit's dropped `lastConnected`
(`../glassdb/glassdb/ConnectionManagerView.swift:756-760`,
`../glassDT/Sources/GlassDesktopUI/DesktopLibraryView.swift:48-49`,
`../glas.sh/glas.sh/ConnectionManagerView.swift:3385-3387`). **The kit itself
(`../GlassConnectionKit`) has substantial uncommitted work** — host address, tag field, settings
sections, sidebar actions, native list selection, service icon, window chrome separator — and is
the user's to commit.

## Next: Stage 3, the Database capability — planned and approved 2026-09-12

Read [the Stage 3 plan](tasks/2026-09/2026-09-12_stage-3-database-plan.md) first; the two read-only
surveys it is built on are beside it in `tasks/2026-09/surveys/`. It supersedes the 2026-09-10
draft. Decisions D7–D11 are in [decisions](decisions.md); **D8 (a real "This Mac" host taking every
service kind, several of a kind allowed) and D9 (parity-plus) are approved**, and the user approved
**installing MySQL and PostgreSQL on the test VM** (`192.0.2.6`, sudo available, least-privilege
test users, never root).

### Wave 1 — in progress, 2026-09-12

| Piece | State |
|---|---|
| **W-kit**, the engine moved | **done**, [note](tasks/2026-09/2026-09-12_stage-3-kit-move.md). Landed as `Sources/GlassDBKit` (a target, not a nested package — same role as `GlassSSHTransport`, and the Xcode project needed no edit). 22 tests; the six that tested `SSHTunnelManager` left with it and each has a named owner in `GlassSSHTransport`. **The survey's top risk is dead: the merged graph resolves on swift-crypto 4.5.2**, proven by `swift package resolve`, not by argument |
| **W-shell**, borrowing the host's forward (D7) | **done**, [note](tasks/2026-09/2026-09-12_stage-3-shell-forward.md). Pulled forward from wave 2. `GlassCapabilityHostAccess.forwardPort(toHost:port:)` + `GlassCapability.openPortForward`, implemented by the terminal. 7 unit tests. **Never opened a real socket yet** — first honest test is wave 2 |
| **W-floor**, the availability sweep | running |
| **W-vm**, real databases on the VM | running |

Package now **514 tests / 34 suites**, and the app builds for macOS, iOS Simulator and visionOS
Simulator with the database engine in the graph. Nothing committed yet.

### Wave 2 — in progress, 2026-09-12

**W-capability: the port is built.** `Sources/GlassDatabase`, 26 files. The Database tab in the
one-and-done sheet is **live** (UI-tested, not inspected); scenes and bootstrap mirror the
terminal's; D7's forward is wired from `hostAccess.forwardPort`; D14's trust broker is built as a
*second source for the existing prompt*, not a second prompt; read-only is enforced on the
connection, not the UI (**D15** — five write paths bypass `executeQuery`, so a guard there would
have protected nothing while looking correct). Note:
[the capability note](tasks/2026-09/2026-09-12_stage-3-capability.md).

**W-local: running**, on D8's built-in "This Mac" host.

**The numbers, stated honestly.** Valid as measured **before W-local started**: `swift test` 560
passed / 0 failed; app builds on macOS, iOS and visionOS; macOS UI 18/19 with the single failure
isolated by experiment to the untracked tag-vocabulary work. Anything sampled since is
**unattributable** — the tree is mid-edit and `swift build` currently fails at
`GlassShellSetup.swift:114`. A UI re-run and a coordinator-run UI suite were both contaminated this
way and are discarded rather than cited.

**Coordination lesson (coordinator's error).** W-local was started while W-capability still had
work needing a green tree, so it is blocked and its measurements are meaningless. Standing rule
adopted: a worker sharing this tree lands compiling increments, and warns before any sweeping change
so the others can be held rather than sample noise.

### Since Stage 3 closed: shipped to /Applications and corrected in use — 2026-09-12

Builds **0.3.56 → 0.3.67**, each installed and the version read back from the installed bundle.
Package **615 tests / 48 suites**, one known issue (D13). **Nothing is committed** — 63 files.

**The finding that matters: the SSH forward dropped a server-first protocol's opening bytes.**
[Full note](tasks/2026-09/2026-09-12_ssh-forward-server-first.md). MySQL greets first; the channel
was wrapped in a `NIOAsyncChannel` *after* the open returned, so a greeting delivered in the same
read as the channel-open confirmation landed in an empty pipeline and was discarded — the server
then timed out at its `connect_timeout` of exactly 10s. PostgreSQL is client-first and never
reproduced it. Fixed by wrapping **inside the channel initializer**. This is the
"two unexplained ~10s tunnel failures" that had been open since the morning; it is now closed, and
the user confirmed it in the running app against a loopback-only MySQL on a Tailscale host.

It passed every test, including the live tunnel test, because the VM's MySQL listens on `0.0.0.0`
and the race depends on packet coalescing. `openDirectChannel` is byte-for-byte identical to
glas.sh's, which felt like proof of correctness and actually means **glas.sh has the same latent
bug**. Three hypotheses were refuted along the way, and the right diagnosis was abandoned early for
the wrong reason — a failed remedy was read as a failed theory.

**UI and validation work** — [note](tasks/2026-09/2026-09-12_ui-and-validation.md): the canvas
border, "Paint Theme Color" removed, service tabs as the choice (which also fixed the Terminal tab
demanding new credentials during a database add), real colour swatches, the database name made
optional, `Set to NULL` moved into the column tool row, and record-editor validation for size
(`ColumnTypeConstraint`) and format (`ColumnValueFormat`). Two defects surfaced doing it: a
Release-only link failure from sharing a result-builder availability guard across modules (**D16**),
and `isBool` matching a bare `tinyint` so a score column rendered as a toggle and **would have saved
`0` over real data** (**D17**).

**Two regressions of my own, both recorded as rules:** a deleted `.toolbar(removing:)` line that I
then investigated everywhere except my own diff (rule 23), and an unverified mechanism propagated to
a worker who wrote it into a task note (rule 19).

### What is left before Stage 4

The plan's remaining work is **re-planned against the code that now exists**, with `file:line`
anchors — see *Remaining work, re-planned* in
[the Stage 3 plan](tasks/2026-09/2026-09-12_stage-3-database-plan.md). Two estimates in the original
were wrong: **AI on iOS is already done**, and the **audit viewer is not "one list view"** — there is
no audit store at all, only `os.Logger` output, so it needs a decision between building a store and
reading `OSLogStore`.

Order: **R1 the SQL draft-loss fix** (it loses work: `QueryDocumentTab.text` is in memory only and
nothing persists it), then **R2 row deletion** and **R3 foreign-key navigation** — the approved
parity-plus a user will notice — then settings, the audit decision, one command palette, D13, and
the smaller items. Desktop should not start until R1–R3 are done.

### Proven against real servers, 2026-09-12

`Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift` ran against MySQL 8.4.11 and
PostgreSQL 18.6 on the VM. **Stage 3's central claim is no longer a compile-and-unit-test claim.**

| Proof | Result |
|---|---|
| Both engines connect **through the capability**, real server version | **passed** |
| Seeded tables and the `members → teams` foreign key (MySQL) | **passed** |
| `SELECT` through the session manager returns the seeded rows, both engines | **passed** |
| **The read-only guard refuses a real `UPDATE`, row provably unchanged**, both engines | **passed** |
| MySQL and PostgreSQL each over **a real SSH forward** | **UNDER INVESTIGATION — see below** |
| **Read-only still refuses writes through a tunnel** | passed (same caveat) |

**The D7 tunnel claim is WITHDRAWN pending a controlled A/B.** It was made on runs that were on a
warm MySQL auth cache. `MySQL over a real SSH forward` then failed twice with
`Got timeout reading communication packets` at ~10s, and began passing again only after the cache
was warmed — unintentionally — by a `mysql` CLI connection through a plain `ssh -L`. Through a
forward the server sees the client as `127.0.0.1`, a **different `caching_sha2_password` cache entry
from the direct path**, which is why only the tunnel exposes it. PostgreSQL over the same forward
passes every time because it is client-first and never exercises the path.

This is the same warm-cache trap W-vm caught on the direct engine path, one layer up. Whole package
with the live and tunnel environments set: **592 tests / 45 suites**.

**Ruled out so far, by evidence not argument:**
- *Not* our forwarding diverging from proven code: `SSHTransport.openDirectChannel` is byte-for-byte
  identical to glas.sh's shipping implementation (`../glas.sh/glas.sh/Models.swift:2466`), and both
  vendored Citadel copies of `DirectTCPIP+Client.swift` are the same file.
- *Not* a lost server-first greeting: disabling `autoRead` on that hunch made the test **hang**, so
  the theory is wrong. Reverted.
- MySQL through a plain `ssh -L` forward works; MySQL direct works.

**The cold-cache theory was tested and is REFUTED.** W-vm flushed at `05:39:28Z` and stood off the
server; the first `gpt_test` connection afterwards was the Swift tunnel test, and
`MySQL over a real SSH forward` **passed in 0.072s**, all three tunnel tests green. Cold
`caching_sha2_password` full auth over our forward works. The OpenSSH control arm was therefore not
run — there is no fault to isolate.

The framing was wrong twice, and W-vm caught the second before the experiment ran: **only
`gpt_test@%` exists, and MySQL keys its cache by the matched account, not the client address.** The
tunnel never had its own cache entry, so "the tunnel is cold while the direct path is warm" was not
a mechanism that existed.

**Still unexplained, and the contention hypothesis is NOT supported.** Two reproducible failures at
almost exactly 10s — MySQL's `connect_timeout`, so round-trip-shaped rather than throughput-shaped.

*Provenance, since it was questioned and the answer matters:* the string came from the **client**
surfacing a server `ERR` packet — mysql-nio formats `MySQLError.server` as `"Server error: …"`
(`MySQLError.swift:40`). The VM's error log does not contain it, which is **consistent, not
exculpatory**: at `log_error_verbosity=2` the `MY-010914` note is not written, while the ERR packet
still reaches the client. Absence in the log and presence on the wire are one event seen twice.
Nothing listens on 3306 or 33306 on this Mac, so no local MySQL could have produced it — the
investigation is on the right machine.

*What the server's own counters say* (W-vm, for the 05:15Z–05:25Z window):

| Evidence | Reading |
|---|---|
| `Max_used_connections = 4` vs `max_connections = 151` | nowhere near a limit |
| `Connection_errors_{max_connections,accept,internal,peer_address,tcpwrap}` | all **0** |
| sshd journal, whole day, for throttle/refusal/timeout patterns | **no matches at all** |
| sshd `MaxStartups 10:30:100`; busiest second 7 accepts | below the throttle floor |
| `performance_schema.host_cache` for the Mac | `SUM_CONNECT_ERRORS = 0`, validated |

So **contention is recorded as proposed and unsupported.** It is not disproved either — a
client-side stall leaves no server trace at verbosity 2 — but it will not be kept alive for
convenience. A reverse-DNS stall was also chased and **ruled out**: `skip_name_resolve=0` made a
2×5s resolver timeout fit suspiciously well, but the lookup measures 6ms and the host cache holds a
validated entry.

**Armed for a recurrence:** `log_error_verbosity` raised to 3 (`SET GLOBAL` + `SET PERSIST`) with a
counter baseline snapshotted at `05:43:08Z` (`Aborted_connects 55`, `Aborted_clients 0`,
`Connections 210`, `Max_used_connections 4`). Only the **diff** from that baseline is meaningful.
Revert with `SET GLOBAL log_error_verbosity=2; RESET PERSIST log_error_verbosity;`.

**Read that log with two facts in hand, or it will mislead you.**

*First, much of the aborted-connect noise is ours by design.* Verbosity 3 immediately caught four
notes inside 12ms — three `Got an error reading communication packets` and one `Bad handshake`.
That is `MySQLAdapter.serverAdvertisesTLS` (`MySQLAdapter.swift:76-94`), which deliberately opens a
raw connection, reads **only the unauthenticated greeting** to check for `CLIENT_SSL`, and closes
without authenticating — a fail-closed design so mysql-nio's opportunistic TLS can never send an
auth response to a server that does not offer encryption. From the server it is indistinguishable
from a client giving up. It runs whenever `tlsPolicy.isRequired`, so every suite run that exercises
a TLS-required policy drifts `Aborted_connects` upward with no fault behind it.

*Second, and this is what makes the trap escapable:* the probe's notes say **"Got an error** reading
communication packets"; the unexplained failure said **"Got timeout** reading communication
packets". **Different reason path, so the two are distinguishable in the log.** Anyone grepping
later will find a pile of aborted-connect notes that are not the bug; match on *timeout*.

The `Bad handshake` note in the same cluster is the probe too — it closes mid-handshake by design —
and is **not** a lead, despite pointing at the handshake rather than a read stall.

**Three distinct things fail at ten seconds on this path.** They are told apart only by their
strings, so the table matters more than any of them individually:

| Signature | Source |
|---|---|
| `Got timeout reading communication packets` — a server `ERR` packet over the wire | **the open bug** |
| `Got an error…` / `Bad handshake` in the server log | our fail-closed TLS probe; benign |
| `Timed out waiting for the MySQL server greeting.` — a client-side string | the probe's own greeting timeout (`MySQLAdapter.swift:86`) |

`serverAdvertisesTLS` carries its own `connectTimeout(.seconds(10))` at `:80` as well, so the
coincidence is threefold and none of them is evidence for another.

**The probe's interaction with a tunnel was checked, and is correct.** With TLS required over a
forward it opens a *second* forwarded connection before the real one. Both are correctly targeted:
the transport plan sets `databaseHost = "127.0.0.1"` and `databasePort = tunnelLocalPort`
(`DatabaseSessionManager.swift:230-236`) and the probe receives exactly those, so it tests the
endpoint the session will actually use. And the policy over a tunnel is
`.requiredSystemTrustForHost(config.host)` (`:218`), so the certificate is verified against **the
machine's real name, not loopback** — the thing a tunnel implementation usually gets wrong, already
right. A cost, not a defect.

### macOS UI suite — the first attributable run, 2026-09-12

**18 passed, 1 failed, 1 skipped**, on a machine verified quiet before the run and with nothing else
started during it (rule 21). Three earlier runs were discarded as unattributable.

- `GlassShellLibraryUITests` **7/7** — including `testAddHostWithTerminalInOneSheetThenConnect`,
  which had failed in a contended suite with an event-synthesis timeout and **passes here in the
  suite at 77.9 s**. That settles it as contamination, not a defect, and is the evidence rule 21
  was missing.
- `GlassShellLocalHostUITests` **4/4** — D8 verified against the running app.
- `GlassTerminalUITests` 4 passed, 1 skipped. `LaunchSmokeUITests` 1/1.
- **`GlassShellTagFieldUITests.testCollectionsAreChipsAndFeedTheSystemWideVocabulary` — failed.**

**The one failure, with what is established and what is not.** It is pre-existing, in **untracked
Stage 2 tag-vocabulary work** (`Sources/GlassShell/GlassShellTagVocabulary.swift`,
`UITests/GlassShellTagFieldUITests.swift`), and was independently reproduced by two workers with
Stage 3 absent.

*Established:* it fails **only at the final assertion** — the `Clients` collection appearing in the
sidebar; every earlier assertion passes. The sidebar does render collections as their own section
from `projection.collections` (`GlassLibraryCategories.swift`). The setup sheet **does** pass tags
to `addHost`/`updateHost` (`GlassShellSetup.swift:275,287`). The model-level equivalent passes in
`GlassShellModelTests` (`projection.collections.map(\.name) == ["Lab", "Prod"]`).

*The useful narrowing:* the test's earlier success — the suggestion reading "Add Clients" — proves
**the vocabulary store persisted the tag**, which is a *different store* from the host record. It is
not evidence that the host itself carries the tag, and the two are easy to conflate.

*Not established:* why the sidebar row is absent. **No mechanism is offered here deliberately**
(rule 19); it needs a run with element inspection, which is its own task.

### Stage 3 remaining work: R1–R8 closed, 2026-09-12

Three workers in parallel plus the coordinator. Package **711 tests / 61 suites, no known issues**
— D13's `withKnownIssue` is gone because the defect is fixed, not suppressed. Nothing committed.

| | Outcome |
|---|---|
| **R1** SQL draft loss | [note](tasks/2026-09/2026-09-12_sql-drafts.md). Query history's *shape* reused, its *medium* rejected — history is capped at 500 because `UserDefaults` is materialised at launch, and a draft is unbounded. Found and fixed a **second instance**: `tableSQLDrafts` |
| **R2** Row deletion | [note](tasks/2026-09/2026-09-12_rows-and-audit.md). Predicate extracted so deletion is a third caller, not a fourth copy. **A row edited underneath the user reports 0 against both real servers** |
| **R3** FK navigation | Composite keys **fail closed** on a repeated ordinal. Live fixture holds both `(1,2)` and `(2,1)` so a transposed pairing cannot pass for the wrong reason |
| **R4** Mutation audit | Viewer plus a `predicate` field storing the **shape only** — never the parameters, which are a verbatim copy of the user's row |
| **R5** Settings | Appearance folded onto the one `GlassLayerStore`; persistence deleted, not added |
| **R6** Command palette | **One implementation pasted twice**, not two implementations. 650 lines deleted |
| **R7** D13 | [note](tasks/2026-09/2026-09-12_certificate-trust.md). CA-only as a *named, chosen* mode with no automatic downgrade; the connection detail now says what TLS verifies |
| **R8** Smaller items | PG arrays, dead fields, `ConnectionFormView` (~1,295 lines) gone. `text`/`blob` **open at six of eight** |

**The correction worth carrying:** an engine-level test proved the *engine* could do VERIFY_CA — it
could not prove a saved record reaches it. Until `transportPlan` mapped the mode, every piece
existed and nothing joined them, and only a **capability-level** test distinguishes those two
states. "It works" and "the parts that would make it work all exist" look identical from below.

**Still owed, and it is not code:** driving deletion and a foreign-key follow through the running
app; the D14 fingerprint prompt; whether SQL-draft restore fires at all; iOS and visionOS, which
remain compile-verified only. No test opens a window anywhere in this stage.

### D8 — "This Mac" is built, 2026-09-12

[The local-host note](tasks/2026-09/2026-09-12_stage-3-local-host.md). The device is a real host:
a fixed `HostID`, its record in a **second catalog store under app-local storage** rather than the
App Group (which is what "never published" means in practice, while reusing the kit's locking and
validation), inserted at the head of `hosts` after grouping so a discovered machine of the same name
cannot swallow it. Built-in services are **declared by the capability, not stored**;
`supportsLocalSetup` defaults to **true**, so a capability opts *out* — `Sources/GlassDatabase` was
never touched and gets local database setup free.

`connectAll` on that row is **picker-only, no play glyph** — see the D8 addendum in
[decisions](decisions.md) for the four-part reasoning, which is recorded because someone will ask.

**The row appears on every platform and is emptier off the Mac, not dead.** No local shell exists on
iPhone, iPad or Vision Pro, so the terminal contributes *no* row rather than one that does nothing;
SQLite is real everywhere and this is the **only place a SQLite file can live in the product**, which
is why the row is not suppressed when empty. Named "This iPhone" etc. rather than the device's own
name, so it cannot be confused with the same machine reached over SSH in the shared library.

**Open limit, stated plainly: iOS and visionOS are compile-verified only.** The UI tests are written
to run there and have **not** been run there, so the row's appearance in the running app on those
platforms is a build result, not a device result.

Full detail, including both hypotheses recorded by name and outcome and a ruled-out subsection for
reverse DNS (which fits well enough that someone will re-propose it), is in
[the VM note](tasks/2026-09/2026-09-12_stage-3-vm-databases.md), under a heading that says
*Read this before grepping the error log*. **Do not lower `log_error_verbosity` while this is open**
— doing so silently disarms the trap.

**Status: open.** The failure is real, it came from the VM's MySQL as a `connect_timeout` expiry,
and nothing yet explains it. It is not closed by "it passes now".

**"It passes now" is not the resolution.** It passed before, too. Until the log explains the two
failures, the honest status of the D7 tunnel is *works in clean conditions, with an unexplained
failure mode under load* — which, if it is contention, is a lesson about how live tests are run
rather than a defect in D7.

**Still not proven by a human:** no fingerprint has been compared in the actual SwiftUI prompt. D14's
broker is unit-tested and the flow through the UI is not.

**A real defect, found by the live run and now fixed.** `PostgreSQLAdapter.foreignKeys(in:database:)`
inner-joined `information_schema.constraint_column_usage`, which PostgreSQL restricts to tables the
current user **owns**. The constraint was visible in `table_constraints` and invisible in
`constraint_column_usage`, so the join dropped it and the Foreign Keys tab rendered **empty —
indistinguishable from a table with no keys**, for exactly the least-privilege accounts a careful
user connects with. D9 commits us to foreign-key navigation, so it would have shipped looking
correct and showing nothing.

Fixed: the adapter reads `pg_catalog` (`pg_constraint`/`pg_class`/`pg_attribute`), house-consistent
with `tableStatus` in the same file. The test that found it now guards it and asserts the key
positively. Its comment warns against "simplifying" it by seeding as the connecting account — the
non-ownership **is** the condition under test.

**Why this one matters beyond itself.** It was invisible to every unit test, every compile and every
reading of the code; it needed a real server *and* a realistic least-privilege account. It is the
third time this stage that the shape of an API suggested one thing and the call sites or the real
server said another — see D13, D15. That is now a rule worth applying, not an anecdote.

The `withKnownIssue` discipline paid for itself: the fix made the test fail with "Known issue was
not recorded", which is what removed the wrapper rather than leaving a stale one behind.

Then: W-palette (one macOS command palette — glassdb's and glas.sh's are two implementations of one
surface), the D9 gap closures, W-settings, the security review, and integration.

Stage 2 close-out still open: widget on a device, live iCloud sync, the visionOS real-host UI test
blocked by XCUITest's scene-ID fault, and the three sibling call sites broken by the kit's dropped
`lastConnected`.

### The device pass, and two things found while preparing it — 2026-09-12 (night)

Stage 3's R1–R8 are closed; what remained was described as "not code, a device pass". Preparing
that pass produced code anyway, which is the finding worth keeping: **the act of trying to test a
thing surfaced defects that reading it never did**, for the third time this stage.

#### D14: the fingerprint was spelled in a way nothing else spells it

`SSHHostTrustEvaluator` returned bare **padded** base64. Every other SSH tool — `ssh-keygen -lf`,
OpenSSH's own first-connect prompt — prints `SHA256:` followed by **unpadded** base64.

| Source | String |
|---|---|
| `ssh-keygen -lf` | `SHA256:O/zNAQP8+gbY+no+sgjwkOLRBlT2Q2MVq6Ltk6KnRqg` |
| Glass Power Tools, until now | `O/zNAQP8+gbY+no+sgjwkOLRBlT2Q2MVq6Ltk6KnRqg=` |

Same 32 bytes — the VM's ed25519 blob was decoded and both digests computed to confirm it. **The
bytes were never wrong; the string was.** D14 exists so a *person* can compare what the app shows
against what the server tells them, and they were being asked to compare two differently-spelled
renderings of the same hash.

**Why no test could have caught it.** The trust decision is made on the key blob
(`SSHHostTrust.swift:182`), never on the fingerprint text, so nothing rejected a connection and
nothing misbehaved. The only symptom was a human squinting. It survived two days of successful
connections.

**Why the fix was small rather than a migration**, all three established before changing anything:
- `PinnedSSHHostKey.sha256Fingerprint(for:)` in GlasSecretStore **already** produced the canonical
  form for the Keychain record. The fix delegates to it, so the fingerprint shown and the
  fingerprint stored are now one line of code instead of two opinions.
- `KeychainManager.validatedHostKeyData:586` already accepted **all three** historical spellings
  (canonical, bare unpadded, bare padded). Someone knew these had diverged and made the *validator*
  tolerant without fixing the *display*. Records written before the change still verify.
- `TrustedHostKeyEntry` is decode-only, a legacy migration source read into the Keychain.

The label changed too: `Fingerprint (SHA-256): SHA256:…` says it twice. Now `Fingerprint: SHA256:…`,
matching `ssh`. Three call sites (`TerminalConnectFlow.swift:608,610`, `TerminalWindowView.swift:422`).

**The old test was pinning the defect.** `#expect(...sha256Base64(of: blob).count == 44)` — 44
characters *is* the padded form. Replaced with a known-answer test whose expectation came from
`ssh-keygen` on a throwaway key (private half destroyed, public blob only), so the assertion is not
the implementation agreeing with itself.

#### SQLHighlighter had no tests at all, and was correct anyway

Asked whether glassdb's test files were useful, a worker found our suite is **not** a subset of
theirs — we cover TLS modes, FK navigation, the audit store, live integration, none of which they
tested. But **whole modules moved across verbatim and arrived with no tests**, and glassdb's file
is the only record of what they guarded.

The load-bearing one: `SQLHighlighter` had **zero test references** anywhere in `Tests/` or
`UITests/`. `ReadOnlyDatabaseConnection.checkReadOnly:52` — D15's whole gate — is one line
delegating to `safetyClassification`. `ReadOnlyServiceTests` proved the *wrapper* against seven
unambiguous statements (`DELETE FROM members`, `DROP TABLE teams`), which is exactly the set that
survives any plausible regression. **The wrapper was tested; the classifier it trusts was not.**

`Tests/GlassDatabaseTests/SQLSafetyClassificationTests.swift` now covers it — 10 tests, all passing.
**No defect was found: the classifier is correct.** What was missing was anything guarding that it
stays correct. A tokenizer change that stopped recognising a string literal or a `/* */` comment
would silently reclassify, and a read-only production service would begin passing writes with
nothing failing.

The suite asserts the security property *directly* — `writeNeverClassifiesAsPermitted` runs 25
statements that mutate a real server and asserts none is permitted, rather than trusting the
case-by-case expectations to stay exhaustive. **The asymmetry is deliberate and written down:** a
read wrongly refused is an inconvenience seen immediately; a write wrongly permitted is silent,
reaches a production server, and is found afterwards or never.

Also reported with no coverage and still open: `Sources/GlassDatabase/KeychainManager.swift` (773
lines, live on every database service, including a credential-rollback path that fails silently)
and the `TableSchemaSQL` DDL builder (`TableDetailView.swift:4613`), whose `validatedType:4940` is
the guard stopping a column *type* string from carrying executable SQL into `ALTER TABLE`.

#### Why no test opened a window on the Database capability

Not an oversight in this port: **glassdb has no UI tests either** — one 194 KB unit file, no
XCUITest target, nothing outside vendored packages. The capability inherited the absence. The
workspace also carried accessibility *labels* but almost no *identifiers* (19 in the module, 16 of
them in the setup form), so it could not be driven even if someone had tried.

#### The `text`/`blob` item was mislabelled — filters never size-checked at all

The carried-forward item read: *"`text`/`blob` limits at six of eight MySQL families (bare
`text`/`blob` need the dialect at `GridColumnFilter`, deliberately left unconstrained)"*. That
described a narrower problem than the one that was there.

Threading a dialect into `GridColumnFilter.boundValue()` turned out to be **inert**:
`StagedEdit.boundValue()` is type *conversion* only (`RecordEditorView.swift:219`) and never
consults `ColumnTypeConstraint`. The size check lives in `StagedEdit.validationError:196`.
`GridColumnFilter.validationError` was a **second, weaker implementation** that called `boundValue()`
and stopped — so a grid filter ran **no size check at all**, on any type, on any engine.
`varchar(4)` accepted `"12345"` and returned an empty page with no explanation.
`ColumnTypeConstraint` was written to serve the record editor *and* the grid; only one was calling it.

**How it was caught, and this is the transferable part.** The first version of the new test
asserted only the dialect-dependent cases — bare `text` on MySQL versus PostgreSQL — and would have
passed for the wrong reason had the plumbing worked. Adding `varchar(4)`, which needs **no** dialect
and should have worked since the day size checking was written, is what exposed it. **A test aimed
only at the part you suspect will agree with you.** Same shape as R7's correction, arriving in a new
disguise.

**The fix, and the judgement in it.** `GridColumnFilter.validationError(dialect:)` now consults the
constraint — but **for `.equals` only**, and that limit is deliberate rather than an oversight:

| Operator | Out-of-range value | Decision |
|---|---|---|
| `=` | cannot match any stored row — the query provably returns nothing | **reported** |
| `<>` | matches *every* row | allowed |
| `<` / `>` | an ordinary way to express "all of them" | allowed |

A filter is a read, not a write, so the question is not "will the server store this?" but "can any
stored row match it?". Blocking the other three would refuse correct queries to enforce a rule that
does not apply to them. `onlyEqualityIsSizeChecked` exists to stop someone tidying that condition away.

The dialect is a **parameter, not a stored property**: a saved filter outlives its session and the
engine belongs to the connection, so storing it would persist a fact that can change — and it is why
`GridColumnFilter` stays `Codable` with no migration. Threaded at five call sites
(`TableDetailView.swift` filter validation, staged filters, display-filter evaluation, the server
query builder, and `ForeignKeyNavigation.filters`).

**A second defect, found by the suite and not by the compiler.** Changing `validationError` from a
property to a method left `ForeignKeyNavigationTests.swift:105` reading
`filters[0].validationError == nil`. That still **compiles**: the unparenthesised reference is a
*function value*, which `== nil` promotes to `Optional` and answers `false` for — a comparison that
can never hold and never warns. Worth knowing as a class: a property-to-method change does not
reliably break its call sites in Swift when they are compared against nil.

**Package: 729 tests / 63 suites, all passing.**

#### D15 hardened: the read-only gate now splits scripts

**Stated precisely, because the distinction matters: this was not a reachable vulnerability.**

`SQLHighlighter.safetyClassification` classifies **one** statement, from its leading keyword. Given
a script it answers for the first statement only, so `SELECT 1; DELETE FROM members` returns
`.readOnly` — the `DELETE` is past the point it looks at. That is correct behaviour for a function
documented to classify a statement, and it was measured, not assumed.

`ReadOnlyDatabaseConnection.checkReadOnly` passed the whole query string to it. **No caller sends a
multi-statement string**: both execution paths (`QueryEditorView.execute:951` and
`TableDetailView.execute:4039`) split with `statementsToExecute` and run `statement.text` one at a
time, which was verified before drawing any conclusion. So nothing was ever exposed.

**Why it was changed anyway.** The guarantee rested entirely on every caller splitting first, and
the file's own header argues against precisely that: *"Wrapping the connection is the only placement
where 'read-only' is a property of the session and not a property of how carefully the next surface
was written."* Trusting callers to have split puts the guarantee back in the caller's hands. A
"run script" command — the natural next feature for a SQL editor, and the obvious way to add one is
to pass the editor's text straight through — would have opened every write in the script at once,
silently, with nothing failing.

The gate now classifies **every** statement and refuses if any is not permitted. An empty or
unparseable string yields no statements, so the whole string is classified instead and returns
`.unknown`, which is refused — never permit by default.

Four tests pin it, including the two that stop it being over-tightened: a script of pure reads must
still pass, and a semicolon **inside a string literal** must not split a statement, or the hardening
becomes a way to refuse good reads.

**How it was found.** Not by reading the gate. A worker comparing our tests against glassdb's
mentioned the statement splitter in passing; the question "what does the classifier do with two
statements?" took one probe to answer. The same shape as the rest of this session — the defect, or
here the latent fragility, sat behind a question nobody had asked out loud.

**Package: 733 tests / 63 suites, all passing** — the seven existing `ReadOnlyServiceTests` included,
so the hardening did not change what the gate already refused.

## 2026-09-13 (later) — Stage 3.5 closed out; Stage 4 is next

**State DOCS.** Owner: coordinating agent. Working tree has uncommitted changes; **nothing has been
committed this session** — the user commits.

**Done here:** `GlasSecretStore` absorbed into `Sources/GlasSecretStore`; **D23** (pinned SSH host
keys synchronize, one configuration for them, eligible set public on `SecretStoreConfiguration`);
the D18 half-fix that left the trust prompt throwing, repaired; the Stage 2 tag-vocabulary UI
failure closed as two stale test assumptions rather than a product defect; `AGENTS.md` and
`memory-bank/toc.md` corrected where they still described the source apps as live software.

**Verified by running, not reading:** package 946 tests / 90 suites; macOS / iOS / visionOS app
builds; 5 real-host SSH transport tests; 21 live database tests; the macOS database UI suite 7/7
against real MySQL 8.4.11 and PostgreSQL 18.6; and `testConnectsToRealHostThroughTheShell`, which
now drives the **D14 trust prompt** — the first time anything has.

**The limit that has not moved:** no test proves CloudKit delivers anything, and now also none proves
a pin made on the Mac reaches the Vision Pro. Three tests in `HostTrustSynchronizationTests` report
**skipped** for a measured reason: an unsigned `swift test` process cannot write a synchronizable
Keychain item (`errSecMissingEntitlement`), and ad-hoc signing the entitlement gets the process
killed. The seven-item device checklist in
[Stage 3.5](tasks/2026-09/2026-09-13_stage-3.5-continuity.md) is still the only thing that can close
this, and it needs the user with two devices.

**Next action:** Stage 4 — the remote desktop capability, planned in
[Stage 4 — desktop](tasks/2026-09/2026-09-10_stage-4-desktop.md). `RDPCredentialStore` is already in
the absorbed module and `rdpCredentialsService` is already eligible, so the third credential kind
arrives with its mobility decided — which was the reason Stage 3.5 went first.

## 2026-09-13 (later still) — visionOS design pass 1 built, unverified on device

**State BUILD.** Owner: coordinating agent. Sequenced before Stage 4 by the user's decision, so the
desktop capability inherits the right patterns.

**Authorization:** *"pay attention to the design. it's terribly off"*, scope *"1 plus our
Glass/transparency/theme controls… 3 shouldn't be a separate wish, it's the goal"*, constraint
*"familiar to a Mac user, but visionOS magic to use."*

**Done:** ornament for primary actions; spatial sidebar widened rather than shrinking its contents;
gaze-scale row metrics and `hoverEffect`; visionOS row type scale; empty detail given its pane; host
sheet enlarged; **the window stopped painting a `Material` over visionOS's own glass**; **the
ornament inset stopped applying when no ornament is shown**. All spatial numbers in
`GlassSpatialMetrics.swift` (GlassConnectionKit), no-ops off visionOS.

**Verified:** package 946/90; macOS UI 25/25 after every change; builds for macOS, iOS Simulator,
visionOS Simulator and visionOS device; simulator captures at each step.

**Blocked and honest about it:** the headset was locked for the whole pass, so **none of this has
been seen on hardware**, and the simulator renders glass differently from what pass 1 changed. Also
undiagnosed: two on-device UI failures (`testCollectionsAreChipsAndFeed…`,
`testAddServiceCollectsTheAddressOnTheHost`) that pass on macOS.

**Next action:** with the headset unlocked, capture library, host detail and Edit Host sheet on
device; diagnose the two device failures from the result bundle; then the terminal and database
surfaces; then Stage 4.

## 2026-09-13 (evening) — builds 0.3.81 → 0.3.99, driven by the user

**State BUILD.** Owner: coordinating agent. Working tree committed at the end of this session.

**Verified:** 948 tests / 90 suites; macOS, iOS Simulator and visionOS Simulator all build;
`/Applications/GlassPowerTools.app` is **0.3.99**, version read back off the installed bundle.

**Landed:** D24 (the family's sidebar toolbar arrangement — keep AppKit's toggle on macOS, app action
on the content column at `.navigation`), D25 (deleting a machine deletes what its capabilities
stored), Workgroups as a contributed library panel, `GlassProduct.displayName`, Open Folder Here for
local *and* remote, native form fields, service icons under the machine name, remembered split-view
dividers, the caret colour via `GlassOnFilledLabelStyle`, and UI-test isolation for
`SharedDefaults`.

**Open, in the order the user is most likely to raise them:**

1. **The glass is over-transparent.** Columns stopped painting so the layering reaches them, and at
   the default `ultraThin` they read as bare wallpaper. Needs a look decision — a thicker default
   or opaque columns — not another patch.
2. **Network/Tailscale panel.** Workgroups proved the pattern; `TerminalTailscaleView` needs the same
   `presentation` + shared-model split and carries more state.
3. **SSH key records do not sync.** Diagnosed and not fixed: the *material* travels (D18) but the
   records live in `UserDefaults`. They belong in CloudKit beside the host catalog — the project's
   own rule is *"keep metadata separate from secrets"*, so bundling them into the Keychain item is
   the wrong fix. See [Stage 3.5](tasks/2026-09/2026-09-13_stage-3.5-continuity.md).
4. **Thousands of abandoned test `UserDefaults` suites** — 4,112 `GlassLayersTests.<UUID>` and more.
   See [test pollution](tasks/2026-09/2026-09-13_test-pollution.md).
5. **The visionOS device run**, with its two undiagnosed failures, and pass 1 of the design work
   still unseen on hardware.

**Proven on hardware this session:** CloudKit *delivers* — a host defined on the Vision Pro appeared
on the Mac unaided. That closes item 2 of the Stage 3.5 device checklist and is the first evidence
D19's transport works rather than only its merge rules.

**Next action:** the glass decision, then the Tailscale panel, then Stage 4.

## 2026-09-14 — the glass decision made; Stage 4 planned

**State: BUILD (glass, done) → PLAN (Stage 4).** Owner: coordinating agent. Working tree has
uncommitted changes; **nothing committed this session** — the user commits.

**The glass decision is closed.** The user chose the sidebar-weight material.
`GlassLayerState.default` is now `.regular`, and — the part that would have made it a no-op — the
store adopts it for anyone whose stored state is byte-for-byte the *old* default, since that value
was written by the store on first launch and never chosen. A `glass.layers.defaultRevision` stamp,
set unconditionally on every init, makes the adoption run exactly once, so a user who later picks
"Light" keeps it. Found by reading the consumer, not the declaration: the user's own
`~/Library/Preferences/com.glasspowertools.plist` held `{"opacity":0,"frost":1,"material":"ultraThin"}`,
so the default was never going to be consulted.

Verified: `swift test --filter GlassLayers` **27 tests / 4 suites**, and both new tests were watched
**failing** with the logic defeated before being trusted. macOS app **BUILD SUCCEEDED**.

**Stage 4 is planned** in [the Stage 4 plan](2026-09-13_stage-4-plan.md), from a measured survey
rather than the 2026-09-10 draft's estimates. Authorization: *"GlassDT works… feature for feature …
please create a plan to migrate the functionality"* and *"focus on the desktop screen sharing
features."* Key findings: glassDT's packages are **72,492 lines**, not the ~5,600 `AGENTS.md`
records; **~41,500 lines actually ship** (27,900 is test code, 8,510 is example apps that do not
move); the engine move adds **zero new external packages** because RDPKit's two `exact:` pins are
already what this project resolves; and **VNC/Apple Screen Sharing moves into Stage 4** because the
only reason it was deferred — sibling apps unable to decode a `.vnc` kind — is void.

**Next action:** the user's approval of the plan, and its three open decisions. Two read-only
surveys of glassDT are still running to add the feature-for-feature parity checklist.

## 2026-09-14 — Stage 4 W1/W2 shipped; the sync gap found

**State BUILD.** Owner: coordinating agent. Committed through `523c301`; tree clean.

**Done:** Stage 4 W1 (engines: `Packages/RDPKit` vendored with its licence chain, `Sources/VNCKit`
and both transports as targets, `THIRD-PARTY-NOTICES.md` created) and W2 (the desktop as a
capability of the shell — protocol picker, session window, D25 cascade). Live CloudKit updates via
silent push. **998 tests / 98 suites**, plus RDPKit's 1014. Installed and verified at **0.4.92 (95)**
on the Mac, an iPhone and the Vision Pro.

**Proven on real hosts this session:** RDP against **Windows 11 Pro with NLA** — the certificate
correctly refused unpinned, then a 1280×800 frame in 0.84s pinned; VNC against **TigerVNC 1.15.0**;
and, by the user in the running app, a **signed-in Apple Screen Sharing session** on security
type 30 — which closed Stage 4.5 items 1 and 2 and retired the largest unknown in either stage.

**The open decision, and it is the user's:** [connection records do not
sync](tasks/2026-09/2026-09-14_connection-records-do-not-sync.md). The catalog travels; no
capability's own record does, so a second device shows the host, the service row and holds the
password, then says "has no saved configuration". Three options are written up with a
recommendation (A: an opaque `configuration: Data?` on `HostServiceLink`, no CloudKit schema
change). **Nothing is being built until that is chosen** — it is an architecture decision, not a fix.

**Also recorded:** a first diagnosis of this was wrong — publishing was never missing, because every
mutation ends in `load()`, which syncs. Checking the callers of the callers corrected it.

**Next action:** the sync decision, then Stage 4 W3 (presentation and input verified on real hosts),
W4 (the 40-item parity sweep), W5 (spatial on the headset). The user has asked for all four parity
gaps: desktop on Vision Pro, desktop on iPhone/iPad, remembered dividers everywhere, and SSH key
records — the last of which the sync decision subsumes.
