import Foundation
import Testing
@testable import GlassDatabase

/// SQL from a terminal (2026-10-20): the tables it names, and the database on the server that has
/// them, so the query editor opens with them selected.
@MainActor
@Suite("The tables SQL names")
struct SQLTableReferencesTests {
    private typealias Reference = SQLTableReferences.Reference

    @Test("after FROM, JOIN, UPDATE, INTO and TABLE; qualified or not, quoted or not; each once")
    func references() {
        #expect(SQLTableReferences.tables(in: "SELECT * FROM orders o JOIN shop.customers c ON c.id = o.customer_id")
                == [Reference(database: nil, table: "orders"), Reference(database: "shop", table: "customers")])
        #expect(SQLTableReferences.tables(in: "UPDATE `billing`.`invoices` SET paid = 1") == [Reference(database: "billing", table: "invoices")])
        #expect(SQLTableReferences.tables(in: "INSERT INTO \"audit\" (at) VALUES (now())") == [Reference(database: nil, table: "audit")])
        #expect(SQLTableReferences.tables(in: "DELETE FROM sessions WHERE expires < now()") == [Reference(database: nil, table: "sessions")])
        #expect(SQLTableReferences.tables(in: "CREATE TABLE IF NOT EXISTS public.notes (id int)") == [Reference(database: "public", table: "notes")])
        #expect(SQLTableReferences.tables(in: "SELECT * FROM a, b WHERE a.x IN (SELECT y FROM a)").first == Reference(database: nil, table: "a"))
        #expect(SQLTableReferences.tables(in: "SELECT 1").isEmpty)
        #expect(SQLTableReferences.tables(in: "SELECT * FROM (SELECT 1) AS t").isEmpty, "a subquery is no table")
        #expect(SQLTableReferences.tables(in: "-- FROM comments\nSELECT 1 FROM dual") == [Reference(database: nil, table: "dual")])
    }

    /// A made-up server: its databases and their tables.
    private let server: [String: [String]] = ["shop": ["orders", "Customers"], "billing": ["invoices"], "empty": []]

    private func locate(_ sql: String, current: String?) async -> (database: String, table: String)? {
        await SQLTableReferences.locate(SQLTableReferences.tables(in: sql), current: current,
                                        databases: { Array(server.keys).sorted() },
                                        tables: { server[$0] ?? [] })
    }

    @Test("the database a name gives, else the current one, else the first that has it; spelled as the server has it")
    func locating() async throws {
        func expectFound(_ sql: String, current: String?, _ database: String, _ table: String,
                         _ comment: Comment? = nil) async throws {
            let found = try #require(await locate(sql, current: current), comment)
            #expect(found.database == database && found.table == table, comment)
        }
        try await expectFound("SELECT * FROM billing.invoices", current: "shop", "billing", "invoices")
        try await expectFound("SELECT * FROM orders", current: "shop", "shop", "orders")
        try await expectFound("SELECT * FROM invoices", current: "shop", "billing", "invoices", "searched for")
        try await expectFound("SELECT * FROM customers", current: nil, "shop", "Customers", "the server's spelling")
        #expect(await locate("SELECT * FROM nowhere", current: "shop") == nil)
        try await expectFound("SELECT * FROM nowhere JOIN orders ON 1", current: "empty", "shop", "orders",
                              "the first table the server has")
    }

    @Test("a server that can't be asked: nothing is selected")
    func unreachable() async {
        struct Down: Error {}
        let found = await SQLTableReferences.locate([Reference(database: nil, table: "orders")], current: "shop",
                                                    databases: { throw Down() }, tables: { _ in throw Down() })
        #expect(found == nil)
    }

    @Test("SQL from a terminal is queued to find its table; a saved query isn't")
    func queued() {
        let manager = DatabaseSessionManager(loadImmediately: false, defaults: UserDefaults(suiteName: "SQLTableReferencesTests.\(UUID())")!)
        let connection = UUID()
        manager.queueQuery(name: "Query", sql: "SELECT * FROM orders", for: connection, findsTable: true)
        manager.queueQuery(name: "Saved", sql: "SELECT 1", for: connection)
        let taken = manager.takePendingQueries(for: connection)
        #expect(taken.map(\.findsTable) == [true, false])
    }
}
