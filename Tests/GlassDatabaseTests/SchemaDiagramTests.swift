//
//  SchemaDiagramTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The schema diagram (D43): what the loader reads from a real SQLite schema, and where the layout
//  puts the cards.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Schema diagram")
struct SchemaDiagramTests {

    /// A shop, plus the awkward cases: a composite key, a self-reference, a key to an implicit
    /// primary key, and a table with no keys at all.
    private static let schema = """
        CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, referred_by INTEGER REFERENCES customers(id));
        CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL REFERENCES customers);
        CREATE TABLE order_items (order_id INTEGER NOT NULL REFERENCES orders(id),
                                  product_id INTEGER NOT NULL REFERENCES products(id),
                                  quantity INTEGER, PRIMARY KEY (order_id, product_id));
        CREATE TABLE shipments (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER,
                                FOREIGN KEY (order_id, product_id) REFERENCES order_items(order_id, product_id));
        CREATE TABLE settings (key TEXT, value TEXT);
        """

    private func loadShop() async throws -> SchemaDiagram {
        let connection = try await SQLiteEngine().connect(path: ":memory:")
        for statement in Self.schema.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !statement.isEmpty {
            _ = try await connection.execute(statement)
        }
        return try await SchemaDiagramLoader.load(connection: connection, database: "main")
    }

