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


## D7 — a database service tunnels through its host's own SSH service — Implemented 2026-09-12

A database service carries no SSH fields. When the database is not directly reachable the capability
borrows the host's SSH transport from the shell and forwards to the database port. Host trust is
therefore shared with the terminal. Capabilities still never import each other.

**Built.** The hook landed as `GlassCapabilityHostAccess.forwardPort(toHost:port:)` rather than the
proposed `sshTransport(for:)`: the borrower needs a local port, not a transport, and returning a
port keeps the NIO graph out of `GlassShell` entirely. The lender side is
`GlassCapability.openPortForward(host:toHost:port:)`, defaulting to a refusal, implemented by
`GlassTerminalCapability`. 7 unit tests; **no live tunnel opened yet**. Host-key trust is refused
rather than prompted or assumed — see the limitation in
[the W-shell note](tasks/2026-09/2026-09-12_stage-3-shell-forward.md). Detail in
[the Stage 3 plan](tasks/2026-09/2026-09-12_stage-3-database-plan.md).

## D8 — "This Mac" is a real host, holding every service kind — Approved 2026-09-12

The user approved a built-in local host that behaves like any other connection and accepts several
services of the same kind: SQLite files and local MySQL/PostgreSQL as databases, a new local shell
on each click of the terminal toolbar icon, containers and VMs as desktops in Stage 4, and the local
filesystem as Files. It has no address and is never asked for one, is never published to the shared
catalog, and its services never tunnel.

## D8 addendum — what building it corrected, 2026-09-12

Implemented — [the local-host note](tasks/2026-09/2026-09-12_stage-3-local-host.md). Four
corrections to D8 as written, all found by building it:

1. **Files is not a service kind, and was not shipped.** It is a `GlassServiceTool` riding a
   Terminal service's live SSH session; no local-filesystem browser exists in the tree. A Files row
   on the local host would have opened nothing, so it was deliberately omitted rather than stubbed.
   Closing it needs a local backend for `SFTPBrowserView` or a new browser.
2. **`connectAll` on the local host is picker-only — no play glyph.** The device is already here;
   there is nothing to connect *to*, and its services are not facets of one thing. The failure mode
   is asymmetric: on a remote host a stray play costs a few sessions to one box, but here it would
   open a terminal, a database workspace per database and a VM console at once on the display you
   are looking at. With exactly one service the row stays a plain play button.
3. **Opening a window is not a session.** The terminal could have reported `.connected` the moment a
   local shell was *asked for*, stamping "last connected" on a shell that may have failed to launch.
   The outcome is queued instead and answered by the pane that actually starts the process, or by
   its `launchError`.
4. **Several services of one kind collided in the accessibility identifiers.** Three terminals on one
   host produced three *identical* identifiers, so every existing UI test was matching an arbitrary
   row and passing by luck — a defect in the test surface, invisible precisely because the tests
   stayed green. The first of a kind keeps the bare identifier; later ones carry their position.

Two further defects were found on the way, one pre-existing: `load()` can run twice concurrently
(`.task` plus the scene-phase observer), and **both** UI-test seeders checked "is it empty?" *after*
an await, so both could pass — producing four database rows where two were expected, visible in a
screenshot and in no unit test. Both now claim a one-shot flag synchronously before their first
await; the pre-existing `--ui-testing-seed-hosts` carried the same latent race.

The forward-broker trap D8 predicted was real and is closed: the broker offered a tunnel to any host
with an `.ssh` service, and the local host has one. Excluded in both the forward path and D14's trust
resolver, with a test that adds a real `.ssh` link to the local host so it fails if the guard goes.


## D9 — Stage 3 ships parity-plus, not parity — Approved 2026-09-12

glassdb's gaps are closed during the port rather than carried: row deletion (with the existing
exactly-one-affected-row guard), foreign-key navigation, a viewer for the audit log it already
writes, the AI assistant on iOS, and the explicitly unfixed SQL draft-loss bug. CREATE/DDL breadth
and streaming export stay out of Stage 3.

## D10 — results stay fully materialised in Stage 3 — Proposed 2026-09-12

No `AsyncSequence` exists in GlassDBKit; rows are bounded by appending a limit plus a sentinel row.
Kept as-is and revisited with export.

## D11 — cancelling a query drops the connection, and the UI says so — Proposed 2026-09-12

MySQL and PostgreSQL cancel by closing the transport; only SQLite cancels in place. Behaviour is
kept and surfaced honestly rather than disguised.

