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
name "Glass Power Tools"; `GlassEditorUI` waits for Stage 5). **D1's Git actions in sibling
repositories remain unauthorized until the user says so explicitly**; P3 (sibling test suites) is
running. The user notes glas.sh has an unmerged PR; local source is authoritative for this work.

Toolchain observed: Xcode 27.0 (27A5252f), Swift 6.4. Simulators: iPhone 17 family on iOS 27.0,
Apple Vision Pro on visionOS 26.4 / 26.5 / 27.0. Physical: iPhone 17 Pro Max (iOS 27.0), Vision
Pro (visionOS 27.0), Mac (macOS 27.0). One Apple Development signing identity.

Coordinator `/root` owns this file, progress, toc, decisions and the monthly README. Workers own
the directories named in their briefs and write their own task notes under `tasks/2026-09/`.

## Next action

Lay down the package skeleton, confirm the three local packages resolve in one graph, then fan out
Stage 1 work: project file, `GlassLayers`, `GlassShell`, app target, security review.
