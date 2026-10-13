# Glass Power Tools patches to swift-nio-ssh

This directory is a vendored copy of swift-nio-ssh with a small set of local changes. Everything
else is upstream, byte for byte. The licence is upstream's Apache License 2.0 (`LICENSE.txt`);
upstream ships no NOTICE file. Every modified file carries a one-line notice below its licence
header, as Apache-2.0 §4(b) requires.

## Provenance

- **Original:** [apple/swift-nio-ssh](https://github.com/apple/swift-nio-ssh), Apache-2.0.
- **Fork used:** the fork maintained for [Citadel](https://github.com/orlandos-nl/Citadel) —
  [Wellz26/swift-nio-ssh](https://github.com/Wellz26/swift-nio-ssh), which shares its history with
  [joannis/swift-nio-ssh](https://github.com/joannis/swift-nio-ssh). It adds, among other things,
  RSA keys, multiple MACs per transport, visionOS support and SSH certificate authentication.
  Citadel requires this fork rather than Apple's release.
- **Baseline:** tag `0.3.7`, commit `6acaa1ae7afb7fe9d07d06cda159e7fecea32500` (2026-09-12) — the
  version upstream Citadel resolves.

To see exactly what differs from the baseline:

```sh
git clone https://github.com/Wellz26/swift-nio-ssh.git /tmp/nio-ssh
git -C /tmp/nio-ssh checkout 6acaa1ae7afb7fe9d07d06cda159e7fecea32500
diff -ru --exclude=.git /tmp/nio-ssh Packages/swift-nio-ssh
```

The diff shows the files listed below, this file, and nothing else.

## Manifest (`Package.swift`)

- swift-crypto range widened from `"1.0.0"..<"4.0.0"` to `"1.0.0"..<"5.0.0"`: the app and Citadel
  use swift-crypto 4.
- The swift-docc-plugin dependency is removed, so a documentation tool does not enter the app's
  dependency graph. The documentation catalogue itself is untouched.

## Source changes

| # | Change | Why | Files | Test |
|---|---|---|---|---|
| N1 | While a host-key or user-authentication decision is pending (the decision can take as long as a person does), incoming data is held in order and processed once the decision is made. The hold is bounded — 1 MiB and 1,024 reads — and the connection closes if a peer exceeds it. The decision's result is delivered on the connection's event loop. | Upstream processed later data while the decision was still open ("This is not right, but for now it's good enough"), so a slow trust prompt could interleave messages out of order. | `NIOSSHHandler.swift` | `testDelayedHostKeyValidationRejectsExcessDeferredInboundData` |
| N2 | The connection's writability reaches every child channel; `channelInactive` is passed on down the pipeline. | Writers on a session could not see that the connection's buffer was full, and the inactive event stopped at the handler. | `NIOSSHHandler.swift`, `SSHChannelMultiplexer.swift` | no dedicated test; the suite's end-to-end tests run through it |
| N3 | `NIOSSHHandler.sendKeepAlive()` sends an OpenSSH `keepalive@openssh.com` global request. | Keeps idle connections through NAT and detects dead peers; Citadel's `SSHClient.sendKeepAlive()` calls it. | `NIOSSHHandler.swift` | `testKeepAliveLeavesConnectionUsable` |
| N4 | An RSA key signs in with the `rsa-sha2-512` algorithm (RFC 8332), named both in the request and in the data the signature covers; the key blob keeps its `ssh-rsa` type. | Current OpenSSH servers refuse the SHA-1 `ssh-rsa` signature algorithm, so RSA keys could not sign in. Changing only the request fails too: the server then rejects a signature over data naming a different algorithm. | `SSHMessages.swift`, `UserAuthSignablePayload.swift` | no unit test — an RSA key type is registered by Citadel, not this package. Verified by signing in to OpenSSH 10.2 with an RSA key: refused with only the request changed, accepted with both. |
| N5 | `SSHChildChannel.remoteAddress0()` returns the parent's remote address. | It returned the parent's *local* address. The public `remoteAddress` property was already correct; NIO's own machinery calls `remoteAddress0()`. | `SSHChildChannel.swift` | `testChildChannelUsesParentAddresses` |
| N6 | Writing channel data that cannot be serialized (a file region, an unknown extended-data type) fails that write with `ChannelError.operationUnsupported`; unsupported child-channel options and operations fail their promise. | Upstream terminated the process (`preconditionFailure`, `fatalError`). An error is recoverable; a crash of the whole app is not. | `SSHChannelData.swift`, `SSHChildChannel.swift` | `testChannelDataRejectsFileRegionsRecoverably`, `testChannelDataRejectsUnknownExtendedTypesRecoverably`, `testUnsupportedChildChannelDataFailsRecoverably`, `testUnsupportedChildChannelOperationsFailRecoverably` |
| N8 | An ECDSA signature whose `r` or `s` is wider than the curve's point size is refused with `invalidSSHMessage`. Upstream's own fix (apple/swift-nio-ssh 31cdc3c, released in 0.14.1), with its two tests. | **GHSA-998x-vgvp-xwpc / CVE-2026-43798, critical:** the signature in the server's key-exchange reply is parsed before the host key is checked, and an oversized component made a negative offset and an out-of-bounds write into stack memory — any server, or anyone between the app and it, could crash the app or worse. A trap in a debug build; in the Release build the app ships, the write. Found by the 2026-10-12 advisory scan of upstream security advisories. | `Keys And Signatures/NIOSSHSignature.swift` | `testOversizedECDSARComponentIsRejected`, `testOversizedECDSASComponentIsRejected` |

The tests above are added in an `extension` at the end of each upstream test file; no upstream test
was changed. With these changes the package's own suite runs 363 tests (356 upstream, 7 added), all
passing.

A seventh change, rejecting key-exchange messages that arrive after the peer's NEWKEYS, was carried
until 2026-09-27 and then dropped: upstream's `default:` branch already throws a protocol violation
for them, so it only changed the error's wording.

## Deliberately not changed

The package keeps upstream's Swift 5 language mode. The app imports it with `@preconcurrency`, which
is the standard way for Swift 6 code to use a library that predates strict concurrency checking.
