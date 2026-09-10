# Stage 2 security review — GlassSSHTransport and the two carried audit items

Reviewer: security fork, read-only. Reviewed commit `6e5ffe6` (`Sources/GlassSSHTransport`, 11
files, 2,249 lines; `Packages/Citadel`, `Packages/swift-nio-ssh`). Scope B read
`../glas.sh/glas.sh/SessionRecorder.swift`, `AIAssistant.swift`, `SFTPBrowserView.swift`,
`Models.swift:835-870`, `TerminalWindowView.swift`, and W2's moved copies in
`Sources/GlassTerminal` as they stood on disk (34 files present at review time; the three Scope B
files were byte-identical to glas.sh except `SFTPBrowserView.swift`, 2 changed lines). No code
edited.

## Findings

| # | Sev | Status | Where | Finding | Why it matters | Fix |
|---|---|---|---|---|---|---|
| S1 | Low | Confirmed | `SSHTransport.swift:332` | `execute(_:maxResponseBytes: .max)` — the default is unbounded | A verbose or hostile server can fill memory through one `execute` | Default to a bound (8 MiB) and require callers to pass a larger explicit limit |
| S2 | Low | Confirmed | `SSHTransportPool.swift:22-31` | Two concurrent first requests for one route each see no entry, both create a transport (the `await acquire` interleaves), the second overwrites the map and the first is orphaned; a fresh transport that is not yet connected is never reused by the next caller | The "one transport per host" guarantee glas.sh relied on fails under concurrency; extra connections and prompts | Record the transport in the map before the first `await`, treat a connecting transport as reusable, or serialize per identity |
| S3 | Low | Confirmed | `SSHTransport.swift:129` | A second `connect()` during an in-flight connect throws `connectionFailed` instead of joining it | Misleading error; callers retry and can double-prompt for trust | Keep the in-flight connect as a `Task` and await it |
| S4 | Low | Confirmed | `SSHTransport.swift:245-273`; Citadel `Client.swift:95-110`; NIOSSH `NIOSSHPublicKey.swift:241` | The legacy fallback itself is sound: off by default (`SSHEndpoint.swift:50`), per hop, only after a `keyExchangeNegotiationFailure`, never after a trust failure (`challengeBox.take()` precedes the retry). But Citadel's `.all` calls `NIOSSHAlgorithms.register`, a **process-wide** registry, so after one legacy connect RSA host-key algorithms stay registered for every later connection in the process. DH-group14-SHA1 and AES128-CTR are per connection | Host identity stays pinned per key blob by our validator, so trust is not weakened; but which host-key algorithms are accepted depends on connection history, which is the kind of hidden global state that surprises later capabilities (database and desktop tunnels share the process) | Register RSA host-key support once at engine load, deliberately and uniformly (its signatures are `rsa-sha2-512`, `RSA.swift:143`); keep only the SHA-1 KEX and AES-CTR behind the per-host option. W2/W3: the per-server toggle has no warning text in glas.sh (`grep -i legacy ServerFormViews.swift SettingsView.swift` is empty) — add the persistent warning the July audit asked for |
| S5 | Low | Confirmed | `SFTPSession.swift:185-197` | `list` builds `entry.path = base + filename` from server-supplied names with no validation; a name containing `/`, or equal to `.`/`..`, yields a path outside the listed directory | glas.sh's browser validates basenames before local writes (`SFTPBrowserView.swift:3157`, `isSafeBasename`); the Stage 5 editor and any other consumer will not unless the engine offers one check | Add `SFTPEntry.hasSafeName` (no `/`, no NUL, not `.`/`..`) computed in `list`, and document that consumers must check it before using `name` as a local file name |
| S6 | Info | Confirmed | `SSHCredentials.swift:115-122, 162` | Resolved passwords and private keys become Swift `String`s for Citadel's `SSHAuthenticationMethod`; those copies are not zeroed and live as long as the auth method | `SecureBytes` protects only the store→builder hop; the note should not claim zeroing end to end | Inherent to Citadel's API; record the limit |
| S7 | Info | Confirmed | `SSHTransport.swift:184` | Credentials are resolved from the Keychain (and any user-presence prompt fires) before the socket opens and the host key is checked | NIOSSH still sends nothing until KEX and host-key validation succeed, so no leak; a biometric prompt merely precedes trust | Resolve lazily inside the authentication closure |
| S8 | Info | Confirmed | `SSHTransport.swift:287-302` | An in-flight `sendKeepAlive` failing after `close()` can call `lostConnection` again: `.lost` is yielded onto a finished continuation (dropped) and `forceClose` is a no-op | Harmless today | Guard `recordMissedKeepAlive` on `isClosing` |
| S9 | Info | Confirmed | `SSHTunnels.swift:370-377` | A remote forward's `run` closure holds the `SSHClient` strongly; the forward outlives transport teardown until its own `close()` | Consumers that forget to close keep a client alive | Track forwards on the transport and cancel them in `teardown`, or document the obligation |
| S10 | Info | Confirmed | `SSHHostTrust.swift:87` | `pin` throws `invalidHost` for an undecodable key blob | Wrong error name; cosmetic | Add an `invalidHostKey` case |

No High or Medium findings. Grep sweep (`TODO|FIXME|fatalError|try!|as!|unsafe|acceptAnything|SSHAlgorithms.all`) over `Sources/GlassSSHTransport`: **no hits** (the `.all` retry is spelled `algorithms: .all`, reviewed as S4).

