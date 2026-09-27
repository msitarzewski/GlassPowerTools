# Stage 3 — the Database capability, planned from a full survey

Owner `/root`. 2026-09-12. **Supersedes the drafted
[Stage 3 note](2026-09-10_stage-3-database.md)**, which predates the one-and-done setup sheet, the
service-draft contract, the address-on-the-host rule and the tool-row hook, and which also records
glassdb's floor as macOS 27.0.

**Status: wave 1 complete, wave 2 in progress.** See the work breakdown below for what each worker
delivered and its note. Nothing is committed.

Evidence: two read-only surveys of `../glassdb`, preserved beside this note at
[`surveys/glassdb-features.md`](surveys/glassdb-features.md) (949 lines, 12 sections) and
[`surveys/glassdb-engine.md`](surveys/glassdb-engine.md) (792 lines, 8 sections + risk appendix).

## What we are porting

22 app files / 22,244 lines, plus `Packages/GlassDBKit` (6 files, ~3,200 lines) and a 4,567-line
test file. Three engines, all complete end to end: **MySQL/MariaDB** (a mandatory fork of
mysql-nio — upstream PR 126 closed unmerged, fixes empty-password `caching_sha2_password`),
**PostgreSQL** (postgres-nio), **SQLite** (system sqlite3, with a proper online-backup snapshot).
No TODOs, no stubs, no `#if DEBUG` in authored code.

## The five decisions this stage turns on

### D7 — the tunnel is the host's own SSH service — **IMPLEMENTED 2026-09-12**

glassdb's database record carries its *own* `sshHost`, `sshPort`, `sshUsername`, `sshAuthMethod`,
`sshKeyID`. In Power Tools the host already **is** the machine and already owns the address (D-address)
and, usually, a Terminal service with credentials. So the database service should carry **no SSH
fields at all**: when the database is not directly reachable, the capability asks the shell for the
host's SSH transport and calls `forward(localPort: nil, toHost: "127.0.0.1", port: dbPort)`.

This is the user's requirement that SFTP serve the editor and port forwarding serve the database, made real, and it is
the single biggest simplification in the port: the Database tab of the setup sheet loses an entire
SSH section. It also unifies host trust — a host trusted in the terminal is trusted for the tunnel.

Needed a shell-level way for one capability to borrow another's transport without importing it.

**Built, and not in the proposed shape.** The hook is
`GlassCapabilityHostAccess.forwardPort(toHost:port:)` returning a `GlassHostPortForward`, not
`sshTransport(for:)` returning an `SSHTransport`: the borrower needs a local port, and returning one
keeps the NIO graph out of `GlassShell` entirely rather than pulling it in behind every consumer of
the shell. The lender side is `GlassCapability.openPortForward(host:toHost:port:)`, which defaults
to a refusal and is implemented by `GlassTerminalCapability`. **Capabilities still never import each
other.** 7 unit tests; **no live tunnel opened yet** — see
[the W-shell note](2026-09-12_stage-3-shell-forward.md), including the deliberate decision to refuse
rather than prompt for host-key trust from a background tunnel.

Open sub-question: a database on a *different* machine reached through this host as a jump. glassdb
supports it implicitly (ssh host ≠ db host). Either model it as a second host with its own service,
or keep an advanced "reach through another host" picker. Recommend the former; decide before W2.

### D8 — "This Mac" is a real host — **APPROVED 2026-09-12**

The user asked for it to behave like a connection in All Connections, allowing several database
services (SQLite, local MySQL, PostgreSQL and so on), a new local terminal on each click of the
toolbar's terminal icon, and screen sharing for local containers and VMs; Files seemed an odd fit,
but the user concluded every kind should be allowed — **yes, all of them.**

A built-in local host appears in the library like any other machine and takes every service kind:

| Kind | On the local host |
|---|---|
| Database | SQLite files, and a local MySQL or PostgreSQL on 127.0.0.1 — **several at once**, each its own service |
| Terminal | a local shell; **each click of the terminal toolbar icon opens another one**, so the local host holds many |
| Desktop | Stage 4: containers and VMs on localhost |
| Files | **not shipped — this row of the plan was wrong.** `Files` is not a service kind: it is a `GlassServiceTool` riding a Terminal service's live SSH session (`GlassTerminalCapability.serviceTools`), and there is no local-filesystem browser anywhere in the tree. A Files row here would have opened nothing, so it was deliberately not shipped. Closing it needs a local backend for `SFTPBrowserView`, or a new browser |

