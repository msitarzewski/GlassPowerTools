# Glass Power Tools patches to Citadel

This directory is a vendored copy of [Citadel](https://github.com/orlandos-nl/Citadel) (MIT,
`LICENSE`) with a set of local changes. Everything else is upstream, byte for byte.

## Provenance

- **Upstream:** [orlandos-nl/Citadel](https://github.com/orlandos-nl/Citadel), MIT.
- **Baseline:** commit `ae8562f895de06ccb86fdb1cbb65fd99c8976e12` on `main` (2026-04-04): release
  0.12.1 plus 8-bit-safe `withExec` and Mac Catalyst support.

To see exactly what differs from the baseline:

```sh
git clone https://github.com/orlandos-nl/Citadel.git /tmp/citadel
git -C /tmp/citadel checkout ae8562f895de06ccb86fdb1cbb65fd99c8976e12
diff -ru --exclude=.git /tmp/citadel Packages/Citadel
```

## Manifest (`Package.swift`)

- swift-nio-ssh comes from `../swift-nio-ssh` (the vendored fork beside this package, see its
  `PATCHES.md`) instead of by URL.
- The `CitadelServerExample` executable target and its ColorizeSwift dependency are removed, so an
  example's dependency does not enter the app's dependency graph. The example sources are untouched.
- swift-crypto `"3.12.3"..<"5.0.0"` and BigInt `"5.2.0"..<"7.0.0"`, widened from `from:` ranges that
  stop below swift-crypto 4 and BigInt 6 — the versions the app uses.

## Fixes

| # | Change | Files |
|---|---|---|
| C1 | SFTP file attributes with extended entries are written with their count, as SFTP v3 requires; they were written without it. | `ByteBufferHelpers.swift` |
| C2 | Writing an SFTP packet, or attributes, into an empty buffer no longer traps: the length placeholder is written rather than skipped over. | `SFTPSerializer.swift`, `ByteBufferHelpers.swift` |
| C3 | `listDirectory` closes the directory handle — after EOF, on a failed read, and when the server ends the listing with anything but EOF. It leaked one handle per listing. | `SFTPClient.swift` |
| C4 | `SFTPFile.readAttributes()` asks about the open handle (`fstat`) instead of looking the path up again (`stat`). | `SFTPFile.swift` |
| C5 | When an operation on a file fails and closing the file then also fails, the original error is the one reported. | `SFTPClient.swift` |
| C6 | Connecting on an existing channel used a new inbound-channel handler instead of the session's, so channels the server opened on such a connection went to a handler nobody held; `SSHClientSettings.channelHandlers` are now installed (they were accepted and ignored). | `ClientSession.swift` |
| C7 | Reconnecting: exponential backoff with jitter (was an immediate, unbounded retry loop), cancelled by `close()`, never after a deliberate close, and a newer attempt cancels an older one. The client's mutable state is behind one lock, because the reconnect task replaces the session while callers read it. | `Client.swift` |
| C8 | `executeCommand`: stderr counts toward `maxResponseSize` (it could grow without bound); exceeding the limit closes the channel; the result completes exactly once however it ends; the 15-second channel-creation timer is cancelled once the channel exists. | `ExecClient.swift` |
| C9 | Unexpected channel data and an internal key error are reported as errors instead of terminating the process (`fatalError`). | `ChannelUnwrapper.swift`, `DirectTCPIP+Client.swift`, `OpenSSHKey.swift` |
| C10 | The debug description of an SFTP handle printed the wrong hex digits (it shifted by 8 bits instead of 4). | `SFTPFile.swift` |
| C11 | An SFTP packet may declare at most 16 MiB; a larger or zero length is rejected before any body is buffered, so a hostile server cannot make the client reserve up to 4 GiB. | `SFTPMessageParser.swift` |
| C12 | A composite SSH string written into a buffer with no room left no longer traps: its length placeholder is written rather than skipped over, as C2 does for SFTP. Diffie-Hellman group 14 writes one into the exchange-hash buffer after the server's KEXINIT, so a server could choose a KEXINIT that ended the app. | `DH-Helpers.swift` |

## Features used by Glass Power Tools

| # | Change | Files |
|---|---|---|
| F1 | RSA signatures use SHA-512 (`rsa-sha2-512`, RFC 8332) — current OpenSSH servers refuse SHA-1. Pairs with swift-nio-ssh patch N4. | `RSA.swift` |
| F2 | `SSHAuthenticationMethod.secureEnclaveP256(username:privateKey:)`: sign in with a key held in the Secure Enclave. | `SSHAuthenticationMethod.swift` |
| F3 | `SSHClient.sendKeepAlive()` (uses swift-nio-ssh patch N3). | `Client.swift` |
| F4 | SFTP server extensions from version negotiation: `serverExtensions`, `serverExtensionVersion(for:)`, `supportsExtension(_:version:)`. | `SFTPClient.swift` |
| F5 | OpenSSH extensions over the SFTP extended request: `posixRename(at:to:)` (atomic replace — what makes a remote save atomic) and `hardLink(at:to:)`. The extended-request message is added to the protocol model; the bundled SFTP *server* answers it as unsupported. | `SFTPClient.swift`, `SFTPMessage.swift`, `SFTPMessageParser.swift`, `SFTPSerializer.swift`, `SFTPServerInboundHandler.swift` |
| F6 | `SFTPFile.synchronize()` — `fsync@openssh.com`, for durable writes. | `SFTPFile.swift` |
| F7 | `SFTPClient.getLinkAttributes(at:)` — `lstat`, without following a symbolic link. | `SFTPClient.swift`, `SFTPMessage.swift` |
| F8 | `SFTPFileAttributes.fileType` and `isRegularFile`, from the permission bits' file-type field. | `SFTPFileFlags.swift` |
| F9 | `SFTPFile.read(_: [ReadRequest])`: up to 8 ranges (2 MiB) in flight at once, returned in request order. | `SFTPFile.swift`, `SFTPClient.swift` |
| F10 | `executeCommand(_:maxResponseSize:executionTimeout:)`: a time limit, and task cancellation closes the channel. | `ExecClient.swift` |

New error cases for these: `SFTPError.invalidPacketLength`, `SFTPError.unsupportedExtension`,
`CitadelError.commandExecutionTimedOut` (`Errors.swift`). `SFTPClient`'s initializer and response
table are `internal` rather than `fileprivate`, so the tests below can drive the client directly.

## Licence notice restored

`Sources/CCitadelBcrypt/bcrypt-kdf.c` is derived from OpenBSD's `bcrypt_pbkdf.c` (© 2013 Ted Unangst,
ISC licence). Citadel's copy had lost its licence header; it is restored, as the ISC licence requires
the notice in all copies.

## Tests

23 tests for the changes above are added in an `extension Citadel2Tests` at the end of
`Tests/CitadelTests/Citadel2Tests.swift`, which now imports Citadel with `@testable` to reach the
SFTP parser and serializer. No upstream test was changed. The package's own suite runs 58 tests
(35 upstream, 23 added), all passing.

## Deliberately not changed

The package keeps upstream's Swift 5 language mode; the app imports it with `@preconcurrency`.
Upstream's SFTP, exec and shell *servers* are unchanged apart from answering the new extended
request — the app is a client and does not use them.
