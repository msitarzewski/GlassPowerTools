//
//  GridServerQueryBuilderTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `GridServerQueryBuilder` (`TableDetailView.swift:643`) assembles every statement the data grid
//  sends: the paged SELECT, its COUNT, and the grouped aggregate pair. It came across from glassdb
//  with the rest of `TableDetailView` and had no direct tests — it was reached only through
//  `LiveDatabaseIntegrationTests`, which need a real server and assert on rows that came back.
//  Tests shaped like that can only observe the queries that *succeed*; the refusals below have
//  never been exercised by anything.
//
//  **Why the refusals are the security surface.** Filter values are bound parameters and column
//  identifiers are quoted, so the builder has no string concatenation of user text — except that
//  the column *name* in a `GridColumnFilter` is itself persisted user-adjacent data
//  (`GridQueryState` is `Codable` and saved per connection/database/table), and the only thing
//  keeping it out of the `WHERE` clause is `validNames.contains`. Delete that guard and the quoted
//  name is still concatenated into SQL — quoting a name that ends the quote correctly is not the
//  same as refusing a name that was never a column. `GridQueryState.reconcile` filters the same
//  set, but it runs on load, not on build, and it is a different line of code; the builder is the
//  one that holds the string.
//
//  So each refusal is asserted by the column it names, not merely that something threw. The
//  builder's errors surface to the user, and "‘Sort’ must contain existing table columns" and
//  "‘shipped_at’ must contain an existing table column" are different sentences about different
//  problems.
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Grid server query builder")
struct GridServerQueryBuilderTests {
    private let columns = [
        ColumnInfo(name: "id", type: "int", isPrimaryKey: true),
        ColumnInfo(name: "email", type: "varchar(255)"),
        ColumnInfo(name: "total", type: "decimal(10,2)"),
        ColumnInfo(name: "note", type: "text")
    ]

    private func filter(
        _ column: String,
        _ operation: GridFilterOperator,
        _ value: String = "",
        type: String = "varchar(255)"
    ) -> GridColumnFilter {
        GridColumnFilter(columnName: column, columnType: type, operation: operation, value: value)
    }

    private func select(
        columns: [ColumnInfo]? = nil,
        filters: [GridColumnFilter] = [],
        sorts: [GridSortDescriptor] = [],
        page: Int = 1,
        pageSize: Int = 100,
        quote: Character = "`",
        dialect: DatabaseDialect = .mysql,
        fetchSentinel: Bool = false,
        database: String = "shop",
        table: String = "orders"
    ) throws -> GridServerQuery {
        try GridServerQueryBuilder.select(
            database: database,
            table: table,
            columns: columns ?? self.columns,
            filters: filters,
            sorts: sorts,
            page: page,
            pageSize: pageSize,
            identifierQuote: quote,
            dialect: dialect,
            fetchSentinel: fetchSentinel
        )
    }

    /// The column a `RecordValueError.invalidValue` names, or nil when the call returned a query.
    private func refusedColumn(_ body: () throws -> GridServerQuery) -> String? {
        do {
            _ = try body()
            return nil
        } catch RecordValueError.invalidValue(let column, _) {
            return column
        } catch {
            Issue.record("expected RecordValueError.invalidValue, got \(error)")
            return nil
        }
    }

    // MARK: - A name that is not a column never reaches the SQL

