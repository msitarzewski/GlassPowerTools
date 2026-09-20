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

## 2026-09-14 — the remainder planned end to end

**State PLAN.** Owner: coordinating agent. Tree clean at `57bca0b`; nothing built from this plan.

Authorization: *"Please create a thorough plan for the remainder of the work. Reuse is essential,
we're working on a professional and public codebase. Be precise in your edits."*

[The remaining work](tasks/2026-09/2026-09-14_remaining-work-plan.md) covers D26 stages 1–5, Stage 4
W3–W6, Stage 4.5 items 3–8, the carried-over items, and Stages 5–6, each with the existing
implementation it extends and the line it extends at.

**Four things the survey changed, all measured rather than remembered:**

1. **D26 has no identity migration.** `EndpointID.rawValue` is already each capability's record UUID
   in all three (`GlassTerminalCapability.swift:198`, `GlassDatabaseCapability.swift:116`,
   `GlassDesktopCapability.swift:90`). Stage 1 relocates bytes and re-keys nothing.
2. **The database already has the seam the other two need.** `ConnectionPersistenceStore`
   (`ConnectionManager.swift:31-54`) is an injectable load/save/restore triple with a readback check.
   The terminal's reads bypass its own injection point (`ServerManager.swift:229-231` against the
   `serverDataWriter` at `:196-215`); the desktop has a file-backed actor to delete outright.
3. **Stage 1 shrinks stage 2.** Once a configuration lives on the link, a tombstone takes it along,
   so the synced-deletion cascade has only Keychain credentials left to clean up.
4. **The abandoned test defaults suites are 17,905, not 4,112 — and the tests are not at fault.**
   `MacWorkspaceTests.swift:2502-2520` balances 24 fixtures against 24 `cleanup()` calls;
   `removePersistentDomain` empties the domain and leaves a 42-byte empty plist behind. Sweeping the
   files fixes today and changes nothing. Naming each suite after its test rather than a fresh
   `UUID()` bounds the count — proposed, not decided.

**The magic directive** (*"familiar to a Mac user, but visionOS magic to use"*) is recorded in the
plan as binding two items: the key manager, which is the only genuinely new surface in the whole
remainder, and Stage 4 W5. Both are designed on the headset's terms and adapted down.

**Next action:** the user's go on D26 stage 1, starting with the terminal — it is the one capability
with a second index over the same data, so its call sites surface the questions the other two will
not.

## 2026-09-14 (evening) — D26 stage 1 underway; D27 and D28 approved

**State BUILD.** Owner: coordinating agent. Committed through `0eee30e`.

**Landed:** the terminal's `ServerPersistenceStore` seam, with the write path converted to async
because `HostCatalogStore` is an actor. Still `UserDefaults`-backed on purpose — the step moves the
seam, not what is behind it. **1146 tests / 117 suites** green, stable across two runs. The rollback
contract was pinned by tests written first and watched failing.

**One real behaviour change:** the legacy host-trust migration no longer completes during
`loadServers` (which `init` calls and cannot await); it runs in a task the manager holds. D26 deletes
that migration outright anyway.

**Two decisions approved this evening:**

- **D27** — every saved connection gets a host record, created *for* the user. SSH config import and
  the standalone Add Server form currently make servers with no host and no link, and those servers
  are already invisible in the library. Both forms stay as they are and raise the host record behind
  the scenes.
- **D28** — what authenticates what is **derived, never stored**. No usage table; the edge is
  `sshKeyID` on the service's configuration. Only SSH keys are shared many-to-one; passwords, RDP
  and database credentials are 1:1, and the database holds no key at all (D7).

**Environment cleanup, not a code change:** 35,865 abandoned test defaults plists and 23 test host
catalogs removed from this Mac; `~/Library/Preferences` went 37,175 → 1,310. The count had nearly
doubled since morning — **a full `swift test` run costs roughly six thousand files** — so bounding
the suite names remains the actual fix. `ai.mirrormesh.tests` was deliberately left: another
project's residue.

**Next action:** plan D27 and D28 properly before building — survey every surface that creates,
edits, deletes or displays a saved connection or a credential, because the reverse index is only
correct if every edge-writing path is known. Then build D26 stage 1's remaining half.

## 2026-09-15 — D27 built; two grammar patches restored; the verification method corrected

**State BUILD.** Owner: coordinating agent. Committed through `1adbea9`; tree clean.
**Full suite: 1473 tests / 155 suites, exit status 0.**

### The correction that matters most

**Every test count reported before today was wrong.** A test target that aborts prints no `✘` line
*and* no `Test run with N tests` line, so verifying by grepping for failures and summing the counts
sees a crashed target as neither. `GlassEditorCoreTests` had been aborting since `57bca0b` —
**320 tests and 36 suites** missing from every figure (1146, 1153, 1169). **Exit status is the
check.** The `Note: Some test targets reported failures:` trailer is the second signal; it appeared
and was misread as being about the target then under refactor.

### Two security patches were dropped and are restored

`57bca0b` swapped GlassEditorKit's **vendored** grammars for pinned upstream revisions. The kit's
sources were not stock:

- **markdown (pen H-1)** — upstream's `serialize()` copies every open block into a fixed 1024-byte
  buffer unbounded: above 254 open blocks it overruns. Heap corruption in release, **reachable by
  opening a deeply-nested markdown file**. `ScannerOverflowPenTests` aborted on every run.
- **SQL (pen M-5)** — `serialize()` frees and nils `start_tag`, consuming the state it was asked to
  snapshot; `deserialize()` overwrites the pointer without freeing or checking it. Still present on
  upstream HEAD, so a newer pin was not the fix.

Both are vendored again at the pinned commits with the patches restored; `parser.c` is byte-identical
to upstream in each, only `scanner.c` differs. **The "41 MB" that drove a fork recommendation was the
working-tree size** — git stores SQL's parser in **2.6 MB**. `.git` is 13 MB.

**M-5 could not be reproduced through behaviour** — not by the existing smoke test, not under
AddressSanitizer, not by an incremental-versus-full highlight comparison with the incremental path
asserted. It is patched because the code is wrong, and `THIRD-PARTY-NOTICES.md` now distinguishes
*guarded by a test* from *applied on inspection*.

### Landed this session

- **`.rdp` import wired** (`ce2b966`). Its only caller had lived in `DesktopLibraryView`, the file
  the merge deleted. Parse off-main → the shell's Add Host sheet pre-filled, notices shown → Save
  through the ordinary flow. glassDT's parser tests ported plus four that walk the seam.
- **D27** (`1adbea9`). `adoptService` / `discardAdoption`; Add Server and `ssh_config` import both
  put machines in the library, reusing a record that already has the address.
- **D26 stage 1 seam** (`0eee30e`): `ServerPersistenceStore`, write path async because the catalog
  is an actor.
- A flaky staging assertion fixed; 35,865 abandoned test plists and 23 test catalogs swept.

### Rules earned this session

1. **Never `git checkout --` a file with uncommitted work** to undo a deliberate defeat — it took
   the prefill implementation with it. Edit the defeat back out in place.
2. **A test written against the wrong projection looks exactly like a passing test.** Two this
   session: `catalogHosts` hides a duplicated record because the grouping merges by address; the SQL
   pen test passes with the bug present.

**Next action:** D26 stage 1's remaining half — the catalog-backed store, `UserDefaultsKeys.servers`
deleted with its two legacy-migration entries, and the `SettingsManager.swift:574` read of the raw
defaults key that bypasses `ServerManager`.

## 2026-09-15 (evening) — D26 stage 1 terminal half done; live RDP and VNC proven; 0.4.107 installed

**State BUILD.** Owner: coordinating agent. Committed through `4471a2e`; tree clean.
**Package: 1481 tests / 157 suites, exit status 0.** Installed **0.4.107 (107)** on this Mac,
version read back off the bundle.

### Landed

- **D26 stage 1, terminal half** (`5b6bac3`). Saved servers live on their service links.
  `UserDefaultsKeys.servers` is no longer the production store and is out of both legacy
  migrations. Deletion cascades to the link through `detachService` — link-only, because the
  capability is the one deleting and `removeService` would call back into the running delete.
- **D27** (`1adbea9`). `adoptService` / `detachService`; Add Server and `ssh_config` import put a
  machine in the library, reusing a record that already holds the address.
- **Stage 4 W3 live evidence** (`f5d6bec`, `e435454`). Both engines proven against real hosts on
  **this** build rather than inherited from glassDT's ledger.
- **`connectToLibrary`** (`4471a2e`) — one public door on the terminal runtime.

### Live results, all real executions

| Host | Result |
|---|---|
| TigerVNC 1.15.0, Ubuntu 26.04.1, `192.0.2.6:5902` | **PASS** — 1024×640 first frame in 0.21s |
| GNOME Remote Desktop 50.2, same VM, `:3389` | **PASS, signed-in session** — 1360×768 frame in 0.41s, after refusing the certificate unpinned and reporting a leaf SHA-256 identical to the one minted on the VM minutes earlier |
| Windows 11 Pro, `192.0.2.3:3389` | Certificate refusal reproduces; leaf byte-identical to the 2026-09-14 record. **No signed-in session** — the `gptrdp` password died with September's scratchpad and Windows has no SSH here |
| Windows TightVNC, `:5900` | Typed error *"This server needs a VNC password"* |

