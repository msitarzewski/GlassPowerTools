# Decisions

## Approved — merge the three applications into one product (2026-09-10)

**Status: Approved by the user, not implemented.**

glas.sh, glassdb and glassDT become one application, Glass Power Tools, bundle identifier
`com.glasspowertools`. GlassEditorKit is proposed as a fourth capability and not yet confirmed.

Reasoning, with the evidence that supported it:

- The shared catalog already models a host owning services of kind `ssh`, `database` and `rdp`, so
  the three apps were partial views of one model.
- Substantial machinery exists only to keep three processes agreeing: pairing, cross-app URL routing,
  the shared App Group catalog with publication and removal journals, and a cross-app Keychain group.
  Merging deletes it.
- The three apps pin different revisions of the same shared packages, recorded in glassDT's research
  notes. During 2026-09-09 that skew forced two features to be deferred: a VNC service kind in the
  catalog, and a VNC-specific credential record. Password-only VNC still uses a placeholder account
  name as a result.
- Three settings interfaces had already drifted; part of 2026-09-09 was spent extracting one design
  from glas.sh so glassDT would stop looking like a stranger.
- None of the three applications is published, so merging costs no product identity.

**Accepted cost:** protocol parsers and live session memory share one address space. Noted in
[technical context](techContext.md) with the mitigation path.

**Superseded:** an earlier recommendation to consolidate the shared packages into one versioned
foundation. That was the right answer for keeping three products, and is unnecessary here.

## Approved — start in a fresh directory (2026-09-10)

**Status: Approved by the user, acted on only to the extent of creating this memory bank.**

`~/Software/glass/GlassPowerTools`, rather than renaming one of the three repositories. Building on
glas.sh would have kept two thirds of the shell in place but made the other two capabilities
permanent guests in its structure, and the shell-to-capability boundary is the thing this product
depends on. The three public repositories will be deprecated with redirects later, on the user's
instruction.

## Approved — GlassEditorKit is a built-in capability (2026-09-10)

**Status: Approved.** The library is brought in from the start and the shell boundary accounts for it.
Its interface is built last, after SSH, databases and remote desktop. The user has SFTP interface
ideas intended to make editing shine, so the SFTP surface is designed with that in mind.

## Approved — capability order (2026-09-10)

**Status: Approved.** SSH and SFTP first, then databases, then remote desktop, then the editor
interface. SSH leads because it is the largest source application and the one the user works in most,
so it stress-tests the shell boundary hardest.

## Approved — data migration is not a constraint (2026-09-10)

**Status: Approved.** The user is the only user. The new identity still declares the existing App
Group `group.sh.glas.shared` and Keychain access group `sh.glas.shared`, because that is free and
keeps current hosts and credentials, but no import path is built and no stage blocks on proving it.

## Approved — one deployment floor, Apple Silicon only (2026-09-10)

**Status: Approved.** 26.0 on macOS, iOS and visionOS. `arm64` only, with no Intel slice.

**Reason, recorded because it shapes the work:** the floor exists to reach visionOS capabilities, not
for tidiness. The project began as a world-class SSH tool for visionOS that uses what the platform
actually offers, and the other capabilities followed with the same intent. The other platforms
inherit the floor from visionOS rather than setting it.

**Consequence:** visionOS leads the design and the other platforms adapt from it. See
[system patterns](systemPatterns.md).

## Approved — the layering system is foundational (2026-09-10)

**Status: Approved.** Window transparency, including title bar backgrounds, is built into the shell
before any capability arrives, rather than added later per surface. It is proven first on the SSH
connection panel and the connection detail view.

Reuses existing work: the titlebar material already extracted into GlassConnectionUI and consumed by
all three applications, and glassDT's window frame, canvas backdrop, opacity and background frost.

## Approved — one multiplatform app target, hand-maintained project (2026-09-10)

**Status: Approved by the user on 2026-09-10, not implemented.**

Glass Power Tools is **one multiplatform application target** covering macOS, iOS and visionOS,
following the model glas.sh and glassdb already use: `SDKROOT = auto`, `SUPPORTED_PLATFORMS`
listing all three platforms and their simulators, per-platform divergence expressed as
`[sdk=macosx*]` conditional build settings for entitlements and Info.plist, and `platformFilter` on
individual files for platform-only assets. It is **not** one target per platform, which is the
glassDT model.

The project file is **hand-maintained**, using synchronized folders so that adding source files
never edits `project.pbxproj`. XcodeGen is not used.

**Evidence considered:**

- glas.sh and glassdb, 53,000 of the family's 59,000 application lines, use the multiplatform model.
  glassDT's three-target model was the outlier.
- The model matches the product principle of one design, led by visionOS, adapting to the other
  platforms. Three targets is structurally three applications sharing code.
