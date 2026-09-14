import Foundation
import SwiftTreeSitter
import Testing
import TreeSitterSql

/// M0 falsification spike for **D-008**: can the vendored DerekStride
/// tree-sitter SQL grammar reproduce the top-level statement splitting that
/// glassdb's hand-rolled `SQLHighlighter.statements(in:)` (`:327–388`) performs?
///
/// The 20 cases below are the pre-committed spike corpus, with counts derived by
/// hand from that algorithm. **It cannot.** Seven cases split a MySQL compound
/// routine body or a transaction block into the wrong number of top-level nodes,
/// and every compound-routine case in the corpus produces a tree containing
/// `ERROR`. Those cases are kept here, marked `.disabled`, so the file records
/// what the grammar actually does rather than what we hoped it would do.
///
/// Three further cases (9, 11, 17) match the expected count only because the
/// *entire* definition collapsed into a single top-level `ERROR` node; they are
/// segregated into `degenerateErrorMatches` so their green is not mistaken for
/// working support.
@Suite("D-008 spike: tree-sitter SQL statement splitting")
struct SQLStatementSpikeTests {

    // MARK: - Corpus

    struct Case: Sendable {
        let index: Int
        /// Which `statements(in:)` behaviour this case probes.
        let probes: String
        let sql: String
        /// Statement count produced by glassdb's reference algorithm.
        let expected: Int
    }

    /// Plain splitting — no compound state involved.
    static let plainSplitting: [Case] = [
        Case(
            index: 1,
            probes: "baseline: two terminated statements split at both `;`",
            sql: "SELECT 1; SELECT 2;",
            expected: 2
        ),
        Case(
            index: 2,
            probes: "trailing statement without a terminator still counts (`:378`)",
            sql: "SELECT 1; SELECT 2",
            expected: 2
        ),
        Case(
            index: 3,
            probes: "line comments are filtered before analysis (`:328`) so a `;` inside one never splits",
            sql: "SELECT 1 -- comment with ; inside\n; SELECT 2;",
            expected: 2
        ),
        Case(
            index: 4,
            probes: "a `;` inside a string literal is not punctuation, so it never splits",
            sql: "SELECT '/*not a comment*/'; SELECT ';';",
            expected: 2
        ),
        Case(
            index: 5,
            probes: "a leading block comment contributes no statement of its own",
            sql: "/* block ; comment */ SELECT 1;",
            expected: 1
        ),
        Case(
            index: 13,
            probes: "`IF` with no `THEN` before the next `;` opens nothing (`:349–354`)",
            sql: "DROP TABLE IF EXISTS t; SELECT 1;",
            expected: 2
        ),
        Case(
            index: 14,
            probes: "the `IF()` *function* is not a compound opener — no `THEN` token precedes the `;`",
            sql: "SELECT IF(a>1, 'y', 'n') FROM t; SELECT 2;",
            expected: 2
        ),
        Case(
            index: 19,
            probes: "a routine embedded between two plain statements — three tops, body kept whole",
            sql: "SELECT 1; CREATE PROCEDURE p() BEGIN SELECT 2; END; SELECT 3;",
            expected: 3
        ),
    ]

    /// Cases where tree-sitter's count matches only because the whole definition
    /// degenerated into one top-level `ERROR` node. Counted right, parsed wrong.
    static let degenerateErrorMatches: [Case] = [
        Case(
            index: 9,
            probes: "CREATE TRIGGER ... FOR EACH ROW BEGIN ... END is one routine (`:344`)",
            sql: "CREATE TRIGGER trg BEFORE INSERT ON t FOR EACH ROW BEGIN SET NEW.a = 1; END;",
            expected: 1
        ),
        Case(
            index: 11,
            probes: "CREATE EVENT ... DO BEGIN ... END is one routine (`:344`)",
            sql: "CREATE EVENT ev ON SCHEDULE EVERY 1 DAY DO BEGIN CALL p(); END;",
            expected: 1
        ),
        Case(
            index: 17,
            probes: "a labelled `lbl: LOOP ... END LOOP` body is one routine (`:356`)",
            sql: "CREATE PROCEDURE p() lbl: LOOP SET i=i+1; LEAVE lbl; END LOOP;",
            expected: 1
        ),
    ]

