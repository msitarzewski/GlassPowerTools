# glassdb Engine and Data Layer Survey

Read-only survey of `../glassdb` for the Glass Power Tools merge.
Scope: engine and data layer, not UI. Date: 2026-09-11.
All paths below are relative to `../glassdb/` unless stated absolute.

Evidence basis: current checkout on branch `main`, plus two commands I actually ran in this
session, both recorded under section 2.4. Everything else is source inspection.

---

## 1. GlassDBKit public API surface

### 1.1 Package shape

- `Packages/GlassDBKit/Package.swift:1` — swift-tools-version 6.2, so Swift 6 language mode by default.
- `Packages/GlassDBKit/Package.swift:8-12` — platforms visionOS 26, macOS 26, iOS 26.
- `Packages/GlassDBKit/Package.swift:14` — one product, `.library(name: "GlassDBKit")`.
- `Packages/GlassDBKit/Package.swift:26-37` — one target `GlassDBKit`, deps MySQLNIO, PostgresNIO, NIOSSL, Citadel.
- `Packages/GlassDBKit/Package.swift:35` — `linkerSettings: [.linkedLibrary("sqlite3")]`, system SQLite, no vendored copy.
- `Packages/GlassDBKit/Package.swift:38-45` — one test target `GlassDBKitTests`.
- Source is six files, about 3,200 lines total:
  - `DatabaseProtocol.swift` 239 lines
  - `QueryResult.swift` 267 lines
  - `MySQLAdapter.swift` 885 lines
  - `PostgreSQLAdapter.swift` 591 lines
  - `SQLiteAdapter.swift` 674 lines
  - `SSHTunnelManager.swift` 539 lines

### 1.2 Errors and capability negotiation

- `DatabaseProtocol.swift:10` — `public enum DatabaseError: Error, LocalizedError`.
- `DatabaseProtocol.swift:11-16` — cases `unexpectedResult(String)`, `invalidTLSCertificate(String)`, `tlsRequiredButUnavailable(host:port:)`, `unsupportedParameter(String)`, `unsupportedCapability(DatabaseCapability, engine:)`, `queryTimedOut`.
- `DatabaseProtocol.swift:18` — `public var errorDescription: String?`, all messages user-facing and specific.
- `DatabaseProtocol.swift:37` — `public enum DatabaseCapability: String, Sendable, Hashable, CaseIterable`.
- `DatabaseProtocol.swift:38-52` — fifteen cases: `transactions`, `parameterBinding`, `transportTLS`, `queryTimeout`, `cancellation`, `metadata`, `schemas`, `indexes`, `foreignKeys`, `tableStatistics`, `aggregateTableStatistics`, `createTableDefinition`, `explain`, `serverVersion`, `truncateTable`.
- `DatabaseProtocol.swift:55-58` — `public enum DatabaseDialect` with `mysql`, `postgresql`, `sqlite`.
- Design note: capabilities are advertised per connection so the UI hides unsupported operations rather than discovering failure late. Comment at `DatabaseProtocol.swift:35`.

### 1.3 Transport policy types

- `DatabaseProtocol.swift:62` — `public struct DatabaseTLSCertificate: Sendable, Hashable` with `bytes: Data` and `format: Format`.
- `DatabaseProtocol.swift:63-66` — `public enum Format` with `pem`, `der`.
- `DatabaseProtocol.swift:79` — `public enum DatabaseTLSPolicy: Sendable, Hashable`.
- `DatabaseProtocol.swift:80-85` — cases `disabled`, `requiredSystemTrust`, `requiredSystemTrustForHost(String)`, `requiredCertificates([DatabaseTLSCertificate], serverName: String?)`.
- `DatabaseProtocol.swift:84` — `requiredSystemTrustForHost` exists specifically so a socket connected through a local SSH tunnel still verifies the real server name.
- `DatabaseProtocol.swift:87-92` — `public var isRequired: Bool`. Both required modes fail closed and never fall back to plaintext, per the comment at line 77.

### 1.4 `DatabaseEngine` protocol

- `DatabaseProtocol.swift:95` — `public protocol DatabaseEngine: Sendable`.
- `DatabaseProtocol.swift:96-103` — `connect(host:port:username:password:database:tlsPolicy:) async throws -> any DatabaseConnection`.
- `DatabaseProtocol.swift:105-107` — `var engineName: String`, `var capabilities: Set<DatabaseCapability>`, `var dialect: DatabaseDialect`.
- `DatabaseProtocol.swift:143-164` — `public extension DatabaseEngine` supplies defaults for `capabilities` and `dialect`, plus a compatibility `connect` overload that passes `.disabled`.

### 1.5 `DatabaseConnection` protocol, grouped by responsibility

- `DatabaseProtocol.swift:110` — `public protocol DatabaseConnection: Sendable`.

Connection identity and state:
- `DatabaseProtocol.swift:111` — `var isConnected: Bool { get async }`.
- `DatabaseProtocol.swift:112-115` — `engineName`, `capabilities`, `identifierQuoteCharacter: Character`, `dialect`.

Query execution:
- `DatabaseProtocol.swift:117` — `execute(_:parameters:) async throws -> QueryResult`.
- `DatabaseProtocol.swift:118-122` — `execute(_:parameters:timeout: Duration?) async throws -> QueryResult`.
- `DatabaseProtocol.swift:140` — `explain(_:parameters:) async throws -> QueryResult`.

Cancellation:
- `DatabaseProtocol.swift:123` — `cancelCurrentQuery() async throws`.

Transactions:
- `DatabaseProtocol.swift:124-126` — `beginTransaction()`, `commitTransaction()`, `rollbackTransaction()`.

Lifecycle:
- `DatabaseProtocol.swift:127` — `close() async throws`.

Schema introspection:
- `DatabaseProtocol.swift:129` — `databases() async throws -> [String]`.
- `DatabaseProtocol.swift:130` — `tables(in:) async throws -> [String]`.
- `DatabaseProtocol.swift:131` — `columns(in:database:) async throws -> [ColumnInfo]`.
- `DatabaseProtocol.swift:132` — `showCreateTable(_:database:) async throws -> String`.
- `DatabaseProtocol.swift:133` — `indexes(in:database:) async throws -> [IndexInfo]`.
- `DatabaseProtocol.swift:134` — `foreignKeys(in:database:) async throws -> [ForeignKeyInfo]`.
- `DatabaseProtocol.swift:135` — `tableStatus(in:) async throws -> [TableStatus]`.
- `DatabaseProtocol.swift:136` — `tableStatusByNamespace() async throws -> [String: [TableStatus]]`.
- `DatabaseProtocol.swift:137-138` — `rowCount(table:database:)` and the timeout-bearing overload.
- `DatabaseProtocol.swift:139` — `serverVersion() async throws -> String`.

Protocol extension defaults, all of which throw `unsupportedCapability` rather than lying:
- `DatabaseProtocol.swift:167-170` — defaults for `engineName`, `capabilities`, `identifierQuoteCharacter` = backtick, `dialect` = `.mysql`.
- `DatabaseProtocol.swift:172-177` — `parameterPlaceholder(at:)` returns `$n` for PostgreSQL, `?` for MySQL and SQLite.
- `DatabaseProtocol.swift:179-181` — convenience `execute(_:)` with no parameters.
- `DatabaseProtocol.swift:183-192` — timeout overload throws `.queryTimeout` unsupported unless timeout is nil.
- `DatabaseProtocol.swift:194-196` — `cancelCurrentQuery` throws `.cancellation` unsupported.
- `DatabaseProtocol.swift:198-208` — transaction defaults issue literal `START TRANSACTION` / `COMMIT` / `ROLLBACK`.
- `DatabaseProtocol.swift:210-212` — `serverVersion` throws `.serverVersion` unsupported.
- `DatabaseProtocol.swift:218-220` — `tableStatusByNamespace` throws `.aggregateTableStatistics` unsupported.
- `DatabaseProtocol.swift:222-224` — `explain` throws `.explain` unsupported.
- `DatabaseProtocol.swift:226-231` — `rowCount` timeout overload throws unsupported unless nil.
- `DatabaseProtocol.swift:235-238` — `quotedIdentifier(_:)` doubles embedded quote characters and quotes one logical component only, so a dotted path cannot be smuggled into SQL syntax.

### 1.6 Result and metadata value types

