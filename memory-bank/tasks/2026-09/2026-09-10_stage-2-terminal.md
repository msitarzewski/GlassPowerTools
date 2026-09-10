# Stage 2 — W2: glas.sh moved in as the `GlassTerminal` capability

Worker W2. 2026-09-10. **Status: built and unit-tested on all three platforms; not committed
(coordinator commits); parity validation against a real host not run by this worker.**

## What moved (verbatim unless listed under "changed")

| Into | From | Count |
|---|---|---|
| `Sources/GlassTerminal/*.swift` | `../glas.sh/glas.sh/*.swift` (30 files, 31,393 lines) | 30 + 5 new files, 30,755 lines |
| `Sources/GlassTerminal/macOS/*.swift` | `../glas.sh/Platforms/macOS/*.swift`, each wrapped in `#if os(macOS)` (SwiftPM has no per-file platform filter) | 9 files, 5,690 lines |
| `Sources/GlassTerminalEmulator/` | `../glas.sh/Packages/RealityKitContent/Sources` — **misnamed**: it is `SwiftTermHostView.swift` + `TerminalEmulator.swift`, the SwiftTerm host, with no rkassets; its 1.3 GB `build/` was not copied. Module renamed; 8 `import RealityKitContent` lines became `import GlassTerminalEmulator` | 4,214 lines |
| `Widgets/` | `../glas.sh/glasWidgets` (sources, `Info.plist`, entitlements, `PrivacyInfo.xcprivacy`) | 250 lines |
| `Tests/GlassTerminalTests/` | `../glas.sh/glas.shTests` (`@testable import glas_sh` → `GlassTerminal`; macOS file guarded) | 11,553 lines active |

Not moved: `glas.sh/Assets.xcassets` (app icons/accent — the app target has its own),
`terminal_bell.caf` (unreferenced; the bell is `AudioServicesPlaySystemSound(1007)`),
`PrivacyInfo.xcprivacy` of the app (app-level), `README.md`.

## Package and project

- `Package.swift`: targets `GlassTerminalEmulator` (SwiftTerm 1.15.0 exact, as glas.sh pinned) and
  `GlassTerminal` (depends on `GlassSSHTransport`, `GlassShell`, `GlassLayers`, the kit products,
  `GlasSecretStore`, `GlassEditorKit` — glas.sh's SFTP remote editor already uses `GlassEditorUI`, so
  D6's "wait for Stage 5" is overtaken by parity — SwiftTerm, and, for the reasons below, Citadel/
  NIO products); test target `GlassTerminalTests`.
- **Approachable concurrency, expressed for SwiftPM.** glas.sh builds with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (it never
  set `SWIFT_STRICT_CONCURRENCY = complete`). The module and its tests use
  `.defaultIsolation(MainActor.self)` + `InferIsolatedConformances` + `NonisolatedNonsendingByDefault`
  + `MemberImportVisibility`. Without these the same code produced Swift 6 isolation errors.
- `GlassPowerTools.xcodeproj` (hand-authored, same id style): the app target now links the
  `GlassTerminal` product; new target **`GlassPowerToolsWidgets`** (`com.glasspowertools.widgets`,
  WidgetKit extension, App Group `group.sh.glas.shared`, iOS + visionOS) embedded on iOS and
  visionOS only via `platformFilters = (ios, xros)` exactly as glas.sh embeds `glasWidgets`.
  Verified in the built products: `PlugIns/GlassPowerToolsWidgets.appex` present on iOS and
  visionOS, absent on macOS.

## The transport boundary — what was cut and what replaced it

Removed from `Models.swift` (3,252 → 2,174 lines): `SSHTransportIdentity`, `SSHTransportOwnership`,
`SharedSSHTransport`, `SSHConnection` (the Citadel client, jump chain, PTY, keep-alive),
`HostKeyChallengeBox`, `PromptingHostKeyValidator`. `PortForwardManager.swift` (1,176 → 374): the
NIO listeners, direct-tcpip relay, child-channel registry and the whole SOCKS5 server are gone.