    /// Cases tree-sitter genuinely reproduces: the routine is one top-level node
    /// with real structure (a `create_procedure` / `create_function`), even though
    /// the subtree still contains internal `ERROR`s.
    static let compoundMatches: [Case] = [
        Case(
            index: 8,
            probes: "`DEFINER=` is a significant plain word; CREATE..PROCEDURE still inside the first four (`:342–345`)",
            sql: "CREATE DEFINER=`admin`@`localhost` PROCEDURE p() BEGIN SELECT 1; END;",
            expected: 1
        ),
        Case(
            index: 10,
            probes: "CREATE FUNCTION ... RETURNS ... BEGIN ... END is one routine (`:344`)",
            sql: "CREATE FUNCTION f() RETURNS INT BEGIN RETURN 1; END;",
            expected: 1
        ),
    ]

    /// Cases the grammar gets wrong. Each splits where `statements(in:)` does not.
    static let failures: [Case] = [
        Case(
            index: 6,
            probes: "a top-level `BEGIN` is a transaction start, NOT a compound open — `isRoutineDefinition` stays false (`:347`)",
            sql: "BEGIN; UPDATE t SET a=1; COMMIT;",
            expected: 3
        ),
        Case(
            index: 7,
            probes: "`compoundDepth` holds every `;` inside a BEGIN…END routine body (`:356–367`)",
            sql: "CREATE PROCEDURE p() BEGIN SELECT 1; SELECT 2; END;",
            expected: 1
        ),
        Case(
            index: 12,
            probes: "`IF` opens because `THEN` precedes the next `;`; `END IF` closes it (`:349–362`)",
            sql: "CREATE PROCEDURE p() BEGIN IF x > 0 THEN SELECT 1; END IF; SELECT 2; END;",
            expected: 1
        ),
        Case(
            index: 15,
            probes: "`WHILE` opens, `END` decrements, and the `WHILE` after `END` must not reopen (`:358`)",
            sql: "CREATE PROCEDURE p() BEGIN WHILE i < 10 DO SET i = i + 1; END WHILE; END;",
            expected: 1
        ),
        Case(
            index: 16,
            probes: "`REPEAT … UNTIL … END REPEAT` with the same END-suppression guard (`:356–358`)",
            sql: "CREATE PROCEDURE p() BEGIN REPEAT SET i=i+1; UNTIL i>10 END REPEAT; END;",
            expected: 1
        ),
        Case(
            index: 18,
            probes: "`CASE` opens compound and also contains `THEN` — the IF lookahead must not double-count",
            sql: "CREATE PROCEDURE p() BEGIN CASE x WHEN 1 THEN SELECT 1; ELSE SELECT 2; END CASE; END;",
            expected: 1
        ),
        Case(
            index: 20,
            probes: "nested IF/WHILE: depth reaches 3 and unwinds through `END WHILE`, `END IF`, `END`",
            sql: "CREATE PROCEDURE p() BEGIN IF a THEN WHILE b DO SELECT 1; END WHILE; END IF; END;",
            expected: 1
        ),
    ]

    /// Compound-routine cases from the corpus (7–12, 15–20) that the grammar
    /// keeps as a single node spanning the whole definition including `END`.
    static let wholeBodyHeld: [Case] = degenerateErrorMatches + compoundMatches

    /// Compound-routine cases whose top-level node stops short of the final `END`.
    static let wholeBodyBroken: [Case] = failures.filter { $0.index != 6 }

    // MARK: - Grammar helpers