- `QueryResult.swift:10` — `public struct QueryResult: Identifiable, Sendable`.
- `QueryResult.swift:11-26` — `id`, `query`, `columns`, `rows: [[DatabaseValue]]`, `affectedRows: UInt64?`, `lastInsertID: UInt64?`, `warningCount: UInt16?`, `executionTime`, `timestamp`, `error: String?`, `appliedRowLimit: Int?`, `isTruncated: Bool`.
- `QueryResult.swift:23` — `appliedRowLimit` nil means no bound applied by glassdb.
- `QueryResult.swift:26` — `isTruncated` is true only when a sentinel row proved more rows existed and was then removed.
- `QueryResult.swift:56-58` — `isError`, `rowCount`, `columnCount`.
- `QueryResult.swift:61` — `public struct ColumnInfo: Identifiable, Sendable, Hashable`.
- `QueryResult.swift:62-76` — `id`, `name`, `type`, `isNullable`, `isPrimaryKey`, `ordinalPosition`, `isUnsigned`, `characterSetID: UInt8?`, `sourceSchema`, `sourceTable`, `sourceColumn`, `length: UInt32?`, `decimals: UInt8?`, `defaultValue`, `isGenerated`.
- `QueryResult.swift:113` — `public struct DatabaseTemporalValue: Sendable, Hashable` with `rawValue: String` and `kind`.
- `QueryResult.swift:114-120` — `public enum Kind` with `date`, `time`, `dateTime`, `timestamp`, `year`.
- `QueryResult.swift:122` — comment: `rawValue` is the exact server representation including fractional seconds.
- `QueryResult.swift:132` — `public enum DatabaseValue: Sendable, Hashable`.
- `QueryResult.swift:133-147` — twelve cases: `string`, `int(Int64)`, `uint(UInt64)`, `decimal(String)`, `double`, `data(Data)`, `json(String)`, `temporal`, `bit(Data)`, `null`, `date(Date)`, `bool`.
- `QueryResult.swift:136` — `decimal` is a String specifically to avoid Decimal and Double precision loss.
- `QueryResult.swift:140` — `json` retains the original server text.
- `QueryResult.swift:143` — `bit` is exact bytes, most significant first.
- `QueryResult.swift:149-165` — `displayString`, which abbreviates binary as `<n bytes>`.
- `QueryResult.swift:167-170` — `isNull`.
- `QueryResult.swift:174-179` — `exportString`, lossless, Base64 for `data` and `bit`.
- `QueryResult.swift:189` — `public struct IndexInfo: Identifiable, Sendable` with `name`, `columnName`, `isUnique`, `isPrimary`, `type`, `sequenceInIndex`.
- `QueryResult.swift:215` — `public struct ForeignKeyInfo: Identifiable, Sendable` with `constraintName`, `columnName`, `referencedTable`, `referencedColumn`, `ordinalPosition`.
- `QueryResult.swift:232` — `public enum TableRowCountAccuracy: Sendable, Equatable` with `exact`, `estimated`.
- `QueryResult.swift:237` — `public struct TableStatus: Identifiable, Sendable` with `name`, `engine`, `rowCount`, `dataLength`, `collation`, `rowCountAccuracy`, `statisticsUpdatedAt`, `modifiedRowsSinceAnalysis`.

### 1.7 Public symbols exported by the SSH file

Listed here for completeness; behaviour is section 3.

- `SSHTunnelManager.swift:20` — `public enum SSHHostKeyChallengeReason` with `unknown`, `changed`.
- `SSHTunnelManager.swift:25` — `public struct SSHHostKeyChallenge: Sendable, Hashable`.
- `SSHTunnelManager.swift:35` — `public struct SSHHostKeyTrustRequiredError: Error, LocalizedError, Sendable`.
- `SSHTunnelManager.swift:48` — `public enum SSHAlgorithmPolicy` with a single case `modernOnly`.
- `SSHTunnelManager.swift:53` — `public enum SSHPrivateKeyAlgorithm` with `rsa`, `ed25519`, `secureEnclaveP256`.
- `SSHTunnelManager.swift:59` — `public struct SSHTunnelConfig: Sendable`.
- `SSHTunnelManager.swift:97` — `public final class SSHTunnelManager: Sendable`.
- `SSHTunnelManager.swift:339` — `public final class SSHTunnel: @unchecked Sendable`.
- `SSHTunnelManager.swift:509` — `public enum SSHTunnelError: Error, LocalizedError`.

### 1.8 What is NOT in the API

- No streaming of any kind. `grep` for `AsyncSequence`, `AsyncStream`, `AsyncThrowingStream`, `for try await` across `Packages/GlassDBKit/Sources` returns nothing. Every result is fully materialized into `[[DatabaseValue]]`.
- No connection pooling. One `DatabaseConnection` per session.
- No row limiting inside the kit. Bounding is applied by the app, see section 5.5.
- No schema mutation helpers. DDL goes through `execute` as raw SQL.

---

## 2. Drivers: what is supported end to end

### 2.1 MySQL and MariaDB

- `MySQLAdapter.swift:15` — `public final class MySQLEngine: DatabaseEngine, @unchecked Sendable`.
- `MySQLAdapter.swift:19` — allocates `MultiThreadedEventLoopGroup(numberOfThreads: 2)` per engine instance.
- `MySQLAdapter.swift:23-30` — capabilities: `transactions`, `parameterBinding`, `transportTLS`, `metadata`, `indexes`, `foreignKeys`, `tableStatistics`, `aggregateTableStatistics`, `createTableDefinition`, `explain`, `serverVersion`, `queryTimeout`, `cancellation`, `truncateTable`. Notably NOT `schemas`.
- `MySQLAdapter.swift:32-58` — `connect` builds TLS config, preflights, then calls `MySQLConnection.connect`.
- `MySQLAdapter.swift:60-81` — `serverAdvertisesTLS` reads only the unauthenticated MySQL greeting. This exists to stop mysql-nio's opportunistic TLS from ever sending an auth response to a server that does not advertise `CLIENT_SSL`. Ten-second connect and read timeouts.
- `MySQLAdapter.swift:45-55` — post-connect it re-verifies that `NIOSSLClientHandler` is actually in the pipeline and closes the connection if not. TLS is proven, not assumed.
- `MySQLAdapter.swift:146` — `final class MySQLTLSCapabilityProbe: ChannelInboundHandler, @unchecked Sendable`, the greeting reader.
- `MySQLAdapter.swift:215` — `final class MySQLDatabaseConnection: DatabaseConnection, @unchecked Sendable`.
- `MySQLAdapter.swift:239` — `serverVersion` via `SELECT VERSION()`.
- `MySQLAdapter.swift:375` — after a mutation it reads `SELECT ROW_COUNT() AS glassdb_affected_rows, @@warning_count AS glassdb_warning_count`.
- `MySQLAdapter.swift:583-590` — an explicit utility-command allowlist for statements MySQL rejects in the prepared-statement protocol: `USE`, `SET`, `SHOW`, `DESCRIBE`, `DESC`, `EXPLAIN`, `FLUSH`, `KILL`, `RESET`, `TRUNCATE`. Background at `memory-bank/decisions.md:135`.
- `MySQLAdapter.swift:863` — `private final class MySQLQueryTimeoutState: @unchecked Sendable`.

MySQL introspection SQL:
- `MySQLAdapter.swift:597` — `databases()` uses `SHOW DATABASES`.
- `MySQLAdapter.swift:607` — `tables(in:)` uses ``SHOW TABLES FROM `db` ``.
- `MySQLAdapter.swift:620` — `columns` uses `information_schema.COLUMNS` selecting `COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, ORDINAL_POSITION, COLUMN_DEFAULT, EXTRA`.
- `MySQLAdapter.swift:678` — `showCreateTable` uses `SHOW CREATE TABLE` via `simpleQuery`.
- `MySQLAdapter.swift:689` — `indexes` uses `SHOW INDEX FROM ... FROM ...`.
- `MySQLAdapter.swift:713` — `foreignKeys` uses `information_schema.KEY_COLUMN_USAGE`.
- `MySQLAdapter.swift:745` — `tableStatus` uses `SHOW TABLE STATUS FROM`.
- `MySQLAdapter.swift:754` — `tableStatusByNamespace` uses one `information_schema.TABLES` query aliased to the SHOW column names so one mapping serves both paths. Rationale at lines 749-753.
- `MySQLAdapter.swift:792` — comment records that exact SHOW TABLE STATUS counts are documented for MyISAM only, which is why `TableRowCountAccuracy` exists.
- `MySQLAdapter.swift:808` — exact `rowCount` falls back to `SELECT COUNT(*)`.

### 2.2 PostgreSQL

- `PostgreSQLAdapter.swift:15` — `public final class PostgreSQLEngine: DatabaseEngine, @unchecked Sendable`.
- `PostgreSQLAdapter.swift:17` — logger label `app.glassdb.postgresql`.
- `PostgreSQLAdapter.swift:20` — also two event-loop threads per engine instance.
- `PostgreSQLAdapter.swift:25-32` — capabilities: `transactions`, `parameterBinding`, `transportTLS`, `queryTimeout`, `metadata`, `schemas`, `indexes`, `foreignKeys`, `explain`, `serverVersion`, `cancellation`, `tableStatistics`, `aggregateTableStatistics`, `truncateTable`. Notably NOT `createTableDefinition`.
- `PostgreSQLAdapter.swift:113` — `actor PostgreSQLDatabaseConnection: DatabaseConnection`. The only true actor among the three.
- `PostgreSQLAdapter.swift:122` — `identifierQuoteCharacter` is the double quote, not the backtick.

PostgreSQL introspection SQL and per-engine differences:
- `PostgreSQLAdapter.swift:211-213` — **`databases()` returns schemas, not databases.** Documented rationale: the browser contract models the namespace containing tables, and PostgreSQL databases require a new connection and cannot be switched in-session. This is the single biggest semantic divergence from MySQL.
- `PostgreSQLAdapter.swift:217-220` — schema list from `information_schema.schemata`, excluding `information_schema` and `pg_%`.
- `PostgreSQLAdapter.swift:229` — `tables` from `information_schema.tables`.
- `PostgreSQLAdapter.swift:242-255` — `columns` from `information_schema.columns` with a correlated subquery over `table_constraints` joined to `key_column_usage` to derive primary keys.
- `PostgreSQLAdapter.swift:276-278` — **`showCreateTable` throws `unsupportedCapability(.createTableDefinition)`.** PostgreSQL has no server-side equivalent and none is synthesized.
- `PostgreSQLAdapter.swift:283-298` — `indexes` from `pg_class`, `pg_namespace`, `pg_index`, `pg_am`, with `LATERAL unnest(index.indkey) WITH ORDINALITY` to recover column order, and a `LEFT JOIN` to `pg_attribute`. Expression indexes surface as `<expression>` at line 304.
- `PostgreSQLAdapter.swift:316-322` — `foreignKeys` from `table_constraints`, `key_column_usage`, `constraint_column_usage`.
- `PostgreSQLAdapter.swift:345-353` — `tableStatus` from `pg_class` with `pg_total_relation_size` and a `LEFT JOIN` to `pg_stat_user_tables`.
- `PostgreSQLAdapter.swift:367-379` — `tableStatusByNamespace` is the same query without the namespace filter.
- `PostgreSQLAdapter.swift:421` — exact `rowCount` via `SELECT COUNT(*)` with quoted schema and table.

