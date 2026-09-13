//
//  SQLSafetyClassificationTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `SQLHighlighter.safetyClassification` is the classifier D15's read-only guard delegates to.
//  `ReadOnlyDatabaseConnection.checkReadOnly` (`ReadOnlyDatabaseConnection.swift:52`) is one line:
//  it asks for a classification and refuses anything that is not `.readOnly` or `.sessionControl`.
//
//  Until now the *wrapper* was tested and the *classifier* was not. `ReadOnlyServiceTests` proves
//  the gate refuses seven unambiguous statements (`DELETE FROM members`, `DROP TABLE teams`…) —
//  which is exactly the set that survives any plausible regression. The statements that matter are
//  the ones where a write is spelled so that a naive reading sees a SELECT, and nothing checked
//  those at all. `SQLHighlighter` moved into this product from glassdb essentially verbatim and
//  arrived with no tests; this file is the coverage it never had.
//
//  **The asymmetry is the whole point.** A read wrongly refused is an inconvenience the user sees
//  immediately. A write wrongly permitted is silent, reaches a production server, and is discovered
//  afterwards or never. So `writeNeverClassifiesAsPermitted` asserts the security property directly
//  rather than trusting the case-by-case expectations below to stay exhaustive.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("SQL safety classification")
struct SQLSafetyClassificationTests {
    /// What `ReadOnlyDatabaseConnection.checkReadOnly` does with a classification. Duplicated from
    /// the gate deliberately: if the gate's policy changes, this test should fail and make someone
    /// re-read the security argument rather than silently following it.
    private func isPermittedByReadOnlyGate(_ classification: SQLSafetyClassification) -> Bool {
        switch classification {
        case .readOnly, .sessionControl: true
        case .mutation, .destructive, .unknown: false
        }
    }

    private func classify(_ sql: String) -> SQLSafetyClassification {
        SQLHighlighter.safetyClassification(of: sql)
    }

    // MARK: - A write must never be spelled past the gate

