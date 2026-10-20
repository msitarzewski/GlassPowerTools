//
//  TerminalSQLDetector.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  SQL a terminal shows, for Open in SQL Editor (the owner, 2026-10-20: "a data detector for SQL
//  that when engaged checks the server for a defined DB and will take the SQL into a new editor
//  with the proper database and table selected"; then "right-click only").
//
//  A right-click on a line of SQL takes the whole statement it belongs to: up from the line to
//  where the statement starts, down to its `;`, a blank line or the next statement. Agents print
//  SQL indented or framed (a bar down the left of a quote, a bullet before a step), so those
//  are taken off each line first. Whether text is SQL is a guess from its shape, kept narrow:
//  a statement's first keyword with the one that must follow it (UPDATE … SET, INSERT … INTO,
//  DELETE … FROM), and, in lower case, where English reads the same way ("select a file from the
//  list"), a `;` or a clause only SQL has.
//

import Foundation
import SwiftTerm

enum TerminalSQLDetector {
    /// Words a statement can begin with.
    static let starters: Set<String> = [
        "SELECT", "WITH", "INSERT", "REPLACE", "UPDATE", "DELETE", "MERGE", "CREATE", "ALTER", "DROP",
        "TRUNCATE", "EXPLAIN", "SHOW", "DESCRIBE", "DESC", "GRANT", "REVOKE", "CALL", "COPY", "VACUUM",
        "ANALYZE", "PRAGMA",
    ]

    /// What follows CREATE, ALTER or DROP in a statement.
    private static let objects: Set<String> = [
        "TABLE", "VIEW", "INDEX", "UNIQUE", "DATABASE", "SCHEMA", "FUNCTION", "PROCEDURE", "TRIGGER", "SEQUENCE",
        "TYPE", "EXTENSION", "OR", "TEMPORARY", "TEMP", "MATERIALIZED", "USER", "ROLE", "EVENT", "POLICY",
    ]

    /// Clauses English doesn't have, which make lower-case text SQL.
    private static let clauses: Set<String> = ["WHERE", "JOIN", "LIMIT", "VALUES", "HAVING", "RETURNING", "OFFSET"]

    /// Statements longer than this are not taken from a terminal: it is a script, and the scan
    /// stays cheap.
    static let maximumRows = 80

    // MARK: Whether text is SQL

    /// Whether `text` reads as one SQL statement (or several), by its first keyword and what that
    /// keyword needs after it.
    static func looksLikeSQL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 64_000 else { return false }
        let words = Self.words(trimmed)
        guard let first = words.first else { return false }
        let starter = first.uppercased()
        guard starters.contains(starter) else { return false }
        let upper = Set(words.dropFirst().map { $0.uppercased() })
        let terminated = trimmed.hasSuffix(";")
        let shaped: Bool
        switch starter {
        case "SELECT": shaped = upper.contains("FROM") || terminated
        case "WITH": shaped = upper.contains("AS") && !upper.isDisjoint(with: ["SELECT", "INSERT", "UPDATE", "DELETE"])
        case "INSERT", "REPLACE": shaped = upper.contains("INTO")
        case "UPDATE": shaped = upper.contains("SET") && trimmed.contains("=")
        case "DELETE": shaped = upper.contains("FROM")
        case "MERGE": shaped = upper.contains("INTO") && upper.contains("USING")
        case "CREATE", "ALTER", "DROP": shaped = words.count > 1 && objects.contains(words[1].uppercased())
        case "TRUNCATE": shaped = words.count > 1
        default: shaped = words.count > 1 && (first == starter || terminated)
        }
        guard shaped else { return false }
        // Written in capitals, as SQL usually is; in lower case only with what English lacks.
        if first == starter { return true }
        return terminated || !upper.isDisjoint(with: clauses)
            || (starter == "UPDATE" && trimmed.contains("="))
            || (starter == "INSERT" && upper.contains("VALUES"))
            || upper.contains("BY") && (upper.contains("ORDER") || upper.contains("GROUP"))
    }

    private static func words(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
    }

    // MARK: A line as SQL

    /// Characters an agent or a quote puts before a line of its output: indentation, a bar down
    /// a quote or code block, a bullet, a reply's marker.
    private static let leaders = CharacterSet(charactersIn: " \t│┃▏▎▍▌▐║⎿⏺•●◦▸▹>").union(.whitespaces)

    /// `line` without what frames it: its leaders, a bar at its end, trailing spaces.
    static func cleaned(_ line: String) -> String {
        var text = Substring(line)
        while let first = text.unicodeScalars.first, leaders.contains(first) { text = text.dropFirst() }
        var result = String(text)
        while let last = result.unicodeScalars.last, CharacterSet(charactersIn: " \t│┃║").contains(last) {
            result.removeLast()
        }
        return result
    }

    /// Whether a cleaned line begins a statement.
    static func startsStatement(_ cleanedLine: String) -> Bool {
        guard let first = words(cleanedLine).first else { return false }
        return starters.contains(first.uppercased())
    }

    // MARK: The statement around a row

    struct Statement: Equatable {
        /// The statement as SQL: each line without its frame, soft-wrapped rows joined.
        let text: String
        /// Its first and last rows, as buffer rows (`Position.row`: scrollback included).
        let firstRow: Int
        let lastRow: Int
    }

    /// The statement the buffer row `row` is part of, or nil when that row isn't SQL.
    static func statement(around row: Int, in terminal: Terminal) -> Statement? {
        let top = terminal.buffer.totalLinesTrimmed
        // The rows as lines: a soft-wrapped row belongs to the line before it.
        func rowText(_ row: Int) -> (text: String, wrapped: Bool)? {
            guard row >= 0, let line = terminal.getScrollInvariantLine(row: top + row) else { return nil }
            return (line.translateToString(trimRight: true), line.isWrapped)
        }
        guard let clicked = rowText(row), !cleaned(clicked.text).isEmpty else { return nil }

        // Up to where the statement starts; a blank line or a statement's end above stops it.
        var first = row
        while true {
            // A wrapped row continues the one above it: never a start.
            if let current = rowText(first), !current.wrapped, startsStatement(cleaned(current.text)) { break }
            guard row - first < maximumRows, let above = rowText(first - 1) else { return nil }
            let text = cleaned(above.text)
            if text.isEmpty || (text.hasSuffix(";") && rowText(first)?.wrapped != true) { return nil }
            first -= 1
        }
        // Down to its end: a `;`, a blank line, or the next statement.
        var last = first
        while last - first < maximumRows {
            let text = cleaned(rowText(last)?.text ?? "")
            if text.hasSuffix(";") { break }
            guard let below = rowText(last + 1) else { break }
            let next = cleaned(below.text)
            if next.isEmpty || (!below.wrapped && startsStatement(next)) { break }
            last += 1
        }
        guard (first...last).contains(row) else { return nil }

        var text = ""
        for index in first...last {
            guard let line = rowText(index) else { continue }
            if index > first, !line.wrapped { text += "\n" }
            text += line.wrapped ? line.text : cleaned(line.text)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeSQL(text) else { return nil }
        return Statement(text: text, firstRow: first, lastRow: last)
    }

    /// Selected text as SQL: each line without its frame, or nil when it isn't SQL.
    static func selection(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map(cleaned)
        let sql = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return looksLikeSQL(sql) ? sql : nil
    }
}
