# Merge plan: three applications into Glass Power Tools

Owner `/root`. Created 2026-09-10. **Status: planned, nothing built.**

## Task

- **Objective:** one application, `com.glasspowertools`, containing the terminal, database and remote
  desktop capabilities, over a shared shell, with the host as the organising object.
- **Authorization so far:** create this plan and the memory bank. Building starts on the user's word.
- **Owner and affected files:** this repository only. The three source
  applications are read-only inputs and must keep building.
- **Acceptance:** each capability reaches parity here, proven by its own tests and native workflows,
  before the next begins. Existing user data is found in place, proven on a test build.

## Sequence

Each stage ends in something that builds and runs. No stage requires the next to be useful.

### Stage 0 — Decisions — **complete**

All four answered on 2026-09-10 and recorded in [decisions](../../decisions.md): the editor is built
in as a library with its interface last; data migration is not a constraint; the capability order is
SSH and SFTP, databases, remote desktop, editor; and the floor is 26.0 everywhere, `arm64` only. A
fifth requirement arrived with them: the layering system is foundational.

### Stage 1 — Shell and layers, no capabilities

One multiplatform application target (decided 2026-09-10, see [decisions](../../decisions.md)),
the host library, host and service navigation, settings, window and scene model, and the credential
boundary. Detailed in the [Stage 1 task note](2026-09-10_stage-1-shell.md). It consumes GlassConnectionKit, GlasSecretStore and the
host catalog as they exist, and brings GlassEditorKit in as a library without an interface. It can
list hosts and their services and connect to nothing.

**The layering system is built here, not later.** Window transparency including title bar
backgrounds, panel and detail materials, and the opacity controls, as one system every surface draws
from. Reuse the titlebar material already in GlassConnectionUI and glassDT's window frame, canvas
backdrop, opacity and frost rather than writing new ones.

The service picker on the library row is built here: icons per defined service, Connect opening the
last used service, a chevron menu on Mac and press-and-hold on touch, and "Add a service…" replacing
"Paired Services".

**Proves:** the boundary, and the layering system on the connection detail view.

### Stage 2 — SSH and SFTP to parity

The largest source application, about 31,400 lines, and the one the user works in most, so it tests
the boundary hardest. Terminal, SFTP, port forwarding and workgroups move in as modules; its settings
merge into the one settings surface. `../glas.sh` keeps building untouched.

**The SSH connection panel is where the layering system is proven on a real capability surface.**

The SFTP interface is designed with the editor in mind, because the user has ideas there that decide
how well editing lands later. Design decisions taken here should be recorded, not just implemented.

**Proves:** that a capability moves without a rewrite, and that the shell boundary survives contact
with a real one. If it does not survive, fix the boundary here, before three more arrive.

### Stage 3 — Databases to parity

About 22,200 lines. Note that glassdb's macOS deployment target is 27.0 today and the merged floor is
26.0, so anything depending on 27.0 must be found during this migration.

### Stage 4 — Remote desktop to parity

About 5,600 lines plus RDPKit, VNCKit and the two transports. The smallest and best understood of the
three, and the one whose engines are already cleanly separated.

### Stage 5 — Editor interface, and the things only one app can do

The editor interface, last by decision, over the library that has been present since Stage 1 and the
SFTP surface designed for it in Stage 2.

Then the things three applications could never do: the spatial workspace where one host's terminal,
database and desktop coexist, generalising glas.sh's Workgroups. The SSH tunnel for VNC, nearly free
once SSH and remote desktop share a binary. The VNC service kind and VNC credential record that were
deferred because installed siblings could not decode them.

### Stage 6 — Deprecate the source repositories

On the user's instruction only. Archive with redirects to this project. Not before parity.

## Structural observations that shape the stages (read 2026-09-10)

- **glas.sh has no internal module boundary.** Its 31,393 lines sit in 30 loose Swift files at
  `glas.sh/glas.sh/`, with a `Platforms/macOS` overlay and a `glasWidgets` target. "Move in as
  modules" therefore means *carve into modules first*, then move. This is the largest single piece
  of work in the project and Stage 2 must budget for it.