Consequences to design for, not to discover later:

- **The host has no address and never asks for one.** The address gate (W7's work) must exempt it;
  its services bind to `127.0.0.1` or a file path.
- **It is never published to the shared catalog** and never merges with a discovered host. It is
  local to this device, so each device has its own.
- **Its services never tunnel.** D7's "borrow the host's SSH transport" does not apply.
- **`connectAll` on it would open everything at once.** Decide whether the play glyph is even right
  there, or whether the local host's row offers only the chevron.
- The Mac's local terminal, which today lives only behind ⌘N in the terminal window, gets a home.
- Several services of the same kind on one host is already legal in the catalog; the shell's
  detail, icons and `connectAll` must be checked against three terminals and two databases.

### D9 — parity-plus — **APPROVED 2026-09-12**

The survey lists what glassdb does **not** do. Porting faithfully ports these gaps:

| Gap | Cost to close during the port |
|---|---|
| **No row deletion anywhere** — removing a row means typing SQL | Small: one predicate path already exists for UPDATE; reuse it with the same exactly-1-affected-row guard |
| No foreign-key navigation, though FKs are displayed | Small-medium: the grid already knows the FK list |
| No CREATE TABLE / CREATE or DROP DATABASE; no trigger, function, view, sequence or enum editing | Large; out of scope for Stage 3 |
| No whole-table / whole-database / streaming export | Medium; pairs with the no-streaming finding below |
| Mutation audit log is written but never readable | Small: one list view |
| AI assistant's availability gate is wrong — **corrected 2026-09-12 by the floor sweep**: five `guard #available(visionOS 27.0, macOS 27.0, *)` sites, but `SystemLanguageModel` is `@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`. The `*` resolves to the iOS target, so it in fact **works on iOS and is dark on macOS 26.x and visionOS 26.x** — the opposite of the survey's reading | Trivial: drop the gate to 26.0. Almost certainly unintended |
| iOS Settings omits Appearance entirely (`SettingsView.swift:129-152`) | Trivial: the shell owns Appearance now, so this resolves itself |
| **Open bug: SQL draft data loss** on window close / app quit, explicitly unfixed and explicitly not to be described as fixed | Medium: durable drafts. **Porting verbatim ports the bug.** |

**Decided: parity-plus.** The user chose parity plus, since the work was already under way. So Stage 3 ships every small
and medium closure in the table above — row deletion with the same exactly-one-affected-row guard
the update path uses, foreign-key navigation, the audit viewer, AI on iOS, and **the SQL draft-loss
fix**, which is a correctness bug and must not be carried over. CREATE/DDL breadth (tables,
databases, triggers, functions, views, sequences, enums) and streaming export stay out of Stage 3
and are recorded as the database capability's own backlog.

**Added to that backlog 2026-09-12, found by running the live tests rather than by reading: there is
no way to trust a self-signed database certificate.** The app constructs only `.requiredSystemTrust`
/ `.requiredSystemTrustForHost` (`DatabaseSessionManager.swift:238-243`);
`grep -rn requiredCertificates ../glassdb/glassdb/` returns **0**, and the connection form has a
"Use TLS" toggle (`ConnectionFormView.swift:613`, `:964`) with nothing that accepts a certificate.
Both MySQL and PostgreSQL self-sign by default, so ticking "Use TLS" against a stock server is a
hard failure — loudly, not silently; there is no retry path — with no remedy inside the app. Closing
it needs **both** a CA-only verification mode (MySQL's `VERIFY_CA`, which `DatabaseTLSPolicy` cannot
express — D13) and a certificate import. A defect, not a blocker: the cold-cache measurement proved
mysql-nio completes `caching_sha2_password` over the RSA key exchange, so plaintext auth is safe.

### D10 — result streaming (proposed)

There is no `AsyncSequence` anywhere in GlassDBKit; every result is fully materialised into
`[[DatabaseValue]]`, and the app bounds rows by appending a limit to the SQL plus a sentinel row.
That is acceptable and shipping. Keep it for Stage 3, record it, and revisit with export.

### D11 — cancellation semantics (proposed)

MySQL and PostgreSQL cancel by **closing the transport**; only SQLite cancels without disconnecting.
Keep the behaviour, but surface it honestly in the merged UI: cancelling a long query drops the
connection and the session reconnects. Do not let the UI imply otherwise.

## Module layout

| Module | Owns | Depends on |
|---|---|---|
| `Packages/GlassDBKit` | glassdb's engine moved **minus `SSHTunnelManager.swift`** | mysql-nio (pinned fork), postgres-nio, swift-nio-ssl, system sqlite3 |
| `Sources/GlassDatabase` | the 22 app files, less its library and its settings shell | `GlassDBKit`, `GlassSSHTransport`, `GlassShell`, `GlassLayers`, `GlassEditorCore` |
| App target | registers the capability, declares its scenes | — |

`GlassDatabase` imports `GlassSSHTransport` for forwards only and **never** imports `GlassTerminal`.

**The dependency conflict dissolves with the tunnel manager.** The survey's top risk is that
swift-crypto 4.5.2 is excluded by glassdb's *vendored* Citadel and swift-nio-ssh (`<4.0.0` upper
bounds). We are not bringing those copies: this repo already vendors glas.sh's modern Citadel and
swift-nio-ssh and already builds on swift-crypto 4.5.2. Dropping `SSHTunnelManager` drops
GlassDBKit's only Citadel dependency (`Packages/GlassDBKit/Package.swift`), leaving mysql-nio,
postgres-nio and swift-nio-ssl — the combination the Stage 3 gate already proved resolves.

