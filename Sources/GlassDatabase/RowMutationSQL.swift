//
//  RowMutationSQL.swift
//  Glass Power Tools — GlassDatabase
//
//  The row-identity predicate every single-row write path shares, and the DELETE built on it.
//
//  This is an extraction, not a new idea. The single-row update (`TableDetailView.applyEdits`)
//  and the pasted-range update (`applyBatchPaste`) each built the same optimistic `WHERE` inline:
//  the primary key **plus every original value of the row**, so a row that changed underneath the
//  user matches nothing and the mutation is refused rather than silently overwriting a concurrent
//  edit. Row deletion needs exactly that predicate, so it moved here and all three callers use it
//  instead of a third copy.
//
//  Not to be confused with `GridServerQueryBuilder.predicate`, which is the *browsing* filter
//  behind SELECT and COUNT. That one answers "which rows is the user looking at"; this one
//  answers "which single row is this write allowed to touch". The Stage 3 plan conflated them.
//

import Foundation
import GlassDBKit

enum RowIdentityError: LocalizedError, Equatable {
    case noPrimaryKey
    case emptyPredicate
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .noPrimaryKey:
            return "This table has no primary key, so a single row cannot be identified safely."
        case .emptyPredicate:
            return "The row carries no values to identify it with, so the write was not attempted."
        case .invalidIdentifier(let name):
            return "\"\(name)\" is not a usable identifier."
        }
    }
}

/// One row's optimistic identity, ready to bind.
struct RowIdentityPredicate: Equatable {
    /// Clauses joined with `AND`. No leading `WHERE`, so callers compose it as they already did.
    let sql: String
    /// The values to bind, in placeholder order. **Never** stored in an audit record.
    let parameters: [DatabaseValue]
    /// The columns the predicate constrains, in order.
    let columnNames: [String]

    /// The predicate with its placeholders intact — what the audit log records.
    ///
    /// Deliberately identical to `sql`: the bound values are a verbatim copy of the whole row,
    /// so recording them would copy the user's data into `UserDefaults`. The shape says which
    /// columns identified the row and whether NULLs took part, and says nothing about their
    /// contents.
    var auditShape: String { sql }
}

enum RowMutationSQL {

    /// The predicate the update paths have always built, extracted verbatim.
    ///
    /// - Parameter parameterOffset: how many parameters the caller has already bound. The single-row
    ///   update binds its `SET` values first, so its predicate placeholders do not start at `$1`.
    /// - Note: columns past the end of `row` are skipped, exactly as the inline versions did — a
    ///   result set narrower than the column metadata must not index out of bounds.
    static func identityPredicate(
        columns: [ColumnInfo],
        row: [DatabaseValue],
        identifierQuote: Character,
        dialect: DatabaseDialect,
        parameterOffset: Int = 0
    ) throws -> RowIdentityPredicate {
        guard columns.contains(where: \.isPrimaryKey) else { throw RowIdentityError.noPrimaryKey }

        var clauses: [String] = []
        var parameters: [DatabaseValue] = []
        var names: [String] = []
        for (index, column) in columns.enumerated() where index < row.count {
            let identifier = try quoted(column.name, identifierQuote)
            names.append(column.name)
            let original = row[index]
            if original.isNull {
                clauses.append("\(identifier) IS NULL")
            } else {
                parameters.append(original)
                clauses.append("\(identifier) = \(placeholder(parameterOffset + parameters.count, dialect: dialect))")
            }
        }
        guard !clauses.isEmpty else { throw RowIdentityError.emptyPredicate }

        return RowIdentityPredicate(
            sql: clauses.joined(separator: " AND "),
            parameters: parameters,
            columnNames: names
        )
    }

    /// `DELETE FROM db.table WHERE <row identity>`.
    ///
    /// The caller runs this inside a transaction and refuses to commit unless the server reports
    /// exactly one affected row — the same guard the update paths use, and the reason a stale
    /// row or a duplicate cannot be deleted by accident.
    static func delete(
        database: String,
        table: String,
        columns: [ColumnInfo],
        row: [DatabaseValue],
        identifierQuote: Character,
        dialect: DatabaseDialect
    ) throws -> (sql: String, predicate: RowIdentityPredicate) {
        let predicate = try identityPredicate(
            columns: columns,
            row: row,
            identifierQuote: identifierQuote,
            dialect: dialect
        )
        let qualified = "\(try quoted(database, identifierQuote)).\(try quoted(table, identifierQuote))"
        return ("DELETE FROM \(qualified) WHERE \(predicate.sql)", predicate)
    }

    // MARK: - Identifiers

    /// Quotes and doubles the delimiter, and refuses an identifier that cannot be one.
    /// Column names arrive from server metadata, but the check costs nothing and a control
    /// character in an identifier is never legitimate.
    private static func quoted(_ value: String, _ delimiter: Character) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 256,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw RowIdentityError.invalidIdentifier(value)
        }
        let quote = String(delimiter)
        return "\(quote)\(trimmed.replacingOccurrences(of: quote, with: quote + quote))\(quote)"
    }

    private static func placeholder(_ position: Int, dialect: DatabaseDialect) -> String {
        dialect == .postgresql ? "$\(position)" : "?"
    }
}
