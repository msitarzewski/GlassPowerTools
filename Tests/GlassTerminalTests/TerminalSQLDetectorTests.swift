import Foundation
import SwiftTerm
import Testing
@testable import GlassTerminalEmulator

/// SQL in a terminal (2026-10-20, the owner: "a data detector for SQL … right-click only"): what
/// is taken for SQL, and how much of what a terminal shows is taken as one statement.
@MainActor
@Suite("SQL in a terminal")
struct TerminalSQLDetectorTests {
    private final class Delegate: TerminalDelegate { func send(source: Terminal, data: ArraySlice<UInt8>) {} }
    private let delegate = Delegate()

    private func terminal(_ lines: [String], columns: Int = 80) -> Terminal {
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: columns, rows: 30, scrollback: 100))
        terminal.feed(byteArray: Array(lines.joined(separator: "\r\n").utf8))
        return terminal
    }

    @Test("statements in capitals, and lower case where English couldn't read the same")
    func recognises() {
        for sql in ["SELECT * FROM customers", "select id, email from customers where id = 4",
                    "UPDATE orders SET status = 'shipped' WHERE id = 7", "INSERT INTO audit (at) VALUES (now())",
                    "DELETE FROM sessions WHERE expires_at < now();", "WITH recent AS (SELECT 1) SELECT * FROM recent",
                    "CREATE TABLE IF NOT EXISTS notes (id integer)", "ALTER TABLE orders ADD COLUMN note text",
                    "EXPLAIN SELECT * FROM orders", "SHOW TABLES", "select 1;",
                    "select name from users order by name"] {
            #expect(TerminalSQLDetector.looksLikeSQL(sql), "\(sql)")
        }
    }

    @Test("English that starts like SQL isn't taken for it")
    func refusesEnglish() {
        for text in ["Select a file from the list", "Update the README, then set up CI", "Delete from the menu bar",
                     "Show me what changed", "Create a new branch", "With that done, select the next one",
                     "SELECT", "Drop it", "describe the problem"] {
            #expect(!TerminalSQLDetector.looksLikeSQL(text), "\(text)")
        }
    }

    @Test("a frame is taken off each line: indentation, a quote's bar, an agent's marker")
    func cleaning() {
        #expect(TerminalSQLDetector.cleaned("    SELECT * FROM orders") == "SELECT * FROM orders")
        #expect(TerminalSQLDetector.cleaned("│ SELECT * FROM orders  │") == "SELECT * FROM orders")
        #expect(TerminalSQLDetector.cleaned("⏺ UPDATE orders SET a = 1;") == "UPDATE orders SET a = 1;")
        #expect(TerminalSQLDetector.cleaned("  ⎿  WHERE id = 3") == "WHERE id = 3")
        #expect(TerminalSQLDetector.selection("  SELECT *\n    FROM orders\n    WHERE id = 1;")
                == "SELECT *\nFROM orders\nWHERE id = 1;")
        #expect(TerminalSQLDetector.selection("hello world") == nil)
    }

    @Test("a right-clicked row takes the whole statement: up to its start, down to its semicolon")
    func statementAround() throws {
        let terminal = terminal([
            "Here is the query I ran:",
            "",
            "  SELECT o.id, c.email",
            "  FROM orders o",
            "  JOIN customers c ON c.id = o.customer_id",
            "  WHERE o.status = 'open';",
            "That returned 12 rows.",
        ])
        for row in 2...5 {
            let statement = try #require(TerminalSQLDetector.statement(around: row, in: terminal), "row \(row)")
            #expect(statement.firstRow == 2 && statement.lastRow == 5)
            #expect(statement.text == "SELECT o.id, c.email\nFROM orders o\nJOIN customers c ON c.id = o.customer_id\nWHERE o.status = 'open';")
        }
        #expect(TerminalSQLDetector.statement(around: 0, in: terminal) == nil, "the prose above")
        #expect(TerminalSQLDetector.statement(around: 1, in: terminal) == nil, "a blank row")
        #expect(TerminalSQLDetector.statement(around: 6, in: terminal) == nil, "the prose after the semicolon")
    }

    @Test("without a semicolon a statement ends at a blank line or the next statement")
    func statementEnds() throws {
        let terminal = terminal([
            "SELECT * FROM a",
            "WHERE x = 1",
            "UPDATE b SET y = 2",
            "",
            "done",
        ])
        let first = try #require(TerminalSQLDetector.statement(around: 1, in: terminal))
        #expect(first.firstRow == 0 && first.lastRow == 1)
        let second = try #require(TerminalSQLDetector.statement(around: 2, in: terminal))
        #expect(second.text == "UPDATE b SET y = 2")
    }

    @Test("a statement wider than the terminal is one line again")
    func softWrapped() throws {
        let terminal = terminal(["SELECT id, email, created_at FROM customers WHERE email LIKE '%@example.com';"], columns: 30)
        // Wrapped onto three rows; a right-click on the last of them.
        let statement = try #require(TerminalSQLDetector.statement(around: 2, in: terminal))
        #expect(statement.firstRow == 0 && statement.lastRow == 2)
        #expect(statement.text == "SELECT id, email, created_at FROM customers WHERE email LIKE '%@example.com';")
    }
}