## D12 — the product floor stays at 26.0; glassdb's 27.0 was never justified — Approved 2026-09-12

glassdb declares `MACOSX_DEPLOYMENT_TARGET = 27.0` in all four configurations. A compile-based
sweep at 26.0 produced **exit 65, two diagnostics, one call site**: `visibilityPriority` and `.high`
at `../glassdb/glassdb/Constants.swift:663`. The SDK puts that API at **macOS 26.1** — not 27.0 —
so glassdb's floor was over-stated by a major version for a reason that does not exist. One
`if #available(macOS 26.1, *)` and the same project builds at 26.0 on macOS, iOS device, iOS
Simulator and visionOS Simulator. `GlassDBKit` contains zero availability annotations.

**No floor change.** Keeping 26.0 needs no new approval; raising it would. The cost of the guard is
that the SQL Run control loses its pinned toolbar slot at narrow widths and can fall into the `»`
overflow — cosmetic, nothing functional. Evidence and the exact commands:
[the floor sweep](tasks/2026-09/2026-09-12_stage-3-floor-sweep.md).

Implemented ahead of the port: the guard now lives once, in
`Sources/GlassLayers/GlassToolbarVisibility.swift`, as `glassKeepVisibleWhenCompact()` and
`glassOverflowFirstWhenCompact()`, covering macOS 26.1, iOS 27.0 and visionOS (where the API is
unavailable outright, not merely newer). `GlassTerminal`'s two private copies were replaced by it
across 8 call sites, so the database capability inherits the guard instead of adding a third copy.

## D13 — pinned-CA TLS cannot reach a stock MySQL server — Observed 2026-09-12

`.requiredCertificates(_, serverName:)` always sets `certificateVerification = .fullVerification`
and hands `serverName` to NIOSSL as the hostname to match. A stock MySQL 8.4 generates a
certificate with CN `MySQL_Server_8.4.11_Auto_Generated_Server_Certificate` and **no
subjectAltName at all**, so neither of the two available routes works:

- `serverName: <the IP>` — no SAN and a CN that is not the address, so verification fails.
- `serverName: <the CN>` — **NIOSSL refuses the string before contacting the server**:
  `NIOSSLExtraError.serverHostnameImpossibleToMatch … contains non-DNS characters`.

**The second reason is not what it first looks like, and the distinction decides the fix.** CN
fallback itself works: measured with OpenSSL against this server,
`s_client -verify_hostname MySQL_Server_8.4.11_Auto_Generated_Server_Certificate` returns
`Verification: OK`, code 0, while the same check against `192.0.2.6` gives `hostname mismatch`.
So the CN *would* match; NIOSSL simply will not accept a non-DNS string as a hostname to match
against. (Measured with OpenSSL; BoringSSL is expected to agree but that was not confirmed inside
NIOSSL.)

The fix is therefore **not** a better server name — no string works — but a policy that
authenticates the chain without matching a name: MySQL's own `VERIFY_CA`, as distinct from
`VERIFY_IDENTITY`. `DatabaseTLSPolicy` can express only the latter, so a user who pins the CA of a
default MySQL install cannot use TLS at all.

Found by running the live test against a real server rather than by reading. **Not yet fixed** — it
changes the engine's security surface, so it goes to the wave-4 security review.

**Severity settled 2026-09-12: a defect, not a blocker.** The open question was whether MySQL would
force TLS. Measured against a flushed auth cache, `mysql8LiveRoundTrip` passes over plaintext, so
mysql-nio does complete `caching_sha2_password` full authentication over the RSA public-key
exchange. A user on a stock MySQL therefore loses pinned-CA TLS and falls back to an unencrypted
connection that still authenticates safely — bad, worth fixing, not stopping anything.

The suite records this with `withKnownIssue` at `Tests/GlassDBKitTests/GlassDBKitTests.swift` rather
than deleting the block or asserting the failure as correct: the defect stays visible in every run,
and when the policy gains a CA-only mode Swift Testing will report the known issue as unrecorded and
send someone back to remove the wrapper.

### Two corrections after checking the call sites, 2026-09-12

**There is no silent fallback to plaintext.** It was suggested that a user asking for pinned-CA TLS
would quietly get an unencrypted connection, which would put the honest-status rule at stake rather
than only certificate handling. The code does not do this. `DatabaseSessionManager.swift:238-243`
chooses the policy **once** from `config.useTLS` and there is no retry path; a TLS failure throws
and propagates. The two `tlsPolicy: .disabled` sites at `:106` and `:234` are SQLite, which is a
local file and cannot have transport security at all — not a downgrade. Checked rather than
accepted, because "fails loudly" and "downgrades silently" are opposite findings.