### 2.3 SQLite

- `SQLiteAdapter.swift:11` — `public final class SQLiteEngine: DatabaseEngine, Sendable`. Fully `Sendable`, not `@unchecked`, because it holds no state.
- `SQLiteAdapter.swift:16-22` — capabilities: `transactions`, `parameterBinding`, `queryTimeout`, `cancellation`, `metadata`, `schemas`, `indexes`, `foreignKeys`, `createTableDefinition`, `explain`, `serverVersion`, `tableStatistics`. Notably NOT `transportTLS` and NOT `aggregateTableStatistics`.
- `SQLiteAdapter.swift:25-27` — a dedicated `connect(path:readOnly:)` so filesystem state is not forced through network fields.
- `SQLiteAdapter.swift:129-150` — the protocol `connect` rejects any non-disabled TLS policy and requires port zero with empty credentials.
- `SQLiteAdapter.swift:36-124` — `createManagedSnapshot(from:at:fileManager:)` uses the SQLite online backup API. Comment at lines 31-34 states the reason: copying only the main file can omit committed pages still in the write-ahead log. Destination must not exist, is removed on any failure, 256-page steps, up to a hundred busy retries, then `PRAGMA quick_check` validation at line 152.
- `SQLiteAdapter.swift:177` — `final class SQLiteDatabaseConnection: DatabaseConnection, @unchecked Sendable`.
- `SQLiteAdapter.swift:208` — enables `PRAGMA foreign_keys = ON` on open.
- `SQLiteAdapter.swift:660` — `private final class SQLiteTimeoutState: @unchecked Sendable`.

SQLite introspection SQL:
- `SQLiteAdapter.swift:298` — `databases()` uses `PRAGMA database_list`.
- `SQLiteAdapter.swift:309` — `tables` from `sqlite_schema`.
- `SQLiteAdapter.swift:320` — `columns` via `PRAGMA table_xinfo`, which includes generated and hidden columns.
- `SQLiteAdapter.swift:343` — `showCreateTable` selects `sql` from `sqlite_schema`.
- `SQLiteAdapter.swift:356` and `:365` — `indexes` via `PRAGMA index_list` then `PRAGMA index_info` per index.
- `SQLiteAdapter.swift:399` — `foreignKeys` via `PRAGMA foreign_key_list`.
- `SQLiteAdapter.swift:413` — `tableStatus`.
- `SQLiteAdapter.swift:445` — `serverVersion`.
- `SQLiteAdapter.swift:453` — `explain`.

### 2.4 Timeout and cancellation differ per engine

- MySQL timeout is **client side**: `MySQLAdapter.swift:324-372` schedules an event-loop task and races it against the query. It does not use `MAX_EXECUTION_TIME`, so the server keeps running the statement.
- PostgreSQL timeout is **server side**: `PostgreSQLAdapter.swift:149-152` sets `statement_timeout` via `set_config`, then resets it to zero on every exit path at lines 155, 161, 170 and 180. It maps SQLSTATE `57014` to `DatabaseError.queryTimedOut` at lines 165 and 175.
- SQLite timeout is a watchdog plus `sqlite3_interrupt`, `SQLiteAdapter.swift:459`.
- `MySQLAdapter.swift:366-368` — `cancelCurrentQuery` **closes the transport**. Comment states mysql-nio does not expose `COM_PROCESS_KILL` for a live query.
- `PostgreSQLAdapter.swift:188-193` — `cancelCurrentQuery` **closes the connection**. Comment states postgres-nio 1.33 does not expose the cancel-request packet on a direct connection, and that this is deliberately an abortive cancellation that disconnects the session.
- `SQLiteAdapter.swift:269` and `:459` — the only engine that cancels without disconnecting.
- Port consequence: cancelling a running query on MySQL or PostgreSQL drops the session. Any merged UI must either keep that behaviour or add a second control connection.

### 2.5 Test coverage, measured

I ran `swift build` and `swift test` in `Packages/GlassDBKit`.

- `swift build` completed with exit status 0, no errors.
- `swift test` reported **28 tests in 3 suites passed** in 0.019 seconds.
- Suites: `QueryResultTests` at `Tests/GlassDBKitTests/GlassDBKitTests.swift:11`, `SQLiteAdapterTests` at line 454, `LiveEngineIntegrationTests` at line 629.
- 25 unit tests ran. Three live-database tests did **not** run because they are environment gated.
- `Tests/GlassDBKitTests/GlassDBKitTests.swift:630` — `mysqlPasswordlessCachingSHA2RoundTrip`, gated on `GLASSDB_MYSQL_PASSWORDLESS_TEST == "1"`.
- `Tests/GlassDBKitTests/GlassDBKitTests.swift:668` — `mysql8LiveRoundTrip`, gated on `GLASSDB_MYSQL_TEST_PASSWORD`.
- `Tests/GlassDBKitTests/GlassDBKitTests.swift:757` — `postgres17LiveRoundTrip`, gated on `GLASSDB_POSTGRES_TEST_PASSWORD`.
- `Tests/GlassDBKitTests/GlassDBKitTests.swift:738` — optional TLS variables `GLASSDB_MYSQL_TLS_CA_PATH` and `GLASSDB_MYSQL_TLS_SERVER_NAME`.
- `Tests/GlassDBKitTests/GlassDBKitTests.swift:846` — `private struct TestConnection: DatabaseConnection`, a test double used to prove the protocol-extension defaults throw correctly.

Unit tests that actually matter for the port, by name and line:
- `:18` `sshPendingBufferBudgetIsStrictlyBoundedAndResettable`
- `:56` `queryResultTruncationMetadataIsExplicit`
- `:84` `mysqlParameterBindingPreservesBoundaries`
- `:106` `mysqlBinaryDecodingPreservesTypedText`
- `:145` `mysqlTLSGreetingPreflightFailsClosed`
- `:161` `requiredTLSRejectsMissingAndMalformedTrustRootsBeforeNetworkUse`
- `:196` `sshTrustPolicyRejectsUnknownAndRotatedKeys`
- `:228` `sshConfigurationRejectsMalformedCredentialsAndEndpointsBeforeNetworkUse`
- `:257` `openSSHPrivateKeyDetectionRoutesRSAAndEd25519WithoutTextGuessing`
- `:290` `malformedAndLegacyPrivateKeysReturnActionableTunnelErrors`
- `:310` `CRLFEd25519PrivateKeyParsesWithoutNetworkUse`
- `:328` `identifiersAreQuotedAsOneComponent`
- `:335` `engineCapabilitiesAreExplicit`
- `:362` `aggregateTableStatusQueriesCoverEveryNamespaceInOneStatement`
- `:389` `postgresAggregateRowsMapFromTheSchemaPrefixedOffset`
- `:428` `postgresParameterBoundariesAreExplicit`
- `:455` `tableStatisticsExposeRealTablesAndExactRowCounts`
- `:476` `managedSnapshotCapturesCommittedWALPages`
- `:512` `bindingsPreserveNULAndRejectSmuggledOrMismatchedStatements`
- `:544` `realFileRoundTripMetadataTransactionsTimeoutAndCancellation`

App-level suite: `glassdbTests/glassdbTests.swift` contains 152 `@Test` declarations. I did not run it.

### 2.6 Completeness assessment

- `grep` for `TODO`, `FIXME`, `not implemented`, `unimplemented`, `stub` across `Packages/GlassDBKit/Sources` and `glassdb` returns **nothing**. Corroborated by `memory-bank/progress.md:15`.
- Nothing in the three drivers is stubbed. The two unsupported operations, PostgreSQL `showCreateTable` and MySQL `schemas`, are honestly advertised through the capability set rather than faked.

---

## 3. SSHTunnelManager: full contract and every call site

File: `Packages/GlassDBKit/Sources/GlassDBKit/SSHTunnelManager.swift`, 539 lines.

### 3.1 `SSHTunnelConfig` payload

- `SSHTunnelManager.swift:59` — `public struct SSHTunnelConfig: Sendable`.
- `SSHTunnelManager.swift:60-62` — `sshHost: String`, `sshPort: Int`, `sshUsername: String`.
- `SSHTunnelManager.swift:63` — **`sshPassword: String?`, a raw plaintext password.**
- `SSHTunnelManager.swift:64` — **`sshPrivateKey: String?`, raw private key text.**
- `SSHTunnelManager.swift:65` — **`sshKeyPassphrase: String?`, raw passphrase.**
- `SSHTunnelManager.swift:66-67` — `remoteHost: String`, `remotePort: Int`, defaulting to `127.0.0.1` and 3306 at lines 79-80.
- `SSHTunnelManager.swift:68-69` — `trustedHostKeys: Set<Data>`, described as previously confirmed complete SSH wire-format host keys for this host and port.
- `SSHTunnelManager.swift:70` — `algorithmPolicy: SSHAlgorithmPolicy`, defaulting to `.modernOnly` at line 82.
- There is **no** `SecureBytes` anywhere in this type. All three secrets are ordinary heap strings.
- The struct owns no trust storage. Trust is supplied by the caller on every call.

### 3.2 Establish

