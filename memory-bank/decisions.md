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

A new `GlassPowerTools` directory beside the three source repositories, rather than renaming one of them. Building on
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

**Amended 2026-10-13 (the owner's question on the unfolded iPhone Duo: "How do I get back to the main
all connections from the active connections window?"):** the library had also followed glassdb in
removing the toggle on iPhone and iPad. A screen that shows the list and its detail with the sidebar
folded away then had no way back but an edge swipe. The library leaves UIKit's own toggle alone there
too — still the system's item, never a placed one; UIKit shows it only while the sidebar can be
hidden. (The database's own `databaseSidebarChrome()` still removes it off the Mac; look at it the
same way when a narrow two-column layout shows the problem there.)

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
**Observed 2026-10-18:** the installed 0.4.476 carries Sparkle.framework and `SUFeedURL` but no
`SUPublicEDKey`, so the updater never starts and its menu item and settings are hidden. A Developer ID
Application certificate for the team is now in the login Keychain. There is no Sparkle key under the
account the release script signs with (`GlassPowerTools`); the only one is under Sparkle's default
account, made 2026-06-06 for another app. No Developer ID provisioning profile is on disk (the script's
automatic signing with `-allowProvisioningUpdates` may make one; unproven). **A step this list lacked:**
a Developer ID build uses CloudKit's production environment, so the schema must be deployed to
production in CloudKit Console first, and the production database starts empty. Builds installed
from Xcode use development, so the two kinds of build do not see each other's data.
Notarization now uses a notarytool profile saved in the Keychain (`glasspowertools-notary`, or
`GPT_NOTARY_PROFILE`), as the owner's other projects do, checked before the archive; the team comes from
`Config/Identity.xcconfig`. It no longer takes an Apple ID and password from the environment.
**Findings, 2026-10-18.** Every entitlement the Mac app uses is available to Developer ID: App Groups,
iCloud CloudKit and key-value storage, Keychain sharing and push (Apple, "Supported capabilities
(macOS)", https://developer.apple.com/help/account/reference/supported-capabilities-macos). Nothing can
be reused from the source apps: a profile belongs to one bundle identifier, glassDT shipped no embedded
profile, and AudioPaper uses no iCloud. Xcode's automatic signing makes the Developer ID profiles at
export. **The owner's library can move to production, and he wants it to:** the Mac and iOS team
profiles allow `com.apple.developer.icloud-container-environment` Production as well as Development.
Each sync reads the whole zone, and `GlassCatalogMerge.reconcile` uploads a host the account lacks, so
the first device to sync against the empty production zone uploads its library, tombstones included,
and the others converge by record ID. The zone holds one record type, `Host` (fields `profile`, an
encoded `HostProfile`, and `updatedAt`), which must be deployed to production in CloudKit Console
first. Key-value storage and iCloud Keychain have no environments, so settings, favorites and
credentials are unaffected. The update downloads go on GitHub Releases (the owner, 2026-10-18), which
needs the repository to exist and be public; on 2026-10-18 it did not exist.
**Dry run, 2026-10-18** (`release-mac.sh --dry-run 0.4.479 479`, after the owner signed in to Xcode):
archived arm64 only, exported with Developer ID, every check passed. Xcode made the Developer ID
profiles ("Mac Team Direct Provisioning Profile", until 2044) for the app and the Files extension, the
two bundles that need one. The app's profile grants every entitlement it claims: Production iCloud,
production push, the container, key-value store, `group.sh.glas.shared` and the Keychain group. The
Files extension claims only a team-prefixed App Group, which needs no grant on a Mac. Still to do: a
notarized copy actually launching. The export was not run, because it would have shared the owner's data
with his running copy.

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
**Narrowed by the owner, 2026-09-28 (supersedes the order above):** the terminal, database, Files,
editor and desktop transparency all stay. Change only list formats and anything that does not serve
the "Glass" (window transparency). Priority: visionOS, Apple-native HIG patterns, familiar from Mail
and Safari so nobody has to learn it. The database window is right as it is except the tool bar above
the results (wrapping, mixed button styles); touch nothing else there.

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

## D43 — Schema diagram, in 3D on Vision Pro — Approved 2026-09-30
**Owner:** "2 please. In 3D, in space on VP if possible. … this was a major miss and is an expected
feature." The first exception to the 2026-09-26 feature freeze. **Decision:** a native, interactive
diagram of a database's tables, columns and foreign keys, read live from the connection: a 2D canvas
on Mac, iPad and iPhone; a RealityKit volume on Vision Pro. Plan and evidence:
`tasks/2026-09/2026-09-30_schema-diagram.md`.

## D44 — Terminals that outlive the device: tmux, and Active across devices — Approved 2026-10-01
**Owner:** "tmux support when connecting to hosts that support it" … "we have the Active tab. We could
use that to move between machines. There are instances where I want two to 5 terminals on a given
host. Maybe a few DB connections, too." … "Let's knock out that amazing tmux vision!" **Decision:**
a per-server setting keeps each terminal in its own tmux session (`glass-1`, `glass-2`, …), so it
survives a suspended app or a dropped network and can be picked up on another device. Active lists,
under each machine, the tmux sessions running on the host that this device is not showing — detached,
or attached elsewhere — to attach, take over or end. Stage 2 (later, not approved yet): a synced
"open the same set here" for a host's terminals and databases. Plan and evidence:
`tasks/2026-10/2026-10-01_tmux-sessions.md`.

## D45 — A database reached through another machine — Approved 2026-10-05
**Owner:** "I have to ssh into a machine, then connect to a DB server on a private IP address from
that machine. I can't see a way to do that with our current settings." Offered two shapes; the
owner chose **its own machine**: the database server is a host in the library at its private
address, and its database service's **Connect** picker chooses "Through <machine>" — another
machine's Terminal service carries the tunnel to the database's own address. Stored as
`DatabaseConnectionConfig.tunnelServiceID` (a service id, which survives the library merging
duplicate machines). The rejected shape: a "database address as seen from this machine" field on
the jump machine's own service. Evidence: `tasks/2026-10/2026-10-05_db-through-another-machine.md`.

## D46 — Hand gestures for remote desktops on Vision Pro — Proposed 2026-10-06
**Owner:** "palm up click-drag = scrollwheel" and "pinch hold > [n secs] should be right click maybe".
**Proposed:** palm-toward-you pinch-drag scrolls; pinch-and-hold still right-clicks; quick pinch clicks,
pinch-and-move drags. Measured palm direction separates cleanly (task note). The pose needs a SwiftUI
spatial gesture that takes all input and has no mouse buttons, so the owner's idea — behave by device —
becomes a hands mode and a trackpad mode switched on what is in use. Not approved or built.

## D47 — Local terminals kept in tmux — Approved 2026-10-07
**Owner:** running an agent inside the app's local terminal, an install ended it. Offered a watcher
installer, local tmux, or Terminal.app; the owner: "local tmux is the way, right?" and "Let's build
this … Keep local terminals running with tmux. We use it for SSH already." **Decision:** a Mac setting
(off by default, offered only when tmux is found) runs each local pane in its own `glass-N` session on
the Mac's tmux server, saved with the pane so a relaunched tab reattaches. Closing a pane, tab or
window ends its session; quitting the app keeps them all. Unlike D44's SSH terminals, local sessions
are not listed in Active — closing ends them, so none are left behind. **Amended the same day:** the
owner closed a tab and could not resume it, so closing now detaches as D44's terminals do, and Active
lists the Mac's sessions under This Mac (open, take over, end). The SSH tmux commands also look
in Homebrew's folders, so another device can reach these sessions over SSH. Evidence:
`tasks/2026-10/2026-10-07_terminal-tabs-and-local-tmux.md`.

## D48 — SwiftTerm 1.20, and a weekly check of newer dependency releases — Approved 2026-10-07
**Owner:** Claude Code drew roughly in our terminal. The cause: it asks XTVERSION before it asks
about synchronized output, and SwiftTerm 1.18 did not answer (`tasks/2026-10/2026-10-07_terminal-tabs-and-local-tmux.md`).
1.19 and 1.20 answer it, but 1.19 had been held back for its build-tool plugin. Asked "Why are we
pinning like this? Can we test … when there's a new version?", the owner chose: take **SwiftTerm
1.20** with its plugin (it runs `git` on SwiftTerm's checkout to stamp a version; no network), and
build an **update check, on demand and weekly**, that reports newer releases and tests the app
against them without moving a pin. Pins stay; raising one stays a person's decision. Also approved:
local terminals get the Mac's environment (as Terminal.app passes it) with `TERM_PROGRAM=GlassPowerTools`.
"This will need testing on the other platforms" — device checks on iPhone and Vision Pro are part of it.
visionOS note, 2026-10-07: the "one Connections window on the headset" choice (2026-09-29) is now kept
by a value-keyed `WindowGroup` rather than a `Window` scene, which made every launch fatal once
visionOS held two saved sessions for it (task note of the same date).

## D49 — Favourites sync across devices — Approved 2026-10-08
**Owner:** "Favorites aren't synced" … "scroll and favorites too please". They were per-device by
design (glas.sh's preferences). **Decision:** each host's favourite travels through the shell's iCloud
key-value sync (`GlassFavoritesPayload`, key `shell-favorites-envelope-v1`), as the editor's project
list does: the newest change per host wins, an unfavourite travels too, favourites set before sync
count as the oldest change so each device's are kept together, and the device's own host (one fixed
id on every device) is never synced. Connection history and last-used service stay per device (D41).

## D50 — Reaching This Mac's terminals from other devices — Proposed 2026-10-08
**Owner:** "Is there any chance that this local terminal will be available via [the Mac]/ssh from
vision pro?" and, seeing Active: "This Mac isn't available on Vision Pro." This Mac is a device-only
host (`GlassLocalHost`); other devices know the same machine only as its synced record, which has no
Terminal service. **Proposed, not built:** a Mac setting that offers this Mac's terminals to the
owner's other devices — it would need Remote Login (the owner turns it on), an SSH key the app holds
and syncs, that key's public half added to the owner's `~/.ssh/authorized_keys`, the Mac's host key
pinned for the other devices, and a Terminal service with tmux on added to the Mac's synced record.
Writing `authorized_keys` is the owner's call. Also wanted with it: the Mac recognising its synced
record as itself, so Active does not list each session twice.

## D51 — Workgroups sync across devices — Approved 2026-10-08
**Owner:** "work on getting workgroups to sync on icloud". They were saved per device. **Decision:**
each workgroup travels through the shell's iCloud key-value sync under the terminal's existing iCloud
switch (key `terminal-workgroups-envelope-v1`), as its own JSON (the module's main-actor coding cannot
cross into the off-main payload). Saving stamps `modifiedAt`; the newest change per workgroup wins; a
deletion leaves a dated tombstone (kept 90 days) so it travels; on a tie the workgroup outlives its
deletion. When it was last opened and its per-device SSH substitutions stay on the device, so opening
one sends nothing.


## D52 — Workgroups live in Connections; no separate window — Implemented 2026-10-08
**Owner:** the app crashed while resizing the separate Workgroups window. "It's weird that we have a
separate window for that anyway, isn't it? It's inline in the connections window?" The window was
glas.sh's, kept through the merge. **Decision:** removed on macOS and visionOS. Window ▸ Workgroups
and Library ▸ Workgroups bring the Connections window forward on Workgroups, opening one if none is
open (`fde5940`). The library's column autosave went with it (rule 62). Column widths now come from
SwiftUI's own per-window autosave.

## D53 — Workgroups as tmux sessions through control mode — Proposed 2026-10-08
**Owner:** "Is there a way to provide a nice Apple polished interface to tmux sessions on a given
host?" and "can we use [tmux windows] to attach tmux sessions to our workgroup tabs?"
**Proposed, not approved:** the app becomes a tmux control-mode client (`tmux -CC`), as iTerm2 is.
A workgroup on one host is one tmux session, its tabs that session's windows, and its splits the
windows' panes, all drawn natively, with native scrollback, find and selection. The layout lives on
the host, so a crash or another device brings it back as it was. Limit: a session lives on one
host, so a workgroup spanning hosts is one session per host. **Before deciding:** a spike against
the scratch VM. **Near term instead:** W4b (each tab remembers its own session) and a sessions
browser per host in Active (W6).

## D54 — Terminal windows are reopened by the app, not by macOS — Implemented 2026-10-09
**Owner:** "we need to remember window positions. Apple has an API for this, right?" macOS window restoration was
turned on for the app (`56f9ce5`): it reopened the terminal windows without their value, as empty "New Terminal"
windows, and the app's own reopen list stood aside; the owner: "that restart was f*d". **Decision:** reverted
(`5722124`); the terminal window scene declines restoration, and the app's own records, which know each window's
tabs, reopen them. Positions are to be kept in those records too (W12), and the list read by whichever window
appears first and kept current while running, so a crash reopens the same windows.

## D55 — Vision Pro, iPad and iPhone reopen their tab groups from the app's own list — Implemented 2026-10-09
**Owner:** "We should also work on restoring tab groups on relaunch with vision OS and iPad OS." **Decision:** as D54
for the Mac: the terminal scene keeps declining system restoration, and the app keeps its own list
(`terminalWorkgroupsToReopen`, App Group defaults), current while it runs so a crash restores too, taken once per launch
after the library has loaded. A workgroup comes back if any terminal in it is in tmux; plain shells in it start again
on the same machine; a window closed by hand stays closed; saved Workgroups are never written. Vision Pro reopens a
window per workgroup and connects every terminal; iPad and iPhone bring all back and connect only the one on screen.
Built in W15 (`6394fc6`); not yet tried on a device.

## D56 — Synchronized settings are combined with the built-in theme under one identifier — Implemented 2026-10-10
**Evidence:** "Failed to synchronize portable settings … Code=3" (`invalidPayload`) at every launch; from 2026-09-27
(bf178ce renamed the built-in theme) no current build could send terminal settings: the KVS store is shared with
glas.sh (`GPT_KVSTORE_SUFFIX = sh.glas.app`), older writers use the old built-in identifier (accepted by `validate()`),
and combining before a send matched themes by identifier only, so the result held two built-in themes. **Decision:**
before combining, both sides rename the built-in theme to the current identifier and keep the more recently changed
one; selection follows. No migration, nothing deleted; an older build reading the new copy rejects it and stops syncing
rather than overwriting. Built in W18 (`6293e69`). After-effect: the first launch with the fix applies iCloud's
frozen copy of terminal preferences once more; changes made since 09-27 may need making again, then they sync.

## D57 — A terminal window owns its look — Implemented 2026-10-10
**Owner:** "a way to give a color/tint to the tab group… It should inherit the settings of the first one in the order
yes?" Asked how; chose **"window owns it"**. **Decision:** one look (`TerminalSessionOverride` fields: tint, opacity,
blur, frost, interactive glass) per terminal window/tab group, resolved field by field over the global settings
(`TerminalLook.resolved`). Stored on the Mac window record, on `TerminalWorkgroup` and W15's reopen records, and in
`LayoutPreset` (synced, decoded leniently, schema unchanged so earlier builds still read it). Set from any tab's
Settings ▸ Overrides; new and moved-in tabs take it; Move Tab to New Window and Duplicate carry it; ⌘N starts plain.
Per-session overrides removed (keyed by ids no later session has). Tint drawn at a fixed 12% (it was 12% × opacity,
invisible at the default 0%). Built in W20 (`d274577`). Limit: a build before W20 that re-saves a synced workgroup
drops its look.

## D58 — Any setting can be overridden per window, through one shared overlay — Implemented (terminal) 2026-10-10
**Owner:** "the original idea was that anything in the system settings could be overridden per window"; asked the
scope, chose **every kind of window now**. **Decision:** GlassLayers owns the mechanism (W22, `eac2ee7`):
`GlassWindowSetting` declares one overridable setting under a stable key (`<capability>.<name>`, `appearance.*`
reserved), `GlassWindowOverrides` is a window's overlay (only what it sets; lenient decoding; unknown keys kept; ≤64
entries), carried in the environment from the window root; `GlassLayeredWindow`/`Panel` draw a window's own Appearance
from it; `GlassWindowSettingRow` shows "Same as …"/"This window only" with Reset. Terminal windows cover theme, font,
cursor, bell, scrollback, tint, interactive glass and Appearance; W20's look (D57) is part of it and still written in
W20's format for earlier builds. Initial size and connection/security/device settings stay global. Editor, database and
desktop windows adopt it in W23–W25. Caveat: visionOS layers paint no frost since `7478a39`, so per-window
Frost/Material there change nothing.

## D59 — A Vision Pro terminal window draws Apple's glass itself, as strong as its Blur — Implemented 2026-10-10
**Owner:** "We've lost complete transparency... 100% transparent glass (the whole point of the app)"; his diagnosis:
"we're assigning transparency to the terminal (the black part), not the Apple provided window". `cfd5094` had dropped
`.plain` from the terminal scene to get Apple's window back as the corner the canvas nests in, and the system keeps that
window's glass behind a focused window whatever the app draws. Proposed returning to `.plain` and drawing the glass
ourselves; he said "Yeah". **Decision:** the terminal scene is `.plain` again; `VisionTerminalWorkgroupView` draws
`VisionTerminalWindowGlass` (since D60 the shared `GlassSpatialWindowGlass`) once behind the whole window: `glassBackgroundEffect` in Apple's 46-pt continuous corner,
faded by `TerminalLook.windowGlass` = the resolved Blur (This Window's, else Appearance's Frost; Reduce Transparency
keeps it at full). 0 draws no glass, so the window is completely clear; the default Frost 100% looks as Apple's window
did. Opacity still paints only the canvas, and the nested corners (`cfd5094`, `0788d12`) are unchanged. The window-only
canvas frost (`TerminalLook.windowBlur`, a material fill over the whole window) is gone. Checked in the visionOS
simulator: `.opacity` fades the glass smoothly (Blur 0, 50%, 100%). Open: Interactive Glass and Material no longer
change a headset terminal (Settings UX round).

## D60 — Every Vision Pro window follows the terminal's glass where visionOS allows — Implemented 2026-10-10
**Owner:** "rebuild all window appearances to match the new terminal. So screen sharing, database, etc." **Decision
(W28):** the terminal's model is shared in GlassLayers: `GlassSpatialWindowGlass` (Apple's glass in the 46-pt
continuous corner, faded to a strength, nothing at 0), `GlassWindowGlass.strength` (Appearance's Glass with the
window's own over it; Reduce Transparency → 1) and `.glassSpatialCanvas(opacity:)` (Opacity paints the content area 34 pt
in, in the ≈23.75 continuous concentric corner; `GlassWindowShape.spatialNestedCanvas*`). The remote desktop matches the
terminal fully: plain, its own glass at the desktop's Glass, the remote screen as the nested canvas. **Observed limit:**
on visionOS 27 a NavigationSplitView/NavigationStack always draws its own system glass (UIKit columns'
`preferredContainerBackgroundStyle = .automatic`); no public API removes it and rule 62 forbids introspection. So
Connections, the editor, Files and the database keep system navigation (D40), with Opacity painting only their content
column in the nested corner and no extra glass. **Proposed, owner to choose:** the database without a split view on
visionOS (`DatabaseSpatialLayout.ownGlass`, off), fully clear at Glass 0, at the cost of the system sidebar's collapse,
adaptive column widths and split-view rotor landmarks.

## D61 — A remote display per window on one connection, and Quality the person can set — Implemented 2026-10-10 (unverified on a Mac)
**Owner** (Vision Pro on a mobile link, sharing a two-display Mac): "no scaling or bandwidth streaming control / quality
setting ... I'd like two screens, independently controllable like a real desktop setup." **Decision (W30):** one
`DesktopSessionModel` per connection, one `DesktopViewport` per window (display, presentation, its own settings, pointer
mode, on-screen); display windows are `WindowGroup(id: "desktop-display", for: DesktopDisplayWindowValue)` joining the live
session; input maps through each window's display region; VNC update requests cover only on-screen displays (bounding
rectangle; nothing on screen → a 1-px keep-alive every 2 s; CopyRect withheld while region-limited). Quality per
connection: Best (32 bpp lossless), Balanced (JPEG 8, today's), Data Saver (RGB565, JPEG 5, ≤15 updates/s), Lowest (8-bit
or 16-bit for Tight servers, JPEG 2, ≤8/s); Automatic measures every socket byte and steps at 16/4/0.75 Mbit/s with
hysteresis; colour changes wait for no outstanding request. Apple's server (RFB 003.889): ZRLE first, Apple's display
layout (encoding 1105, read defensively; a failure disables asking that host for the run), colour ≥16-bit. Desktop
Settings ▸ Connection shows the live figures. **Evidence:** TigerVNC fixture with two screens and a rate-limited proxy
(whole Best 87 Mbit/s → display 2 only Best 49 → whole Data Saver 5.6 → Lowest 1.3; Automatic settled Data Saver at 2
Mbit/s and Lowest at 0.6). **Unverified on a real Mac:** Apple's layout encoding, 16-bit colour, region requests — the
owner's checklist is in the task note.

