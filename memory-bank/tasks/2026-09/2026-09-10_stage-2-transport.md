# Stage 2 — W1: GlassSSHTransport engine

Worker `stage2-transport`. 2026-09-10. **Status: built, unit-verified on macOS, builds for iOS and
visionOS simulators; real-host suite written and gated, blocked from running in this session by
macOS Local Network privacy (evidence below). Not committed (coordinator commits).**

## What moved, from where

| Engine file | From glas.sh | Notes |
|---|---|---|
| `SSHEndpoint.swift` — `SSHEndpoint`, `SSHConnectionOptions`, `SSHHop`, `SSHRoute`, `SSHTransportIdentity`, `SSHTransportOwnership` | `Models.swift:1852-1907` (`SSHTransportIdentity`, `SSHTransportOwnership`), `normalizedHost` at `:2727` | Identity now hashes the hop values instead of reading `ServerConfiguration`; ownership verbatim plus `forceClose()` |
| `SSHCredentials.swift` — `SSHCredentialReference`, `SSHResolvedCredential`, `SSHCredentialResolver`, `SecretStoreCredentialResolver`, `SSHAuthenticationBuilder` | `Models.swift:2010-2075` (`resolveAuthMethod`, both Secure Enclave encodings, RSA/Ed25519 detection); `KeychainManager.swift:523,606` | Credentials are references resolved inside the engine; no raw strings in the API. glassdb's `SSHTunnelConfig` (raw password/key strings) deliberately not ported |
| `SSHHostTrust.swift` — `SSHHostTrustPolicy`, `SSHHostTrustChallenge`, `SSHHostTrustRequiredError`, `SSHHostTrustDecision`, `SSHHostTrustDecider`, `SSHHostTrustStore`, `SecretStoreHostTrustStore`, `InMemoryHostTrustStore`, `SSHHostTrustEvaluator`, internal `SSHHostKeyChallengeBox`, `SSHPromptingHostKeyValidator` | `Models.swift:26-31` (`HostKeyVerificationMode`), `:243-268` (challenge, reason, required error), `:270-368` (challenge box, validator) | One challenge type for the app; trust arithmetic separated from NIO into `SSHHostTrustEvaluator` so it is unit-testable; pinning through `SSHHostTrustKeychainStore.save`/`replace` |
| `SSHTransportError.swift` | `Models.swift:2781-2830` (`SSHError`), `:2615-2700` (`userFacingMessage`), `:2735-2760` (kex-failure, legacy-retry, channel-closed helpers), `PortForwardManager.swift:1165` (bind error text) | Renamed `SSHTransportError`; adds `hostTrustRequired/Rejected`, `credentialUnavailable`, `tunnelBindFailed`, `cancelled`, `sftpUnavailable` |
| `SSHTransport.swift` — `actor SSHTransport`, `SSHConnectionStage`, `SSHTransportEvent` | `Models.swift:1909-1935` (`SharedSSHTransport`), `:1937-2320` (connection half of `SSHConnection`: direct + jump-chain connect, legacy-algorithm retry, keep-alive at `:2570`, `executeRemoteCommand`, `openSFTPClient`, `createDirectTCPIPChannel`, `runRemotePortForward`, `disconnect`) | Progress lines and `TerminalSession` calls became `events`; trust challenge → decider loop inside `connect()`; `UserDefaults` reads became `SSHRoute.trustPolicy` / `SSHConnectionOptions` |
| `SSHShellChannel.swift` — `SSHPTYRequest`, `SSHShellOutput`, `SSHShellExit`, `actor SSHShellChannel` | `Models.swift:2320-2420` (`runInteractiveTTY`, PTY request, env merge, TTY-ready continuation, clean-exit classification), `:2425-2460` (`sendInput`/`sendBytes`), `:2600` (`resizeTerminal`) | Output is an `AsyncStream`; exit reason recorded once; keep-alive counter reset on every chunk as before |
| `SFTPSession.swift` — `SFTPAttributes`, `SFTPEntry`, `SFTPOpenMode`, `SFTPFileHandle`, `SFTPSession` (+ `readFile`/`writeFile`), internal `CitadelSFTPSession`, `CitadelSFTPFileHandle` | The `SFTPClient` calls inline in `SFTPBrowserView.swift` (`listDirectory` ×8, `openFile` ×5, `remove` ×5, `rename` ×4, `createDirectory` ×3, `setAttributes`, `getAttributes`, 262 144-byte chunking at `:3939`) and `openSFTPClient` at `Models.swift:2463` | Consumers see no Citadel types; the browser's operations map one-to-one |
| `SOCKS5.swift` | `PortForwardManager.swift:16-80` (types, limiter, permit), `:775-960` (credential policy, constant-time compare, three parsers, reply) | Verbatim, namespaced under `SOCKS5Protocol`; public for tests and for the port-forwarding UI |
| `SSHTunnels.swift` — `SSHDirectChannelProvider`, `SSHTunnel`, `SSHRemoteForward`, internal `SSHTunnelChildRegistry`, `SSHTunnelFactory` | `PortForwardManager.swift:86-160` (child registry), `:330-445` (local listener), `:445-500` (pipe), `:505-560` (remote forward), `:600-700` (SOCKS5 listener), `:965-1080` (SOCKS5 handler), `:1083-1160` (stop/wait) | Per-forward `Task`/listener/registry bookkeeping became one `SSHTunnel` object per forward; the `PortForward` rows, statuses and per-session dictionaries stay with the terminal UI (W2) |
| `SSHTransportPool.swift` | The transport-sharing behaviour of `SSHConnection.shareTransport`/`canShareTransport` (`Models.swift:1960-1975`) | A pool keyed by identity with owner counting |

