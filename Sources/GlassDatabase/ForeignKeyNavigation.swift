//
//  ForeignKeyNavigation.swift
//  Glass Power Tools — GlassDatabase
//
//  Following a foreign key: open the referenced table showing the referenced row.
//
//  The keys themselves were already displayed (the Foreign Keys tab, `TableDetailView` :5552).
//  What did not exist was the act of following one. This turns a selected row plus a relationship
//  into the *browsing* filters the grid already knows how to apply — `GridColumnFilter`, which
//  `GridServerQueryBuilder.predicate` turns into a bound `WHERE` on the target table's SELECT.
//  That is the browsing predicate's correct use, and it is a different predicate from
//  `RowMutationSQL`, which identifies a row to write to.
//
//  `foreignKeys(in:database:)` returns one row per key column. Until 2026-09-12 a two-column key
//  came back as a four-row cross product with no ordinal correlation, asserting `x → b` alongside
//  `x → a`. Navigation built on that would have filtered the referenced table by the wrong column
//  and shown a wrong row confidently, so the ordinal pairing is reconstructed here explicitly and
//  a key whose ordinals do not line up is refused rather than followed.
//

import Foundation
import GlassDBKit

/// One followable relationship: a named constraint, its column pairs in ordinal order, and the
/// table it points at.
struct ForeignKeyRelationship: Identifiable, Equatable, Sendable {
    struct ColumnPair: Equatable, Sendable {
        let column: String
        let referencedColumn: String
    }

    let constraintName: String
    let referencedTable: String
    let pairs: [ColumnPair]

    var id: String { constraintName }
    var isComposite: Bool { pairs.count > 1 }

    /// `team_id → teams.id`, or `(x, y) → parent (a, b)` for a composite key.
    var summary: String {
        let local = pairs.map(\.column).joined(separator: ", ")
        let remote = pairs.map(\.referencedColumn).joined(separator: ", ")
        return isComposite
            ? "(\(local)) → \(referencedTable) (\(remote))"
            : "\(local) → \(referencedTable).\(remote)"
    }
}

enum ForeignKeyNavigationError: LocalizedError, Equatable {
    case nullReference(column: String)
    case unfollowableValue(column: String, reason: String)
    case missingColumn(String)
    case inconsistentOrdinals(constraint: String)

    var errorDescription: String? {
        switch self {
        case .nullReference(let column):
            return "‘\(column)’ is NULL in this row, so it references nothing to open."
        case .unfollowableValue(let column, let reason):
            return "‘\(column)’ cannot be used as a filter: \(reason)"
        case .missingColumn(let name):
            return "‘\(name)’ is not present in the loaded result, so the reference cannot be followed."
        case .inconsistentOrdinals(let constraint):
            return "‘\(constraint)’ reports its columns inconsistently and was not followed."
        }
    }
}

enum ForeignKeyNavigation {

    /// Groups the per-column rows into relationships, pairing each key's columns by ordinal.
    ///
    /// A key is dropped rather than guessed at when its ordinals repeat — the signature of the
    /// cross-product defect — or when its members disagree about the referenced table.
    static func relationships(from keys: [ForeignKeyInfo]) -> [ForeignKeyRelationship] {
        Dictionary(grouping: keys, by: \.constraintName)
            .compactMap { name, members -> ForeignKeyRelationship? in
                let ordered = members.sorted { $0.ordinalPosition < $1.ordinalPosition }
                guard let referencedTable = ordered.first?.referencedTable,
                      ordered.allSatisfy({ $0.referencedTable == referencedTable }),
                      Set(ordered.map(\.ordinalPosition)).count == ordered.count else { return nil }
                return ForeignKeyRelationship(
                    constraintName: name,
                    referencedTable: referencedTable,
                    pairs: ordered.map {
                        ForeignKeyRelationship.ColumnPair(column: $0.columnName,
                                                          referencedColumn: $0.referencedColumn)
                    }
                )
            }
            .sorted { $0.constraintName.localizedCaseInsensitiveCompare($1.constraintName) == .orderedAscending }
    }