    /// The guard, stated as the property it exists for: whatever the saved filter claims its
    /// column is, if the live table has no such column no statement is produced at all.
    @Test("A filter naming a column the table does not have is refused, not quoted")
    func unknownFilterColumnIsRefused() {
        let hostile = [
            "shipped_at",
            "id`, (SELECT password FROM users) AS x, `id",
            "1=1 OR ",
            "*",
            "",
            "ID",  // case matters: the server's column is `id`
        ]

        for name in hostile {
            #expect(refusedColumn { try select(filters: [filter(name, .equals, "1")]) } == name,
                    "‘\(name)’ was accepted as a column")
            #expect(refusedColumn {
                try GridServerQueryBuilder.count(
                    database: "shop",
                    table: "orders",
                    columns: columns,
                    filters: [filter(name, .isNull)],
                    identifierQuote: "`"
                )
            } == name, "the COUNT path has its own call and must refuse the same name")
        }
    }

    @Test("A sort naming a column the table does not have is refused")
    func unknownSortColumnIsRefused() {
        #expect(refusedColumn {
            try select(sorts: [GridSortDescriptor(columnName: "shipped_at", direction: .ascending)])
        } == "Sort")

        #expect(refusedColumn {
            try select(sorts: [
                GridSortDescriptor(columnName: "id", direction: .ascending),
                GridSortDescriptor(columnName: "nope", direction: .descending)
            ])
        } == "Sort", "one bad descriptor refuses the whole clause")
    }

    @Test("A filter value that is not valid for its column is refused rather than bound")
    func malformedFilterValueIsRefused() {
        #expect(refusedColumn {
            try select(filters: [filter("id", .equals, "not a number", type: "int")])
        } == "id")
    }

    // MARK: - Aggregates

    @Test("Group and aggregate columns must exist, and groups must be unique")
    func aggregateRefusals() {
        func aggregate(
            group: [String],
            aggregates: [GridAggregateDescriptor]
        ) throws -> GridServerQuery {
            try GridServerQueryBuilder.aggregate(
                database: "shop",
                table: "orders",
                columns: columns,
                filters: [],
                groupColumns: group,
                aggregates: aggregates,
                page: 1,
                pageSize: 100,
                identifierQuote: "`"
            )
        }
        let countAll = GridAggregateDescriptor(function: .countAll, columnName: nil)

        #expect(refusedColumn { try aggregate(group: [], aggregates: []) } == "Aggregate",
                "an aggregate query with nothing to aggregate is refused")
        #expect(refusedColumn { try aggregate(group: ["shipped_at"], aggregates: [countAll]) } == "Group")
        #expect(refusedColumn { try aggregate(group: ["id", "id"], aggregates: [countAll]) } == "Group",
                "a repeated GROUP BY column is a mistake, not a query")
        #expect(refusedColumn {
            try aggregate(group: [], aggregates: [GridAggregateDescriptor(function: .countAll, columnName: "id")])
        } == "Count All", "COUNT(*) takes no column")
        #expect(refusedColumn {
            try aggregate(group: [], aggregates: [GridAggregateDescriptor(function: .sum, columnName: "shipped_at")])
        } == "shipped_at")
        #expect(refusedColumn {
            try aggregate(group: [], aggregates: [GridAggregateDescriptor(function: .sum, columnName: "email")])
        } == "email", "SUM of a varchar is refused before the server has to decide what it means")
        #expect(refusedColumn {
            try aggregate(group: [], aggregates: [GridAggregateDescriptor(function: .average, columnName: "note")])
        } == "note")
    }

    @Test("MIN and MAX are allowed on non-numeric columns")
    func minAndMaxAreNotNumericOnly() throws {
        for function in [GridAggregateFunction.minimum, .maximum, .count] {
            let query = try GridServerQueryBuilder.aggregate(
                database: "shop",
                table: "orders",
                columns: columns,
                filters: [],
                groupColumns: [],
                aggregates: [GridAggregateDescriptor(function: function, columnName: "email")],
                page: 1,
                pageSize: 100,
                identifierQuote: "`"
            )
            #expect(query.sql.contains("\(function.sqlName)(`email`)"))
        }
    }

    @Test("A grouped aggregate selects, groups and orders by the same quoted columns")
    func aggregateShape() throws {
        let query = try GridServerQueryBuilder.aggregate(
            database: "shop",
            table: "orders",
            columns: columns,
            filters: [],
            groupColumns: ["email"],
            aggregates: [
                GridAggregateDescriptor(function: .countAll, columnName: nil),
                GridAggregateDescriptor(function: .sum, columnName: "total")
            ],
            page: 1,
            pageSize: 100,
            identifierQuote: "`"
        )

        #expect(query.sql == "SELECT `email`, COUNT(*) AS `glassdb_1_countAll`, SUM(`total`) AS `glassdb_2_sum` "
                + "FROM `shop`.`orders` GROUP BY `email` ORDER BY `email` ASC LIMIT 100 OFFSET 0")
    }

    /// Without a GROUP BY there is exactly one aggregate row, so the count is a constant rather
    /// than a second trip to the server — but the selection is still validated first, which is why
    /// a bad aggregate is refused even on the path that discards it.
    @Test("An ungrouped aggregate count is a constant, and still validates its aggregates")
    func aggregateCountWithoutGrouping() throws {
        let query = try GridServerQueryBuilder.aggregateCount(
            database: "shop",
            table: "orders",
            columns: columns,
            filters: [],
            groupColumns: [],
            aggregates: [GridAggregateDescriptor(function: .countAll, columnName: nil)],
            identifierQuote: "`"
        )
        #expect(query.sql == "SELECT 1")
        #expect(query.parameters.isEmpty)

        #expect(refusedColumn {
            try GridServerQueryBuilder.aggregateCount(
                database: "shop",
                table: "orders",
                columns: columns,
                filters: [],
                groupColumns: [],
                aggregates: [GridAggregateDescriptor(function: .sum, columnName: "shipped_at")],
                identifierQuote: "`"
            )
        } == "shipped_at")
    }

    @Test("A grouped aggregate count wraps the grouping in a subquery")
    func aggregateCountWithGrouping() throws {
        let query = try GridServerQueryBuilder.aggregateCount(
            database: "shop",
            table: "orders",
            columns: columns,
            filters: [filter("email", .isNotNull)],
            groupColumns: ["email"],
            aggregates: [GridAggregateDescriptor(function: .countAll, columnName: nil)],
            identifierQuote: "`"
        )

        #expect(query.sql == "SELECT COUNT(*) FROM (SELECT 1 FROM `shop`.`orders` WHERE `email` IS NOT NULL "
                + "GROUP BY `email`) AS `glassdb_group_count`")
    }

    // MARK: - Identifier quoting

    /// The delimiter is doubled, which is how both MySQL and PostgreSQL spell an escaped quote
    /// inside a quoted identifier. A column really can be named ``a`b`` — this is not a
    /// hypothetical, and the guard above does not help, because such a column *does* exist.
    @Test("A quote character inside an identifier is doubled, per dialect")
    func identifierQuotingDoublesTheDelimiter() throws {
        let backticked = [ColumnInfo(name: "we`ird", type: "varchar(255)")]
        let mysql = try select(
            columns: backticked,
            sorts: [GridSortDescriptor(columnName: "we`ird", direction: .ascending)],
            quote: "`",
            dialect: .mysql
        )
        #expect(mysql.sql.contains("ORDER BY `we``ird` ASC"))

        let quoted = [ColumnInfo(name: "we\"ird", type: "varchar(255)")]
        let postgres = try select(
            columns: quoted,
            sorts: [GridSortDescriptor(columnName: "we\"ird", direction: .descending)],
            quote: "\"",
            dialect: .postgresql
        )
        #expect(postgres.sql.contains("ORDER BY \"we\"\"ird\" DESC"))
    }

    @Test("Database and table names are quoted the same way")
    func databaseAndTableAreQuoted() throws {
        let query = try select(database: "sh`op", table: "or`ders")

        #expect(query.sql.hasPrefix("SELECT * FROM `sh``op`.`or``ders`"))
    }

    // MARK: - Placeholders and parameters

    /// PostgreSQL numbers its placeholders and MySQL/SQLite do not, so the two dialects produce
    /// different SQL for the same filters. The numbering is positional: `$n` must agree with the
    /// index of the value in `parameters`, or the server binds the wrong value to the wrong column.
    @Test("Placeholders are numbered on PostgreSQL and anonymous elsewhere")
    func placeholdersFollowTheDialect() throws {
        let filters = [
            filter("email", .equals, "a@b.c"),
            filter("id", .greaterThan, "7", type: "int"),
            filter("note", .notEquals, "x", type: "text")
        ]

        let postgres = try select(filters: filters, quote: "\"", dialect: .postgresql)
        #expect(postgres.sql.contains(
            #"WHERE "email" = $1 AND "id" > $2 AND "note" <> $3"#
        ))
        #expect(postgres.parameters == [.string("a@b.c"), .int(7), .string("x")],
                "the values must be in the order the $n numbering claims")

        for dialect in [DatabaseDialect.mysql, .sqlite] {
            let other = try select(filters: filters, dialect: dialect)
            #expect(other.sql.contains("WHERE `email` = ? AND `id` > ? AND `note` <> ?"))
            #expect(!other.sql.contains("$1"), "\(dialect) has no numbered placeholders")
            #expect(other.parameters == [.string("a@b.c"), .int(7), .string("x")])
        }
    }

    /// `IS NULL` takes no value, so it must not consume a placeholder number. If it did, every
    /// `$n` after it would be off by one and the filters would silently apply to the wrong values.
    @Test("Null tests take no parameter and do not advance the numbering")
    func nullTestsDoNotConsumePlaceholders() throws {
        let query = try select(
            filters: [
                filter("email", .isNull),
                filter("id", .equals, "1", type: "int"),
                filter("note", .isNotNull),
                filter("total", .lessThan, "9.50", type: "decimal(10,2)")
            ],
            quote: "\"",
            dialect: .postgresql
        )

        #expect(query.sql.contains(
            #"WHERE "email" IS NULL AND "id" = $1 AND "note" IS NOT NULL AND "total" < $2"#
        ))
        #expect(query.parameters == [.int(1), .decimal("9.50")])
    }

    /// The reason the builder is not a SQL-injection surface: the user's text is never in the SQL.
    @Test("A filter's text is bound, never concatenated")
    func filterTextIsAlwaysBound() throws {
        let payload = "'; DROP TABLE users; --"
        let query = try select(filters: [filter("email", .equals, payload)])

        #expect(!query.sql.contains("DROP"))
        #expect(!query.sql.contains("'"))
        #expect(query.parameters == [.string(payload)])
    }

    @Test("No filters means no WHERE clause and no parameters")
    func noFiltersMeansNoPredicate() throws {
        let query = try select()

        #expect(!query.sql.contains("WHERE"))
        #expect(query.parameters.isEmpty)
    }

    // MARK: - Paging

    @Test("Page size and page number are bounded before they reach LIMIT and OFFSET")
    func pagingIsBounded() throws {
        #expect(try select(page: 1, pageSize: 100).sql.hasSuffix("LIMIT 100 OFFSET 0"))
        #expect(try select(page: 3, pageSize: 50).sql.hasSuffix("LIMIT 50 OFFSET 100"))
        #expect(try select(page: 0, pageSize: 50).sql.hasSuffix("LIMIT 50 OFFSET 0"))
        #expect(try select(page: -7, pageSize: 50).sql.hasSuffix("LIMIT 50 OFFSET 0"))
        #expect(try select(page: 1, pageSize: 0).sql.hasSuffix("LIMIT 1 OFFSET 0"),
                "a zero page size would otherwise mean LIMIT 0")
        #expect(try select(page: 1, pageSize: 5_000_000).sql.hasSuffix("LIMIT 10000 OFFSET 0"),
                "the ceiling is what keeps a saved page size from pulling a whole table")
        #expect(try select(page: 2, pageSize: 5_000_000).sql.hasSuffix("LIMIT 10000 OFFSET 10000"),
                "the offset uses the bounded size, so pages stay contiguous")
    }

    /// One extra row is fetched to learn whether a next page exists; `GridPageWindow.bounded`
    /// removes it again. The sentinel must widen only the LIMIT, never the OFFSET.
    @Test("The next-page sentinel adds one row to the limit only")
    func sentinelWidensTheLimit() throws {
        #expect(try select(page: 2, pageSize: 100, fetchSentinel: true).sql
            .hasSuffix("LIMIT 101 OFFSET 100"))
        #expect(try select(page: 1, pageSize: 10_000, fetchSentinel: true).sql
            .hasSuffix("LIMIT 10001 OFFSET 0"))
    }

    // MARK: - Whole statements

    @Test("A filtered, sorted page is one statement with its parameters")
    func selectShape() throws {
        let query = try select(
            filters: [filter("email", .equals, "a@b.c")],
            sorts: [
                GridSortDescriptor(columnName: "total", direction: .descending),
                GridSortDescriptor(columnName: "id", direction: .ascending)
            ],
            page: 2,
            pageSize: 25
        )

        #expect(query.sql == "SELECT * FROM `shop`.`orders` WHERE `email` = ? "
                + "ORDER BY `total` DESC, `id` ASC LIMIT 25 OFFSET 25")
        #expect(query.parameters == [.string("a@b.c")])
    }

    @Test("The count statement carries the same predicate and parameters as the page")
    func countMatchesTheSelect() throws {
        let filters = [filter("email", .equals, "a@b.c"), filter("id", .greaterThan, "3", type: "int")]
        let page = try select(filters: filters)
        let count = try GridServerQueryBuilder.count(
            database: "shop",
            table: "orders",
            columns: columns,
            filters: filters,
            identifierQuote: "`"
        )

        #expect(count.sql == "SELECT COUNT(*) FROM `shop`.`orders` WHERE `email` = ? AND `id` > ?")
        #expect(count.parameters == page.parameters,
                "a count over a different predicate would page the grid to rows it cannot show")
        #expect(!count.sql.contains("LIMIT"))
    }
}