    /// Node types the DerekStride grammar emits for comments at the top level.
    /// `comment` is `--`/`#`; `marginalia` is `/* … */`.
    static let commentNodeTypes: Set<String> = ["comment", "marginalia"]

    private static func parse(_ sql: String) throws -> Node {
        let parser = Parser()
        try parser.setLanguage(Language(tree_sitter_sql()))
        let tree = try #require(parser.parse(sql), "parser returned no tree")
        return try #require(tree.rootNode, "tree had no root node")
    }

    /// The named children of `program` that are not comments — the grammar's
    /// answer to "how many top-level statements is this?".
    ///
    /// `ERROR` nodes are counted. They are spans of text the grammar could not
    /// attribute to any statement, and a caller running "the statement under the
    /// caret" would still have to execute them; silently dropping them would hide
    /// exactly the failure this spike exists to measure. `errorExcludedCount`
    /// records the alternative policy for the report.
    static func topLevelStatements(in sql: String) throws -> [Node] {
        let root = try parse(sql)
        return (0..<root.namedChildCount).compactMap { index in
            guard let child = root.namedChild(at: index) else { return nil }
            guard let type = child.nodeType, !commentNodeTypes.contains(type) else { return nil }
            return child
        }
    }

    static func topLevelStatementCount(in sql: String) throws -> Int {
        try topLevelStatements(in: sql).count
    }

    /// `Node.range` is a byte range presented as an `NSRange`.
    static func text(of node: Node, in sql: String) -> String {
        let bytes = Array(sql.utf8)
        let lower = min(node.range.location, bytes.count)
        let upper = min(node.range.location + node.range.length, bytes.count)
        return String(decoding: bytes[lower..<upper], as: UTF8.self)
    }

    /// Byte offset just past the last `END` keyword in the source.
    static func endOfFinalEND(in sql: String) -> Int? {
        guard let range = sql.range(of: "END", options: .backwards) else { return nil }
        return sql.utf8.distance(from: sql.utf8.startIndex, to: range.upperBound.samePosition(in: sql.utf8)!)
    }

    // MARK: - Count assertions