    @Test("every table and every key is read, composite keys as one relationship")
    func loadsTheShop() async throws {
        let diagram = try await loadShop()
        #expect(diagram.tables.map(\.name) == ["customers", "order_items", "orders", "products", "settings", "shipments"])
        let pairs = Set(diagram.relationships.map { "\($0.fromTable)→\($0.toTable)" })
        #expect(pairs == ["customers→customers", "orders→customers", "order_items→orders",
                          "order_items→products", "shipments→order_items"])
        let composite = try #require(diagram.relationships.first { $0.fromTable == "shipments" })
        #expect(composite.fromColumns == ["order_id", "product_id"])
        #expect(composite.toColumns == ["order_id", "product_id"])
        #expect(diagram.unresolvedRelationshipCount == 0 && diagram.omittedTableCount == 0)
    }

    @Test("a key to an implicit primary key names the primary key's column")
    func implicitPrimaryKey() async throws {
        let diagram = try await loadShop()
        let key = try #require(diagram.relationships.first { $0.fromTable == "orders" })
        #expect(key.toColumns == ["id"], "got \(key.toColumns)")
    }

    @Test("columns carry their key marks, in table order")
    func keyMarks() async throws {
        let diagram = try await loadShop()
        let items = try #require(diagram.table(named: "order_items"))
        #expect(items.columns.map(\.name) == ["order_id", "product_id", "quantity"])
        #expect(items.columns.map(\.isPrimaryKey) == [true, true, false])
        #expect(items.columns.map(\.isForeignKey) == [true, true, false])
        #expect(items.keyColumns.map(\.name) == ["order_id", "product_id"])
        #expect(diagram.table(named: "settings")?.keyColumns.isEmpty == true)
        #expect(diagram.relationships.contains { $0.isSelfReference && $0.fromTable == "customers" })
        #expect(diagram.neighbors(of: "orders") == ["customers", "order_items"])
    }

    @Test("a key to a table outside the diagram is counted, not drawn")
    func unresolvedKey() {
        let diagram = SchemaDiagramLoader.assemble(
            database: "main", tableNames: ["a"],
            columns: ["a": []],
            foreignKeys: ["a": [ForeignKeyInfo(constraintName: "fk", columnName: "b_id",
                                               referencedTable: "b", referencedColumn: "id", ordinalPosition: 1)]])
        #expect(diagram.relationships.isEmpty)
        #expect(diagram.unresolvedRelationshipCount == 1)
    }

    // MARK: - Layout

    private func nodes(_ names: [String]) -> [SchemaDiagramLayout.Node] {
        names.map { .init(id: $0, size: SIMD3(240, 40 + Double($0.count) * 12, 20)) }
    }

    private let shopEdges = [("orders", "customers"), ("order_items", "orders"), ("order_items", "products"),
                             ("shipments", "order_items"), ("reviews", "products"), ("reviews", "customers")]
    private let shopNames = ["customers", "orders", "order_items", "products", "shipments", "reviews",
                             "settings", "audit_log", "migrations"]

    @Test("the same schema lays out the same way every time", arguments: [SchemaDiagramLayout.Space.plane, .volume])
    func deterministic(space: SchemaDiagramLayout.Space) {
        let first = SchemaDiagramLayout.layout(nodes: nodes(shopNames), edges: shopEdges, space: space, gap: 40)
        let second = SchemaDiagramLayout.layout(nodes: nodes(shopNames.reversed()), edges: shopEdges, space: space, gap: 40)
        #expect(first == second)
    }

    @Test("no two cards overlap on the plane; in the volume, no two centres crowd", arguments: [SchemaDiagramLayout.Space.plane, .volume])
    func noOverlap(space: SchemaDiagramLayout.Space) {
        let many = (0..<60).map { "t\($0)" }
        let edges = (1..<60).map { ("t\($0)", "t\(($0 * 7 + 3) % $0)") }
        let all = nodes(many)
        let placed = SchemaDiagramLayout.layout(nodes: all, edges: edges, space: space, gap: 30)
        for a in all.indices {
            for b in all.indices where b > a {
                let p = placed[all[a].id]!, q = placed[all[b].id]!
                let reach = (all[a].size + all[b].size) / 2
                let apart: Bool
                if space == .plane {
                    apart = abs(p.x - q.x) >= reach.x - 0.001 || abs(p.y - q.y) >= reach.y - 0.001
                } else {
                    let d = p - q
                    apart = (d * d).sum().squareRoot() >= max(reach.x, reach.y) * 0.8 - 0.001
                }
                #expect(apart, "\(all[a].id) and \(all[b].id) overlap")
            }
        }
    }

    @Test("the volume is spread in all three directions, not a column")
    func volumeIsNotAColumn() {
        let many = (0..<24).map { "t\($0)" }
        let edges = (1..<24).map { ("t\($0)", "t\(($0 * 7 + 3) % $0)") }
        let placed = SchemaDiagramLayout.layout(nodes: nodes(many), edges: edges, space: .volume, gap: 56)
        let spans = (0..<3).map { axis in placed.values.map { $0[axis] }.max()! - placed.values.map { $0[axis] }.min()! }
        let widest = spans.max()!
        #expect(spans.allSatisfy { $0 > widest * 0.35 }, "spans \(spans.map(Int.init))")
    }

    @Test("related tables sit nearer each other than unrelated ones, on average")
    func relatedAreNear() {
        let placed = SchemaDiagramLayout.layout(nodes: nodes(shopNames), edges: shopEdges, space: .plane, gap: 40)
        func distance(_ a: String, _ b: String) -> Double {
            let d = placed[a]! - placed[b]!; return (d * d).sum().squareRoot()
        }
        let linked = shopEdges.map { distance($0.0, $0.1) }
        let connected = Set(shopEdges.flatMap { [$0.0, $0.1] }).sorted()
        let related = Set(shopEdges.map { [$0.0, $0.1].sorted().joined(separator: "|") })
        var unlinked: [Double] = []
        for a in connected.indices {
            for b in connected.indices where b > a {
                guard !related.contains([connected[a], connected[b]].sorted().joined(separator: "|")) else { continue }
                unlinked.append(distance(connected[a], connected[b]))
            }
        }
        let mean = { (values: [Double]) in values.reduce(0, +) / Double(values.count) }
        #expect(mean(linked) < mean(unlinked))
    }

    @Test("tables with no keys are set out in rows below the rest, on the plane")
    func isolatedInRows() {
        let placed = SchemaDiagramLayout.layout(nodes: nodes(shopNames), edges: shopEdges, space: .plane, gap: 40)
        let lowestLinked = ["customers", "orders", "order_items", "products", "shipments", "reviews"]
            .map { placed[$0]!.y }.max()!
        for name in ["settings", "audit_log", "migrations"] {
            #expect(placed[name]!.y > lowestLinked)
        }
        let minX = placed.values.map(\.x).min()!, minY = placed.values.map(\.y).min()!
        #expect(minX >= 0 && minY >= 0, "the plane's layout starts at the top-left")
    }
}