New `SSHConnection.swift` (535 lines): an adapter over `GlassSSHTransport.SSHTransport` /
`SSHShellChannel` that **keeps every call-site signature** `TerminalSession`, `SessionManager`, the
SFTP browser and the port-forwarding manager used (`connect(preparation:jumpHostChain:)`,
`sendBytes`, `resizeTerminal`, `executeRemoteCommand`, `createDirectTCPIPChannel`,
`runRemotePortForward`, `disconnect`, `hasReusableTransport`, `canShareTransport`,
`shareTransport(from:)`, `takePendingHostKeyChallenge`, `setPreferredTerminalSize`). Moved verbatim
into it: `SSHError`, `userFacingMessage(for:server:)`, `normalizedHost`, `isChannelClosedError`,
`isKeyExchangeNegotiationFailure`. Terminal-side glue, as briefed: engine events →
`ConnectionProgressStage` / terminal lines, `.lost` → `reportError` + `attemptAutoReconnect`,
shell exit → `handleCleanRemoteExit`, the trust prompt, purpose, recording.

Credentials: `PreparedCredentialResolver: SSHCredentialResolver` hands glas.sh's already-resolved
`SessionAuthenticationMaterial` (from `SessionManager.prepareConnection`, which still drives the
password-prompt UX and transient sessions) to the engine as `SecureBytes` / `SSHKeyMaterial`. No
secret crosses as a `String`. Trust: `TerminalHostTrustDecider` stores the engine's challenge and
answers `.reject`, so glas.sh's flow (surface challenge → user pins → reconnect) is unchanged;
`SSHTransportError.hostTrustRequired/Rejected` is mapped to `HostKeyTrustRequiredError` for
`TerminalSession`'s existing catch. Trust policy `.strict` follows the verification-mode setting.

### Call sites whose semantics changed (reported, as briefed)

| Site | Change |
|---|---|
| `shareTransport(from:)` (SessionManager:397, :432) | Now `async` — the engine's ownership is actor-isolated. Both callers were already in async functions; `await` added. |
| `executeRemoteCommand(_:maxResponseBytes:executionTimeout:)` | The engine's `execute` has no timeout parameter; `executionTimeout` is accepted and ignored. **Open item for W1**: expose a timeout. |
| `runRemotePortForward` | Same contract (runs until the forward closes, `onOpen(boundPort)`), now `remoteForward` + `boundPort()` + `waitUntilClosed()`. |
| `resetKeepAliveCounter()` | Keep-alive is the engine's; retained as a no-op for callers. |
| `hasReusableTransport` / `canShareTransport` | Backed by an `isTransportConnected` flag driven by engine events instead of `client.isConnected`. |
| Port forwards | `startLocalForward` → `connection.forward(...)`, `startDynamicForward` → `connection.socks5(...)`; the manager keeps registry, attempt generations, SOCKS5 credentials (now `SOCKS5Credentials`), status and `userFacingBindError`. `stopAllForwardsAndWait` closes `SSHTunnel`s. |
| SFTP browser | `openSFTPClient()` returns a **terminal-internal, Citadel-shaped shim** (`SFTPCompatibility.swift`: `SFTPClient`, `SFTPFile`, `SFTPPathComponent`, `SFTPFileAttributes`, `SFTPFileType`, `SFTPError`, `SFTPOpenFileFlags` = engine `SFTPOpenMode`) over `SFTPSession` / `SFTPFileHandle`. The 5,813-line browser is byte-identical except the dropped `import Citadel` and an added `import GlassSSHTransport`. After W1's extension (`serverExtensions`, `posixRename`, `hardLink`, `setAttributes` with times, `synchronize`) the shim routes those honestly; `serverExtensions` is read once at client creation because the browser asks synchronously. Pipelined reads (`read(_ requests:)`) are issued concurrently in a task group and returned in order. |

