//
//  MutationAuditTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The mutation audit: what it keeps, what order it hands it back, and — the assertion that
//  matters — that no row value can reach it.
//
//  Every test uses its own `UserDefaults` suite. Writing to `.standard` from a test would edit
//  the developer's real audit log.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@MainActor
private func scratchDefaults(_ function: String = #function) -> UserDefaults {
    let suite = "com.glasspowertools.tests.audit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func record(_ operation: String, table: String = "members",
                    connection: UUID, at timestamp: Date,
                    outcome: MutationOutcome = .committed,
                    affected: UInt64? = 1,
                    predicate: String? = nil) -> MutationAuditRecord {
    MutationAuditRecord(connectionID: connection, database: "gpt_test", object: table,
                        normalizedOperation: operation, source: "grid-delete",
                        timestamp: timestamp, outcome: outcome, affectedRows: affected,
                        predicate: predicate)
}

@MainActor
@Suite("Mutation audit")
struct MutationAuditTests {

    @Test("Records come back newest first, whatever order they were appended in")
    func newestFirst() {
        let defaults = scratchDefaults()
        let connection = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        MutationAuditStore.append(record("update", connection: connection, at: now), defaults: defaults)
        MutationAuditStore.append(record("delete", connection: connection, at: now + 60), defaults: defaults)
        MutationAuditStore.append(record("insert", connection: connection, at: now - 60), defaults: defaults)

        #expect(MutationAuditStore.records(defaults: defaults).map(\.normalizedOperation)
                == ["delete", "update", "insert"])
    }

    @Test("A connection sees its own mutations and not another's")
    func filteredByConnection() {
        let defaults = scratchDefaults()
        let mine = UUID()
        let theirs = UUID()
        let now = Date()
        MutationAuditStore.append(record("delete", connection: mine, at: now), defaults: defaults)
        MutationAuditStore.append(record("delete", connection: theirs, at: now), defaults: defaults)

        #expect(MutationAuditStore.records(forConnection: mine, defaults: defaults).count == 1)
        #expect(MutationAuditStore.records(forConnection: theirs, defaults: defaults).count == 1)
        #expect(MutationAuditStore.records(defaults: defaults).count == 2)
    }

    @Test("Clearing removes every connection's records, not only the visible ones")
    func clearIsTotal() {
        let defaults = scratchDefaults()
        MutationAuditStore.append(record("delete", connection: UUID(), at: Date()), defaults: defaults)
        MutationAuditStore.append(record("update", connection: UUID(), at: Date()), defaults: defaults)
        MutationAuditStore.clear(defaults: defaults)
        #expect(MutationAuditStore.records(defaults: defaults).isEmpty)
    }

    @Test("An unreadable store reads as empty rather than throwing away the surface")
    func corruptStoreReadsEmpty() {
        let defaults = scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsKeys.mutationAudit)
        #expect(MutationAuditStore.records(defaults: defaults).isEmpty)
    }

    @Test("A deletion's record carries its outcome and its affected-row count")
    func deletionRecordShape() {
        let defaults = scratchDefaults()
        let connection = UUID()
        MutationAuditStore.append(
            record("delete", connection: connection, at: Date(),
                   outcome: .rolledBack, affected: 0),
            defaults: defaults)
        let stored = try! #require(MutationAuditStore.records(defaults: defaults).first)
        #expect(stored.normalizedOperation == "delete")
        #expect(stored.source == "grid-delete")
        #expect(stored.outcome == .rolledBack)
        #expect(stored.affectedRows == 0)
        #expect(stored.database == "gpt_test")
        #expect(stored.object == "members")
    }

    @Test("Every outcome explains itself, and only the unknown one warns")
    func outcomesAreExplained() {
        // `serverStateUnknown` is the one a user must act on: the commit went out and no answer
        // came back, so the app genuinely does not know what the table holds.
        #expect(MutationOutcome.serverStateUnknown.explanation.contains("may or may not"))
        for outcome in [MutationOutcome.committed, .rolledBack, .notStarted] {
            #expect(!outcome.explanation.isEmpty)
            #expect(!outcome.explanation.contains("may or may not"))
        }
    }

    @Test("A record written before the predicate field existed still decodes")
    func olderRecordsStillDecode() throws {
        // `predicate` was added to `MutationAuditRecord` after the store had been shipping. Records
        // already in `glassdb.mutationAudit.v1` have no such key, and the store was deliberately
        // not versioned past v1 on the strength of this: `JSONDecoder` tolerates a missing key for
        // an `Optional`. Asserted rather than assumed, because the cost of being wrong is a user's
        // whole audit log silently reading as empty.
        let defaults = scratchDefaults()
        let legacy = """
        [{"id":"\(UUID().uuidString)","connectionID":"\(UUID().uuidString)","database":"gpt_test",        "object":"members","normalizedOperation":"update","source":"record-editor",        "timestamp":0,"outcome":"committed","affectedRows":1}]
        """
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsKeys.mutationAudit)

        let records = MutationAuditStore.records(defaults: defaults)
        #expect(records.count == 1, "a record without the key must not be dropped")
        #expect(records.first?.predicate == nil)
        #expect(records.first?.normalizedOperation == "update")
    }

    // MARK: The privacy assertion

    @Test("The predicate is stored as a shape, and no row value can reach the store")
    func onlyThePredicateShapeIsStored() {
        // The optimistic predicate binds a verbatim copy of the whole row. What is recorded is the
        // predicate's *shape*; the parameters are simply never written. This asserts it at the
        // boundary — the bytes that land in `UserDefaults` — rather than trusting the call sites,
        // because a future call site passing a fully formatted statement would look perfectly
        // reasonable and would be caught only here.
        let defaults = scratchDefaults()
        let connection = UUID()
        let secret = "ada@example.test"
        let predicate = try! RowMutationSQL.identityPredicate(
            columns: [ColumnInfo(name: "id", type: "int", isPrimaryKey: true),
                      ColumnInfo(name: "email", type: "varchar(80)")],
            row: [.int(7), .string(secret)],
            identifierQuote: "`",
            dialect: .mysql)
        #expect(predicate.parameters.contains(.string(secret)), "the value is bound, as it must be")

        // Recorded exactly the way the three write paths record it.
        MutationAuditStore.append(
            record("delete", connection: connection, at: Date(), predicate: predicate.auditShape),
            defaults: defaults)

        let text = String(decoding: defaults.data(forKey: UserDefaultsKeys.mutationAudit)!,
                          as: UTF8.self)
        #expect(!text.contains(secret), "nothing the audit persists carries a row value")
        #expect(text.contains("email"), "the column name is recorded, so the shape is useful")
        #expect(MutationAuditStore.records(defaults: defaults).first?.predicate
                == "`id` = ? AND `email` = ?")
    }
}