**The real gap is larger than the one above, and it is in the app, not the engine.** grep of the
whole of `../glassdb/glassdb/` finds **no construction of `.requiredCertificates` anywhere**: the
app only ever builds `.requiredSystemTrust` or `.requiredSystemTrustForHost` (`:240-241`). So the
pinned-CA path is reachable only from tests, and there is no UI to supply a CA. Since a default
MySQL **and** a default PostgreSQL both generate self-signed certificates, the practical position
is: *a user who ticks "Use TLS" against a stock server gets a hard failure and no remedy inside the
app.* The engine has had the capability all along and the app never exposed it.

That reframes the work. Closing D13 needs both a CA-only verification mode **and** a way to import
or point at a certificate — which makes it a parity-plus item for Stage 3's own backlog alongside
the D9 closures, not merely a note for the wave-4 reviewer. Recorded here; not yet scheduled.

## D14 — host-key trust is resolved in the connect flow, not refused — Approved 2026-09-12

Supersedes the interim behaviour recorded in
[the W-shell note](tasks/2026-09/2026-09-12_stage-3-shell-forward.md), where
`GlassTerminalCapability.openPortForward` passes `trustDecider: nil` and an untrusted machine gets
`GlassPortForwardError.hostNotTrusted` telling the user to go and connect the Terminal service first.

**Why that was wrong.** It was justified on the grounds that a background tunnel is the wrong place
to ask a user to compare a fingerprint. The security instinct holds — auto-trusting would be a
silent downgrade — but the classification does not: opening a database service is a **foreground**
action. The user pressed play and is waiting. That is exactly the moment DBeaver, DataGrip and
Sequel Ace all resolve trust.

**Approved design.** The database connect flow surfaces the terminal's own trust prompt — the same
challenge, the same fingerprint UI, one flow for the product — rather than refusing. Where possible,
resolve trust **at setup time**: when a database service is added to a machine whose key is not yet
pinned, settle the fingerprint in the setup sheet so connecting later simply works.

**What makes this ours rather than a copy of theirs.** Trust is keyed `host:port` in
`SecretStoreHostTrustStore` (`Sources/GlassSSHTransport/SSHHostTrust.swift:81-95`), which lives in
the transport and is owned by no capability. So trust is an attribute of **the machine**, and pinning
it once in any capability is inherited by every other. Every comparable tool treats "the SSH host"
and "the database host" as unrelated strings that happen to coincide, so trusting a box for one
connection's tunnel does nothing for the next. The same structure is why the database service asks
for no SSH details at all (D7).

Owner: wave 2, W-capability, including the `GlassTerminal` edits — sequenced ahead of W-local rather
than locked, so the trust flow stays in one head. The refusal path stays as the honest fallback for
the case where no prompt can be shown.

**Approved shape, 2026-09-12.** The connect path needs **no new protocol hook**: `forwardPort` is
already async and main-actor isolated, so `GlassTerminalCapability.openPortForward` simply swaps
`trustDecider: nil` for one that routes into the existing prompt and awaits the answer. The database
side calls `forwardPort` unchanged.

The setup path does need one, because at setup time there is no connection to challenge:

```swift
public enum GlassHostTrustOutcome: Sendable { case trusted, declined, unavailable }

// GlassCapabilityHostAccess
func resolveHostTrust() async -> GlassHostTrustOutcome
// GlassCapability, defaulting to .unavailable — the same refusing default as openPortForward
func resolveHostTrust(host: HostProfile) async -> GlassHostTrustOutcome
```

Brokered exactly as `forwardPort` is, so capabilities still never import each other. **Not a `Bool`:**
a bare `false` would conflate "the user declined", "there was nobody to ask" and "**the host key
changed**" — and reporting a changed key as an ordinary failure is the swallowed-error pattern the
project rules forbid. Named `resolve` rather than `ensure` because it reports rather than guarantees.

**Known limit, by design.** The one-and-done sheet can create a host, its Terminal service and its
Database service in a single save, so when the Database tab's tunnel toggle flips there may be no
committed SSH service to challenge yet. Setup-time resolution therefore works only when adding a
database to a machine that already has a Terminal service; the combined case returns `.unavailable`
and falls back to prompting at first connect. Save is never blocked on it.

## D15 — read-only mode is enforced on the connection, not in the UI — Implemented 2026-09-12

