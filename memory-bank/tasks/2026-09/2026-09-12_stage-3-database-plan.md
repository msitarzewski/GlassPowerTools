# Stage 3 — the Database capability, planned from a full survey

Owner `/root`. 2026-09-12. **Supersedes the drafted
[Stage 3 note](2026-09-10_stage-3-database.md)**, which predates the one-and-done setup sheet, the
service-draft contract, the address-on-the-host rule and the tool-row hook, and which also records
glassdb's floor as macOS 27.0. Status: **planned, not started.**

Evidence: two read-only surveys of `../glassdb`, kept at
`scratchpad/glassdb-features.md` (949 lines, 12 sections) and `scratchpad/glassdb-engine.md`
(792 lines, 8 sections + risk appendix). Copy both into this note's directory before the scratchpad
is lost if Stage 3 outlives the session.

## What we are porting

22 app files / 22,244 lines, plus `Packages/GlassDBKit` (6 files, ~3,200 lines) and a 4,567-line
test file. Three engines, all complete end to end: **MySQL/MariaDB** (a mandatory fork of
mysql-nio — upstream PR 126 closed unmerged, fixes empty-password `caching_sha2_password`),
**PostgreSQL** (postgres-nio), **SQLite** (system sqlite3, with a proper online-backup snapshot).
No TODOs, no stubs, no `#if DEBUG` in authored code.

## The five decisions this stage turns on

### D7 — the tunnel is the host's own SSH service (proposed)

glassdb's database record carries its *own* `sshHost`, `sshPort`, `sshUsername`, `sshAuthMethod`,
`sshKeyID`. In Power Tools the host already **is** the machine and already owns the address (D-address)
and, usually, a Terminal service with credentials. So the database service should carry **no SSH
fields at all**: when the database is not directly reachable, the capability asks the shell for the
host's SSH transport and calls `forward(localPort: nil, toHost: "127.0.0.1", port: dbPort)`.

This is the user's "SFTP to be used by Edit, port forwarding by DB" requirement made real, and it is
the single biggest simplification in the port: the Database tab of the setup sheet loses an entire
SSH section. It also unifies host trust — a host trusted in the terminal is trusted for the tunnel.

Needs: a shell-level way for one capability to borrow another's transport without importing it.
Proposal: extend `GlassCapabilityHostAccess` with `sshTransport(for: HostProfile) async throws ->
SSHTransport?`, resolved by the shell through whichever capability owns `.ssh`. **Capabilities still
never import each other.**

Open sub-question: a database on a *different* machine reached through this host as a jump. glassdb
supports it implicitly (ssh host ≠ db host). Either model it as a second host with its own service,
or keep an advanced "reach through another host" picker. Recommend the former; decide before W2.

### D8 — SQLite has no host (needs the user)

A SQLite connection has no address, no port, no credentials — it is a managed file copy in
Application Support. The shell's library is organised by machine. Options:

1. A built-in **"This Mac"** host that always exists, holding local services (SQLite files, and the
   Mac's local terminal, which today lives only in the terminal window's ⌘N).
2. SQLite files are **not services**: a separate Files-style tool row, or a documents surface.
3. Skip SQLite in Stage 3 and keep it in glassdb only.

Recommend option 1: it gives the local terminal a home too, and matches how the Mac already thinks.

### D9 — parity or parity-plus (needs the user)

The survey lists what glassdb does **not** do. Porting faithfully ports these gaps:

| Gap | Cost to close during the port |
|---|---|
| **No row deletion anywhere** — removing a row means typing SQL | Small: one predicate path already exists for UPDATE; reuse it with the same exactly-1-affected-row guard |
| No foreign-key navigation, though FKs are displayed | Small-medium: the grid already knows the FK list |
| No CREATE TABLE / CREATE or DROP DATABASE; no trigger, function, view, sequence or enum editing | Large; out of scope for Stage 3 |
| No whole-table / whole-database / streaming export | Medium; pairs with the no-streaming finding below |
| Mutation audit log is written but never readable | Small: one list view |
| AI assistant unavailable on iOS (`AIAssistant.swift:176` names only visionOS 27 / macOS 27) | Trivial: fix the availability check |
| iOS Settings omits Appearance entirely (`SettingsView.swift:129-152`) | Trivial: the shell owns Appearance now, so this resolves itself |
| **Open bug: SQL draft data loss** on window close / app quit, explicitly unfixed and explicitly not to be described as fixed | Medium: durable drafts. **Porting verbatim ports the bug.** |

Recommend: close the four trivial/small ones during the port (row deletion, FK navigation, audit
viewer, the two platform gaps), fix the draft-loss bug as part of moving the editor, and leave
CREATE/DDL breadth and streaming export to a later stage.

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

| Wave | Worker | Owns | Deliverable |
|---|---|---|---|
| 1 | **W-kit** | `Packages/GlassDBKit` | moved minus the tunnel manager and its Citadel edge; builds for the three platforms in the merged graph; its 28 tests pass; the three live-DB tests gated on env vars |
| 1 | **W-floor** | read-only sweep | every API above the 26.0 floor listed — **measured: exactly two errors, both `Constants.swift:663` (`visibilityPriority`), so the real floor is 26.1, not 27.0**; adapt with `if #available` |
| 2 | **W-capability** | `Sources/GlassDatabase`, `Tests/GlassDatabaseTests`, `App/` | the 22 files moved; library replaced by the shell's; the draft/commit contract; the tunnel over the engine (D7); scenes |
| 2 | **W-shell** | `Sources/GlassShell` | `GlassCapabilityHostAccess.sshTransport(for:)` so a capability can borrow the host's SSH transport without importing another capability; unit-tested with a fake |
| 3 | **W-gaps** | `Sources/GlassDatabase` | the D9 closures the user approves: row deletion, FK navigation, audit viewer, AI availability, and the SQL draft-loss fix |
| 3 | **W-settings** | settings pages | folded into the one surface; Appearance removed |
| 4 | **security review** | read-only | the tunnel replacement; credentials never as `String` (the survey found `SecureBytes` downgraded to `String` at `DatabaseSessionManager.swift:131-132`); the record-editor predicate path; export paths; AI SQL gating and prompt-injection defences |
| 4 | **integration** | `UITests/` | three platforms; add a database service in the one sheet; connect direct and over a tunnel; browse schema; run a query; edit a record |

## Verification

- `swift test` for GlassDBKit (28) and the ported app tests (152 in glassdb's suite — moved, not rewritten).
- Real databases. **The test VM at `192.0.2.6` needs MySQL and PostgreSQL installed** — a user
  action, or a documented `docker compose` on the VM. Gated like the SSH suite:
  `GPT_DB_TEST_*`. Without it, Stage 3 cannot claim parity honestly.
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