- `SSHTunnelManager.swift:97` — `public final class SSHTunnelManager: Sendable`.
- `SSHTunnelManager.swift:100-102` — `init()` allocates its own `MultiThreadedEventLoopGroup(numberOfThreads: 1)`. One group per manager.
- `SSHTunnelManager.swift:107` — `public func establish(config:) async throws -> SSHTunnel`. The only entry point.
- `SSHTunnelManager.swift:108-114` — validation: non-empty trimmed `sshHost`, `sshUsername`, `remoteHost`, and both ports within `1...65535`. Failure throws `SSHTunnelError.invalidConfiguration`.
- `SSHTunnelManager.swift:116-127` — auth selection. **Key wins unconditionally.** If `sshPrivateKey` is non-nil the password is never consulted. With neither, `SSHTunnelError.noAuthMethod`.
- `SSHTunnelManager.swift:129-135` — creates the challenge box and `PinnedSSHHostKeyValidator`.
- `SSHTunnelManager.swift:138-145` — `SSHClient.connect` with `hostKeyValidator: .custom(...)`, **`reconnect: .never`**, and `algorithms:` from the policy.
- `SSHTunnelManager.swift:146-151` — on any connect failure it checks the challenge box first and converts to `SSHHostKeyTrustRequiredError`, otherwise rethrows.
- `SSHTunnelManager.swift:154-167` — `ServerBootstrap` with `SO_REUSEADDR`, installing one `LocalToSSHForwarder` per accepted local connection.
- `SSHTunnelManager.swift:169` — **binds `127.0.0.1` port `0`.** The local port is kernel-assigned and cannot be configured or predicted.
- `SSHTunnelManager.swift:171-174` — missing local address or port throws `SSHTunnelError.bindFailed`.
- `SSHTunnelManager.swift:176-180` — returns `SSHTunnel(localPort:serverChannel:sshClient:)`.

### 3.3 Reconnect, teardown, and lifecycle gaps

- `SSHTunnelManager.swift:143` — **`reconnect: .never`. There is no reconnect at any layer of this file.**
- There is no keepalive, no heartbeat, and no liveness probe anywhere in the file.
- `SSHTunnelManager.swift:339-348` — `SSHTunnel` exposes only `localPort` publicly. `serverChannel` and `sshClient` are private.
- `SSHTunnelManager.swift:350-355` — `close()` is the entire teardown: close the listener if active, then close the SSH client. In-flight child channels are not drained and are not awaited.
- `SSHTunnelManager.swift:258-260` — **`deinit` calls `try? eventLoopGroup.syncShutdownGracefully()`.** A blocking shutdown inside a deinitializer, which can run on an event-loop thread. This is a real hazard and should become an explicit async shutdown in the shared engine.
- Session-level reconnect is implemented elsewhere and does not reuse a tunnel: `glassdb/DatabaseSessionManager.swift:322` builds an entirely new session and swaps it in at line 340.

### 3.4 Host key trust

- `SSHTunnelManager.swift:267` — `private final class PinnedSSHHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable`.
- `SSHTunnelManager.swift:279` — host is trimmed and lowercased for comparison.
- `SSHTunnelManager.swift:285-303` — `validateHostKey` serializes the key to wire format, asks the policy for a challenge, succeeds if nil, otherwise stores the challenge and fails the promise.
- `SSHTunnelManager.swift:306-337` — `enum SSHHostKeyTrustPolicy`, internal not public.
- `SSHTunnelManager.swift:313` — trusted if the exact wire bytes are in the set. Byte equality, no parsing.
- `SSHTunnelManager.swift:320` — **reason is `.unknown` when `trustedKeys` is empty, `.changed` otherwise.** This single bit drives the destructive-button styling in the UI.
- `SSHTunnelManager.swift:324-329` — algorithm name parsed from the leading length-prefixed field, defaulting to `"unknown"` on malformed input.
- `SSHTunnelManager.swift:331-336` — fingerprint is `SHA256:` plus unpadded Base64 of the SHA-256 digest, matching OpenSSH's display format.
- `SSHTunnelManager.swift:25-33` — `SSHHostKeyChallenge` carries `host`, `port`, `algorithm`, `fingerprintSHA256`, `publicKeyData`, `reason`.

### 3.5 Key material handling

- `SSHTunnelManager.swift:190-214` — `public static func detectPrivateKeyAlgorithm(from:) throws -> SSHPrivateKeyAlgorithm`.
- `SSHTunnelManager.swift:192-194` — a `SECURE_ENCLAVE_P256:` string prefix selects the Secure Enclave path.
- `SSHTunnelManager.swift:195-198` — **legacy PEM headers are rejected explicitly** with `unsupportedPrivateKeyFormat`.
- `SSHTunnelManager.swift:201-208` — otherwise delegates to Citadel's `SSHKeyDetection`, accepting only RSA and Ed25519.
- `SSHTunnelManager.swift:216-249` — `static func authenticationMethod(username:privateKey:passphrase:)`, internal not public.
- `SSHTunnelManager.swift:225-230` — Secure Enclave path Base64-decodes the suffix into `P256.Signing.PrivateKey(rawRepresentation:)`.
- `SSHTunnelManager.swift:232-236` — RSA via `Insecure.RSA.PrivateKey(sshRsa:decryptionKey:)`.
- `SSHTunnelManager.swift:237-242` — Ed25519 via `Curve25519.Signing.PrivateKey(sshEd25519:decryptionKey:)`.
- `SSHTunnelManager.swift:251-256` — `normalizedPrivateKey` normalizes CRLF and CR to LF and trims. This is why the CRLF test at `GlassDBKitTests.swift:310` exists.
- `SSHTunnelManager.swift:183-188` — `algorithms(for:)` returns a default-constructed `SSHAlgorithms()` for the only policy case. **`SSHAlgorithmPolicy` is a placeholder, not a functioning policy.**

### 3.6 Data forwarding

- `SSHTunnelManager.swift:361` — `private final class LocalToSSHForwarder: ChannelInboundHandler, @unchecked Sendable`.
- `SSHTunnelManager.swift:380-427` — `channelActive` opens a `createDirectTCPIPChannel` to `remoteHost:remotePort` with originator `127.0.0.1:0`.
- `SSHTunnelManager.swift:405` — **explicitly hops back to the local channel's event loop** before touching handler state, to avoid racing `channelRead`. This is the correct pattern and should survive the port.
- `SSHTunnelManager.swift:410-413` — if the local channel died or is closing while the SSH channel was opening, the new channel is closed immediately.
- `SSHTunnelManager.swift:416-420` — flushes buffered bytes then resets the budget.
- `SSHTunnelManager.swift:429-449` — `channelRead` forwards directly if ready, otherwise reserves budget and buffers; on budget failure it closes.
- `SSHTunnelManager.swift:451-463` — `channelInactive` and `errorCaught` both set `isClosing`, drop buffers, and close.
- `SSHTunnelManager.swift:468` — `struct PendingTunnelBufferBudget`, internal so it can be unit tested.
- `SSHTunnelManager.swift:469` — `static let maximumBytes = 1_048_576`, one megabyte cap on pre-connect buffering.
- `SSHTunnelManager.swift:473-480` — `reserve(bytes:)` rejects negatives, oversize single writes, and cumulative overflow.
- `SSHTunnelManager.swift:490` — `private final class SSHToLocalForwarder: ChannelInboundHandler, @unchecked Sendable`, the return path.
- `SSHTunnelManager.swift:487-489` — comment notes Citadel's `DataToBufferCodec` already unwraps `SSHChannelData`, so these handlers see raw `ByteBuffer`.

### 3.7 Error surface

- `SSHTunnelManager.swift:509` — `public enum SSHTunnelError: Error, LocalizedError`.
- `SSHTunnelManager.swift:510-517` — `noAuthMethod`, `invalidConfiguration`, `invalidPrivateKey`, `unsupportedPrivateKeyAlgorithm(String)`, `unsupportedPrivateKeyFormat`, `bindFailed`, `tunnelClosed`, `pendingBufferLimitExceeded(maximumBytes:)`.
- `SSHTunnelManager.swift:519-538` — every case has an actionable user-facing message.
- `SSHTunnelManager.swift:516` — `tunnelClosed` is declared but I found no site that throws it. Dead case.
- `SSHTunnelManager.swift:35-46` — `SSHHostKeyTrustRequiredError` message differs by reason, naming host, port, algorithm and fingerprint.

### 3.8 Every call site in the app, with its assumptions

Six references exist. Only two establish a tunnel.

**A. Connect path.** `glassdb/DatabaseSessionManager.swift:120-162`.
- `:120-122` — gated on `config.useSSHTunnel` plus non-nil `sshHost` and `sshUsername`.
- `:123` — sets session state to `.connecting(stage: .establishingSSHTunnel)`.
- `:129-133` — if `sshAuthMethod == .sshKey`, retrieves key material via `KeychainManager.retrieveSSHKey(for: keyID)` and **converts `SecureBytes` to plain `String` via `toUTF8String()`**.
- `:135` — constructs a **fresh `SSHTunnelManager()` per connection**, so a fresh event-loop group per connection.
- `:137-141` — reads trusted keys from `SSHHostTrustKeychainStore.authorizedRecords(host:port:config:)` using `KeychainManager.config`, which is the shared Glass access group.
- `:142-155` — builds the config. Assumes `remoteHost`/`remotePort` are the **database** host and port from the saved record, not a separate forward target.
- `:146-149` — routes the password through `Self.tunnelPassword(sshPassword:hasPrivateKey:)`.
- `:154` — maps trusted records to `Set(trustedHostKeys.map(\.publicKeyData))`.
- `:156-158` — establishes and stores both tunnel and manager on the session.
- `:160` — captures `tunnel.localPort` into `tunnelLocalPort`.
- `:185-189` — on any failure in the enclosing `do`, closes the tunnel and nils both references.
- Assumption: `glassdb/DatabaseSessionManager.swift:212-217` — `tunnelPassword` returns nil when a private key is present, so **a keyed tunnel never also receives a password** and a missing SSH password never falls back to the database password.