## D62 — Opacity stays on every window; the navigation windows go to their own glass — Approved 2026-10-10
**Owner:** "The whole point of Glass Power Tools is Glass. Opacity is essential transparency is essential." Asked (after
W32 began removing the dark inset panel, and Opacity with it, from the database, Files and the editor): Opacity tints the
**whole window, edge to edge** (chosen); full transparency in Connections, the database, the editor and Files by
replacing Apple's split view on visionOS — **"Yes, all four"** (chosen), accepting the loss of the system's animated
sidebar collapse, column resizing and VoiceOver column landmarks. **Implemented so far:** whole-window Opacity behind
the columns (`GlassNavigationWindowOpacity.behindColumns`, 6f2cb23; Connections switched with it). **In progress:** W33,
one shared own-glass sidebar/content container for the four windows; supersedes D60's "split-view windows keep system
glass" and its prototype switch. Never remove or hide an Opacity or Glass control to make a look work.

## D63 — No Light/Dark mode on Vision Pro built on colorScheme — Proposed 2026-10-11
**Evidence (W35):** visionOS has no system Light/Dark for native apps (HIG Dark Mode and Materials; WWDC23 10076);
Compatible Apps Appearance applies to iPhone/iPad apps only. Forcing `.preferredColorScheme(.light)` on visionOS changes
UIKit label and text-field text to black while glass, ornaments and SwiftUI primary text stay unchanged — a mixed, less
legible state. **Proposal:** never derive a visionOS light look from colorScheme; if the owner wants light/dark on the
headset, make it a terminal (and editor) theme pair chosen per window or by Focus Mode, with Opacity/Glass unchanged
(D62). Hide or caption controls that do nothing on visionOS (terminal Canvas Material). Awaiting the owner.