`Packages/Citadel` and `Packages/swift-nio-ssh` copied verbatim from `../glas.sh/Packages/`
(`Sources`, `Tests`, `Package.swift`, `Package.resolved`, docs; excluded `build`, `.build`,
`.swiftpm/xcode/xcuserdata`, `Examples`). `diff -rq` on `Sources/`: 0 differences each.

**Not moved (terminal-owned, W2):** `TerminalSession`, `SessionState`, `ConnectionProgressStage`
→ UI mapping of `SSHTransportEvent`, auto-reconnect policy, recording, `PortForward` rows and
`PortForwardManager`'s per-session state, the SFTP browser and its transfer bookkeeping, agent
forwarding UI (the engine reports `.agent` as unavailable exactly as glas.sh did).

## One fix made while moving

`NIOAsyncChannel(wrappingChannelSynchronously:)` must run on the channel's event loop
(`NIOCore/AsyncChannel.swift:110` precondition). glas.sh's `handleLocalConnection` and
`handleSOCKS5Connection` wrap the SSH channel from an arbitrary task; under the vendored
swift-nio 2.102 that trapped in the unit tests. `SSHTunnelFactory.wrap` hops to the loop with
`eventLoop.submit`. W2 should expect the same trap if any moved terminal code wraps channels
off-loop.

## Renames (collision avoidance and prefixing)