## What is sound (do not re-review)

- **Host trust.** Every hop and the target get their own `SSHPromptingHostKeyValidator` with the
  authorised set for that `host:port` (`SSHTransport.swift:163-170, 185, 200, 211, 224`); Citadel
  dispatches `.custom` validators unconditionally (`ClientSession.swift:328`). Unknown and changed
  keys both fail the promise with the one `SSHHostTrustChallenge` (`SSHHostTrust.swift:174-193`);
  `.strict` never prompts (`SSHTransport.swift:139`); pins are written only after a `.trust`
  decision and a changed key uses `replace` (`SSHHostTrust.swift:86-95`); `.trust(remember:
  false)` is per transport instance; a Keychain failure while pinning aborts the connect rather
  than degrading. No path accepts anything.
- **Credentials.** The public API carries only references (`SSHCredentialReference`);
  resolution reads `KeychainOperations`/`SSHKeyKeychainStore` under the family configuration;
  `notFound` falls through the location list, any other Keychain error propagates; `.agent` is an
  honest error; error text names user@host only (`userFacingMessagesNameTheEndpointNotTheSecret`
  is tested); logging emits error type names only (`SSHTransport.swift:115`, `Logging.swift`).
- **SOCKS5.** Parsers are incremental and bounded (257 / 513 / 262 bytes; 64 KiB buffered
  handshake; `SOCKS5.swift:97-111`), 15 s handshake timeout, 64 pre-authentication connections,
  constant-time credential comparison across the full 255-byte field including length
  (`SOCKS5.swift:124-138`), authentication result always answered before the request is read.
- **Tunnels.** Listeners bind `127.0.0.1` only (`SSHTunnels.swift:145`); accepted clients are
  registered and closed on `close()`; `NIOAsyncChannel` is created on the channel's own loop for
  accepted children (`makeCompletedFuture`, :117) and for provider channels (`eventLoop.submit`,
  :180-184); refused remote channels close the local client.
- **SFTP.** No Citadel types cross the API; every operation checks cancellation first;
  `readFile` is chunked and bounded by `maxBytes`; no temporary files in the engine; Citadel's
  SFTP logger is pinned to `.error` because its info level logs full remote paths.
- **Shell channel.** Refuses writes after exit, floors PTY sizes at 1, distinguishes remote close,
  cancellation and failure.
- **Vendored code.** `Packages/Citadel` and `Packages/swift-nio-ssh` `Sources/` and `Tests/` are
  byte-identical to `../glas.sh/Packages` (0 differing files); only `Examples/` and `build/` were
  left behind. Citadel's RSA user-key signatures are `rsa-sha2-512` (`RSA.swift:143`), not SHA-1.
- **Tests.** 40 tests in 7 suites cover trust decisions, credential failure modes, SOCKS5
  parsing, tunnel piping and close, ownership, and two consumer types that use tunnels and SFTP
  without importing the terminal. The real-host suite skips with an explicit "no host configured"
  reason when the environment is absent (`SSHTransportIntegrationTests.swift:18-19`).

## Scope B — the two audit items carried from July

**(1) `SessionRecorder.recordInput` — RESOLVED in glas.sh, moved unchanged.** Input capture is
opt-in per recording: `start(..., capturesInput: Bool = false)` (`SessionRecorder.swift:257-265`)
and `recordInput` returns unless `capturesInput` (:440-441). The choice is explained where it is
made — "Output-only is the safest default. Keyboard input may include passwords, tokens, and other
secrets because remote password prompts cannot be detected reliably." (`TerminalWindowView.swift:
192`). A `recordingIndicator` is shown in the terminal chrome (:527, :782, :1324). `finalize()`
is called on every disconnect and failure path (`Models.swift:704, 716, 730, 871, 909`). Files
carry `.completeUnlessOpen` while recording (`SessionRecorder.swift:304, 350`) and `.complete`
once finalised (:505, :722, :870). Recordings live under `Documents` (:1303) but neither
`../glas.sh/glas.sh/Info.plist` nor `App/Info.plist` sets `UIFileSharingEnabled`, so they are not
exposed through Files. The moved copy in `Sources/GlassTerminal` is byte-identical. **No W2/W3
action required** beyond keeping that UI text.

**(2) AI one-click execution trusting the model's `riskLevel` — RESOLVED in glas.sh, moved
unchanged.** A deterministic `assess(_:)` independent of the model (`AIAssistant.swift:146-234`)
flags shell control/redirection/substitution syntax, destructive, privilege-escalation,
credential, network and interpreter utilities (first token and arguments), non-read-only `git`,
`find -delete/-exec`, and control or invisible Unicode; `requiresConfirmation` is always true and
`isExecutable` is false only for disallowed Unicode. Execution happens solely from a confirmation
alert that shows the exact command and the assessment's reasons (:466-472, :602-612; the
"fix" path mirrors it at :748-790). The model's `riskLevel` is rendered as a "Model: …" badge
(:614-627) and gates nothing. **No W2/W3 action required.**

## Out of scope, noted

`Sources/GlassTerminal` was mid-move (W2); only the three Scope B files were compared. The
tunnel and SFTP APIs' real-host exercise is blocked by the session terminal's Local Network grant,
not by code (W1's note).