## Conforming to the Power Tools patterns

| Pattern | What the database capability supplies |
|---|---|
| `GlassCapability` | `kind: .database`, `displayName: "Database"`, the Heroicons circle-stack symbol already in the kit |
| `GlassServiceDraft` | **required:** engine, database, username, password. **advanced:** port, TLS, read-only mode, row-page size, colour tag. **No SSH fields** (D7), **no address** (the host owns it) |
| `commit(endpointID:host:address:)` | writes the connection record and its credential, creating the service complete — no pending state, no "Set Up…" |
| `serviceTools` | **Query** (opens the editor against this service) and **Schema** if it earns a row; the pattern Files established |
| `settingsPages` | glassdb's Connections/Editor/AI pages folded into the one settings surface; Appearance is the shell's and is dropped |
| `open(service:host:hostAccess:report:)` | opens the database workspace window; reports `.connected` / `.failed` so `lastConnected` is honest |
| `removeService` | deletes the connection record, its credentials, and any managed SQLite copy |
| Library row | the circle-stack icon already ships; `connectAll` opens the database alongside the terminal |
| Setup sheet | fills the **Database tab** that is disabled today, with no shell change |
| Windows | `Window`/`WindowGroup` in a `GlassDatabaseScenes`, registered like `GlassTerminalScenes`; recovery through `GlassWindowRecoveryManager` |
| Rules | 15 (HIG sheets), 16 (verify the installed version), 11 (element screenshots), 13 (panel roles) |

## Work breakdown

Status as of 2026-09-12. Wave 1 opened with three independent pieces; **W-shell** was pulled
forward from wave 2 because it depends on nothing in wave 1 and unblocks W-capability.