    /// Cases 1–5, 13, 14, 19 — plain splitting, string/comment masking, and the
    /// `IF`-without-`THEN` discriminations. The grammar reproduces all of these.
    @Test("Plain splitting matches statements(in:)", arguments: plainSplitting)
    func plainCase(_ testCase: Case) throws {
        let count = try Self.topLevelStatementCount(in: testCase.sql)
        #expect(
            count == testCase.expected,
            "case \(testCase.index) [\(testCase.probes)]: expected \(testCase.expected), got \(count)"
        )
    }

    /// Cases 8, 10 — the two compound routines the grammar has real rules for
    /// (`create_procedure`, `create_function` with a single-statement body).
    @Test("Compound routine kept whole", arguments: compoundMatches)
    func compoundMatchCase(_ testCase: Case) throws {
        let count = try Self.topLevelStatementCount(in: testCase.sql)
        #expect(
            count == testCase.expected,
            "case \(testCase.index) [\(testCase.probes)]: expected \(testCase.expected), got \(count)"
        )
    }

    /// Cases 9, 11, 17 — CREATE TRIGGER, CREATE EVENT, and labelled `LOOP` are
    /// not in the grammar at all. The count matches only because the whole
    /// definition became one top-level `ERROR`, so this test asserts the error
    /// as well: if the grammar ever gains real support, this test fails and the
    /// case graduates to `compoundMatches`.
    @Test("Count matches only via a whole-definition ERROR node", arguments: degenerateErrorMatches)
    func degenerateErrorCase(_ testCase: Case) throws {
        let statements = try Self.topLevelStatements(in: testCase.sql)
        #expect(
            statements.count == testCase.expected,
            "case \(testCase.index) [\(testCase.probes)]: expected \(testCase.expected), got \(statements.count)"
        )
        #expect(
            statements.first?.nodeType == "ERROR",
            "case \(testCase.index): expected a degenerate top-level ERROR, got \(statements.first?.nodeType ?? "nil")"
        )
    }

    /// Cases 6, 7, 12, 15, 16, 18, 20 — the grammar produces the wrong top-level
    /// count. See the report in the D-008 resolution for each tree's sexp.
    @Test(
        "Compound and transaction splitting matches statements(in:)",
        .disabled("D-008: tree-sitter-sql cannot reproduce this — see decisions.md"),
        arguments: failures
    )
    func failingCase(_ testCase: Case) throws {
        let statements = try Self.topLevelStatements(in: testCase.sql)
        let rendered = statements.map { "\($0.nodeType ?? "?"):<<\(Self.text(of: $0, in: testCase.sql))>>" }
        #expect(
            statements.count == testCase.expected,
            """
            case \(testCase.index) [\(testCase.probes)]: expected \(testCase.expected), \
            got \(statements.count) — \(rendered.joined(separator: " | "))
            """
        )
    }

    // MARK: - Honesty probe: is the routine body actually held together?

    /// A matching count is not enough: the routine must be ONE top-level node
    /// whose range spans the whole definition through its final `END`. Cases 8,
    /// 9, 10, 11 and 17 satisfy that.
    @Test("Routine body is one node spanning through END", arguments: wholeBodyHeld)
    func routineSpansWholeDefinition(_ testCase: Case) throws {
        let statements = try Self.topLevelStatements(in: testCase.sql)
        try #require(statements.count == 1, "case \(testCase.index): \(statements.count) top-level nodes, expected 1")

        let node = statements[0]
        let endOfEND = try #require(Self.endOfFinalEND(in: testCase.sql))
        #expect(node.range.location == 0, "case \(testCase.index): routine node does not start at offset 0")
        #expect(
            node.range.location + node.range.length >= endOfEND,
            """
            case \(testCase.index): routine node ends at byte \
            \(node.range.location + node.range.length) but the final END closes at \(endOfEND) — \
            body was split: <<\(Self.text(of: node, in: testCase.sql))>>
            """
        )
    }

    /// Cases 7, 12, 15, 16, 18, 20 — the top-level node stops at the *first*
    /// `END` it can reach and the remainder of the body leaks out as sibling
    /// statements and `ERROR`s. This is the finding that resolves D-008.
    @Test(
        "Routine body is one node spanning through END (compound forms)",
        .disabled("D-008: tree-sitter-sql cannot reproduce this — see decisions.md"),
        arguments: wholeBodyBroken
    )
    func routineBodySplit(_ testCase: Case) throws {
        let statements = try Self.topLevelStatements(in: testCase.sql)
        try #require(statements.count == 1, "case \(testCase.index): \(statements.count) top-level nodes, expected 1")

        let node = statements[0]
        let endOfEND = try #require(Self.endOfFinalEND(in: testCase.sql))
        #expect(node.range.location == 0)
        #expect(node.range.location + node.range.length >= endOfEND)
    }

    /// Every compound-routine case in the corpus parses to a tree containing
    /// `ERROR`, including the ones whose counts happen to match. Recorded as a
    /// disabled test so the fact is documented and re-checkable if the grammar
    /// is ever re-vendored from a newer commit.
    @Test(
        "Compound routine syntax parses without ERROR",
        .disabled("D-008: tree-sitter-sql cannot reproduce this — see decisions.md"),
        arguments: wholeBodyHeld + wholeBodyBroken
    )
    func compoundRoutineParsesClean(_ testCase: Case) throws {
        let parser = Parser()
        try parser.setLanguage(Language(tree_sitter_sql()))
        let root = try #require(parser.parse(testCase.sql)?.rootNode)
        #expect(!root.hasError, "case \(testCase.index): \(root.sExpressionString ?? "no sexp")")
    }
}

extension SQLStatementSpikeTests.Case: CustomTestStringConvertible {
    var testDescription: String { "case \(index)" }
}