**D61 update (2026-10-11, W36):** a Mac publishes its displays only when SetEncodings lists both AppleDisplayLayout
(1105) and DisplayInfo (1101) (remotex notes); the owner's probe showed none with 1105 alone. Now both are listed on the
Apple dialect, DisplayInfo is stepped over, the layout is parsed per the notes (length counts what follows it; 0x14-byte
header; 0x38-byte records with backing bounds in framebuffer pixels; mirror sets offer their first), the framebuffer is
resized from each layout, and SetServerScaling (0x08, f64) carries Data Saver 0.75 / Lowest 0.5 on a Mac, confirmed by
the next layout, pointer positions divided by the factor in force. The "don't ask this host again" refusal now needs
display metadata to have arrived. **Unverified on a real Mac;** our client negotiates RFB 3.8, not 3.889 with Apple's
record layer, which is what the notes measured.

**D61 verified (2026-10-11):** on the owner's two-display Mac (one 2x Retina, one 1x external), build 0.4.348 opens each
display in its own window on the Vision Pro — "Dual screen works!!!". The RFB 3.8 risk noted above did not bite.

## D64 — Retina at 1x, one connection per display over mixed densities, windows held to their display's shape — Implemented 2026-10-11 (Mac-side unverified)
**Owner:** "lock the dimensions to the actual screen ratio"; "can we have the Mac chill on the 2x retina resolution";
the pointer "insanely small on the main display ... isn't visible on the second". **Decision (W38):** the factor asked
of a Mac is Quality's × 1/density of the displays being fetched when they share one density (a 2x display alone at
0.5); mixed densities in one request get 1 (as Apple's viewer). With a window per display over mixed densities, each
display window opens its own connection to the endpoint (credential reused in memory, clipboard off), selects its
display with SetDisplay (0x0d) and asks for 1x; refused → not retried, the window falls back to the main connection.
"Retina Displays: Send at 1x (Recommended) / Native 2x" on the Connection page. Windows: "Keep Display Proportions"
(on by default) — visionOS via UIKit `requestGeometryUpdate(.Vision(size:resizingRestrictions: .uniform))` (SwiftUI
has none), Mac via `contentAspectRatio`; left free while Match Window Size resizes the remote. Pointer: a Mac's shape is
in points, drawn at density × server scale; CursorPos (1100) and the cursor cache (1104) advertised on Apple servers;
a hidden pointer returns on movement. **Needs the owner's probe run:** a second session, SetDisplay under RFB 3.8,
1100/1104 delivery, CursorPos coordinates, hand-resizing under `.uniform` on the headset.

## D65 — Automatic watches lateness; High Performance mode behind a switch — Implemented 2026-10-11 (HP unverified on a Mac)
**Owner** (hotspot drive): "bandwidth isn't the issue right?"; Data Saver "much more responsive"; agreed order: latency-aware
Automatic, availability probe, then High Performance "behind a switch, probe first". **Decisions:** (1) Automatic steps
down for updates ≥ 0.25 s and for TCP queueing (smoothed RTT over the 2-minute base, NWConnection transfer report) ≥ 200 ms
twice; a Mac's Automatic stops at Balanced (8b9f39d). (2) Availability: VNC probed every 10 min (each probe starts the
Mac's screensharingd + agent for 15 s), none while connected (e5912f5); Bonjour `_rfb._tcp` left to the owner (needs the
local-network permission). (3) **High Performance (Experimental)** as a per-desktop "Mac Screen Sharing" setting
(Standard / High Performance), taken at connect: a virtual display the window's points × density, HEVC 4:4:4 decoded by
VideoToolbox, AAC-ELD by AudioToolbox, SRTP/RTCP/RCTL as remotex measured (MIT, credited), one tile a frame (refresh
pictures after loss), Data Saver caps 8 Mbit/s, Lowest 3, else the Mac's 20–60 Mbit/s controller (6211b12…c2ed00c).
The probe cannot test it against the owner's own Mac (the stream needs the same UDP ports at both ends; a botched offer
once crashed WindowServer and logged the user out), so it is tested in the app on the headset with the owner present.
(4) A colour-depth change on a pushing Mac waits for a SetEncodings layout marker (1f2a01c): the hotspot log showed three
sessions killed by misread in-flight pictures, and the first one tripped W36 (why no scale was ever asked); W36 now
counts only the Mac closing the connection, for 10 minutes.

