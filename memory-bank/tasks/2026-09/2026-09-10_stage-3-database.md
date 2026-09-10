# Stage 3 — the GlassDatabase capability over GlassDBKit and the shared SSH engine

Owner `/root`. Drafted 2026-09-10 while Stage 2 was integrating. **Status: planned; starts when
Stage 2 reaches parity.**

## Task

- **Objective:** glassdb at parity inside Glass Power Tools — connections, schema browsing, query
  editor, results grid, record editing, export, AI assistant, SQL documents — with its SSH tunnel
  replaced by `GlassSSHTransport.forward` and its settings merged into the one surface.
- **Inputs, read-only:** `../glassdb` (22 flat files, 22,244 lines; `Packages/GlassDBKit`, the
  engine; vendored Citadel/swift-nio-ssh — the *older* copies, **not** brought in).
- **Decisions in force:** engines first-class, one capability module, consumer matrix
  (`Database → tunnel`); 26.0 floor (glassdb's macOS target was 27.0: anything depending on 27.0
  API is found and adapted during the move).
- **Gate already passed (2026-09-10):** `mysql-nio` `6948987` and `postgres-nio` 1.33.1 resolve and
  build with swift-crypto 4.5.2 / swift-nio 2.102.0 in one graph.

## Module layout

| Module | Owns | Depends on |
|---|---|---|
| `Packages/GlassDBKit` | glassdb's engine package moved verbatim, **minus `SSHTunnelManager.swift`** (and its Citadel dependency) | mysql-nio, postgres-nio, nio-ssl |
| `Sources/GlassDatabase` | the 22 app files: `DatabaseSessionManager`, `ConnectionManager`, forms, workspace, schema browser, query editor, results grid, record editor, exporter, AI assistant, SQL highlighter, `GlassEditorAdapters`, settings | `GlassDBKit`, `GlassSSHTransport`, `GlassShell`, `GlassLayers`, `GlassEditorCore` |
| App target | registers the database capability, declares its scenes | — |

`GlassDatabase` imports `GlassSSHTransport` for tunnels only; it never imports `GlassTerminal`.

## The tunnel replacement — the first-class integration this stage proves

`DatabaseSessionManager.swift:135-186, 307-310` today: `SSHTunnelManager().establish(config)` with
`SSHTunnelConfig` carrying `sshPassword`/`sshPrivateKey` strings and a `trustedHostKeys` set.
Replacement: build an `SSHRoute` from the connection's SSH settings, an `SSHCredentialReference`
from its credential ID (GlasSecretStore — the raw-string path is not ported), obtain a transport
from the shell's `SSHTransportPool`, call `forward(localPort: nil, toHost: dbHost, port: dbPort)`,
connect the driver to `127.0.0.1:tunnel.localPort`, close the tunnel with the session. Host-trust
prompts use the same `SSHHostTrustDecider` UI the terminal registers, so a host trusted in the
terminal is trusted for the tunnel and vice versa — one trust store.

Proof: a `GlassDatabaseTests` integration test, gated on the same `GPT_SSH_TEST_*` variables plus
a database reachable on the test host, opens a tunnel through the engine and runs `SELECT 1`.

## Dependency map (measured; see groundwork)

Hubs: `Models.swift` 132 incoming refs, `Constants.swift` 89, `AIAssistant` 56, `SQLHighlighter`
47, `DatabaseSessionManager` 42, `KeychainManager` 42. `TableDetailView.swift` is 5,847 lines with
45 types; it moves whole. `ConnectionManagerView` (1,223) is glassdb's library — replaced by the
shell's; its forms (`ConnectionFormView`, 1,804) survive as the database service editor.

## Work breakdown

| Worker | Owns | Deliverable |
|---|---|---|
| W1 kit | `Packages/GlassDBKit` | moved verbatim minus the tunnel manager; builds for the three platforms in the merged graph; its tests pass |
| W2 capability | `Sources/GlassDatabase`, `Tests/GlassDatabaseTests`, `App/` scenes and registration | the 22 files moved; library replaced by the shell's; `GlassDatabaseCapability: GlassCapability` (`kind: .database`); tunnel over the engine; 27.0-only API found and adapted (list each); glassdb's tests moved and passing |
| W3 settings | glassdb's settings pages into the shell surface | one surface with database pages |
| Security review | read-only | tunnel replacement, credential handling in forms, SQL injection surface in record editing (the July audit's manual escaping finding — check whether glassdb fixed it), export paths, AI SQL gating |
| Integration | `UITests/` | builds/tests on three platforms; connect to a real database over a tunnel; UI tests: add database service, connect, browse schema, run a query |

## Parity checklist

Connect to MySQL and PostgreSQL directly and over an SSH tunnel; TLS on; schema browse; query with
results grid; record edit with transactions; export; SQLite local files; SQL documents on the Mac;
AI assistant with deterministic gating; settings pages present. `../glassdb` builds untouched.

## Risks

| Risk | Response |
|---|---|
| A 27.0-only macOS API in glassdb | Found at first build; adapt with `if #available` or a 26.0 equivalent; list in the note |
| Two SSH stacks briefly (glassdb's vendored copy pulled in by `GlassDBKit`) | `GlassDBKit` drops its Citadel dependency with the tunnel manager before it is added to the graph |
| The July finding "record editing emits manually escaped SQL with no transaction" | Verify current state during the review; fix in the capability if still present |