A read-only database service must refuse writes. The obvious place is the session manager's
`executeQuery`, and it would have been wrong: **five write paths call the driver directly and never
go through it** — `SchemaBrowserView.swift:518` (truncate and drop), `TableDetailView.swift:3966`
(row update), `:4060` (a pasted range), `:4146` (insert) and `:4756` (schema change). A guard at
`executeQuery` would have left every one of them open while looking correct. Verified at the first
call site rather than taken on trust.

`ReadOnlyDatabaseConnection` therefore wraps the connection itself at connect time, so classification
happens **before the wire** and there is no path around it. Session-control statements pass, because
they select what you are reading. A statement the classifier cannot read is refused rather than
allowed: `unknown` is not evidence that something is safe. Eight tests drive it the way those five
callers do and assert that nothing refused reaches the driver.

The general lesson, which has now cost this stage twice: the shape of an API suggests where a rule
belongs, and the call sites decide it.

## D16 — a result-builder availability guard cannot be shared across modules — Observed 2026-09-12

`visibilityPriority` sits above the product floor, so its `if #available` lives inside a
`@ToolbarContentBuilder`. Extracting that guard into `GlassLayers` so two capabilities could share
it **broke the Release link**: `ToolbarContentBuilder.buildLimitedAvailability` undefined,
referenced from `GlassTerminal.o`. The compiler emits that symbol for the availability branch and
its opaque type descriptor does not resolve across a module boundary. `@inlinable` does not help.

Debug built clean, 592 unit tests passed and all three platforms built — only a **Release** build
found it. The guard is therefore duplicated per module on purpose
(`TerminalToolbarVisibility.swift`, `DatabaseToolbarVisibility.swift`), each carrying a comment
saying so, because it looks exactly like something to tidy away.

## D17 — validation reads the declared type, never result-set metadata — Implemented 2026-09-12

The record editor validates size and format from the column's **declared type** (`varchar(40)`,
`decimal(10,2)`, `enum('a','b')`) rather than from the driver's column metadata.

Reason: MySQL reports `columnLength` in **bytes**, so a `varchar(40)` in utf8mb4 arrives as 160 — a
limit built on it would let a user type 160 characters and fail at the server. PostgreSQL reports
no length at all. The declared type is identical on both engines, needs no adapter change, and is
already displayed beside the field.

`ColumnTypeConstraint` (what fits) and `ColumnValueFormat` (what is well formed) are separate, so a
value that does not parse is reported as the wrong *type* rather than the wrong *size*.

**Corrected while doing it:** `isBool` matched a bare `tinyint`. `tinyint(1)` is MySQL's boolean
convention; plain `tinyint` is an integer. A score column rendered as a toggle and **saving would
have written 0 over the stored value**. See
[the UI and validation note](tasks/2026-09/2026-09-12_ui-and-validation.md).


## D18 — credentials synchronize through iCloud Keychain — Approved 2026-09-13

The user: *"We can't truly sync database sessions if the database passwords stay app-private. That
must change… define everything on Mac, then pick up Vision Pro and get to work without having to
mess with settings and passwords."*

`GlasSecretStore` was built for this and defaulted off. `SecretMobilityPolicy.iCloudKeychain` exists,
`validateMobility` already enforces Apple's constraints, `kSecAttrSynchronizable` is wired into every
write, and the eligible-services list already names passwords, SSH passwords, RDP credentials and SSH
private keys. **`iCloudKeychain` appears zero times in the app** — the mechanism is complete and
unused, the same shape as `DatabaseCommands` and `DatabaseSession.openForward`.

**The distinction that was being conflated:** the access group controls which *apps on one device*
can read an item; `kSecAttrSynchronizable` controls whether it reaches the user's *other devices*.
The requirement needs the second, not the first — so the security review's F3 (database passwords
written into the shared Glass-family group, unreachable and never cleaned up) remains a bug to fix
and does not work against this decision.

**Why SSH keys can travel after all:** Apple synchronizes password-class items only, not keys or
certificates — but `GlasSecretStore` stores everything as `kSecClassGenericPassword`, so key bytes
ride inside a password item. Secure Enclave–backed keys genuinely cannot sync and
`validateMobility` already refuses them; that refusal stays.

See [Stage 3.5](tasks/2026-09/2026-09-13_stage-3.5-continuity.md). D19 (CloudKit for the catalog),
D20 (Secure Enclave keys stay device-bound and the UI says so) are **Proposed**; D21 (opt-in or
default, per-record or global) and D22 (what happens to existing device-only secrets) are **open and
need the user**.