**B. SSH-only test path.** `glassdb/DatabaseSessionManager.swift:275-317`.
- `:276-280` — throws `SSHTunnelError.noAuthMethod` if the config is not a tunnel config. Slight misuse of that case as a guard.
- `:284-288` — same `SecureBytes` to `String` conversion.
- `:291-295` — same trusted-key read.
- `:296-306` — builds the config, inlining the key-beats-password rule at line 300 rather than calling `tunnelPassword`. Duplicated logic worth unifying in the port.
- `:307-310` — creates a manager, establishes, then immediately closes with `try? await tunnel.close()`.
- `:311-316` — wraps failures through `actionableConnectionError` so a pending local-network prompt reads as actionable.

**C. Session storage.** `glassdb/DatabaseSessionManager.swift:1066-1067`.
- `var tunnel: SSHTunnel?` and `var tunnelManager: SSHTunnelManager?` on the `@MainActor @Observable class DatabaseSession` declared at line 1061.
- Assumption: the manager must outlive the tunnel, since its event-loop group backs the listener. Holding both is deliberate.

**D. Key import classification.** `glassdb/SettingsView.swift:569-578`.
- Calls `SSHTunnelManager.detectPrivateKeyAlgorithm(from:)` purely to map into the UI's own `SSHKeyAlgorithmKind`.
- Assumption: the three-case return maps one-to-one onto `.rsa`, `.ed25519`, `.ecdsaP256`. A fourth algorithm added to the kit breaks this switch at compile time, which is the desired behaviour.
- No tunnel is created on this path.

**E. Trust challenge capture.** `glassdb/ConnectionManagerView.swift:20-24` and `:1100-1106`.
- `:20` — `private struct PendingHostTrustAttempt` holds `connection`, `password`, `sshPassword`, `challenge`.
- `:24` — `let challenge: SSHHostKeyChallenge`.
- `:1100-1106` — catches `SSHHostKeyTrustRequiredError` and stores the attempt.
- Assumption, and a secrets concern: **the pending attempt retains both the database password and the SSH password as plain `String` in SwiftUI `@State`** so it can replay the connect after the user trusts the key.

**F. Trust persistence and retry.** `glassdb/ConnectionManagerView.swift:176-187`, `:1151-1163`, and `glassdb/KeychainManager.swift:449-464`.
- `:176` — alert title switches on `challenge.reason == .changed`.
- `:182` — the Trust and Retry button takes `role: .destructive` only for a changed key.
- `:187` — the alert body shows the challenge fingerprint.
- `:1151-1154` — on confirm, calls `KeychainManager.saveHostKey(attempt.challenge)` then clears the attempt.
- `glassdb/KeychainManager.swift:450-456` — builds a `PinnedSSHHostKey` from the challenge.
- `glassdb/KeychainManager.swift:457-463` — **`.changed` uses `SSHHostTrustKeychainStore.replace`, first use uses `save`.** Comment at lines 458-459 states replace preserves revoked history for audit while advancing the only generation permitted to authorize the endpoint.

**Cross-cutting assumptions the shared SSH engine must preserve:**
1. The tunnel always binds loopback; the database client connects to `127.0.0.1:localPort`.
2. TLS server-name verification is redirected to the real host via `.requiredSystemTrustForHost`, `glassdb/DatabaseSessionManager.swift:238-244`. Losing this silently breaks certificate validation through tunnels.
3. Trust storage is the caller's job; the engine must accept an injected key set.
4. Key material beats password, always.
5. Reconnect is not a tunnel concern; the session layer rebuilds from scratch.
6. The macOS sandbox needs `com.apple.security.network.server` for the local listener, `glassdb/glassdb-macOS.entitlements`.

---

## 4. Credentials and secrets

### 4.1 GlasSecretStore is used throughout

- `glassdb/KeychainManager.swift:5` — file header states it is a thin wrapper delegating to `KeychainOperations` and `SSHKeyKeychainStore`.
- `glassdb/KeychainManager.swift:10` — `import GlasSecretStore`.
- Consumers: `glassdb/DatabaseSessionManager.swift:10`, `glassdb/SettingsManager.swift:12`, `glassdb/ConnectionFormView.swift:12`, `glassdb/SettingsView.swift:10`, `glassdb/ConnectionManagerView.swift:14`.
- Three store types are used: `KeychainOperations`, `SSHKeyKeychainStore`, `SSHHostTrustKeychainStore`.

### 4.2 Three storage configurations

- `glassdb/KeychainManager.swift:152-157` — `sharedConfig`, prefix `sh.glas`, access group from `resolvedAccessGroup`, legacy prefixes `["app.glassdb"]`.
- `glassdb/KeychainManager.swift:159-163` — `appOnlyConfig`, prefix `app.glassdb.private`, **no access group**.
- `glassdb/KeychainManager.swift:165-169` — `authenticatedConfig`, prefix `app.glassdb.protected`, no access group.
- `glassdb/KeychainManager.swift:171-175` — `useDataProtectionKeychain` is true on macOS, false elsewhere.
- `glassdb/KeychainManager.swift:177-188` — access group resolution: visionOS hardcodes `7JQGQ7CRH8.sh.glas.shared`; macOS and iOS read Info.plist key `GlasKeychainAccessGroup`.
- `glassdb/KeychainManager.swift:194-206` — `validatedSharedAccessGroup` rejects empty values, unexpanded `$(` build variables, and anything whose suffix is not exactly `sh.glas.shared` with a ten-character uppercase alphanumeric team prefix.
- `glassdb/KeychainManager.swift:190-192` — `sharedCredentialAccessAvailable` is simply whether the group resolved.
- `glassdb/KeychainManager.swift:210` — `static let config = sharedConfig`, with the comment that SSH keys and host pins remain intentionally shared with glas.sh.

### 4.3 Policy model and eligibility

- `glassdb/Models.swift:228` — `enum CredentialStoragePolicy: String, Codable, CaseIterable, Identifiable, Sendable`.
- `glassdb/Models.swift:229-231` — `sharedWithGlas`, `glassdbOnly`, `requireAuthentication`.
- `glassdb/Models.swift:243-252` — policy descriptions: shared is available to glassdb and glas.sh while the device is unlocked; glassdbOnly is a private device-only namespace; requireAuthentication demands device-owner auth before every use.
- `glassdb/Models.swift:254-259` — **`databasePolicies` excludes `sharedWithGlas` entirely.** Database secrets are never shared across the family by design, because glas.sh has no use for them.
- `glassdb/Models.swift:264-266` — `sshManualPolicies` also excludes shared; sharing is a separate opt-in.
- `glassdb/Models.swift:271-277` — `sshPolicy(shareWithGlas:manualPolicy:)`. Sharing wins; a stray shared value without the opt-in collapses to private.
- `glassdb/Models.swift:104-113` — **on decode, any database policy of `sharedWithGlas` is rewritten to `glassdbOnly`.** Legacy records are normalized to private on read.
- `glassdb/Models.swift:114-120` — SSH policy defaults to `sharedWithGlas` on decode, preserving pre-G04 record locations. Comment states SSH identity is the shareable class.
- `glassdb/KeychainManager.swift:647-684` — `descriptor(for:kind:)` maps policy to config, access policy, and prompt. `requireAuthentication` maps to `SecretAccessPolicy.userPresence` at line 668 with per-kind prompts at lines 669-671.
- There is **no CloudKit or iCloud Keychain sync** anywhere in this app. Mobility is entirely GlasSecretStore's concern; glassdb never declares a sync attribute.

### 4.4 Account naming

- `glassdb/KeychainManager.swift:530-532` — `databaseAccount` via `GlassFamilyCredentialAccount.databasePassword(profileID:)`, keyed on connection UUID.
- `glassdb/KeychainManager.swift:534-536` — `sshAccount` via `GlassFamilyCredentialAccount.sshPassword(profileID:)`.
- `glassdb/KeychainManager.swift:538-540` — legacy database account was `user@host:port`.
- `glassdb/KeychainManager.swift:542-544` — legacy SSH account was `ssh:user@host:port`.
- `glassdb/KeychainManager.swift:633-645` — `sharedSSHCompatibilityAccount` writes the endpoint-shaped alias `ssh:user@host:port` **in addition to** the UUID record, but only when the policy is shared and auth is not a key. Comment at lines 546-548 explains glas.sh uses the alias while glassdb keeps the UUID primary.

### 4.5 Save, retrieve, delete

- `glassdb/KeychainManager.swift:214-219` — `savePassword(_:for:)`.
- `glassdb/KeychainManager.swift:221-240` — `retrievePassword(for:)` with a legacy fallback that only runs for shared policy and, on success, rewrites the value into the current location.
- `glassdb/KeychainManager.swift:242-247` — `deletePassword(for:)`.
- `glassdb/KeychainManager.swift:251-269` — `saveSSHPassword` writes both the UUID record and, for shared policy, the compatibility alias.
- `glassdb/KeychainManager.swift:271-290` — `retrieveSSHPassword` with the same fallback-and-rewrite behaviour.
- `glassdb/KeychainManager.swift:302-308` — `saveCredentials(databasePassword:sshPassword:for:replacing:store:)` returns a `CredentialPersistenceReport`.
- `glassdb/KeychainManager.swift:299-301` — comment: every destination is saved and verified before prior-policy records are removed, and every touched record is snapshotted first so a later failure restores the complete pre-mutation state.
- `glassdb/KeychainManager.swift:122-130` — `CredentialSnapshot` and `CredentialDeletionReceipt` implement that rollback.
- `glassdb/KeychainManager.swift:132-150` — `CredentialPolicyError` covers auth unavailable, auth cancelled, verification failed, and rollback failed, each with a specific message.
- `glassdb/ConnectionManager.swift:241` and `:247` — delete stages a credential receipt and restores it if persistence fails, escalating to `credentialRollbackFailed` at line 249.

