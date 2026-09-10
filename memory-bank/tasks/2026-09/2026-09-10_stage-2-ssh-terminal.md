# Stage 2 — GlassSSHTransport engine and the GlassTerminal capability

Owner `/root`. Planned 2026-09-10. **Status: planned; starts when Stage 1 is committed.**

## Task

- **Objective:** glas.sh at parity inside Glass Power Tools — terminal, SFTP, port forwarding,
  workgroups, its Mac workspace, its widget — with the SSH transport extracted as a first-class
  engine every other capability can use, and the layering system proven on the SSH connection panel.
- **Authorization:** given (Stages 1–5 end to end, user 2026-09-10). Commits by the coordinator.
- **Inputs, read-only:** `../glas.sh` (30 flat files, 31,393 lines; `Platforms/macOS` 5,663;
  `glasWidgets` 250; `Packages/Citadel`, `Packages/swift-nio-ssh` — the modern copies).
- **Decisions in force:** engines first-class, one capability module, consumer matrix
  ([decisions](../../decisions.md)); transport surface and API proposal in the
  [groundwork](2026-09-10_stage-2-3-groundwork.md).

## Module layout (this repository)

| Module | Owns | Depends on |
|---|---|---|
| `Packages/Citadel`, `Packages/swift-nio-ssh` | glas.sh's vendored copies, verbatim | — |
| `Sources/GlassSSHTransport` | connection + shared per-host transport, host trust (GlasSecretStore), auth, PTY shell channel, **SFTP session**, **tunnels / port forwarding / SOCKS5** | Citadel, GlasSecretStore, GlassConnectionKit (IDs only) |
| `Sources/GlassTerminal` | everything else from glas.sh: `TerminalSession`, recording, terminal views, SFTP browser UI, port-forwarding UI, workgroups, server forms, settings pages, AI assistant, Tailscale, themes, `Platforms/macOS` workspace | `GlassSSHTransport`, `GlassShell`, `GlassLayers`, SwiftTerm, GlassEditorCore |
| `Widgets/` target (`GlassPowerToolsWidgets`) | `glasWidgets` moved, embedded on iOS and visionOS with `platformFilters = (ios, xros)` as glas.sh does | App Group defaults |
| App target | registers the SSH capability, declares its scenes | — |

Rule: `GlassSSHTransport` never imports `GlassShell`, `GlassLayers` or SwiftUI. `GlassTerminal`
keeps every file `internal`; only the capability registration, scene views and settings pages are
`public`.

## The engine's public API (contract the terminal codes against; drawn from real consumers)

```swift
public struct SSHEndpoint: Sendable, Hashable { host, port, username, jumps: [SSHEndpoint] }
public struct SSHCredentialReference: Sendable { credentialID: CredentialID; kind: .password | .privateKey(keyID) | .agent }
public protocol SSHHostTrustDecider: Sendable { func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision }
public actor SSHTransport {                      // from SharedSSHTransport / SSHConnection
    init(endpoint:credential:trust:secrets:)     // secrets = GlasSecretStore configuration
    func connect() async throws
    func openShell(pty: SSHPTYRequest) async throws -> SSHShellChannel     // terminal
    func openSFTP() async throws -> SFTPSession                            // SFTP browser, editor
    func forward(localPort: UInt16?, toHost: String, port: UInt16) async throws -> SSHTunnel  // database, desktop
    func remoteForward(...) / func socks5(...)                             // as PortForwardManager today
    func close() async
}
public struct SSHTunnel: Sendable { let localPort: UInt16; func close() async }
public protocol SFTPSession { list/stat/read(stream)/write(stream)/rename/remove/mkdir, cancellation }
```

- **No raw secrets cross the API.** Credentials are references resolved through GlasSecretStore
  inside the transport. glassdb's `SSHTunnelConfig` passing password/key strings is not ported.
- One host-trust challenge type for the whole app, backed by `SSHHostTrustKeychainStore`.
- The SFTP session and tunnel APIs are **exercised by a test consumer other than the terminal**
  before Stage 2 is called done: a `GlassSSHTransportTests` integration test opens a tunnel and an
  SFTP session against a real host, and a fixture consumer type compiles against the API without
  importing `GlassTerminal`. That is the proof of "first-class".