| Wave | Worker | Owns | Deliverable | Status |
|---|---|---|---|---|
| 1 | **W-kit** | `Sources/GlassDBKit` | the engine moved minus the tunnel manager and its Citadel edge; builds for the three platforms in the merged graph; tests pass; the live-DB tests gated on env vars | **done** — [note](2026-09-12_stage-3-kit-move.md). 22 tests (6 left with the tunnel manager, each with a named owner in `GlassSSHTransport`); package 507/33; three platforms build; **swift-crypto 4.5.2 kept, so the survey's top risk is dead — proven by resolving, not by reasoning** |
| 1 | **W-floor** | read-only sweep | every API above the 26.0 floor listed, with the adaptation for each | **done** — [note](2026-09-12_stage-3-floor-sweep.md). **Exactly one API, and it is macOS 26.1, not 27.0** (`Constants.swift:663`). Measured by compiling at 26.0: exit 65, two diagnostics, one call site; one `if #available` and all four platform builds succeed. **Floor unchanged (D12)**; the guard now lives once in `GlassLayers` |
| 1 | **W-vm** | the test VM only | MySQL and PostgreSQL on `192.0.2.6`; least-privilege users, never root; seeded schema; exact commands recorded | **done** — [note](2026-09-12_stage-3-vm-databases.md). Real Oracle **MySQL 8.4.11** (not MariaDB) and **PostgreSQL 18.6**, seeded `teams`/`members` with a foreign key. Two databases per engine: `gpt_test` (fixture, DML only) and `gpt_scratch` (CREATE/DROP), because a MySQL database-scoped `DROP` also permits `DROP DATABASE` — proved by dropping the fixture during a denial test. **Both live round trips pass against real servers**, MySQL's on a flushed auth cache so the RSA path is genuinely exercised |
| 2→1 | **W-shell** | `Sources/GlassShell`, `Sources/GlassTerminal` | a capability borrows the host's SSH forward without importing the capability that owns it | **done** — [note](2026-09-12_stage-3-shell-forward.md). Landed as `forwardPort(toHost:port:)`, not `sshTransport(for:)` — a port keeps NIO out of the shell. 7 unit tests; package 514/34; **no live tunnel opened yet** |
| 2 | **W-capability** | `Sources/GlassDatabase`, `Tests/GlassDatabaseTests`, `App/`, and D14's `GlassTerminal` edits | the 22 app files moved; library replaced by the shell's; the draft/commit contract; the tunnel over the engine (D7); host-key trust through the terminal's own prompt (D14); scenes | **stages 1–3 done** — [note](2026-09-12_stage-3-capability.md). 21 files / 19,332 lines; the **Database tab is live**, verified by UI test; read-only enforced on the connection (D15); package 544. **Nothing has reached a real server yet** — the live run is next, and D14's terminal work is outstanding |
| 2 | **W-local** | `Sources/GlassShell`, `Sources/GlassTerminal` | the built-in local host (D8): always present, never published, exempt from the address gate, several services of one kind, each terminal-icon click opening another local shell; the shell's detail, icons and `connectAll` verified against three terminals and two databases. **Must also exclude the local host from the forward broker** — its services are already local | **done** — [note](2026-09-12_stage-3-local-host.md). Four corrections to D8 recorded as an addendum in [decisions](../../decisions.md); Files deliberately not shipped; `connectAll` picker-only; 4/4 macOS UI tests. iOS and visionOS **compile-verified only** |
| 3 | **W-gaps** | `Sources/GlassDatabase` | the approved D9 closures: row deletion, FK navigation, audit viewer, AI on iOS, and the SQL draft-loss fix | pending |
| 3 | **W-settings** | settings pages | folded into the one surface; Appearance removed | pending |
| 3 | **W-palette** | `Sources/GlassShell` or `GlassLayers`, `GlassTerminal`, `GlassDatabase` | **one macOS command palette.** glassdb's `MacCommandCenter`/`CommandPalettePanel` (now in `Sources/GlassDatabase/Constants.swift`) and glas.sh's (`Sources/GlassTerminal/macOS/MacWorkspaceCommands.swift:285`) are two implementations of one macOS-wide surface. Nothing collides today — different modules — but a merged product must not show two. Shape: a shell-owned surface with capabilities contributing entries, like `settingsPages` / `serviceTools`. **Cross-module and collides with W-local, so it is its own task, not a stage-3 improvisation** | pending |
| 4 | **security review** | read-only | the tunnel replacement; credentials never as `String` (the survey found `SecureBytes` downgraded to `String` at `DatabaseSessionManager.swift:131-132`); the record-editor predicate path; export paths; AI SQL gating and prompt-injection defences | pending |
| 4 | **integration** | `UITests/` | three platforms; add a database service in the one sheet; connect direct and over a tunnel; browse schema; run a query; edit a record | pending |

## Remaining work, re-planned against the code that now exists — 2026-09-12

The waves above were planned before the port. This section replaces their pending rows: every item
is anchored to a real `file:line` in `Sources/GlassDatabase`, and two of the original estimates were
wrong.

### Already done, struck from the list

- **AI on iOS.** The plan carried this as a D9 closure. W-capability fixed it during the port:
  all five gates read `#available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`
  (`AIAssistant.swift:176, 217, 282, 364, 396`). Nothing to do.
- **iOS Settings omitting Appearance.** Resolved by the shell owning appearance, as predicted.

### R1 — the SQL draft-loss fix — **DONE 2026-09-12**

