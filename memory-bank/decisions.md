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
that integrations be first-class rather than workarounds. Not implemented.**

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

The owner stated that database sessions cannot truly sync while database passwords stay app-private,
and that this must change: define everything on the Mac, then pick up the Vision Pro and get to work
without touching settings or passwords.

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


## D21 — credential sync is on by default — Approved 2026-09-13

The owner chose on by default for the intended audience.

The experience the product promises is picking up a Vision Pro and working; an opt-in buried in
settings does not deliver that, because the moment a user has to discover a switch they have already
had the bad first run this stage exists to prevent.

**The cost, recorded so it is a decision and not a side effect:** a synced secret has a larger blast
radius than a device-bound one. Items are end-to-end encrypted to the user's circle of trust and
Apple cannot read them, but any device in that circle can. That is the trade the default takes, and
the UI is expected to state what travels rather than let a user infer it (see D20).

Secure Enclave–backed keys are unaffected: they cannot sync at all and `validateMobility` refuses
them regardless of this setting.

## D22 — existing device-only secrets are rewritten, not migrated — Approved 2026-09-13

The owner noted that no one uses the tool yet and chose a rewrite.

There is no installed base to preserve, so the stage takes the simple path: a secret written under
`.deviceOnly` is not migrated in place. It is replaced the next time it is saved, and the old item is
deleted rather than left behind.

This removes the expensive half of the work — no dual-read fallback, no half-migrated state to
reason about, and none of the partial-failure rollback complexity the security review found untested
in `applyCredentialMutation`. It also lets F3's stranded items be swept rather than reconciled.

**This decision has a shelf life.** It is safe only while the user is the only user; the first real
installation makes it false. It should be re-read, not reused, the moment that changes.


## D19 — the host catalog syncs through CloudKit, not the key-value store — Implemented 2026-09-13

`GlassShellSettingsSync` already syncs terminal themes through `NSUbiquitousKeyValueStore`, so
reusing it for the library was the obvious move and the wrong one. KVS is **1 MB across 1024 keys**,
every write **replaces the whole value** for its key, and there is no partial update — two devices
editing different hosts would overwrite each other. Apple's own line decides it: *a value* belongs
in KVS, *records* belong in CloudKit. A host library is records and grows with use.

KVS keeps the preferences it already carries. The boundary is stated so it does not drift.

`HostProfile` needed no changes: `updatedAt` orders writes, `deletedAt` is a tombstone rather than
an absence, and `lastWriterID` names the device. The catalog has modelled convergence since it was
written for three apps sharing one file.

**The merge rule, stated so the trade is visible rather than discovered:** last write wins by
`updatedAt`. Per-field merging would be better for two people editing one host at the same moment
and is not worth its cost here — the library is edited rarely, by one person, usually on one device.
A **tombstone beats an edit at the same instant**, because a deletion undone by a stale edit is the
failure people notice. Equal timestamps otherwise keep the local copy, so a device echoing back what
it sent does not churn.

The whole profile travels as one encoded field rather than a CloudKit schema mirroring its
properties: a record type is a schema commitment, `HostProfile` already versions itself, and nothing
is queried by field.

Container `iCloud.com.glasspowertools`, provisioned automatically under the existing automatic
signing. Verified in the signed entitlements on macOS, iOS and visionOS.

**Not proven by any test here, and no unit test can prove it:** that CloudKit delivers the records,
that a change token resumes correctly, or that two real devices converge. Those need two devices and
an iCloud account — the device checklist in [Stage 3.5](tasks/2026-09/2026-09-13_stage-3.5-continuity.md).

## D20 — the interface says what travels and what does not — Implemented 2026-09-13

With sync on by default (D21), a user is entitled to know which secrets reach their other devices
**before** they find out by a connection failing on one.

Settings ▸ Privacy now carries an "On your other devices" section: the library's sync state in words,
and the plain statement that passwords, SSH key passphrases and private keys travel through iCloud
Keychain encrypted to the user's devices — **and that a service set to require authentication does
not**. A key protected by this device's biometrics is bound to this device's hardware and cannot
sync; `KeychainOperations.validateMobility` refuses it outright. Being asked for that one password
again on another device is correct behaviour and indefensible as a surprise.

## D23 — pinned SSH host keys synchronize, and there is one configuration for them — Implemented 2026-09-13

**Approved by the standing continuity requirement, not by a fresh question.** The owner's requirement for
Stage 3.5 was to define everything on the Mac, then pick up the Vision Pro and get to work without
touching settings or passwords. Host trust was left device-bound as an open question, which in
practice meant: every machine the Mac already trusts has to be re-approved, by fingerprint, on the
Vision Pro and again on the iPhone. That is the thing the requirement names.

A pinned host key is a **public** key — the fingerprint `ssh-keygen` prints. There is nothing to
protect by keeping it local, and the protection it does provide (noticing when a server's key
changes) is *stronger* when every device agrees on what the key was.