### 4.6 SSH keys and host pins

- `glassdb/KeychainManager.swift:433-437` — `saveSSHKey` wraps the key and passphrase in `SecureBytes` before calling `SSHKeyKeychainStore.save`.
- `glassdb/KeychainManager.swift:439-441` — `retrieveSSHKey` returns `SSHKeyMaterial`, whose fields are `SecureBytes`.
- `glassdb/KeychainManager.swift:443-445` — `deleteSSHKey`.
- `glassdb/KeychainManager.swift:449-464` — `saveHostKey(_:)` described in section 3.8F.
- `glassdb/DatabaseSessionManager.swift:137-141` and `:291-295` — `SSHHostTrustKeychainStore.authorizedRecords(host:port:config:)` is the read side.
- Host pins and SSH keys both live in `sharedConfig`, the family access group, deliberately.

### 4.7 Enumeration reads attributes only

- `glassdb/KeychainManager.swift:607-631` — `sharedSSHCredentialIdentities()` queries with `kSecReturnAttributes: true` and **no `kSecReturnData`**, so secret bytes never leave the Keychain on this path.
- `glassdb/KeychainManager.swift:624-627` — maps account strings back to identities and deduplicates.
- `glassdb/KeychainManager.swift:554-561` — `retrieveSharedSSHPassword(for:)` reads the shared endpoint record when glas.sh owns the credential and glassdb has no private copy. Rationale at lines 551-553.

### 4.8 Plaintext exposure, the actual findings

- **Finding 1, the main one.** `glassdb/DatabaseSessionManager.swift:131-132` and `:286-287` call `toUTF8String()` on the `SecureBytes` returned by `SSHKeyKeychainStore`, producing plain `String` private key and passphrase that are then stored in `SSHTunnelConfig` at `SSHTunnelManager.swift:64-65`. **The SecureBytes protection is discarded for the lifetime of the tunnel config.** A shared SSH engine should accept `SecureBytes` directly.
- **Finding 2.** `glassdb/SettingsManager.swift:36-43` also round-trips key material through `String` when saving.
- **Finding 3.** `glassdb/ConnectionManagerView.swift:20-24` retains both passwords as plain `String` in SwiftUI state across the host-trust prompt.
- **Finding 4.** `glassdb/ConnectionManagerView.swift:1069-1082` and `glassdb/DatabaseSessionManager.swift:987-1009` substitute the empty string on `SecretStoreError.notFound` rather than failing, so a missing credential becomes an empty-password authentication attempt.
- **Nothing is written to disk in plaintext.** No credential reaches UserDefaults, the App Group container, or any file.
- **Nothing is logged.** `glassdb/DatabaseSessionManager.swift:170` logs host, port, username and engine only. `glassdb/ConnectionManager.swift:190` explicitly logs migration failures "without exposing credential material".
- `.gitleaks.toml` exists at the repo root, so secret scanning is configured.

---

## 5. Persistence

### 5.1 Storage technology

- **Everything is UserDefaults plus JSON `Codable`.** There is no SwiftData, no Core Data, and no SQLite-backed app store anywhere in `glassdb/`.

### 5.2 Exact keys

All defined in `glassdb/Constants.swift:18-36`.

- `:19` — `glassdb.connections`, the connection list.
- `:20` — `glassdb.savedQueries`.
- `:21` — `glassdb.queryHistory`.
- `:22` — `glassdb.sshKeys`, local SSH key metadata.
- `:25` — `glassdb.maxQueryHistoryItems`.
- `:26` — `glassdb.resultRowLimit`.
- `:27` — `glassdb.windowOpacity`.
- `:28` — `glassdb.blurBackground`.
- `:29` — `glassdb.showSidebarByDefault`.
- `:30` — `glassdb.editorFontSize`.
- `:31` — `glassdb.dataGridFontSize`.
- `:32` — `glassdb.showLineNumbers`.
- `:33` — `glassdb.autoFormatJSONInRecordEditor`.
- `:34` — `glassdb.redactQueryHistoryLiterals`.
- `:35` — `glassdb.queryFailureNotificationPreference`.

Outside that enum:
- `glassdb/Models.swift:410` — `glassdb.mutationAudit.v1`, the mutation audit log, capped at 1,000 records at line 411 with oldest-first trimming at lines 419-421.
- `glassdb/KeychainManager.swift:19` — `app.glassdb.connectionCredentialMigrationVersion`, current version 2 at line 20.
- `glassdb/SettingsManager.swift:104` — `sshKeys`, the key name **inside the shared App Group suite**, not the standard suite.
- `glassdb/Constants.swift:64` — `app.glassdb.connection-library.columns`, the AppKit split-view autosave name.

### 5.3 File and container paths

- `glassdb/SettingsManager.swift:103` — `UserDefaults(suiteName: "group.sh.glas.shared")` for shared SSH key metadata.
- `glassdb/ConnectionManagerView.swift:272-279` — App Group container resolved via `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.sh.glas.shared")`, then `GlassHostCatalog/hosts.json`.
- `glassdb/ConnectionManager.swift:175` — `HostCatalogDeletionOutbox.applicationSupport(applicationIdentifier: "app.glassdb")`.
- `glassdb/ConnectionFormView.swift:36-53` — imported SQLite files are copied into Application Support under `glassdb/SQLite Databases`.
- `glassdb/glassdb.entitlements` and `glassdb/glassdb-macOS.entitlements` declare app group `group.sh.glas.shared` and keychain group `$(AppIdentifierPrefix)sh.glas.shared`.
- `glassdb.xcodeproj/project.pbxproj:422` — `PRODUCT_BUNDLE_IDENTIFIER = app.glassdb`.
- `glassdb.xcodeproj/project.pbxproj:363` — `DEVELOPMENT_TEAM = 7JQGQ7CRH8`.

### 5.4 Host catalog publication, and yes it publishes

- `glassdb/ConnectionManager.swift:11-12` — imports `GlassConnectionKit` and `GlassHostCatalog`.
- `glassdb/ConnectionManagerView.swift:260-268` — `familyHostPublications` maps each saved connection to a `HostPublication` with `HostServiceLink(endpointID: EndpointID(rawValue: saved.id), kind: .database, displayName: saved.name)`, `hostName: saved.name`, and aliases `[saved.host]` except for SQLite which publishes no alias.
- `glassdb/ConnectionManagerView.swift:270-290` — `publishFamilyHosts()` resolves the App Group, builds a `HostCatalogStore(fileURL:)`, flushes the deletion outbox, then calls `catalog.publish(...)`.
- `glassdb/ConnectionManagerView.swift:67` — triggered by `.task(id:)` keyed on the publication set once the catalog has loaded.
- `glassdb/ConnectionManagerView.swift:69` — re-published on scene phase becoming `.active`.
- `glassdb/ConnectionManager.swift:240` — `familyDeletionOutbox.stage(endpointID:)` runs **before** the credential and catalog transaction, so removal intent is durable even if the app dies mid-delete.
- `glassdb/ConnectionManagerView.swift:283` — the outbox is flushed with the current active endpoint set before publishing.
- `glassdb/ConnectionManagerView.swift:284-286` — a cancellation check between flush and publish, with a comment that metadata must be re-read after awaiting the outbox.
- `glassdb/ConnectionManager.swift:195` and `:198` — `familyCatalogLoaded` gates publication so an empty in-memory list never wipes the shared catalog.

Inbound direction:
- `glassdb/glassdbApp.swift:193-197` and `:235-239` — `onOpenURL` parses `GlassConnectionLink(url:)` and acts only on `.database(id)`, setting `externalConnectionRequest`. URL parsing lives in GlassConnectionKit, not in this app.

### 5.5 Connections, queries, history, settings

- `glassdb/ConnectionManager.swift:33-57` — `ConnectionPersistenceStore` with `load`, `save`, `restore` closures. `save` performs a **read-back verification** at line 42 and throws `readbackMismatch` if the write did not stick.
- `glassdb/ConnectionManager.swift:304-320` — `persist(_:)` snapshots previous data, writes, and on failure restores and verifies, escalating to `rollbackFailed`.
- `glassdb/ConnectionManager.swift:203` — decode is `JSONDecoder().decode([DatabaseConnectionConfig].self, from: data)`.
- `glassdb/ConnectionManager.swift:205-208` — a decode failure logs and resets `connections` to empty **without** clearing `familyCatalogLoaded`, which is why the publication guard at line 271 matters.
- `glassdb/ConnectionManager.swift:257-276` — deleting or re-pointing a SQLite connection removes the managed file if no other connection references it.
- `glassdb/DatabaseSessionManager.swift:913` and `:929` — query history load and save against `UserDefaultsKeys.queryHistory`.
- `glassdb/DatabaseSessionManager.swift:876-877` — per-session history trimmed to `maxHistory`.
- `glassdb/DatabaseSessionManager.swift:895` — history literals are redacted when `glassdb.redactQueryHistoryLiterals` is set.
- `glassdb/DatabaseSessionManager.swift:1124-1158` — `QueryHistoryEntry: Identifiable, Codable, Hashable, Sendable` with `sql`, `timestamp`, `duration`, `rowCount`, `affectedRows`, `error`, `database`, `connectionID`, `safety`.
- `glassdb/SettingsManager.swift:121-122` — `savedQueries: [SavedQuery]` and `sshKeys: [StoredSSHKey]` are in-memory projections of the persisted JSON.
- `glassdb/SettingsManager.swift:105-109` — shared SSH key catalog bounds: 1 MB total, 4,096 entries, 256-byte names, 1 MB private keys, 4,096-byte passphrases.
- `glassdb/SettingsManager.swift:51-75` — `SSHMetadataPersistenceError` covers app-group unavailable, invalid catalog, too large, read-back mismatch, Keychain read-back mismatch, and rollback failed.
- `glassdb/DatabaseSessionManager.swift:492-519` — **row bounding lives here, not in GlassDBKit.** It appends a limit to the SQL, fetches one extra sentinel row, sets `isTruncated` when the extra row appears at line 506, then trims at line 511 and records `appliedRowLimit` at line 518.