## Terminal integration contract (shell ↔ capability)

- `GlassTerminalCapability: GlassCapability` with `kind = .ssh`, registered by the app.
- The endpoint record stays glas.sh's `ServerConfiguration` in glas.sh's `ServerManager` store,
  keyed by `HostServiceLink.endpointID`. "Add a service… → SSH" opens the terminal's server form to
  create it and links it. If `GlassCapability` needs a `makeServiceEditor(host:)` hook for that,
  add it to the shell (small, public, documented).
- glas.sh's `ConnectionManagerView` library is **replaced** by `GlassShellLibraryView`; its server
  forms, add-server flow and detail actions survive as the SSH service editor and detail actions.
- Scenes: the app declares glas.sh's windows (`workspace`, `terminal`, `sftp`, `port-forwarding`,
  `html-preview`, `minimized`, `focus-environment`) from `glas_shApp.swift:99-280`, with the
  library window already owned by the shell.
- Settings: glas.sh's `SettingsView` pages become capability pages inside `GlassShellSettingsView`
  (the shell's `GlassSettingsSections`); `SettingsManager` moves into `GlassTerminal`;
  `ICloudSettingsSyncService` and `WindowRecoveryManager` move to the shell as shell services.
- The **SSH connection panel** draws from `GlassLayers` — this is the Stage 2 layering proof.

## Work breakdown and ownership

| Worker | Owns | Deliverable |
|---|---|---|
| W1 transport | `Packages/Citadel`, `Packages/swift-nio-ssh`, `Sources/GlassSSHTransport`, `Tests/GlassSSHTransportTests` | The engine per the contract; **publishes the public API first** (compiling signatures, then implementations) and writes its note so W2 can code against it; unit tests; real-host integration tests gated on `GPT_SSH_TEST_HOST`/`_USER` (recorded as not run when absent) |
| W2 terminal | `Sources/GlassTerminal`, `Tests/GlassTerminalTests`, `App/` scenes and capability registration, `Widgets/` | glas.sh moved in verbatim, compiling against `GlassShell` and W1's API; library replaced by the shell's; capability registered; glas.sh's tests moved and passing |
| W3 (after W1+W2) settings and shell services | glas.sh settings pages into the shell settings surface; `ICloudSettingsSyncService`, `WindowRecoveryManager` into `GlassShell`; iCloud KVS identifier per D3 | One settings surface with SSH pages; sync and recovery working |
| Security review (after W1) | read-only | Trust, auth, tunnel and SFTP path handling; **the two open audit items:** `SessionRecorder.recordInput` consent and output-only default; AI `riskLevel` one-click execution |
| Integration (after all) | `UITests/` | Builds/tests on iOS, visionOS, macOS; real-host session on the simulators and the Mac; UI tests for connect → terminal, SFTP browse, port forward; parity checklist |

Sequencing: W1 and W2 start together; W2 moves files and fixes everything except transport calls
first, then switches to W1's API. W3, security and integration follow.

## Parity checklist (what "done" means)

Connect to a real host over password and key auth with host-trust prompt; terminal I/O, resize,
themes, recording (with the audit fix); SFTP browse/upload/download/remote edit; local and remote
port forwards and SOCKS5; workgroups on visionOS and the Mac workspace; Tailscale listing; widget
shows server health; settings pages present; window recovery; iCloud settings sync. Each item is
checked on the platform it applies to and recorded in the integration note. `../glas.sh` builds
untouched throughout.

## Risks

| Risk | Response |
|---|---|
| The transport extraction breaks `TerminalSession`'s assumptions | W1 keeps `SharedSSHTransport`'s ownership and reference-counting semantics; W2 reports every call site that no longer fits before changing behaviour |
| Vendored Citadel/NIOSSH changes were made for glas.sh and are undocumented | Move verbatim; diff against upstream tags into W1's note; no edits |
| SwiftTerm 1.15 and Citadel's swift-crypto 4.5 in one graph with GlassEditorKit | Resolve at W1's first build; record the resolved `Package.resolved` |
| 31k lines of `internal` code moved into one module exposes duplicate type names with the shell/kit | Rename only on collision, noted |
| Real-host tests need a host | Gated on env vars, honest not-run otherwise; ask the user for a host to point at |