- **glassdb is half-separated.** Its engine is already a package, `Packages/GlassDBKit`; its UI is
  22 loose files at `glassdb/glassdb/`. Stage 3 carves the UI only.
- **glassDT is already the target shape for *modules***: `GlassDesktopCore`, `GlassDesktopUI`, four
  engine packages and a `Package.swift`. Stage 4 is mostly a move. It is **not** the template for the
  project model: see the next point.
- **glas.sh and glassdb each vendor Citadel and swift-nio-ssh.** Two copies of the SSH stack become
  one in Stage 2, and glassdb's SSH tunnel then uses the shared one in Stage 3.
- **The layering system is further along than the active context implies.** `GlassConnectionUI`
  already holds `GlassNativeWindowFrame`, `GlassWindowChrome`, `GlassCanvasBackdrop`,
  `GlassSpatialDisplay*`, `GlassSettingsSections`, `GlassSettingSlider` and the
  `GlassConnectionLibrary` / `GlassLibrary*` surfaces. Stage 1 is largely consuming these, not
  writing them. Verify what remains only in `glassDT/Sources/GlassDesktopUI` before assuming it
  needs extraction.
- **The family uses two different project models, and Stage 1 must pick one.** glas.sh and glassdb
  are each a **single multiplatform app target**: `SDKROOT = auto`, `SUPPORTED_PLATFORMS` covering
  iOS, macOS and visionOS, per-platform divergence expressed as `[sdk=macosx*]` build settings
  (entitlements, Info.plist) and `platformFilter` on individual files (Mac assets, app icon, widget
  embed). glassDT is **one app target per platform**, three targets stamped from an XcodeGen
  template. The multiplatform-single-target model carries the two largest apps and matches the
  product principle of one design adapting across platforms. The plan's earlier wording, "an
  application target per platform", was inherited from glassDT. **Decided 2026-09-10: single
  multiplatform target.** Recorded in [decisions](../../decisions.md).
- **glas.sh carries a widget extension** (`glasWidgets`, a 250-line ServerHealth WidgetKit target,
  iOS and visionOS only, embedded with `platformFilters = (ios, xros)`). The merged app has at least
  two targets whichever model is chosen.
- **XcodeGen versus a hand-maintained `.xcodeproj` is a second, separate decision.** Verified on
  2026-09-10 with a generated probe project: XcodeGen 2.46 expresses the single-multiplatform model
  exactly (`supportedDestinations`, `destinationFilters`, `[sdk=…]` settings pass through). The
  hand-maintained model is also proven in the family: glas.sh's and glassdb's `project.pbxproj` are
  hand-curated, with sequential authored identifiers, and stay under 950 lines. **Decided
  2026-09-10: hand-maintained, following glas.sh, with synchronized folders.** Recorded in
  [decisions](../../decisions.md).

## Risks

| Risk | Response |
|---|---|
| Layering retrofitted per surface, as happened with settings across three apps | Built in Stage 1, proven on the detail view and the SSH connection panel |
| The merge becomes a rewrite | Move modules; forbid rewriting working functionality to fit |
| The shell is shaped by the first capability | Draw the boundary in Stage 1; correct it in Stage 2 |
| User data is not found by the new identity | Prove in Stage 1 on a test build, before any capability |
| Three test suites rot during the move | Each capability arrives with its tests, and they run here |
| Parsers share memory with live sessions | Accepted knowingly; XPC isolation stays available later |
| Source apps break while being read | They are inputs only; nothing there is edited by this work |

## Open questions

None remain. The four that blocked Stage 1 were answered on 2026-09-10; see
[decisions](../../decisions.md).

Worth deciding during Stage 2 rather than now: what the SFTP interface should become, given that the
user has ideas for it that determine how well the editor lands in Stage 5.

## Current state and next action

Memory bank and guide written, all Stage 0 decisions recorded. No project structure. Next: a fresh
session reads `AGENTS.md`, the active context and this plan, then begins Stage 1. Nothing blocks it.