### 5.6 Versioning

- **The only schema versioning is a hand-written decoder.** `glassdb/Models.swift:89-127` uses `decodeIfPresent` with defaults for every field added after v1: `engine`, `useSSHTunnel`, `sshHost`, `sshPort`, `sshUsername`, `sshAuthMethod`, `sshKeyID`, both credential policies, `useTLS`, `isFavorite`, `colorTag`, `dateAdded`, `lastConnected`, `tags`.
- `glassdb/Models.swift:195-208` — `DatabaseEngineType` has a custom decoder accepting `mariadb` as `mysql`, and `postgres` / `postgres-nio` as `postgresql`, throwing on anything else.
- `glassdb/KeychainManager.swift:469-528` — the credential migration is separately versioned, gated at line 476, and only records success at line 523 when there were zero failures.
- There is **no** stored schema version number for the connection list itself. Forward compatibility rests entirely on defaulted decoding.

---

## 6. Concurrency

### 6.1 Strict concurrency status

- `glassdb.xcodeproj/project.pbxproj:428`, `:538`, `:565`, `:593` — `SWIFT_STRICT_CONCURRENCY = complete` in **every** build configuration.
- `glassdb.xcodeproj/project.pbxproj:429`, `:539`, `:566`, `:594` — `SWIFT_VERSION = 6.0`.
- `Packages/GlassDBKit/Package.swift:1` — swift-tools-version 6.2 with no `swiftLanguageModes` override, so Swift 6 mode.
- **Measured:** `swift build` in `Packages/GlassDBKit` completed with exit status 0 and no errors. `swift test` passed 28 of 28.
- `../GlassConnectionKit/Package.swift` ends with `swiftLanguageModes: [.v6]`, so the shared library is also Swift 6.

### 6.2 Actors and isolation boundaries

- `Packages/GlassDBKit/Sources/GlassDBKit/PostgreSQLAdapter.swift:113` — `actor PostgreSQLDatabaseConnection: DatabaseConnection`. The only true actor in the kit.
- `PostgreSQLAdapter.swift:114-122` — `nonisolated let` for `engineName`, `dialect`, `capabilities`, `identifierQuoteCharacter`, so metadata reads do not hop.
- `glassdb/DatabaseSessionManager.swift:14-16` — `@MainActor @Observable class DatabaseSessionManager`.
- `glassdb/DatabaseSessionManager.swift:1059-1061` — `@MainActor @Observable class DatabaseSession`.
- `glassdb/ConnectionManager.swift:158-160` — `@MainActor @Observable class ConnectionManager`.
- `glassdb/SettingsManager.swift:100-102` — `@MainActor @Observable class SettingsManager`.
- `glassdb/Models.swift:408-409` — `@MainActor enum MutationAuditStore`.
- `glassdb/AIAssistant.swift:157` — `@MainActor`.
- `glassdb/GlassEditorAdapters.swift:105` and `:522` — `@MainActor`.
- `glassdb/Constants.swift:316`, `:631`, `:736`, `:933`, `:970`, `:1238`, `:1244` — additional `@MainActor` declarations, plus `@MainActor let` toolbar placements at lines 882-898.
- `glassdb/DatabaseSessionManager.swift:212` and `:219` — `nonisolated static func tunnelPassword` and `transportPlan`, deliberately isolation-free so they are unit-testable and callable off the main actor.
- `glassdb/DatabaseSessionManager.swift:973` — `private nonisolated static func actionableConnectionError`.
- Model layer: `DatabaseConnectionConfig` is a `Codable, Hashable` struct; `QueryHistoryEntry`, `MutationAuditRecord`, `DatabaseStatisticsSnapshot` are all `Sendable` structs. **No mutable reference type crosses an isolation boundary unguarded.**

### 6.3 Every `@unchecked Sendable`, with justification

In GlassDBKit:
- `SSHTunnelManager.swift:339` — `SSHTunnel`. Holds a `Channel` and `SSHClient`, neither `Sendable`. Confinement is by NIO convention.
- `SSHTunnelManager.swift:361` — `LocalToSSHForwarder`. Mutable state is confined to the local channel's event loop, with an explicit hop at line 405 to preserve that.
- `SSHTunnelManager.swift:490` — `SSHToLocalForwarder`. Holds only a `Channel` reference.
- `MySQLAdapter.swift:15` — `MySQLEngine`. Holds an `EventLoopGroup`.
- `MySQLAdapter.swift:146` — `MySQLTLSCapabilityProbe`. Event-loop confined.
- `MySQLAdapter.swift:215` — `MySQLDatabaseConnection`. Event-loop confined.
- `MySQLAdapter.swift:863` — `MySQLQueryTimeoutState`. A one-shot fire/complete latch.
- `PostgreSQLAdapter.swift:15` — `PostgreSQLEngine`. Holds an `EventLoopGroup`.
- `SQLiteAdapter.swift:177` — `SQLiteDatabaseConnection`. Serial-queue confined around a raw `OpaquePointer`.
- `SQLiteAdapter.swift:660` — `SQLiteTimeoutState`.

In the app, all four are function-holder injection seams for testing, not shared mutable state:
- `glassdb/KeychainManager.swift:30` — `CredentialMigrationStore`.
- `glassdb/KeychainManager.swift:100` — `CredentialMutationStore`.
- `glassdb/ConnectionManager.swift:33` — `ConnectionPersistenceStore`.
- `glassdb/SettingsManager.swift:22` — `SSHKeyLifecycleStore`.

### 6.4 Preconcurrency suppressions

- `SSHTunnelManager.swift:12` — `@preconcurrency import Citadel`.
- `SSHTunnelManager.swift:16` — `@preconcurrency import NIOSSH`.
- These two are the concurrency debt the merge inherits. They exist because the vendored Citadel and NIOSSH copies predate Swift 6 annotations.

### 6.5 Safety observations

- **No `nonisolated(unsafe)` anywhere** in `glassdb/` or `Packages/GlassDBKit/Sources/`.
- **No `unsafeFlags`** in any manifest.
- `SSHTunnelManager.swift:264` — the challenge box uses `Mutex<SSHHostKeyChallenge?>` from `Synchronization`, a correct modern primitive.
- `SSHTunnelManager.swift:405-421` — the deliberate event-loop hop is the single most important correctness detail in the forwarder and must survive the port verbatim.
- **Known hazard:** `SSHTunnelManager.swift:258-260`, blocking `syncShutdownGracefully()` in `deinit`. Same pattern at `MySQLAdapter.swift:127-129` and `PostgreSQLAdapter.swift:108-110`. Three instances, all worth converting to explicit async shutdown.
- **Resource scaling:** a fresh `MySQLEngine` or `PostgreSQLEngine` is created per connection at `glassdb/DatabaseSessionManager.swift:201-207`, each allocating two event-loop threads, and each `SSHTunnelManager` adds one more. Thread count grows linearly with open sessions.
- I found no data race. The `@unchecked` annotations are all backed by a real confinement argument stated in code or comment.

---

## 7. Platform floor

### 7.1 Declared targets

- `glassdb.xcodeproj/project.pbxproj:421`, `:531`, `:558`, `:586` — `MACOSX_DEPLOYMENT_TARGET = 27.0`.
- `glassdb.xcodeproj/project.pbxproj:415`, `:525`, `:556`, `:584` — `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.
- `glassdb.xcodeproj/project.pbxproj:433`, `:543`, `:571`, `:599` — `XROS_DEPLOYMENT_TARGET = 26.0`.
- `glassdb.xcodeproj/project.pbxproj:425` — `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`. No tvOS, no watchOS.
- `Packages/GlassDBKit/Package.swift:8-12` — the kit itself declares visionOS 26, macOS 26, iOS 26. **The kit is already below the app's macOS floor.**
- `../GlassConnectionKit/Package.swift` — iOS 26, macOS 26, visionOS 26.

### 7.2 What actually requires newer than 26.0, measured not guessed

I compiled the macOS target with `MACOSX_DEPLOYMENT_TARGET=26.0` overridden. **Exactly two errors, both the same expression:**

- `glassdb/Constants.swift:663:9` — error: `'visibilityPriority' is only available in macOS 26.1 or newer`.
- `glassdb/Constants.swift:663:29` — error: `'high' is only available in macOS 26.1 or newer`.

**That is the complete list.** Nothing else in the app or the kit requires anything above 26.0.

### 7.3 Consequences

- The blocking API needs **macOS 26.1, not 27.0**. The declared 27.0 floor is roughly a full major version higher than the code requires.
- `glassdb/Constants.swift:659-674` — `ToolbarContent.databaseHighVisibilityPriority()`. The macOS branch at line 663 calls `visibilityPriority(.high)` **unguarded**; the iOS branch at line 665 already guards with `if #available(iOS 27.0, *)`; every other platform returns `self` at line 671.
- Fix is one guard: wrap line 663 in `if #available(macOS 26.1, *)` with an `else { self }`, matching the iOS branch exactly. That puts the app on macOS 26.0.
- Only two call sites are affected: `glassdb/QueryEditorView.swift:559` and `glassdb/TableDetailView.swift:142`. Both are toolbar visibility hints, purely cosmetic, so the fallback loses nothing functional.
- `glassdb/Constants.swift:665` is the **only** `#available` or `@available` construct in the entire codebase. There is no other version-conditional code to audit.