    /// The filters that open `relationship.referencedTable` at the row this one references.
    ///
    /// **Every column pair is carried**, so a composite key lands on one row rather than on the
    /// first match of its leading column.
    ///
    /// - Parameters:
    ///   - columns: the metadata of the table being left, aligned with `row`.
    ///   - referencedColumns: the metadata of the table being opened. The filter is parsed and
    ///     bound against the *target's* declared type (D17), which is the type the server will
    ///     compare — not the type of the column being left, even though a foreign key makes them
    ///     compatible.
    static func filters(
        following relationship: ForeignKeyRelationship,
        row: [DatabaseValue],
        columns: [ColumnInfo],
        referencedColumns: [ColumnInfo],
        dialect: DatabaseDialect? = nil
    ) throws -> [GridColumnFilter] {
        var filters: [GridColumnFilter] = []
        for pair in relationship.pairs {
            guard let index = columns.firstIndex(where: { $0.name == pair.column }),
                  index < row.count else {
                throw ForeignKeyNavigationError.missingColumn(pair.column)
            }
            let value = row[index]
            // A NULL foreign key references no row. Opening the target filtered to IS NULL would
            // show whatever happens to have a NULL key there, which is a different question.
            guard !value.isNull else {
                throw ForeignKeyNavigationError.nullReference(column: pair.column)
            }
            let target = referencedColumns.first { $0.name == pair.referencedColumn }
            let filter = GridColumnFilter(
                columnName: pair.referencedColumn,
                columnType: target?.type ?? columns[index].type,
                isUnsigned: target?.isUnsigned ?? columns[index].isUnsigned,
                operation: .equals,
                value: value.displayString
            )
            // `displayString` is a presentation form, and for binary columns it is `<n bytes>`
            // rather than the bytes. Refuse rather than filter on a placeholder.
            if let reason = filter.validationError(dialect: dialect) {
                throw ForeignKeyNavigationError.unfollowableValue(column: pair.referencedColumn,
                                                                  reason: reason)
            }
            filters.append(filter)
        }
        return filters
    }
}

/// Filters staged for a table that is about to be opened.
///
/// Navigation is two steps — the workspace opens the tab, then the tab loads — and the target may
/// or may not already be mounted, so the filters cannot simply be handed to a view that might not
/// exist yet. They wait here and the data tab claims them, on first load or on being told to.
/// Nothing is written to `UserDefaults` by staging: only applying them persists, exactly as it
/// does when a user types a filter by hand.
@MainActor
enum ForeignKeyFilterHandoff {
    struct Key: Hashable {
        let sessionID: UUID
        let database: String
        let table: String
    }

    /// How long a staged handoff stays claimable. The claim it is waiting for happens on the very
    /// next run loop — the workspace opens the tab and the data tab's `.task` claims on mount — so
    /// this is not a race window, it is a bound on the one bad outcome: an entry that is *never*
    /// claimed (nothing opened the table) would otherwise sit there and silently filter the user's
    /// next ordinary visit to that table, which looks exactly like the app working.
    static let staleAfter: TimeInterval = 30

    private struct Staged {
        let filters: [GridColumnFilter]
        let at: Date
    }

    private static var staged: [Key: Staged] = [:]

    static func stage(_ filters: [GridColumnFilter], for key: Key, at now: Date = Date()) {
        staged[key] = Staged(filters: filters, at: now)
    }

    /// Reads and removes. A handoff is consumed once, and an old one is discarded rather than
    /// applied — a stale filter appearing on a later, unrelated visit would fail silently.
    static func claim(_ key: Key, at now: Date = Date()) -> [GridColumnFilter]? {
        guard let entry = staged.removeValue(forKey: key) else { return nil }
        guard now.timeIntervalSince(entry.at) <= staleAfter else { return nil }
        return entry.filters
    }

    static func reset() {
        staged.removeAll()
    }
}