`sshHostTrustService` joins `validateMobility`'s eligible set, and the set moved out of the function
onto the configuration as the public `SecretStoreConfiguration.synchronizableServices`, so a caller
can ask the same question the validator answers. Secure Enclave services stay off it permanently: a
sealed token is usable only by the chip that minted it.

### What this repaired, which was not the question it started as

Checking whether host trust *should* sync surfaced that host trust did not work. D18's fix moved the
**transport's** trust store to a device-bound configuration and left `KeychainManager`'s own
`savePinnedHostKey`, `replaceHostKey`, `allPinnedHostKeys` and `trustedHostKeyBase64Set` on the
synchronizing one. Those four are where the **trust prompt** writes. So:

- accepting a fingerprint through the UI threw `ineligibleService` — the D14 prompt could not
  complete;
- and even without the throw, a synchronizable Keychain item and a device-only one with the same
  account are *different items*, so a pin written on connect was invisible to the prompt.

`KeychainManager.hostTrustConfig` is now the single name for where pins live, used by all four
methods and by all three `SecretStoreHostTrustStore` construction sites. `deviceBoundConfig` remains
for exactly one thing — Secure Enclave key material — and its documentation says so.

### Why nothing caught it, stated so the gap is not re-created

**No `swift test` process can write a synchronizable Keychain item.** Measured on this machine:
`SecItemAdd` with `kSecAttrSynchronizable: true` returns `errSecMissingEntitlement` (-34018) with or
without the data-protection Keychain, because the item needs `com.apple.application-identifier`;
ad-hoc signing the test binary with that entitlement gets the process killed on launch. The real-host
integration suite passes an `InMemoryHostTrustStore`, so it proves SSH works and proves nothing about
storage. Every other mobility test asserted a configuration's *properties* rather than driving an
item through the store.

`HostTrustSynchronizationTests` now exists and **reports skipped, with that reason, rather than
passing vacuously**. Its refusal half runs everywhere. The proof that the whole path works is
`testConnectsToRealHostThroughTheShell` on macOS against the live VM: it reaches the prompt, accepts
it, stores the pin under the app's real synchronizing configuration and connects — **the first time
anything has driven the D14 prompt.**

### Consequence accepted, per D22

Pins written under the device-bound configuration are different Keychain items and are not carried
over. Each host is trusted once more, through the prompt, and then travels. That is the rewrite
D22 authorized, and it exercises the prompt rather than avoiding it.

## D24 — the family's sidebar toolbar arrangement — Implemented 2026-09-13

**Approved by the user after an expensive detour**, and recorded because it had already been
rediscovered and lost more than once: the owner pointed out that glas.sh and glassdb both already
use this pattern, proven working, and directed that it be copied and made the standard for any window
with a sidebar.

**On macOS, do not remove `.sidebarToggle`.** glassdb's `databaseSidebarChrome()`
(`glassdb/Constants.swift:267-273`) removes it on every platform *except* macOS, and glas.sh never
removed it at all. Left alone, AppKit's own item sits at the sidebar's trailing edge, never enters
the overflow menu, and moves with the column.

**The app's own action goes on the content column, at `.navigation`** — the placement glassdb gives
Add Connection (`ConnectionManagerView.swift:327-330`). It leads the content region, just past the
column divider.

That is the whole standard. It now applies to the terminal workspace
(`GlassTerminal/macOS/MacWorkspaceView.swift`) and the library (`GlassConnectionLibrary`), and is
what any future window with a sidebar should do.

### Why it kept regressing, stated so it stops

Glass Power Tools had inherited `.toolbar(removing: .sidebarToggle)` — twice in the terminal — plus a
hand-built "Toggle Sidebar" button. **A placed button cannot behave like the system item.** It is an
ordinary toolbar item, so it drops into the overflow menu *with its title* once the toolbar is
crowded, and if it sits in the sidebar's toolbar region it disappears when that column collapses.
Neither is fixable by choosing a different placement, and on 2026-09-13 the following were each
tried and each failed: `.navigation` always; `.automatic` with a flexible spacer; a placement
switched on `columnVisibility`; a `ToolbarItemGroup`; and attaching the toolbar to the
`NavigationSplitView` itself. The last removed AppKit's `NSTrackingSeparatorToolbarItem`, which only
exists while the sidebar column contributes toolbar content.

**`MacTerminalWindowPolicyTests.workspaceUsesNativeTitle` was part of the loop.** It pinned the
app-supplied toggle ahead of the separator — encoding the deviation as a requirement, so every
attempted fix had to satisfy something the family standard deliberately does not do. It now asserts
the standard, with the reason in the test.

**The lesson worth more than the fix:** a working implementation sat in a sibling directory the
whole time. When it disagreed with reasoning about placements, the implementation was right.

