# Stage 3 W-kit — the database engine moved, minus the tunnel

Owner `/root` (coordinator did this one directly). 2026-09-12. Wave 1 of the
[Stage 3 plan](2026-09-12_stage-3-database-plan.md). **Status: done, package green, three
platforms build.** Not committed at time of writing.

## What moved

Five files from `../glassdb/Packages/GlassDBKit/Sources/GlassDBKit/`, byte-for-byte:

| File | Lines |
|---|---|
| `DatabaseProtocol.swift` | 239 |
| `QueryResult.swift` | 267 |
| `MySQLAdapter.swift` | 885 |
| `PostgreSQLAdapter.swift` | 591 |
| `SQLiteAdapter.swift` | 674 |

**`SSHTunnelManager.swift` (539 lines) did not move** — D7: the host's own SSH service supplies the
forward. The excision is clean: `grep` for `SSHTunnel`, `PendingTunnelBufferBudget` and `Citadel`
across the other five files returns nothing, so no adapter referenced it.

## It is a target, not a nested package — deviation from the plan, with reason

The plan's module table said `Packages/GlassDBKit`. It landed as `Sources/GlassDBKit`, a target of
the root package, because:

- It is **our** code. `Packages/` holds the two vendored third-party forks (Citadel, swift-nio-ssh);
  mixing our engine in with them blurs that boundary.
- It is the exact peer of `Sources/GlassSSHTransport` — an engine module with no UI and no shell
  dependency. Same role, same place.
- One resolution graph, one `Package.resolved`, and **no Xcode project edit**: the project keeps its
  single `XCLocalSwiftPackageReference` = `.` and picked the new scheme up by itself
  (`xcodebuild -list` now shows `GlassDBKit`).

`GlassDatabase` will depend on it in wave 2; the app links the product then.

## The swift-crypto conflict is dead — proven by resolving, not by reasoning

The survey's top risk was that swift-crypto 4.5.2 is excluded by glassdb's vendored Citadel and
swift-nio-ssh (`<4.0.0` upper bounds). Dropping `SSHTunnelManager` drops GlassDBKit's only Citadel
edge, and the merged graph resolves:

| Package | glassdb's kit resolved | **Power Tools resolves** |
|---|---|---|
| swift-crypto | 3.15.1 | **4.5.2** (ours, unchanged) |
| swift-nio | 2.100.0 | 2.102.0 |
| swift-nio-ssl | 2.36.0 | 2.37.4 |
| postgres-nio | 1.33.0 | 1.33.1 |
| mysql-nio | `69489876` (fork) | `69489876` (same fork, same pin) |

The mysql-nio pin is **mandatory and carried deliberately**: upstream PR 126 (empty-password
`caching_sha2_password`) was closed unmerged. The reason is recorded in `Package.swift` beside the
pin so nobody "tidies" it to a version range.

## Tests

glassdb's 28 kit tests came across as **22**. The six that left are the ones that tested
`SSHTunnelManager` and have no subject here any more:

| Dropped test | Who owns that behaviour now | Its coverage |
|---|---|---|
| `openSSHPrivateKeyDetectionRoutesRSAAndEd25519WithoutTextGuessing` | `GlassSSHTransport` | `SSHPublicKeysTests.ed25519MatchesSSHKeygen`, `rsaMatchesSSHKeygen` |
| `malformedAndLegacyPrivateKeysReturnActionableTunnelErrors` | `GlassSSHTransport` | `SSHPublicKeysTests.legacyWrappedP256DerivesAnECDSAKey` |
| `CRLFEd25519PrivateKeyParsesWithoutNetworkUse` | `GlassSSHTransport` | `SSHPublicKeysTests`, `SSHPrivateKeyImportTests` |
| `sshTrustPolicyRejectsUnknownAndRotatedKeys` | `GlassSSHTransport` | `SSHHostTrustTests.differentKeyForPinnedHostIsAChangedChallenge` |
| `sshConfigurationRejectsMalformedCredentialsAndEndpointsBeforeNetworkUse` | `GlassSSHTransport` | `SSHCredentialTests`, `SecurityReviewFixTests` |
| `sshPendingBufferBudgetIsStrictlyBoundedAndResettable` | `GlassSSHTransport` | `SOCKS5Protocol.maximumConnectRequestBytes` bounds the handshake buffer at `SSHTunnels.swift:277`; the local-forward path streams rather than buffering |

One further line left with them: `transportPoliciesAreExplicit` asserted
`SSHAlgorithmPolicy.modernOnly == .modernOnly` in the middle of a database-TLS test. The database
half of that test is intact.