**Neither real RDP server advertised MS-RDPEDISP.** Two of two decline it, so "resize works" stays
unclaimed for both.

### Four rules this session paid for

25 (verify by exit status — an aborting target prints no failure line *and* no count line, and
320 tests were missing from every figure), 26 (never `git checkout --` a file with uncommitted work),
27 (a test written against the wrong projection looks exactly like a passing test), 28 (`mktemp` /
`Code=513` means the screen is locked), 29 (an OOM kill leaves nothing — run a suspect test under a
memory watchdog), 30 (a pty echoes what you send it), 31 (`which` proves only what is on `PATH`).

### The verification gap the install exposed

`swift build` and `swift test` **do not compile the App target** — it lives in the Xcode project,
not the SwiftPM package. The composition root reached `sessionManager`, which is `internal`, and
both were green while the app could not build at all. **A package suite passing is not the app
building**; an install is the only proof of that.

**Next action:** D26 stage 1's remaining two capabilities — the database (`glassdb.connections`)
and the desktop (`connections.json`).

## 2026-09-15 (late) — D26 stages 1–3 built; stage 4 next

**State BUILD.** Owner: coordinating agent. Committed through `0e1ce68`; tree clean.

**Done:** stage 1 (all three capabilities keep their records on their service links), stage 2 (a
machine deleted on another device cleans up here), stage 3 (device-bound services never leave this
device, and key records live in the Keychain beside their material).

**The three pieces of stage 3 that have to agree**, and the one that was not in the plan: publish
redacts, apply re-attaches, and **stage 2 excludes** — without the third, a redacted service reads
as *deleted elsewhere* on the next sync and stage 2 deletes its credential. The two stages would
have quietly undone each other.

**Verification owed.** The last full run could not complete: the screen locked (rule 28, now
extended — it fails reads as `Code=257` too, and most failures carry no signature at all). Last
complete run was **1497 tests / 161 suites, exit status 0**; the app target builds. **Repeat the
full run unlocked.** Installed build is still **0.4.107**, which predates stages 1–3.

**Next action:** stage 4, the key manager panel with "used by" — a read across the catalog, which is
what stages 1 and 3 were for. Then the two-device acceptance run, which no test replaces.

## 2026-09-16 — resume notes (SUPERSEDED — see the RESUME HERE block at the end of this file)

**State BUILD.** Owner: coordinating agent. Tree clean at `810e8b9`. **1506 tests / 163 suites,
exit status 0**, verified by exit status; the app target builds separately (rule 32).

### Where the work actually is

**D26 is built through stage 4's model layer.** Stages 1, 2, 3 and D28's "used by" are done *and
verified*. What remains of D26 is **stage 4's panel** and **stage 5's storage cleanup**.

| Piece | State |
|---|---|
| Stage 1 — all three capabilities keep records on their service links | done, verified |
| Stage 2 — a machine deleted elsewhere cleans up here | done, verified |
| Stage 3 — device-bound services never leave; key records in the Keychain | done, verified |
| Stage 4 — `services(usingKey:)` / `usageCount(ofKey:)` | done, verified |
| Stage 4 — the key manager **panel** | **not started** |
| Stage 5 — storage cleanup | not started |

### Start here, in this order

1. **Install a current build.** `/Applications/GlassPowerTools.app` is **0.4.107**, which predates
   all four stages. Build with `MARKETING_VERSION=0.4.<commit count>` and read the version back off
   the bundle (rule 16).
2. **The two-device acceptance run.** Add a host with a key on the Mac, connect from the phone
   **without re-approving host trust**. That one run proves configuration sync, key record sync and
   D23's pin sync together. *Everything in D26 is currently proven by unit tests and a single-device
   app; the sentence the product is has never been run.*
3. **The key manager panel** — the last of stage 4. A contributed `GlassLibraryPanel` beside
   Collections (copy `GlassTerminalCapability.libraryPanels()`, which is Workgroups and is the only
   existing consumer). Name, algorithm, fingerprint, added date, *iCloud* / *This device only*
   badge; per key rename, copy public key, export public key, **used by**, delete naming what it
   will unassign. It is a **read** over `services(usingKey:)` and `usageCount(ofKey:)` — the model
   layer is done. **The magic directive applies: design it on visionOS terms first, adapt down.**

### Things that will bite the next session

- **The screen lock.** Rule 28. Every catalog write is `.completeFileProtection`; locked, it fails
  as `mktemp`/`Code=513` on write and `Code=257` on read, **and most failing tests carry no
  signature at all** — they are assertions downstream of a write that never happened. Check
  `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked` **before** diagnosing anything. Run
  long suites under `caffeinate -dimsu`.
- **`swift build` never compiles the App target** (rule 32). Build the app separately, every time.
- **Verify by exit status, never by grepping for `✘`** (rule 25). An aborting target prints neither
  a failure line nor a count.
- **After replacing a protocol requirement, grep for the old name** (rule 33). A conformer that
  still implements it keeps compiling and silently takes the default — it cost four stage 3 tests
  that went on passing while proving nothing.

### Environment left running

Both Parallels VMs are configured and were up. Ubuntu `192.0.2.6`: TigerVNC on **5902**, and
**GNOME Remote Desktop on 3389** (username `gptrdp`, password in this session's scratchpad, cert
fingerprint `0b:7a:6e:22:…:ee:bf:c7`). Stop with `systemctl --user stop gptvnc` and
`grdctl rdp disable && systemctl --user stop gnome-remote-desktop`. Windows `192.0.2.3`: RDP 3389
and TightVNC 5900, neither provisioned by us — the September `gptrdp` password died with that
session.

### After D26