## D25 — deleting a machine deletes what its capabilities stored — Implemented 2026-09-13

Found by the owner, who asked whether a cache remained after deleting every stored session — a
host deleted from the library kept appearing in the terminal's Connect Saved Host.

`deleteHost` removed the catalog records and the preferences and **told no capability**. Each one's
own configuration was orphaned — the terminal's `ServerConfiguration`, the database's connection,
their Keychain entries — and stayed *reachable*, because surfaces that read a capability's store
rather than the catalog went on listing it. There was then no way to remove it: the machine that
owned it no longer existed.

`removeService` has always done this for one service and says so in its own documentation
(*"then lets the owning capability delete what it stored for it"*). `deleteHost` never called it.
The same shape as `DatabaseCommands`, `DatabaseSession.openForward`, `SecretMobilityPolicy` and
`GlassLibraryNavigation`'s `extras`: written, documented, joined to nothing.

Deletion now collects the host's services first, removes the records, then asks each owning
capability to clean up. A capability that throws does not strand the others — the records are
already gone, so stopping at the first error would orphan everything after it; the failure is
collected and rethrown once every service has had its turn.

**Two tests, verified to bite:** with the capability pass disabled both fail; with it, both pass.

## D26 — the catalog is the one store for a connection

**Status: Approved** by the user, 2026-09-14: option D, with the clarification that the "too big
right now: it's a migration of existing local data" objection instead means making sure every store
Power Tools owns is cleaned up (including keys) and that this is done correctly.

**The decision.** A service's own configuration lives on its `HostServiceLink`, encoded by the
capability that owns it. The catalog *is* the store, not a copy of one. Each capability's separate
store is **deleted**, not migrated: `servers` in SharedDefaults, `glassdb.connections`,
`connections.json`, and the `sshKeys` library.

**Why not the cheaper option.** An earlier write-up offered A — the same transport, but with each
capability keeping its own store as master and the catalog carrying a copy. That leaves two copies
of one truth and a rule about which wins. The user's answer removed the only reason A existed: there
is no installed base to migrate, so "one store" costs no more than "two stores kept in step", and it
is the version that stays correct.

**Why migration was never a real constraint, recorded because it was got wrong three times.** The
user has said since 2026-09-11 that the user base is the two of us, that no one uses it yet, and
that data loss is acceptable. Pricing in a migration cost turned the correct design into "too big right now" and
recommended the weaker one. **When the user has stated a constraint is absent, stop re-deriving it.**

**What this makes true**, and it is the sentence the product is: add a host on any device, attach a
service, import a key — and connect from any other device. Measured 2026-09-14, the pieces that
already travel are the host profile, the SSH key material and passphrase
(`sshKeysPrivateService`, `sshKeysPassphraseService`) and the host-key pin (D23). D adds the two
that do not: the service configuration and the key record.

**The deliberate exception.** Secure Enclave key material never synchronizes
(`KeychainManager.swift:575-584` routes it to a device-bound configuration) because a hardware key
cannot leave its device. "Works everywhere" is therefore true of an imported key and false of a
generated hardware one, by design.

**Amended the same day: keys are not a detail of this.** The user required a key to exist on its
own, so that it survives deleting the Linux server's Terminal connection and can be reused for other
hosts and services. A key outlives connections and is shared by them, so it gets its own
stage and its own manager — see
[keys first class](tasks/2026-09/2026-09-14_d26-keys-first-class.md). The original scope item 2
below understated it as folding a library into the Keychain.

**Scope, as the user framed it — cleaned up correctly, including keys:**

1. Connection configuration onto the service link; the per-capability stores deleted.
2. Keys promoted to a first-class, workspace-level library with a manager surface, independent of
   any connection's lifetime. **A service whose credential cannot leave the device does not appear
   on other devices at all** — the user's model, 2026-09-14: a Terminal that uses a device-bound key
   becomes a device-bound terminal and does not appear on the iPhone. Secure Enclave material is the
   trigger, the binding is derived from the credential rather than stored, and the publish/apply
   pair must both be implemented or a device deletes its own hardware-key services on the second
   sync.
3. **Storage keys still carry the old app's names.** Measured on this Mac: 529 keys, 295 KB, of
   which **82% is under `glassdb.*` or `app.glassdb.*`** — `glassdb.queryHistory` (151 KB),
   `glassdb.connections` (59 KB), `glassdb.mutationAudit.v1`, and 206 `app.glassdb.grid*` keys. The
   user-visible strings were renamed weeks ago; the storage keys never were.
4. **Unbounded accumulation:** 263 `macWorkspaceRestoration.*` keys, never pruned.
5. Synced deletion must cascade to capabilities as local deletion already does (D25). Today a host
   deleted on one device vanishes from the others' libraries and leaves their configuration orphaned.
6. View state (query history, grid layouts) stays local, under corrected key names.