**No behaviour we still ship lost its test.** Every dropped assertion has a named owner above.

## Live tests now aim at the project VM

glassdb's three live tests hardcoded `127.0.0.1:33306` / `:35432` and `glassdb_test`, gated on
`GLASSDB_*` variables. They are rewired through a new `LiveDatabaseEnvironment` helper onto the
plan's `GPT_DB_TEST_*` namespace, defaulting to `127.0.0.1` and the standard ports so a local
install still works:

`GPT_DB_TEST_HOST`, `_MYSQL_{PORT,USER,DB,PASSWORD}`, `_PG_{PORT,USER,DB,PASSWORD}`, plus
`_MYSQL_PASSWORDLESS*` and `_MYSQL_TLS_*` for the two special cases. Temporary tables renamed
`gpt_live_*`. Credentials come from `~/.config/gpt-db-test.env` (outside the repo — see the
[VM note](2026-09-12_stage-3-vm-databases.md)); none are recorded here.

## Verification

| Check | Result |
|---|---|
| `swift package resolve` | **passed** — swift-crypto **4.5.2** retained; full pin table above |
| `swift build --target GlassDBKit` | **passed**, no errors, no new warnings |
| `swift test` (whole package) | **507 tests / 33 suites passed** (was 485 / 30 before the move) |
| `swift test --filter LiveEngineIntegrationTests` | 3 tests, **3 correctly skipped** with no `GPT_DB_TEST_*` set — the gate works |
| `xcodebuild -scheme GlassDBKit`, `generic/platform=` iOS, visionOS, macOS | **BUILD SUCCEEDED** on all three |
| `xcodebuild -scheme GlassPowerTools`, `platform=macOS,arch=arm64` | **BUILD SUCCEEDED** — the app is unaffected |
| App, iOS Simulator and visionOS Simulator | **BUILD SUCCEEDED** on both |
| **`postgres17LiveRoundTrip` against PostgreSQL 18.6 on the VM** | **passed** — create, parameterised insert with an injection string, `NUMERIC(40,18)`, `BYTEA`, `JSONB`, transaction rollback, metadata, `EXPLAIN`, drop, query cancellation |
| **`mysql8LiveRoundTrip` against MySQL 8.4.11 on the VM, auth cache flushed** | **passed** — see below; this is the run that counts |
| Pinned-CA TLS to MySQL | **known issue, D13** — recorded in the suite with `withKnownIssue`, not deleted and not asserted as correct |

## The one thing swift-crypto 4.5.2 genuinely changes

Dropping Citadel freed the graph to swift-crypto **4.5.2**, where glassdb's kit was pinned to
3.15.1. That is not a cosmetic bump for MySQL: mysql-nio's `caching_sha2_password` full
authentication over an insecure channel requests the server's RSA public key and encrypts the
password with `_RSA.Encryption.PublicKey(pemRepresentation:)` from `_CryptoExtras`
(`MySQLConnectionHandler.swift:326-351`). So **the cold-cache MySQL login is the first exercise of
mysql-nio's RSA path against swift-crypto 4.5.2** — a combination glassdb never ran, created by this
move. It compiles; compiling is not the question.

The server offers the exchange: W-vm measured `--get-server-public-key` succeeding cold, and plain
plaintext failing cold with `ERROR 2061`. Whether our client completes it is the measurement, and
it is the reason the live MySQL test must be run against a **flushed** auth cache — a warm cache
takes the fast path and never touches this code at all.

**Measured 2026-09-12T03:36Z and it works.** W-vm ran `FLUSH PRIVILEGES`, connected only as
`root@localhost` over `auth_socket` (which creates no `caching_sha2_password` cache entry for
`gpt_test`) and then stood off the server, so the Swift test held the first `gpt_test` connection
after the flush. `mysql8LiveRoundTrip` **passed in 0.091s over plaintext**. mysql-nio's RSA path is
therefore proven at runtime on swift-crypto 4.5.2, and **TLS is not mandatory for MySQL** — which
is what keeps D13 a defect rather than a blocker.

Two earlier green MySQL runs are recorded here as proving nothing: both were on a warm cache, which
takes the fast path. They are kept in this note because "it passed twice" was the wrong conclusion
and the reason it was wrong is worth remembering.

## Remaining for later waves

- The engine's **live behaviour is unproven** until W-vm's databases exist and the three gated tests
  actually run. Until then this is a compile-and-unit-test result only.
- Risks from the survey still open and owned by wave 2: blocking `syncShutdownGracefully()` in three
  deinits, PostgreSQL `databases()` returning schemas, no version number on the connection record.
- `swift test --build-system native` now prints a deprecation warning; the flag can be dropped.
