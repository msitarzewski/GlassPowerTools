# Stage 2 and 3 groundwork — dependency maps and the carve

Owner `/root`. Written 2026-09-10 while Stage 1 workers were building. **Status: analysis and a
proposal; no Stage 2 or 3 code exists.** Every number here was measured from the checkouts.

## glas.sh — what depends on what

Cross-file references between the 30 flat files (`../glas.sh/glas.sh/*.swift`), counting uses of
types each file declares:

| File | Lines | Declares | Depends on (refs) |
|---|---|---|---|
| `Models.swift` | 3,252 | 53 types | KeychainManager(1), SessionManager(1), SessionRecorder(1) |
| `KeychainManager.swift` | 1,060 | 7 | Models(16) |
| `SettingsManager.swift` | 1,643 | 7 | Models(48), ICloudSettingsSyncService(18), WindowRecoveryManager(8), KeychainManager(7) |
| `SessionManager.swift` | 894 | 7 | Models(83), SettingsManager(8) |
| `ServerManager.swift` | 948 | 10 | Models(38), KeychainManager(18) |
| `ConnectionManagerView.swift` | 3,734 | 15 | Models(159), KeychainManager(58), ConnectionLibrary(30), TailscaleClient(8) |
| `SFTPBrowserView.swift` | 5,813 | 5 | KeychainManager(55), SFTPRemoteEditorView(18), Models(11), SessionRecorder(8) |
| `TerminalWindowView.swift` | 2,473 | 15 | KeychainManager(41), Models(34), ServerFormViews(8), SessionRecorder(6) |
| `SettingsView.swift` | 1,880 | 13 | KeychainManager(50), Models(31), SettingsManager(13), TailscaleClient(7) |
| `ServerFormViews.swift` | 1,035 | 11 | KeychainManager(35), Models(17), ServerManager(6) |
| `glas_shApp.swift` | 872 | 11 | Models(23), KeychainManager(11), SessionManager(8) |
| `VisionTerminalWorkgroupView.swift` | 712 | 6 | Models(29), KeychainManager(7), TerminalWindowView(5) |
| `PortForwardManager.swift` / `…View.swift` | 1,176 / 399 | 9 / 3 | Models, KeychainManager |
| `SessionRecorder.swift` | 1,306 | 9 | Models(2) |
| `ICloudSettingsSyncService.swift` | 822 | 14 | Models(8) |
| `AIAssistant.swift` | 791 | 10 | KeychainManager(6) |
| `TailscaleClient.swift` | 772 | 9 | KeychainManager(5) |
| others (Constants, Logger, SSHConfigParser, HTMLPreviewWindow, NotificationOverlay, WindowRecoveryManager, TerminalThemeImportService, SFTPRemoteEditorView, SFTPTransferActivity, FocusEnvironmentView, TerminalAudioManager, ConnectionLibrary) | ≤ 300 each | | |

**Hubs by incoming references:** `Models.swift` 553, `KeychainManager.swift` 318, then a long
tail (`SettingsManager` 41, `ConnectionLibrary` 30, `SessionManager` 28).

Plus `Platforms/macOS/` (5,663 lines: `MacWorkspace*`, `MacTerminalOverview`,
`MacTerminalWindowPolicy`, `MacSecureKeyboardEntry`, `SFTPFilePromiseDragSource`) and `glasWidgets`
(250 lines, reads server health from the App Group defaults).

## glassdb — what depends on what

22 flat files plus `Packages/GlassDBKit` (the engine, already a package).

| File | Lines | Declares | Depends on |
|---|---|---|---|
| `TableDetailView.swift` | 5,847 | 45 | AIAssistant(50), RecordEditorView(39), Models(23), QueryEditorView(15), SQLHighlighter(15) |
| `ConnectionFormView.swift` | 1,804 | 8 | Models(29), KeychainManager(18) |
| `Constants.swift` | 1,256 | 28 | DatabaseWorkspaceView(4) |
| `DatabaseDetailView.swift` | 1,244 | 7 | DatabaseSessionManager(7) |
| `ConnectionManagerView.swift` | 1,223 | 3 | ConnectionManager(25), Models(20), KeychainManager(11) |
| `DatabaseWorkspaceView.swift` | 1,206 | 8 | QueryEditorView(19), Constants(11) |
| `QueryEditorView.swift` | 1,197 | 11 | SQLHighlighter(15), DatabaseSessionManager(8) |
| `DatabaseSessionManager.swift` | 1,159 | 11 | Models(10), SQLHighlighter(7), KeychainManager(6) |
| `KeychainManager.swift` | 900 | 14 | Models(14) |
| `SQLHighlighter.swift` | 893 | 8 | — |
| `RecordEditorView.swift` | 822 | 5 | AIAssistant(2) |
| `AIAssistant.swift` | 734 | 13 | SQLHighlighter(3) |
| `SettingsManager.swift` / `SettingsView.swift` | 664 / 579 | 5 / 4 | Constants(39) |
| `SchemaBrowserView.swift`, `GlassEditorAdapters.swift`, `Models.swift`, `ConnectionManager.swift`, `DataExporter.swift`, `ResultsGridView.swift`, `glassdbApp.swift`, `Logger.swift` | 18–659 | | |

