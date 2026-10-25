//
//  ReadOnlyServiceTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  Read-only has to mean read-only. These drive the wrapper the way the app's five direct
//  callers do — straight at `execute`, not through `DatabaseSessionManager.executeQuery` —
//  because that is exactly the bypass the wrapper exists to close.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

/// Records what actually reached the driver. Anything the wrapper refuses must not appear here.
private final class RecordingConnection: DatabaseConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var _executed: [String] = []
    var executed: [String] { lock.withLock { _executed } }

    var isConnected: Bool { get async { true } }
    var engineName: String { "Recorder" }
    var capabilities: Set<DatabaseCapability> { [.transactions, .cancellation] }
    var identifierQuoteCharacter: Character { "\"" }
    var dialect: DatabaseDialect { .postgresql }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        lock.withLock { _executed.append(query) }
        return QueryResult(query: query, columns: [], rows: [], executionTime: 0)
    }
    func cancelCurrentQuery() async throws {}
    func beginTransaction() async throws {}
    func commitTransaction() async throws {}
    func rollbackTransaction() async throws {}
    func close() async throws {}
    func databases() async throws -> [String] { ["gpt_test"] }
    func tables(in database: String) async throws -> [String] { ["teams"] }
    func columns(in table: String, database: String) async throws -> [ColumnInfo] { [] }
    func showCreateTable(_ table: String, database: String) async throws -> String { "" }
    func indexes(in table: String, database: String) async throws -> [IndexInfo] { [] }
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] { [] }
    func tableStatus(in database: String) async throws -> [TableStatus] { [] }
    func tableStatusByNamespace() async throws -> [String: [TableStatus]] { [:] }
    func rowCount(table: String, database: String) async throws -> Int { 0 }
    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int { 0 }
    func serverVersion() async throws -> String { "0" }
    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        QueryResult(query: query, columns: [], rows: [], executionTime: 0)
    }
}

@Suite("Read-only service")
struct ReadOnlyServiceTests {

    private func guarded() -> (RecordingConnection, ReadOnlyDatabaseConnection) {
        let recorder = RecordingConnection()
        return (recorder, ReadOnlyDatabaseConnection(wrapping: recorder, connectionName: "Production"))
    }

    @Test("Reads pass through")
    func readsPass() async throws {
        let (recorder, connection) = guarded()
        _ = try await connection.execute("SELECT * FROM teams", parameters: [])
        #expect(recorder.executed == ["SELECT * FROM teams"])
    }

    @Test("Writes never reach the driver, whichever kind they are")
    func writesAreRefusedBeforeTheWire() async {
        let statements = [
            "UPDATE members SET name = 'x' WHERE id = 1",
            "INSERT INTO teams (name) VALUES ('x')",
            "DELETE FROM members WHERE id = 1",
            "DROP TABLE teams",
            "TRUNCATE TABLE members",
            "ALTER TABLE teams ADD COLUMN note TEXT",
            "CREATE INDEX idx ON teams (name)",
        ]
        for statement in statements {
            let (recorder, connection) = guarded()
            await #expect(throws: ReadOnlyServiceError.self, "\(statement) should be refused") {
                _ = try await connection.execute(statement, parameters: [])
            }
            #expect(recorder.executed.isEmpty, "\(statement) must not reach the driver")
        }
    }

    /// The gate splits a script itself, rather than trusting its caller to have: a read followed by a
    /// write is refused whole, and the driver sees neither. (SQLSafetyClassificationTests split the
    /// script in the test and checked their own copy of the policy, so this path had no test until
    /// 2026-10-24.)
    @Test("A write after a read in one script is refused, and nothing reaches the driver")
    func aWriteHiddenAfterAReadIsRefused() async {
        let (recorder, connection) = guarded()
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await connection.execute("SELECT 1; DELETE FROM members", parameters: [])
        }
        #expect(recorder.executed.isEmpty, "\(recorder.executed)")
    }

    @Test("A statement the classifier cannot read is refused, not assumed safe")
    func unknownIsRefused() async {
        let (recorder, connection) = guarded()
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await connection.execute("WITH x AS (…) CALL do_something()", parameters: [])
        }
        #expect(recorder.executed.isEmpty)
    }

    @Test("Session control passes: it selects what you are reading")
    func sessionControlPasses() async throws {
        let (recorder, connection) = guarded()
        _ = try await connection.execute("USE gpt_test", parameters: [])
        #expect(recorder.executed == ["USE gpt_test"])
    }

    @Test("The timeout overload is gated too — it is the same statement by another door")
    func timeoutOverloadIsGated() async {
        let (recorder, connection) = guarded()
        await #expect(throws: ReadOnlyServiceError.self) {
            _ = try await connection.execute("DELETE FROM members", parameters: [], timeout: .seconds(5))
        }
        #expect(recorder.executed.isEmpty)
    }

    @Test("EXPLAIN and metadata still work: a read-only service is still browsable")
    func metadataStillWorks() async throws {
        let (_, connection) = guarded()
        #expect(try await connection.databases() == ["gpt_test"])
        #expect(try await connection.tables(in: "gpt_test") == ["teams"])
        _ = try await connection.explain("DELETE FROM members", parameters: [])
    }

    @Test("The refusal says which service refused and what it refused")
    func refusalIsActionable() async {
        let (_, connection) = guarded()
        do {
            _ = try await connection.execute("DELETE FROM members", parameters: [])
            Issue.record("expected a refusal")
        } catch let error as ReadOnlyServiceError {
            let message = try? #require(error.errorDescription)
            #expect(message?.contains("Production") == true)
            #expect(error.classification == .destructive || error.classification == .mutation)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("A service that is not read-only is handed the driver unwrapped")
    func onlyWrapsWhenAsked() {
        let recorder = RecordingConnection()
        let plain = DatabaseConnectionConfig(name: "Plain", host: "h", port: 3306, username: "u")
        var readOnly = plain
        readOnly.isReadOnly = true

        #expect(DatabaseSessionManager.applyingReadOnly(recorder, config: plain) is RecordingConnection)
        #expect(DatabaseSessionManager.applyingReadOnly(recorder, config: readOnly) is ReadOnlyDatabaseConnection)
    }
}
