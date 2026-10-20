//
//  SQLTableReferences.swift
//  Glass Power Tools — GlassDatabase
//
//  The tables a statement names, and which database on the server holds them, for SQL a terminal
//  hands over (2026-10-20, the owner: "will take the SQL into a new editor with the proper database
//  and table selected (if possible)"). Read with the query editor's own tokenizer, so a table is
//  what the editor would call one: after FROM, JOIN, UPDATE, INTO and TABLE, as `table`,
//  `database.table` or `catalog.schema.table`, quoted or not.
//

import Foundation

enum SQLTableReferences {
    struct Reference: Equatable {
        /// The database (MySQL) or schema (PostgreSQL) the statement names, when it names one.
        let database: String?
        let table: String
    }

    /// Words a table name follows.
    private static let introducers: Set<String> = ["FROM", "JOIN", "UPDATE", "INTO", "TABLE"]
    /// Words between TABLE and its name: CREATE TABLE IF NOT EXISTS, DROP TABLE IF EXISTS.
    private static let skipped: Set<String> = ["IF", "NOT", "EXISTS", "ONLY", "LATERAL"]

    /// The tables `sql` names, in order, each once.
    static func tables(in sql: String) -> [Reference] {
        guard sql.utf8.count <= 64_000 else { return [] }
        let tokens = SQLHighlighter.tokenize(sql).filter { $0.kind != .comment }
        func text(_ index: Int) -> String { String(sql[tokens[index].range]) }
        func isName(_ index: Int) -> Bool {
            guard index < tokens.count else { return false }
            let kind = tokens[index].kind
            return kind == .identifier || kind == .plain
                || (kind == .keyword && !introducers.contains(text(index).uppercased())
                    && !["SELECT", "WHERE", "SET", "VALUES", "ON", "USING", "AS"].contains(text(index).uppercased()))
        }
        var found: [Reference] = []
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard introducers.contains(text(index).uppercased()) else { continue }
            var next = index + 1
            while next < tokens.count, skipped.contains(text(next).uppercased()) { next += 1 }
            guard isName(next) else { continue }
            var parts = names(text(next))
            while next + 2 < tokens.count, text(next + 1) == ".", isName(next + 2) {
                parts += names(text(next + 2))
                next += 2
            }
            guard let table = parts.last, !table.isEmpty else { continue }
            let reference = Reference(database: parts.count > 1 ? parts[parts.count - 2] : nil, table: table)
            if !found.contains(reference) { found.append(reference) }
        }
        return found
    }

    /// A name token's parts: the tokenizer keeps `shop.customers` unquoted as one token, and a quoted
    /// one (`"my.table"`) is one name whatever it holds.
    private static func names(_ token: String) -> [String] {
        let quotes = CharacterSet(charactersIn: "`\"[]")
        if let first = token.unicodeScalars.first, quotes.contains(first) {
            return [token.trimmingCharacters(in: quotes)]
        }
        return token.split(separator: ".").map { $0.trimmingCharacters(in: quotes) }
    }

    /// The most databases searched for an unqualified table: a server with hundreds is searched only
    /// as far as this, the current database always first.
    static let searchedDatabases = 64

    /// Where the first of `references` the server has is: the database it names, else the current
    /// database, else the first database that has it. Names are matched as the server spells them,
    /// ignoring case. Nil when none is found, or the server can't be asked.
    @MainActor
    static func locate(_ references: [Reference], current: String?,
                       databases: () async throws -> [String],
                       tables: (String) async throws -> [String]) async -> (database: String, table: String)? {
        var listed: [String: [String]] = [:]
        func tablesOf(_ database: String) async -> [String] {
            if let known = listed[database] { return known }
            let names = (try? await tables(database)) ?? []
            listed[database] = names
            return names
        }
        func match(_ table: String, in database: String) async -> String? {
            await tablesOf(database).first { $0.caseInsensitiveCompare(table) == .orderedSame }
        }
        var everyDatabase: [String]?
        func allDatabases() async -> [String] {
            if let everyDatabase { return everyDatabase }
            let all = (try? await databases()) ?? []
            everyDatabase = all
            return all
        }
        for reference in references {
            if let named = reference.database {
                let all = await allDatabases()
                let database = all.first { $0.caseInsensitiveCompare(named) == .orderedSame } ?? named
                if let table = await match(reference.table, in: database) { return (database, table) }
                continue
            }
            if let current, let table = await match(reference.table, in: current) { return (current, table) }
            let all = await allDatabases()
            for database in all.prefix(searchedDatabases) where database != current {
                if let table = await match(reference.table, in: database) { return (database, table) }
            }
        }
        return nil
    }
}