[Note](2026-09-12_sql-drafts.md). Drafts live in `Application Support/GlassPowerTools/SQLDrafts/`,
one file per connection — query history's *shape* reused, its *medium* deliberately rejected:
history is capped at 500 entries because `UserDefaults` is materialised at launch and rewritten
whole, and a draft is unbounded (10 MiB imports). Scoped to the connection, not the session, because
replaying a `DELETE … WHERE` written for one schema into an editor pointed at another loses data.
Restored once per workspace via a claim, so a second window does not duplicate every tab. Pruned at
24 drafts / 8 MiB per connection with a 90-day expiry, and dropped outright when the connection is
deleted (`ConnectionManager.swift:262`).

**It found a second instance of the same bug:** `tableSQLDrafts` (`DatabaseWorkspaceView.swift:203`)
holds SQL written against *table* tabs, equally unsaved, equally lost on quit, and absent from this
plan. Persisted too — and restored back into `tableSQLDrafts` rather than opened as tabs nobody
asked for.

**Unproven and wanting a person in front of the app:** that restore fires at all —
`onChange(of: session?.connectionConfig.id, initial: true)` assumes a session exists by first
render, which is *read, not observed*. Everything else is worthless if that does not run.

### R1 — original brief (kept for the reasoning)

**Confirmed by reading the port:** `QueryDocumentTab` holds its SQL in `var text: String`
(`QueryEditorView.swift:345`, its `text` at `:347` — this note first cited `:68`, which is
`SQLTextDocument.text`; the conclusion held, the line did not) and **nothing persists it** — there is no `UserDefaults`, no
`@AppStorage` and no file backing in `QueryEditorView.swift` or `DatabaseWorkspaceView.swift`.
Closing the window or quitting loses every unsaved statement. The user agreed this must not be
carried over; it is the one item here that loses work rather than merely lacking a feature.

Shape: give each tab a durable draft keyed by its workspace and tab identity, written on change
(debounced) and restored on open, with the existing `tabs` array (`DatabaseWorkspaceView.swift:99`)
as the index. Query *history* is already persisted (`DatabaseSessionManager.swift:21`
`persistentQueryHistory`), so the storage pattern to follow is in the same module.

### R2 — row deletion — **DONE 2026-09-12**

[Note](2026-09-12_rows-and-audit.md). The optimistic row-identity predicate was extracted out of the two update paths into `RowMutationSQL.swift`, so deletion is a **third caller** rather than a fourth copy. Three layers guard it: `identityPredicate` throws before any SQL exists if the table has no primary key or the row yields no clauses (a collapsed predicate would empty the table); every statement runs in a transaction requiring `affectedRows == 1`; and against **real MySQL 8.4.11 and PostgreSQL 18.6** a current row reports 1, a row with a NULL column reports 1 through `IS NULL`, and **a row edited underneath the user reports 0 and survives** — the optimistic check firing, not a description of it firing.

### R2 — original brief

None exists: `grep` for `DELETE FROM` across the module returns nothing. The two write paths to
copy are the single-row update (`TableDetailView.swift:3963`) and the pasted-range update
(`:4059`), both of which build their `WHERE` from the primary key **plus every original row value**
as an optimistic conflict check, and both of which already route through the mutation review sheet
(`recordMutationReviewSheet`, `:2697`, preview text at `:3843`). Deletion reuses that predicate
shape and that review sheet, with the same exactly-one-affected-row guard.

Note the plan's phrase "one predicate path already exists" pointed at
`TableDetailView.swift:781 static func predicate(...)`, which is the **browsing** filter used by
SELECT and COUNT (`:625`, `:650`) — not the row-identity predicate. Use the update path's.

### R3 — foreign-key navigation — **DONE 2026-09-12**

`ForeignKeyNavigation.swift`, a Follow Reference menu and a per-relationship button. **Composite keys fail closed:** `relationships(from:)` refuses a key whose ordinals repeat rather than guessing — fed the exact four-row cross product the PostgreSQL adapter used to return, it returns nothing instead of a confidently wrong `x → b`, so this morning's defect cannot return through this path. Proven live on both engines with a fixture parent holding **both `(1,2)` and `(2,1)`**, so a transposed pairing would land on a row that *exists* and a test whose wrong answer was "no rows" could not pass for the wrong reason.