| glas.sh | Engine |
|---|---|
| `HostKeyVerificationMode` | `SSHHostTrustPolicy` |
| `HostKeyTrustChallenge` / `HostKeyChallengeReason` / `HostKeyTrustRequiredError` | `SSHHostTrustChallenge` / `SSHHostTrustReason` / `SSHHostTrustRequiredError` |
| `HostKeyChallengeBox` / `PromptingHostKeyValidator` | `SSHHostKeyChallengeBox` / `SSHPromptingHostKeyValidator` (internal) |
| `SSHError` | `SSHTransportError` |
| `SharedSSHTransport` + `SSHConnection` | `SSHTransport` |
| `PortForwardChildChannelRegistry` | `SSHTunnelChildRegistry` (internal) |
| `PortForwardManager.parseSOCKS5*` etc. | `SOCKS5Protocol.*` |
| `SessionAuthenticationMaterial` / `PreparedServerAuthentication` / `SessionConnectionPreparation` | `SSHResolvedCredential` + `SSHCredentialResolver` (preparation is the resolver's job) |

## Public API as implemented

48 public types, ~2,250 lines. Signatures as messaged to the coordinator ("API surface landed"):
`SSHEndpoint(host:port:username:)`, `SSHConnectionOptions(allowLegacyAlgorithms:forwardAgent:keepAliveInterval:keepAliveMaxMissed:terminalType:environment:)`,
`SSHHop(recordID:displayName:endpoint:credential:options:)`, `SSHRoute(target:jumps:trustPolicy:)`,
`SSHCredentialReference {.password(profileID:), .privateKey(keyID:), .agent, .custom(String)}`,
`SecretStoreCredentialResolver(configuration:passwordLocations:)`,
`SSHTransport(route:secrets:trustDecider:)` / `(route:credentials:trustStore:trustDecider:)` with
`events`, `connect()`, `acquire(owner:)`, `release(owner:)`, `close()`, `openShell(pty:)`,
`execute(_:maxResponseBytes:)`, `openSFTP()`, `openDirectChannel(toHost:port:)`,
`forward(localPort:toHost:port:)`, `socks5(localPort:credentials:)`,
`remoteForward(remoteHost:remotePort:toLocalHost:localPort:)`; `SSHShellChannel` (`output`,
`exit`, `write`, `sendCommand`, `resize`, `close`); `SFTPSession` protocol + `readFile`/`writeFile`;
`SSHTunnel`, `SSHRemoteForward`, `SOCKS5Credentials`, `SSHTransportPool`. No SwiftUI, no
`GlassShell`/`GlassLayers` import; `GlassConnectionKit` only for `CredentialID` bridging.

## Verification

| Check | Result |
|---|---|
| `swift build --target GlassSSHTransport` | Build complete, **0 warnings** in the target, no `notImplemented`/`TODO`/`fatalError`/`try!`/`as!` |
| `xcodebuild -scheme GlassSSHTransport`, iOS Simulator (iPhone 17 Pro Max, iOS 27.0) | **BUILD SUCCEEDED**, 0 warnings in the target |
| `xcodebuild -scheme GlassSSHTransport`, visionOS Simulator (Apple Vision Pro, OS 27.0) | **BUILD SUCCEEDED**, 0 warnings in the target |
| Unit tests, macOS host: SOCKS5 protocol 7, ownership/identity 6, host trust 7, credentials 5, tunnels 6, first-class consumers 4, gated suite 5 (not-run paths) | **40 tests in 7 suites passed**, three consecutive runs |
| Real-host suite (`GPT_SSH_TEST_HOST=192.0.2.6`, user `michael`, key `~/.ssh/scratch_vm`) | **Not run — blocked by macOS Local Network privacy in this session.** All five tests fail at TCP connect with `errno 65 No route to host`. Evidence: `nc -z 192.0.2.6 22` succeeds and `ssh … 'echo ok; uname -sr'` returns `ok` / `Linux 7.0.0-29-generic` from the same shell (Apple-signed tools are exempt), while an ad-hoc-signed Swift binary doing a plain BSD `connect()` to `192.0.2.6:22` gets `errno 65` and the same binary reaches `127.0.0.1:22` and reads `SSH-2.0-OpenSSH_`. The VM is on `bridge100` (a local network); no TCC prompt can be answered from this session. |

**How the package tests were run.** `swift test` at the repository root cannot run yet: SwiftPM
links every test target into one bundle and W2's `GlassTerminal` is mid-move (its own
compile errors, e.g. `ServerManager.familyDeletionOutbox`); additionally SwiftPM's default
swiftbuild backend fails on SwiftTerm's `Shaders.metal` via the stub `metal`, which
`--build-system native` avoids. I ran the engine's tests from a throwaway runner package in the
session scratchpad (`transport-runner/Package.swift` depending on the `GlassSSHTransport` product
by path with `Tests` symlinked to `Tests/GlassSSHTransportTests`). Once `GlassTerminal` compiles,
`swift test --build-system native --filter GlassSSHTransportTests` at the root is the command.

**To run the real-host suite** (from a terminal whose app has the Local Network grant, e.g. after
System Settings → Privacy & Security → Local Network for the terminal, or Terminal.app):
`GPT_SSH_TEST_HOST=192.0.2.6 GPT_SSH_TEST_USER=michael GPT_SSH_TEST_KEY_PATH=$HOME/.ssh/scratch_vm swift test --build-system native --filter SSHTransportIntegrationTests`.
The suite is read-only apart from a `/tmp/glasspowertools-transport-<uuid>` directory it creates
and removes; it trusts the host key for the run only and records nothing.

## First-class proof

`Tests/GlassSSHTransportTests/FirstClassConsumerTests.swift` defines `DatabaseTunnelConsumer`
(uses `forward`) and `EditorSFTPConsumer` (uses `SFTPSession` read/write) without importing
`GlassTerminal`. They pass against a TCP provider and an in-memory SFTP session; the gated suite
runs the same two consumers against the real transport (`tunnelReachesTheHostsOwnSSHPort`,
`sftpListsAndRoundTripsInATemporaryDirectory`).