Engine dependencies still imported by `GlassTerminal`: `NIOCore` (`Channel`, `TimeAmount`,
`ByteBuffer` in the browser and shim), `NIOSSH` in `SSHConnection.swift` (for
`NIOSSHError` in the verbatim `isKeyExchangeNegotiationFailure`) and in **`SettingsManager.swift`**
together with Citadel (`NIOSSHPrivateKey`/`Insecure.RSA` to derive public keys for display/export —
key management, not transport). **Seam for W1**: a `publicKey(for: SSHKeyMaterial)` utility would
let `SettingsManager` drop Citadel.

## Shell integration

- `GlassTerminalCapability: GlassCapability` (`kind: .ssh`). `open(service:host:)`: if a saved
  `ServerConfiguration` exists with `id == service.endpointID.rawValue` → connect; otherwise the
  bootstrap presents glas.sh's `AddServerView` with a draft whose **id is the shell's endpoint id**
  (one-line change in `ServerFormView`'s add path: `id: draft?.id ?? UUID()`), so saving the form
  is the link. No `GlassCapability` hook was needed for this; a `makeServiceEditor(host:)` hook
  would only make it inline instead of a sheet.
- `GlassTerminalRuntime` owns `SessionManager`, `SettingsManager`, `WindowRecoveryManager`; the
  app registers the capability and passes the runtime to `GlassTerminalBootstrap` (wrapping the
  shell's library) and `GlassTerminalScenes`.
- `GlassTerminalBootstrap` = glas.sh's `MainBootstrapView` made generic over its content (state
  load, deep links, trust alerts; `ConnectionManagerView()` → `content`) + `TerminalConnectFlow`
  (the connect flow moved **verbatim** out of `ConnectionManagerView`: legacy-algorithm
  confirmation, trust prompt gated on the verification mode, password-prompt fallback via
  `ConnectionPasswordPromptSheet`, terminal/SFTP purpose, per-platform presentation) + the iPhone
  router (`IOSAppRoot`'s switch between library, live workgroup and SFTP sheet) + the setup sheet.
- `GlassTerminalScenes: Scene` = `glas_shApp.swift:99-280` minus the Connections window and
  Settings, which the shell owns (`workspace`, `sftp`, `port-forwarding`, `html-preview` on macOS;
  `terminal`, `minimized`, `html-preview`, `sftp`, `port-forwarding`, `focus-environment` on
  visionOS). `MacTerminalAppDelegate` made public so the app's `NSApplicationDelegateAdaptor`
  keeps glas.sh's quit confirmation; `runtime.attach(to:)` wires it.
- Removed as three-process machinery: `ServerManager`'s `HostCatalogDeletionOutbox` (and
  `import GlassHostCatalog`), `ConnectionManagerView`'s `publishFamilyHosts` / `HostPublication`
  block, the `@main` App struct and `IOSAppRoot`.

**Kept compiling but unreferenced (seams for the coordinator / W3):** `ConnectionManagerView.swift`
(3,697 lines) and `ConnectionLibrary.swift` — the shell's library replaces the list, but three
terminal features still live only there and need a home: **workgroup-preset launching**
(`openVisionWorkgroup`, `LayoutRestorationPlan`, substitution review), **Tailscale network mode
and quick connect**, and the Mac **local terminal** entry. Server **edit/delete** actions also
still live there (a per-service detail hook in the shell would surface them).

## Layering proof (Stage 2)

Not done by this worker beyond compiling: the SSH connection panel / terminal chrome are not yet
wrapped in `GlassLayeredWindow` / `GlassLayeredPanel`. glas.sh's terminal window has its own
material handling (`TerminalWindowView`, `MacTerminalWindowPolicy` — the family titlebar sequence
`GlassLayers` already reproduces). Open item for the integration pass, listed below.

## Settings / shell services seams for W3

`SettingsView` (1,880), `SettingsManager` (1,643), `ICloudSettingsSyncService` (822),
`WindowRecoveryManager` (161) moved and compile inside `GlassTerminal`. Nothing declares a second
Settings scene; glas.sh's settings pages are not yet shown anywhere in the merged app. W3: expose
`SettingsView`'s pages as `GlassShellSettingsView` pages; move sync and recovery to the shell.

## Tests

- `swift test --build-system native --filter GlassTerminalTests` (the default swiftbuild backend
  fails on SwiftTerm's Metal shader because the Metal Toolchain component is not installed;
  `xcodebuild` is unaffected): **338 tests in 3 suites, 337 passed, 1 failed**.
  - Failing: `localSSHSubstitutionIsDeviceLocalAndInvalidatedWhenSourceChanges`
    (`glas_shTests.swift:579`): expects the substitution's `startupCommand` to be the multi-line
    `cd -- … && {\npwd\n}`; the value is normalised through `TerminalStartupCommandTicket`. The test
    and the code under it are byte-identical to glas.sh. Probe: running this exact test inside `../glas.sh` (`xcodebuild test -only-testing`, derived data in
    the session scratchpad, sibling untouched) could not confirm or refute it — glas.sh's own test
    target **does not compile at HEAD on Xcode 27.0** (`glas_shTests.swift:129`
    `followSidebarBoundary()` needs `import GlassConnectionUI` under MemberImportVisibility, the
    same fix applied in the moved copy). Nothing in the substitution path (`WorkgroupSSHSubstitution`,
    `SessionIntent`, `TerminalStartupCommandTicket`, `SettingsManager`) was changed by the move.
    Treat as inherited until glas.sh's suite is green again (the user notes an unmerged PR there).
- **Set aside, not deleted** — `Tests/GlassTerminalTests/Disabled-transport-era-tests.swift.txt`
  (432 lines, not compiled): 16 functions from `glas_shTests.swift` and 1 from
  `MacWorkspaceTests.swift` that test internals now owned by the engine — SOCKS5 greeting/
  authentication/limiter/permit/connect parsing (7), `SharedSSHTransport` ownership and identity
  (2), PTY terminal modes (1), key-exchange retry (1), the host-key validator's event-loop
  behaviour (1), and four SFTP browser helper tests written against Citadel's value types (outline
  duplicates, batch operations, table sorting, download read batches, v3 stat). Their coverage
  belongs in `GlassSSHTransportTests`; the four browser-helper tests should be rewritten against
  `SFTPCompatibility` (they test terminal code).
