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

## Next action

Lay down the package skeleton, confirm the three local packages resolve in one graph, then fan out
Stage 1 work: project file, `GlassLayers`, `GlassShell`, app target, security review.