- XcodeGen 2.46 was verified able to express the multiplatform model with a generated probe on
  2026-09-10, so the tool was not rejected for inability. It was rejected because its one decisive
  advantage, stamping several targets from a template, does not apply to one target; because
  every source group in glas.sh (app, macOS overlay, widget, both test bundles) is already a
  synchronized folder with zero explicit `.swift` file references, removing the file-adding pain
  XcodeGen exists to solve; and because glas.sh's hand-curated `project.pbxproj` with authored
  sequential identifiers proves the hand-maintained model works in this family at 31,000 lines.
- glas.sh embeds a widget extension with `platformFilters = (ios, xros)`. The merged application
  carries that second target in the same way.

**Consequence:** Stage 1 copies glas.sh's project structure, not glassDT's `project.yml`. See the
[Stage 1 task](tasks/2026-09/2026-09-10_stage-1-shell.md).

**Supersedes** the merge plan's original wording "an application target per platform", which was
inherited from glassDT without a decision having been taken.

## Approved — engines are first-class shared modules; one capability module per app (2026-09-10)

**Status: Approved by the user on 2026-09-10 and refined the same day on the user's instruction
("first-class integrations, not hacks"). Not implemented.**

Two layers, and the rule that capabilities never depend on each other holds between them:

**Engines** — shared modules with public APIs, no UI, no dependency on the shell:
- `GlassSSHTransport`, extracted from glas.sh in Stage 2: connection, host trust through
  GlasSecretStore, authentication, PTY channel, **SFTP client**, **local and remote port
  forwarding with a tunnel API**. Designed from the first commit for four consumers: the terminal
  (shell channel), the database capability (tunnel), the desktop capability (tunnel for VNC and
  RDP), and the editor (SFTP file operations). The dependency map locates it: the SSH types in
  `Models.swift`, `SessionManager`, `PortForwardManager` and `ServerManager`.
- `GlassDBKit`, already a package. Its `SSHTunnelManager` over glassdb's older vendored Citadel is
  replaced by `GlassSSHTransport`'s tunnel API; there is one SSH stack.
- `RDPKit`, `VNCKit`, `GlassRDPTransport`, `GlassVNCTransport`, already packages.

**Capabilities** — one module per source application, every file's `internal` access kept, only
capability registration, scene views and settings pages made `public`: `GlassTerminal` (glas.sh
minus the transport), `GlassDatabase` (glassdb minus the tunnel), `GlassDesktopCore` and
`GlassDesktopUI` (already this shape), the editor interface in Stage 5. Each depends on the shell
and on engines; none on another capability.

**Consumer matrix — each row is a first-class dependency on the engine's public API, never on
another capability (user's instruction, 2026-09-10):**

| Engine service | Terminal | Database | Desktop (RDP/VNC) | Editor |
|---|---|---|---|---|
| Shell channel (PTY) | uses | — | — | — |
| **SFTP session** | SFTP browser | — | — | **open / save remote files** |
| **Port forwarding / tunnel** | port-forward UI, SOCKS5 | **DB over SSH tunnel** | **VNC and RDP over SSH tunnel** | — |
| Host trust + credential resolution | uses | uses | uses | uses |
| `GlassDBKit` (database engine) | — | uses | — | SQL documents in Stage 5 |
| `RDPKit` / `VNCKit` | — | — | uses | — |

This is what makes the Stage 5 integrations real rather than bolted on: VNC over SSH is the desktop
capability calling `GlassSSHTransport.forward`; the editor over SFTP is the editor calling the same
module's SFTP client; the spatial workspace composes capabilities through the shell.

Evidence in the [Stage 2/3 groundwork](tasks/2026-09/2026-09-10_stage-2-3-groundwork.md). The
earlier five-way UI split of glas.sh (terminal, SFTP browser, port-forwarding UI, workgroups) stays
deferred: those are presentation layers over one engine and can be separated later inside a
building app.

**Supersedes** the Stage 2 wording "carve glas.sh into terminal, SFTP, port forwarding, workgroups,
SSH transport" in the merge plan and the Stage 1 note.

## Approved and done — version control for the inputs and this project (2026-09-10)

**Status: Executed on the user's explicit instruction, 2026-09-10.**

- `../GlasSecretStore`: the 12 uncommitted files (RDP credential store, synchronizable-Keychain
  lifecycle, provenance and notes) committed on `codex-completions` as `aa1b3f1`. Tree clean.
- `../GlassConnectionKit`: initialised on `main`, 47 files, initial commit `d48a5ff`.
- This project: initialised on `main` with the guide, Memory Bank, session log and package
  skeleton. Worker output is committed as it lands.

Commit messages carry co-author attribution and no session URLs, per the user's global rules.

