//
//  SQLHighlighter.swift
//  glassdb
//
//  SQL syntax highlighting + basic linting for the query editor.
//  Produces NSAttributedString for use with UITextView on visionOS.
//

import Foundation
import GlassDBKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Token Types

enum SQLExecutionMode: String, Sendable {
    case automatic, statement, selection, all
}

enum SQLTokenKind: Equatable {
    case keyword
    case function
    case string
    case number
    case comment
    case identifier
    case operator_
    case punctuation
    case plain
    case error
}

// MARK: - Statement Parsing and Safety

enum SQLSafetyClassification: String, Codable, CaseIterable, Hashable, Sendable {
    case readOnly
    case mutation
    case destructive
    case sessionControl
    case unknown

    var requiresConfirmation: Bool {
        switch self {
        case .readOnly, .sessionControl:
            return false
        case .mutation, .destructive, .unknown:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .readOnly: return "Read only"
        case .mutation: return "Changes data"
        case .destructive: return "Destructive"
        case .sessionControl: return "Session control"
        case .unknown: return "Review required"
        }
    }
}

struct SQLStatement: Identifiable {
    let id: Int
    let text: String
    let range: Range<String.Index>
    let safety: SQLSafetyClassification
}

struct SQLBoundedReadPlan: Equatable {
    let originalSQL: String
    let executionSQL: String
    let rowLimit: Int
    let fetchLimit: Int
}

struct SQLToken {
    let kind: SQLTokenKind
    let range: Range<String.Index>
}

// MARK: - Lint Diagnostic

struct SQLDiagnostic: Identifiable {
    let id = UUID()
    let range: Range<String.Index>
    let message: String
}

// MARK: - Highlighter

struct SQLHighlighter {

    static let validEditorResultRowLimits = 1...100_000