A staged handoff that nothing ever claims goes stale after 30 s — otherwise it would have filtered the user's **next ordinary visit** to that table, which looks exactly like the app working.

### R3 — original brief

`foreignKeys(in:database:)` is now trustworthy on both engines — it was wrong in two independent
ways until today (owner-scoped view, and composite keys returned as a cross product; see
`PostgreSQLAdapter.swift`). The keys are already displayed in their own tab. What is missing is the
act of following one: open the referenced table filtered to the referencing value. Composite keys
must carry every column pair, which is exactly what the cross-product bug would have broken.

### R4 — the mutation audit — **DONE 2026-09-12** (and corrected twice; read this)

This section was wrong in both directions, and the second error is the instructive one.

The original plan said "Small: one list view". The re-plan then said **"there is no audit store"** —
also wrong. There is: `MutationOutcome`, `MutationAuditRecord` and `MutationAuditStore` at
`Models.swift:388-445`, persisting a 1,000-record ring under `glassdb.mutationAudit.v1`
(`Constants.swift:30`), with **11 call sites already appending** — single-row update, pasted range,
insert, truncate and drop (`SchemaBrowserView.swift:520,542`), schema change
(`TableDetailView.swift:4766,4784`) and confirmed query-editor statements (`:3885`). W-capability
built it during the port and it already follows the `persistentQueryHistory` pattern.

**How the re-plan got it wrong:** it grepped for `auditLog`, `AuditEntry`, `writeAudit` and
`mutationHistory`, found nothing, checked `Logger.swift`, saw no audit category and concluded
absence. It searched for **the names it expected rather than the concept**. A negative claim —
"there is no X" — needs more care than a positive one, because a positive claim carries its own
evidence and a negative one only proves where you looked.

**So the actual work is:** a viewer, and one new field. `MutationAuditRecord` gained
`predicate: String?` (optional, so records already on disk still decode).

**What a record stores, decided deliberately:** the predicate's **shape only** — the SQL with its
bound placeholders left in — and **never the parameters**. The optimistic predicate these paths
build is the primary key plus every original column value, so the parameters are a verbatim copy of
the user's row; writing them into `UserDefaults` in plaintext, in a store that exists to be read
back and displayed, would create a copy of the user's data nobody asked for. The shape still answers
which columns identified the row, whether NULLs took part, and how wide the conflict check was.

It deliberately **cannot** answer *which* row. Storing primary-key values would close that and is
refused: a key is routinely itself identifying (an email, an account number), so there is no subset
of the parameters that is safely "just the key". Row-level traceability is a separate decision to be
taken in the open, not smuggled in under "audit".

### R5 — settings — **DONE 2026-09-12**

`windowOpacity` and `blurBackground` were *stored* in `Sources/GlassDatabase/SettingsManager.swift`
with their own `UserDefaults` persistence — a second copy of state the shell already owns, and the
reason the Appearance page had nowhere to write once the shell took it over. They are now computed
over the one `GlassLayerStore`, exactly as `GlassTerminal.SettingsManager` has always done, and the
runtime passes the store it was already holding. Net effect: persistence deleted, not code added.

### R5 — original brief

`Sources/GlassDatabase/SettingsManager.swift` still carries appearance values (`windowOpacity`,
`blurBackground`) that drive the database canvas with **no page to change them**, because the
Appearance page was dropped when the shell took ownership. Fold them onto the shell's
`GlassLayerStore`, exactly as `GlassTerminal`'s `SettingsManager(…layers:)` already does.

### R6 — one macOS command palette — **DONE 2026-09-12**

Not "two implementations of one surface" as this plan said all day: **one implementation pasted twice**, byte-for-byte identical at 286 lines, differing only by a trailing `#endif`. Each module also defined its own `MacCommandCenterEntry` and its own `macCommandCenterEntries` focused-value key — *same names, different types* — so a database workspace's commands could never reach the terminal's palette. Two palettes that could not see each other.

Now `Sources/GlassLayers/GlassCommandPalette.swift`, with a `GlassCommandPalette.present(...)` facade so consumers contribute entries without touching the table view or responder handling. 650 lines deleted, 7 added; the test moved to `GlassLayersTests` with the behaviour. **Release** built as well as Debug, because D16 was a Release-only link failure from sharing code across a module boundary.

### R6 — original brief