**No conversion path.** The new build reads nothing old and removes the legacy keys on first launch.
Half-converted is the only outcome worth avoiding, and there is no data to preserve.

**Acceptance, and no test replaces it:** add a host with a key on the Mac, connect from the phone,
and watch whether it prompts for host trust. That single run proves the configuration sync, the key
record sync and D23's pin sync together.

## D27 — every saved connection has a host record, created for the user rather than by them

**Status: Approved** by the user, 2026-09-14, who accepted the recommendation.

**The finding that forced it.** Two paths create a saved server with no host record and no service
link, both with a fresh `UUID()`: `SettingsManager.importSSHConfig` (`SettingsManager.swift:1040-1049`)
and the standalone Add Server form, `TerminalServiceDraft.saveStandalone`
(`ServerFormViews.swift:324-336`), reached from `requestAddServer()` and from the Tailscale panel
(`TerminalTailscaleView.swift:104`). Only `GlassShellSetup.swift:334` creates a link.

**Those servers are already invisible**, which is why this is a live defect and not something D26
introduces. `GlassShellLibraryView` renders `model.items` — the catalog — and nothing anywhere in
`Sources/GlassShell` reads `serverManager.servers`. A host imported from an `ssh_config` cannot be
seen, favourited, tagged, given a second service or synced; it is reachable only from the terminal's
own Connect-Saved-Host surfaces. Under D26 it has nowhere to be stored at all.

**The decision.** Both forms stay exactly as they are. Each creates the host record and the `.ssh`
link **behind the scenes**, so the machine appears in the library like every other machine. The
alternative — rerouting Add Server through the shell's host sheet — is a visible workflow change
that buys nothing this does not.

**Mechanism:** a closure on the runtime set by the composition root, the pattern
`GlassDesktopRuntime.hostAccess` already uses (`GlassDesktopCapability.swift:45`), so the capability
still never holds the shell model (project rule 6). The shell side is already public:
`addHost(displayName:address:…)` and `addService(kind:displayName:endpointID:)`.

**The one visible consequence, stated so it is not reported as a bug:** importing an `ssh_config`
with twelve hosts now puts twelve machines in the library. Today they appear nowhere.

**Scale, measured 2026-09-14:** `com.glasspowertools.plist` holds **one** saved server. A
correctness fix, not a migration.

## D28 — what authenticates what is derived, never stored

**Status: Approved** by the user, 2026-09-14, from the scenario they set: the Mac and the Linux server share
a key, and the Mac terminal using it is deleted while the Linux server's terminal still uses it; the user
asked for some kind of lookup that tracks which services use each credential.

**The decision: no table.** The edge already exists on the service's own configuration
(`sshKeyID`). Once D26 stage 1 puts configurations in the catalog, "which services use key K" is one
pass over `configurations(ofKind:)`. A stored usage table is a second copy of a truth that already
exists and has to be kept in step through deletion, editing, sync and merge — and D25 is exactly the
bug where deleting a thing forgot to tell the other store. A derived index cannot drift.

**The user's scenario falls out of it with no cascade to write:** deleting the Mac's Terminal
removes that service's configuration, the edge goes with it, and the key reads "used by 1 · the Linux server ·
Terminal". The Linux server is untouched because nothing ever pointed at it.

**Only keys are shared. Measured 2026-09-14:**

| Auth | Shape |
|---|---|
| SSH key | **many** services → one key. `sshKeyID` appears in six files, all the terminal's |
| Password | keyed by service id (`KeychainManager.serverPasswordAccount(for:)`) — exactly one service |
| RDP and database credentials | one service each |
| Database over SSH | holds no key; borrows the host's forward from the terminal (D7) |

So the surface is a **key** manager with a usage list, plus flat 1:1 inventory rows for everything
else — considerably smaller than tracking usage for every credential first sounded.

**Detaching from the key side is a write, and it has consequences that must be stated at the point
of choice:**

1. **A service left with no credential cannot sign in.** The action offers the replacement inline
   (another key, or a password) or leaves the service visibly *needs setup*. Silently broken is the
   one outcome to refuse.
2. **Detaching a Secure Enclave key changes where the service exists.** Device-binding is derived
   from the credential (D26 stage 3), so removing a hardware key stops a terminal being device-bound
   and it **starts appearing on other devices**; attaching one makes it disappear from them. This is
   a real consequence of a key-side action and belongs in its confirmation.

**The failure mode designed in from the start:** a configuration this build cannot decode is skipped
rather than fatal. So "used by" must report *"2 services, plus 1 this build cannot read"* rather than
silently undercounting — otherwise a key still in use reads as unused and gets deleted. A zero only
ever proves where you looked (project rule 24). A key genuinely used by nothing says so plainly:
that is the state after the Mac deletion and the signal that it is safe to delete.