## D66 — This Mac's tmux server runs under launchd — Implemented 2026-10-12 (verified on the owner's Mac)
**Owner:** a Force Quit of a scratch app run from a tmux pane ended every local terminal; asked for "both" the cleanup and
the launchd server. **Cause, measured:** the app, the tmux server it starts and every pane share the app's resource
coalition; once that app has quit (every install), each answers for itself, and the Dock's Force Quit of an app run from a
pane ends the whole coalition (reproduced with a probe and two bystander panes). **Decision:** when no server answers, the
app has launchd run `tmux -u -D` from a job file in Application Support (no login item; starts when a local terminal needs
it; Interactive; pane environment less SSH_AUTH_SOCK/TMPDIR); a running server is left alone; launchd refusing leaves the
claim to start tmux as before (1e89b18, 0619569). Under it, the same probe's Force Quit ended the probe alone. Takes over
only when the current server ends; evidence in `tasks/2026-10/2026-10-12_tmux-under-launchd.md`. **Revised the same day
(9b62ebf):** launchd runs the app's own executable as host (`--tmux-host`), which starts tmux, because panes answer for
privacy permissions to whatever their chain started from (tmux, run directly, raised its own Desktop prompt); the host
turns tmux's `exit-empty` back on so the server and host end with the last session; Settings ▸ Terminal can end both.

## D67 — A terminal can be opened without tmux; tmux settings live in Settings ▸ Terminal — Implemented 2026-10-12
**Owner:** "What if I just want a quick naked local terminal?"; "build both. we need to allow remote sessions without
tmux too even if it's been selected as default." **Decision:** tmux stays the default where it is set (local: one
setting; SSH: per host), and any terminal can be opened plain: New Basic Terminal Tab (⌃⌘T), "+"'s menu, Connect Saved
Host's "Open without tmux", the palette, and Basic Terminal in a host's detail on every device. The choice is the
terminal's (`withoutTmux` on the session, the Mac pane and the workgroup) and survives relaunch and workgroups; such a
terminal is never offered tmux. The local toggle moved from Settings ▸ Connections to Settings ▸ Terminal ▸ tmux, beside
the background server's controls (130c879). Named **Basic** wherever it appears, and "+" offers New Terminal, New Basic Terminal and New
Terminal on ▸ every saved host, in the owner's words (737fa43).

## D68 — Widgets read a snapshot the app writes; taps are App Intents — Implemented 2026-10-12
**Owner:** "update the widget suite to make all of them useful for today's platform"; chose Machines and Active on
iPhone/iPad, Vision Pro and the Mac. **Decision:** the widgets read a snapshot written by the app into the App Group
container for them alone (`GlassWidgetData`, metadata only, schema-numbered), never the catalog's or the old `servers`
defaults; a tap is an App Intent run in the app (connect a service, show a machine, show Active), not a URL scheme,
keeping D4's removal of the old schemes. The extension is now built for the Mac as well (sandboxed, App Group).
Evidence: `tasks/2026-10/2026-10-12_widgets-machines-and-active.md` (cd6a2f1).

## D69 — Database and desktop tunnels keep their own SSH connections — Implemented 2026-10-13
**Status and provenance:** the agent's recommendation under the owner's standing "go with your recommendations",
reported to him the same day; it closes B-X5's leftover ("tunnels connect outside W21's pool").
**Decision:** a tunnel (`GlassTerminalCapability.openPortForward`) and an editor project's SFTP lister open their own
connection, not one from the terminals' pool (`SSHConnection.transportPool`, W21). The pool exists for the server's
limits, and a tunnel is not what they count: `MaxSessions` counts shell, login and subsystem sessions and permits
forwarding even at 0 (sshd_config(5)); a tunnel adds one sign-in when it opens. Sharing would put a desktop's frames
or a large result on the same TCP stream as every keystroke, which OpenSSH users report as interactive lag on a
multiplexed connection (openssh-unix-dev, 2009-10 and 2011-03), and would end the tunnel with the terminals'
connection. Wake checks still reach every connection (`SSHLiveTransports`). Evidence: cf5c64e; the reasons are at
`GlassTerminalPortForward`.