## Resolved dependency versions (root `Package.resolved`, after adding the engine)

swift-nio 2.102.0, swift-crypto 4.5.2, swift-log 1.15.1, BigInt 6.0.1, swift-atomics 1.3.1,
swift-collections 1.6.0, swift-system 1.8.1, swift-asn1 1.7.2; unchanged from GlassEditorKit:
SwiftTreeSitter 0.25.0, tree-sitter 0.25.10; W2 added SwiftTerm 1.15.0. Citadel requires
swift-crypto 4.5.1..<5.0.0 and swift-nio ≥ 2.101.3 — no conflict with GlassEditorKit (tree-sitter
grammars only). One graph, one copy of each.

## Addendum — SFTP server extensions and file times (coordinator request, after `6e5ffe6`)

W2 found the SFTP browser taking the hardlink / posix-rename / fsync fallback paths
unconditionally and having no way to set file times. Both were Citadel capabilities the engine had
not surfaced (`SFTPClient.serverExtensions` / `supportsExtension` at `SFTPClient.swift:82-100`,
`hardLink` `:587`, `posixRename` `:613`, `SFTPFile.synchronize` `SFTPFile.swift:322`;
`SFTPFileAttributes.accessModificationTime` sets the `acmodtime` flag automatically,
`SFTPFileFlags.swift:94-118`). Moved through, not reimplemented:

- `public struct SFTPServerExtensions` — `raw: [String: String]`, `version(of:)`,
  `supports(_:version:)`, `supportsPOSIXRename` / `supportsHardLink` / `supportsFSync` (exact
  version "1", the OpenSSH contract), name constants `posixRename`, `hardLink`, `fsync`.
- `SFTPSession` gained `var serverExtensions: SFTPServerExtensions { get async }`,
  `posixRename(_:to:)`, `hardLink(_:to:)`, and `setAttributes(_ changes: SFTPAttributeChanges, at:)`
  as the requirement; `setPermissions(_:at:)` is now a convenience over it, joined by
  `setTimes(at:accessed:modified:)` (fills the missing side from the file, because SFTP v3 sends
  the pair) and `replace(_:with:)` (posix-rename when advertised, else remove + rename — the
  decision the browser made by hand).
- `public struct SFTPAttributeChanges { permissions?, size?, accessed?, modified? }`; a lone time
  is refused with `SFTPSessionError.partialTimes`.
- `SFTPFileHandle` gained `synchronize()`.
- Citadel's `SFTPError.unsupportedExtension(name)` maps to `SFTPSessionError.extensionUnsupported(name)`.

Tests: `SFTPExtensionsAndTimesTests` (5) — name/version queries, flag derivation, `setTimes`
fill-in and partial refusal, `setPermissions` convenience, consumer choice with and without the
extensions (fake session records which path ran). The gated real-host test now also checks that
OpenSSH advertises extensions, round-trips times and permissions, and exercises `replace` and
`synchronize` where advertised. **Unit: 45 tests in 8 suites passed** (two consecutive runs);
visionOS Simulator build succeeded, 0 warnings. Real host still blocked by the Local Network
grant (same `errno 65`).

## Addendum 2 — W2 backlog items and the engine security review (after the SFTP commit)

**W2 backlog (both taken).** `SSHTransport.execute(_:maxResponseBytes:timeout:)` gained the
one-hour timeout glas.sh had (`executeRemoteCommand`, Models.swift:2470) via Citadel's timed
overload. `SSHPublicKeys` (new file) moves `SettingsManager.openSSHPublicKey(for:)`
(SettingsManager.swift:807-846) into the engine: `openSSHLine(for:comment:)`, `algorithm(for:)`,
`sha256Fingerprint(for:)` over `SSHKeyMaterial`, so the capability drops its Citadel/NIOSSH
imports. Tests use three throwaway `ssh-keygen` fixtures and assert equality with what ssh-keygen
wrote to the `.pub` files (Ed25519, RSA-2048, passphrase-protected Ed25519), a legacy-wrapped P256
payload, the OpenSSH fingerprint format, and refusal of garbage without echoing it.