**Where it lives:** the key manager panel in the library sidebar beside Collections (D26 stage 4),
with "used by" as host · service rows each carrying its own detach — which is the point of the
request: detaching a given key from the Linux server's terminal directly, without walking Connections › the Linux server › Terminal.

## D29 — Uninstalling is a feature, not a support article

**Status: Proposed, 2026-09-16.** While clearing three dead apps off the Mac by
hand, the user asked for uninstalling to be as easy as installing.

**Why it earns its place in this product rather than a README.** Removing the three source apps
today meant walking eight locations — the bundle, a preferences plist, a sandbox container, saved
window state, caches, HTTP storage, a shared App Group container and the Keychain — and knowing
which of them the *surviving* app still reads. Two of those are shared: deleting
`group.sh.glas.shared` or the `sh.glas.shared` Keychain group would have taken Glass Power Tools'
own hosts and credentials with them. Nobody should have to know that, and no support article makes
it safe, because the answer differs by what else is installed. The app knows.

**What it does.** Settings ▸ a plain **Uninstall Glass Power Tools…**, which:

1. **Says what it will remove, counted, before anything happens.** *"4 machines, 7 services, 2 SSH
   keys, 31 saved passwords, 1,729 preference entries, 4 MB of query history."* The same read the
   key manager already does for "used by" — nothing new has to be invented to count it.
2. **Asks what to do with credentials separately**, because they are the one thing that is not
   ours to assume about: *keep them in the Keychain* (they synchronize, and another device may
   still be using them) or *destroy them here*. Secure Enclave material is named as destroyed
   either way — it cannot leave the device, so it dies with the install.
3. **Offers an export first**, the same document the library already writes, so "uninstall" and
   "start clean" stop being the same irreversible act.
4. **Removes, then reports what it could not remove and why** — a file the sandbox refuses, a
   Keychain item another app's access group holds. Never a silent partial success.
5. **Quits and moves its own bundle to the Trash**, which is where uninstalling actually becomes as
   easy as installing: the user does not then go hunting in `~/Library`.

**What it must never do:** touch another app's container, delete a Keychain item outside this app's
access group, or remove the shared App Group container while any sibling still declares it. The
uninstall is scoped to what this app created.

**How it gets tested:** against a real `GlassShellModel` over a temporary directory — the inventory
count matches what was created, the credential choice is honoured in both directions, and a second
app's container in the same fixture is still there afterwards. The one part no unit test can prove
is moving the bundle to the Trash; that is a device check.

**Not approved, not scheduled.** It belongs after D26 stage 5 (storage cleanup), which is the same
knowledge pointed the other way: stage 5 works out what this app writes and where, and an uninstall
is that list executed.

## D30 — watchOS stays out until someone else is using this — Approved 2026-09-20

**Status:** Approved by the user, 2026-09-20: the Watch is to be revisited once someone other than
the owner is using the product. `AGENTS.md` has excluded Apple TV and watchOS since the merge was
decided; this reaffirms it with a condition attached rather than leaving it a flat no.

**The use cases, ranked, so the next look starts from them rather than from scratch.** They were
worked out on 2026-09-20 and they are real:

1. **"Your deploy finished."** Start something long on a host, put the phone away, and the wrist
   taps when the prompt comes back, with the exit code and the last lines. Nothing else in this
   product is more worth leaving a desk for.
2. **Snippets on the wrist.** The terminal already keeps a snippet library; the Watch picks from
   it and confirms. The command was composed earlier on a real keyboard, which is what makes a
   one-tap fleet remote defensible.
3. **A transfer on the Smart Stack.** `SFTPTransferActivityStore` already tracks progress. This
   one needs **no new seam at all** and is the cheapest magic available.
4. **"Is it up?" as a complication**, and **trust prompts as approvals** — a changed host key is
   exactly the kind of decision that should interrupt you anywhere. **No key material ever goes
   to the Watch**; it approves presence, never identity (D18/D23).

**What it must never be:** a terminal, a database browser, or anything whose answer is text you
have to scan. The screen is wrong for it and a bad one costs more than none.

**The prerequisite is not watchOS.** Three of the four want *"run a command on this machine and
tell me when it is done"* — the same seam the editor needs for `git status`, project-wide `rg`
search and server-side LSP (Stage 5). Build that for the platforms with users first; the Watch is
then its fourth consumer and a small app.

## D31 — A session outlives the screen it was on, where there are no windows — Implemented 2026-09-21

**Context.** D1/D2 gave a phone one list of what is open and a way back into any of it. Building
it exposed that two of the four capabilities had nothing to go back *to*: the editor discarded its
workspace and the desktop closed its connection, both in `onDisappear`, which on a phone fires
every time the full-screen cover is dismissed — that is, every time the user taps the back
chevron meaning "show me the library again".

**Decided.** On a device that cannot open windows, **leaving a session's screen does not end the
session**. Closing is a separate, deliberate act, and the switcher's swipe is where it lives.