Two implementations of one surface: glassdb's `MacCommandCenter`/`CommandPalettePanel`
(`Sources/GlassDatabase/Constants.swift`) and glas.sh's
(`Sources/GlassTerminal/macOS/MacWorkspaceCommands.swift:285`). W-local established that **the seam
is cheap**: the dynamic entries are already produced as data at `DatabaseWorkspaceView.swift:1022-1041`
and `Constants.swift:793-799`, and only then handed to the panel. A shell-owned palette can take
those lists as id/title/action with the producers unchanged.

### R7 — D13 — **DONE 2026-09-12**

[Note](2026-09-12_certificate-trust.md). `.requiredCertificatesWithoutHostnameVerification` — a **separate case**, not a reinterpretation of `serverName: nil`, which still means "match the connection host" and has a test guarding it. Reachable only because a user picked it by name; **no path from a failed full verification**. The connection detail now states what TLS verifies rather than that it is on.

**The distinction that matters:** the engine-level test proved the *engine* could do VERIFY_CA. It could not prove a saved record reaches it — until `transportPlan` mapped the mode, every piece existed and nothing joined them. Three **capability-level** live tests tell those two states apart: a saved CA-only service connects through `DatabaseSessionManager` and the *server* reports a non-empty `Ssl_cipher`; the name-checking mode still throws; a pinned service with no certificate throws and leaves no session behind.

`ConnectionFormView` — ~1,295 unreachable lines — deleted after `SQLiteFileImporter` was extracted, every nested type grepped first.

### R7 — original brief