- Adapted, not disabled: three `MainBootstrapView.sameDeepLinkSecurityIdentity` calls →
  `MainBootstrapView<EmptyView>`; the macOS test file's `import RealityKitContent`.

## Builds (actual)

| Target | macOS | iOS Simulator (iPhone 17 Pro Max, 27.0) | visionOS Simulator (Vision Pro, 27.0) |
|---|---|---|---|
| `GlassTerminal` scheme | BUILD SUCCEEDED | BUILD SUCCEEDED | BUILD SUCCEEDED |
| `GlassPowerTools` app (+ widgets) | BUILD SUCCEEDED (`noKVS.xcconfig`) | BUILD SUCCEEDED | BUILD SUCCEEDED |
| whole package, `swift build --build-system native` | Build complete | — | — |

Not run: the UI test target (per brief), any real-host session, any device.

## Open items

1. Integration pass: connect to a real host through the shell (Add Host → Add a service → SSH →
   form → Connect); terminal I/O, resize, SFTP browse/transfer, local/dynamic/remote forwards over
   the engine — none exercised yet.
2. Wrap the SSH connection panel and terminal window in `GlassLayers` (Stage 2 layering proof).
3. Re-home workgroup presets, Tailscale network mode, local terminal, server edit/delete (above).
4. W3: settings pages, iCloud sync, window recovery into the shell.
5. W1 backlog: `execute` timeout; public-key derivation utility so `SettingsManager` drops Citadel.
6. Rewrite the four browser-helper tests against the shim; move the transport-internal tests'
   intent to `GlassSSHTransportTests` if not already covered.
7. Not mine, noticed in the tree: `Platforms/macOS/Info.plist` shows modified and
   `memory-bank/tasks/2026-09/2026-09-10_stage-2-security-review.md` is untracked.