- **The editor now follows this.** `forget` keeps the workspace when
  `closesWorkspaceWithItsWindow` is false; `closeWorkspace` always discards. Without it, tapping
  Connections threw away open documents and unsaved edits silently. See rule 54.
- **The terminal and the database already followed it.** Leaving either clears only the id
  pointing at the session; the connection stays live. That is the behaviour being generalised,
  not a new one.
- **The desktop deliberately does not.** `DesktopSessionView.onDisappear` closes the session and
  is left alone: a live RDP or VNC stream held open in the background on a phone has a cost in
  battery and data that the other three do not, and nobody has asked for it. It therefore
  contributes no rows to the switcher, which is honest rather than an omission. **Revisit when
  someone asks to leave a desktop and come back** — the seam is one `openSessions()` away.

**Consequence accepted.** A database workspace's *tabs* still do not survive the round trip: the
session and its on-disk SQL drafts do, but `DatabaseWorkspaceView`'s tab state is `@State` and
dies with the view. Hoisting it onto `DatabaseSessionManager` is the fix and is not made here.

## D32 — Records that agree on an address are one record, automatically — Implemented 2026-09-21

**Context.** Three devices each set the Linux server up before they had heard of each other's record. The
catalog merges by record id, so eleven records for one machine accumulated; the library grouped
them into one row and its detail showed the union of their services — two Terminals, two
Desktops. The group projection (`GlassShellHost.members`) had been treated as a lasting state,
and Stage 6's `consolidateRecords(of:)` had been held back for source applications that are now
obsolete.

**Decided.** After every load and sync, every group whose members **agree on the address** is
folded into its canonical (oldest) record: services move over, one link survives per
(kind, name) — the smallest endpoint id, decided from the catalog alone so every device agrees —
the losers are handed to their capability as removals, and the emptied members are tombstoned.
Preferences keyed on a member migrate before the fold; a folded member's id keeps resolving.

**Deliberately not folded:** a group whose members **disagree** on the address. Two records
named "db" at two addresses are two machines sharing a name, and the design keeps surfacing that
for the user to settle with one edit. The group projection stays as the mechanism for that case
and for the moment between a sync arriving and the fold running.

**Consequence accepted.** When two devices each configured the same service, one device's
configuration record is removed. Pre-launch, one user, three devices — as the user put it, there
is no fleet of devices to protect.

## D33 — Active in the library, and one control to reach it — Implemented 2026-09-21

**Context.** Every capability worked on a phone and none could reach another. The morning's
answer was a per-session Sessions control with a switcher sheet and a gallery (D1–D3). By the
evening the user cut it, asking for the open-connections problem to be drastically simplified on
every deployment target.

**Decided.** The library gets a fourth category, **Active** — the live sessions grouped by the
machine each is on, each machine a disclosure — and every top toolbar in the app gets the **⚡**,
one control meaning "take me to Active". Choosing a row switches to the open session. The Sessions
control, its sheet and the gallery are **removed**; `GlassOpenSession` and `openSessions()` stay as
the seam Active reads, and the Mac's Terminal Overview keeps drawing sessions with the card and
layout that gallery left behind.

**Kept deliberately.** Workgroups — the terminal's saved multi-machine layouts — unchanged.

**Later, maybe.** The user would like a more playful way to view that list. The seam is ready for it.


## D34 — A deletion is dated; the later statement wins — Implemented 2026-09-21

**Context.** `GlassCatalogMerge.winner` was last-write-wins by `updatedAt`, but the store that
applies incoming records (`HostCatalogStore.precedes`) made a tombstone beat a live record
whatever the dates. When the phone folded its duplicate Linux server records into one and the merged
record arrived at the Mac live and newer, a five-day-old tombstone for that id refused it,
silently, and the Linux server vanished from the Mac with every service folded into it.

**Decided.** One rule at both layers: the later statement about a record wins, deletion
included. A tombstone beats a live record only when its `deletedAt` is at or after the live
record's `updatedAt`. Ties keep the tombstone.

**Cost accepted.** A device that edits a host after another device deleted it revives it. That
was D19's "deleted here must not come back" case; the trade is that an edit is a deliberate act
too, and losing a whole machine to an unrelated old tombstone was the worse failure and the one
that actually happened. Pre-launch, one user, three devices.

## D35 — Previews render Markdown with swift-markdown and Mermaid from a bundled script — Implemented 2026-09-23

**Context.** The editor is to show images and media as themselves and offer a VS Code–style
Preview for Markdown, HTML, SVG and CSV, with Mermaid diagrams inside Markdown
([plan](tasks/2026-09/2026-09-23_viewers-and-preview.md)).