**Security review (`2026-09-10_stage-2-security-review.md`): no High/Medium; five Low and the
cheap Info items fixed, one Info documented.**

| # | Fix | Test |
|---|---|---|
| S1 | `execute` defaults to `SSHTransport.defaultMaximumResponseBytes` = 8 MiB; larger limits are explicit | bound asserted |
| S2 | Pool records the fresh transport in the map before any suspension and treats a connecting (not closing) transport as reusable; a closing one is replaced | 16 concurrent first requests → 1 construction, 16 owners; closing transport replaced |
| S3 | `connect()` keeps the in-flight attempt as a `Task` and later callers await it | 3 concurrent connects to a refusing port: none gets `connectionFailed` |
| S4 | `SSHEngineAlgorithms.registerHostKeyAlgorithmsOnce` registers RSA host keys (`rsa-sha2-512` signatures, `RSA.swift:143`) at engine load; the per-hop legacy option now uses `SSHEngineAlgorithms.legacy` = SHA-1/SHA-256 group-14 KEX + AES-128-CTR only, per connection, no registry side effects | legacy set registers no public-key algorithms; option off by default |
| S5 | `SFTPEntry.hasSafeName` / `SFTPEntry.isSafeName(_:)` — non-empty, not `.`/`..`, no `/`, no NUL; documented consumer obligation before local writes or path joins | seven name cases |
| S8 | `recordMissedKeepAlive` and `lostConnection` guard on `isClosing`; `lostConnection` only tears down when `forceClose()` flips | double `close()` yields exactly `[.closed]` |
| S9 | Transport tracks its `SSHRemoteForward`s and closes them in `teardown`; forwards report closure once via `onClosed`; `remoteForwardCount` for diagnostics | forward closes once, reports once |
| S10 | `SSHTransportError.invalidHostKey`; `SecretStoreHostTrustStore.pin` throws it for an undecodable blob | asserted, with its description |
| S7 | **Not taken.** Citadel's `SSHClientSettings.authenticationMethod` is a synchronous, non-throwing closure, so Keychain resolution (async, throwing, may prompt) cannot move inside it without changing Citadel. NIOSSH sends nothing before KEX and host-key validation succeed, so there is no leak; only prompt ordering | — |
| S6 | **Recorded limit:** resolved passwords and private keys become Swift `String`s for Citadel's `SSHAuthenticationMethod`; those copies are not zeroed and live as long as the method. `SecureBytes` protects the store→builder hop only. Inherent to Citadel's API | — |

W2/W3 note from the review, not mine: glas.sh's per-server legacy toggle has no warning text; add
the persistent warning the July audit asked for.

**Verification after these changes:** unit **60 tests in 10 suites passed** (two consecutive runs);
visionOS Simulator build **succeeded, 0 warnings**; scaffold sweep clean. Real host unchanged
(Local Network grant still absent).

**Header-only key classification (W2 request, after the above).** `SSHPublicKeys.declaredKeyType(inOpenSSHPrivateKey:)` and `declaredKeyType(in: SSHKeyMaterial)` return an engine `SSHDeclaredKeyType` (rsa, ed25519, ecdsaP256/384/521 with `displayName` and `isSupportedForAuthentication`) by reading only the OpenSSH header through Citadel's `SSHKeyDetection.detectPrivateKeyType`; errors are `SSHKeyHeaderError`. Import forms classify a key — including a passphrase-protected or body-corrupted one — without decoding it, which is what full derivation (`algorithm(for:)`) cannot do. Test: header-valid/body-corrupted fixture classifies as ed25519 while `openSSHLine` refuses it. Unit total now **61 tests in 10 suites**.

## Open items

- Real-host results are pending the Local Network grant; nothing in the code path is untested
  except the Citadel-backed implementations themselves (`connect`, PTY, SFTP, direct-tcpip,
  remote forward), which the gated suite covers.
- `SSHConnectionOptions.forwardAgent` is carried for identity only; agent auth and forwarding
  remain unavailable, as in glas.sh.
- `Packages/Citadel/Package.resolved` may be rewritten by builds; the copied `Sources` are what
  matters and are verbatim.
- W2: map `SSHTransportEvent` to `ConnectionProgressStage`, keep auto-reconnect and recording in
  the terminal, pass glas.sh's password location list through `SecretStoreCredentialResolver`,
  and expect the on-loop `NIOAsyncChannel` requirement noted above.