    /// The security property, stated once and independently of the tables below.
    ///
    /// Every statement here mutates or destroys data on a real server. None may classify as
    /// something the read-only gate lets through. This is the test that must not be deleted when
    /// someone "simplifies" the classifier: it does not care *which* non-permitted classification
    /// is returned, only that the statement is stopped.
    @Test("No statement that writes is ever permitted by the read-only gate")
    func writeNeverClassifiesAsPermitted() {
        let writes = [
            // Plain forms.
            "DELETE FROM members",
            "DROP TABLE teams",
            "TRUNCATE TABLE audit",
            "UPDATE accounts SET balance = 0",
            "INSERT INTO accounts (id) VALUES (1)",
            "REPLACE INTO accounts (id) VALUES (1)",
            "ALTER TABLE teams ADD COLUMN x INT",
            "RENAME TABLE a TO b",
            "GRANT ALL ON *.* TO 'x'@'%'",
            "REVOKE ALL ON *.* FROM 'x'@'%'",
            "CREATE TABLE t (id INT)",
            "CALL some_procedure()",
            "MERGE INTO target USING source ON (1=1) WHEN MATCHED THEN UPDATE SET x = 1",
            "LOAD DATA INFILE '/tmp/x' INTO TABLE t",

            // A data-modifying CTE: the statement opens with WITH and reads like a SELECT.
            "WITH removed AS (DELETE FROM sessions RETURNING id) SELECT * FROM removed",
            "WITH moved AS (UPDATE accounts SET x = 1 RETURNING id) SELECT * FROM moved",
            "WITH added AS (INSERT INTO t VALUES (1) RETURNING id) SELECT * FROM added",

            // Writes to the server's filesystem, which open with SELECT.
            "SELECT * FROM audit INTO OUTFILE '/tmp/export'",
            "SELECT * FROM audit INTO DUMPFILE '/tmp/export'",

            // PostgreSQL SELECT INTO creates a table; MySQL SELECT INTO assigns variables.
            "SELECT id INTO new_table FROM accounts",

            // Locking reads take real locks on a live server.
            "SELECT * FROM accounts FOR UPDATE",
            "SELECT * FROM accounts FOR SHARE",

            // Server-wide configuration outlives the session.
            "SET GLOBAL max_connections = 1",
            "SET PERSIST max_connections = 1",
            "SET PERSIST_ONLY max_connections = 1",
        ]

        for sql in writes {
            let classification = classify(sql)
            #expect(!isPermittedByReadOnlyGate(classification),
                    "a read-only service would have sent this to the server: \(sql) → \(classification)")
        }
    }

    // MARK: - Keywords that are not keywords

    /// A keyword inside a string literal is data, not an instruction.
    ///
    /// The mechanism is structural: `tokenize` emits `.string` and `.comment` kinds and
    /// `safetyClassification` keeps only `.keyword` and `.plain`. That is why these pass, and it is
    /// what these tests pin — a tokenizer change that stops recognising a literal would reclassify
    /// every one of them without any line of `safetyClassification` being touched.
    @Test("A keyword inside a string literal does not classify the statement")
    func keywordsInsideStringLiteralsAreData() {
        #expect(classify("WITH visible AS (SELECT 'UPDATE accounts') SELECT * FROM visible") == .readOnly)
        #expect(classify("SELECT 'DELETE FROM accounts' AS note") == .readOnly)
        #expect(classify("SELECT * FROM logs WHERE message = 'DROP TABLE teams'") == .readOnly)
    }

    /// Likewise a keyword inside a comment, in all three comment syntaxes the tokenizer knows.
    @Test("A keyword inside a comment does not classify the statement")
    func keywordsInsideCommentsAreIgnored() {
        #expect(classify("/* DELETE FROM accounts */ SELECT 1") == .readOnly)
        #expect(classify("-- DROP TABLE teams\nSELECT 1") == .readOnly)
        #expect(classify("# TRUNCATE TABLE audit\nSELECT 1") == .readOnly)
        #expect(classify("SELECT 1 /* UPDATE accounts SET x = 1 */") == .readOnly)
    }

    /// The inverse, and the more important direction: a comment must not *hide* a real write.
    @Test("A comment before a write does not disguise the write")
    func commentsDoNotHideARealWrite() {
        #expect(classify("/* harmless */ DELETE FROM members") == .destructive)
        #expect(classify("-- just a note\nUPDATE accounts SET balance = 0") == .mutation)
    }

    // MARK: - Reads

    @Test("Ordinary reads are read-only")
    func readsAreReadOnly() {
        #expect(classify("SELECT * FROM accounts") == .readOnly)
        #expect(classify("select id from accounts") == .readOnly, "classification is case-insensitive")
        #expect(classify("SHOW TABLES") == .readOnly)
        #expect(classify("DESCRIBE accounts") == .readOnly)
        #expect(classify("DESC accounts") == .readOnly)
        #expect(classify("EXPLAIN SELECT * FROM accounts") == .readOnly)
        #expect(classify("VALUES (1), (2)") == .readOnly)
    }

    /// A read-only CTE stays read-only: `WITH` alone is not suspicious.
    @Test("A CTE that only reads is read-only")
    func readOnlyCTE() {
        #expect(classify("WITH recent AS (SELECT * FROM logs) SELECT * FROM recent") == .readOnly)
    }

    // MARK: - Session control

    /// Permitted by the gate, and deliberately so: these affect the connection, not the data.
    @Test("Session-scoped statements are session control, not mutations")
    func sessionControl() {
        #expect(classify("SET autocommit = 1") == .sessionControl)
        #expect(classify("USE gpt_test") == .sessionControl)
        #expect(classify("BEGIN") == .sessionControl)
        #expect(classify("START TRANSACTION") == .sessionControl)
        #expect(classify("COMMIT") == .sessionControl)
        #expect(classify("ROLLBACK") == .sessionControl)
        #expect(classify("SAVEPOINT s1") == .sessionControl)
        #expect(classify("LOCK TABLES t READ") == .sessionControl)
        #expect(classify("UNLOCK TABLES") == .sessionControl)
    }

    /// `SET` is the one keyword that straddles the boundary, so it gets its own check.
    @Test("SET is session control only while it stays in the session")
    func setScopeDecidesTheClassification() {
        #expect(classify("SET autocommit = 1") == .sessionControl)
        #expect(classify("SET SESSION sql_mode = ''") == .sessionControl)
        #expect(classify("SET GLOBAL max_connections = 1") == .mutation)
        #expect(classify("SET PERSIST max_connections = 1") == .mutation)
        #expect(classify("SET PERSIST_ONLY max_connections = 1") == .mutation)
    }

    // MARK: - Nothing to classify

    /// Unknown is refused by the gate, which is the safe direction: an empty or unparseable
    /// statement is not evidence that it is a read.
    @Test("Empty and unrecognised input is unknown, and unknown is refused")
    func unknownIsRefused() {
        #expect(classify("") == .unknown)
        #expect(classify("   \n\t  ") == .unknown)
        #expect(classify("/* only a comment */") == .unknown)
        #expect(classify("FLIBBERTIGIBBET accounts") == .unknown)
        #expect(!isPermittedByReadOnlyGate(.unknown))
    }

    // MARK: - The gate's own policy

    /// Documents which classifications the read-only service lets through, so the security
    /// argument is written down somewhere a reader will find it.
    @Test("The read-only gate permits exactly reads and session control")
    func gatePolicy() {
        #expect(isPermittedByReadOnlyGate(.readOnly))
        #expect(isPermittedByReadOnlyGate(.sessionControl))
        #expect(!isPermittedByReadOnlyGate(.mutation))
        #expect(!isPermittedByReadOnlyGate(.destructive))
        #expect(!isPermittedByReadOnlyGate(.unknown))
        #expect(SQLSafetyClassification.allCases.count == 5,
                "a new classification must be given an explicit policy above, not a default")
    }

    // MARK: - The gate splits scripts; the classifier does not

    /// `safetyClassification` classifies ONE statement, from its leading keyword. Given a script it
    /// answers for the first statement only, and this pins that so nobody mistakes it for a
    /// whole-script verdict — including whoever next reads `ReadOnlyDatabaseConnection`.
    @Test("The classifier answers for the first statement of a script, not the whole script")
    func classifierIsSingleStatement() {
        #expect(classify("SELECT 1; DELETE FROM members") == .readOnly)
        #expect(classify("SHOW TABLES; UPDATE accounts SET x = 1") == .readOnly)
        #expect(classify("DELETE FROM members; SELECT 1") == .destructive,
                "order matters, which is the point")
    }

    /// So the gate splits first. This is the test that would have caught a "run script" command
    /// added later without one.
    ///
    /// No caller sends a multi-statement string today — both execution paths split with
    /// `statementsToExecute` and run one statement at a time — so this is defence in depth rather
    /// than a fix for a reachable hole. It is here because the guarantee should not depend on
    /// every future caller remembering to split.
    @Test("A script hiding a write in any position is refused by the gate")
    func gateRefusesWritesAnywhereInAScript() {
        let scripts = [
            "SELECT 1; DELETE FROM members",
            "SHOW TABLES; UPDATE accounts SET x = 1",
            "SELECT 1; SELECT 2; DROP TABLE teams",
            "SELECT 1;\nTRUNCATE TABLE audit;\nSELECT 2",
            "USE gpt_test; INSERT INTO t VALUES (1)",
        ]
        for script in scripts {
            let verdict = SQLHighlighter.statements(in: script).map(\.safety)
            #expect(verdict.contains { !isPermittedByReadOnlyGate($0) },
                    "the gate must find the write in: \(script)")
        }
    }

    /// The inverse: an all-reads script must still be allowed, or the hardening has broken
    /// ordinary use.
    @Test("A script of reads stays permitted")
    func allReadScriptIsPermitted() {
        let statements = SQLHighlighter.statements(in: "SELECT 1; SHOW TABLES; SELECT 2")
        #expect(statements.count == 3)
        #expect(statements.allSatisfy { isPermittedByReadOnlyGate($0.safety) })
    }

    /// A write hidden behind a semicolon inside a string literal is not a second statement, and
    /// must not be split into one — otherwise the hardening above becomes a way to refuse
    /// perfectly good reads.
    @Test("A semicolon inside a literal does not split a statement")
    func semicolonInsideALiteralDoesNotSplit() {
        let statements = SQLHighlighter.statements(in: "SELECT 'one;two' AS note")
        #expect(statements.count == 1)
        #expect(statements.allSatisfy { isPermittedByReadOnlyGate($0.safety) })
    }
}