**Hubs:** `Models.swift` 132, `Constants.swift` 89, `AIAssistant` 56, `SQLHighlighter` 47,
`DatabaseSessionManager` 42, `KeychainManager` 42.

## What the maps say

1. In both apps the domain model file is the hub and everything else is a leaf or near-leaf. The
   carve is therefore *not* a tangle; it is "model first, then everything".
2. `KeychainManager.swift` in each app is the credential façade over GlasSecretStore, referenced
   from views hundreds of times. In the merged app that façade becomes the shell's credential
   boundary; the views keep calling a façade of the same shape.
3. Each app's `ConnectionManagerView` is its library plus host management. `GlassShell` now owns
   the library; what survives from these files is the endpoint forms and add-flow.
4. `SettingsView`/`SettingsManager` in each app merge into the shell's one settings surface as
   capability pages; the *models* behind them move with the capability.

## Carve — engines first-class, one capability module per app (refined by the user 2026-09-10)

**The user's requirement:** the other capabilities must be able to use the SSH transport, SFTP and
tunnelling as first-class integrations. Therefore the transport is extracted as a shared engine
module in Stage 2 — `GlassSSHTransport` — with a public API built for the terminal, the database
tunnel, the desktop tunnel and the editor's SFTP at once. The single-module simplification below
applies to the capability (UI and session) layer only. Full decision in
[decisions](../../decisions.md).

### The original single-module reasoning, kept for the capability layer

The Stage 1 note said "carve glas.sh into terminal, SFTP, port forwarding, workgroups, SSH
transport". The maps argue for something simpler and safer:

**Move each source application in as ONE module** — `GlassTerminal` (glas.sh), `GlassDatabase`
(glassdb) — keeping every file's `internal` access level intact. Only the handful of types the app
target needs become `public`: the capability registration (`GlassCapability` conformance), the
scene content views, and the settings pages. Finer modules (SFTP, port forwarding) can be extracted
later *inside* the app, where the compiler and tests catch every break.

Why: splitting glas.sh into five modules means making hundreds of types `public` across module
boundaries — visible surgery on 31,000 lines before a single feature works, and exactly the "merge
becomes a rewrite" risk the plan warns about. One module per capability is the smallest change that
draws the shell boundary; it is what glassDT already is (`GlassDesktopCore` + `GlassDesktopUI`).

**Status: proposed.** It changes the Stage 2 wording in the merge plan and needs the user's nod.

## Dependencies to consolidate — measured skew

| Package | glas.sh | glassdb | glassDT |
|---|---|---|---|
| swift-nio | 2.101.3 | 2.100.0 | 2.102.0 |
| swift-crypto | **4.5.1** | **3.15.1** | — |
| swift-collections | 1.6.0 | 1.4.0 | 1.6.0 |
| swift-nio-ssl | — | 2.36.0 | 2.37.4 |
| BigInt | 6.0.0 | 5.7.0 | — |
| SwiftTerm | 1.15.0 | — | — |
| mysql-nio | — | `6948987` (msitarzewski fork) | — |
| postgres-nio | — | 1.33.0 | — |
| Citadel, swift-nio-ssh | vendored copy | vendored copy | — |

One graph resolves each of these once. swift-crypto 3 → 4 is a major bump for glassdb's SSH tunnel
and database drivers. **Checked 2026-09-10 with a throwaway package in the session scratchpad:**
`mysql-nio` at `6948987` and `postgres-nio` (resolved 1.33.1) resolve and build on the macOS host
together with swift-crypto 4.5.2 and swift-nio 2.102.0 (plus nio-ssl 2.37.4, transport-services
1.28.0). Stage 3 is not blocked on dependency resolution; device-platform builds are checked when
`GlassDBKit` moves in.

**The two vendored SSH stacks are not the same code.** `Packages/Citadel` differs in 45 entries
between glas.sh and glassdb and `Packages/swift-nio-ssh` in 52, including source files
(`DH-Helpers.swift`, `DiffieHellmanGroup14Sha1.swift`, `SSHChannelMultiplexer.swift`). Neither copy
has Git history. The `Package.swift` manifests settle which is modern: glas.sh's Citadel requires
swift-nio ≥ 2.101.3, swift-crypto 4.5.1..<5.0.0 and BigInt ≥ 6.0.0; glassdb's requires 2.81.0,
3.12.3 and 5.2.0. 34 Citadel and 40 swift-nio-ssh source files differ — glas.sh's copy was brought
forward for the newer stack. **Stage 2 brings in glas.sh's copy.** Stage 3 builds glassdb's tunnel
against it and reconciles anything glassdb's older copy did differently; diff the two `Sources/`
trees into the Stage 3 note before that work starts.