## D70 — A connection belongs to its controller, never to a view's task — Implemented 2026-10-13
**Status and provenance:** found by the owner twice in one day ("+" ▸ New Terminal on: "these always fail", then
"Didn't work"), fixed in 795ce5d and 9ce83d9.
**Decision:** work that must outlive a redraw — an SSH pane's connection first of all — runs in a task its
controller holds (`MacWorkspaceController.startSSHPaneIfNeeded`), and only the owner's own end (closing the pane,
the tab or the window) cancels it. A SwiftUI `.task` may *ask* for it but must not run it: SwiftUI cancels a view's
task whenever it removes the view, and it removes views it is about to draw again (a placeholder giving way to the
terminal; a new tab drawn twice as it settles). Each time the symptom was "Could not connect to …" with
`CancellationError` in the log, while the same machine opened another way worked. Test:
`anSSHPaneKeepsConnectingWhenTheViewThatAskedGoesAway` (fails with the view's await). Evidence:
`tasks/2026-10/2026-10-13_owner-testing-day.md`.

## D71 — The app has its own Light, Dark or System — Implemented 2026-10-13
**Status and provenance:** asked for by the owner, 2026-10-13, when the command palette drew in the Mac's appearance:
"TIL we don't allow the user to choose (in Appearance) Light, Dark, System. Then it should follow that."
**Decision:** Settings ▸ Appearance opens with Appearance: System, Light or Dark (`GlassAppAppearance`, key
`com.glasspowertools.appearance`), a choice for this device, not synced. On the Mac it is `NSApplication.appearance`,
so every window, sheet, menu and AppKit panel follows it; on iPhone and iPad, each `UIWindow`'s
`overrideUserInterfaceStyle`, windows opened later included. Applied before the first window shows
(`applicationWillFinishLaunching`; the iOS delegate's launch). **Not on Vision Pro** (D63). A terminal theme keeps its
own colours; its Automatic canvas follows the app's appearance. Evidence: `GlassAppAppearanceTests`.

## D72 — System integration on every platform: the whole plan — Approved 2026-10-13
**Approved by the owner:** "Do all of the things. Wonderful ideas!" — every phase of
`tasks/2026-10/2026-10-13_system-integration-plan.md`, the optional pieces included (Finder Quick Actions and the
Finder toolbar button), with the agent's recommendations on the open questions: `ssh://` links open in the app (Q1);
Services **and** Quick Actions (Q2) and a Finder Sync toolbar button (Q3), as "all of the things"; machine names in
system search only once switched on in Settings ▸ Privacy (Q4); `.command` files run in a new tab, `.sh` files open in
the editor (Q5); order 1 → 2 → 3 → 4, then a spike for 5 (Q6). Built phase by phase, each piece committed as it lands
(the standing "commit each piece as it lands"); nothing claimed working on a device until the owner has seen it.

## D73 — Favorites hold machines, services, projects, workgroups and folders — Implemented 2026-10-13
**Owner:** "Favorites should be machines OR services OR projects OR Workgroups OR SFTP (at the current folder
depth), yes?" Asked how the list should look, he chose **sections by kind** (Machines, Services, Projects,
Workgroups, Folders), over one list by last use or one ordered by hand.
**Decision:**
- Machines keep their mark on the host and D49's sync, unchanged, so older builds read them as before.
- The other four are `GlassFavorite`s, each kept with its sync clock in the shell's preferences and synced by D49's
  rule (newest change wins, an unstar travels, a tie keeps the star) under their own key,
  `shell-favorite-items-envelope-v1`, which older builds neither read nor write. An unstar is dropped after 90 days.
- A folder is a machine's Terminal service and an absolute path: the folder Files was showing when it was starred.
  It opens Files there; its menu also opens it as a project. A terminal in that folder is not built: it needs tmux's
  start directory carried into the remote startup command.
- The shell names and connects services; the composition root describes projects, workgroups and folders
  (`GlassShellModel.describeFavorite`). A favourite whose thing is gone, or has not reached the device yet, is not
  listed, and its star is kept for when it does.
- Stars: the machine row (as before), a service's menu in a machine's details, a project's and a saved workgroup's
  menu, and Files' toolbar (Add This Folder to Favorites). A favourite row opens on one click or tap, as a Finder
  sidebar favourite does.

## D74 — Vision Pro session windows shrink into an orb — Implemented 2026-10-15
**Owner:** "a persistent system level session/service icon that shrinks a window into a small preview. When activity
is enabled, the preview/orb should pulse." Asked to choose, he picked: a face that is a live picture of the session;
the pulse switched by the window's Auto-focus on activity; the control first in the bottom bar; every kind of session
window (terminal, desktop, database, editor). Then, on the headset: "redraw the tabs around the orb evenly distributed
with a preview in the orb on hover"; names "only … when focused"; the orb as "one more option for the view menu".
**Decision:**
- The window itself becomes the orb, as the Connections window does (W39): no second window. Its content stays laid
  out at its size, out of sight and out of reach; its ornaments go; visionOS is asked for the orb's size
  (`GlassWindowSizer`), and a pinch on the orb grows it back to the size it had.
- A glass sphere showing the session's picture once a second; the window's tabs as dots evenly on a ring. Looking
  at a dot shows that tab's picture in the orb and its name beside the dot; the name is part of the dot's hover group,
  so it stays while read. A pinch on a dot or name grows the window back on that tab.
- The app is never told where a person looks, so every look effect is a system hover effect in a shared
  `HoverEffectGroup`; pictures and names follow their group and never start one.
- Terminal windows with two or more terminals offer it as Orb in the view menu (with Tabs, Grid and Carousel);
  otherwise Shrink to Orb is first in the bottom bar.
- Vision Pro only. Evidence: `GlassSessionOrbUITests`; `tasks/2026-10/2026-10-14_all-windows-mac-layout-headset.md`.

## D75 — A terminal window that resizes, and one that scales — Implemented 2026-10-16
**Owner:** "we need both a resize capability and a scale capability. For example I may want a 120 x 40 terminal, but
with a much smaller window." Asked before building: Vision Pro, Mac and iPad windows ("vision mac and ipad
multi-window"); a setting and a bar button; the grid the terminal has when Scale is chosen ("If I've resized to 200 x
100, and choose to scale, keep that setting, do not override my terminal's current state"); the window held to the
grid's shape.
**Decision:** When Resized — Change Rows and Columns (default, as before) or Scale the Text — in Settings ▸ Terminal
(synced), This Window, and Scale Text in the window's bar. Under Scale the terminal is drawn at its own font and the
drawing scaled to fit; the font never changes, because SwiftTerm re-grids and soft-resets on every font set and its
cells come in whole points of height. The window is held to the grid's shape by the desktop's lock, moved to GlassShell
(`GlassWindowAspectLock`). ⌘+ / ⌘− / ⌘0 size the window under Scale (Mac, Vision Pro); iPad can't shape a window, so
there the text is centred, and only grows one (⌘+, through the scene's minimum size), drawing scaled text with Core
Graphics for the pixels shown (2026-10-16 evening). Evidence and limits:
`tasks/2026-10/2026-10-16_terminal-resize-and-scale.md`, "Built".

## D76 — A printed path's file previews over a Mac terminal — Implemented 2026-10-16
**Owner:** "resolve, say a path to a local image, and display that image in a popover over the terminal? or markdown,
or any of the file types supported by our Editor"; "build it with the menu item and space, local and remote"; "Show
previews: ( ) Never (•) Mouseover ( ) Mouseover + space … with mouseover as the default"; web addresses never on
mouseover, and Space on one asks to open it as a ⌘-click does; "Keep the hover open so the user can mouse into it";
"check the .output file type/mime types and allow edit"; "Use our file preview formats".
**Decision:** Quick Look first in a path's right-click menu; Show previews in Settings ▸ Terminal (Mac, synced, This
Window override). The file is resolved as Open in Editor resolves it, copied from a server over the pane's own SSH
connection (≤32 MB, removed on close), recognised from its bytes, and shown as the editor shows it: highlighted text in
the editor's view, the editor's rendered preview for Markdown/HTML/SVG/CSV, Quick Look for pictures, PDFs and media.
A bar offers Open in Editor and Show in Finder/Files. Mac only. Evidence: `MacTerminalContextMenuTests`,
`GlassEditorQuickPreviewTests`, `TerminalRemotePreviewTests`; `tasks/2026-10/2026-10-14_all-windows-mac-layout-headset.md`.