Needs **both** halves, which is why it is bigger than it looks: a CA-only verification mode
(MySQL's `VERIFY_CA`, which `DatabaseTLSPolicy` cannot express) **and** a way to supply a
certificate, since the app never constructs `.requiredCertificates` at all. Both MySQL and
PostgreSQL self-sign by default, so today "Use TLS" against a stock server is a hard failure with
no in-app remedy.

### R8 — smaller items — **mostly done 2026-09-12**

PostgreSQL arrays closed — both spellings, literal well-formedness, each element checked against its
own type so `date[]` inherits the date check. `TransportPlan.tunnelRemoteHost`/`tunnelRemotePort`
deleted, along with two tests that were circular: they asserted a field nothing reads was written.
`ConnectionFormView` deleted. `StagedEdit.dialect` threaded from `session?.connection?.dialect`.

**`text`/`blob` — CLOSED 2026-09-12 (night), and the item was mislabelled.**

It read as "six of eight families work; bare `text`/`blob` need the dialect at `GridColumnFilter`".
The real gap was larger: `GridColumnFilter.validationError` was a **second, weaker copy** of the
record editor's check that called `boundValue()` and stopped — and `boundValue()` is type
*conversion* only (`RecordEditorView.swift:219`), never consulting `ColumnTypeConstraint`. So a grid
filter ran **no size check at all**, on any type, on any engine: `varchar(4)` accepted `"12345"` and
returned an empty page with no explanation.

Now consults the constraint, and takes the dialect as a **parameter rather than a stored property** —
a saved filter outlives its session and the engine belongs to the connection, which is also why
`GridColumnFilter` stays `Codable` with no migration. Threaded at five call sites.

**Size-checked for `.equals` only, deliberately.** A filter is a read, so the question is not "will
the server store this?" but "can any stored row match it?". For `=` the answer is provably no. For
`<>` the same value matches every row, and for `<`/`>` an out-of-range bound is an ordinary way to
say "all of them"; refusing those would block correct queries. `onlyEqualityIsSizeChecked` exists to
stop someone tidying that condition away.

**How it was caught, which is the transferable part:** the first version of the test asserted only
the dialect-dependent cases and would have passed for the wrong reason. Adding `varchar(4)` — which
needs no dialect and should have worked since the day size checking was written — is what exposed it.
*A test aimed only at the part you suspect will agree with you.*

### R8 — original brief

| Item | Where |
|---|---|
| `text`/`blob` byte limits — MySQL's `TEXT` is 65,535 **bytes**, which the declared type does not carry, so this needs the schema path | `ColumnTypeConstraint.swift` |
| PostgreSQL array types (`integer[]`) have no format check | `ColumnValueFormat.swift` |
| `TransportPlan.tunnelRemoteHost` is set and **never read** — delete it before someone mistakes it for the forward target | `DatabaseSessionManager.swift:31` |
| Files failed once from a cold app and worked after a quit/restart — stale state, not reproduced since, **not closed** | `GlassTerminalCapability.swift:292-304` |
| `createSFTPSession(sharing:)` has **no callers** — dead code that implies Files needs an existing session when it does not | `SessionManager.swift:424` |

### R9 — verification: partly closed 2026-09-12 (night), and this is what keeps Stage 3 open

**Closed.**
- **macOS integration UI.** `UITests/GlassDatabaseUITests.swift` passes **7/7** against real MySQL
  8.4.11 and PostgreSQL 18.6 — see [the device-pass note](2026-09-12_device-pass.md). Row deletion,
  a composite foreign-key follow, Run All Statements, draft restore and the editor's AX value are
  driven through the running app on both engines. This also answered R1's *"unproven and wanting a
  person in front of the app"*: **restore fires.**
- **Prompt-injection defences**, **export paths** and **AI SQL gating** now have tests where they had
  none — `SchemaContextTests`, `UntrustedPromptRegionTests`, `GridExportFormatterTests`,
  `SQLSafetyClassificationTests`, `GridServerQueryBuilderTests`, `SQLiteManagedStorageTests`.
  All five implementations were already correct; nothing had been guarding them.
- **Installed on device.** 0.3.69 is on the iPhone 17 Pro Max and the Vision Pro, version read back
  from the installed bundle. *Installed is not driven* — see below.

**Still owed, and Stage 3 is not closed until these are:**
1. **iOS and visionOS UI verification.** The suites are written to run there and have never been run
   there. The **visionOS UI target cannot link at all**: `GlassShellLocalHostUITests.swift:143` calls
   `.click()` on an `XCUICoordinate`, which the xrOS SDK does not have. That is a hard blocker on
   the platform this product was started for, and it should be fixed before Stage 4.
2. **The formal security review** as a pass in its own right — the tunnel replacement, credential
   handling and the record-editor predicate path are still unreviewed, even though neighbouring
   surfaces gained tests.
3. **The D14 fingerprint prompt.** The fingerprint *text* is now correct and known-answer tested
   against `ssh-keygen`, but **nobody has driven the prompt** — not a test, not a person.
4. The tag-vocabulary UI test failure, pre-existing and in untracked Stage 2 work.
5. An **accessibility gap**, recorded and deliberately unfixed pending a decision: schema rows expose
   no accessibility action for the single-click selection they exist for, and `tableRow` is the same.

### Suggested order

R1 (loses work) → R2 and R3 (the approved parity-plus that users will notice) → R5 → R4 once its
decision is taken → R6 → R7 → R8 → R9. Desktop should not start until R1–R3 are done, since they
are the difference between "the database capability is ported" and "the database capability is
finished".

## Verification

- `swift test` for GlassDBKit (28) and the ported app tests (152 in glassdb's suite — moved, not rewritten).
- Real databases. **APPROVED 2026-09-12: install MySQL and PostgreSQL on the test VM
  (`192.0.2.6`, user `michael`, sudo available).** Do it over the app's own SSH engine or plain
  ssh, record the exact commands and the seeded schema in this note, and create a least-privilege
  test user per engine — **never the root account** (global rule). Gate the suite on `GPT_DB_TEST_*`
  the way the SSH suite is gated. Without real databases Stage 3 cannot claim parity honestly.
- UI suites on macOS, iPhone and visionOS, with the known platform quirks (macOS `click()`, iOS
  toggle at dx 0.92, lazy rows need `reveal()`, the visionOS "Save Password?" alert).
- Device installs, version verified per rule 16.

## Risks carried from the survey

| Risk | Response |
|---|---|
| swift-crypto conflict | Dissolves with the tunnel manager; **prove by building, not by reasoning** |
| SSH key material as `String` | The engine takes credential *references*; the raw-string path is not ported |
| Blocking `syncShutdownGracefully()` in three deinits | Convert to explicit async shutdown during the move |
| PostgreSQL `databases()` returns schemas | Model it in the browser or it mislabels the tree |
| Connection persistence has no version number | Add one while moving the record |
| mysql-nio fork is mandatory and pinned by revision | Carry the pin; record why (upstream PR closed unmerged) |
| glassdb must keep building until parity | It keeps its own vendored copies; we take none of them |