    // MARK: Keywords

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL",
        "AS", "ON", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS",
        "FULL", "NATURAL", "USING", "ORDER", "BY", "ASC", "DESC",
        "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "ALTER", "DROP", "TABLE", "DATABASE", "INDEX", "VIEW",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT",
        "IF", "EXISTS", "DEFAULT", "AUTO_INCREMENT", "UNIQUE",
        "GRANT", "REVOKE", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "USE",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT",
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "LIKE", "BETWEEN", "ESCAPE", "TRUE", "FALSE",
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "MEDIUMINT",
        "VARCHAR", "CHAR", "TEXT", "BLOB", "DATE", "DATETIME",
        "TIMESTAMP", "FLOAT", "DOUBLE", "DECIMAL", "BOOLEAN", "JSON",
        "NOT", "NULL", "UNSIGNED", "SIGNED",
        "TRUNCATE", "RENAME", "LOCK", "UNLOCK", "FLUSH",
        "WITH", "RECURSIVE", "TEMPORARY", "REPLACE",
    ]

    private static let functions: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX", "NOW", "CURDATE", "CURTIME",
        "CONCAT", "SUBSTRING", "SUBSTR", "LENGTH", "TRIM", "UPPER", "LOWER",
        "COALESCE", "IFNULL", "NULLIF", "CAST", "CONVERT",
        "DATE_FORMAT", "DATE_ADD", "DATE_SUB", "DATEDIFF",
        "ABS", "CEIL", "FLOOR", "ROUND", "MOD", "RAND",
        "GROUP_CONCAT", "JSON_EXTRACT", "JSON_ARRAYAGG",
        "ROW_NUMBER", "RANK", "DENSE_RANK", "LEAD", "LAG",
        "OVER", "PARTITION",
    ]

    // MARK: Tokenizer

    static func tokenize(_ sql: String) -> [SQLToken] {
        var tokens: [SQLToken] = []
        var i = sql.startIndex

        while i < sql.endIndex {
            let c = sql[i]

            // Whitespace — skip
            if c.isWhitespace {
                i = sql.index(after: i)
                continue
            }

            // Single-line comments: -- ... and MySQL # ...
            if c == "-", let next = sql.index(i, offsetBy: 1, limitedBy: sql.endIndex),
               next < sql.endIndex, sql[next] == "-" {
                let start = i
                if let newline = sql[i...].firstIndex(where: { $0 == "\n" }) {
                    i = sql.index(after: newline)
                    tokens.append(SQLToken(kind: .comment, range: start..<i))
                } else {
                    tokens.append(SQLToken(kind: .comment, range: start..<sql.endIndex))
                    i = sql.endIndex
                }
                continue
            }

            if c == "#" {
                let start = i
                if let newline = sql[i...].firstIndex(where: { $0 == "\n" }) {
                    i = sql.index(after: newline)
                    tokens.append(SQLToken(kind: .comment, range: start..<i))
                } else {
                    tokens.append(SQLToken(kind: .comment, range: start..<sql.endIndex))
                    i = sql.endIndex
                }
                continue
            }

            // Block comment: /* ... */
            if c == "/", let next = sql.index(i, offsetBy: 1, limitedBy: sql.endIndex),
               next < sql.endIndex, sql[next] == "*" {
                let start = i
                i = sql.index(i, offsetBy: 2)
                while i < sql.endIndex {
                    if sql[i] == "*",
                       let next2 = sql.index(i, offsetBy: 1, limitedBy: sql.endIndex),
                       next2 < sql.endIndex, sql[next2] == "/" {
                        i = sql.index(i, offsetBy: 2)
                        break
                    }
                    i = sql.index(after: i)
                }
                tokens.append(SQLToken(kind: .comment, range: start..<i))
                continue
            }

            // String literal: 'text' (handles escaped quotes '')
            if c == "'" {
                let start = i
                i = sql.index(after: i)
                var closed = false
                while i < sql.endIndex {
                    if sql[i] == "\\" {
                        let escaped = sql.index(after: i)
                        i = escaped < sql.endIndex ? sql.index(after: escaped) : escaped
                        continue
                    }
                    if sql[i] == "'" {
                        let afterQuote = sql.index(after: i)
                        if afterQuote < sql.endIndex, sql[afterQuote] == "'" {
                            i = sql.index(after: afterQuote) // skip ''
                        } else {
                            i = afterQuote
                            closed = true
                            break
                        }
                    } else {
                        i = sql.index(after: i)
                    }
                }
                tokens.append(SQLToken(kind: closed ? .string : .error, range: start..<i))
                continue
            }

            // Backtick identifier: `name`
            if c == "`" {
                let start = i
                i = sql.index(after: i)
                var closed = false
                while i < sql.endIndex {
                    if sql[i] == "`" {
                        let afterQuote = sql.index(after: i)
                        if afterQuote < sql.endIndex, sql[afterQuote] == "`" {
                            i = sql.index(after: afterQuote)
                        } else {
                            i = afterQuote
                            closed = true
                            break
                        }
                    } else {
                        i = sql.index(after: i)
                    }
                }
                tokens.append(SQLToken(kind: closed ? .identifier : .error, range: start..<i))
                continue
            }

            // Double-quoted identifier: "name"
            if c == "\"" {
                let start = i
                i = sql.index(after: i)
                var closed = false
                while i < sql.endIndex {
                    if sql[i] == "\\" {
                        let escaped = sql.index(after: i)
                        i = escaped < sql.endIndex ? sql.index(after: escaped) : escaped
                        continue
                    }
                    if sql[i] == "\"" {
                        let afterQuote = sql.index(after: i)
                        if afterQuote < sql.endIndex, sql[afterQuote] == "\"" {
                            i = sql.index(after: afterQuote)
                        } else {
                            i = afterQuote
                            closed = true
                            break
                        }
                    } else {
                        i = sql.index(after: i)
                    }
                }
                tokens.append(SQLToken(kind: closed ? .identifier : .error, range: start..<i))
                continue
            }

            // Number
            if c.isNumber || (c == "." && i < sql.endIndex) {
                let start = i
                if c.isNumber {
                    while i < sql.endIndex, sql[i].isNumber || sql[i] == "." {
                        i = sql.index(after: i)
                    }
                    tokens.append(SQLToken(kind: .number, range: start..<i))
                    continue
                }
            }

            // Word (keyword, function, or plain identifier)
            if c.isLetter || c == "_" || c == "@" {
                let start = i
                while i < sql.endIndex, sql[i].isLetter || sql[i].isNumber || sql[i] == "_" || sql[i] == "." || sql[i] == "@" {
                    i = sql.index(after: i)
                }
                let word = String(sql[start..<i])
                let upper = word.uppercased()
                if keywords.contains(upper) {
                    tokens.append(SQLToken(kind: .keyword, range: start..<i))
                } else if functions.contains(upper) {
                    tokens.append(SQLToken(kind: .function, range: start..<i))
                } else {
                    tokens.append(SQLToken(kind: .plain, range: start..<i))
                }
                continue
            }

            // Operators
            if "<>=!+-*/%".contains(c) {
                let start = i
                i = sql.index(after: i)
                if i < sql.endIndex, "=><".contains(sql[i]) {
                    i = sql.index(after: i)
                }
                tokens.append(SQLToken(kind: .operator_, range: start..<i))
                continue
            }

            // Punctuation
            if "(),;.".contains(c) {
                let start = i
                i = sql.index(after: i)
                tokens.append(SQLToken(kind: .punctuation, range: start..<i))
                continue
            }

            // Unknown character — advance
            i = sql.index(after: i)
        }

        return tokens
    }

    // MARK: Statements

    /// Splits a script only at terminators that the lexer identified outside
    /// strings, quoted identifiers, and comments. Compound routine bodies keep
    /// their internal terminators until the matching END keyword.
    static func statements(in sql: String) -> [SQLStatement] {
        let tokens = tokenize(sql).filter { $0.kind != .comment }
        var ranges: [Range<String.Index>] = []
        var statementStart = sql.startIndex
        var compoundDepth = 0
        var isRoutineDefinition = false
        var significantWords: [String] = []

        var previousWord: String?
        for (tokenIndex, token) in tokens.enumerated() {
            let text = String(sql[token.range])
            let upper = text.uppercased()

            if token.kind == .keyword || token.kind == .plain {
                significantWords.append(upper)
                if significantWords.count <= 4,
                   significantWords.first == "CREATE",
                   ["PROCEDURE", "FUNCTION", "TRIGGER", "EVENT"].contains(upper) {
                    isRoutineDefinition = true
                }
                if isRoutineDefinition {
                    let opensCompound: Bool
                    if upper == "IF" {
                        opensCompound = tokens[(tokenIndex + 1)...].prefix { future in
                            !(future.kind == .punctuation && String(sql[future.range]) == ";")
                        }.contains { future in
                            String(sql[future.range]).uppercased() == "THEN"
                        }
                    } else {
                        opensCompound = ["BEGIN", "CASE", "LOOP", "WHILE", "REPEAT"].contains(upper)
                    }
                    if opensCompound, previousWord != "END" {
                        compoundDepth += 1
                    } else if upper == "END", compoundDepth > 0 {
                        compoundDepth -= 1
                    }
                }
                previousWord = upper
            }

            guard token.kind == .punctuation, text == ";", compoundDepth == 0 else {
                continue
            }

            appendMeaningfulRange(statementStart..<token.range.lowerBound, in: sql, to: &ranges)
            statementStart = token.range.upperBound
            significantWords.removeAll(keepingCapacity: true)
            isRoutineDefinition = false
            previousWord = nil
        }

        appendMeaningfulRange(statementStart..<sql.endIndex, in: sql, to: &ranges)
        return ranges.enumerated().map { index, range in
            let text = String(sql[range])
            return SQLStatement(
                id: index,
                text: text,
                range: range,
                safety: safetyClassification(of: text)
            )
        }
    }

    static func editorText(forGeneratedQuery sql: String) -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasSuffix(";") ? trimmed : trimmed + ";"
    }

    /// Returns the selected SQL, or the parsed statement containing the caret.
    /// A non-empty selection may intentionally contain multiple statements.
    static func statementsToExecute(in sql: String, selectedRange: NSRange) -> [SQLStatement] {
        guard !sql.isEmpty else { return [] }
        let boundedLocation = min(selectedRange.location, (sql as NSString).length)
        let boundedLength = min(selectedRange.length, (sql as NSString).length - boundedLocation)

        if boundedLength > 0,
           let range = Range(NSRange(location: boundedLocation, length: boundedLength), in: sql) {
            return statements(in: String(sql[range]))
        }

        let caret = String.Index(utf16Offset: boundedLocation, in: sql)
        let parsed = statements(in: sql)
        if let containing = parsed.first(where: { $0.range.contains(caret) || $0.range.upperBound == caret }) {
            return [containing]
        }
        if let previous = parsed.last(where: { $0.range.upperBound < caret }) {
            return [previous]
        }
        return parsed.first.map { [$0] } ?? []
    }

    static func statementsToExecute(in sql: String, selectedRange: NSRange, mode: SQLExecutionMode) -> [SQLStatement] {
        switch mode {
        case .automatic:
            return statementsToExecute(in: sql, selectedRange: selectedRange)
        case .statement:
            return statementsToExecute(in: sql, selectedRange: NSRange(location: selectedRange.location, length: 0))
        case .selection:
            guard selectedRange.length > 0, selectedRange.location < (sql as NSString).length else { return [] }
            return statementsToExecute(in: sql, selectedRange: selectedRange)
        case .all:
            return statements(in: sql)
        }
    }

    static func safetyClassification(of sql: String) -> SQLSafetyClassification {
        let words = tokenize(sql).compactMap { token -> String? in
            guard token.kind == .keyword || token.kind == .plain else { return nil }
            return String(sql[token.range]).uppercased()
        }
        guard !words.isEmpty else { return .unknown }

        if words[0] == "WITH" {
            // A CTE may read in its first subquery and mutate in its outer
            // statement (or mutate inside a data-modifying CTE). Classify the
            // whole token stream so an earlier SELECT cannot hide that write.
            if words.contains(where: {
                ["DELETE", "DROP", "TRUNCATE", "ALTER", "RENAME", "GRANT", "REVOKE", "LOAD"].contains($0)
            }) {
                return .destructive
            }
            if words.contains(where: {
                ["INSERT", "UPDATE", "REPLACE", "MERGE", "CALL", "CREATE"].contains($0)
            }) {
                return .mutation
            }
        }
        let leading = words[0] == "WITH" && words.contains("SELECT") ? "SELECT" : words[0]

        switch leading {
        case "SELECT":
            // SELECT ... INTO OUTFILE/DUMPFILE writes to the server filesystem.
            if words.contains("INTO"), words.contains("OUTFILE") || words.contains("DUMPFILE") {
                return .destructive
            }
            // PostgreSQL SELECT INTO creates a table, while MySQL SELECT INTO
            // can assign session variables. Neither is a read-only result set.
            if words.contains("INTO") {
                return .mutation
            }
            if words.contains("FOR"), words.contains("UPDATE") || words.contains("SHARE") {
                return .mutation
            }
            return .readOnly
        case "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "VALUES":
            return .readOnly
        case "INSERT", "UPDATE", "REPLACE", "MERGE", "CALL":
            return .mutation
        case "DELETE":
            return .destructive
        case "DROP", "TRUNCATE", "ALTER", "RENAME", "GRANT", "REVOKE", "LOAD":
            return .destructive
        case "CREATE":
            return .mutation
        case "SET":
            if words.contains("GLOBAL") || words.contains("PERSIST") || words.contains("PERSIST_ONLY") {
                return .mutation
            }
            return .sessionControl
        case "USE", "BEGIN", "START", "COMMIT", "ROLLBACK", "SAVEPOINT", "LOCK", "UNLOCK":
            return .sessionControl
        default:
            return .unknown
        }
    }

    /// Wraps a single, parser-validated SELECT/CTE and asks the server for one
    /// sentinel row beyond the configured display bound. Mutations, locking
    /// reads, utility commands, malformed input, and scripts are never rewritten.
    static func boundedReadPlan(
        for sql: String,
        rowLimit: Int,
        dialect: DatabaseDialect
    ) -> SQLBoundedReadPlan? {
        guard validEditorResultRowLimits.contains(rowLimit) else { return nil }
        let parsed = statements(in: sql)
        guard parsed.count == 1,
              parsed[0].safety == .readOnly,
              topLevelOperation(in: parsed[0].text) == "SELECT" else { return nil }

        let fetchLimit = rowLimit + 1
        let statement = parsed[0].text
        let executionSQL: String
        switch dialect {
        case .mysql, .postgresql, .sqlite:
            executionSQL = """
            SELECT * FROM (
            \(statement)
            ) AS glassdb_bounded_result
            LIMIT \(fetchLimit)
            """
        }
        return SQLBoundedReadPlan(
            originalSQL: sql,
            executionSQL: executionSQL,
            rowLimit: rowLimit,
            fetchLimit: fetchLimit
        )
    }

    private static func topLevelOperation(in sql: String) -> String? {
        let tokens = tokenize(sql).filter { $0.kind != .comment }
        guard !tokens.contains(where: { $0.kind == .error }) else { return nil }

        var depth = 0
        for token in tokens where token.kind == .punctuation {
            switch String(sql[token.range]) {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth < 0 { return nil }
            default: break
            }
        }
        guard depth == 0 else { return nil }

        let operationWords: Set<String> = [
            "SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "REPLACE",
            "CREATE", "DROP", "ALTER", "CALL", "VALUES", "TABLE"
        ]
        var parenthesisDepth = 0
        var sawWith = false
        for token in tokens {
            if token.kind == .punctuation {
                switch String(sql[token.range]) {
                case "(": parenthesisDepth += 1
                case ")": parenthesisDepth -= 1
                default: break
                }
                continue
            }
            guard token.kind == .keyword || token.kind == .plain else { continue }
            let word = String(sql[token.range]).uppercased()
            if !sawWith {
                if word == "SELECT" { return word }
                guard word == "WITH" else { return word }
                sawWith = true
                continue
            }
            if parenthesisDepth == 0, operationWords.contains(word) {
                return word
            }
        }
        return nil
    }

    static func redactingLiterals(in sql: String) -> String {
        let tokens = tokenize(sql)
        var output = ""
        var cursor = sql.startIndex
        for token in tokens where token.kind == .string || token.kind == .number {
            output += sql[cursor..<token.range.lowerBound]
            output += token.kind == .string ? "'?'" : "?"
            cursor = token.range.upperBound
        }
        output += sql[cursor..<sql.endIndex]
        return output
    }

    // MARK: Completion and Formatting

    /// The database qualifier currently being completed, not the session's
    /// selected database. Reuses caret/token rules to exclude strings/comments.
    static func completionDatabase(in sql: String, selectedRange: NSRange) -> String? {
        guard let context = completionContext(in: sql, selectedRange: selectedRange),
              let dot = context.prefix.firstIndex(of: "."),
              dot != context.prefix.startIndex else { return nil }
        return String(context.prefix[..<dot])
    }

    /// Returns bounded, deterministic suggestions for the identifier fragment at
    /// the caret. Callers supply live schema names so completion never invents
    /// database objects or requires a second parser implementation in the UI.
    static func completions(
        in sql: String,
        selectedRange: NSRange,
        schemaIdentifiers: [String],
        limit: Int = 12
    ) -> [String] {
        guard limit > 0,
              let context = completionContext(in: sql, selectedRange: selectedRange),
              !context.prefix.isEmpty else { return [] }

        let candidates = keywords.union(functions).union(schemaIdentifiers)
        return candidates
            .filter { $0.lowercased().hasPrefix(context.prefix.lowercased()) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.caseInsensitiveCompare(context.prefix) == .orderedSame
                let rhsExact = rhs.caseInsensitiveCompare(context.prefix) == .orderedSame
                if lhsExact != rhsExact { return lhsExact }
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The dimmed inline preview for Tab-to-complete: the characters that
    /// accepting the top suggestion would append at the caret. `nil` when
    /// there is no suggestion, the prefix is empty, or the suggestion does
    /// not extend the prefix (e.g. exact match already typed).
    static func completionPreviewSuffix(
        in sql: String,
        selectedRange: NSRange,
        schemaIdentifiers: [String]
    ) -> String? {
        guard let context = completionContext(in: sql, selectedRange: selectedRange),
              !context.prefix.isEmpty,
              let top = completions(
                  in: sql,
                  selectedRange: selectedRange,
                  schemaIdentifiers: schemaIdentifiers,
                  limit: 1
              ).first,
              top.count > context.prefix.count,
              top.lowercased().hasPrefix(context.prefix.lowercased())
        else { return nil }
        return String(top.dropFirst(context.prefix.count))
    }

    /// Replaces only the completion fragment immediately before the caret and
    /// returns the new selection. A non-empty selection is replaced directly.
    static func applyingCompletion(
        _ completion: String,
        to sql: String,
        selectedRange: NSRange,
        appendSpace: Bool = false,
        databaseNames: [String] = []
    ) -> (sql: String, selection: NSRange, automaticSpace: Int?) {
        let source = sql as NSString
        let location = min(selectedRange.location, source.length)
        let length = min(selectedRange.length, source.length - location)
        let replacementRange: NSRange
        if length > 0 {
            replacementRange = NSRange(location: location, length: length)
        } else if let context = completionContext(
            in: sql,
            selectedRange: NSRange(location: location, length: 0)
        ) {
            replacementRange = context.range
        } else {
            replacementRange = NSRange(location: location, length: 0)
        }
        // USE/CREATE DATABASE consume a database name, not a qualified table.
        let leadingWords = source.substring(to: replacementRange.location)
            .split(whereSeparator: { $0.isWhitespace }).last?.uppercased()
        let qualifiesDatabase = databaseNames.contains(completion)
            && !["USE", "DATABASE", "SCHEMA"].contains(leadingWords ?? "")
        var completed = source.replacingCharacters(in: replacementRange, with: completion)
        var caret = replacementRange.location + (completion as NSString).length
        var automaticSpace: Int?
        if qualifiesDatabase {
            if (completed as NSString).substring(from: caret).hasPrefix(".") {
                caret += 1
            } else {
                completed = (completed as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: ".")
                caret += 1
            }
        } else if appendSpace {
            let tail = (completed as NSString).substring(from: caret)
            if tail.first == " " || tail.first == "\t" {
                caret += 1
            } else if tail.first.map({ !$0.isWhitespace && !".,;()[]".contains($0) }) ?? true {
                completed = (completed as NSString).replacingCharacters(
                    in: NSRange(location: caret, length: 0), with: " "
                )
                automaticSpace = caret
                caret += 1
            }
        }
        return (completed, NSRange(location: caret, length: 0), automaticSpace)
    }

    /// Normalizes keyword case and statement spacing while preserving string,
    /// identifier, comment, and compound-routine contents byte-for-byte.
    static func formatted(_ sql: String) -> String {
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let mutable = NSMutableString(string: sql)
        for token in tokenize(sql).reversed() where token.kind == .keyword {
            let range = NSRange(token.range, in: sql)
            mutable.replaceCharacters(in: range, with: String(sql[token.range]).uppercased())
        }
        let normalized = mutable as String
        return statements(in: normalized)
            .map(\.text)
            .joined(separator: ";\n\n")
    }

    private static func completionContext(
        in sql: String,
        selectedRange: NSRange
    ) -> (range: NSRange, prefix: String)? {
        let source = sql as NSString
        let location = min(selectedRange.location, source.length)
        let length = min(selectedRange.length, source.length - location)
        if length > 0 {
            let range = NSRange(location: location, length: length)
            return (range, source.substring(with: range))
        }

        let caret = String.Index(utf16Offset: location, in: sql)
        if tokenize(sql).contains(where: { token in
            let containsCaret = token.range.contains(caret)
                || (token.range.upperBound == caret && token.range.lowerBound < caret)
            return containsCaret && [.string, .comment, .error].contains(token.kind)
        }) {
            return nil
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.$@"))
        var start = location
        while start > 0 {
            let scalar = source.character(at: start - 1)
            guard let unicode = UnicodeScalar(scalar), allowed.contains(unicode) else { break }
            start -= 1
        }
        let range = NSRange(location: start, length: location - start)
        return (range, source.substring(with: range))
    }

    private static func appendMeaningfulRange(
        _ candidate: Range<String.Index>,
        in sql: String,
        to ranges: inout [Range<String.Index>]
    ) {
        guard let lower = sql[candidate].firstIndex(where: { !$0.isWhitespace }) else { return }
        var upper = candidate.upperBound
        while upper > lower {
            let previous = sql.index(before: upper)
            guard sql[previous].isWhitespace else { break }
            upper = previous
        }
        let range = lower..<upper
        let meaningful = tokenize(String(sql[range])).contains { $0.kind != .comment }
        if meaningful {
            ranges.append(range)
        }
    }

    // MARK: Lint

    static func lint(_ sql: String, tokens: [SQLToken]? = nil) -> [SQLDiagnostic] {
        let toks = tokens ?? tokenize(sql)
        var diagnostics: [SQLDiagnostic] = []

        for token in toks {
            if token.kind == .error {
                diagnostics.append(SQLDiagnostic(
                    range: token.range,
                    message: "Unterminated string or identifier"
                ))
            }
        }

        return diagnostics
    }

    // MARK: Attributed String

    #if canImport(UIKit)
    static func highlight(_ sql: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let tokens = tokenize(sql)
        let attr = NSMutableAttributedString(
            string: sql,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: UIColor.label,
            ]
        )

        for token in tokens {
            let nsRange = NSRange(token.range, in: sql)
            let color: UIColor
            switch token.kind {
            case .keyword:
                color = .systemBlue
                attr.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), range: nsRange)
            case .function:
                color = .systemPurple
            case .string:
                color = UIColor.systemGreen
            case .number:
                color = UIColor.systemOrange
            case .comment:
                color = .secondaryLabel
            case .identifier:
                color = .systemTeal
            case .operator_:
                color = .label
            case .punctuation:
                color = .secondaryLabel
            case .error:
                color = UIColor.systemRed
                attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                attr.addAttribute(.underlineColor, value: UIColor.systemRed, range: nsRange)
            case .plain:
                color = .label
            }
            attr.addAttribute(.foregroundColor, value: color, range: nsRange)
        }

        // Lint diagnostics — add wavy underline on errors
        let diagnostics = lint(sql, tokens: tokens)
        for diag in diagnostics {
            let nsRange = NSRange(diag.range, in: sql)
            attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.union(.single).rawValue, range: nsRange)
            attr.addAttribute(.underlineColor, value: UIColor.systemRed, range: nsRange)
        }

        return attr
    }
    #elseif canImport(AppKit)
    static func highlight(_ sql: String, fontSize: CGFloat = 14) -> NSAttributedString {
        let tokens = tokenize(sql)
        let attr = NSMutableAttributedString(
            string: sql,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        for token in tokens {
            let nsRange = NSRange(token.range, in: sql)
            let color: NSColor
            switch token.kind {
            case .keyword:
                color = .systemBlue
                attr.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), range: nsRange)
            case .function:
                color = .systemPurple
            case .string:
                color = .systemGreen
            case .number:
                color = .systemOrange
            case .comment:
                color = .secondaryLabelColor
            case .identifier:
                color = .systemTeal
            case .operator_:
                color = .labelColor
            case .punctuation:
                color = .secondaryLabelColor
            case .error:
                color = .systemRed
                attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                attr.addAttribute(.underlineColor, value: NSColor.systemRed, range: nsRange)
            case .plain:
                color = .labelColor
            }
            attr.addAttribute(.foregroundColor, value: color, range: nsRange)
        }

        for diagnostic in lint(sql, tokens: tokens) {
            let nsRange = NSRange(diagnostic.range, in: sql)
            attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.union(.single).rawValue, range: nsRange)
            attr.addAttribute(.underlineColor, value: NSColor.systemRed, range: nsRange)
        }

        return attr
    }
    #endif
}