**Proposal.** swift-markdown (Apple, Apache-2.0, GFM via cmark-gfm), pinned exactly. Mermaid's
`mermaid.min.js` (MIT) vendored into `GlassEditor`'s resources at a pinned version. A preview page
runs no script but the bundled Mermaid, loads nothing from the network, and receives every
resource through one app-answered URL scheme that reads through the document's own file access;
HTML files preview with scripts off.

**Status.** Implemented 2026-09-23 — approved by the user with one condition, which is now part
of the decision: Mermaid must never be stale. The scheme's build pre-action (`Tools/Mermaid/update-mermaid.sh`)
checks the npm registry on every build, and a moved version is downloaded, sha512-verified against
the registry's integrity field, and built in.

## D36 — A TextKit 1 backend for the Mac editor — Implemented 2026-09-23

**Context.** [Text engine research](tasks/2026-09/2026-09-23_text-engine-research.md) — the state of the art in native Mac editors — on the
user's 14.6 MB one-line SVG, bare TextKit 1 with non-contiguous layout opens in 0.3 s and scrolls
at well under a frame; TextKit 2 takes ~1 s and 30 ms a frame offscreen, and in our real editor the
file opens in ~5 s and does not scroll. The engine's D-001 kept a `GlassEditorEngine` protocol so a
backend could be swapped.

**Proposal.** A second AppKit backend on TextKit 1 (`NSLayoutManager`, `allowsNonContiguousLayout`),
behind the same protocol, used on the Mac. Colours as temporary attributes; the gutter against
layout-manager line fragments; the TextKit 2 tripwire becomes per-backend. iPhone keeps TextKit 2
and Preview for huge-line files; iPad and Vision Pro to be measured before choosing.

Independent of the engine, the fast editors' other two practices apply to either: parse off the main
thread and apply by range; colour without touching the text storage.

**Status.** Approved 2026-09-23 (the user asked to test it and build the new editor). **Implemented** the same
day at `9b4da5f`: `GlassTextView.makeTextKit1()`, `GlassEditorAppKitEngine(textSystem: .textKit1)` the
Mac default, the gutter numbered from layout-manager line fragments, the tests run on both systems.
Seen by the user in 0.4.217, who was pleased with the new renderer — the 14.6 MB SVG opens in 1.9 s (was
~5 s) and scrolls. Not yet done: colours are still text-storage attributes, highlighting is still on
the main thread, and re-wrapping that file after a resize takes ~1.7 s.

## D37 — File ▸ Save is the shell's, and the focused window says what it saves — Implemented 2026-09-25

**Context.** ⌘S was the database's "Save SQL Document…", disabled unless a database workspace was
focused; the editor's Save was on ⌥⌘S. In an editor, ⌘S beeped ([task note](tasks/2026-09/2026-09-25_editor-save-and-new-window.md)).

**Decision.** ⌘N's pattern for ⌘S: the shell owns one Save item (`GlassShellFileCommands`), and each
window publishes `\.glassSaveItem` — a title and an action — or nothing. The editor says "Save…" for
a never-saved document and "Save" otherwise; the database says "Save SQL Document…". Off the Mac,
where the shell's item does not exist, the database keeps its own ⌘S item. Guarded by
`MenuBarPlacementTests` (one menu owner for ⌘S; both publishers present).

**Placement, as observed.** The item sits in the shell's New group. From the shell's commands
(attached to the library scene) both `replacing: .saveItem` and `after: .saveItem` drew nothing in the
running app; the New group is the placement known to reach the menu bar. If Save is wanted beside
Close, that is the open question: attach an item from a scene whose `.saveItem` does draw.

**Status.** Implemented 2026-09-25 in answer to the user's report that ⌘S should show a save
interface rather than beep; 0.4.220 onward, menu bar read back.

## D38 — Distribution and automatic updates: Developer ID + Sparkle on the Mac, TestFlight then the App Store elsewhere — Approved 2026-09-25

**Context.** No build has been distributed yet; every install so far is from Xcode, which never
updates itself. The user required that automatic updates be accounted for.

**Decision.**
- **macOS: Developer ID, notarized, updated by Sparkle** — the Mac App Store is not open to this app.
  It requires App Sandbox (App Store Review Guidelines 2.4.5(i)), `Platforms/macOS/macOS.entitlements`
  has none, and sandboxing is not a formality here: a local shell started inside the sandbox inherits
  it and cannot reach the user's files or tools, and `~/.ssh`, `ssh-agent` and open-anything editing
  would all need workarounds. The user confirmed the Mac build cannot go through the App Store because it is not sandboxed.
  Reuse the release path of AudioPaper, the author's other open-source Mac app (its
  `scripts/release.sh` and `appcast.py`): archive,
  export with Developer ID and hardened runtime, notarize, staple, a Sparkle zip signed with the EdDSA
  key, the feed entry, then the DMG. The feed is `https://glasspowertools.com/appcast.xml`; the update
  zip is on the site or on GitHub Releases, depending on whether the repository is public.
