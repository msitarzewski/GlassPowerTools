//
//  ReadOnlyDatabaseConnection.swift
//  Glass Power Tools — GlassDatabase
//
//  A service marked read-only refuses to write, and refuses it at the connection rather than in
//  the UI. Five of the app's write paths call the driver directly instead of going through
//  `DatabaseSessionManager.executeQuery` — `SchemaBrowserView.swift:518` (truncate and drop),
//  `TableDetailView.swift:3966` (row update), `:4060` (pasted range), `:4146` (insert) and
//  `:4756` (schema change) — so a guard at the session manager would leave every one of them
//  open. Wrapping the connection is the only placement where "read-only" is a property of the
//  session and not a property of how carefully the next surface was written.
//

import Foundation
import GlassDBKit

/// Refused because the service is read-only. Carries the classification so the message can say
/// what was refused rather than only that something was.
struct ReadOnlyServiceError: LocalizedError {
    let classification: SQLSafetyClassification
    let connectionName: String

    var errorDescription: String? {
        let what = switch classification {
        case .destructive: "a destructive statement"
        case .mutation: "a statement that changes data"
        case .unknown: "a statement that could not be classified as a read"
        case .readOnly, .sessionControl: "this statement"
        }
        return "\(connectionName) is set to read-only, so \(what) was not sent. Turn read-only off in the service's settings to allow writes."
    }
}

/// Delegates every read to the real connection and refuses everything else. A decorator rather
/// than a subclass because `DatabaseConnection` is a protocol with several engine
/// implementations; one wrapper covers all three.
///
/// `sessionControl` is allowed through (`USE`, `SET`): it selects what you are reading, and the
/// workspace's current-database indicator depends on it. `unknown` is refused — a statement the
/// classifier cannot read is not evidence that it is safe.
final class ReadOnlyDatabaseConnection: DatabaseConnection {
    private let wrapped: any DatabaseConnection
    private let connectionName: String

    init(wrapping connection: any DatabaseConnection, connectionName: String) {
        self.wrapped = connection
        self.connectionName = connectionName
    }

    /// The one gate. Everything that reaches the server passes through it.
    ///
    /// **Every statement in the string is classified, not the string.**
    /// `safetyClassification` reads a single statement: it classifies from the leading keyword, so
    /// `SELECT 1; DELETE FROM members` comes back `.readOnly` — the `DELETE` is past the point it
    /// looks at. That is not a bug in the classifier, which is documented to classify one
    /// statement, but it would be a hole here if this gate trusted it with a script.
    ///
    /// Today no caller sends one: both execution paths (`QueryEditorView.execute` and
    /// `TableDetailView.execute`) split with `statementsToExecute` first and run `statement.text`
    /// one at a time, so the gate has only ever seen single statements. **That is exactly why this
    /// splits too.** This file's whole argument is that read-only should be a property of the
    /// session and not of how carefully the next surface was written; trusting callers to have
    /// split first would put the guarantee straight back into the caller's hands. A future path
    /// that passes editor text through unsplit — the natural way to add a "run script" command —
    /// would otherwise open every write in the script at once, silently and with nothing failing.
    ///
    /// An empty or unparseable string yields no statements, so the whole string is classified
    /// instead: that path returns `.unknown`, which is refused. Never permit by default here.
    private func checkReadOnly(_ query: String) throws {
        let statements = SQLHighlighter.statements(in: query)
        let classifications = statements.isEmpty
            ? [SQLHighlighter.safetyClassification(of: query)]
            : statements.map(\.safety)

        for classification in classifications {
            switch classification {
            case .readOnly, .sessionControl:
                continue
            case .mutation, .destructive, .unknown:
                throw ReadOnlyServiceError(classification: classification, connectionName: connectionName)
            }
        }
    }

    // MARK: Gated

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        try checkReadOnly(query)
        return try await wrapped.execute(query, parameters: parameters)
    }

    func execute(_ query: String, parameters: [DatabaseValue], timeout: Duration?) async throws -> QueryResult {
        try checkReadOnly(query)
        return try await wrapped.execute(query, parameters: parameters, timeout: timeout)
    }

    // MARK: Passed through

    var isConnected: Bool { get async { await wrapped.isConnected } }
    var engineName: String { wrapped.engineName }
    var capabilities: Set<DatabaseCapability> { wrapped.capabilities }
    var identifierQuoteCharacter: Character { wrapped.identifierQuoteCharacter }
    var dialect: DatabaseDialect { wrapped.dialect }

    func cancelCurrentQuery() async throws { try await wrapped.cancelCurrentQuery() }
    // Transactions are not writes: a refused statement inside one leaves nothing to commit, and
    // a read transaction is a legitimate way to get a consistent view.
    func beginTransaction() async throws { try await wrapped.beginTransaction() }
    func commitTransaction() async throws { try await wrapped.commitTransaction() }
    func rollbackTransaction() async throws { try await wrapped.rollbackTransaction() }
    func close() async throws { try await wrapped.close() }

    func databases() async throws -> [String] { try await wrapped.databases() }
    func tables(in database: String) async throws -> [String] { try await wrapped.tables(in: database) }
    func columns(in table: String, database: String) async throws -> [ColumnInfo] {
        try await wrapped.columns(in: table, database: database)
    }
    func showCreateTable(_ table: String, database: String) async throws -> String {
        try await wrapped.showCreateTable(table, database: database)
    }
    func indexes(in table: String, database: String) async throws -> [IndexInfo] {
        try await wrapped.indexes(in: table, database: database)
    }
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] {
        try await wrapped.foreignKeys(in: table, database: database)
    }
    func tableStatus(in database: String) async throws -> [TableStatus] {
        try await wrapped.tableStatus(in: database)
    }
    func tableStatusByNamespace() async throws -> [String: [TableStatus]] {
        try await wrapped.tableStatusByNamespace()
    }
    func rowCount(table: String, database: String) async throws -> Int {
        try await wrapped.rowCount(table: table, database: database)
    }
    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int {
        try await wrapped.rowCount(table: table, database: database, timeout: timeout)
    }
    func serverVersion() async throws -> String { try await wrapped.serverVersion() }
    /// `EXPLAIN` plans a statement without running it, so it is a read whatever it plans.
    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        try await wrapped.explain(query, parameters: parameters)
    }
}