Stage 4 W3's remainder (input, held-key release, clean disconnect — needs the session window, not a
probe), W4's 40-item parity sweep, **W5 spatial on the headset — still the only unknown-size item in
the plan**, W6 audit. Then Stage 4.5 (VNC-over-SSH; **sleep/wake, which our own testing table
requires**; measured performance; RD Gateway optional). Carried: Tailscale is still a window not a
panel, visionOS pass 1 unverified with two on-device failures, the database workspace one-line
greedy-frame fix, remembered dividers per platform. Then Stage 5 (the editor interface) and Stage 6
(deprecate the public repos — **not without the user's word**).

**Full detail:** [the remaining work](tasks/2026-09/2026-09-14_remaining-work-plan.md), which carries
the execution log for every stage and the surface survey behind D27/D28.

## 2026-09-16 (later) — resume notes (SUPERSEDED — see the RESUME HERE block at the end of this file)

**State BUILD.** Tree clean at `2358d08`, commit count **119**.
**1509 tests / 164 suites, exit status 0.** The app target builds on macOS, iOS and visionOS.

### Installed right now

| Platform | Version | How verified |
|---|---|---|
| macOS `/Applications/GlassPowerTools.app` | **0.4.119 (119)** | read off the bundle |
| iPhone 17 Pro Max `00000000-0000000000000A02` | **0.4.119 (119)** | read off the device |
| Vision Pro `00000000-0000000000000A01` | **not installed** | built and signed; the headset is paired but timed out — it was asleep |

**Finish the Vision Pro install first.** The app is already built at
`<scratchpad>/dd-xros/Build/Products/Release-xros/GlassPowerTools.app`; wake the headset and
`xcrun devicectl device install app --device 00000000-0000000000000A01 <path>`, then read the
version back (rule 16). If the scratchpad is gone, rebuild with
`-destination 'platform=visionOS,id=00000000-0000000000000A01'`.

### Where D26 stands

Stages 1, 2, 3 and stage 4's **model layer** are built and verified. Remaining: **stage 4's key
manager panel** and **stage 5's storage cleanup**.

### Do these next, in order

1. **Vision Pro install** (above).
2. **The two-device acceptance run.** Add a host with a key on the Mac, connect from the phone
   **without re-approving host trust** — that single run proves configuration sync, key record sync
   and D23's pin sync together. Then: delete the connection and confirm the key survives; generate a
   Secure Enclave key and confirm that terminal does **not** appear on the phone while the database
   on the same host still does; sync twice with it in place. **D26 has never been run across two
   devices. Everything is proven by unit tests and a single-device app.**
3. **The key manager panel** — the last of stage 4. A contributed `GlassLibraryPanel` beside
   Collections; copy `GlassTerminalCapability.libraryPanels()` (Workgroups), the only existing
   consumer. Name, algorithm, fingerprint, added date, *iCloud* / *This device only* badge; per key
   rename, copy/export public key, **used by**, and a delete naming what it will unassign. It is a
   **read** over `model.services(usingKey:)` and `model.usageCount(ofKey:)`, which are done and
   tested. **The magic directive applies: design it on visionOS terms first, adapt down.**

### What just bit, and will again

- **A test double more permissive than production certified a broken build.** `GlassInMemoryServiceStore`
  stores a configuration for any endpoint id; the real model requires a service link. 1506 tests
  passed while adding a service was impossible — the user saw *"That service is no longer on the
  host."* on the first install. **Fixed** (link first, then the record) and covered by
  `Tests/GlassTerminalTests/D26SetupSheetSaveTests.swift`, which drives the real model. When a
  capability's storage is involved, test against `GlassShellModel`, not the double.
- **Platform-conditional code is invisible to a macOS build.** An iOS-only `#if` branch in
  `TerminalConnectFlow` had never been compiled by any check that had run. Build all three before
  believing a refactor is done.
- Rules earned this session and worth re-reading before touching anything: **25** (verify by exit
  status), **28** (the screen lock, which fails reads too and leaves most failures unsigned), **32**
  (`swift build` never compiles the App target), **33** (replacing a protocol requirement silently
  orphans conformers).
- Run long suites under `caffeinate -dimsu`. Check
  `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked` **before** diagnosing any file failure.

### Environment left running

Ubuntu `192.0.2.6`: TigerVNC on **5902**, **GNOME Remote Desktop on 3389** — username `gptrdp`,
password in this session's scratchpad (`grd.pw`), certificate fingerprint `0b:7a:6e:22:…:ee:bf:c7`.
Stop with `systemctl --user stop gptvnc` and
`grdctl rdp disable && systemctl --user stop gnome-remote-desktop`.
Windows `192.0.2.3`: RDP 3389 and TightVNC 5900, **neither provisioned by us** — September's
`gptrdp` password died with that session, so a signed-in Windows RDP session is still unproven.

### After D26

Stage 4 W3's remainder (input, held-key release, clean disconnect — needs the session window, not a
probe; both VMs are configured), W4's 40-item parity sweep, **W5 spatial on the headset — still the
only unknown-size item in the plan**, W6 audit. Then Stage 4.5 (VNC-over-SSH; **sleep/wake, required
by our own testing table**; measured performance; RD Gateway optional). Carried: Tailscale is still
a window not a panel; visionOS design pass 1 unverified with two on-device failures; the database
workspace one-line greedy-frame fix; remembered dividers per platform. Then Stage 5 (the editor
interface) and Stage 6 (deprecate the public repos — **not without the user's word**).

**Full detail:** [the remaining work](tasks/2026-09/2026-09-14_remaining-work-plan.md) — it carries
the execution log for every D26 stage and the surface survey behind D27/D28.

## 2026-09-16 (evening) — RESUME HERE

**State BUILD.** Owner: coordinating agent. **Uncommitted** — 12 files modified, 8 new. The user has
not asked for a commit.
**1527 tests / 167 suites, exit status 0** (the one "known issue" is the editor's pre-recorded ReDoS
finding, not a new failure). Package builds; the app target builds on **macOS, iOS and visionOS** at
0.4.120.

### What this session did, and why it interrupted D26

The user reported against the installed 0.4.119: *"Command-T doesn't work for a new tab/session."*

**The terminal had no File menu at all.** Two scenes replaced `CommandGroup(.newItem)` — the
database's and the terminal workspace's — and SwiftUI keeps one. Read out of the running app with
System Events, the File menu was entirely the database's: no *New Terminal Window*, no ⌘T, no
⌥⌘T *Connect Saved Host…*, and the `replacing: .saveItem` group gone too, so **⌘W closed the window
instead of the tab**. This is now **rule 34**.

Fixed the way the user asked for: **⌘N is a stub the focused window aims** —
`GlassNewItemAction` carries the title and the action through `\.glassNewItem`, so ⌘N is *New SQL
Document* in a database workspace, *New Terminal Window* in a terminal workspace, *New Host* in the
library, and a disabled *New* elsewhere. `GlassShellFileCommands` is the one scope that replaces the
placement; capabilities append with `after:` and keep their items unbound.
**⇧⌘T is new**: "New Tab on oscar", copying the focused pane's intent so it connects with no chooser.

**D26 stage 4's panel is built.** `GlassKeyManagerPanel` in the shell, contributed through
`GlassShellModel.libraryPanels()` and joined at `GlassShellLibraryView`. `GlassKeyStore` is the
contract; `GlassTerminalKeyStore` forwards every call to `SettingsManager`, so the journalled delete
and the import/generate/rename sheets are reused rather than rewritten. Settings' SSH Keys section is
now one line pointing at the library. Fingerprints come from `OpenSSHPublicKeyLine` (GlasSecretStore),
checked against `ssh-keygen -lf`, and the transport's own fingerprint now goes through it too.

### Do these next, in order

1. **Install 0.4.120 and look.** *The app was running with the user's live oscar session all session,
   so nothing was installed.* Quit it first, then install and **read the menu bar back**
   (rule 34's `osascript` line) to confirm ⌘T, ⇧⌘T and — still unproven — that ⌘W is *Close Tab*
   again. Then open the library and confirm the **Keys** panel is actually in the sidebar: that line
   is a view, no unit test reaches it, and a missing join is this project's most repeated defect.
2. **The Vision Pro install**, still owed from the last session. The 0.4.119 build is at
   `<scratchpad>/dd-xros/Build/Products/Release-xros/GlassPowerTools.app`; a 0.4.120 visionOS build
   is at `$TMPDIR/dd-xros-check`. The headset refused the last attempt with
   `CoreDeviceError 10003` — *the device has not been unlocked recently*. It has to be worn and
   unlocked.
3. **The two-device acceptance run.** Still never done, still the only thing that proves D26's
   sentence. Add a host with a key on the Mac, connect from the phone **without re-approving host
   trust**; delete the connection and confirm the key survives; generate a Secure Enclave key and
   confirm that terminal does *not* appear on the phone while the database on the same host still
   does; sync twice with it in place.
4. **D26 stage 5**, storage cleanup — the last of D26.

### Open question for the user

Nothing blocking. One decision was made and is easy to reverse: *New Terminal Window* and *New SQL
Document* keep their menu items but no longer carry their own ⌘N, because ⌘N is now the contextual
one. If either should keep a dedicated key, it is a one-line change.

### Environment

Unchanged from the previous block: Ubuntu `192.0.2.6` (TigerVNC 5902, GNOME RD 3389, `gptrdp`),
Windows `192.0.2.3` unprovisioned. Rules that bit today: **34** (new), 25, 32.

## 2026-09-16 (evening) — every device on 0.4.123

The user cleared the old `glas*` builds off the iPhone — *"No more glas* apps on my iphone at all"*
— and clarified the intent the same evening: *"Oh, you can install on iPhone. I just wanted to make
sure that it was clean."* A clean slate, not an exclusion. **Stale builds are the hazard, not the
phone**: a phone on the pre-fix build kept republishing erased configurations through the catalog
sync, which is why fixing the Mac alone did not hold.

Rule to carry: **every device is on the current build or on nothing.**

Installed now, each read back off the bundle or the device: **macOS
`/Applications/Glass Power Tools.app` 0.4.123**, **iPhone `00000000-0000000000000A02` 0.4.123**,
**Vision Pro `00000000-0000000000000A01` 0.4.123**. The headset had
been sitting on **0.4.92 (build 95)** — pre-D26, and therefore a live copy of the defect that erased
configurations and republished the erasure through the catalog sync. It was the last device that
could have re-opened the loop; it is now current.

**Any two of the three serve for the D26 acceptance run**, which is still owed and is the only
thing that proves the catalog travels.

## 2026-09-16 (night) — 0.4.130 (SUPERSEDED — see the RESUME HERE block at the end)

**Installed:** macOS **0.4.130**, iPhone **0.4.130** (both read back). Vision Pro is built at
`$TMPDIR/dd-xros-130/Build/Products/Release-xros/Glass Power Tools.app` and refused with
`CoreDeviceError 10003` — locked again after the 0.4.123 install went through.

**1,557 tests, exit status 0.** Three commits today: the persistence and menu-bar work
(`c67bb62`), stage 5's editor (`65ca7bd`), six grammars (`4247347`).

### Stage 5 as it actually stands

Built: documents, tabs, save/save-as with byte-identical round trips, find and replace, go to line,
recents, drag and drop, a project tree over a local folder, and a window whose ⌘N means New Document.
Twelve languages now colour — the six original config formats plus Python, JavaScript, Go, Rust, C
and PHP — and because the SFTP remote editor picks its grammar the same way, files opened on a
server through the Files browser colour too.

**Not built, and it is the half that matters:** `GlassEditorDirectoryReader` has one implementation,
the local file system. A project on another machine shows its badge and cannot be browsed. The SFTP
reader needs a broker — rule 6 forbids the editor importing the terminal — shaped like
`GlassCapabilityHostAccess`: the shell asks whichever capability owns `.ssh` for a directory listing
and a file's bytes, and the editor never learns who served it.

**After that, in the order argued from the market:** project-wide search by running `rg --json` on
the far machine; git status in the tree from `git status --porcelain=v2`; then **server-side LSP**,
which is the differentiator — run the language server *on the remote host* over an SSH exec channel
and speak LSP across its stdio, so an iPad gets completions and diagnostics from the machine that
has the toolchain. The engine's `CompletionProvider`, `DiagnosticsProvider` and
`StatementBoundaryProvider` are already the seam; nothing needs re-architecting, something needs to
conform. Two to three weeks, not an afternoon.

**Still owed from before all of this:** the D26 two-device acceptance run, and the test hygiene —
1,519 keychain items and the preference-file sprawl from suites using the real Mac as scratch space.

## 2026-09-16 (late) — RESUME HERE

**State BUILD.** Owner: coordinating agent. **1,563 tests / exit status 0.** macOS, iOS and visionOS
all build.

### Installed

| Platform | Version |
|---|---|
| macOS `/Applications/Glass Power Tools.app` | **0.4.153** — the editor with one workspace per window, rounds two to four |
| iPhone `00000000-0000000000000A02` | **0.4.143** — installed 2026-09-17, version read back off the device |
| Vision Pro `00000000-0000000000000A01` | **0.4.123** — locked at every later attempt |

The process is now `Glass Power Tools` (rule 37): **`pgrep -x GlassPowerTools` matches nothing**, and
the bundle installs to `/Applications/Glass Power Tools.app`.

### What today was

Four defects found by *using* the app, not by testing it — and the two hardest were in the
projection rather than the data, with the records on disk correct the whole time (rule 38).

1. **Settings were being deleted by the code that loaded them.** An unread catalog answered
   "nothing", a capability believed it, and the next write reconciled the catalog to match.
   `isCatalogLoaded` + `GlassServiceRecords.replaceAll` refusing + `catalogDidLoad()`.
2. **One deleted machine stopped this device publishing, permanently.** The sync applied incoming
   records with `upsert` — the local-edit path, which refuses a tombstone — and the publish sits
   below that loop. `merge(_:)` was always the right API. The sync now logs its counts and its
   failures; the silence is what made it cost a day.
3. **The terminal had no File menu.** Two scenes replaced `CommandGroup(.newItem)`. The shell owns
   the placement now, with one New item the focused window aims (rule 34).
4. **"This Mac" vanished** the moment the sync started working — see rule 38.

Plus: D26 stage 4's key manager panel, stage 5's editor, twelve highlighted languages, the product
renamed *Glass Power Tools* everywhere (rule 37), pull-to-refresh and a background context menu in
the library, a way back to Connections from a database workspace, and a connect failure that names
the machine and suggests the tunnel.

### Do these next, in order

1. **Put 0.4.132 on the phone**, and the Vision Pro when it is unlocked. Every device current or
   empty (the memory `no-glass-apps-on-the-iphone` records why).
2. **The editor's remote half** — the whole of stage 5's remaining value, laid out step by step in
   [the remaining work](tasks/2026-09/2026-09-14_remaining-work-plan.md) under *"Stage 5 — what is
   left, in order"*. The user asked for exactly this: right-click a folder in the SFTP browser →
   **Open in Editor** → a tree over that remote folder, with the project tracked as `(hostID, path)`
   so it follows him between devices.
3. **The editor has no entry point on iOS or visionOS.** Contribute it as a library panel beside
   SSH Keys.
4. **The D26 two-device acceptance run**, still never done, and now easy: two devices are current
   and the catalog demonstrably syncs.
5. **Test hygiene.** 1,519 keychain items (`test.SSHHostTrust.*`, `test.KeychainOps.*`) and the
   preference-file sprawl, from suites using the real Mac as scratch space. Bounded names or a test
   keychain. Nothing in the app is wrong; the tests are rude.

### Things that will bite

- **Rules earned today: 34** (one owner per command placement; read the menu bar out of the running
  app), **35** ("not read yet" and "empty" are different answers), **36** (there is no legacy — do
  not write migration code), **37** (the product's name, and `INFOPLIST_KEY_CFBundleName` is
  accepted and ignored), **38** (the projection is not the data; a fix can make a latent defect
  reachable).
- `swift build` never compiles the App target (rule 32). Build all three platforms before believing
  a refactor is done — an iOS-only `#if` branch is invisible to a macOS build.
- The screen lock still fails catalog writes with no signature (rule 28). `caffeinate -dimsu`.
- Reading the app's own log is now the fastest diagnosis available:
  `log show --last 5m --predicate 'subsystem == "com.glasspowertools"' --info`.

### Environment

Ubuntu `192.0.2.6`: TigerVNC 5902, GNOME RD 3389, user `gptrdp`. Windows `192.0.2.3`
unprovisioned. oscar `192.0.2.10`: SSH open, **MySQL on 3306 is not reachable from outside** —
it needs the service's SSH tunnel switched on, which is what the new connect error now says.

## 2026-09-17 — RESUME HERE (supersedes the 2026-09-16 block above)

**State BUILD.** Owner: coordinating agent. **1,578 tests / exit status 0**, run unlocked. macOS,
iOS and visionOS all build.

### Installed

| Platform | Version |
|---|---|
| macOS `/Applications/Glass Power Tools.app` | **0.4.158** |
| iPhone `00000000-0000000000000A02` | **0.4.143** — before the editor's rounds two to four |
| Vision Pro `00000000-0000000000000A01` | **0.4.123** — far behind; not attempted since 2026-09-16 |

### What today was

The user tested and reported; nearly everything here was found by **using** the app, and several
were design errors of mine rather than slips:

1. **One workspace per window.** The editor kept one for the whole app, so ⇧⌘E gave a window with
   the same documents in it. Split into `GlassEditorPreferences` (shared: text size, line numbers,
   wrapping, recents) and `GlassEditorWorkspace` (per window: documents, projects, selection, find),
   with a value-based `WindowGroup`.
2. **A desktop configuration read as lost** and the user deleted the service. The record was in the
   catalog; `catalogDidLoad()` defers the read, and the edit sheet asked the model rather than the
   catalog. It asks the catalog now (D26: the catalog *is* the record).
3. **The editor rendered the first document forever** with several open — `GlassEditorView` had no
   view identity, and the engine observes its model rather than being pushed values.
4. **⌘O joined ⌘T, ⌘N and ⌘W** as a key two items claimed. Four now, each with a guard.
5. Swift and XML grammars vendored; SQL probed and found correct, so left alone.
6. The header, footers, fonts, tabs, title/subtitle and Open behaviour, across four rounds.

### Do these next, in order

1. **The gutter.** The line-number strip reaches into the title bar. Stop using `NSRulerView` and
   draw the gutter beside the text. Three patches at three links in that chain missed, and the app's
   own geometry cannot be measured from this shell — the unified log stopped answering for the
   process and the sandbox container is closed. Do not attempt a fourth patch; change the shape.
2. **The phone and the headset.** 0.4.143 and 0.4.123. Every device current or empty.
3. **Stage C — Projects as a library panel**, with persistence and sync. It also gives the editor an
   entry point on iOS and visionOS, which it still has none of.
4. **Stage D — the editor's remote half**, which is still the largest piece of stage 5.
5. **The D26 two-device acceptance run**, and the test hygiene.

### Things that will bite

- **Rule 32 three times in one refactor.** `homeDirectoryForCurrentUser`, `navigationSubtitle` and
  `controlActiveState` are all macOS-only; a type-check timeout appeared on iOS and visionOS first,
  because they carry a settings sheet the Mac does not. Build all three, every time.
- **Rule 28 costs twenty minutes if you forget it.** A locked screen fails every
  `.completeFileProtection` write; `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked`
  settles it in one line. It was consulted last, after disk space and `TMPDIR`.
- **The type checker gives up on this view's `body`** and reports it as a timeout. Three modifiers
  hold what used to be inline: `MacEditorWindowBehaviour`, `GlassEditorWindowLifecycle`,
  `GlassEditorDialogs`.
- Reading the running app's **menu bar** through System Events is still the fastest way to see what
  the menu bar actually became. Reading the app's **log** is not currently available to the shell.

## 2026-09-17 (afternoon) — RESUME HERE (supersedes the block above)

**State BUILD.** Owner: coordinating agent. **1,620 tests / exit status 0** (re-run unlocked), plus **7 live tests against `192.0.2.6`**, green. macOS, iOS and
visionOS all build. Plan and detail:
[the gutter and stage C](tasks/2026-09/2026-09-17_gutter-and-stage-c.md).

### Installed

| Platform | Version |
|---|---|
| macOS | **0.4.167** |
| iPhone `00008150` | **0.4.167** — desktop on the phone confirmed working by the user at 0.4.166 |
| Vision Pro `00008112` | 0.4.123 — paired but **locked**; unlock it and the same build installs |

### What changed

1. **The gutter is no longer an `NSRulerView`.** It is an `NSView` beside the scroll view inside
   `GlassEditorAppKitEngine.containerView`, mirroring the UIKit backend that always had the right
   shape. The drawing moved into `GutterLineNumbers.draw(in:offsetY:…)` and is now written once for
   both platforms; the only per-platform value is `offsetY`. **Wants a look** — no test here can
   say whether it stops at the tabs, only that its frame matches the scroll view's band.
2. **Stage C, first half.** Projects are persisted and synced (`GlassEditorProjectLibrary` over
   `GlassSettingsSyncService`) and contributed to the library as a panel through the new
   `registerLibraryPanel`, the twin of `registerSettingsPage`. **It is the editor's first entry
   point on iOS and visionOS.**

### Stage D, the tree half — also built

The reader seam is **async** now, because an SFTP listing is. A remote project's tree lists over the
host's own SSH service, borrowed through `GlassHostDirectoryLister` — the shape of
`GlassHostPortForward`, D14 trust prompt included — and *Open in Editor* on a folder in the Files
browser is what makes one. Closing the project closes the connection.

**Its files open, edit and save**, through the same methods a local file uses. The reader became
`GlassEditorFileAccess` — list, read, write, stat, close — one object per project, and
`GlassEditorDocument` takes it as an argument instead of reaching for `FileManager`. **Local files
gained conflict detection as a consequence**: `RemoteDocumentSession` and `ConflictDetector` hold a
size, a time and a digest, which mean the same thing on a disk, so a file changed by a checkout or
a build now stops the save and asks exactly as a remote one does.

**Nothing in stage D has met a real server** — the Ubuntu VM at `192.0.2.6` is where it gets its
first real listing and its first real save.

### Do these next, in order

1. **Look at it.** The gutter; the Projects panel beside Keys; *Open in Editor* on a folder;
   **Edit on a file** — it now opens a tab in the real editor instead of the old sheet. The
   transport under it is proven against the VM; the route through the UI is not.
2. **Delete `SFTPRemoteEditorView`** once that click has been made — it is still there as the
   fallback for "nothing can take the file", and is the last of the two editors.
3. **A UI-test seed for desktop configurations.** The desktop has no UI test and cannot have one:
   `--ui-testing-seed-hosts` makes services without a capability record, and a desktop with no
   record cannot open. That gap is what let "nothing happens on the iPhone" ship.
4. **The Vision Pro**, on an unlock.
5. **The D26 two-device run**, and the test hygiene.

### Running the live tests

    GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=michael \
    GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/scratch_vm swift test --filter LiveRemoteEditing

Unconfigured they print **NOT RUN** rather than passing quietly. `gptrdp` is the *desktop* account
on that VM and has no SSH key; `michael` with `~/.ssh/scratch_vm` is the SSH one.

### Things that will bite

- Everything in the previous block still holds: rule 32 (build all three, every time), rule 28 (a
  locked screen fails every protected write), and the editor `body` type-check timeout held back by
  three extracted modifiers.
- **`HostServiceKind` is `rdp, ssh, database`** — there is no `.terminal` case, though the terminal
  is what an `ssh` service opens.
- The Mac app is **not sandboxed** (no `com.apple.security.app-sandbox`), which is why a project
  reopens from a stored path with no security-scoped bookmark. Do not assume that on iOS.

## 2026-09-17 (night) — RESUME HERE (supersedes the afternoon block)

**State DOCS.** **1,623 tests / exit status 0**, plus 7 live against `192.0.2.6`. macOS, iOS and
visionOS all build. macOS and iPhone on **0.4.170**; the Vision Pro is still locked at 0.4.123.

### What tonight was

Two reports, both from using the app on the phone, and both the same shape as the morning's: a
thing that works on one platform and silently does nothing on another.

1. **The SFTP editor on the iPhone.** Edit opened a black screen and the browser came back as
   *"source session is no longer active"*. The editor was presented from **behind** the browser's
   sheet, which dismissed it — and destroying the browser closes the SSH session it owns, as that
   class's own comment says. It is a **child** of the browser now, like the editor it replaced.
   The black screen was a `NavigationSplitView` nested in a `NavigationStack`.
2. **A terminal service that synced without its settings**, while the desktop added in the same
   sitting was fine. The Mac had **deleted** the phone's configuration: `replaceAll` reconciles the
   catalog to the caller's list, and the terminal read its list once and ignored every later
   catalog load. Full write-up:
   [the terminal configuration the Mac deleted](tasks/2026-09/2026-09-17_terminal-configuration-loss.md).

### Do these next, in order

1. **Decide what to do about `replaceAll`.** Freshness is now every capability's duty; the
   primitive still lets a stale caller delete another device's work. A per-record write, or a
   reconcile that refuses to delete records it has never seen, makes the class impossible.
2. **A UI-test seed for desktop configurations.** The desktop still has no UI test and cannot have
   one; that gap is what let "nothing happens on the iPhone" reach a phone.
3. **The Vision Pro**, on an unlock. Still 0.4.123.
4. **The D26 two-device acceptance run** — which would have caught tonight's defect, and is still
   the thing this project keeps owing itself.
5. Test hygiene: 1,519 keychain items and the preference sprawl.

### Things that will bite

- **Rules 42–45** are all from today: read the obsolete apps, one answer to "can this device open a
  window", a capability's list is a cache the catalog changes underneath, and every action an error
  offers must work.
- **The Mac's catalog cannot be read from this shell.** TCC refuses the Group Container, so a sync
  question has to be answered from the app's behaviour or from a test, not by looking at the file.
- Rule 28 still costs twenty minutes if forgotten, though auto-lock is now off on this Mac.

## 2026-09-18 — RESUME HERE (supersedes the night block above)

**State DOCS.** **1,623 tests / exit status 0**, 7 live against `192.0.2.6`, all three platforms
build. iPhone on **0.4.171**; the Mac is built at 0.4.171 and waiting for the app to be quit; the
Vision Pro is still locked at 0.4.123.

### What the night was

One report — *"the editor doesn't actually work at all. The file title shows but no content"* —
and **four iPhone-only defects behind it**, none in the editor's text view:
[the editor on a phone](tasks/2026-09/2026-09-17_editor-on-a-phone.md).

The editor now opens a project, lists its files and renders a document on a phone, photographed at
every step.

### Do these next, in order

1. **Drive the other three capabilities on a phone.** The terminal, the database and the desktop
   have never been watched there, and tonight's four defects were all invisible to a Mac build and
   to 1,623 unit tests. `UITests/EditorOnIPhoneUITests.swift` is the pattern.
2. **A seed for desktop configurations**, so that capability can have a UI test at all.
3. **`replaceAll` remains a whole-kind reconcile** driven by one device's list — freshness is now
   every capability's duty rather than a property of the call.
4. **The Vision Pro**, on an unlock, and the D26 two-device run.

### Things that will bite

- **Rules 42–47**, all earned on 2026-09-17: read the obsolete apps; one answer to "can this device
  open a window"; a capability's list is a cache the catalog changes underneath; every action an
  error offers must work; drive the phone rather than reasoning about it; and a simulator fixture
  must live inside the app.
- The simulator's data container is renamed on reinstall while `UserDefaults` survives. Anything
  seeded from the host is stale by the next run.
- Result bundles frequently arrive unfinalised; write screenshots to the runner's temporary
  directory as well as attaching them.

## 2026-09-18 (later) — the plan for iOS navigation

The editor works on a phone; **finding your way around does not**. Planned in
[finding your way around on iOS](tasks/2026-09/2026-09-18_ios-navigation-plan.md), nothing built:

1. Opening a folder lands on its **files**, not on the editor's empty state with the tree behind a
   toggle. Opening a file still goes to the editor.
2. The file and folder views stop being **modals** — one navigation stack, pushes, the whole
   interface, mirroring `SFTPBrowserView`.
3. **One header for both browsers**: the folder's name large, the full path beneath it across the
   width without the folder repeated, truncated from the *front*. `SFTPBrowserView` currently sets
   `.navigationTitle(currentPath)`, which is the whole path as a title.
4. **A session switcher.** A phone has no route between open connections at all: every session is
   full-screen in the primary scene, so a terminal, a desktop and a database cannot be reached from
   one another. Contributed `openSessions()` per capability, a Sessions control in each session's
   chrome, a list first and the app-switcher carousel second.

Everything carried is in section E of that note — the Mac install, the headset, the desktop's
missing UI test, `replaceAll`, D26, test hygiene.

## 2026-09-18 (build) — A, B and C are in — RESUME HERE

**State DOCS.** **1,632 tests / exit status 0** (nine new for the path header), Release builds for
macOS, iOS and visionOS, and the iPhone walkthrough driven twice with screenshots. Nothing is
committed. **0.4.173 is installed on the Mac and on the iPhone**, both read back off the installed
bundle, and carries all of A, B and C. The Mac app was quit for the install and relaunched, so
whatever was open in it at the time is gone. The Vision Pro is still on 0.4.123.

**0.4.173 supersedes it**: a library panel's count was a *stored* number, so removing a project
left the sidebar saying 5 with four in the list (reported 2026-09-18 with a screenshot).
`GlassLibraryPanel.count` is an `@autoclosure` asked for every draw now — the same shape
`hasSelection` already had, and it covers Workgroups and SSH Keys too. A panel a capability
rebuilds each body got a fresh count for free; a **standalone** panel is registered once and kept,
which is why only Projects showed it. Two tests, both seen red against a stored count.

**Versions are passed on the command line, not stored:** `MARKETING_VERSION=0.4.N
CURRENT_PROJECT_VERSION=N`. The project file says 0.1.0, so a build made without them cannot be
told apart from any other once it is installed.

### What landed

Sections A, B and C of
[finding your way around on iOS](tasks/2026-09/2026-09-18_ios-navigation-plan.md), together as
planned, with the build record appended to that note:

- **Opening a project lands on its files.** The phone's editor is a `NavigationStack` over
  `GlassEditorCompactRoute` — a folder screen as the root, a folder as a push, the document as a
  push. A window with no project (Edit in the Files browser) still opens on the document.
- **No modals.** The tree's sheet and the `Files` toggle are both gone.
- **One header, `GlassConnectionUI.GlassPathHeader`** — folder name large, the path beneath it
  across the width without the folder repeated, truncated from the front. `SFTPBrowserView` no
  longer titles itself with `currentPath`.

The first run photographed two defects of its own: the name appeared twice (navigation bar and
header), so the title is macOS-only now; and `~F/Documents` — the editor's private `abbreviated`
kept one character of home too many, so that rule moved into `GlassPathLocation.abbreviatingHome`
where both browsers use it and two tests cover it.

### Do these next, in order

1. **D1 and D2** — `openSessions()` per capability and the Sessions control. That is the dead end:
   a phone still has no route between a terminal, a desktop and a database.
2. **Look at the Files browser's header on a real listing.**
   `GlassTerminalUITests.testFilesBrowserHeaderNamesTheFolder` was written for exactly this and is
   **NOT RUN**: macOS UI automation on this machine currently fails to start for *every* test
   ("Timed out while enabling automation mode", reproduced with `LaunchSmokeUITests`), and the
   simulator's runner never received `TEST_RUNNER_GPT_SSH_TEST_*`, so it skipped.
3. **Install 0.4.171 to the Mac** when the app is quit, and look at the Mac's own surfaces.
4. Everything in section E of the plan note: the headset, the desktop's seed, `replaceAll`, D26.

### Things that will bite

- **macOS UI automation is down.** Before blaming a test, run `LaunchSmokeUITests` — if that
  cannot start either, it is the machine, not the change.
- The simulator's runner does not see `TEST_RUNNER_*` environment on this toolchain; the live
  fixtures have only ever been driven from macOS, where the runner inherits the shell's.
- Rules 42–47 all still apply, rule 46 most of all: the terminal, database and desktop have still
  never been driven on a phone.

## 2026-09-18 (afternoon) — three scopes, glass in the Files browser, and a suggestion

**State DOCS.** **1,645 tests / exit status 0**; Release builds for all three. **0.4.174 installed
on the Mac**; the iPhone is still on **0.4.173** — it reported `unavailable` to `devicectl` when
the install was attempted (`CoreDeviceError 4016`, no power assertion), so 0.4.174 is built and
waiting at `/tmp/gpt-ios-174/Build/Products/Release-iphoneos`.

### What landed

1. **The Files browser is glass.** The `sftp` scene gave its content `.glassLayers` — the layer
   *state* — and nothing painted it, because painting is `GlassLayeredWindow`'s job and that scene
   never wrapped its content in one. Both scenes (macOS, visionOS) do now, and the file `List`/
   `Table` gave up its opaque `scrollContentBackground`.
2. **Text settings cascade file over project over global** (`GlassEditorTextOverrides`, one pure
   `resolve`, seven tests). Each level stores only what it *changes*, so raising the app's default
   still moves everything that never disagreed.
   - **Toolbar gear → this file's**, on every platform. The Mac's `SettingsLink` is gone from the
     toolbar: app settings are a keystroke away at ⌘,.
   - **File-list footer gear → this project's**, which travel in the synced record.
   - Settings ▸ Editor keeps the defaults, unchanged.
   - "Default" is a real third state, so the pickers are three-way rather than switches — and each
     footer names what it is following.
3. **A project you can work in and cannot find again.** `Open Project…` opens the folder straight
   into the workspace and never reaches the Projects list. The window now *offers*:
   `GlassSuggestionButton` (a lightbulb, in `GlassConnectionUI`, deliberately reusable) → **Save as
   Project**. Offered rather than done, because the list is the user's and it syncs.
4. **Renaming a project reached only the window's copy** and was gone at the next launch. It goes
   through `GlassEditorRuntime.rename`, which writes both. Proven by a test seen red.

### Do these next, in order

1. **Install 0.4.174 on the phone** when it is reachable again.
2. **Look at the Files browser on the Mac** — the transparency and the header are both unverified
   by eye; macOS UI automation still cannot start.
3. **D1 and D2** — the session switcher. Still the dead end on a phone.
4. Section E of the plan note: the headset, the desktop's seed, `replaceAll`, D26.

### Things that will bite

- **A file's overrides are not stored.** They last while the document is open, by design; the
  durable levels are the project's and the app's. If that is wrong, the place to change it is
  `GlassEditorDocument.textOverrides`.
- `GlassEditorProject` gained an optional field. Records written before it decode fine — there is a
  test — but anything that *re-encodes* a record on an older build would drop it.

## 2026-09-18 (0.4.175) — what an open project says about itself

**State DOCS.** **1,650 tests / exit status 0**, three Release builds, **0.4.175 installed on the
Mac and the iPhone** (the phone came back from `unavailable`, so it skipped 174).

Three reports from the running app, all from looking at it:

1. **The file list's footer painted nothing**, so filenames scrolled behind the gear. It had a
   deliberate comment saying a divider was separation enough — a divider separates, it does not
   *cover*. `.bar`, the same surface the status line uses.
2. **Two Done buttons in Project Settings.** A toolbar item and a bottom bar, and a sheet on the
   Mac draws both. The bar is the one every platform draws, so the toolbar item went.
3. **A window with a project open offered three ways to open something.** It shows the project
   now (`GlassEditorProjectOverview`): agent instructions (`AGENTS.md`, `CLAUDE.md`, …), what to
   read first, what builds it, whether it is a git repository, and what was recently edited *in
   that project*. Open Project… / Open File… / New Document belong to the **empty** editor that
   ⇧⌘E makes, and are only there now.

Every fact in the overview comes from the listing the tree already loaded and the recents the app
already keeps, so it costs no reads. **`git status` is deliberately absent**: the editor reaches a
project through `GlassEditorFileAccess`, which lists, reads, writes and stats and cannot run a
command — a status that worked only for local folders would vanish over SSH. Doing it properly
means a "run a command on this machine" seam owned by the terminal, which is a real piece of work
and is not started.

### Do these next, in order

1. **D1 and D2** — the session switcher. Still the dead end on a phone.
2. **The Files browser's header and transparency on a Mac**, by eye; macOS UI automation still
   cannot start ("Timed out while enabling automation mode", any test).
3. Section E of the plan note: the headset, the desktop's seed, `replaceAll`, D26.

## 2026-09-19 (0.4.177) — the provisional tab

**State DOCS.** **1,657 tests / exit status 0**, three Release builds, **0.4.177 on the Mac and
the iPhone**.

The pattern every editor uses, asked for by name: **one click shows a file provisionally; the next
single click takes the same tab; committing to it keeps it.** `GlassEditorWorkspace` holds one
`previewDocumentID` — one id rather than a flag per document, so "two documents are both the
preview" cannot be represented.

- **Commitment** is a double click, a deliberate open (Return, ⌘↓, the context menu, Edit in the
  Files browser), an **edit**, or a save. All four route through `makePermanent`.
- **An edited preview is never evicted** — it is promoted and the new file opens beside it, which
  is what makes replacing a preview safe without a prompt.
- The new tab **takes the old one's index**, so the strip does not shuffle while someone clicks
  down a list.
- The provisional tab is drawn in *italics* (`GlassWorkspaceTabItem.isProvisional`, shared with the
  database's strip), and VoiceOver says "previewing".

Seven tests. Also from the same sitting: the project overview is centred in the pane, both axes
(`minHeight`, so a long one still scrolls).

### Do these next, in order

1. **D1 and D2** — the session switcher, still the phone's dead end.
2. **The Files browser's header and transparency on a Mac**, by eye. macOS UI automation still
   cannot start.
3. Section E of the plan note: the headset, the desktop's seed, `replaceAll`, D26.

## 2026-09-19 (0.4.178) — three answers, two of them defects

**State DOCS.** **1,660 tests / exit status 0**, Release builds for all three, **0.4.178 on the
Mac and the iPhone**.

### The toolchain moved under us

**Xcode updated to 27.2 (27B5019j)** overnight, and two things broke that are nothing to do with
this code:

- Every build failed with *"cannot execute tool 'metal' due to missing Metal Toolchain"* (SwiftTerm
  has a `.metal` shader). Fixed here with `xcodebuild -downloadComponent MetalToolchain` — 839 MB.
- **The simulator is gone**: `/Library/Developer/PrivateFrameworks/CoreSimulator.framework` does
  not exist, so `xcodebuild test` on a simulator cannot load `IDESimulatorFoundation`. That needs
  **`sudo xcodebuild -runFirstLaunch`**, which this session cannot run — the user has to. Until
  then there is **no iPhone UI testing**, and that is the pass that has been finding the defects.
  Yesterday's "macOS UI automation cannot start" was very probably the same update, mid-flight.

### The three reports

1. **Leaving a terminal does not end the session.** `showConnections()` only sets
   `router.terminalWorkgroupID = nil`; `closeWorkgroupOnce()` runs when the *last tab* is closed,
   never on leaving. The session stays live and is reachable again through the library's
   **Workgroups** panel (`resumableWorkgroupID`), which is not obvious — see the next item. The
   control's icon was `sidebar.left` on a screen with no sidebar; it is `chevron.backward` now,
   matching the database's, which already got this right.
2. **"It just absorbed the click" is a real defect, and not the error's fault.** A contributed
   panel told the compact stack `hasSelection: Bool`. It went true on the first selection and
   **stayed** true, so every later selection changed nothing the stack was watching: after going
   back once, no project's detail could ever be pushed again. `GlassLibraryPanel` now reports
   `selectedItem: AnyHashable?` and a `clearSelection()` the stack calls when the detail pops.
   Reproduced first in `EditorOnIPhoneUITests.testAProjectThatRefusesToOpenDoesNotBlockTheNextOne`
   (which failed exactly where the user said it would), and covered by three unit tests.
3. **The session switcher is planned and unbuilt** — section D of the iOS navigation plan. Item 1
   is the argument for it: the session is alive and the way back is a panel nobody would think to
   open.

### Do these next, in order

1. **`sudo xcodebuild -runFirstLaunch`** — the user's to run. Without it there is no simulator.
2. **Re-run `testAProjectThatRefusesToOpenDoesNotBlockTheNextOne`** once the simulator is back; it
   is written and currently cannot run.
3. **D1 and D2** — the session switcher.

## 2026-09-19 (0.4.179) — a keyboard you can put away, and HTML

**State DOCS.** **1,663 tests / exit status 0**, three Release builds, **0.4.179 on the Mac and
the iPhone**.

1. **The keyboard hides and comes back, as the terminal's does.** `GlassEditorModel.requestKeyboard`
   carries the ask — the model is the API and a SwiftUI consumer never holds the engine, so the
   instruction travels as observable state the UIKit backend watches. A **serial, not a flag**:
   the user can swipe the keyboard away between two presses of Show, and a control that works
   every other time is worse than none (rule 45). Two surfaces: a bar above the keyboard with the
   terminal's own `keyboard.chevron.compact.down`, and a toggle at the end of the editor's status
   bar whose icon follows the *system's* notifications rather than a flag this app sets.
2. **HTML is the sixteenth grammar.** A pinned dependency, not a vendored copy — upstream's
   manifest compiles `parser.c` and `scanner.c` unconditionally, which is the thing YAML's gets
   wrong. `tree-sitter/tree-sitter-html` at `73a3947`. Its `@tag` needed the same override XML
   needed (an element name is markup's keyword, and `@tag` means punctuation in the universal
   table because PHP uses it for `<?php`), and `<script>`/`<style>` bodies read as embedded code
   rather than prose. `.html .htm .xhtml .vue .svelte .hbs .ejs .njk` claim it; `<!DOCTYPE html>`
   is sniffed **before** the XML prolog rule, because it is the one doctype that is not XML.

### Do these next, in order

1. **`sudo xcodebuild -runFirstLaunch`** — still the user's to run; without it there is no
   simulator, and `testAProjectThatRefusesToOpenDoesNotBlockTheNextOne` cannot run.
2. **D1 and D2** — the session switcher.
3. An **injection pass** would make `<script>` actually JavaScript and `<style>` actually CSS;
   today they are one honest colour. Not started, and the grammar work above is what it needs.

## 2026-09-19 (0.4.180) — the simulator is back, and it found one more

**State DOCS.** **1,663 tests / exit status 0**, three Release builds, **0.4.180 on the Mac and
the iPhone**. The user ran `sudo xcodebuild -runFirstLaunch`; there are fresh simulators on iOS
26.5, 27.0 and **27.2**.

**Both iPhone UI tests pass**, including
`testAProjectThatRefusesToOpenDoesNotBlockTheNextOne` — the reproduction of "it just absorbed the
click". **Seen red against the old `hasSelection: Bool`** and green against `selectedItem`, on a
phone, which is the verification that was owed.

Getting there found one more defect, and the tests found it rather than a person:

**A library panel's sidebar row was three accessibility elements.** The identifier sat on an
`HStack`, so on **iOS 27.2** the first match for `glass-library-panel-editor-projects` was the
row's *image* — not hittable, so the tap did nothing and both tests failed before they reached
what they were testing. VoiceOver had the same row three times for the same reason. One
`.accessibilityElement(children: .combine)` makes it one control that says its name and its count.
Worth noting as a pattern: **an identifier on a container reaches its children**, and which child
XCUITest picks changes between OS versions.

### Do these next, in order

1. **D1 and D2** — the session switcher. Nothing else is in front of it now.
2. Drive the **terminal, database and desktop** on a phone (rule 46) — still never done, and the
   simulator is working again today.
3. Section E of the plan note: the headset (still 0.4.123), the desktop's seed, `replaceAll`, D26.

## 2026-09-19 (0.4.181) — the database had the editor's disease

**State DOCS.** **1,663 tests / exit status 0**, three Release builds, **0.4.181 on the Mac and
the iPhone**. Three reports, one cause and two consequences.

**`DatabaseWorkspaceView` is a `NavigationSplitView`**, and on a compact width SwiftUI collapses
one of those into a single stack showing its **sidebar**. So on a phone the workspace *was* the
schema browser: Browse Data, a table, the SQL Editor button — every one of them selected a
destination in a column that was never on screen. Exactly the defect the editor had on
2026-09-17, still here because nobody had driven the database on a phone (rule 46, and it was
item 2 of the plan's carried list).

1. **"Browse data absorbs the click."** There is a compact layout now — a `NavigationStack` whose
   root is the schema and whose push is the detail, the same shape the editor uses. Every route
   that chooses something pushes: a tap, a double tap, the SQL Editor button, ⌘T.
2. **"No back button to get from Databases back to the connection list."** The control existed
   (added 2026-09-16) at `ToolbarItemPlacement.navigation`, which iOS drops in a collapsed split
   view. It is `.topBarLeading` on iOS now — and, just as important, the toolbar is attached
   **inside** each navigation container: a `.toolbar` on a view that *contains* a
   `NavigationStack` does not reach the screens inside it, which would have removed every control
   the moment the compact layout landed.
3. **"Our footer is confused."** The schema browser's filter is a floating bottom search on iOS 26
   and later, and the workspace's `.bottomBar` group landed in the same strip — search field,
   buttons and list rows all in one place, photographed. On a compact width the SQL editor moves
   to the top bar beside Refresh and the rest into the overflow menu that is already there; the
   bottom belongs to the search field.

**Also:** *is there a whole SQL surface for iOS?* Yes — `QueryEditorView`, `TableDetailView`,
`DatabaseDetailView` and `ConnectionOverviewView` are all cross-platform and always have been.
Only the route to them was missing.

### Not proven on a phone

No UI test covers any of this: the database tests are gated on `GPT_DB_TEST_*`, and **a simulator
runner does not receive `TEST_RUNNER_*` environment** on this toolchain, so they skip. A seeded
database configuration — the same gap the desktop has — is what would fix that, and it needs
credentials the fixture cannot carry. The user is testing it live.

### Do these next, in order

1. **Drive the terminal and the desktop on a phone.** The database had this defect for three days
   and the phone's own report found it; those two have still never been watched there.
2. **D1 and D2** — the session switcher.
3. A **seed for database and desktop configurations**, so those two can have UI tests at all.

## 2026-09-19 (0.4.182) — the regression I caused, and where Back should go

**State DOCS.** **1,664 tests / exit status 0**, three Release builds, **0.4.182 on the Mac and
the iPhone**.

**I broke the database list and the phone caught it in one round.** My compact stack used a
*typed* path — `NavigationStack(path: $compactPath)` over `[DatabaseCompactRoute]`. The schema
browser has had its own compact navigation since glassdb (`compactDatabaseList` pushes a
`CompactSchemaDatabaseDestination` for a database's tables), and **a typed path accepts only its
own type**, so those links silently did nothing: "now the databases can't be clicked". It is a
`NavigationPath` now, with the detail's depth tracked separately because a `NavigationPath` will
not say what is in it.

**The lesson, and it is a new one:** before wrapping a view in a `NavigationStack`, find out
whether it already navigates. The schema browser was doing the right thing on a phone long before
this; the workspace around it was not, and the fix has to leave the working half alone.

**Back goes to the machine now, not to the top of the list.** `GlassShellModel.hostToShow` is the
seam — a capability asks for a host, the library selects it, and the library pushes its detail for
a selection change on its own. The catalog answers "which host owns this endpoint?" in the
composition root, because the database does not hold the catalog. Every capability that replaces
the library on a phone wants this; the database is the first to use it, and the terminal and the
editor should follow.

### Still not proven on a phone

No UI test reaches any database surface: the fixtures are gated on `GPT_DB_TEST_*`, and a
simulator runner does not receive `TEST_RUNNER_*`. **That gap is now load-bearing** — it is why a
regression reached the user instead of a test. A seeded database configuration is the fix and is
the next thing worth building after the switcher.

## 2026-09-19 (0.4.183) — one grid, everywhere

**State DOCS.** **1,664 tests / exit status 0**, three Release builds, **0.4.183 on the Mac and
the iPhone**.

A phone showed query results as a **card per row** — "Row 1", then four fields down the page. It
was a different way of reading a table rather than a smaller one: no column alignment, nothing to
compare down a column, and only the first four columns at all. *"I appreciate the idea of the card
view for rows, but it's not right. Let's use the table view we already have."*

`dataGrid` is used on every platform now. It already scrolls in both directions, which is exactly
what a narrow screen needs, and both surfaces carried the same `db-grid-row-*`/`db-grid-cell-*`
identifiers so the database UI tests are unaffected. The **pager** and the **control bar** keep
their compact forms — those are about controls fitting a phone, not about how a table is read —
and `usesCompactRecordList` is renamed `usesCompactPager` to say so. `compactRecordList` is
deleted rather than left behind a flag.

## 2026-09-19 (0.4.184) — pinned chrome has to occlude

**State DOCS.** **1,664 tests / exit status 0**, three Release builds, **0.4.184 on the Mac and
the iPhone**.

The grid's **column header and row-number gutter painted nothing** when the workspace's opacity
was 0, and the data scrolled straight through them: `#` and `content` written over cell text,
illegible (photographed on the phone). The old comment said it disappeared at 0% on purpose —
*"preserving the exact transparent and opaque endpoints selected by the user"* — which is the
right instinct for a canvas and the wrong one for chrome that has to say **which column you are
reading**.

`databaseCanvasPinnedSurface` now lays `.ultraThinMaterial` under the tint on every platform. A
material rather than a colour floor, because it stays translucent — the window is still glass,
which is what "still transparent like the Mac version" asks for — and at full opacity the tint
covers it completely, so nothing changes at the end of the scale that already looked right.

**Verified by eye only.** The alpha maths is unchanged, so no test moved; whether a header is
legible over scrolling text is a thing to look at.


## 2026-09-19 (end of day) — RESUME HERE (supersedes every block above)

**State DOCS.** **1,664 tests / exit status 0**. Release builds for macOS, iOS and visionOS.
**0.4.184 installed on the Mac and the iPhone**, both read back off the installed bundle; the
Vision Pro is still on **0.4.123**. Everything through 0.4.184 is committed.

**The day, in one page:** [the iOS round, day two](tasks/2026-09/2026-09-19_ios-round-two.md).
Eight releases, seven reported defects, one of them a regression of mine. New rules **48** (find
out whether a view already navigates before wrapping it), **49** (an identifier on a container
reaches its children) and **50** (pinned chrome must occlude whatever the transparency says).

### What is true now

- The **editor** works on a phone: a folder opens on its files, folders push, one click previews
  a file and commitment keeps it, the keyboard hides and comes back, and text settings cascade
  **file over project over global**.
- The **database** works on a phone as of today: the schema pushes tables, a table pushes the
  detail, Back goes to *the machine*, the grid is the real grid and its pinned chrome occludes.
- **HTML** is the sixteenth grammar.
- The **terminal** and the **desktop** have still never been driven on a phone.

### Do these next, in order

1. **D1 and D2 — the session switcher.** Nothing is in front of it. The terminal question that
   opened the day is its argument: leaving an SSH session only clears
   `router.terminalWorkgroupID`, so the session stays live and the only way back is the
   Workgroups panel, which nobody would think to open.
2. **Drive the terminal and the desktop on a phone.** The database cost three defects and a
   regression for want of this.
3. **A seeded database or desktop configuration**, so either can have a UI test at all. This is
   what let a regression of mine reach the user instead of a test.
4. Section E of the navigation plan: the **Vision Pro** (three weeks behind), `replaceAll`, the
   D26 two-device run, test hygiene.

### Things that will bite

- **`sudo xcodebuild -runFirstLaunch` was needed** after Xcode 27.2, and the Metal toolchain had
  to be downloaded. Both are recorded in [technical context](techContext.md); if builds or
  simulators break again after an Xcode update, start there.
- **A simulator runner never sees `TEST_RUNNER_*`**, so every live-fixture UI test is macOS-only.
- Rules 42–50, and rule 46 above all: the phone is where the defects are.


## 2026-09-19 (0.4.185) — Settings on a phone, and two capabilities cleared

**State DOCS.** **1,664 tests / exit status 0**, three Release builds, **0.4.185 on the Mac and
the iPhone**.

**The terminal and the desktop have now been driven on a phone, by the user, and both work.** RDP
to `oscar` rendered a GNOME login at 1,320 × 2,318 with the Esc/Tab/Keyboard bar, reported
"Connected", and the terminal came through the same pass. That closes the oldest item on the
carried list — rule 46's debt is paid for three of the four capabilities, and only the editor's
own phone pass predates it.

**Settings ▸ Terminal was one clipped row.** `GlassShellSettingsView` wrapped every page in a
`Form`: right for the shell's own four, which are sets of `Section`s, and wrong for a capability's,
which is already a `Form`. Nested Forms collapse on iOS. A capability page is handed through
untouched now, and the shell's four get the `Form` they need — **rule 51**.

### Do these next, in order

1. **D1 and D2 — the session switcher.** Everything else on the phone works; moving *between*
   the things that work is what is left.
2. **A seeded database or desktop configuration**, so either can have a UI test at all.
3. Section E of the navigation plan: the **Vision Pro** (still 0.4.123), `replaceAll`, D26.

## 2026-09-20 (0.4.186) — the SQL that stopped keeping up, and the Duo

**State DOCS.** **1,667 tests / exit status 0**, three Release builds, **0.4.186 on the Mac and
the iPhone**.

**The pager moved the rows and the SQL above them still said `OFFSET 0`.** A table's SQL pane
holds the *generated* browsing query, which the grid rewrites on every page, filter and sort —
but only while it believes the user has not typed there. A **restored** draft came back as an
edit every time: `QueryDocumentTab(text:)` leaves `savedText` empty, so `hasUnsavedChanges` was
true for the rest of the session and the grid never rewrote its own query again. Not a phone bug
at all; it needed only a draft that had been stored once.

`SQLDraftRecord` carries `isUnsavedEdit` now — recorded from the document, which already knows —
and a restored baseline comes back rewritable while a restored edit stays protected.

**And the test caught something far worse than the bug.** `var isUnsavedEdit = false` with a
synthesized `Codable` makes the key **required on decode**: every draft file written before the
field would have failed to decode, and every stored draft on the machine would have been lost by
a change meant to fix a cosmetic staleness. A `decodeIfPresent` initialiser in an extension fixes
it (the extension keeps the memberwise init). Worth remembering: **a default value is not a
default on decode.**

### iPhone Duo

The device type ships with Xcode 27.2 —
`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, minimum runtime **27.1** — but **none of the
three installed runtimes support it** (26.5, 27.0, 27.2/24B5084k all list it as unsupported), so
a device cannot be created. Getting one means downloading the current iOS simulator runtime
(`xcodebuild -downloadPlatform iOS`), which is several gigabytes and is the user's call.

## 2026-09-20 — the Duo, read as a use case

Planned, nothing built: [iPhone Duo](tasks/2026-09/2026-09-20_iphone-duo.md). It ships
**23 October**. Three things to act on, and one question answered.

1. **`canOpenWindows` may refuse it.** The gate is `supportsMultipleScenes && idiom != .phone`
   (rule 43). The Duo is an iPhone by idiom and shows two apps side by side. Ask the system, not
   the idiom — **after** verifying on the device, because guessing is what rule 43 was written
   about.
2. **The size class changes on a hinge, mid-session.** The library has handled that since before
   the merge; the editor's and the database's brand-new compact stacks do not. Testable on an
   **iPad** today by moving a Split View divider, which is the test to write before 23 October.
3. **`SFTPBrowserView`'s drop target is `#if os(macOS)`**, on a device whose headline gesture is
   dragging a file from one app into another.

**Transparency on iPhone stays as it is.** Split View is tiled, not overlapping, so a translucent
window still shows wallpaper. Rule 50 — nothing may need opacity to be legible — is the part that
matters, and it is already in force.

## 2026-09-20 (0.4.187) — a drop the app had been refusing for months

**1,667 tests / exit status 0**, three Release builds, **0.4.187 on the Mac and the iPhone**.

`#if os(macOS)` around the Files browser's drop target was a platform check standing in for a
capability, and it was **already wrong before the Duo**: iPadOS has had cross-application drag and
drop for years, and this app turned it down. `SFTPIncomingDrop` is cross-platform now — the
AppKit fast path stays fenced by name, the `NSItemProvider` path serves everyone else — and five
`⌘`-shortcut fences went with it, because an iPad with a keyboard has ⌘A and Escape. **Rule 52.**

Still macOS-only, and deliberately: dragging a file **out** of the browser. It is an
`NSViewRepresentable` over file promises, and the iOS equivalent must download the remote file to
hand over an item provider. Recorded in the Duo note as worth doing before October.

## 2026-09-20 (0.4.188) — a number on the wrong line, and a password that is not required

**1,668 tests / exit status 0**, three Release builds. **0.4.188 on the iPhone; the Mac is on
0.4.187** — the quit AppleEvent timed out, which is what an open modal sheet does, so that install
is waiting.

**The gutter's last number sat a line too low.** Measured rather than guessed: with
`.ensuresExtraLineFragment`, TextKit 2 lays the document's final empty line out **inside** the
last paragraph's fragment — `"one line\n"` is *one* fragment, 32 points tall, holding two
16-point line fragments, the second with a zero-length range. The trailing label was placed at the
fragment's `maxY`, which is one line below where the caret actually is. It is placed at the extra
line fragment's own top now, and `AppKitEngineTests` asserts the second number sits exactly one
line below the first, with the line height taken from the layout rather than assumed.

**A database password is no longer required.** `auth_socket`, `trust`, `peer`, a tunnelled local
instance, a user created without one — all connect with nothing to send, and the form refused to
save the service at all. Two halves: the draft no longer raises the issue, **and** the connect
path no longer throws `credentialMissing` when the keychain holds nothing, which would have made
a service that saves and then refuses to connect. Whether an empty password is accepted is the
server's to say, and it says so accurately.

One consequence recorded honestly: a *stranded* credential — one the keychain lost — now reads as
the server's own authentication rejection rather than as "no saved password was found". The error
case is still there for a caller that can genuinely tell the two apart; the connect path cannot.