- **iOS, iPadOS, visionOS: TestFlight first, then the App Store.** Those platforms do not let an app
  update itself; TestFlight's automatic updates and the App Store's are the mechanism. TestFlight also
  installs over the air, which removes the Xcode-pairing dependency seen on 2026-09-25.

**Required before the first Mac release** (not yet done):
1. Sparkle linked for **macOS only** — one multiplatform target, so a platform-filtered dependency.
2. A **Developer ID provisioning profile** carrying the CloudKit container `iCloud.com.glasspowertools`,
   the App Group `group.sh.glas.shared` and the Keychain group; sync verified on a Developer ID build
   before it ships.
3. `com.apple.developer.aps-environment` **`production`** for release builds (it is `development`), or
   CloudKit's change notifications do not reach released copies.
4. The feed served uncached (D39).

**Status.** Approved 2026-09-25. **Partly implemented 2026-09-27:** Sparkle 2.10.0 linked on macOS
only (a platform-conditioned product on `GlassShell`); `GlassShellUpdates` starts only when the build
names `SUFeedURL` and `SUPublicEDKey` (from `Config/Identity.xcconfig`), never in a UI-test run;
Check for Updates… in the app menu and in Settings ▸ About; the push environment is a build setting
the release build sets to `production`; `Tools/Release/release-mac.sh` and `appcast.py` (syntax- and
feed-checked, never run: they need the Developer ID certificate and notarization credentials).
**Still the owner's:** generate the EdDSA key and set its public half; the Developer ID provisioning
profile with the CloudKit container, App Group and Keychain group; sync verified on a Developer ID
build; the feed served uncached.

## D39 — Documentation and glasspowertools.com — Approved 2026-09-25

**Decision.** Documentation is built in the order the user set: the vision; then an audit of every
surface against the code, fixing discrepancies, whose output is the help; then a landing page, one
product page per capability and a help centre. Plan and models:
[documentation and site plan](tasks/2026-09/2026-09-25_documentation-and-site-plan.md).
- **Audience first:** developers who want a first-class Vision Pro experience; every surface is
  written Vision Pro first, other platforms' differences marked, each claim at its verified level.
- **Help centre:** Anomalous's help system (anomalous.bot/help — one registry for
  sidebar, ⌘K search, meta, JSON-LD, sitemap, `llms.txt`), rebuilt as static files: a registry and
  Markdown pages in this repo, generated by an extension of AudioPaper's `build_site.py`.
- **Copy:** Bedrock for the landing and product pages (`bedrock-brand-voice` writes, `ask-bedrock`
  judges); help pages plain and exact; nothing claimed beyond what the audit verified.
- **Hosting:** **glasspowertools.com** (owned by the user), a static site the build produces as a
  folder of files, served from the user's own infrastructure. **How and where it is hosted is not
  recorded in this repository** — machine names, addresses and server layout are private; the
  deployment runbook lives in the user's private infrastructure notes. Deployment scripts are run by
  the user.
- **The update feed must be served uncached** (`appcast.xml`, and the site's HTML and JSON), so an
  update is never missed; a requirement on the hosting, tracked privately.

**Status.** Approved by the user 2026-09-25 (accepting this plan in conversation and asking for all of
these decisions to be documented). Nothing built.

## D40 — Leave spatial design to Apple: the visionOS unwind — Approved 2026-09-28
**Owner:** "I would leave it Apple to define what spatial is best." Almost every visionOS surface
that felt wrong was our own addition (nested gaze highlights, spatial padding, custom frames).
**Decision:** full unwind, surface by surface — system windows, text styles, control sizes and
toolbar ornaments; keep only terminal/desktop transparency (incl. the desktop's colour key) and the
desktop control bar. Order: library window, then database, editor, terminal, desktop, each judged
on the headset before the next. Lists are already done (`glassSpatialList`/`glassSpatialListRow`).

## D41 — Library overview and service availability — Approved 2026-09-28
**Overview:** the library's empty detail shows counts (machines, services by kind, per machine,
favourites/collections) and a connection timeline, from connection history kept **on this device
only** (when, which service; nothing else). **Availability dots:** a setting, **off by default**
(Settings ▸ General ▸ "Show service availability"); when on, green/orange/red per service from a TCP
connect to its port — never a login — only while the library is visible, at most once a minute,
results kept on this device. Every service kind, not only databases (SQL Studio Pro's idea, widened).

## D42 — Richer clipboard, in order — Approved 2026-09-28
1) RDP text, rich text and images, both ways; 2) RDP files both ways, streamed with progress and
cancel; 3) Files (SFTP) ⌘C/⌘V and drag with Finder; 4) VNC Extended Clipboard (TigerVNC-class
servers). All behind the existing per-desktop clipboard switch; transfers need a user action.
Proven on the Docker xrdp/TigerVNC rigs; Windows needs the Windows 11 VM.