## Next

Stage 1 lands first. Then, with the user's nod on the one-module carve: Stage 2 begins by creating
`Sources/GlassTerminal` and moving glas.sh's files in verbatim, adding `Packages/Citadel` and
`Packages/swift-nio-ssh` from glas.sh, then making the scene and capability types public and
compiling until green — no behaviour edits until it builds.

## The SSH transport surface, located (read 2026-09-10)

Only four glas.sh files import Citadel or NIO: `Models.swift`, `PortForwardManager.swift`,
`SFTPBrowserView.swift`, `SettingsManager.swift`. Citadel API used, by count: `SSHClient` 17,
`SFTPClient` 16, `SFTPPathComponent` 10, `SFTPFile`/`SFTPFileAttributes` 6 each,
`SSHHostKeyValidator` 4, `NIOSSHPrivateKey` 4, `createDirectTCPIPChannel` 4,
`SSHAuthenticationMethod` 3, `withPTY`/`TTYStdinWriter`/`openSFTP`/`executeCommand` 1 each.

**glas.sh already has a transport abstraction**, in `Models.swift`:
`SSHTransportIdentity` (:1852), `SSHTransportOwnership` (:1890), `SharedSSHTransport` (:1909),
`SSHConnection` (:1937), `SSHError` (:2781) — roughly lines 1852–2842 — plus the trust and auth
model above it: `HostKeyVerificationMode` (:26), `TrustedHostKeyEntry` (:31),
`AuthenticationMethod` (:43), `HostKeyTrustChallenge` (:248), `HostKeyTrustRequiredError` (:266),
`SessionAuthenticationMaterial` (:370), `PreparedServerAuthentication` (:375),
`SessionConnectionPreparation` (:380), `PortForward` / `ForwardType` (:1224), `TunnelStatus`
(:1216). `TerminalSession` (:418–1117) is a consumer of it. `PortForwardManager.swift` (1,176
lines) is the tunnel engine: direct-TCP/IP channels and a full SOCKS5 proxy with a connection
limiter. `SFTPBrowserView.swift` drives `SFTPClient` inline from a 5,813-line view; the SFTP
*service* the editor needs is extracted from there.

**glassdb's consumer contract today** (`GlassDBKit/SSHTunnelManager.swift`, 539 lines):
`SSHTunnelConfig { sshHost, sshPort, sshUsername, sshPassword?, sshPrivateKey?, sshKeyPassphrase?,
remoteHost, remotePort, trustedHostKeys: Set<Data>, algorithmPolicy }` →
`SSHTunnelManager().establish(config) async throws -> SSHTunnel` with `.localPort` and `.close()`,
called from `DatabaseSessionManager.swift:135-186, 307-310`. It carries its own
`SSHHostKeyChallenge` / `SSHHostKeyTrustRequiredError`, duplicating glas.sh's
`HostKeyTrustChallenge`. **It passes raw passwords and private keys as `String`s.**

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

### `GlassSSHTransport` public API — drawn from those consumers (proposal for the Stage 2 brief)

- `SSHEndpoint { host, port, username, jump: [SSHEndpoint] }` and `SSHCredentialReference`
  (a `CredentialID` resolved through GlasSecretStore at connect time — **no raw secret strings
  cross the API**, fixing glassdb's contract).
- `SSHHostTrust` — one challenge type for the whole app, backed by `SSHHostTrustKeychainStore`;
  the caller supplies a `HostTrustDecider` (UI prompt) and never a raw `trustedHostKeys` set.
- `actor SSHTransport` (from `SharedSSHTransport`): `connect()`, shared per host identity,
  reference-counted ownership as today.
- `openShell(pty:) -> SSHShellChannel` (terminal), `openSFTP() -> SFTPSession` (editor and SFTP
  browser: list/stat/read/write/rename/remove with streaming and cancellation),
  `forward(local: port?, to remoteHost:remotePort) -> SSHTunnel { localPort, close() }` (database
  and desktop), remote forwarding and SOCKS5 as today (`PortForwardManager` moves in whole).
- Tests: state machine and trust decisions as unit tests; a real-server integration suite gated on
  an environment variable naming a host the user owns, recorded as not run when absent.

`GlassTerminal` keeps `TerminalSession`, recording, workgroups and every view; it imports
`GlassSSHTransport`. `GlassDatabase` replaces `SSHTunnelManager` with `forward`. The desktop
capability's VNC-over-SSH in Stage 5 is the same call.