## D77 — A terminal window's sidebar adds to the window — Implemented 2026-10-16
**Owner:** "make the left (and eventually right) sidebars additive and not resize my terminal window to make room."
**Decision:** On the Mac, opening or closing a terminal window's sidebar grows or shrinks the window by its width toward
its side; the terminal keeps its size and place, so its rows and columns (or its scaled text) don't change. The app
moves the window itself (`GlassAdditiveSidebars`, GlassShell): AppKit's `.preferResizingSplitViewWithFixedSiblings`
does this only for a split view in a plain window — in a SwiftUI `WindowGroup` window it grew the window rightward and
never shrank it (two builds snapped on reopen for the owner). AppKit keeps the window's size; the window follows the
sidebar's net state, animated with it, and the terminal's column holds its width meanwhile. The window keeps its size
for the sidebar it opens with (its saved frame holds it), for the overview, in full screen, and where it can't be
that wide. The window's minimum belongs to the terminal's column. Only the Mac terminal window has a sidebar.
Evidence: `GlassAdditiveSidebarsTests`, `MacTerminalSidebarTests`, the window-scene probe;
`tasks/2026-10/2026-10-16_additive-sidebars.md`.
**2026-10-17, Implemented, then Superseded the same day — the toolbar holds still too.** Offered three ways (keep fixed, centre the title, leave
as Finder does); the owner: "keep the + and title fixed". An empty toolbar item before "+" holds the room the
window's and the sidebar's buttons take with the sidebar closed, as wide as the sidebar shows; with it open there is
that gap after the sidebar's button. A toolbar item is never under 36 pt, so "+" dips up to ~30 pt for two frames at
the start of opening and the end of closing. And the titlebar material no longer leaves the toolbar see-through for
the frame AppKit draws mid-opening.
**2026-10-17, Implemented — no line at the sidebar's edge.** The owner: "What is that gray line … That's what we need
to eliminate." AppKit's split divider and the chrome's hairline: in the terminal window both are gone
(`GlassTitlebarMaterialView.showsSidebarEdge` off); the database and desktop windows keep theirs, unasked.
**2026-10-17, Superseded — the held space closed.** Seen open on 0.4.469 ("there's a little new space … before the
+"), asked keep or close: "It moves anyway... let's close the space." Reverted (1534ece): "+" leads the content after
the sidebar again (D24's arrangement) and slides with it. The no-see-through fix and the edge stay.

## D78 — 3D models open everywhere files do — Implemented 2026-10-16
**Owner:** "we need 3D model support!" (Apple's iMac `.usdz` as the example). Asked first; all four recommendations
taken: everywhere files open; Apple's 3D Quick Look on Vision Pro; USDZ, USD and Reality; a model's link clicked in a
terminal opens in 3D here.
**Decision:** A file kind `model3D`, decided by the bytes (a zip whose first entry is a stored USD layer; `PXR-USDC`;
`#usda`) and Reality files by name. Shown with RealityKit on the Mac, iPhone and iPad (`RealityView`, the camera
aimed at the model, orbit controls; iPhone/iPad add AR Quick Look), and on Vision Pro in the window (`Model3D`) and
Apple's Quick Look volume (`PreviewApplication`). The editor's viewer, the Files browser through it, and the Mac's
hover preview. A model link, once confirmed, is downloaded (≤ 512 MB), checked by its bytes and shown. Evidence:
`tasks/2026-10/2026-10-16_3d-models.md`.


## D79 — What a person removes stays removed through the sync's merge — Implemented 2026-10-17
**Found** documenting sync (the owner: "make sure that the memory bank … and the site/help are current"); **fixed at
his word** ("yes, fix both"). The merge's second pass (2026-09-28, `GlassCatalogMerge.reconcile`: "no set-up service
disappears through a merge", written for a stale device's fold) revived every set-up service that no live record held
— including the ones a person removed. Deleting a set-up machine: the deleting device adopted the account's older live
copy instead of sending its tombstone (its store kept the tombstone, so the machine vanished there and nowhere else),
and a device that did receive a deletion sent the machine back alive. Remove Service: undone the same way.
**Decision:** what a person removes says so in the records, and a fold never does. `deleteHost` tombstones a record
with its services still on it, while a fold moves each service out first (`HostCatalogStore.move`) — so a service
any tombstone names went with its machine and is not revived. Remove Service leaves the record live (`unpair`) — so a
copy is revived only from a record that ended deleted, never past that record's own live, newer statement. The folds
of 2026-09-21 and 2026-09-28 revive as before (their tombstones name nothing).
**Cost accepted:** a service set up on another device *after* the machine was deleted still brings the machine back,
so that setup isn't lost (D34's trade: an edit is a deliberate act too). Old tombstones written by the catalog's
`remove(endpointID:)` (the database's outbox, unused since the merge) name nothing and read as folds.
**Evidence:** `GlassCatalogMergeTests` +5 and `D19SyncPublishTests` +2, each failing on the old merge (d61271a). Not
yet seen across two devices.

## D80 — Unsaved changes are asked about before anything ends them — Implemented 2026-10-17
**Found** documenting the editor; **fixed at the owner's word.** Only closing a document asked; closing an editor
window, quitting the Mac app, or ending the session in Active, All Windows or the Mac's overview discarded the
changes silently (`GlassEditorWorkspace.hasUnsavedChanges` had no caller).
**Decision:** on the Mac a window asks before it closes, document by document with the document's own question (Save,
Discard Changes, Cancel), then closes; a quit asks "Quit without saving?" with the terminals' loss in the same
question, and Cancel brings the changes forward. Where a window can be dismissed without asking (iPad, Vision Pro) its
workspace and project are kept while they hold changes, listed in Active, and reopened from there. A session says
what ending it would lose (`GlassOpenSession.unsavedChanges`), and every place that ends one asks first
(`glassAskingBeforeClosing`).
**Pattern:** `GlassWindowCloseGate` (GlassConnectionUI) stands in for SwiftUI's window delegate and forwards everything
else to it, as the terminal's window reader has since glas.sh; recorded against rule 62. The terminal's reader could
adopt it.
**Evidence:** `GlassWindowCloseGateTests`, `GlassEditorSessionLifetimeTests` +2, `GlassOpenSessionTests` +1,
`MacQuitWithUnsavedChangesTests`; each behaviour fails with its fix undone (eaa59a6). The Mac's walk through several
documents is the owner's to try.

## D81 — Your Library counts connections on all your devices — Implemented 2026-10-17
**Owner:** "I'd also like to display the cross device use in the All Connections (no connection selected) pane.
Right now it's per device. So maybe totals, then a way to choose which device?" Asked what may travel and how to show
it: "When the Active connections refreshes on iCloud maybe?" (with the iCloud sync the app already does); the layout
"All devices, then pick one", "but use the device name, not the product. I might have two vision pros". What travels
was not chosen; the smaller of the two offered was taken.
**Decision (amends D41):** each device's history stays on it; what travels is the device's name and its connections
counted per day, per machine and per kind of service, for the overview's 30 days — no times of day
(`GlassUsagePayload`, `Sources/GlassShell/GlassShellUsageSync.swift`). One key in iCloud's key-value store, an entry
per device keyed by its writer id, each device writing only its own (pushed at start, after each connection and
when renamed; merged newest-per-device). The overview adds every device up, and a menu (All Devices, then each
device by name) narrows the chart and Most used to one.
**Device names:** a Mac's computer name; on iPhone, iPad and Vision Pro the system gives an app only the kind of
device ("iPhone") without Apple's user-assigned-device-name entitlement (`UIDevice.name`, iOS 16 and later), so
Settings ▸ General ▸ This Device names the device here. Requesting the entitlement would make the starting names
right; it must be granted before it can be added, or signing breaks.
**Evidence:** `GlassUsageSyncTests` 6 (counting, merging, validation, an unknown kind, the sums, two devices over a
shared store; the sums and the two-device test fail with their change undone). iPad simulator capture.

## D82 — GPLv3, with a contributor agreement — Approved and implemented 2026-10-18
**Owner:** "My hesitation with MIT is, as I understand it, someone could clone this repo, rename it, and put it on
the App store for $99." Told that MIT allows exactly that and that GPLv3 is the usual deterrent, he asked whether he
could still ship the iPhone, iPad and Vision Pro apps on the App Store, then: "Switch to GPLv3 and add the
contributor agreement."
**Decision:** the project is licensed under the GNU GPL, **version 3 only** (`LICENSE`, the FSF's text verbatim). This
is the moment the license could change: nothing had been published (the GitHub repository did not exist), and
every source repository's history had one author, the owner. As the copyright holder he may also ship his own code
under other terms, such as the App Store's. Outside contributions would take that away, so `CLA.md` grants him a
licence to use each contribution under any terms; contributors keep their copyright. It is shaped like the Apache
ICLA 2.2, and the contributor agrees by putting one sentence in their pull request (`CONTRIBUTING.md`).
**What it does not change:** versions already published under MIT stay MIT (glas.sh, GlasSecretStore,
GlassConnectionKit and GlassEditorKit on GitHub), and third-party components keep their own licences. Those
licences are MIT, BSD and Apache 2.0, which are compatible with GPLv3; the MIT notice on RDPKit's audio player stays
with that code.
**Limits, said to the owner:** whether the App Store's terms are compatible with the GPL is disputed, so the licence
deters copies there more than it forbids them. Material generated by AI has limited copyright protection in the US,
so any licence protects this code less than it would code written by hand; the name and icon are protected by
trademark either way. The CLA has not been reviewed by a lawyer.
**Changed:** `LICENSE`, `CLA.md` (new), `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `THIRD-PARTY-NOTICES.md`,
`projectbrief.md`, and the site (footer, home page, structured data, `llms.txt`).

## D83 — tmux tabs keep their own history: tmux's control mode — Approved 2026-10-19
**Owner:** "I need to be able to drag select through a scroll … Now it starts a new selection in the current
buffer." Offered (A) the terminal keeps its own scrollback in tmux, or (B) a selection anchored in tmux's history:
"I like A. Seems simpler." Then, shown that A loses lines, and offered (1) repairing the history after bursts or
(2) tmux's control mode: "2."
**Why:** tmux takes the alternate screen and the mouse, so history lives in tmux, a scroll redraws in place, and a
selection made on the screen loses its text. Route A (built and tested 2026-10-19, uncommitted:
`TerminalTmuxScreen` declines tmux's alternate screen and mouse, turns `CSI n S` into line feeds, and loads
`capture-pane -e -J` history on attach) put scrolled lines in the terminal's history, but tmux does not send every
line: measured, 32 of 60 lines printed at once never reached the terminal over SSH, and at least 85 of 1,000 locally.
They exist only in tmux, so the terminal's history would have holes, and a selection across them would silently
leave lines out.
**Decision:** a terminal the app keeps in tmux attaches as a control-mode client (`tmux -C`/`-CC`), as iTerm2 does:
tmux hands over every byte the pane's program writes (`%output`), and the terminal draws it as it draws a plain
shell — complete history, the program's own alternate screen and mouse, and the session still survives
disconnects and other devices. One session, one window, one pane per tab. The history load on attach carries
over.
**Status:** Implemented and committed 2026-10-19 (task note); installed in 0.4.482 and, with the slow-reattach fix,
0.4.483 on the Mac and iPhone (the Vision Pro was unreachable). Route A's code was removed. Remote tabs use `-CC` on the SSH PTY; local panes use `-C` on pipes, because SwiftTerm's
PTY reader left tmux's last bytes waiting under load (measured; the task note has the runs).

## D84 — Terminal looks: backgrounds behind the text, glow later — Approved for an experiment 2026-10-20
**Owner:** "We look at these terminals all day long, so I was hoping for some inspired ideas to keep them
interesting": backgrounds that distort (pixelation, Matrix animation, blurs, images), an image dropped into a window
as the background of every terminal in it, and glowing text (vaporwave, green, amber, Matrix). Then: "document the
direction in the memory bank, then build an experiment yes … live in general after you test in the VM".

**Direction:**
- **Effects behind or around the text, never over it.**
  - Terminals are transparent, so a view behind them is ordinary SwiftUI on every platform: shaders, animation, blur,
    images.
  - Effects on the text's own pixels (true glow, scanlines, curvature) need a pixel pass in the renderer and come
    later.
- **Text first:** a readability guard keeps contrast.
- **Motion:**
  - It means something: it follows the terminal's activity.
  - It stops under Reduce Motion, Low Power Mode and in hidden windows.
- **The window keeps its glass.**
- **Our own code and assets only:** nothing third-party the App Store build can't carry (D82).

**Status:** Implemented as the experiment and installed in 0.4.484 (Exposé pictures and the brightness ceiling in
0.4.485); the owner: "Holy shit on a stick. This is AMAZING." Committed 2026-10-20 at his word. The task note is
`2026-10-20_terminal-looks.md`.

## D85 — SQL in a terminal opens in the query editor — Approved and implemented 2026-10-20
**Owner:** "we need a data detector for SQL that when engaged checks the server for a defined DB and will take the
SQL into a new editor with the proper database and table selected (if possible)". Then, on the proposal: "1.
right-click only 2. present a menu? 3. nah".

**Decision:**
- **Trigger:** right-click only, on the Mac. The statement under the pointer is taken whole and shown selected.
- **Destinations:** the terminal's machine's databases, plus those reached through its server (D45). One database
  is an item, several are a menu, none is a dimmed item saying so.
- **The editor:** the SQL opens unrun in a new query tab. The table it names is found on the server, its database
  made active and the table opened beside it.
- **Not done:** no reading of `psql` or `mysql` prompts; no hover detection.

**Status:** installed in 0.4.486. Not yet driven end to end against a real database. Task note
`2026-10-20_sql-detector.md`.

## D86 — This Mac knows its own library record — Approved 2026-10-20
**Owner:** "we don't recognize in the app that 'This Mac' and [his Mac's library record] are one in the same. How
can we set that?" Then, on the proposal: "yes, build it".

**Why:** D8 kept the device's own host apart from any record of the same machine reached over SSH, and D50 (2026-10-08)
already wanted the Mac to recognise its synced record as itself.

**Decision:** a device-local link from This Mac to a library machine.
- **Recognition:**
  - automatic when the machine's pinned SSH host key is this Mac's own;
  - offered once when its address is one of this Mac's;
  - set or cleared by hand in the machine's editor.
- **What the link does on this Mac:**
  - one row in the library;
  - its Terminal opens a local shell in tmux;
  - its databases count as This Mac's, including for SQL from a local terminal.
- **Next:** hide Screen Sharing to itself, and list Active's sessions once.
- **Other devices** keep it a remote machine; nothing about the link syncs.

**Status:** Implemented and committed 2026-10-20 at his word.
- 0.4.488 linked his Mac by itself, by its SSH host key.
- 0.4.489 lists Active's sessions once and hides Screen Sharing to itself.
- Not done: the terminal's own direct connect paths (Basic Terminal, the palette's "without tmux", workgroups).

Task note `2026-10-20_this-mac-link.md`.

## D87 — Your Library counts time in use — Approved 2026-10-20
**Owner:** "this show half truths! The number of connections is true... but I've had tmux sessions running for days
in a row now and that's not reflected in the data here." Asked what counts and what the chart opens on, he chose
**Activity** (a minute with input or output) and **Time in use**.

**Decision:**
- Each minute, every machine and kind of service whose open sessions had input or output counts one minute.
  - On the Mac, a terminal tab's local shells count too.
  - The minutes are kept on the device for 90 days, and sync per day alongside D81's counts.
- The overview opens on hours in use per day, with Most Used by time; Connections is a choice beside it.
- Connections are still counted only for a library Connect. Counting every path (restores, reconnects, the terminal's
  own) is deferred.

**Status:** Implemented 2026-10-20 (0.4.490); committed in 7f824f86. Task note `2026-10-20_time-in-use.md`.


## D88 — Orbs gather in a dock on Vision Pro — Approved 2026-10-25
**Owner:** "an invisible 'canvas' where (when enabled) a user's windows (when the orb mode is clicked) would move
automatically into a 'dock' that itself can be moved around. I'd resize the connections orb to match, and include it
too. We also need to add Editor, Database, and Desktop to the orb so it's more of a machine nav than just tabs for a
Terminal window." From his headset captures: four session orbs and the Connections orb, each a window of its own,
in a row at desk height.

**Platform:** visionOS opens a new window above, below, leading or trailing another one (`WindowPlacement.Position`,
visionOS 2+), and moves no window already open; the app has met that before (a resized window stays centred). So no
window can be carried into a dock: a window docks by closing into its orb, with its sessions kept, and comes back
when its orb is pinched.

**Asked, he chose:**
- **A terminal window is one orb**, its tabs on the ring as now, with its machine's Database, Desktop and Editor
  added. **Databases and desktops are one orb per machine.** **An editor** opened from a terminal (the folder button,
  Open in Editor) goes with that terminal window's orb; one opened from the machine in the library goes with the
  machine's orb.
- **Every service the machine has** is on the ring, dimmed while not open; a pinch opens it.
- **The Connections orb** is in the dock at the session orbs' size, keeping the app's icon and the Active count.
- **A window comes back above the dock.** The orbs keep their current size ("I like the current size of the orb").

**Decision:**
- A Vision Pro setting, off by default: Settings ▸ Appearance ▸ Orbs. Off, a window shrinks into its own orb where
  it is (D74). On, Shrink to Orb closes the window into the dock, a window of its own with no panel, moved by its bar.
- Pinching an orb in the dock opens its window again above the dock, at the size it had.

**Revised the same evening, on the headset (0.4.523):** "we should only show connected services. Every orb has ghost
services for the editor, mysql, and desktop for [one machine] … if I connect mysql on [it], then we should show [that
machine's] orb with a single mysql tab. The spacing is about 2x what it should be … maybe we need horizontal scroll?
Looks like we also lost the colors for the icons? and the icons in the middle seem to overlap?" So:
- A ring holds only what is open: no faint services, no Editor that opens a project.
- In the dock a machine's connected databases, desktops and library editors are one orb for that machine, docked or
  not, and terminal orbs no longer repeat them. In place, a terminal orb's ring adds its machine's connected services.
- Orbs in the dock sit half as far apart; a dot's name shows under its orb while the dot is looked at; past a width
  the dock scrolls sideways.
- Tabs in the dock draw their agents' marks in colour, as a window's own orb does.

**Revised again on the headset (0.4.525):** "Let's have the natural state remain the circle, only expand on
attention. and they need to remain on top!", then "the next thing is pinch/click and hold on a docked window to move its
order so muscle memory can land." So a dot in the dock is a circle until looked at, an open name lies over the orb,
and an orb held in the dock is carried along the row and takes the place of the one it is let go on; every orb keeps
its place on this device, so one that leaves the dock comes back where it stood.

**Revised 2026-10-26, his asks while testing 0.4.533.** "Let's have windows respawn in their last used state. In the
dock vs. open?" So a terminal window the launch reopens comes back open, in the dock, or standing as its orb, growing
back to the size it had; Connections comes back in the dock or as its orb. Connections waits for the reopened terminals
to connect, and stays open if it is showing anything then (a password asked for, a host key, what failed) — found by
the relaunch test, where docking would have closed the question with it. Databases, desktops and editors are not
reopened at launch at all, so they have no state to come back in. Then: "could we make it responsive? A user could
then make it vertical with simply resizing it so … Glass/transparency options for the dock?" Asked, he chose **its
shape decides** (taller than wide, a column; no direction setting) and **its own glass and Opacity, starting with
Appearance**. So the dock is resizable, keeps the size given it on this device and opens at it, fits its orbs in a row
until resized (Settings: Fit Dock to Its Orbs), and has a Dock section in Settings ▸ Appearance ▸ Orbs: Opacity and
Glass following Appearance until set. This ends the dock as a window with no panel: it now paints what Appearance
paints, and 0% of both makes it clear again.

**Revised again 2026-10-26, with the commit (bd85f676).** "Respond like a responsive flex with cards in it where the
docked windows move to fit the shape of the dock"; a name near the dock's right edge opening left; "a pinch and drag
scrolls the dock 100% of the time ... pinch hold drag on a window should move it like it does today"; Connections
"more prominence ... pinch and hold actions"; and from a tall dock, windows "to the left or right depending on dock
position". Asked, he chose orbs that wrap (not cards), Connections a third larger and set apart, its hold menu with
favorites, recents and Settings, and the side from where the head points (visionOS tells an app nothing of where its
windows stand). The hold that carries an orb is UIKit's on the dock's window: measured, SwiftUI's hold-then-drag on the
orbs kept a quick drag from scrolling. Then, from the headset: docked orbs show the picture their window had as it
docked, kept across a relaunch; and "enable focus on motion by default": Auto-focus on Activity is on unless set.

**Revised 2026-10-27, from the headset on 0.4.535.** "No menu on the connections icon with pinch and hold. When we
resize the dock, let's make sure it snaps to the shape of the visible icons. Also, the first time I tried to resize
vertically the app crashed." Found: ARKit gives head tracking only in a Full Space ("ARKit data is available only when
your app presents a Full Space and other apps are hidden", Apple, Setting up access to ARKit data), so the head-based
side never worked in the shared space; and `ARKitSession.run(_:)` "throws an error or asserts" when handed a provider
it stopped, which the dock did as it went tall, wide and tall again. Asked, he chose **the head in Focus Mode, a
setting elsewhere** (Settings ▸ Appearance ▸ Orbs: Windows From a Tall Dock, On Its Left / On Its Right, right by
default) and **the nearest whole rows** for the snap. So the dock runs no head tracking of its own and asks Focus
Mode's; a resized dock, once the hand lets go, snaps to the widest row its orbs make at that width and to every row or
the whole rows nearest its height, and snaps within the size given again as orbs come and go. Connections' hold menu
is a menu whose pinch is its primary action: a `.contextMenu` on that button never opened, in the simulator either.

**Status:** Approved 2026-10-25; built through the eighth round (0.4.534) and committed 2026-10-26 at his word. The
headset has seen rounds one to five and nine; the sixth to eighth are his to confirm. The ninth (the flex, names,
scroll, Connections' menu, sides, kept pictures, auto-focus on) is 0.4.535 and the tenth (the crash, the snap, the
menu, the side setting) 0.4.536, both committed 2026-10-27 at his word. Task note
`tasks/2026-10/2026-10-25_orb-dock.md`.

## D89 — Focus Mode environments on Vision Pro — Approved 2026-10-26
**Owner, 2026-10-22:** "crazy crazy idea for the focus mode.... in the window settings, overriding the application
preferences.... the user should be able to upload their own environment. include a sketchfab free model browser with
room and environment filters." His answers that day: iCloud for the files, 360° photos too, and a Sketchfab
registration request drafted for him to send (not known to be sent). **2026-10-26:** "Go ahead and build the upload
interfaces and the environment library", "can you make a few that will become part of the library of environments by
default?", then "This environment feature should only be on visionOS … The user may manage their library from mac,
but the environments are spatial and only work (today) on Vision Pro."

**Decision:**
- Focus Mode on Vision Pro shows an environment from a library: Dimmed Room (as before, the default), four built-ins
  drawn in code (Night Sky, Dusk, Grid, Studio; no image assets), and the person's own 3D rooms (USDZ, Reality) and
  360° photos (pictures twice as wide as tall).
- The person's own are files in iCloud Drive ▸ Glass Power Tools ▸ Environments (the app's iCloud container, made
  public in Finder and Files), so a Mac manages the library in Finder; without iCloud Drive they stay on the device.
  Added on the headset from Files, or dropped on the library. Checked on the way in: a 3D file must be one inside, a
  picture 2:1; refusals say why.
- Settings ▸ Terminal ▸ Focus Mode chooses for every window (synced, but sent only by Vision Pro, so another device's
  unchosen default can't undo it); This Window, and the moon's pinch-and-hold menu, for one window.
- Only Vision Pro shows any of it. The Mac's Focus Mode stays full screen.
- **Not built:** Sketchfab (sold by Epic to KitBash in August 2026, its Download API's future unannounced) or any other
  catalogue; live data in environments (proposed to him).
- **Open Immersed** (the owner, 2026-10-26, answering whether a chosen environment should open fully around him:
  "Leave immersion to the user... in that same panel in the main settings. [ ] Open Immersed."): a toggle in Settings ▸
  Terminal ▸ Focus Mode, off by default. On, Focus Mode opens all the way round; the Digital Crown still dials it back.
- **Try Out, fits and moving about** (the owner, 2026-10-26: "Yes, build all three"): a 3D environment is fitted in
  Try Out (what its numbers are in, a size, a floor, where to start; the file's own camera when it has one), the fit
  kept beside the file in iCloud for every Vision Pro. Inside any environment with a floor the person moves by
  Mirador's teleport (pinch the floor, the hand chooses the facing, raise it to cancel; swing a pinch on the sky or
  a wall to turn 45°), onto a room's own floors and landings too. The world moves, never the person; a floor is
  forced under every walkable environment. Head position from ARKit world tracking, which asks nothing of the person.

**Status:** Approved and built 2026-10-26 (0.4.530–0.4.533); committed 2026-10-26 at his word. Not yet seen on the
headset. Task note `tasks/2026-10/2026-10-26_focus-environments.md`.