### 7.4 Vendored package floors

- `Packages/Citadel/Package.swift:9-11` — macOS 14, iOS 17, visionOS 1.
- `Packages/swift-nio-ssh/Package.swift:39-43` — macOS 10.15, iOS 13, visionOS 1, watchOS 6, tvOS 13.
- Both are far below the family floor and therefore do not constrain deployment. They do carry stale-fork maintenance cost.

---

## 8. Dependency graph

### 8.1 Vendored, committed in-tree, not submodules

`git submodule status` returns nothing. Both are ordinary tracked files in the glassdb repository.

- `Packages/Citadel` — 90 tracked files, `Packages/Citadel/Package.swift:1` swift-tools-version 5.9.
- `Packages/swift-nio-ssh` — 124 tracked files, `Packages/swift-nio-ssh/Package.swift:1` swift-tools-version 5.10.
- Neither directory has its own git remote; both share the glassdb repository history.
- Because they are path dependencies, **neither appears in any `Package.resolved`.** A reader auditing only the resolved files will miss them entirely.

### 8.2 Declared dependency edges

- `Packages/GlassDBKit/Package.swift:17-20` — mysql-nio, pinned by exact `revision: "69489876bebca3b54c46680e519669789060d0ae"` on the `msitarzewski/mysql-nio` fork.
- `Packages/GlassDBKit/Package.swift:21` — postgres-nio `from: "1.33.0"`.
- `Packages/GlassDBKit/Package.swift:22` — swift-nio-ssl `from: "2.14.0"`.
- `Packages/GlassDBKit/Package.swift:23` — `.package(path: "../Citadel")`.
- `Packages/Citadel/Package.swift:20` — `.package(path: "../swift-nio-ssh")`.
- `Packages/Citadel/Package.swift:21` — swift-nio `from: "2.81.0"`.
- `Packages/Citadel/Package.swift:22` — swift-log `from: "1.0.0"`.
- `Packages/Citadel/Package.swift:23` — BigInt `from: "5.2.0"`.
- `Packages/Citadel/Package.swift:24` — **swift-crypto `from: "3.12.3"`**.
- `Packages/swift-nio-ssh/Package.swift:49` — swift-nio `from: "2.81.0"`.
- `Packages/swift-nio-ssh/Package.swift:50` — **swift-crypto `"1.0.0"..<"4.0.0"`**.
- `Packages/swift-nio-ssh/Package.swift:51` — swift-atomics `from: "1.0.2"`.
- `glassdb.xcodeproj/project.pbxproj:636-638` — local package reference to `Packages/GlassDBKit`.
- `glassdb.xcodeproj/project.pbxproj:643-645` — remote `GlassEditorKit`.
- `glassdb.xcodeproj/project.pbxproj:651` — local path reference to `../GlassConnectionKit`.
- `glassdb.xcodeproj/project.pbxproj:652-654` — remote `GlasSecretStore`.

### 8.3 Resolved pins, app workspace

From `glassdb.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Package | Pin | Fetched or vendored |
|---|---|---|
| Citadel | in-tree, 90 files | vendored |
| swift-nio-ssh | in-tree, 124 files | vendored |
| mysql-nio | rev `69489876bebca3b54c46680e519669789060d0ae` | fetched, fork |
| postgres-nio | 1.33.0 | fetched |
| swift-nio-ssl | 2.36.0 | fetched |
| swift-nio | 2.100.0 | fetched |
| swift-crypto | 3.15.1 | fetched |
| swift-asn1 | 1.5.1 | fetched |
| BigInt | 5.7.0 | fetched |
| swift-collections | 1.4.0 | fetched |
| swift-atomics | 1.3.0 | fetched |
| swift-log | 1.10.1 | fetched |
| swift-metrics | 2.11.0 | fetched |
| swift-algorithms | 1.2.1 | fetched |
| swift-async-algorithms | 1.1.3 | fetched |
| swift-numerics | 1.1.1 | fetched |
| swift-nio-transport-services | 1.28.0 | fetched |
| swift-service-lifecycle | 2.11.0 | fetched |
| swift-system | 1.6.4 | fetched |
| GlasSecretStore | rev `9be45c91d145` | fetched |
| GlassEditorKit | rev `ae094a8162a8` | fetched |
| GlassConnectionKit | `../GlassConnectionKit` | local path |
| SwiftTreeSitter | 0.25.0 | fetched, via GlassEditorKit |
| tree-sitter | 0.25.10 | fetched, via GlassEditorKit |

Note two other resolved files exist and disagree slightly, which is normal for nested resolution:
- `Packages/GlassDBKit/Package.resolved` — swift-collections 1.3.0, swift-system 1.6.4, swift-asn1 1.5.1.
- `Packages/swift-nio-ssh/Package.resolved` — swift-nio 2.101.3, swift-crypto 3.15.1, swift-asn1 1.7.1, swift-collections 1.6.0, swift-system 1.7.4.
- The app workspace resolution is the authoritative one.

### 8.4 Conflicts against a graph holding swift-nio 2.102.0, swift-crypto 4.5.2, Citadel, swift-nio-ssh

**One hard conflict. It is currently unsatisfiable.**

- **swift-crypto 4.5.2 is excluded by both vendored packages.** `Packages/swift-nio-ssh/Package.swift:50` declares a hard upper bound `"1.0.0"..<"4.0.0"`, and `Packages/Citadel/Package.swift:24` declares `from: "3.12.3"` which SwiftPM also caps below 4.0. A merged graph requiring swift-crypto 4.5.2 **will fail to resolve** against these copies as written.
  - Mitigation: both are already vendored and locally modified, so widening the ranges is a local edit rather than an upstream negotiation.
  - The actually-exercised swift-crypto surface is small: `SSHTunnelManager.swift:13` imports `Crypto` and uses `P256.Signing.PrivateKey` at line 229, `Curve25519.Signing.PrivateKey` at line 239, `Insecure.RSA.PrivateKey` at line 232, and `SHA256.hash` at line 332. Citadel additionally uses `_CryptoExtras` per `Packages/Citadel/Package.swift:35`.
  - **This must be built and tested against swift-crypto 4.x before anyone calls it resolved.** Do not assume a range widening is sufficient; `Insecure.RSA` in particular is a Citadel-side construct layered on `_CryptoExtras`.

**Everything else resolves cleanly.**

- swift-nio 2.100.0 against 2.102.0: no conflict. Both `Packages/Citadel/Package.swift:21` and `Packages/swift-nio-ssh/Package.swift:49` use `from: "2.81.0"`, an open upper bound.
- Citadel and swift-nio-ssh as packages: no version conflict possible, because both are path dependencies. The merged product must decide whether to keep two vendored forks or adopt upstream releases. Keeping forks means the merged repo inherits 214 vendored files.
- swift-asn1 1.5.1 against 1.7.1: resolves upward automatically.
- swift-collections 1.3.0 against 1.4.0 against 1.6.0: resolves upward automatically.
- postgres-nio 1.33.0 and swift-nio-ssl 2.36.0 are new to a terminal-only graph but conflict with nothing.
- GlasSecretStore and GlassConnectionKit are already shared with the terminal app; version skew between the two apps' pins must be checked separately against glas.sh, which was outside this survey.

### 8.5 The mysql-nio fork is mandatory

- `memory-bank/progress.md:40` — the fork corrects empty-password `caching_sha2_password` handling; upstream pull request 126 was **closed without merge**, so the fork remains required until an equivalent upstream release is validated.
- `memory-bank/activeContext.md:100` — the fix was validated against MySQL 9.7.1 through the gated live regression, and the SHA is pinned in both SwiftPM resolution surfaces.
- The pin is an immutable `revision:`, not a version range, so it is reproducible but will never receive upstream fixes automatically.

---

## Appendix: prioritized risks for the port plan

1. **swift-crypto 4.5.2 is unsatisfiable** against the vendored Citadel and swift-nio-ssh ranges. `Packages/swift-nio-ssh/Package.swift:50`, `Packages/Citadel/Package.swift:24`. Blocks graph resolution; must be resolved first.
2. **`SecureBytes` is downgraded to `String`** for SSH key material. `glassdb/DatabaseSessionManager.swift:131-132`, `:286-287`. The shared SSH engine should take `SecureBytes` and never require this conversion.
3. **macOS floor is one guard away from 26.0.** `glassdb/Constants.swift:663`. Cheap, high-value, and the declared 27.0 target is misleading as it stands.
4. **No tunnel reconnect or health check.** `SSHTunnelManager.swift:143`. The shared engine should own this; the current session-level rebuild is a workaround.
5. **Blocking `syncShutdownGracefully()` in three deinits.** `SSHTunnelManager.swift:258`, `MySQLAdapter.swift:127`, `PostgreSQLAdapter.swift:108`.
6. **Cancellation drops the connection** on both network engines. `MySQLAdapter.swift:366`, `PostgreSQLAdapter.swift:188`. A merged UI should either keep this contract explicitly or add a control connection.
7. **PostgreSQL `databases()` returns schemas.** `PostgreSQLAdapter.swift:211`. Any shared schema browser must model this or it will mislabel the tree.
8. **No streaming anywhere.** Large result sets are fully materialized. Acceptable today because the app bounds rows at `glassdb/DatabaseSessionManager.swift:492`, but the kit offers no path to streaming without an API change.
9. **Connection-list persistence has no version number.** `glassdb/Models.swift:89`. Forward compatibility rests entirely on defaulted decoding, which is fragile across a bundle-identifier migration.
10. **Two stale vendored forks, 214 files.** `Packages/Citadel`, `Packages/swift-nio-ssh`. The merge should decide deliberately whether to carry them forward.
