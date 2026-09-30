//
//  SchemaDiagram.swift
//  Glass Power Tools — GlassDatabase
//
//  One database's tables, their columns and the foreign keys between them, read live from the
//  connection: what the schema diagram draws (D43, 2026-09-30). The reads are the engine's own
//  per-table ones (`tables`, `columns`, `foreignKeys`), which every dialect already implements and
//  tests, so the diagram agrees with the Structure and Foreign Keys views by construction.
//

import Foundation
import GlassDBKit

/// A database as the diagram sees it.
struct SchemaDiagram: Sendable, Equatable {
    struct Column: Sendable, Hashable {
        var name: String
        var type: String
        var isPrimaryKey: Bool
        var isForeignKey: Bool
        var isNullable: Bool
    }

    struct Table: Sendable, Hashable, Identifiable {
        var name: String
        var columns: [Column]
        var id: String { name }

        /// The columns a "Keys Only" card shows: primary and foreign keys, in table order.
        var keyColumns: [Column] { columns.filter { $0.isPrimaryKey || $0.isForeignKey } }
    }

    /// One foreign-key constraint: composite keys are one relationship, not one per column.
    struct Relationship: Sendable, Hashable, Identifiable {
        var name: String
        var fromTable: String
        var fromColumns: [String]
        var toTable: String
        var toColumns: [String]
        var id: String { "\(fromTable)\u{1F}\(name)" }
        var isSelfReference: Bool { fromTable == toTable }
    }

    var database: String
    var tables: [Table]
    var relationships: [Relationship]
    /// Tables left out because the database has more than `SchemaDiagramLoader.tableLimit`.
    var omittedTableCount: Int = 0
    /// Keys whose referenced table is not in the diagram (another schema, or one left out).
    var unresolvedRelationshipCount: Int = 0

    func table(named name: String) -> Table? { tables.first { $0.name == name } }

    /// The tables joined to `name` by a key in either direction, not counting itself.
    func neighbors(of name: String) -> Set<String> {
        var result = Set<String>()
        for relationship in relationships {
            if relationship.fromTable == name { result.insert(relationship.toTable) }
            if relationship.toTable == name { result.insert(relationship.fromTable) }
        }
        result.remove(name)
        return result
    }
}

enum SchemaDiagramLoader {
    /// Past this the diagram is unreadable anyway and the load takes minutes over a tunnel; the
    /// first tables by name are shown and the rest are counted.
    static let tableLimit = 300

    /// Reads the whole diagram. `progress` is told how many tables are done out of how many.
    static func load(connection: any DatabaseConnection,
                     database: String,
                     progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> SchemaDiagram {
        let allNames = try await connection.tables(in: database)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let names = Array(allNames.prefix(tableLimit))
        var columnsByTable: [String: [ColumnInfo]] = [:]
        var keysByTable: [String: [ForeignKeyInfo]] = [:]
        await progress(0, names.count)
        for (index, name) in names.enumerated() {
            try Task.checkCancellation()
            columnsByTable[name] = try await connection.columns(in: name, database: database)
            keysByTable[name] = try await connection.foreignKeys(in: name, database: database)
            await progress(index + 1, names.count)
        }
        var diagram = assemble(database: database, tableNames: names,
                               columns: columnsByTable, foreignKeys: keysByTable)
        diagram.omittedTableCount = allNames.count - names.count
        return diagram
    }

    /// The pure half of `load`, so the rules are testable without a server.
    static func assemble(database: String, tableNames: [String],
                         columns: [String: [ColumnInfo]],
                         foreignKeys: [String: [ForeignKeyInfo]]) -> SchemaDiagram {
        let present = Set(tableNames)
        var relationships: [SchemaDiagram.Relationship] = []
        var unresolved = 0
        var foreignKeyColumns: [String: Set<String>] = [:]

        for table in tableNames {
            let groups = Dictionary(grouping: foreignKeys[table] ?? [], by: \.constraintName)
            for (name, members) in groups.sorted(by: { $0.key < $1.key }) {
                let ordered = members.sorted { $0.ordinalPosition < $1.ordinalPosition }
                guard let target = ordered.first?.referencedTable else { continue }
                foreignKeyColumns[table, default: []].formUnion(ordered.map(\.columnName))
                guard present.contains(target) else { unresolved += 1; continue }
                var toColumns = ordered.map(\.referencedColumn)
                // SQLite reports an empty referenced column for a key to the target's implicit
                // primary key (`REFERENCES customers` with no column list).
                if toColumns.contains(where: \.isEmpty) {
                    let primary = (columns[target] ?? []).filter(\.isPrimaryKey)
                        .sorted { $0.ordinalPosition < $1.ordinalPosition }.map(\.name)
                    if primary.count == toColumns.count { toColumns = primary }
                }
                relationships.append(.init(name: name, fromTable: table,
                                           fromColumns: ordered.map(\.columnName),
                                           toTable: target, toColumns: toColumns))
            }
        }

        let tables = tableNames.map { name in
            let keyed = foreignKeyColumns[name] ?? []
            let ordered = (columns[name] ?? []).sorted { $0.ordinalPosition < $1.ordinalPosition }
            return SchemaDiagram.Table(name: name, columns: ordered.map {
                .init(name: $0.name, type: $0.type, isPrimaryKey: $0.isPrimaryKey,
                      isForeignKey: keyed.contains($0.name), isNullable: $0.isNullable)
            })
        }
        return SchemaDiagram(database: database, tables: tables, relationships: relationships,
                             unresolvedRelationshipCount: unresolved)
    }
}
