//
//  TableDetailView.swift
//  glassdb
//
//  Context-sensitive detail surface for a selected table.
//  TabView with Data, Structure, DDL, Indexes, Foreign Keys tabs.
//

import SwiftUI
import GlassShell
import UniformTypeIdentifiers
import GlassDBKit
import GlassEditorUI
import GlassLayers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension DatabaseValue {
    /// Presentation only: never infer numeric types from textual identifiers.
    var usesNumericGridAlignment: Bool {
        switch self {
        case .int, .uint, .decimal, .double: true
        default: false
        }
    }
}

struct TableDetailView: View {
    let sessionID: UUID
    let database: String
    let table: String
    var isWorkspaceActive = true
    var onOpenSQLEditor: (() -> Void)?
    var sqlDraft: Binding<QueryDocumentTab>?

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab: TableTab = .data
    @State private var actionScope = UUID()
    @State private var runAvailability = SQLRunAvailability()
    #if os(macOS) || os(iOS)
    @State private var visitedTabs: Set<TableTab> = [.data]
    #endif

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    var body: some View {
        Group {
            #if os(macOS)
            macOSContent
            #elseif os(iOS)
            iOSContent
            #else
            spatialContent
            #endif
        }
        .onPreferenceChange(SQLRunAvailabilityKey.self) { runAvailability = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbOpenTable)) { notification in
            // Following a reference lands on rows, so show them: a table opened this way while the
            // user was on Structure or Foreign Keys would otherwise apply its filter out of sight.
            guard let request = notification.object as? OpenTableRequest,
                  request.sessionID == sessionID,
                  request.database == database,
                  request.table == table else { return }
            selectedTab = .data
        }
        .glassActiveConnectionsLastInToolbar(isActive: isWorkspaceActive)
        .toolbar {
            if isWorkspaceActive {
                #if os(macOS)
                ToolbarSpacer(.flexible, placement: databaseContextToolbarPlacement)
                #endif

                if selectedTab == .data {
                    ToolbarItemGroup(placement: databaseTransferToolbarPlacement) {
                        Button {
                            NotificationCenter.default.post(
                                name: .glassdbTransfer,
                                object: GridTransferRequest(scope: actionScope, operation: .importTSV)
                            )
                        } label: {
                            Label("Import TSV", systemImage: "square.and.arrow.down")
                        }
                        .help("Import tab-separated values")

                        exportMenu
                    }
                }

                #if os(macOS)
                if selectedTab == .data {
                    ToolbarSpacer(.fixed, placement: databaseContextToolbarPlacement)
                }
                ToolbarItemGroup(placement: databaseContextToolbarPlacement) {
                    ForEach(TableTab.allCases) { tab in
                        Toggle(isOn: tableTabSelection(for: tab)) {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                        .toggleStyle(.button)
                        .labelStyle(.iconOnly)
                        .help(tab.helpText)
                        .accessibilityLabel(tab.title)
                        .accessibilityHint(tab.helpText)
                        .accessibilityIdentifier(tab.accessibilityIdentifier)
                    }
                }
                ToolbarSpacer(.fixed, placement: databaseToolbarPlacement)
                DatabasePersistentToolbar {
                    onOpenSQLEditor?()
                }
                #elseif os(iOS)
                ToolbarItem(placement: databaseContextToolbarPlacement) {
                    Menu {
                        Picker("Table View", selection: $selectedTab) {
                            ForEach(TableTab.allCases) { tab in
                                Label(tab.title, systemImage: tab.systemImage)
                                    .tag(tab)
                                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                            }
                        }
                    } label: {
                        Label(selectedTab.title, systemImage: selectedTab.systemImage)
                    }
                    .help("Choose table data, structure, DDL, indexes, or foreign keys")
                    .accessibilityLabel("Table view: \(selectedTab.title)")
                }
                #endif

                ToolbarItemGroup(placement: databaseExecutionToolbarPlacement) {
                    if selectedTab == .data {
                        #if canImport(FoundationModels)
                        Button {
                            NotificationCenter.default.post(name: .glassdbShowAI, object: actionScope)
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .help("Ask the on-device assistant about this table")
                        #endif

                        SQLRunControl(availability: runAvailability) { mode in
                            NotificationCenter.default.post(name: .glassdbExecuteQuery, object: actionScope,
                                                            userInfo: ["mode": mode.rawValue])
                        }
                        .contextMenu {
                            Button("Run every 10s") {
                                NotificationCenter.default.post(name: .glassdbStartRepeat, object: actionScope)
                            }
                        }
                    }
                }
                .glassKeepVisibleWhenCompact()

                ToolbarItemGroup(placement: databaseToolbarPlacement) {
                    if selectedTab == .data {
                        Button {
                            NotificationCenter.default.post(name: .glassdbAddRow, object: actionScope)
                        } label: {
                            Label("Add Row", systemImage: "plus")
                        }
                        .help("Stage a new row")
                        Button {
                            NotificationCenter.default.post(name: .glassdbRefreshData, object: actionScope)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Reload table data")
                    }
                }
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            ForEach(GridExportFormat.allCases) { format in
                Button(format.displayName) {
                    NotificationCenter.default.post(
                        name: .glassdbTransfer,
                        object: GridTransferRequest(scope: actionScope, operation: .export(format))
                    )
                }
                .help("Export table data as \(format.displayName)")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuIndicator(.hidden)
        .help("Export table data")
    }

    private func tableTabSelection(for tab: TableTab) -> Binding<Bool> {
        Binding(
            get: { selectedTab == tab },
            set: { isSelected in
                if isSelected { selectedTab = tab }
            }
        )
    }

    #if os(macOS)
    private var macOSContent: some View {
        ZStack {
            ForEach(TableTab.allCases.filter(visitedTabs.contains)) { tab in
                let isActive = selectedTab == tab
                tableContent(for: tab, isActive: isWorkspaceActive && isActive)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                    .zIndex(isActive ? 1 : 0)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
        }
    }
    #endif

    #if os(iOS)
    private var iOSContent: some View {
        ZStack {
            ForEach(TableTab.allCases.filter(visitedTabs.contains)) { tab in
                let isActive = selectedTab == tab
                tableContent(for: tab, isActive: isWorkspaceActive && isActive)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
                    .zIndex(isActive ? 1 : 0)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
        }
    }
    #endif

    #if !os(macOS)
    private var spatialContent: some View {
        TabView(selection: $selectedTab) {
            Tab("Data", systemImage: "tablecells", value: .data) {
                tableContent(for: .data, isActive: isWorkspaceActive && selectedTab == .data)
            }
            Tab("Structure", systemImage: "list.bullet.rectangle", value: .structure) {
                tableContent(for: .structure, isActive: selectedTab == .structure)
            }
            Tab("DDL", systemImage: "curlybraces", value: .ddl) {
                tableContent(for: .ddl, isActive: selectedTab == .ddl)
            }
            Tab("Indexes", systemImage: "arrow.triangle.branch", value: .indexes) {
                tableContent(for: .indexes, isActive: selectedTab == .indexes)
            }
            Tab("Foreign Keys", systemImage: "arrow.triangle.turn.up.right.diamond", value: .foreignKeys) {
                tableContent(for: .foreignKeys, isActive: selectedTab == .foreignKeys)
            }
        }
    }
    #endif

    @ViewBuilder
    private func tableContent(for tab: TableTab, isActive: Bool) -> some View {
        switch tab {
        case .data:
            DataTabView(
                sessionID: sessionID,
                database: database,
                table: table,
                actionScope: actionScope,
                isWorkspaceActive: isActive,
                tableDraft: sqlDraft
            )
        case .structure:
            StructureTabView(
                sessionID: sessionID,
                database: database,
                table: table,
                onOpenSQL: onOpenSQLEditor
            )
        case .ddl:
            DDLTabView(
                sessionID: sessionID,
                database: database,
                table: table,
                onOpenSQL: onOpenSQLEditor
            )
        case .indexes:
            IndexesTabView(sessionID: sessionID, database: database, table: table)
        case .foreignKeys:
            ForeignKeysTabView(sessionID: sessionID, database: database, table: table)
        }
    }
}

private struct GridTransferRequest {
    let scope: UUID
    let operation: Operation

    enum Operation {
        case importTSV
        case export(GridExportFormat)
    }
}

extension Notification.Name {
    static let glassdbExecuteQuery = Notification.Name("glassdbExecuteQuery")
    static let glassdbAddRow = Notification.Name("glassdbAddRow")
    static let glassdbRefreshData = Notification.Name("glassdbRefreshData")
    static let glassdbShowAI = Notification.Name("glassdbShowAI")
    static let glassdbStartRepeat = Notification.Name("glassdbStartRepeat")
    static let glassdbTransfer = Notification.Name("glassdbTransfer")
    static let glassdbOpenSQLDraft = Notification.Name("glassdbOpenSQLDraft")
    /// Posted when one table wants another opened — today only by foreign-key navigation.
    /// Observed by the workspace, which owns the tab strip; the same seam `glassdbOpenSQLDraft`
    /// already uses, so a detail view still does not reach into navigation itself.
    static let glassdbOpenTable = Notification.Name("glassdbOpenTable")
}

struct OpenTableRequest: Sendable {
    let sessionID: UUID
    let database: String
    let table: String
}

struct SQLDraftRequest: Sendable {
    let sessionID: UUID
    let sql: String
}

// MARK: - Tab Enum

enum TableTab: Hashable, CaseIterable, Identifiable {
    case data, structure, ddl, indexes, foreignKeys

    var id: Self { self }

    var title: String {
        switch self {
        case .data: "Data"
        case .structure: "Structure"
        case .ddl: "DDL"
        case .indexes: "Indexes"
        case .foreignKeys: "Foreign Keys"
        }
    }

    var systemImage: String {
        switch self {
        case .data: "tablecells"
        case .structure: "list.bullet.rectangle"
        case .ddl: "curlybraces"
        case .indexes: "arrow.triangle.branch"
        case .foreignKeys: "link"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .data: "db-tab-data"
        case .structure: "db-tab-structure"
        case .ddl: "db-tab-ddl"
        case .indexes: "db-tab-indexes"
        case .foreignKeys: "db-tab-foreign-keys"
        }
    }

    var helpText: String {
        switch self {
        case .data: "Browse and edit table data"
        case .structure: "Inspect and modify table columns"
        case .ddl: "Review or open the table definition as SQL"
        case .indexes: "Inspect and modify table indexes"
        case .foreignKeys: "Inspect and modify foreign-key relationships"
        }
    }
}

enum GridSortDirection: String, Codable, Sendable {
    case ascending
    case descending

    var sql: String { self == .ascending ? "ASC" : "DESC" }
}

extension View {
    /// Holds a frozen column's cell at its pinned position while the grid scrolls sideways. Only
    /// frozen cells carry the scroll-driven effect: on every cell it was a measured share of the
    /// cost of building a row (tasks/2026-09/2026-09-23_grid-scroll-cost.md).
    @ViewBuilder
    func gridFrozen(_ isFrozen: Bool, leadingOffset: CGFloat, zIndex: Double) -> some View {
        if isFrozen {
            visualEffect { content, proxy in
                content.offset(x: max(0, leadingOffset - proxy.frame(in: .scrollView(axis: .horizontal)).minX))
            }
            .zIndex(zIndex)
        } else {
            self
        }
    }

    /// Select on a click, act on a double-click. Two tap gestures per cell (single and double)
    /// were the largest share of building a row. On the Mac one gesture does both: the event's
    /// click count says which click this is, and the first click of a double-click selecting is
    /// what a Mac list does anyway — without the wait a double-tap gesture puts on every click.
    /// Touch keeps the two gestures.
    @ViewBuilder
    func gridTap(select: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        #if os(macOS)
        onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { open() } else { select() }
        }
        #else
        onTapGesture(count: 2, perform: open)
            .onTapGesture(perform: select)
        #endif
    }
}

/// The rows the grid shows, in order, kept until the result, the filters or the sorts change.
/// Every selection click re-evaluates the grid's body, and re-filtering and re-sorting a whole
/// page per click is work the answer does not need (tasks/2026-09/2026-09-23_grid-scroll-cost.md).
/// A reference held in `@State` and never observed: storing an answer does not re-render.
@MainActor
final class GridDisplayedRowsMemo {
    struct Key: Equatable {
        let result: UUID
        let rowCount: Int
        let filters: [GridColumnFilter]
        let sorts: [GridSortDescriptor]
        let dialect: DatabaseDialect?
        let isAnalysis: Bool
        let isTable: Bool
    }

    private var key: Key?
    private var rows: [Int] = []
    private(set) var computations = 0

    func rows(for key: Key, compute: () -> [Int]) -> [Int] {
        if key == self.key { return rows }
        rows = compute()
        self.key = key
        computations += 1
        return rows
    }
}

struct GridSortDescriptor: Codable, Hashable, Identifiable, Sendable {
    let columnName: String
    var direction: GridSortDirection
    var id: String { columnName }
}

enum GridFilterOperator: String, CaseIterable, Codable, Identifiable, Sendable {
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case isNull
    case isNotNull

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .equals: return "Equals"
        case .notEquals: return "Does Not Equal"
        case .greaterThan: return "Greater Than"
        case .lessThan: return "Less Than"
        case .isNull: return "Is NULL"
        case .isNotNull: return "Is Not NULL"
        }
    }
    var requiresValue: Bool { self != .isNull && self != .isNotNull }
}

struct GridColumnFilter: Codable, Hashable, Identifiable, Sendable {
    let columnName: String
    let columnType: String
    let isUnsigned: Bool
    var operation: GridFilterOperator
    var value: String
    var id: String { columnName }

    init(
        columnName: String,
        columnType: String,
        isUnsigned: Bool = false,
        operation: GridFilterOperator,
        value: String
    ) {
        self.columnName = columnName
        self.columnType = columnType
        self.isUnsigned = isUnsigned
        self.operation = operation
        self.value = value
    }

    /// The filter's text as a bound parameter, validated the same way a record edit is.
    ///
    /// `dialect` is the connection's and is a **parameter rather than a stored property** on
    /// purpose. A saved filter outlives the session that made it, and the engine it will next be
    /// applied against is a fact about the connection, not about the filter — storing it would
    /// persist something that can change and then quietly disagree with reality. It is also why
    /// `GridColumnFilter` stays `Codable` without a migration.
    ///
    /// Passing nil leaves bare `text`/`blob` unconstrained, which is the safe reading: those two
    /// names mean ~1 GB on PostgreSQL and `SQLITE_MAX_LENGTH` on SQLite, so borrowing MySQL's
    /// 65,535 would refuse values that are perfectly storable. A missing limit only fails to warn.
    func boundValue(dialect: DatabaseDialect? = nil) throws -> DatabaseValue? {
        guard operation.requiresValue else { return nil }
        return try StagedEdit(
            columnIndex: 0,
            columnName: columnName,
            columnType: columnType,
            dialect: dialect,
            isPrimaryKey: false,
            isNullable: true,
            isUnsigned: isUnsigned,
            isGenerated: false,
            defaultValue: nil,
            originalValue: .null,
            editText: value,
            isNull: false,
            useDefault: false
        ).boundValue()
    }

    /// Why this filter cannot be applied, or nil when it can.
    ///
    /// Two checks, in order, matching `StagedEdit.validationError` so the type error is reported
    /// before the size one ("abc" in an int says it is not a number, not that it is out of range).
    ///
    /// **The size check runs for `.equals` only, and that limit is deliberate.** A filter is a
    /// read, not a write, so the question is not "will the server store this?" but "can any stored
    /// row match it?". For `=` the answer is provably no: a value too large for the column cannot
    /// be in it, so the query is guaranteed to return nothing and saying so is more useful than
    /// silently returning an empty page. For `<>` the same value matches *every* row, and for `<`
    /// and `>` an out-of-range bound is an ordinary and meaningful way to express "all of them" —
    /// refusing those would block legitimate queries to enforce a rule that does not apply to them.
    ///
    /// Before this, filters ran no size check at all: `varchar(4)` accepted `"12345"` and returned
    /// an empty page with no explanation. `ColumnTypeConstraint` was written to serve both the
    /// record editor and the grid, and only one of the two was calling it.
    func validationError(dialect: DatabaseDialect? = nil) -> String? {
        do {
            _ = try boundValue(dialect: dialect)
        } catch {
            return error.localizedDescription
        }
        guard operation == .equals else { return nil }
        return ColumnTypeConstraint
            .parse(columnType, isUnsigned: isUnsigned, dialect: dialect)?
            .overflowMessage(for: value, column: columnName)
    }
}

enum GridFilterApplicationMode: String, CaseIterable, Identifiable, Sendable, Equatable {
    case updateQuery
    case displayOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updateQuery: "Update SQL Query"
        case .displayOnly: "Display Only"
        }
    }

    var explanation: String {
        switch self {
        case .updateQuery:
            "Adds bound conditions to the generated SELECT and reloads rows from the database."
        case .displayOnly:
            "Hides nonmatching rows from the currently loaded page without changing SQL or contacting the database."
        }
    }
}

enum GridDisplayFilterEvaluator {
    static func matchingRowIndices(
        rows: [[DatabaseValue]],
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        dialect: DatabaseDialect? = nil
    ) -> [Int] {
        guard !filters.isEmpty else { return Array(rows.indices) }
        var columnIndices: [String: Int] = [:]
        for (index, column) in columns.enumerated() where columnIndices[column.name] == nil {
            columnIndices[column.name] = index
        }
        return rows.indices.filter { rowIndex in
            filters.allSatisfy { filter in
                guard let columnIndex = columnIndices[filter.columnName],
                      rows[rowIndex].indices.contains(columnIndex) else { return false }
                return matches(rows[rowIndex][columnIndex], filter: filter, dialect: dialect)
            }
        }
    }

    private static func matches(
        _ value: DatabaseValue,
        filter: GridColumnFilter,
        dialect: DatabaseDialect?
    ) -> Bool {
        switch filter.operation {
        case .isNull:
            return value.isNull
        case .isNotNull:
            return !value.isNull
        case .equals, .notEquals, .greaterThan, .lessThan:
            guard !value.isNull,
                  let comparison = try? filter.boundValue(dialect: dialect) else { return false }
            let ordering = compare(value, comparison)
            switch filter.operation {
            case .equals: return ordering == .orderedSame
            case .notEquals: return ordering != .orderedSame
            case .greaterThan: return ordering == .orderedDescending
            case .lessThan: return ordering == .orderedAscending
            default: return false
            }
        }
    }

    static func compare(_ lhs: DatabaseValue, _ rhs: DatabaseValue?) -> ComparisonResult {
        guard let rhs else { return .orderedDescending }
        if lhs == rhs { return .orderedSame }
        if let leftNumber = decimalValue(lhs), let rightNumber = decimalValue(rhs) {
            if leftNumber == rightNumber { return .orderedSame }
            return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
        }
        return lhs.displayString.compare(rhs.displayString, options: [.literal])
    }

    private static func decimalValue(_ value: DatabaseValue) -> Decimal? {
        switch value {
        case .int(let number): Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
        case .uint(let number): Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
        case .decimal(let number): Decimal(string: number, locale: Locale(identifier: "en_US_POSIX"))
        case .double(let number): Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
        default: nil
        }
    }
}

enum GridDisplaySortEvaluator {
    static func sortedRowIndices(
        rows: [[DatabaseValue]],
        columns: [ColumnInfo],
        rowIndices: [Int],
        sorts: [GridSortDescriptor]
    ) -> [Int] {
        guard !sorts.isEmpty else { return rowIndices }
        var columnIndices: [String: Int] = [:]
        for (index, column) in columns.enumerated() where columnIndices[column.name] == nil {
            columnIndices[column.name] = index
        }
        return rowIndices.sorted { leftIndex, rightIndex in
            for sort in sorts {
                guard let columnIndex = columnIndices[sort.columnName],
                      rows[leftIndex].indices.contains(columnIndex),
                      rows[rightIndex].indices.contains(columnIndex) else { continue }
                let comparison = GridDisplayFilterEvaluator.compare(
                    rows[leftIndex][columnIndex],
                    rows[rightIndex][columnIndex]
                )
                guard comparison != .orderedSame else { continue }
                return sort.direction == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            return leftIndex < rightIndex
        }
    }
}

struct GridServerQuery: Equatable, Sendable {
    let sql: String
    let parameters: [DatabaseValue]
}

enum GridAggregateFunction: String, CaseIterable, Codable, Identifiable, Sendable {
    case countAll
    case count
    case sum
    case average
    case minimum
    case maximum

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .countAll: return "Count All"
        case .count: return "Count"
        case .sum: return "Sum"
        case .average: return "Average"
        case .minimum: return "Minimum"
        case .maximum: return "Maximum"
        }
    }
    var sqlName: String {
        switch self {
        case .countAll, .count: return "COUNT"
        case .sum: return "SUM"
        case .average: return "AVG"
        case .minimum: return "MIN"
        case .maximum: return "MAX"
        }
    }
    var requiresColumn: Bool { self != .countAll }
}

struct GridAggregateDescriptor: Codable, Hashable, Identifiable, Sendable {
    let function: GridAggregateFunction
    let columnName: String?
    var id: String { "\(function.rawValue):\(columnName ?? "*")" }
}

struct GridQueryState: Codable, Equatable, Sendable {
    var filters: [GridColumnFilter] = []
    var sorts: [GridSortDescriptor] = []
    var groupColumns: [String] = []
    var aggregates: [GridAggregateDescriptor] = []
    var pageSize: Int = 100

    mutating func reconcile(columns: [ColumnInfo]) {
        let valid = Set(columns.map(\.name))
        filters = filters.filter { valid.contains($0.columnName) }
        sorts = sorts.filter { valid.contains($0.columnName) }
        groupColumns = groupColumns.filter(valid.contains)
        aggregates = aggregates.filter { descriptor in
            !descriptor.function.requiresColumn || descriptor.columnName.map(valid.contains) == true
        }
        pageSize = max(1, min(pageSize, 10_000))
    }

    static func storageKey(connectionID: UUID, database: String, table: String) -> String {
        let object = Data("\(database)\u{0}\(table)".utf8).base64EncodedString()
        return "app.glassdb.gridQuery.\(connectionID.uuidString.lowercased()).\(object)"
    }
}

enum GridServerQueryBuilder {
    static func select(
        database: String,
        table: String,
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        sorts: [GridSortDescriptor],
        page: Int,
        pageSize: Int,
        identifierQuote: Character,
        dialect: DatabaseDialect = .mysql,
        fetchSentinel: Bool = false
    ) throws -> GridServerQuery {
        let predicate = try predicate(
            columns: columns,
            filters: filters,
            identifierQuote: identifierQuote,
            dialect: dialect
        )
        let order = try orderClause(columns: columns, sorts: sorts, identifierQuote: identifierQuote)
        let boundedSize = max(1, min(pageSize, 10_000))
        let offset = max(0, page - 1) * boundedSize
        let fetchLimit = boundedSize + (fetchSentinel ? 1 : 0)
        let qualified = "\(quote(database, with: identifierQuote)).\(quote(table, with: identifierQuote))"
        return GridServerQuery(
            sql: "SELECT * FROM \(qualified)\(predicate.sql)\(order) LIMIT \(fetchLimit) OFFSET \(offset)",
            parameters: predicate.parameters
        )
    }

    static func count(
        database: String,
        table: String,
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        identifierQuote: Character,
        dialect: DatabaseDialect = .mysql
    ) throws -> GridServerQuery {
        let predicate = try predicate(
            columns: columns,
            filters: filters,
            identifierQuote: identifierQuote,
            dialect: dialect
        )
        let qualified = "\(quote(database, with: identifierQuote)).\(quote(table, with: identifierQuote))"
        return GridServerQuery(
            sql: "SELECT COUNT(*) FROM \(qualified)\(predicate.sql)",
            parameters: predicate.parameters
        )
    }

    static func aggregate(
        database: String,
        table: String,
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        groupColumns: [String],
        aggregates: [GridAggregateDescriptor],
        page: Int,
        pageSize: Int,
        identifierQuote: Character,
        dialect: DatabaseDialect = .mysql,
        fetchSentinel: Bool = false
    ) throws -> GridServerQuery {
        let selection = try aggregateSelection(
            columns: columns,
            groupColumns: groupColumns,
            aggregates: aggregates,
            identifierQuote: identifierQuote
        )
        let predicate = try predicate(
            columns: columns,
            filters: filters,
            identifierQuote: identifierQuote,
            dialect: dialect
        )
        let boundedSize = max(1, min(pageSize, 10_000))
        let offset = max(0, page - 1) * boundedSize
        let fetchLimit = boundedSize + (fetchSentinel ? 1 : 0)
        let qualified = "\(quote(database, with: identifierQuote)).\(quote(table, with: identifierQuote))"
        let grouping = groupColumns.isEmpty ? "" : " GROUP BY " + groupColumns.map {
            quote($0, with: identifierQuote)
        }.joined(separator: ", ")
        let ordering = groupColumns.isEmpty ? "" : " ORDER BY " + groupColumns.map {
            "\(quote($0, with: identifierQuote)) ASC"
        }.joined(separator: ", ")
        return GridServerQuery(
            sql: "SELECT \(selection) FROM \(qualified)\(predicate.sql)\(grouping)\(ordering) LIMIT \(fetchLimit) OFFSET \(offset)",
            parameters: predicate.parameters
        )
    }

    static func aggregateCount(
        database: String,
        table: String,
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        groupColumns: [String],
        aggregates: [GridAggregateDescriptor],
        identifierQuote: Character,
        dialect: DatabaseDialect = .mysql
    ) throws -> GridServerQuery {
        _ = try aggregateSelection(
            columns: columns,
            groupColumns: groupColumns,
            aggregates: aggregates,
            identifierQuote: identifierQuote
        )
        let predicate = try predicate(
            columns: columns,
            filters: filters,
            identifierQuote: identifierQuote,
            dialect: dialect
        )
        let qualified = "\(quote(database, with: identifierQuote)).\(quote(table, with: identifierQuote))"
        guard !groupColumns.isEmpty else {
            return GridServerQuery(sql: "SELECT 1", parameters: [])
        }
        let grouping = groupColumns.map { quote($0, with: identifierQuote) }.joined(separator: ", ")
        return GridServerQuery(
            sql: "SELECT COUNT(*) FROM (SELECT 1 FROM \(qualified)\(predicate.sql) GROUP BY \(grouping)) AS \(quote("glassdb_group_count", with: identifierQuote))",
            parameters: predicate.parameters
        )
    }

    private static func aggregateSelection(
        columns: [ColumnInfo],
        groupColumns: [String],
        aggregates: [GridAggregateDescriptor],
        identifierQuote: Character
    ) throws -> String {
        let validNames = Set(columns.map(\.name))
        guard !aggregates.isEmpty else {
            throw RecordValueError.invalidValue(column: "Aggregate", expected: "at least one aggregate function")
        }
        guard Set(groupColumns).count == groupColumns.count,
              groupColumns.allSatisfy(validNames.contains) else {
            throw RecordValueError.invalidValue(column: "Group", expected: "unique existing table columns")
        }
        var selections = groupColumns.map { quote($0, with: identifierQuote) }
        for (index, descriptor) in aggregates.enumerated() {
            let argument: String
            if descriptor.function == .countAll {
                guard descriptor.columnName == nil else {
                    throw RecordValueError.invalidValue(column: "Count All", expected: "no column")
                }
                argument = "*"
            } else {
                guard let columnName = descriptor.columnName, validNames.contains(columnName) else {
                    throw RecordValueError.invalidValue(column: descriptor.columnName ?? "Aggregate", expected: "an existing table column")
                }
                if descriptor.function == .sum || descriptor.function == .average,
                   let column = columns.first(where: { $0.name == columnName }),
                   !isNumericType(column.type) {
                    throw RecordValueError.invalidValue(column: columnName, expected: "a numeric column for sum or average")
                }
                argument = quote(columnName, with: identifierQuote)
            }
            let alias = "glassdb_\(index + 1)_\(descriptor.function.rawValue)"
            selections.append("\(descriptor.function.sqlName)(\(argument)) AS \(quote(alias, with: identifierQuote))")
        }
        return selections.joined(separator: ", ")
    }

    private static func isNumericType(_ type: String) -> Bool {
        let base = type.lowercased().split(separator: "(", maxSplits: 1).first.map(String.init) ?? type.lowercased()
        return ["tinyint", "smallint", "mediumint", "int", "integer", "bigint", "decimal", "numeric", "float", "double", "real"].contains(base)
    }

    private static func predicate(
        columns: [ColumnInfo],
        filters: [GridColumnFilter],
        identifierQuote: Character,
        dialect: DatabaseDialect
    ) throws -> (sql: String, parameters: [DatabaseValue]) {
        var clauses: [String] = []
        var parameters: [DatabaseValue] = []
        let validNames = Set(columns.map(\.name))
        for filter in filters {
            guard validNames.contains(filter.columnName) else {
                throw RecordValueError.invalidValue(column: filter.columnName, expected: "an existing table column")
            }
            let identifier = quote(filter.columnName, with: identifierQuote)
            switch filter.operation {
            case .isNull: clauses.append("\(identifier) IS NULL")
            case .isNotNull: clauses.append("\(identifier) IS NOT NULL")
            case .equals, .notEquals, .greaterThan, .lessThan:
                guard let value = try filter.boundValue(dialect: dialect) else { continue }
                let operation: String
                switch filter.operation {
                case .equals: operation = "="
                case .notEquals: operation = "<>"
                case .greaterThan: operation = ">"
                case .lessThan: operation = "<"
                default: operation = "="
                }
                parameters.append(value)
                clauses.append("\(identifier) \(operation) \(placeholder(parameters.count, dialect: dialect))")
            }
        }
        return (clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND "), parameters)
    }

    private static func orderClause(
        columns: [ColumnInfo],
        sorts: [GridSortDescriptor],
        identifierQuote: Character
    ) throws -> String {
        guard !sorts.isEmpty else { return "" }
        let validNames = Set(columns.map(\.name))
        guard sorts.allSatisfy({ validNames.contains($0.columnName) }) else {
            throw RecordValueError.invalidValue(column: "Sort", expected: "existing table columns")
        }
        return " ORDER BY " + sorts.map {
            "\(quote($0.columnName, with: identifierQuote)) \($0.direction.sql)"
        }.joined(separator: ", ")
    }

    private static func quote(_ identifier: String, with delimiter: Character) -> String {
        let quote = String(delimiter)
        return quote + identifier.replacingOccurrences(of: quote, with: quote + quote) + quote
    }

    private static func placeholder(_ position: Int, dialect: DatabaseDialect) -> String {
        dialect == .postgresql ? "$\(position)" : "?"
    }
}

struct GridPageWindow {
    let result: QueryResult
    let hasNextPage: Bool

    static func bounded(
        _ rawResult: QueryResult,
        pageSize: Int,
        displayedQuery: String
    ) -> Self {
        let boundedSize = max(1, min(pageSize, 10_000))
        let hasNextPage = rawResult.rows.count > boundedSize
        let visibleRows = Array(rawResult.rows.prefix(boundedSize))
        return Self(
            result: QueryResult(
                id: rawResult.id,
                query: displayedQuery,
                columns: rawResult.columns,
                rows: visibleRows,
                affectedRows: rawResult.affectedRows,
                lastInsertID: rawResult.lastInsertID,
                warningCount: rawResult.warningCount,
                executionTime: rawResult.executionTime,
                timestamp: rawResult.timestamp,
                error: rawResult.error,
                appliedRowLimit: boundedSize,
                isTruncated: hasNextPage
            ),
            hasNextPage: hasNextPage
        )
    }
}

struct GridColumnLayout: Codable, Equatable, Sendable {
    var order: [String] = []
    var hidden: Set<String> = []
    var frozen: Set<String> = []
    var widths: [String: Double] = [:]

    mutating func reconcile(columns: [ColumnInfo]) {
        let names = columns.map(\.name)
        let valid = Set(names)
        order = order.filter(valid.contains)
        var orderedNames = Set(order)
        for name in names where orderedNames.insert(name).inserted {
            order.append(name)
        }
        hidden.formIntersection(valid)
        frozen.formIntersection(valid)
        widths = widths.filter { valid.contains($0.key) }
    }

    func visibleColumnIndices(columns: [ColumnInfo]) -> [Int] {
        let indexByName = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element.name, $0.offset) })
        let visible = order.filter { !hidden.contains($0) }
        return (visible.filter(frozen.contains) + visible.filter { !frozen.contains($0) })
            .compactMap { indexByName[$0] }
    }

    static func storageKey(connectionID: UUID, database: String, table: String) -> String {
        let object = Data("\(database)\u{0}\(table)".utf8).base64EncodedString()
        return "app.glassdb.gridLayout.\(connectionID.uuidString.lowercased()).\(object)"
    }

    static func leadingOffsets(widths: [CGFloat], startingAt initial: CGFloat) -> [CGFloat] {
        var running = initial
        return widths.map { width in
            defer { running += width }
            return running
        }
    }
}

struct GridCellCoordinate: Hashable, Sendable {
    let row: Int
    let column: Int
}

struct GridRowSelectionState: Equatable, Sendable {
    var rows: Set<Int> = []
    var anchor: Int?

    func selecting(
        _ row: Int,
        from displayedRows: [Int],
        extendsSelection: Bool,
        togglesSelection: Bool
    ) -> GridRowSelectionState {
        guard let clickedPosition = displayedRows.firstIndex(of: row) else { return self }
        if extendsSelection,
           let anchor,
           let anchorPosition = displayedRows.firstIndex(of: anchor) {
            let range = min(anchorPosition, clickedPosition)...max(anchorPosition, clickedPosition)
            let rowsInRange = Set(displayedRows[range])
            return GridRowSelectionState(
                rows: togglesSelection ? rows.union(rowsInRange) : rowsInRange,
                anchor: anchor
            )
        }
        if togglesSelection {
            var toggledRows = rows
            if toggledRows.contains(row) {
                toggledRows.remove(row)
            } else {
                toggledRows.insert(row)
            }
            return GridRowSelectionState(rows: toggledRows, anchor: row)
        }
        return GridRowSelectionState(rows: [row], anchor: row)
    }
}

struct GridRowDifference: Equatable, Sendable {
    let columnName: String
    let left: DatabaseValue
    let right: DatabaseValue
}

enum GridRowComparison {
    static func differences(
        result: QueryResult,
        leftRow: Int,
        rightRow: Int,
        columnIndices: [Int]
    ) throws -> [GridRowDifference] {
        guard result.rows.indices.contains(leftRow), result.rows.indices.contains(rightRow), leftRow != rightRow else {
            throw RecordValueError.invalidValue(column: "Compare", expected: "two distinct result rows")
        }
        guard columnIndices.allSatisfy(result.columns.indices.contains) else {
            throw RecordValueError.invalidValue(column: "Compare", expected: "existing result columns")
        }
        return columnIndices.compactMap { index in
            let left = index < result.rows[leftRow].count ? result.rows[leftRow][index] : .null
            let right = index < result.rows[rightRow].count ? result.rows[rightRow][index] : .null
            return left == right ? nil : GridRowDifference(
                columnName: result.columns[index].name,
                left: left,
                right: right
            )
        }
    }
}

enum GridPasteMappingMode: String, Codable, Sendable {
    case positional
    case headerRow
}

enum GridImportPolicy {
    static let maximumBytes = 10 * 1_024 * 1_024

    static func validate(byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumBytes else {
            throw RecordValueError.invalidValue(column: "Import", expected: "UTF-8 TSV data no larger than 10 MB")
        }
    }

    static func validate(text: String) throws {
        try validate(byteCount: text.utf8.count)
    }
}

struct GridBatchRowEdit {
    let rowIndex: Int
    let edits: [StagedEdit]
}

struct GridPastePlan {
    let rows: [GridBatchRowEdit]
    let mappedColumnNames: [String]
    let sourceRowCount: Int
    let mappingMode: GridPasteMappingMode
}

enum GridPastePlanBuilder {
    static func build(
        tsv: String,
        anchor: GridCellCoordinate,
        result: QueryResult,
        columns: [ColumnInfo],
        visibleColumnIndices: [Int],
        mappingMode: GridPasteMappingMode,
        dialect: DatabaseDialect? = nil
    ) throws -> GridPastePlan {
        guard result.rows.indices.contains(anchor.row), columns == result.columns || columns.count == result.columns.count else {
            throw RecordValueError.invalidValue(column: "Paste", expected: "a current base-table result row")
        }
        let parsed = parse(tsv)
        guard !parsed.isEmpty else {
            throw RecordValueError.invalidValue(column: "Paste", expected: "at least one data row")
        }

        let mappedIndices: [Int]
        let dataRows: [[String]]
        switch mappingMode {
        case .positional:
            guard let start = visibleColumnIndices.firstIndex(of: anchor.column),
                  let width = parsed.first?.count,
                  width > 0,
                  start + width <= visibleColumnIndices.count else {
                throw RecordValueError.invalidValue(column: "Paste", expected: "a range within the visible columns")
            }
            mappedIndices = Array(visibleColumnIndices[start..<(start + width)])
            dataRows = parsed
        case .headerRow:
            guard parsed.count > 1 else {
                throw RecordValueError.invalidValue(column: "Paste header", expected: "a header plus at least one data row")
            }
            let names = parsed[0].map(decodeTSV)
            guard Set(names).count == names.count else {
                throw RecordValueError.invalidValue(column: "Paste header", expected: "unique column names")
            }
            let indexByName = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element.name, $0.offset) })
            mappedIndices = try names.map { name in
                guard let index = indexByName[name] else {
                    throw RecordValueError.invalidValue(column: name, expected: "an existing table column")
                }
                return index
            }
            dataRows = Array(parsed.dropFirst())
        }

        guard !mappedIndices.isEmpty,
              dataRows.allSatisfy({ $0.count == mappedIndices.count }),
              anchor.row + dataRows.count <= result.rows.count else {
            throw RecordValueError.invalidValue(column: "Paste", expected: "rectangular data that fits the loaded rows")
        }
        let primaryKeyIndices = columns.indices.filter { columns[$0].isPrimaryKey }
        guard !primaryKeyIndices.isEmpty else {
            throw RecordValueError.invalidValue(column: "Paste", expected: "a table with a primary key")
        }
        var targetIdentities: Set<[DatabaseValue]> = []
        for rowIndex in anchor.row..<(anchor.row + dataRows.count) {
            let identity = primaryKeyIndices.map { index in
                index < result.rows[rowIndex].count ? result.rows[rowIndex][index] : .null
            }
            guard targetIdentities.insert(identity).inserted else {
                throw RecordValueError.invalidValue(column: "Paste", expected: "unique target primary keys")
            }
        }

        var plannedRows: [GridBatchRowEdit] = []
        for (rowOffset, encodedValues) in dataRows.enumerated() {
            let rowIndex = anchor.row + rowOffset
            var edits: [StagedEdit] = []
            for (valueOffset, encoded) in encodedValues.enumerated() {
                let columnIndex = mappedIndices[valueOffset]
                guard columns.indices.contains(columnIndex), columnIndex < result.rows[rowIndex].count else {
                    throw RecordValueError.invalidValue(column: "Paste", expected: "matching table and result columns")
                }
                let column = columns[columnIndex]
                guard !column.isGenerated else {
                    throw RecordValueError.invalidValue(column: column.name, expected: "a writable column")
                }
                let isNull = encoded == "\\N"
                guard !isNull || column.isNullable else {
                    throw RecordValueError.invalidValue(column: column.name, expected: "a non-NULL value")
                }
                let edit = StagedEdit(
                    columnIndex: columnIndex,
                    columnName: column.name,
                    columnType: column.type,
                    dialect: dialect,
                    isPrimaryKey: column.isPrimaryKey,
                    isNullable: column.isNullable,
                    isUnsigned: column.isUnsigned,
                    isGenerated: column.isGenerated,
                    defaultValue: column.defaultValue,
                    originalValue: result.rows[rowIndex][columnIndex],
                    editText: isNull ? "" : decodeTSV(encoded),
                    isNull: isNull,
                    useDefault: false
                )
                let value = try edit.boundValue()
                if value != edit.originalValue { edits.append(edit) }
            }
            if !edits.isEmpty { plannedRows.append(GridBatchRowEdit(rowIndex: rowIndex, edits: edits)) }
        }
        guard !plannedRows.isEmpty else {
            throw RecordValueError.invalidValue(column: "Paste", expected: "at least one changed value")
        }
        return GridPastePlan(
            rows: plannedRows,
            mappedColumnNames: mappedIndices.map { columns[$0].name },
            sourceRowCount: dataRows.count,
            mappingMode: mappingMode
        )
    }

    static func parse(_ tsv: String) -> [[String]] {
        var rows = tsv.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
        if tsv.hasSuffix("\n"), rows.last == [""] { rows.removeLast() }
        return rows
    }

    static func decodeTSV(_ value: String) -> String {
        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "\\" {
                let next = value.index(after: index)
                guard next < value.endIndex else { output.append("\\"); break }
                switch value[next] {
                case "t": output.append("\t")
                case "r": output.append("\r")
                case "n": output.append("\n")
                case "\\": output.append("\\")
                default: output.append("\\"); output.append(value[next])
                }
                index = value.index(after: next)
            } else {
                output.append(value[index])
                index = value.index(after: index)
            }
        }
        return output
    }
}

private enum PendingRecordMutation {
    case update(edits: [StagedEdit], rowIndex: Int)
    case insert(edits: [StagedEdit])
    case batchUpdate(GridPastePlan)
    case delete(rowIndices: [Int])
}

private enum MutationExecutionError: LocalizedError {
    case affectedRows(expected: UInt64, actual: UInt64?)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .affectedRows(let expected, let actual):
            return "The server reported \(actual.map(String.init) ?? "an unknown number of") affected rows; expected exactly \(expected). The edit was not accepted."
        case .server(let message):
            return message
        }
    }
}

// MARK: - Data Tab

struct DataTabView: View {
    let sessionID: UUID
    let database: String
    let table: String
    let actionScope: UUID
    let isWorkspaceActive: Bool
    private let document: Binding<QueryDocumentTab>?
    private let tableDraft: Binding<QueryDocumentTab>?
    private let completionIdentifiers: [String]
    private let externalEditorController: SQLEditorController?
    private let completionError: String?
    private let displaysEditor: Bool

    init(
        sessionID: UUID,
        database: String,
        table: String,
        actionScope: UUID,
        isWorkspaceActive: Bool,
        tableDraft: Binding<QueryDocumentTab>? = nil
    ) {
        self.sessionID = sessionID
        self.database = database
        self.table = table
        self.actionScope = actionScope
        self.isWorkspaceActive = isWorkspaceActive
        document = nil
        self.tableDraft = tableDraft
        completionIdentifiers = []
        completionError = nil
        displaysEditor = true
        externalEditorController = nil
    }

    init(
        sessionID: UUID,
        document: Binding<QueryDocumentTab>,
        isWorkspaceActive: Bool,
        completionIdentifiers: [String],
        completionError: String? = nil,
        displaysEditor: Bool = true,
        editorController: SQLEditorController? = nil
    ) {
        self.sessionID = sessionID
        database = ""
        table = ""
        actionScope = document.wrappedValue.id
        self.isWorkspaceActive = isWorkspaceActive
        self.document = document
        tableDraft = nil
        self.completionIdentifiers = completionIdentifiers
        self.completionError = completionError
        self.displaysEditor = displaysEditor
        externalEditorController = editorController
    }

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode
    #endif

    @State private var tableQueryText = ""
    @State private var tableSelectedRange = NSRange(location: 0, length: 0)
    @State private var tableResult: QueryResult?
    @State private var columnMeta: [ColumnInfo] = []
    @State private var tableIsLoading = false
    @State private var errorMessage: String?
    @State private var errorIsQueryFailure = false
    @State private var selectedRowIndex: Int?
    @State private var showEditor = false
    @State private var addingNewRow = false
    @State private var editorHeight: CGFloat = 120
    @State private var editorHeightDragStart: CGFloat?
    @State private var showAIAssistant = false
    @State private var showExporter = false
    @State private var exportFormat: GridExportFormat = .csv
    @State private var pendingQueryStatements: [SQLStatement]?
    @State private var pendingRecordMutation: PendingRecordMutation?
    @State private var queuedRecordMutation: PendingRecordMutation?

    // Server-side grid state
    @State private var filters: [GridColumnFilter] = []
    @State private var displayFilters: [GridColumnFilter] = []
    /// This table's followable relationships, loaded beside the column metadata.
    @State private var foreignKeyRelationships: [ForeignKeyRelationship] = []
    /// Which table the relationships above describe. Foreign keys do not change between pages, and
    /// `loadData` runs on every page turn, so the catalog is read once per table rather than once
    /// per page.
    @State private var foreignKeysLoadedFor: String?
    @State private var sorts: [GridSortDescriptor] = []
    @State private var displayedRowsMemo = GridDisplayedRowsMemo()
    @State private var groupColumns: [String] = []
    @State private var aggregates: [GridAggregateDescriptor] = []
    @State private var filterColumnName = ""
    @State private var filterOperation: GridFilterOperator = .equals
    @State private var filterValue = ""
    @State private var showFilterEditor = false
    @State private var filterApplicationMode: GridFilterApplicationMode = .updateQuery
    @State private var stagedQueryFilters: [GridColumnFilter] = []
    @State private var stagedDisplayFilters: [GridColumnFilter] = []
    @State private var showColumnManager = false
    @State private var columnSearchText = ""
    @State private var stagedColumnLayout = GridColumnLayout()

    // Persisted presentation and bounded range selection
    @State private var columnLayout = GridColumnLayout()
    @State private var resizeStartWidths: [String: Double] = [:]
    @State private var selectionAnchor: GridCellCoordinate?
    @State private var selectionEnd: GridCellCoordinate?
    @State private var selectedRowIndices: Set<Int> = []
    @State private var rowSelectionAnchor: Int?
    @State private var pendingPasteTSV: String?
    @State private var pasteMappingMode: GridPasteMappingMode = .positional
    @State private var comparisonText: String?
    @State private var showTSVImporter = false
    @State private var inputErrorMessage: String?

    // Pager
    @State private var currentPage: Int = 1
    @State private var pageSize: Int = 100
    @State private var pageSizeDraft = "100"
    @FocusState private var pageSizeFocused: Bool
    @State private var totalRowCount: Int?
    @State private var hasNextPage = false
    @State private var confirmingExactCount = false
    @State private var exactCountTask: Task<Void, Never>?
    @State private var isCalculatingExactCount = false

    // Auto-repeat
    @State private var autoRepeatInterval: TimeInterval = 10
    @State private var autoRepeatTask: Task<Void, Never>?
    @State private var isAutoRepeating = false

    private let rowNumWidth: CGFloat = 50
    private let rowHeight: CGFloat = 30
    private let minEditorHeight: CGFloat = 60
    private let maxEditorHeight: CGFloat = 400

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    private var isTableContext: Bool { document == nil }

    /// The table-browsing surface loads its own schema identifiers (the
    /// document surface receives them from QueryEditorView's loader). Without
    /// this, table-surface completion had only keywords and current-table
    /// columns — `comm` could never offer `shop`.
    @State private var tableSurfaceIdentifiers: [String] = []
    @State private var qualifiedTableIdentifiers: [String: [String]] = [:]
    @State private var completionDatabaseNames: [String] = []

    private var completionDatabase: String? {
        SQLHighlighter.completionDatabase(in: queryText, selectedRange: selectedRange)
    }

    private var effectiveCompletionIdentifiers: [String] {
        (isTableContext ? tableSurfaceIdentifiers : completionIdentifiers)
            + (completionDatabase.flatMap { qualifiedTableIdentifiers[$0] } ?? [])
    }

    /// The table context owns its editor handle; the document context shares
    /// QueryEditorView's, so its document-level actions reach the same editor.
    @State private var ownedEditorController = SQLEditorController()
    private var editorController: SQLEditorController {
        externalEditorController ?? ownedEditorController
    }

    /// The editor model is the source of truth for content; these setters
    /// keep the persisted state AND forward to the editor handle. The
    /// forward is an equality no-op when the write originated from typing
    /// (outbound bridge), so only genuine external replacements land.
    private var queryText: String {
        get { document?.wrappedValue.text ?? tableDraft?.wrappedValue.text ?? tableQueryText }
        nonmutating set {
            if let document {
                var value = document.wrappedValue
                value.text = newValue
                document.wrappedValue = value
            } else if let tableDraft {
                tableDraft.wrappedValue.text = newValue
            } else {
                tableQueryText = newValue
            }
            editorController.setText(newValue)
        }
    }

    private var selectedRange: NSRange {
        get { document?.wrappedValue.selectedRange ?? tableSelectedRange }
        nonmutating set {
            if let document {
                var value = document.wrappedValue
                value.selectedRange = newValue
                document.wrappedValue = value
            } else {
                tableSelectedRange = newValue
            }
            editorController.setSelection(newValue)
        }
    }

    private var result: QueryResult? {
        get { document?.wrappedValue.result ?? tableResult }
        nonmutating set {
            guard let document else {
                tableResult = newValue
                return
            }
            var value = document.wrappedValue
            value.result = newValue
            document.wrappedValue = value
        }
    }

    private var isLoading: Bool {
        get { document?.wrappedValue.isExecuting ?? tableIsLoading }
        nonmutating set {
            guard let document else {
                tableIsLoading = newValue
                return
            }
            var value = document.wrappedValue
            value.isExecuting = newValue
            document.wrappedValue = value
        }
    }

    private var queryTextBinding: Binding<String> {
        Binding(get: { queryText }, set: { queryText = $0 })
    }

    private var selectedRangeBinding: Binding<NSRange> {
        Binding(get: { selectedRange }, set: { selectedRange = $0 })
    }

    private var queryResultIdentity: UUID? { result?.id }

    private var resultSchemaContext: SchemaContext {
        SchemaContext(
            databaseName: isTableContext
                ? database
                : (session?.currentDatabase ?? "Current database"),
            tables: isTableContext && !columnMeta.isEmpty ? [
                SchemaContext.TableInfo(
                    name: table,
                    columns: columnMeta.map {
                        SchemaContext.ColumnInfo(name: $0.name, type: $0.type)
                    }
                )
            ] : []
        )
    }

    private var totalPages: Int {
        guard let total = totalRowCount, pageSize > 0 else { return 1 }
        return max(1, Int(ceil(Double(total) / Double(pageSize))))
    }

    private var estimatedRowCount: Int? {
        guard filters.isEmpty, !isAnalysisActive else { return nil }
        return session?.databaseStatistics[database]?.status(for: table)?.rowCount
    }

    private var filterDraft: GridColumnFilter? {
        guard let column = columnMeta.first(where: { $0.name == filterColumnName }) else { return nil }
        return GridColumnFilter(
            columnName: column.name,
            columnType: column.type,
            isUnsigned: column.isUnsigned,
            operation: filterOperation,
            value: filterValue
        )
    }

    private var filterValidationError: String? {
        filterDraft?.validationError(dialect: session?.connection?.dialect)
    }

    private var canApplyFilter: Bool {
        filterDraft != nil && filterValidationError == nil
    }

    private var activeFilterCount: Int {
        filters.count + displayFilters.count
    }

    private var editedFilterCollection: [GridColumnFilter] {
        filterApplicationMode == .updateQuery ? stagedQueryFilters : stagedDisplayFilters
    }

    private var filteredColumnMeta: [ColumnInfo] {
        let search = columnSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return columnMeta }
        return columnMeta.filter {
            $0.name.localizedStandardContains(search) || $0.type.localizedStandardContains(search)
        }
    }

    private var stagedVisibleColumnCount: Int {
        columnMeta.lazy.filter { !stagedColumnLayout.hidden.contains($0.name) }.count
    }

    /// A phone gets the small pager — row count, page, two chevrons — rather than the full one
    /// with its page-size control and jump field. The **grid** is the same everywhere.
    private var usesCompactPager: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        interactionView
            .task(id: sessionID) {
                guard let connection = session?.connection else { return }
                completionDatabaseNames = (try? await connection.databases()) ?? []
            }
            .task(id: completionDatabase) {
                guard let database = completionDatabase,
                      qualifiedTableIdentifiers[database] == nil,
                      let connection = session?.connection else { return }
                do {
                    let names = try await SchemaCompletionIdentifiers.qualifiedTables(
                        connection: connection, database: database
                    )
                    try Task.checkCancellation()
                    qualifiedTableIdentifiers[database] = names
                } catch {
                    // Keep existing completions usable; retry on the next entry
                    // into this qualifier rather than caching transient failures.
                }
            }
            .preference(key: SQLRunAvailabilityKey.self, value: SQLRunAvailability(
                canRun: isTableContext && isWorkspaceActive && session?.state.isConnected == true
                    && !isLoading && !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasSelection: selectedRange.length > 0
            ))
    }

    private var presentedView: some View {
        VStack(spacing: 0) {
            if displaysEditor {
                // SQL editor area remains subordinate to the user-controlled canvas.
                SQLEditorSurface(
                    text: queryTextBinding,
                    fontSize: CGFloat(settingsManager.editorFontSize),
                    showLineNumbers: settingsManager.showLineNumbers,
                    selection: selectedRangeBinding,
                    isActive: isWorkspaceActive,
                    schemaIdentifiers: effectiveCompletionIdentifiers + columnMeta.map(\.name),
                    controller: editorController,
                    onTabComplete: { acceptTopCompletion() },
                    ghostSuffix: SQLHighlighter.completionPreviewSuffix(
                        in: queryText,
                        selectedRange: selectedRange,
                        schemaIdentifiers: effectiveCompletionIdentifiers + columnMeta.map(\.name)
                    ),
                    textViewIdentifier: "db-query-editor"
                )
                .frame(height: editorHeight)
                .databaseCanvasSurface(opacity: settingsManager.windowOpacity, strength: 0.045)
                // Suggestions float over the editor's bottom edge instead of
                // occupying a layout row, so their appearance never reflows
                // the grid below.
                .overlay(alignment: .bottom) {
                    // Pills align with the text area, not the box: the
                    // gutter band (package-defined width) is chrome, and a
                    // scrolled pill must never ride over the line numbers.
                    completionBar
                        .padding(
                            .leading,
                            10 + (settingsManager.showLineNumbers ? EditorMetrics.gutterWidth : 0)
                        )
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                // **There is no "auto query" flag any more.** There was: a change to the text
                // while `isLoading` was false was taken to mean a person had typed, and the
                // pager then refused to act for the rest of the session — one page forward was
                // enough to set it, which is why the SQL incremented and never decremented
                // (reported 2026-09-20). It was a guess about who wrote the text, and the
                // document already knows: the generated query is marked saved in the same pass
                // that writes it (`loadData`), and typing is not. That fact is read where it is
                // needed rather than cached in a flag nothing kept correct.
                .task(id: "\(sessionID).\(database)") {
                    guard isTableContext, let connection = session?.connection else { return }
                    tableSurfaceIdentifiers = (try? await SchemaCompletionIdentifiers.load(
                        connection: connection,
                        database: database
                    )) ?? []
                }

                // Drag handle to resize
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 40, height: 4)
                    Spacer()
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    // Global space: the handle moves with the pane edge it
                    // resizes, so local translation would feed back into
                    // itself. Anchoring to the drag-start height keeps the
                    // cumulative translation from compounding per tick.
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = editorHeightDragStart ?? editorHeight
                            editorHeightDragStart = start
                            editorHeight = min(maxEditorHeight, max(minEditorHeight,
                                start + value.translation.height))
                        }
                        .onEnded { _ in editorHeightDragStart = nil }
                )
            }

            if !columnMeta.isEmpty {
                gridControlBar
                Divider()
            }

            // Results area (bottom)
            if isLoading {
                ProgressView("Executing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ScrollView {
                    QueryErrorCard(
                        error: error,
                        query: queryText,
                        schemaContext: SchemaContext(
                            databaseName: database,
                            tables: columnMeta.isEmpty ? [] : [
                                SchemaContext.TableInfo(
                                    name: table,
                                    columns: columnMeta.map {
                                        SchemaContext.ColumnInfo(name: $0.name, type: $0.type)
                                    }
                                )
                            ]
                        ),
                        aiAssistant: session?.aiAssistant,
                        offersNotifications: errorIsQueryFailure,
                        offersAISuggestion: errorIsQueryFailure,
                        onUseSuggestedSQL: { suggestedSQL in
                            queryText = suggestedSQL
                            errorMessage = nil
                            errorIsQueryFailure = false
                        },
                        onDismiss: {
                            errorMessage = nil
                            errorIsQueryFailure = false
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                if let error = result.error {
                    ScrollView {
                        QueryErrorCard(
                            error: error,
                            query: result.query,
                            schemaContext: resultSchemaContext,
                            aiAssistant: session?.aiAssistant,
                            onUseSuggestedSQL: { suggestedSQL in
                                queryText = suggestedSQL
                                selectedRange = NSRange(
                                    location: (suggestedSQL as NSString).length,
                                    length: 0
                                )
                                self.result = nil
                            },
                            onDismiss: { self.result = nil }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if result.columns.isEmpty {
                    statementCompletedView(result)
                } else {
                    // **The grid, on every platform.** A phone used to get a list of cards —
                    // "Row 1", then four fields down the page — which is a different way of
                    // reading a table rather than a smaller one: no column alignment, no
                    // comparison down a column, and only the first four columns at all. The grid
                    // already scrolls in both directions, which is exactly what a narrow screen
                    // needs (reported 2026-09-19: *"I appreciate the idea of the card view for
                    // rows, but it's not right. Let's use the table view we already have"*).
                    dataGrid(result)
                }
            } else {
                emptyResultsGrid
            }

            // Pager bar at bottom
            if let result {
                Divider()
                if usesCompactPager {
                    compactPager(result)
                } else {
                    fullPager(result)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showEditor, onDismiss: presentQueuedRecordMutation) {
            if let result, let rowIdx = selectedRowIndex, rowIdx < result.rows.count {
                RecordEditorView(
                    columns: columnMeta.isEmpty ? result.columns : columnMeta,
                    mode: .edit(rowIndex: rowIdx, originalRow: result.rows[rowIdx]),
                    dialect: session?.connection?.dialect,
                    onSave: { edits, mode in
                        queuedRecordMutation = .update(edits: edits, rowIndex: rowIdx)
                        showEditor = false
                    },
                    onDiscard: { showEditor = false }
                )
            }
        }
        .sheet(isPresented: $addingNewRow, onDismiss: presentQueuedRecordMutation) {
            RecordEditorView(
                columns: columnMeta,
                mode: .add,
                dialect: session?.connection?.dialect,
                onSave: { edits, _ in
                    queuedRecordMutation = .insert(edits: edits)
                    addingNewRow = false
                },
                onDiscard: { addingNewRow = false }
            )
        }
        .sheet(isPresented: $showFilterEditor) {
            filterEditor
        }
        .sheet(isPresented: $showColumnManager) {
            columnManager
        }
        #if canImport(FoundationModels)
        .sheet(isPresented: $showAIAssistant) {
            if let assistant = session?.aiAssistant {
                AIAssistantView(
                    aiAssistant: assistant,
                    schemaContext: SchemaContext(
                        databaseName: database,
                        tables: columnMeta.isEmpty ? [] : [
                            SchemaContext.TableInfo(
                                name: table,
                                columns: columnMeta.map { SchemaContext.ColumnInfo(name: $0.name, type: $0.type) }
                            )
                        ]
                    ),
                    onInsertQuery: { sql in
                        queryText = sql
                        showAIAssistant = false
                    }
                )
            } else {
                ContentUnavailableView("Session Disconnected", systemImage: "cable.connector.slash")
            }
        }
        #endif
        .alert("Review SQL Before Executing", isPresented: .init(
            get: { pendingQueryStatements != nil },
            set: { if !$0 { pendingQueryStatements = nil } }
        )) {
            Button("Execute", role: .destructive) {
                let statements = pendingQueryStatements ?? []
                pendingQueryStatements = nil
                Task { await execute(statements) }
            }
            Button("Cancel", role: .cancel) { pendingQueryStatements = nil }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text(queryMutationPreview)
        }
        #if os(macOS)
        .sheet(isPresented: .init(
            get: { pendingRecordMutation != nil },
            set: { if !$0 { pendingRecordMutation = nil } }
        )) {
            recordMutationReviewSheet
        }
        #else
        .alert("Review Row Mutation", isPresented: .init(
            get: { pendingRecordMutation != nil },
            set: { if !$0 { pendingRecordMutation = nil } }
        )) {
            Button("Commit", role: .destructive) { commitPendingRecordMutation() }
                .accessibilityIdentifier("db-delete-confirm")
            Button("Cancel", role: .cancel) { pendingRecordMutation = nil }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("db-delete-cancel")
        } message: {
            Text(recordMutationPreview)
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: .init(
            get: { pendingPasteTSV != nil },
            set: { if !$0 { pendingPasteTSV = nil } }
        ), onDismiss: presentQueuedRecordMutation) {
            pasteReviewSheet
        }
        #else
        .alert("Review Pasted Range", isPresented: .init(
            get: { pendingPasteTSV != nil },
            set: { if !$0 { pendingPasteTSV = nil } }
        )) {
            Button("Stage Paste") { confirmPaste() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { pendingPasteTSV = nil }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text(pastePreview)
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: .init(
            get: { comparisonText != nil },
            set: { if !$0 { comparisonText = nil } }
        )) {
            comparisonReviewSheet
        }
        #else
        .alert("Compare Rows", isPresented: .init(
            get: { comparisonText != nil },
            set: { if !$0 { comparisonText = nil } }
        )) {
            Button("Done", role: .cancel) { comparisonText = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(comparisonText ?? "")
        }
        #endif
        .alert("Table Action Failed", isPresented: .init(
            get: { inputErrorMessage != nil },
            set: { if !$0 { inputErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { inputErrorMessage = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(inputErrorMessage ?? "")
        }
        .alert("Calculate Exact Row Count?", isPresented: $confirmingExactCount) {
            Button("Calculate") {
                exactCountTask = Task { await calculateExactRowCount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs SELECT COUNT(*) against the entire table. On a large production table it may scan an index or the table itself. Prefer a read replica when available; the query is stopped after 30 seconds.")
        }
    }

    /// Split from `interactionView` on purpose: with the foreign-key observer added, the single
    /// chain stopped type-checking in reasonable time. Two properties, same view.
    private var observedView: some View {
        presentedView
        .onReceive(NotificationCenter.default.publisher(for: .glassdbExecuteQuery)) { notification in
            guard isWorkspaceActive, isTableContext,
                  let scope = notification.object as? UUID,
                  scope == actionScope || scope == sessionID else { return }
            let mode = (notification.userInfo?["mode"] as? String).flatMap(SQLExecutionMode.init(rawValue:)) ?? .automatic
            Task { await executeCurrentQuery(mode: mode) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbAddRow)) { notification in
            guard notification.object as? UUID == actionScope else { return }
            addingNewRow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbOpenTable)) { notification in
            // The workspace switches to the tab; if this one already exists it is mounted and its
            // `.task` will not run again, so the staged filters are claimed here instead.
            guard let request = notification.object as? OpenTableRequest,
                  request.sessionID == sessionID,
                  request.database == database,
                  request.table == table else { return }
            guard claimStagedForeignKeyFilters() else { return }
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbRefreshData)) { notification in
            guard let scope = notification.object as? UUID,
                  scope == actionScope || scope == sessionID else { return }
            queryText = ""
            totalRowCount = nil
            foreignKeysLoadedFor = nil
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbShowAI)) { notification in
            guard notification.object as? UUID == actionScope else { return }
            showAIAssistant = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbStartRepeat)) { notification in
            guard isWorkspaceActive,
                  notification.object as? UUID == actionScope else { return }
            startAutoRepeat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassdbTransfer)) { notification in
            handleTransfer(notification.object)
        }
    }

    private var interactionView: some View {
        observedView
        .fileExporter(
            isPresented: $showExporter,
            document: exportResult.map {
                GridExportDocument(
                    result: $0,
                    format: exportFormat,
                    database: database,
                    table: table,
                    identifierQuote: session?.connection?.identifierQuoteCharacter ?? "`"
                )
            },
            contentType: exportFormat.contentType,
            defaultFilename: "\(database)_\(table).\(exportFormat.rawValue)"
        ) { result in
            if case .failure(let error) = result {
                inputErrorMessage = "The export could not be completed. \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showTSVImporter,
            allowedContentTypes: [.tabSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { selection in
            do {
                guard let url = try selection.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
                try GridImportPolicy.validate(byteCount: byteCount)
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                try GridImportPolicy.validate(byteCount: data.count)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw RecordValueError.invalidValue(column: "Import", expected: "UTF-8 TSV data")
                }
                pendingPasteTSV = text
            } catch {
                inputErrorMessage = "The import was not staged. \(error.localizedDescription)"
            }
        }
        .onChange(of: currentPage) { handleCurrentPageChange() }
        .onChange(of: pageSize) { handlePageSizeChange() }
        .onChange(of: pageSizeFocused) { handlePageSizeFocusChange() }
        .task { await loadInitialWorkspaceContent() }
        .onChange(of: queryResultIdentity) { handleQueryResultChange() }
        .onChange(of: isWorkspaceActive) { handleWorkspaceActivityChange() }
        .onDisappear(perform: handleWorkspaceDisappear)
    }

    private func loadInitialWorkspaceContent() async {
        if isTableContext {
            loadColumnLayout()
            loadGridQueryState()
            // A foreign-key follow that opened this tab for the first time left its filters here.
            // Claimed after the persisted state so it wins over it, and before the first fetch so
            // the table never appears unfiltered and then jumps.
            claimStagedForeignKeyFilters()
            await loadData()
        } else {
            filterApplicationMode = .displayOnly
            reconcileFreeformResult()
        }
    }

    private func handleQueryResultChange() {
        guard !isTableContext else { return }
        reconcileFreeformResult()
    }

    private func handleWorkspaceActivityChange() {
        if !isWorkspaceActive {
            stopAutoRepeat()
        }
    }

    private func handleCurrentPageChange() {
        // **Paging always fetches the page.** It is the app's own action, not an edit, so it
        // cannot be gated on whether the editor holds a user's query: a chevron that silently
        // does nothing is the thing rule 45 forbids. Whether the *text* follows the page is
        // decided inside `loadData`, which refuses to overwrite something someone typed.
        Task { await loadData() }
    }

    private func handlePageSizeChange() {
        if !pageSizeFocused {
            pageSizeDraft = String(pageSize)
        }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func handlePageSizeFocusChange() {
        if !pageSizeFocused, pageSizeDraft != String(pageSize) {
            commitPageSizeDraft()
        }
    }

    private func handleWorkspaceDisappear() {
        stopAutoRepeat()
        exactCountTask?.cancel()
        exactCountTask = nil
    }

    /// Formats the selected SQL slice when a selection exists, otherwise the
    /// whole editor text. Runs through the state setters so the editor model
    /// updates via the controller path.
    private func formatQuery() {
        let source = queryText as NSString
        if selectedRange.length > 0 {
            let location = min(selectedRange.location, source.length)
            let length = min(selectedRange.length, source.length - location)
            let range = NSRange(location: location, length: length)
            let formatted = SQLHighlighter.formatted(source.substring(with: range))
            queryText = source.replacingCharacters(in: range, with: formatted)
            selectedRange = NSRange(location: location, length: (formatted as NSString).length)
        } else {
            let formatted = SQLHighlighter.formatted(queryText)
            queryText = formatted
            selectedRange = NSRange(location: (formatted as NSString).length, length: 0)
        }
    }

    /// Tab-to-complete: applies the completion bar's top suggestion through
    /// the same insertion path as a bar tap. Returns false when there is
    /// nothing to accept so Tab keeps its normal behavior.
    private func acceptTopCompletion() -> Bool {
        let identifiers = effectiveCompletionIdentifiers + columnMeta.map(\.name)
        guard let first = SQLHighlighter.completions(
            in: queryText,
            selectedRange: selectedRange,
            schemaIdentifiers: identifiers
        ).first else { return false }
        let applied = SQLHighlighter.applyingCompletion(
            first,
            to: queryText,
            selectedRange: selectedRange,
            appendSpace: true,
            databaseNames: completionDatabaseNames
        )
        queryText = applied.sql
        selectedRange = applied.selection
        editorController.markCompletionSpace(in: applied.sql, at: applied.automaticSpace)
        return true
    }

    @ViewBuilder
    private var completionBar: some View {
        let identifiers = effectiveCompletionIdentifiers + columnMeta.map(\.name)
        let suggestions = SQLHighlighter.completions(
            in: queryText,
            selectedRange: selectedRange,
            schemaIdentifiers: identifiers
        )
        if !suggestions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            let applied = SQLHighlighter.applyingCompletion(
                                suggestion,
                                to: queryText,
                                selectedRange: selectedRange,
                                appendSpace: true,
                                databaseNames: completionDatabaseNames
                            )
                            queryText = applied.sql
                            selectedRange = applied.selection
                            editorController.markCompletionSpace(in: applied.sql, at: applied.automaticSpace)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)
                }
            )
        } else if let completionError {
            Label(completionError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .accessibilityLabel("Schema completion unavailable. \(completionError)")
        }
    }

    /// A statement that returns no result set — DDL, DCL, or a bare mutation —
    /// would otherwise render as an empty grid, which looks exactly like a
    /// query that did nothing. Report completion explicitly instead.
    @ViewBuilder
    private func statementCompletedView(_ result: QueryResult) -> some View {
        ContentUnavailableView {
            Label("Statement Completed", systemImage: "checkmark.circle")
        } description: {
            Text(Self.statementCompletionSummary(
                affectedRows: result.affectedRows,
                executionTime: result.executionTime
            ))
        }
        // Fill the results pane, as the grid and the error card do, so the pager stays at its
        // foot instead of riding up under the message (2026-09-29).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func statementCompletionSummary(
        affectedRows: UInt64?,
        executionTime: TimeInterval
    ) -> String {
        let duration = String(format: "%.3f", executionTime)
        guard let affectedRows else {
            return "The server returned no result set. Completed in \(duration)s."
        }
        let noun = affectedRows == 1 ? "row" : "rows"
        return "\(affectedRows) \(noun) affected in \(duration)s."
    }

    @ViewBuilder
    private func fullPager(_ result: QueryResult) -> some View {
        HStack(spacing: 12) {
            let visibleRowCount = displayedRowIndices(in: result).count
            Text(displayFilters.isEmpty
                ? "\(result.rowCount) rows"
                : "\(visibleRowCount) of \(result.rowCount) loaded rows")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isTableContext {
                if let totalRowCount {
                    Text(displayFilters.isEmpty
                        ? "\(totalRowCount) matching total"
                        : "\(totalRowCount) server-matched total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let estimatedRowCount {
                    Text("~\(estimatedRowCount.formatted()) estimated total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("total not calculated")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if result.isTruncated, let limit = result.appliedRowLimit {
                Text("more available — loaded result limited to \(limit)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("in \(String(format: "%.3f", result.executionTime))s")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isTableContext, isAutoRepeating {
                Label("Repeating \(Int(autoRepeatInterval))s", systemImage: "repeat")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if isTableContext, filters.isEmpty, !isAnalysisActive {
                if isCalculatingExactCount {
                    Button("Cancel Count", role: .cancel) {
                        cancelExactRowCount()
                    }
                    .controlSize(.small)
                } else {
                    Button("Calculate Total…") {
                        confirmingExactCount = true
                    }
                    .controlSize(.small)
                    .help("Run an explicit exact count with a 30-second timeout")
                }
            }

            Spacer()
            if isTableContext {
                pageButtons
                Text("Per page:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Rows per page", text: $pageSizeDraft)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($pageSizeFocused)
                    .onSubmit { commitPageSizeDraft() }
                    .accessibilityLabel("Rows per page")
                    .help("Enter a value from 1 through 10,000")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func compactPager(_ result: QueryResult) -> some View {
        HStack(spacing: 10) {
            Text("\(displayedRowIndices(in: result).count) rows")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isTableContext {
                pageButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var pageButtons: some View {
        ControlGroup {
            Button {
                currentPage = max(1, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)
            .accessibilityLabel("Previous page")

            Text(totalRowCount == nil ? "Page \(currentPage)" : "\(currentPage) of \(totalPages)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                currentPage += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!hasNextPage)
            .accessibilityLabel("Next page")
        }
    }

    // The compact record list — a card per row, four columns of it — lived here until
    // 2026-09-19. It was a different way of reading a table rather than a smaller one, and the
    // grid it replaced scrolls in both directions perfectly well on a phone.

    // MARK: - Data Grid

    @ViewBuilder
    private var gridControlBar: some View {
        #if os(macOS)
        ScrollView(.horizontal) {
            gridControls
        }
        .scrollIndicators(.automatic)
        .accessibilityLabel("SQL result controls")
        #elseif os(iOS)
        if usesCompactPager {
            compactGridControls
        } else {
            ScrollView(.horizontal) {
                gridControls
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel("SQL result controls")
        }
        #else
        // Icons only, so the row fits the window as Mail's does; nothing scrolls or wraps.
        gridControls
            .accessibilityElement(children: .contain)
            .accessibilityLabel("SQL result controls")
        #endif
    }

    #if os(iOS)
    private var compactGridControls: some View {
        HStack {
            if isTableContext {
                EditButton()
            }
            Spacer()
            Button {
                formatQuery()
            } label: {
                Label("Format", systemImage: "text.alignleft")
                    .labelStyle(.iconOnly)
            }
            .help("Format the selected SQL, or the whole query when nothing is selected")
            .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button {
                beginFilterEditing()
            } label: {
                Label(activeFilterCount == 0 ? "Filter" : "Filter \(activeFilterCount)", systemImage: "line.3.horizontal.decrease.circle")
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Choose Columns", systemImage: "rectangle.split.3x1") {
                    beginColumnManagement()
                }
                Button("Copy Selected Rows", systemImage: "doc.on.doc") {
                    copySelectedRange()
                }
                .disabled(selectedRowIndices.isEmpty)
                Button("Delete Selected Rows…", systemImage: "trash", role: .destructive) {
                    requestDeleteSelectedRows()
                }
                .disabled(!canDeleteSelectedRows)
                Button("Import TSV", systemImage: "square.and.arrow.down") {
                    showTSVImporter = true
                }
                .disabled(!isTableContext)
                Divider()
                Button("Count All Rows", systemImage: "function") {
                    addAggregate(.countAll, columnName: nil)
                }
                .disabled(!isTableContext)
                if !groupColumns.isEmpty || !aggregates.isEmpty {
                    Button("Clear Analysis", systemImage: "xmark.circle") {
                        clearAnalysis()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    #endif

    /// The bar above the results, in Mail's shape: one row of icon buttons with their names in
    /// the help and accessibility labels, and the occasional tools behind More. It was thirteen
    /// controls in four styles — labelled buttons, a bare "Compare", four arrow buttons, a paste
    /// capsule and a "Header" switch — that wrapped and looked unlike anything else on the
    /// headset (2026-09-28).
    private var gridControls: some View {
        HStack(spacing: 8) {
            Button {
                beginFilterEditing()
            } label: {
                Label("Filter", systemImage: activeFilterCount == 0
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityValue(activeFilterCount == 0 ? "" : "\(activeFilterCount) active")
            .help(activeFilterCount == 0
                ? (isTableContext
                    ? "Choose rows to show using a server query or the currently loaded page"
                    : "Filter the bounded rows currently loaded in this SQL result")
                : "Review \(activeFilterCount) active row filter\(activeFilterCount == 1 ? "" : "s")")
            if !sorts.isEmpty {
                Text(sorts.enumerated().map { index, sort in
                    "\(index + 1):\(sort.columnName) \(sort.direction == .ascending ? "↑" : "↓")"
                }.joined(separator: "  "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button {
                formatQuery()
            } label: {
                Label("Format", systemImage: "text.alignleft")
            }
            .help("Format the selected SQL, or the whole query when nothing is selected")
            .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Menu {
                Menu("Group Columns") {
                    ForEach(columnMeta) { column in
                        Button(groupColumns.contains(column.name) ? "Remove \(column.name)" : "Add \(column.name)") {
                            toggleGrouping(column.name)
                        }
                    }
                }
                Button("Add Count All") {
                    addAggregate(.countAll, columnName: nil)
                }
                Menu("Add Column Aggregate") {
                    ForEach(GridAggregateFunction.allCases.filter(\.requiresColumn)) { function in
                        Menu(function.displayName) {
                            ForEach(columnMeta) { column in
                                Button(column.name) { addAggregate(function, columnName: column.name) }
                            }
                        }
                    }
                }
                if !groupColumns.isEmpty || !aggregates.isEmpty {
                    Divider()
                    Button("Clear Analysis") { clearAnalysis() }
                }
            } label: {
                Label("Analyze", systemImage: "function")
            }
            .accessibilityValue(aggregates.isEmpty ? "" : "\(aggregates.count) aggregates")
            .disabled(!isTableContext)
            .help(isTableContext
                ? "Group and aggregate this table through a bounded server query"
                : "Server-backed analysis is available from a table tab")

            Button {
                beginColumnManagement()
            } label: {
                Label("Columns", systemImage: "rectangle.split.3x1")
            }
            .help("Choose visible and frozen columns")

            Button {
                copySelectedRange()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy the selected cells")
            .disabled(selectedRectangle == nil && selectedRowIndices.isEmpty)

            Menu {
                ForEach(GridExportFormat.allCases) { format in
                    Button(format.displayName) {
                        exportFormat = format
                        showExporter = true
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(exportResult?.rows.isEmpty != false)
            .help("Export the selected rows, or all displayed rows when nothing is selected")

            Button(role: .destructive) {
                requestDeleteSelectedRows()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canDeleteSelectedRows)
            .help(deleteControlHelp)

            moreGridControls
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        #if !os(visionOS)
        .controlSize(.small)
        #endif
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// The tools used now and then, as menu items: comparing rows, nudging the selection, and
    /// staging pasted or imported rows.
    private var moreGridControls: some View {
        Menu {
            Button("Compare Rows", systemImage: "rectangle.split.2x1") { compareSelectedRows() }
                .disabled(!canCompareSelectedRows)

            Menu("Extend Selection", systemImage: "arrow.up.left.and.arrow.down.right") {
                Button("Left", systemImage: "arrow.left") { moveSelection(rowDelta: 0, columnDelta: -1) }
                Button("Right", systemImage: "arrow.right") { moveSelection(rowDelta: 0, columnDelta: 1) }
                Button("Up", systemImage: "arrow.up") { moveSelection(rowDelta: -1, columnDelta: 0) }
                Button("Down", systemImage: "arrow.down") { moveSelection(rowDelta: 1, columnDelta: 0) }
            }
            .disabled(result?.rows.isEmpty != false)

            Divider()

            Button("Paste Rows", systemImage: "doc.on.clipboard") { stagePastedRows() }
                .disabled(!isTableContext || selectionAnchor == nil || isAnalysisActive)
            Button("Import TSV…", systemImage: "square.and.arrow.down") { showTSVImporter = true }
                .disabled(!isTableContext || selectionAnchor == nil || isAnalysisActive)
            Toggle("First Row Is Column Names", isOn: .init(
                get: { pasteMappingMode == .headerRow },
                set: { pasteMappingMode = $0 ? .headerRow : .positional }
            ))
            .disabled(!isTableContext || isAnalysisActive)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("Compare rows, extend the selection, and paste or import rows")
    }

    /// Stages tab-separated text from the clipboard at the selected cell. On iOS and visionOS the
    /// system asks before the app may read what another app copied, as it does for Safari.
    private func stagePastedRows() {
        #if os(macOS)
        let value = NSPasteboard.general.string(forType: .string)
        #else
        let value = UIPasteboard.general.string
        #endif
        guard let value, !value.isEmpty else {
            inputErrorMessage = "The clipboard has no text to paste."
            return
        }
        do {
            try GridImportPolicy.validate(text: value)
            pendingPasteTSV = value
        } catch {
            inputErrorMessage = "The paste was not staged. \(error.localizedDescription)"
        }
    }

    private var filterEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Filtering", selection: $filterApplicationMode) {
                        ForEach(isTableContext ? GridFilterApplicationMode.allCases : [.displayOnly]) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Behavior")
                } footer: {
                    Text(filterApplicationMode.explanation)
                }

                Section("Active Conditions") {
                    if editedFilterCollection.isEmpty {
                        Label("No conditions in this mode", systemImage: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(editedFilterCollection) { filter in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(filter.columnName)
                                        .fontWeight(.medium)
                                    Text(filterDescription(filter))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    removeStagedFilter(filter)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove filter for \(filter.columnName)")
                                .help("Remove this condition")
                            }
                        }
                        Button("Clear \(filterApplicationMode == .updateQuery ? "Query" : "Display") Filters", role: .destructive) {
                            clearStagedFilters()
                        }
                    }
                }

                Section("Add or Replace Condition") {
                    Picker("Column", selection: $filterColumnName) {
                        ForEach(columnMeta) { column in
                            Text(column.name).tag(column.name)
                        }
                    }
                    Picker("Condition", selection: $filterOperation) {
                        ForEach(GridFilterOperator.allCases) { operation in
                            Text(operation.displayName).tag(operation)
                        }
                    }
                    if filterOperation.requiresValue {
                        TextField("Value", text: $filterValue)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { addStagedFilter() }
                            .accessibilityLabel("Filter value")
                            .help("Enter a value compatible with the selected column type")
                    }
                    if let filterValidationError {
                        Label(filterValidationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Invalid filter: \(filterValidationError)")
                    }
                    Button("Add Condition", systemImage: "plus") {
                        addStagedFilter()
                    }
                    .disabled(!canApplyFilter)
                }

                if filterApplicationMode == .displayOnly, let result {
                    Section {
                        LabeledContent(
                            "Visible rows",
                            value: "\(displayedRowIndices(in: result, filters: stagedDisplayFilters).count) of \(result.rowCount) loaded"
                        )
                    } footer: {
                        Text("Display-only comparisons are literal and may differ from the database server’s collation rules.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filter Rows")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFilterEditor = false }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitFilterEditing() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }

    private var columnManager: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button("Show All", systemImage: "eye") {
                            stagedColumnLayout.hidden.removeAll()
                        }
                        Button("Hide All", systemImage: "eye.slash") {
                            stagedColumnLayout.hidden = Set(columnMeta.map(\.name))
                            stagedColumnLayout.frozen.removeAll()
                        }
                        Button("Unfreeze All", systemImage: "pin.slash") {
                            stagedColumnLayout.frozen.removeAll()
                        }
                        Spacer()
                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            stagedColumnLayout = GridColumnLayout(order: columnMeta.map(\.name))
                        }
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text("Changes are staged until you choose Done. Frozen columns remain visible and stay at the leading edge while you scroll.")
                }

                Section {
                    if filteredColumnMeta.isEmpty {
                        ContentUnavailableView.search(text: columnSearchText)
                    } else {
                        ForEach(filteredColumnMeta) { column in
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(column.name)
                                        .font(.body.monospaced())
                                        .lineLimit(1)
                                    Text(column.type)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 12)
                                Toggle(isOn: columnVisibilityBinding(column.name)) {
                                    Label("Visible", systemImage: "eye")
                                }
                                .fixedSize()
                                .help("Show or hide \(column.name)")
                                Toggle(isOn: columnFrozenBinding(column.name)) {
                                    Label("Frozen", systemImage: "pin")
                                }
                                .fixedSize()
                                .help("Keep \(column.name) visible at the leading edge")
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                } header: {
                    HStack {
                        Text("Columns")
                        Spacer()
                        Text("\(stagedVisibleColumnCount) visible · \(stagedColumnLayout.frozen.count) frozen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .searchable(text: $columnSearchText, prompt: "Search columns")
            .navigationTitle("Manage Columns")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showColumnManager = false }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitColumnManagement() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(width: 680, height: 620)
        #endif
    }

    #if os(macOS)
    private var pasteReviewSheet: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    LabeledContent("Table", value: "\(database).\(table)")
                    Picker("Column Mapping", selection: $pasteMappingMode) {
                        Text("From Selected Cell").tag(GridPasteMappingMode.positional)
                        Text("First Row Contains Column Names").tag(GridPasteMappingMode.headerRow)
                    }
                    .pickerStyle(.radioGroup)
                }
                Section("Preview") {
                    Text(pastePreview)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Review Pasted Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingPasteTSV = nil }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stage Paste") { confirmPaste() }
                        .keyboardShortcut(.defaultAction)
                        .help("Validate and stage this range without writing it yet")
                }
            }
        }
        .frame(width: 560, height: 430)
    }

    private var recordMutationReviewSheet: some View {
        NavigationStack {
            Form {
                Section("Pending Change") {
                    Text(recordMutationPreview)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                Section {
                    Label(
                        "No database write occurs until you choose Commit.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Review Row Mutation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingRecordMutation = nil }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("db-delete-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit", role: .destructive) { commitPendingRecordMutation() }
                        .keyboardShortcut(.defaultAction)
                        .help("Commit this reviewed row mutation")
                        .accessibilityIdentifier("db-delete-confirm")
                }
            }
        }
        .frame(width: 560, height: 420)
    }

    private var comparisonReviewSheet: some View {
        NavigationStack {
            Form {
                Section("Selected Rows") {
                    Text(comparisonText ?? "")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Compare Rows")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { comparisonText = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 640, height: 500)
    }
    #endif

    private func displayedRowIndices(
        in result: QueryResult,
        filters filterSet: [GridColumnFilter]? = nil
    ) -> [Int] {
        guard !isAnalysisActive else { return Array(result.rows.indices) }
        let dialect = session?.connection?.dialect
        let compute = {
            let matching = GridDisplayFilterEvaluator.matchingRowIndices(
                rows: result.rows,
                columns: result.columns,
                filters: filterSet ?? displayFilters,
                dialect: dialect
            )
            guard !isTableContext else { return matching }
            return GridDisplaySortEvaluator.sortedRowIndices(
                rows: result.rows,
                columns: result.columns,
                rowIndices: matching,
                sorts: sorts
            )
        }
        // The staged filters of the filter sheet are a preview count, not the grid: not memoized.
        guard filterSet == nil else { return compute() }
        return displayedRowsMemo.rows(
            for: .init(result: result.id, rowCount: result.rows.count, filters: displayFilters, sorts: sorts, dialect: dialect,
                       isAnalysis: false, isTable: isTableContext),
            compute: compute
        )
    }

    private var selectedRectangle: (rows: ClosedRange<Int>, columns: [Int])? {
        guard let anchor = selectionAnchor,
              let end = selectionEnd,
              let result else { return nil }
        let visible = gridVisibleColumnIndices(for: result)
        guard let anchorIndex = visible.firstIndex(of: anchor.column),
              let endIndex = visible.firstIndex(of: end.column) else { return nil }
        let lowerColumn = min(anchorIndex, endIndex)
        let upperColumn = max(anchorIndex, endIndex)
        return (
            min(anchor.row, end.row)...max(anchor.row, end.row),
            Array(visible[lowerColumn...upperColumn])
        )
    }

    private func gridVisibleColumnIndices(for result: QueryResult) -> [Int] {
        isAnalysisActive ? Array(result.columns.indices) : columnLayout.visibleColumnIndices(columns: result.columns)
    }

    private var pastePreview: String {
        guard let pendingPasteTSV, let anchor = selectionAnchor else { return "" }
        let rows = GridPastePlanBuilder.parse(pendingPasteTSV)
        let dataRowCount = max(0, rows.count - (pasteMappingMode == .headerRow ? 1 : 0))
        let columns = rows.first?.count ?? 0
        let mapping = pasteMappingMode == .headerRow
            ? "The first row maps exact table column names."
            : "Columns map positionally from the selected cell."
        return "Target starts at loaded row \(anchor.row + 1).\nPasted data: \(dataRowCount) row(s) × \(columns) column(s).\n\(mapping)\n\nEvery changed row will use its original full-row values as an optimistic predicate inside one transaction. Any validation, conflict, or server error rolls back the entire batch."
    }

    private var isAnalysisActive: Bool { !aggregates.isEmpty }

    private var canCompareSelectedRows: Bool {
        guard !isAnalysisActive else { return false }
        if selectedRowIndices.count == 2 { return true }
        return selectedRectangle?.rows.count == 2
    }

    private var exportResult: QueryResult? {
        guard let result else { return nil }
        let visible = gridVisibleColumnIndices(for: result)
        let rowIndices: [Int]
        if !selectedRowIndices.isEmpty {
            rowIndices = selectedRowIndices.sorted().filter { result.rows.indices.contains($0) }
        } else if let selectedRectangle {
            rowIndices = selectedRectangle.rows.filter { result.rows.indices.contains($0) }
        } else {
            rowIndices = displayedRowIndices(in: result)
        }
        let selectedColumns: [Int]
        if !selectedRowIndices.isEmpty {
            selectedColumns = visible
        } else if let selectedRectangle {
            selectedColumns = selectedRectangle.columns
        } else {
            selectedColumns = visible
        }
        return QueryResult(
            query: result.query,
            columns: selectedColumns.map { result.columns[$0] },
            rows: rowIndices.map { rowIndex in
                selectedColumns.map { columnIndex in
                    columnIndex < result.rows[rowIndex].count ? result.rows[rowIndex][columnIndex] : .null
                }
            },
            executionTime: result.executionTime,
            timestamp: result.timestamp
        )
    }

    /// The unexecuted editor uses the same canvas geometry as populated results.
    /// Stripes are decoration only: no invented columns, rows, or query result.
    private var emptyResultsGrid: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("#")
                            .font(.system(size: settingsManager.dataGridFontSize, weight: .semibold))
                            .frame(width: rowNumWidth)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 36)
                    .databaseCanvasPinnedSurface(
                        opacity: settingsManager.windowOpacity,
                        blur: settingsManager.blurBackground
                    )
                    .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        ForEach(0..<max(0, Int(ceil((geometry.size.height - 36) / rowHeight))), id: \.self) { index in
                            HStack(spacing: 0) {
                                Color.clear.frame(width: rowNumWidth)
                                    .databaseCanvasPinnedSurface(
                                        opacity: settingsManager.windowOpacity,
                                        blur: settingsManager.blurBackground
                                    )
                                Color.clear
                            }
                            .frame(height: rowHeight)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(
                                DatabaseGlassAppearance(opacity: settingsManager.windowOpacity, blur: 0)
                                    .surfaceAlpha(strength: 0.02)
                            ))
                        }
                    }
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            .padding(.trailing, 8)
            Divider()
            HStack {
                Text("Ready — enter SQL above, then run a statement or selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dataGrid(_ result: QueryResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let fontSize = settingsManager.dataGridFontSize
                let visibleIndices = gridVisibleColumnIndices(for: result)
                let automaticWidths = columnWidths(columns: result.columns, rows: result.rows)
                let widths = visibleIndices.map { index in
                    CGFloat(columnLayout.widths[result.columns[index].name] ?? Double(automaticWidths[index]))
                }
                let frozenLeadingOffsets = GridColumnLayout.leadingOffsets(widths: widths, startingAt: rowNumWidth)
                let activeSelection = selectedRectangle
                let selectedColumns = Set(activeSelection?.columns ?? [])
                let totalDataWidth = rowNumWidth + widths.reduce(0, +)
                let fillerWidth = max(0, geometry.size.width - totalDataWidth)
                let displayedRows = displayedRowIndices(in: result)
                let dataHeight = CGFloat(displayedRows.count) * rowHeight
                let headerHeight: CGFloat = 36
                let fillerRowCount = max(0, Int((geometry.size.height - headerHeight - dataHeight) / rowHeight))

                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        Section {
                            // Data rows with a pinned row-number gutter
                            ForEach(displayedRows, id: \.self) { rowIndex in
                                let row = result.rows[rowIndex]
                                let displayedRowNumber = (currentPage - 1) * pageSize + rowIndex + 1
                                HStack(spacing: 0) {
                                    // Keep the generated row-number gutter fixed and legible while data scrolls.
                                    Text("\(displayedRowNumber)")
                                        .font(.system(size: fontSize - 1).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: rowNumWidth, height: rowHeight, alignment: .center)
                                        .background(
                                            selectedRowIndices.contains(rowIndex)
                                                ? Color.accentColor.opacity(0.22)
                                                : Color.clear
                                        )
                                        .databaseCanvasPinnedSurface(
                                            opacity: settingsManager.windowOpacity,
                                            blur: settingsManager.blurBackground
                                        )
                                        .visualEffect { content, proxy in
                                            content.offset(x: max(0, -proxy.frame(in: .scrollView(axis: .horizontal)).minX))
                                        }
                                        .zIndex(3)
                                        .contentShape(Rectangle())
                                        .gridTap(select: { selectRow(rowIndex) },
                                                 open: { openEditor(for: rowIndex) })
                                        .accessibilityLabel("Row \(displayedRowNumber)")
                                        .accessibilityHint("Selects the entire row. Use Shift or Command for multiple rows. Double-click to edit.")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityIdentifier("db-grid-row-\(displayedRowNumber)")
                                        .help("Select row \(displayedRowNumber); Shift-click extends, Command-click toggles, and double-click edits")
                                        .contextMenu {
                                            if isTableContext, !isAnalysisActive {
                                                Button("Edit Row", systemImage: "pencil") {
                                                    openEditor(for: rowIndex)
                                                }
                                                .accessibilityIdentifier("db-row-menu-edit")
                                                followReferenceMenu(for: rowIndex)
                                                Divider()
                                                Button(deleteRowMenuTitle(for: rowIndex),
                                                       systemImage: "trash",
                                                       role: .destructive) {
                                                    if selectedRowIndices.contains(rowIndex) {
                                                        requestDeleteSelectedRows()
                                                    } else {
                                                        requestDeleteRow(rowIndex)
                                                    }
                                                }
                                                .accessibilityIdentifier("db-row-menu-delete")
                                            }
                                        }

                                    // Data cells
                                    ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleOffset, colIndex in
                                        let value = colIndex < row.count ? row[colIndex] : DatabaseValue.null
                                        let frozenLeadingOffset = frozenLeadingOffsets[visibleOffset]
                                        let isFrozen = columnLayout.frozen.contains(result.columns[colIndex].name)
                                        let isSelected = activeSelection?.rows.contains(rowIndex) == true && selectedColumns.contains(colIndex)
                                        Text(value.displayString)
                                            .font(value.usesNumericGridAlignment
                                                ? .system(size: fontSize).monospacedDigit()
                                                : .system(size: fontSize))
                                            .lineLimit(1)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .frame(width: widths[visibleOffset], height: rowHeight,
                                                   alignment: value.usesNumericGridAlignment ? .trailing : .leading)
                                            .foregroundStyle(value.isNull ? .tertiary : .primary)
                                            .background(
                                                isFrozen
                                                    ? AnyShapeStyle(Color.primary.opacity(
                                                        DatabaseGlassAppearance(
                                                            opacity: settingsManager.windowOpacity,
                                                            blur: 0
                                                        ).surfaceAlpha()
                                                    ))
                                                    : AnyShapeStyle(Color.clear)
                                            )
                                            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(Color.clear))
                                            .gridFrozen(isFrozen, leadingOffset: frozenLeadingOffset, zIndex: 2)
                                            .accessibilityLabel("\(result.columns[colIndex].name): \(value.isNull ? "null" : value.displayString)")
                                            .accessibilityIdentifier("db-grid-cell-\(displayedRowNumber)-\(result.columns[colIndex].name)")
                                            .contentShape(Rectangle())
                                            .gridTap(select: { selectCell(row: rowIndex, column: colIndex) },
                                                     open: { openEditor(for: rowIndex) })
                                    }
                                    if fillerWidth > 0 {
                                        Color.clear.frame(width: fillerWidth, height: rowHeight)
                                    }
                                }
                                .background(rowBackground(rowIndex: rowIndex, totalDataRows: displayedRows.count))
                            }
                            // Filler rows
                            ForEach(0..<fillerRowCount, id: \.self) { fillerIndex in
                                let globalIndex = result.rows.count + fillerIndex
                                HStack(spacing: 0) {
                                    Color.clear
                                        .frame(width: rowNumWidth, height: rowHeight)
                                        .databaseCanvasPinnedSurface(
                                            opacity: settingsManager.windowOpacity,
                                            blur: settingsManager.blurBackground
                                        )
                                        .visualEffect { content, proxy in
                                            content.offset(x: max(0, -proxy.frame(in: .scrollView(axis: .horizontal)).minX))
                                        }
                                        .zIndex(3)
                                    ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                                        Color.clear.frame(width: w, height: rowHeight)
                                    }
                                    if fillerWidth > 0 {
                                        Color.clear.frame(width: fillerWidth, height: rowHeight)
                                    }
                                }
                                .background(
                                    globalIndex.isMultiple(of: 2)
                                        ? Color.clear
                                        : Color.primary.opacity(
                                            DatabaseGlassAppearance(
                                                opacity: settingsManager.windowOpacity,
                                                blur: 0
                                            ).surfaceAlpha(strength: 0.02)
                                        )
                                )
                            }
                        } header: {
                            HStack(spacing: 0) {
                                Text("#")
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .frame(width: rowNumWidth, alignment: .center)
                                    .databaseCanvasPinnedSurface(
                                        opacity: settingsManager.windowOpacity,
                                        blur: settingsManager.blurBackground
                                    )
                                    .visualEffect { content, proxy in
                                        content.offset(x: max(0, -proxy.frame(in: .scrollView(axis: .horizontal)).minX))
                                    }
                                    .zIndex(4)

                                ForEach(Array(visibleIndices.enumerated()), id: \.element) { visibleOffset, colIndex in
                                    let col = result.columns[colIndex]
                                    let frozenLeadingOffset = frozenLeadingOffsets[visibleOffset]
                                    let isFrozen = columnLayout.frozen.contains(col.name)
                                    HStack(spacing: 4) {
                                        Text(col.name)
                                            .lineLimit(1)
                                        if let priority = sorts.firstIndex(where: { $0.columnName == col.name }) {
                                            Text("\(priority + 1)\(sorts[priority].direction == .ascending ? "↑" : "↓")")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                        if columnLayout.frozen.contains(col.name) {
                                            Image(systemName: "pin.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .padding(.leading, 12)
                                    .padding(.vertical, 8)
                                    .frame(width: widths[visibleOffset], alignment: .leading)
                                    .background(
                                        isFrozen
                                            ? AnyShapeStyle(Color.primary.opacity(
                                                DatabaseGlassAppearance(
                                                    opacity: settingsManager.windowOpacity,
                                                    blur: 0
                                                ).surfaceAlpha()
                                            ))
                                            : AnyShapeStyle(Color.clear)
                                    )
                                    .visualEffect { content, proxy in
                                        content.offset(
                                            x: isFrozen
                                                ? max(0, frozenLeadingOffset - proxy.frame(in: .scrollView(axis: .horizontal)).minX)
                                                : 0
                                        )
                                    }
                                    .zIndex(isFrozen ? 3 : 0)
                                    .contentShape(Rectangle())
                                    .onTapGesture { cycleSort(for: col.name) }
                                    .contextMenu {
                                        Button("Sort Ascending") { setSort(col.name, direction: .ascending) }
                                        Button("Sort Descending") { setSort(col.name, direction: .descending) }
                                        Button("Remove Sort") { removeSort(col.name) }
                                        Divider()
                                        Button(columnLayout.frozen.contains(col.name) ? "Unfreeze" : "Freeze") {
                                            toggleColumnFreeze(col.name)
                                        }
                                        Button("Hide") { toggleColumnVisibility(col.name) }
                                        Button("Move Left") { moveColumn(col.name, offset: -1) }
                                        Button("Move Right") { moveColumn(col.name, offset: 1) }
                                    }
                                    .overlay(alignment: .trailing) {
                                        Capsule()
                                            .fill(.secondary.opacity(0.45))
                                            .frame(width: 2, height: 14)
                                            .frame(width: 16, height: headerHeight)
                                            .contentShape(Rectangle())
                                            .help("Drag to resize \(col.name)")
                                            .gesture(
                                                // Global space: the handle rides the column edge
                                                // being resized, so local translation feeds back.
                                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                                    .onChanged { value in resizeColumn(col.name, baseWidth: widths[visibleOffset], translation: value.translation.width) }
                                                    .onEnded { _ in finishResizingColumn(col.name) }
                                            )
                                    }
                                    .accessibilityAddTraits(.isHeader)
                                }
                                if fillerWidth > 0 {
                                    Spacer().frame(width: fillerWidth)
                                }
                            }
                            .frame(height: headerHeight)
                            .databaseCanvasPinnedSurface(
                                opacity: settingsManager.windowOpacity,
                                blur: settingsManager.blurBackground
                            )
                        }
                    }
                }
                .scrollIndicators(.visible)
                .databaseLookScrollEnabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Inset the whole viewport, including overlay scrollbars. Keeping this
        // outside GeometryReader also preserves the filler-column measurement.
        .padding(.trailing, 8)
    }

    private func rowBackground(rowIndex: Int, totalDataRows: Int) -> some ShapeStyle {
        if selectedRowIndices.contains(rowIndex) {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        }
        return AnyShapeStyle(
            rowIndex.isMultiple(of: 2)
                ? Color.clear
                : Color.primary.opacity(
                    DatabaseGlassAppearance(
                        opacity: settingsManager.windowOpacity,
                        blur: 0
                    ).surfaceAlpha(strength: 0.02)
                )
        )
    }

    private func openEditor(for rowIndex: Int) {
        guard isTableContext, !isAnalysisActive else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedRowIndex = rowIndex
            selectedRowIndices = [rowIndex]
            rowSelectionAnchor = rowIndex
            selectionAnchor = nil
            selectionEnd = nil
            showEditor = true
        }
    }

    private func selectCell(row: Int, column: Int) {
        let coordinate = GridCellCoordinate(row: row, column: column)
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
        selectionAnchor = coordinate
        selectionEnd = coordinate
        selectedRowIndex = row
    }

    private func selectRow(_ row: Int) {
        guard let result, result.rows.indices.contains(row) else { return }
        let displayedRows = displayedRowIndices(in: result)
        #if os(macOS)
        let modifierFlags = NSEvent.modifierFlags
        let extendsSelection = modifierFlags.contains(.shift)
        let togglesSelection = modifierFlags.contains(.command)
        #else
        let extendsSelection = false
        let togglesSelection = false
        #endif
        let updated = GridRowSelectionState(
            rows: selectedRowIndices,
            anchor: rowSelectionAnchor
        ).selecting(
            row,
            from: displayedRows,
            extendsSelection: extendsSelection,
            togglesSelection: togglesSelection
        )
        selectedRowIndices = updated.rows
        rowSelectionAnchor = updated.anchor

        selectionAnchor = nil
        selectionEnd = nil
        selectedRowIndex = selectedRowIndices.contains(row) ? row : selectedRowIndices.sorted().first
    }

    private func copySelectedRange() {
        guard let exportResult,
              !exportResult.rows.isEmpty,
              !exportResult.columns.isEmpty else { return }
        PlatformClipboard.copy(GridExportFormatter.tsv(
            result: exportResult,
            rowRange: exportResult.rows.indices.lowerBound...(exportResult.rows.indices.upperBound - 1),
            columnRange: exportResult.columns.indices.lowerBound...(exportResult.columns.indices.upperBound - 1)
        ))
    }

    private func moveSelection(rowDelta: Int, columnDelta: Int) {
        guard let result, !result.rows.isEmpty else { return }
        let visible = gridVisibleColumnIndices(for: result)
        guard !visible.isEmpty else { return }
        let current = selectionEnd ?? GridCellCoordinate(row: 0, column: visible[0])
        let currentVisibleIndex = visible.firstIndex(of: current.column) ?? 0
        let next = GridCellCoordinate(
            row: max(0, min(result.rows.count - 1, current.row + rowDelta)),
            column: visible[max(0, min(visible.count - 1, currentVisibleIndex + columnDelta))]
        )
        if selectionAnchor == nil { selectionAnchor = current }
        selectionEnd = next
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
        selectedRowIndex = next.row
    }

    private func stagePastedRange(_ tsv: String) {
        guard let result, let anchor = selectionAnchor else { return }
        let columns = columnMeta.isEmpty ? result.columns : columnMeta
        let visible = columnLayout.visibleColumnIndices(columns: columns)
        do {
            let plan = try GridPastePlanBuilder.build(
                tsv: tsv,
                anchor: anchor,
                result: result,
                columns: columns,
                visibleColumnIndices: visible,
                mappingMode: pasteMappingMode,
                dialect: session?.connection?.dialect
            )
            queuedRecordMutation = plan.rows.count == 1
                ? .update(edits: plan.rows[0].edits, rowIndex: plan.rows[0].rowIndex)
                : .batchUpdate(plan)
        } catch {
            inputErrorMessage = "The paste was not staged and no values were changed. \(error.localizedDescription)"
        }
    }

    private func compareSelectedRows() {
        guard let result else { return }
        let rowIndices: [Int]
        let columnIndices: [Int]
        if selectedRowIndices.count == 2 {
            rowIndices = selectedRowIndices.sorted()
            columnIndices = gridVisibleColumnIndices(for: result)
        } else if let selectedRectangle, selectedRectangle.rows.count == 2 {
            rowIndices = [selectedRectangle.rows.lowerBound, selectedRectangle.rows.upperBound]
            columnIndices = selectedRectangle.columns
        } else {
            return
        }
        do {
            let differences = try GridRowComparison.differences(
                result: result,
                leftRow: rowIndices[0],
                rightRow: rowIndices[1],
                columnIndices: columnIndices
            )
            let header = "Loaded rows \(rowIndices[0] + 1) and \(rowIndices[1] + 1)"
            comparisonText = differences.isEmpty
                ? "\(header) are identical in the selected columns."
                : header + "\n\n" + differences.map {
                    "\($0.columnName)\n  Left: \($0.left.isNull ? "NULL" : $0.left.displayString)\n  Right: \($0.right.isNull ? "NULL" : $0.right.displayString)"
                }.joined(separator: "\n\n")
        } catch {
            errorMessage = error.localizedDescription
            errorIsQueryFailure = false
        }
    }

    private func beginFilterEditing() {
        filterApplicationMode = isTableContext ? .updateQuery : .displayOnly
        stagedQueryFilters = filters
        stagedDisplayFilters = displayFilters
        filterValue = ""
        showFilterEditor = true
    }

    private func addStagedFilter() {
        guard let filter = filterDraft,
              filter.validationError(dialect: session?.connection?.dialect) == nil else { return }
        if filterApplicationMode == .updateQuery {
            stagedQueryFilters.removeAll { $0.columnName == filter.columnName }
            stagedQueryFilters.append(filter)
        } else {
            stagedDisplayFilters.removeAll { $0.columnName == filter.columnName }
            stagedDisplayFilters.append(filter)
        }
        filterValue = ""
    }

    private func removeStagedFilter(_ filter: GridColumnFilter) {
        if filterApplicationMode == .updateQuery {
            stagedQueryFilters.removeAll { $0.id == filter.id }
        } else {
            stagedDisplayFilters.removeAll { $0.id == filter.id }
        }
    }

    private func clearStagedFilters() {
        if filterApplicationMode == .updateQuery {
            stagedQueryFilters.removeAll()
        } else {
            stagedDisplayFilters.removeAll()
        }
    }

    private func commitFilterEditing() {
        let queryFiltersChanged = stagedQueryFilters != filters
        filters = isTableContext ? stagedQueryFilters : []
        displayFilters = stagedDisplayFilters
        selectionAnchor = nil
        selectionEnd = nil
        selectedRowIndex = nil
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
        showFilterEditor = false

        guard isTableContext, queryFiltersChanged else { return }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func filterDescription(_ filter: GridColumnFilter) -> String {
        filter.operation.requiresValue
            ? "\(filter.operation.displayName) \(filter.value)"
            : filter.operation.displayName
    }

    private func confirmPaste() {
        guard let pendingPasteTSV else { return }
        self.pendingPasteTSV = nil
        stagePastedRange(pendingPasteTSV)
        #if !os(macOS)
        presentQueuedRecordMutation()
        #endif
    }

    private func handleTransfer(_ object: Any?) {
        guard let request = object as? GridTransferRequest,
              request.scope == actionScope else { return }
        switch request.operation {
        case .importTSV:
            showTSVImporter = true
        case .export(let format):
            exportFormat = format
            showExporter = true
        }
    }

    private func presentQueuedRecordMutation() {
        guard let queuedRecordMutation else { return }
        self.queuedRecordMutation = nil
        pendingRecordMutation = queuedRecordMutation
    }

    private func commitPendingRecordMutation() {
        let mutation = pendingRecordMutation
        pendingRecordMutation = nil
        Task {
            switch mutation {
            case .update(let edits, let rowIndex): await applyEdits(edits, rowIndex: rowIndex)
            case .insert(let edits): await insertRow(edits)
            case .batchUpdate(let plan): await applyBatchPaste(plan)
            case .delete(let rowIndices): await deleteRows(rowIndices)
            case .none: break
            }
        }
    }

    private func commitPageSizeDraft() {
        let trimmed = pageSizeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), (1...10_000).contains(parsed) else {
            pageSizeDraft = String(pageSize)
            inputErrorMessage = "Rows per page must be a whole number from 1 through 10,000."
            return
        }
        pageSizeDraft = String(parsed)
        guard parsed != pageSize else { return }
        pageSize = parsed
    }

    private func clearGridSelection() {
        selectionAnchor = nil
        selectionEnd = nil
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
    }

    private func cycleSort(for columnName: String) {
        if let index = sorts.firstIndex(where: { $0.columnName == columnName }) {
            if sorts[index].direction == .ascending {
                sorts[index].direction = .descending
            } else {
                sorts.remove(at: index)
            }
        } else {
            sorts.append(GridSortDescriptor(columnName: columnName, direction: .ascending))
        }
        guard isTableContext else {
            clearGridSelection()
            return
        }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func setSort(_ columnName: String, direction: GridSortDirection) {
        if let index = sorts.firstIndex(where: { $0.columnName == columnName }) {
            sorts[index].direction = direction
        } else {
            sorts.append(GridSortDescriptor(columnName: columnName, direction: direction))
        }
        guard isTableContext else {
            clearGridSelection()
            return
        }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func removeSort(_ columnName: String) {
        sorts.removeAll { $0.columnName == columnName }
        guard isTableContext else {
            clearGridSelection()
            return
        }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func beginColumnManagement() {
        stagedColumnLayout = columnLayout
        stagedColumnLayout.reconcile(columns: columnMeta)
        columnSearchText = ""
        showColumnManager = true
    }

    private func columnVisibilityBinding(_ columnName: String) -> Binding<Bool> {
        Binding(
            get: { !stagedColumnLayout.hidden.contains(columnName) },
            set: { isVisible in
                if isVisible {
                    stagedColumnLayout.hidden.remove(columnName)
                } else {
                    stagedColumnLayout.hidden.insert(columnName)
                    stagedColumnLayout.frozen.remove(columnName)
                }
            }
        )
    }

    private func columnFrozenBinding(_ columnName: String) -> Binding<Bool> {
        Binding(
            get: { stagedColumnLayout.frozen.contains(columnName) },
            set: { isFrozen in
                if isFrozen {
                    stagedColumnLayout.frozen.insert(columnName)
                    stagedColumnLayout.hidden.remove(columnName)
                } else {
                    stagedColumnLayout.frozen.remove(columnName)
                }
            }
        )
    }

    private func commitColumnManagement() {
        stagedColumnLayout.reconcile(columns: columnMeta)
        columnLayout = stagedColumnLayout
        selectionAnchor = nil
        selectionEnd = nil
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
        persistColumnLayout()
        showColumnManager = false
    }

    private func toggleColumnVisibility(_ columnName: String) {
        if columnLayout.hidden.contains(columnName) {
            columnLayout.hidden.remove(columnName)
        } else if columnLayout.visibleColumnIndices(columns: columnMeta).count > 1 {
            columnLayout.hidden.insert(columnName)
            columnLayout.frozen.remove(columnName)
        }
        persistColumnLayout()
    }

    private func toggleColumnFreeze(_ columnName: String) {
        if columnLayout.frozen.contains(columnName) {
            columnLayout.frozen.remove(columnName)
        } else {
            columnLayout.frozen.insert(columnName)
            columnLayout.hidden.remove(columnName)
        }
        persistColumnLayout()
    }

    private func moveColumn(_ columnName: String, offset: Int) {
        guard let source = columnLayout.order.firstIndex(of: columnName) else { return }
        let destination = max(0, min(columnLayout.order.count - 1, source + offset))
        guard source != destination else { return }
        columnLayout.order.remove(at: source)
        columnLayout.order.insert(columnName, at: destination)
        persistColumnLayout()
    }

    private func resizeColumn(_ columnName: String, baseWidth: CGFloat, translation: CGFloat) {
        let start = resizeStartWidths[columnName] ?? Double(baseWidth)
        resizeStartWidths[columnName] = start
        columnLayout.widths[columnName] = Double(max(60, min(600, CGFloat(start) + translation)))
    }

    private func finishResizingColumn(_ columnName: String) {
        resizeStartWidths.removeValue(forKey: columnName)
        persistColumnLayout()
    }

    private func resetColumnLayout() {
        columnLayout = GridColumnLayout(order: columnMeta.map(\.name))
        persistColumnLayout()
    }

    private func toggleGrouping(_ columnName: String) {
        if let index = groupColumns.firstIndex(of: columnName) {
            groupColumns.remove(at: index)
        } else {
            groupColumns.append(columnName)
        }
        persistGridQueryState()
        currentPage = 1
        if !aggregates.isEmpty { Task { await loadData() } }
    }

    private func addAggregate(_ function: GridAggregateFunction, columnName: String?) {
        let descriptor = GridAggregateDescriptor(function: function, columnName: columnName)
        if !aggregates.contains(descriptor) { aggregates.append(descriptor) }
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func clearAnalysis() {
        groupColumns = []
        aggregates = []
        persistGridQueryState()
        currentPage = 1
        Task { await loadData() }
    }

    private func loadColumnLayout() {
        guard let connectionID = session?.connectionConfig.id else { return }
        let key = GridColumnLayout.storageKey(connectionID: connectionID, database: database, table: table)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GridColumnLayout.self, from: data) {
            columnLayout = decoded
        }
    }

    private func persistColumnLayout() {
        guard let connectionID = session?.connectionConfig.id,
              let data = try? JSONEncoder().encode(columnLayout) else { return }
        let key = GridColumnLayout.storageKey(connectionID: connectionID, database: database, table: table)
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadGridQueryState() {
        guard let connectionID = session?.connectionConfig.id else { return }
        let key = GridQueryState.storageKey(connectionID: connectionID, database: database, table: table)
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(GridQueryState.self, from: data) else {
            // A table not opened before starts at the service's own Rows per page. The setting
            // was saved and validated, then never read: every grid began at 100 (help audit).
            if let preferred = session?.connectionConfig.rowPageSize {
                pageSize = DatabaseConnectionConfig.clampedRowPageSize(preferred)
            }
            return
        }
        filters = state.filters
        sorts = state.sorts
        groupColumns = state.groupColumns
        aggregates = state.aggregates
        pageSize = state.pageSize
    }

    private func persistGridQueryState() {
        guard let connectionID = session?.connectionConfig.id else { return }
        let state = GridQueryState(
            filters: filters,
            sorts: sorts,
            groupColumns: groupColumns,
            aggregates: aggregates,
            pageSize: pageSize
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let key = GridQueryState.storageKey(connectionID: connectionID, database: database, table: table)
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Column Widths

    private func columnWidths(columns: [ColumnInfo], rows: [[DatabaseValue]]) -> [CGFloat] {
        let charWidth = settingsManager.dataGridFontSize * 0.65
        return columns.enumerated().map { colIndex, col in
            let headerLen = CGFloat(col.name.count)
            var maxDataLen: CGFloat = 0
            for row in rows.prefix(50) {
                if colIndex < row.count {
                    maxDataLen = max(maxDataLen, CGFloat(row[colIndex].displayString.count))
                }
            }
            let computed = max(headerLen, maxDataLen) * charWidth + 24
            return max(80, min(computed, 400))
        }
    }

    // MARK: - Data Loading

    private func reconcileFreeformResult() {
        guard !isTableContext else { return }
        let columns = result?.columns ?? []
        let validColumnNames = Set(columns.map(\.name))
        columnMeta = columns
        filters = []
        displayFilters.removeAll { !validColumnNames.contains($0.columnName) }
        sorts.removeAll { !validColumnNames.contains($0.columnName) }
        groupColumns = []
        aggregates = []
        columnLayout.reconcile(columns: columns)
        if columnLayout.order.isEmpty {
            columnLayout.order = columns.map(\.name)
        }
        currentPage = 1
        totalRowCount = nil
        hasNextPage = false
        clearGridSelection()
        if filterColumnName.isEmpty || !validColumnNames.contains(filterColumnName) {
            filterColumnName = columns.first?.name ?? ""
        }
    }

    private func loadData() async {
        guard let connection = session?.connection else { return }
        let preservedIdentity = selectedRowIdentity()
        isLoading = true
        errorMessage = nil
        errorIsQueryFailure = false
        showEditor = false
        do {
            columnMeta = try await connection.columns(in: table, database: database)
            await loadForeignKeyRelationships()
            let validColumnNames = Set(columnMeta.map(\.name))
            displayFilters.removeAll { !validColumnNames.contains($0.columnName) }
            columnLayout.reconcile(columns: columnMeta)
            persistColumnLayout()
            var queryState = GridQueryState(
                filters: filters,
                sorts: sorts,
                groupColumns: groupColumns,
                aggregates: aggregates,
                pageSize: pageSize
            )
            queryState.reconcile(columns: columnMeta)
            filters = queryState.filters
            sorts = queryState.sorts
            groupColumns = queryState.groupColumns
            aggregates = queryState.aggregates
            pageSize = queryState.pageSize
            persistGridQueryState()
            if filterColumnName.isEmpty || !columnMeta.contains(where: { $0.name == filterColumnName }) {
                filterColumnName = columnMeta.first?.name ?? ""
            }
            if !filters.isEmpty || isAnalysisActive {
                totalRowCount = nil
            }
            let displayedQuery: GridServerQuery
            let fetchQuery: GridServerQuery
            if isAnalysisActive {
                displayedQuery = try GridServerQueryBuilder.aggregate(
                    database: database,
                    table: table,
                    columns: columnMeta,
                    filters: filters,
                    groupColumns: groupColumns,
                    aggregates: aggregates,
                    page: currentPage,
                    pageSize: pageSize,
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect
                )
                fetchQuery = try GridServerQueryBuilder.aggregate(
                    database: database,
                    table: table,
                    columns: columnMeta,
                    filters: filters,
                    groupColumns: groupColumns,
                    aggregates: aggregates,
                    page: currentPage,
                    pageSize: pageSize,
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect,
                    fetchSentinel: true
                )
            } else {
                displayedQuery = try GridServerQueryBuilder.select(
                    database: database,
                    table: table,
                    columns: columnMeta,
                    filters: filters,
                    sorts: sorts,
                    page: currentPage,
                    pageSize: pageSize,
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect
                )
                fetchQuery = try GridServerQueryBuilder.select(
                    database: database,
                    table: table,
                    columns: columnMeta,
                    filters: filters,
                    sorts: sorts,
                    page: currentPage,
                    pageSize: pageSize,
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect,
                    fetchSentinel: true
                )
            }
            // Refreshing/recreating the browsing view must not erase a user draft.
            if tableDraft?.wrappedValue.hasUnsavedChanges != true {
                queryText = SQLHighlighter.editorText(forGeneratedQuery: displayedQuery.sql)
                // Generated browsing SQL is the baseline, not an unsaved user edit.
                tableDraft?.wrappedValue.markSaved()
            }
            let rawResult = try await sessionManager.executeQuery(
                fetchQuery.sql,
                parameters: fetchQuery.parameters,
                sessionID: sessionID
            )
            let window = GridPageWindow.bounded(
                rawResult,
                pageSize: pageSize,
                displayedQuery: displayedQuery.sql
            )
            result = window.result
            hasNextPage = window.hasNextPage
            restoreSelection(identity: preservedIdentity, in: window.result)
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
            errorMessage = error.localizedDescription
            errorIsQueryFailure = true
            hasNextPage = false
        }
        isLoading = false
    }

    private func calculateExactRowCount() async {
        guard filters.isEmpty,
              !isAnalysisActive,
              let connection = session?.connection else { return }
        isCalculatingExactCount = true
        defer {
            isCalculatingExactCount = false
            exactCountTask = nil
        }
        do {
            let count = try await connection.rowCount(
                table: table,
                database: database,
                timeout: .seconds(30)
            )
            try Task.checkCancellation()
            totalRowCount = count
        } catch is CancellationError {
            return
        } catch {
            await sessionManager.handleConnectionFailure(error, sessionID: sessionID)
            inputErrorMessage = "Exact row count failed: \(error.localizedDescription)"
        }
    }

    private func cancelExactRowCount() {
        exactCountTask?.cancel()
        exactCountTask = nil
        Task {
            do {
                try await sessionManager.cancelQuery(sessionID: sessionID)
            } catch {
                inputErrorMessage = "Could not cancel the exact row count: \(error.localizedDescription)"
            }
        }
    }

    private func selectedRowIdentity() -> [String: DatabaseValue]? {
        guard !isAnalysisActive else { return nil }
        guard let result, let selectedRowIndex, result.rows.indices.contains(selectedRowIndex) else { return nil }
        let columns = columnMeta.isEmpty ? result.columns : columnMeta
        let primaryKeys = columns.enumerated().filter { $0.element.isPrimaryKey }
        guard !primaryKeys.isEmpty else { return nil }
        return Dictionary(uniqueKeysWithValues: primaryKeys.compactMap { index, column in
            guard index < result.rows[selectedRowIndex].count else { return nil }
            return (column.name, result.rows[selectedRowIndex][index])
        })
    }

    private func restoreSelection(identity: [String: DatabaseValue]?, in result: QueryResult) {
        guard let identity, !identity.isEmpty else {
            selectedRowIndex = nil
            selectionAnchor = nil
            selectionEnd = nil
            selectedRowIndices.removeAll()
            rowSelectionAnchor = nil
            return
        }
        let indexByName = Dictionary(uniqueKeysWithValues: result.columns.enumerated().map { ($0.element.name, $0.offset) })
        selectedRowIndex = result.rows.firstIndex { row in
            identity.allSatisfy { name, value in
                guard let index = indexByName[name], index < row.count else { return false }
                return row[index] == value
            }
        }
        if selectedRowIndex == nil {
            selectionAnchor = nil
            selectionEnd = nil
            selectedRowIndices.removeAll()
            rowSelectionAnchor = nil
        } else if let selectedRowIndex {
            selectedRowIndices = [selectedRowIndex]
            rowSelectionAnchor = selectedRowIndex
        }
    }

    private var queryMutationPreview: String {
        guard let statements = pendingQueryStatements else { return "" }
        let categories = Set(statements.filter(\.safety.requiresConfirmation).map { $0.safety.displayName }).sorted()
        let sql = statements.map(\.text).joined(separator: ";\n")
        return "Connection: \(session?.connectionConfig.name ?? "Disconnected")\nDatabase: \(database)\nTable: \(table)\nRisk: \(categories.joined(separator: ", "))\nTransaction: statement-defined/server default\n\n\(sql)"
    }

    private var recordMutationPreview: String {
        guard let pendingRecordMutation else { return "" }
        switch pendingRecordMutation {
        case .update(let edits, _):
            return "Connection: \(session?.connectionConfig.name ?? "Disconnected")\nDatabase: \(database)\nTable: \(table)\nOperation: UPDATE one row\nChanged columns: \(edits.map(\.columnName).joined(separator: ", "))\nPredicate: primary key plus all original row values (optimistic conflict check)\nTransaction: atomic commit or rollback"
        case .insert(let edits):
            return "Connection: \(session?.connectionConfig.name ?? "Disconnected")\nDatabase: \(database)\nTable: \(table)\nOperation: INSERT one row\nProvided columns: \(edits.map(\.columnName).joined(separator: ", "))\nOmitted columns: server DEFAULT\nTransaction: atomic commit or rollback"
        case .delete(let rowIndices):
            return "Connection: \(session?.connectionConfig.name ?? "Disconnected")\nDatabase: \(database)\nTable: \(table)\nOperation: DELETE \(rowIndices.count) row(s)\nPredicate: primary key plus every original row value (optimistic conflict check)\nGuard: every statement must affect exactly one row, or nothing is committed\nTransaction: all rows commit together or all rows roll back\nThis cannot be undone from the app."
        case .batchUpdate(let plan):
            return "Connection: \(session?.connectionConfig.name ?? "Disconnected")\nDatabase: \(database)\nTable: \(table)\nOperation: UPDATE \(plan.rows.count) changed row(s) from \(plan.sourceRowCount) pasted row(s)\nMapped columns: \(plan.mappedColumnNames.joined(separator: ", "))\nMapping: \(plan.mappingMode == .headerRow ? "exact header names" : "positional from selected cell")\nPredicate: primary key plus every original row value (optimistic conflict checks)\nTransaction: all rows commit together or all rows roll back"
        }
    }

    private func executeCurrentQuery(mode: SQLExecutionMode = .automatic) async {
        guard !isLoading, session?.state.isConnected == true else { return }
        let statements = SQLHighlighter.statementsToExecute(in: queryText, selectedRange: selectedRange, mode: mode)
        guard !statements.isEmpty else { return }
        if statements.contains(where: { $0.safety.requiresConfirmation }) {
            pendingQueryStatements = statements
            return
        }
        await execute(statements)
    }

    private func execute(_ statements: [SQLStatement]) async {
        isLoading = true
        errorMessage = nil
        errorIsQueryFailure = false
        selectedRowIndex = nil
        selectedRowIndices.removeAll()
        rowSelectionAnchor = nil
        selectionAnchor = nil
        selectionEnd = nil
        showEditor = false
        do {
            var lastResult: QueryResult?
            for statement in statements {
                let queryResult = try await sessionManager.executeQuery(statement.text, sessionID: sessionID)
                if let serverError = queryResult.error {
                    throw MutationExecutionError.server(serverError)
                }
                lastResult = queryResult
                if statement.safety.requiresConfirmation, let connectionID = session?.connectionConfig.id {
                    MutationAuditStore.append(MutationAuditRecord(
                        connectionID: connectionID,
                        database: database,
                        object: table,
                        normalizedOperation: statement.safety.rawValue,
                        source: "query-editor",
                        outcome: .committed,
                        affectedRows: queryResult.affectedRows
                    ))
                }
            }
            result = lastResult
        } catch {
            errorMessage = error.localizedDescription
            errorIsQueryFailure = true
        }
        isLoading = false
    }

    // MARK: - Auto-Repeat

    private func startAutoRepeat() {
        guard isWorkspaceActive else { return }
        stopAutoRepeat()
        isAutoRepeating = true
        autoRepeatTask = Task {
            while !Task.isCancelled {
                await executeCurrentQuery()
                try? await Task.sleep(for: .seconds(autoRepeatInterval))
            }
        }
    }

    private func stopAutoRepeat() {
        autoRepeatTask?.cancel()
        autoRepeatTask = nil
        isAutoRepeating = false
    }

    // MARK: - Apply Edits

    private func applyEdits(_ edits: [StagedEdit], rowIndex: Int) async {
        guard let result, let connection = session?.connection else { return }

        // Use columnMeta for PK info (query result columns don't have it)
        let cols = columnMeta.isEmpty ? result.columns : columnMeta
        let pkColumns = cols.filter(\.isPrimaryKey)
        guard !pkColumns.isEmpty else {
            errorMessage = "Cannot update: table has no primary key"
            errorIsQueryFailure = false
            return
        }

        guard rowIndex < result.rows.count, !edits.isEmpty else { return }
        var parameters: [DatabaseValue] = []
        var transactionStarted = false
        var commitAttempted = false
        /// The predicate's shape, for the audit. Declared out here so a failure records the same
        /// predicate a success would have. Never the parameters — see `MutationAuditRecord`.
        var predicateShape: String?
        do {
            let setClauses = try edits.map { edit -> String in
                guard edit.columnIndex < cols.count else {
                    throw RecordValueError.invalidValue(column: edit.columnName, expected: "a valid table column")
                }
                parameters.append(try edit.boundValue())
                return "\(connection.quotedIdentifier(cols[edit.columnIndex].name)) = \(connection.parameterPlaceholder(at: parameters.count))"
            }.joined(separator: ", ")

            // The optimistic row identity, shared with the pasted range and with deletion.
            let identity = try RowMutationSQL.identityPredicate(
                columns: cols,
                row: result.rows[rowIndex],
                identifierQuote: connection.identifierQuoteCharacter,
                dialect: connection.dialect,
                parameterOffset: parameters.count
            )
            parameters.append(contentsOf: identity.parameters)
            predicateShape = identity.auditShape

            let sql = "UPDATE \(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table)) SET \(setClauses) WHERE \(identity.sql)"
            try await connection.beginTransaction()
            transactionStarted = true
            let updateResult = try await connection.execute(sql, parameters: parameters)
            if let serverError = updateResult.error { throw MutationExecutionError.server(serverError) }
            guard updateResult.affectedRows == 1 else {
                throw MutationExecutionError.affectedRows(expected: 1, actual: updateResult.affectedRows)
            }
            commitAttempted = true
            try await connection.commitTransaction()
            transactionStarted = false
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "update",
                source: "record-editor",
                outcome: .committed,
                affectedRows: updateResult.affectedRows,
                predicate: predicateShape
            ))
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            withAnimation { showEditor = false }
            await loadData()
        } catch {
            let outcome: MutationOutcome
            if commitAttempted {
                outcome = .serverStateUnknown
            } else if transactionStarted {
                outcome = await rollback(connection) ? .rolledBack : .serverStateUnknown
            } else {
                outcome = .notStarted
            }
            if outcome == .serverStateUnknown {
                sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            }
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "update",
                source: "record-editor",
                outcome: outcome,
                affectedRows: nil,
                predicate: predicateShape
            ))
            errorMessage = "Update failed (\(outcomeDescription(outcome))): \(error.localizedDescription)"
            errorIsQueryFailure = false
        }
    }

    private func applyBatchPaste(_ plan: GridPastePlan) async {
        guard !isAnalysisActive,
              let result,
              let connection = session?.connection else { return }
        let columns = columnMeta.isEmpty ? result.columns : columnMeta
        guard columns.contains(where: \.isPrimaryKey), !plan.rows.isEmpty else {
            errorMessage = "Batch paste was not started because the table has no primary key or the plan is empty."
            errorIsQueryFailure = false
            return
        }

        var transactionStarted = false
        var commitAttempted = false
        var affectedRows: UInt64 = 0
        /// The shape of the last predicate built. Every row in a pasted range is identified the
        /// same way, so one shape describes the batch; on failure it names the row that stopped it.
        var predicateShape: String?
        isLoading = true
        errorMessage = nil
        errorIsQueryFailure = false
        do {
            try await connection.beginTransaction()
            transactionStarted = true
            for rowEdit in plan.rows {
                guard result.rows.indices.contains(rowEdit.rowIndex), !rowEdit.edits.isEmpty else {
                    throw RecordValueError.invalidValue(column: "Paste", expected: "current non-empty target rows")
                }
                var parameters: [DatabaseValue] = []
                let setClauses = try rowEdit.edits.map { edit -> String in
                    guard columns.indices.contains(edit.columnIndex), !columns[edit.columnIndex].isGenerated else {
                        throw RecordValueError.invalidValue(column: edit.columnName, expected: "a writable table column")
                    }
                    parameters.append(try edit.boundValue())
                    return "\(connection.quotedIdentifier(columns[edit.columnIndex].name)) = \(connection.parameterPlaceholder(at: parameters.count))"
                }.joined(separator: ", ")

                let identity = try RowMutationSQL.identityPredicate(
                    columns: columns,
                    row: result.rows[rowEdit.rowIndex],
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect,
                    parameterOffset: parameters.count
                )
                parameters.append(contentsOf: identity.parameters)
                predicateShape = identity.auditShape
                let sql = "UPDATE \(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table)) SET \(setClauses) WHERE \(identity.sql)"
                let updateResult = try await connection.execute(sql, parameters: parameters)
                if let serverError = updateResult.error { throw MutationExecutionError.server(serverError) }
                guard updateResult.affectedRows == 1 else {
                    throw MutationExecutionError.affectedRows(expected: 1, actual: updateResult.affectedRows)
                }
                affectedRows += 1
            }
            commitAttempted = true
            try await connection.commitTransaction()
            transactionStarted = false
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "update-batch",
                source: "grid-paste",
                outcome: .committed,
                affectedRows: affectedRows,
                predicate: predicateShape
            ))
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            await loadData()
        } catch {
            let outcome: MutationOutcome
            if commitAttempted {
                outcome = .serverStateUnknown
            } else if transactionStarted {
                outcome = await rollback(connection) ? .rolledBack : .serverStateUnknown
            } else {
                outcome = .notStarted
            }
            if outcome == .serverStateUnknown {
                sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            }
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "update-batch",
                source: "grid-paste",
                outcome: outcome,
                affectedRows: affectedRows,
                predicate: predicateShape
            ))
            errorMessage = "Batch paste failed after \(affectedRows) row(s) (\(outcomeDescription(outcome))): \(error.localizedDescription)"
            errorIsQueryFailure = false
            isLoading = false
        }
    }

    // MARK: - Foreign-Key Navigation

    /// Loaded beside the column metadata, and non-fatal: a table still browses when the account
    /// cannot read the catalog. Refusing to show data because a *navigation affordance* could not
    /// be built would be the wrong trade.
    private func loadForeignKeyRelationships(force: Bool = false) async {
        guard isTableContext, let connection = session?.connection else {
            foreignKeyRelationships = []
            foreignKeysLoadedFor = nil
            return
        }
        let token = "\(database).\(table)"
        guard force || foreignKeysLoadedFor != token else { return }
        foreignKeysLoadedFor = token
        do {
            foreignKeyRelationships = ForeignKeyNavigation.relationships(
                from: try await connection.foreignKeys(in: table, database: database)
            )
        } catch {
            foreignKeyRelationships = []
            // Retry on the next load rather than remembering a failure as "this table has none".
            foreignKeysLoadedFor = nil
        }
    }

    private func canFollow(_ relationship: ForeignKeyRelationship, from rowIndex: Int) -> Bool {
        guard let result, result.rows.indices.contains(rowIndex) else { return false }
        return relationship.pairs.allSatisfy { pair in
            guard let index = columnsForMutation.firstIndex(where: { $0.name == pair.column }),
                  index < result.rows[rowIndex].count else { return false }
            return !result.rows[rowIndex][index].isNull
        }
    }

    /// Opens the referenced table showing the referenced row.
    ///
    /// The referenced table's own columns are fetched first so the filter is parsed against the
    /// type the *target* declares (D17) rather than the type of the column being left.
    private func followForeignKey(_ relationship: ForeignKeyRelationship, from rowIndex: Int) async {
        guard let result, result.rows.indices.contains(rowIndex),
              let connection = session?.connection else { return }
        do {
            let referencedColumns = try await connection.columns(in: relationship.referencedTable,
                                                                 database: database)
            let newFilters = try ForeignKeyNavigation.filters(
                following: relationship,
                row: result.rows[rowIndex],
                columns: columnsForMutation,
                referencedColumns: referencedColumns,
                dialect: session?.connection?.dialect
            )
            ForeignKeyFilterHandoff.stage(newFilters, for: .init(sessionID: sessionID,
                                                                 database: database,
                                                                 table: relationship.referencedTable))
            NotificationCenter.default.post(
                name: .glassdbOpenTable,
                object: OpenTableRequest(sessionID: sessionID,
                                         database: database,
                                         table: relationship.referencedTable)
            )
        } catch {
            errorMessage = error.localizedDescription
            errorIsQueryFailure = false
        }
    }

    /// Takes filters staged for this table by a foreign-key follow, if any are waiting.
    /// Returns whether anything was applied, so the caller can decide about reloading.
    @discardableResult
    private func claimStagedForeignKeyFilters() -> Bool {
        guard isTableContext,
              let staged = ForeignKeyFilterHandoff.claim(.init(sessionID: sessionID,
                                                               database: database,
                                                               table: table)) else { return false }
        filters = staged
        displayFilters = []
        currentPage = 1
        totalRowCount = nil
        clearGridSelection()
        persistGridQueryState()
        return true
    }

    @ViewBuilder
    private func followReferenceMenu(for rowIndex: Int) -> some View {
        if isTableContext, !isAnalysisActive, !foreignKeyRelationships.isEmpty {
            Menu("Follow Reference", systemImage: "arrow.triangle.turn.up.right.diamond") {
                ForEach(foreignKeyRelationships) { relationship in
                    Button(relationship.summary) {
                        Task { await followForeignKey(relationship, from: rowIndex) }
                    }
                    .disabled(!canFollow(relationship, from: rowIndex))
                    .accessibilityIdentifier("db-row-menu-follow-\(relationship.constraintName)")
                }
            }
            .accessibilityIdentifier("db-row-menu-follow")
        }
    }

    // MARK: - Delete Rows

    /// Rows the current selection can delete: a table context, not an aggregate projection,
    /// and every selected index still present in the loaded page.
    private var deletableSelectedRowIndices: [Int] {
        guard isTableContext, !isAnalysisActive, let result else { return [] }
        return selectedRowIndices.sorted().filter { result.rows.indices.contains($0) }
    }

    private var canDeleteSelectedRows: Bool {
        !deletableSelectedRowIndices.isEmpty && columnsForMutation.contains(where: \.isPrimaryKey)
    }

    /// `columnMeta` is the table's real schema and carries primary-key flags; a free-form result's
    /// columns do not. The write paths have always preferred it and fallen back to the result.
    private var columnsForMutation: [ColumnInfo] {
        guard let result else { return columnMeta }
        return columnMeta.isEmpty ? result.columns : columnMeta
    }

    private func deleteRowMenuTitle(for rowIndex: Int) -> String {
        let count = selectedRowIndices.contains(rowIndex) ? deletableSelectedRowIndices.count : 1
        return count == 1 ? "Delete Row…" : "Delete \(count) Rows…"
    }

    /// Says why the control is unavailable rather than leaving a dimmed button unexplained.
    /// Read-only services are deliberately *not* mentioned here: the refusal belongs on the
    /// connection (D15), and a UI that pre-judges it would be a second, untested opinion.
    private var deleteControlHelp: String {
        if !isTableContext {
            return "Deletion is available from a table tab, where rows have a known identity"
        }
        if isAnalysisActive {
            return "Deletion is unavailable while a grouped or aggregated projection is shown"
        }
        if !columnsForMutation.contains(where: \.isPrimaryKey) {
            return "This table has no primary key, so a single row cannot be identified safely"
        }
        if deletableSelectedRowIndices.isEmpty {
            return "Select one or more rows to delete"
        }
        let count = deletableSelectedRowIndices.count
        return "Review and delete \(count) selected row\(count == 1 ? "" : "s")"
    }

    private func requestDeleteSelectedRows() {
        let rowIndices = deletableSelectedRowIndices
        guard !rowIndices.isEmpty else { return }
        guard columnsForMutation.contains(where: \.isPrimaryKey) else {
            errorMessage = RowIdentityError.noPrimaryKey.localizedDescription
            errorIsQueryFailure = false
            return
        }
        pendingRecordMutation = .delete(rowIndices: rowIndices)
    }

    private func requestDeleteRow(_ rowIndex: Int) {
        guard let result, result.rows.indices.contains(rowIndex) else { return }
        selectedRowIndices = [rowIndex]
        rowSelectionAnchor = rowIndex
        selectedRowIndex = rowIndex
        selectionAnchor = nil
        selectionEnd = nil
        requestDeleteSelectedRows()
    }

    /// Deletion, built on the update paths rather than beside them: the same optimistic row
    /// identity (`RowMutationSQL.identityPredicate`), the same exactly-one-affected-row guard, the
    /// same transaction and the same audit record. A row edited by someone else since this page
    /// loaded matches no predicate, reports 0 affected rows and rolls the whole batch back.
    private func deleteRows(_ rowIndices: [Int]) async {
        guard let result, let connection = session?.connection else { return }
        let columns = columnsForMutation
        let targets = rowIndices.filter { result.rows.indices.contains($0) }
        guard !targets.isEmpty else { return }

        var transactionStarted = false
        var commitAttempted = false
        var deletedRows: UInt64 = 0
        /// The shape of the last predicate built, for the audit. Values are never recorded.
        var predicateShape: String?
        isLoading = true
        errorMessage = nil
        errorIsQueryFailure = false
        do {
            try await connection.beginTransaction()
            transactionStarted = true
            for rowIndex in targets {
                let statement = try RowMutationSQL.delete(
                    database: database,
                    table: table,
                    columns: columns,
                    row: result.rows[rowIndex],
                    identifierQuote: connection.identifierQuoteCharacter,
                    dialect: connection.dialect
                )
                predicateShape = statement.predicate.auditShape
                let deleteResult = try await connection.execute(
                    statement.sql,
                    parameters: statement.predicate.parameters
                )
                if let serverError = deleteResult.error { throw MutationExecutionError.server(serverError) }
                guard deleteResult.affectedRows == 1 else {
                    throw MutationExecutionError.affectedRows(expected: 1, actual: deleteResult.affectedRows)
                }
                deletedRows += 1
            }
            commitAttempted = true
            try await connection.commitTransaction()
            transactionStarted = false
            recordDeleteAudit(outcome: .committed, affectedRows: deletedRows, predicate: predicateShape)
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            clearGridSelection()
            selectedRowIndex = nil
            showEditor = false
            totalRowCount = nil
            await loadData()
        } catch {
            let outcome: MutationOutcome
            if commitAttempted {
                outcome = .serverStateUnknown
            } else if transactionStarted {
                outcome = await rollback(connection) ? .rolledBack : .serverStateUnknown
            } else {
                outcome = .notStarted
            }
            if outcome == .serverStateUnknown {
                sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            }
            recordDeleteAudit(outcome: outcome, affectedRows: deletedRows, predicate: predicateShape)
            errorMessage = "Delete failed after \(deletedRows) row(s) (\(outcomeDescription(outcome))): \(error.localizedDescription)"
            errorIsQueryFailure = false
            isLoading = false
        }
    }

    private func recordDeleteAudit(outcome: MutationOutcome, affectedRows: UInt64,
                                   predicate: String?) {
        MutationAuditStore.append(MutationAuditRecord(
            connectionID: session?.connectionConfig.id ?? sessionID,
            database: database,
            object: table,
            normalizedOperation: "delete",
            source: "grid-delete",
            outcome: outcome,
            affectedRows: affectedRows,
            predicate: predicate
        ))
    }

    // MARK: - Insert Row

    private func insertRow(_ edits: [StagedEdit]) async {
        let cols = columnMeta
        guard let connection = session?.connection else { return }
        guard !cols.isEmpty else {
            errorMessage = "Cannot insert: no column metadata"
            errorIsQueryFailure = false
            return
        }

        var transactionStarted = false
        var commitAttempted = false
        do {
            let usableEdits = edits.filter { !$0.useDefault }
            let sql: String
            var parameters: [DatabaseValue] = []
            if usableEdits.isEmpty {
                let tableName = "\(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table))"
                sql = connection.dialect == .mysql
                    ? "INSERT INTO \(tableName) () VALUES ()"
                    : "INSERT INTO \(tableName) DEFAULT VALUES"
            } else {
                let columnNames = try usableEdits.map { edit -> String in
                    guard edit.columnIndex < cols.count else {
                        throw RecordValueError.invalidValue(column: edit.columnName, expected: "a valid table column")
                    }
                    parameters.append(try edit.boundValue())
                    return connection.quotedIdentifier(cols[edit.columnIndex].name)
                }.joined(separator: ", ")
                let placeholders = (1...parameters.count)
                    .map(connection.parameterPlaceholder(at:))
                    .joined(separator: ", ")
                sql = "INSERT INTO \(connection.quotedIdentifier(database)).\(connection.quotedIdentifier(table)) (\(columnNames)) VALUES (\(placeholders))"
            }

            try await connection.beginTransaction()
            transactionStarted = true
            let insertResult = try await connection.execute(sql, parameters: parameters)
            if let serverError = insertResult.error { throw MutationExecutionError.server(serverError) }
            guard insertResult.affectedRows == 1 else {
                throw MutationExecutionError.affectedRows(expected: 1, actual: insertResult.affectedRows)
            }
            commitAttempted = true
            try await connection.commitTransaction()
            transactionStarted = false
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "insert",
                source: "record-editor",
                outcome: .committed,
                affectedRows: insertResult.affectedRows
            ))
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            addingNewRow = false
            totalRowCount = nil
            await loadData()
        } catch {
            let outcome: MutationOutcome
            if commitAttempted {
                outcome = .serverStateUnknown
            } else if transactionStarted {
                outcome = await rollback(connection) ? .rolledBack : .serverStateUnknown
            } else {
                outcome = .notStarted
            }
            if outcome == .serverStateUnknown {
                sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            }
            MutationAuditStore.append(MutationAuditRecord(
                connectionID: session?.connectionConfig.id ?? sessionID,
                database: database,
                object: table,
                normalizedOperation: "insert",
                source: "record-editor",
                outcome: outcome,
                affectedRows: nil
            ))
            errorMessage = "Insert failed (\(outcomeDescription(outcome))): \(error.localizedDescription)"
            errorIsQueryFailure = false
        }
    }

    private func rollback(_ connection: any DatabaseConnection) async -> Bool {
        do {
            try await connection.rollbackTransaction()
            return true
        } catch {
            return false
        }
    }

    private func outcomeDescription(_ outcome: MutationOutcome) -> String {
        switch outcome {
        case .committed: return "committed"
        case .rolledBack: return "rolled back"
        case .serverStateUnknown: return "server state unknown; refresh before retrying"
        case .notStarted: return "not started"
        }
    }
}

// MARK: - Table Schema Editing

enum TableSchemaEditError: LocalizedError, Equatable {
    case invalidIdentifier(String)
    case invalidType(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let value):
            "‘\(value)’ is not a valid database identifier."
        case .invalidType(let value):
            "‘\(value)’ is not a safe SQL type expression."
        case .unsupported(let message):
            message
        }
    }
}

enum TableColumnDefaultMode: String, CaseIterable, Identifiable {
    case keep = "Keep Current"
    case none = "No Default"
    case null = "NULL"
    case literal = "Literal Value"
    case currentTimestamp = "Current Timestamp"

    var id: Self { self }
}

enum TableSchemaSQL {
    static func addColumn(
        database: String,
        table: String,
        name: String,
        type: String,
        nullable: Bool,
        quoteCharacter: Character
    ) throws -> String {
        let column = try identifier(name, quoteCharacter: quoteCharacter)
        let sqlType = try validatedType(type)
        let nullability = nullable ? "NULL" : "NOT NULL"
        return "ALTER TABLE \(try object(database, table, quoteCharacter: quoteCharacter)) ADD COLUMN \(column) \(sqlType) \(nullability)"
    }

    static func renameColumn(
        database: String,
        table: String,
        oldName: String,
        newName: String,
        quoteCharacter: Character
    ) throws -> String {
        "ALTER TABLE \(try object(database, table, quoteCharacter: quoteCharacter)) RENAME COLUMN \(try identifier(oldName, quoteCharacter: quoteCharacter)) TO \(try identifier(newName, quoteCharacter: quoteCharacter))"
    }

    static func dropColumn(
        database: String,
        table: String,
        name: String,
        quoteCharacter: Character
    ) throws -> String {
        "ALTER TABLE \(try object(database, table, quoteCharacter: quoteCharacter)) DROP COLUMN \(try identifier(name, quoteCharacter: quoteCharacter))"
    }

    static func alterColumn(
        database: String,
        table: String,
        original: ColumnInfo,
        name: String,
        type: String,
        nullable: Bool,
        unsigned: Bool,
        defaultMode: TableColumnDefaultMode,
        defaultLiteral: String,
        dialect: DatabaseDialect,
        quoteCharacter: Character
    ) throws -> [String] {
        let target = try object(database, table, quoteCharacter: quoteCharacter)
        let oldName = try identifier(original.name, quoteCharacter: quoteCharacter)
        let newName = try identifier(name, quoteCharacter: quoteCharacter)
        let sqlType = try validatedType(type)
        let normalizedOriginalType = original.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNewType = sqlType.trimmingCharacters(in: .whitespacesAndNewlines)
        let renamed = name.trimmingCharacters(in: .whitespacesAndNewlines) != original.name
        let definitionChanged = normalizedNewType.caseInsensitiveCompare(normalizedOriginalType) != .orderedSame
            || nullable != original.isNullable
            || unsigned != original.isUnsigned
            || defaultMode != .keep

        guard renamed || definitionChanged else {
            throw TableSchemaEditError.unsupported("Change at least one column setting before reviewing SQL.")
        }
        if original.isGenerated, definitionChanged {
            throw TableSchemaEditError.unsupported(
                "Generated expressions are managed in DDL. This editor can safely rename the column, then open the table definition in SQL for expression changes."
            )
        }
        if nullable, original.isPrimaryKey {
            throw TableSchemaEditError.unsupported(
                "Primary-key columns cannot allow NULL values. Change the primary key in Indexes before changing nullability."
            )
        }
        if unsigned, dialect != .mysql {
            throw TableSchemaEditError.unsupported("Unsigned numeric columns are supported only by MySQL.")
        }

        switch dialect {
        case .sqlite:
            guard !definitionChanged else {
                throw TableSchemaEditError.unsupported(
                    "SQLite requires a table-rebuild migration to change a column type, nullability, or default. Rename-only changes can be applied here; open the DDL in SQL for a reviewed rebuild migration."
                )
            }
            return ["ALTER TABLE \(target) RENAME COLUMN \(oldName) TO \(newName)"]

        case .mysql:
            if !definitionChanged {
                return ["ALTER TABLE \(target) RENAME COLUMN \(oldName) TO \(newName)"]
            }
            let nullability = nullable ? "NULL" : "NOT NULL"
            let unsignedClause = unsigned ? " UNSIGNED" : ""
            let defaultClause = try mysqlDefaultClause(
                mode: defaultMode,
                literal: defaultLiteral,
                original: original,
                newType: sqlType,
                nullable: nullable
            )
            return [
                "ALTER TABLE \(target) CHANGE COLUMN \(oldName) \(newName) \(sqlType)\(unsignedClause) \(nullability)\(defaultClause)"
            ]

        case .postgresql:
            var statements: [String] = []
            var currentName = oldName
            if renamed {
                statements.append("ALTER TABLE \(target) RENAME COLUMN \(oldName) TO \(newName)")
                currentName = newName
            }
            if normalizedNewType.caseInsensitiveCompare(normalizedOriginalType) != .orderedSame {
                statements.append("ALTER TABLE \(target) ALTER COLUMN \(currentName) TYPE \(sqlType)")
            }
            if nullable != original.isNullable {
                let action = nullable ? "DROP NOT NULL" : "SET NOT NULL"
                statements.append("ALTER TABLE \(target) ALTER COLUMN \(currentName) \(action)")
            }
            if defaultMode != .keep {
                let action = try postgresDefaultAction(
                    mode: defaultMode,
                    literal: defaultLiteral,
                    type: sqlType,
                    nullable: nullable
                )
                statements.append("ALTER TABLE \(target) ALTER COLUMN \(currentName) \(action)")
            }
            return statements
        }
    }

    static func createIndex(
        database: String,
        table: String,
        name: String,
        columns: [String],
        unique: Bool,
        dialect: DatabaseDialect,
        quoteCharacter: Character
    ) throws -> String {
        guard !columns.isEmpty else { throw TableSchemaEditError.invalidIdentifier("No columns selected") }
        let quotedColumns = try columns.map { try identifier($0, quoteCharacter: quoteCharacter) }
        let index = try identifier(name, quoteCharacter: quoteCharacter)
        let target: String
        let indexTarget: String
        if dialect == .sqlite {
            target = try identifier(table, quoteCharacter: quoteCharacter)
            indexTarget = "\(try identifier(database, quoteCharacter: quoteCharacter)).\(index)"
        } else {
            target = try object(database, table, quoteCharacter: quoteCharacter)
            indexTarget = index
        }
        let uniqueness = unique ? "UNIQUE " : ""
        return "CREATE \(uniqueness)INDEX \(indexTarget) ON \(target) (\(quotedColumns.joined(separator: ", ")))"
    }

    static func dropIndex(
        database: String,
        table: String,
        name: String,
        dialect: DatabaseDialect,
        quoteCharacter: Character
    ) throws -> String {
        let index = try identifier(name, quoteCharacter: quoteCharacter)
        switch dialect {
        case .mysql:
            return "DROP INDEX \(index) ON \(try object(database, table, quoteCharacter: quoteCharacter))"
        case .postgresql, .sqlite:
            return "DROP INDEX \(try identifier(database, quoteCharacter: quoteCharacter)).\(index)"
        }
    }

    static func addForeignKey(
        database: String,
        table: String,
        name: String,
        column: String,
        referencedTable: String,
        referencedColumn: String,
        dialect: DatabaseDialect,
        quoteCharacter: Character
    ) throws -> String {
        guard dialect != .sqlite else {
            throw TableSchemaEditError.unsupported("SQLite requires a table-rebuild migration to add a foreign key.")
        }
        return "ALTER TABLE \(try object(database, table, quoteCharacter: quoteCharacter)) ADD CONSTRAINT \(try identifier(name, quoteCharacter: quoteCharacter)) FOREIGN KEY (\(try identifier(column, quoteCharacter: quoteCharacter))) REFERENCES \(try object(database, referencedTable, quoteCharacter: quoteCharacter)) (\(try identifier(referencedColumn, quoteCharacter: quoteCharacter)))"
    }

    static func dropForeignKey(
        database: String,
        table: String,
        name: String,
        dialect: DatabaseDialect,
        quoteCharacter: Character
    ) throws -> String {
        guard dialect != .sqlite else {
            throw TableSchemaEditError.unsupported("SQLite requires a table-rebuild migration to remove a foreign key.")
        }
        let action = dialect == .mysql ? "DROP FOREIGN KEY" : "DROP CONSTRAINT"
        return "ALTER TABLE \(try object(database, table, quoteCharacter: quoteCharacter)) \(action) \(try identifier(name, quoteCharacter: quoteCharacter))"
    }

    private static func mysqlDefaultClause(
        mode: TableColumnDefaultMode,
        literal: String,
        original: ColumnInfo,
        newType: String,
        nullable: Bool
    ) throws -> String {
        switch mode {
        case .keep:
            guard let existing = original.defaultValue else { return "" }
            return " DEFAULT \(try existingDefaultExpression(existing, type: original.type))"
        case .none:
            return ""
        case .null:
            guard nullable else {
                throw TableSchemaEditError.unsupported("A required column cannot use NULL as its default.")
            }
            return " DEFAULT NULL"
        case .literal:
            return " DEFAULT \(try literalExpression(literal, type: newType))"
        case .currentTimestamp:
            guard isTemporalType(newType) else {
                throw TableSchemaEditError.unsupported("CURRENT_TIMESTAMP requires a temporal column type.")
            }
            return " DEFAULT CURRENT_TIMESTAMP"
        }
    }

    private static func postgresDefaultAction(
        mode: TableColumnDefaultMode,
        literal: String,
        type: String,
        nullable: Bool
    ) throws -> String {
        switch mode {
        case .keep:
            return ""
        case .none:
            return "DROP DEFAULT"
        case .null:
            guard nullable else {
                throw TableSchemaEditError.unsupported("A required column cannot use NULL as its default.")
            }
            return "SET DEFAULT NULL"
        case .literal:
            return "SET DEFAULT \(try literalExpression(literal, type: type))"
        case .currentTimestamp:
            guard isTemporalType(type) else {
                throw TableSchemaEditError.unsupported("CURRENT_TIMESTAMP requires a temporal column type.")
            }
            return "SET DEFAULT CURRENT_TIMESTAMP"
        }
    }

    private static func existingDefaultExpression(_ value: String, type: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        // **This string comes from the server**, not the operator: it is
        // `INFORMATION_SCHEMA.COLUMNS.COLUMN_DEFAULT`, copied verbatim by the adapter
        // (`MySQLAdapter.swift:624`). Anyone with DDL rights on a table the operator later opens
        // chooses it, so this is a trust boundary and the three shapes below were all returned
        // unchecked: `CURRENT_TIMESTAMP, DROP COLUMN secret` matched the prefix test, and
        // `(1), DROP COLUMN secret, ADD pad int DEFAULT (1)` starts with `(` and ends with `)`.
        // The route is ordinary — `beginEditing` sets the default behaviour to **Keep Current**,
        // so it is reached by opening the column editor and applying any change at all.
        if upper == "NULL" {
            return trimmed
        }
        if (upper.hasPrefix("CURRENT_TIMESTAMP") && isTemporalType(type))
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) {
            return try rejectingClauseEscape(trimmed, type: type)
        }
        return try literalExpression(trimmed, type: type)
    }

    /// Refuses a default expression that could close its own clause and begin another.
    ///
    /// `ALTER TABLE … SET DEFAULT <expr>` is one statement, so neither of the protocol-level
    /// protections applies: mysql-nio omits `CLIENT_MULTI_STATEMENTS` and PostgresNIO's extended
    /// protocol refuses multi-statement strings — but a **comma** needs neither. `0, DROP COLUMN
    /// secret` stays a single `ALTER TABLE` with a second clause bolted on.
    ///
    /// `validatedType` has enforced exactly this rule for column *types* since it was written
    /// (a comma is legal only inside parentheses); default expressions were simply never given the
    /// same treatment.
    ///
    /// **Backslashes are deliberately not treated as escapes inside quotes.** PostgreSQL with
    /// `standard_conforming_strings` on — the default since 9.1 — ends the string at `\'`, and so
    /// does MySQL under `NO_BACKSLASH_ESCAPES`. Honouring the escape would leave this scanner
    /// believing it is still inside a literal while the server has already left it, which is the
    /// dangerous direction; ending the string early can only make this stricter.
    private static func rejectingClauseEscape(_ expression: String, type: String) throws -> String {
        let characters = Array(expression)
        var depth = 0
        var quote: Character?
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if let active = quote {
                if character == active {
                    // A doubled quote is an escaped quote in both engines.
                    if index + 1 < characters.count, characters[index + 1] == active {
                        index += 2
                        continue
                    }
                    quote = nil
                }
                index += 1
                continue
            }
            switch character {
            case "'", "\"", "`":
                quote = character
            case "(":
                depth += 1
            case ")":
                depth -= 1
                guard depth >= 0 else { throw TableSchemaEditError.unsupported(defaultRefusal(type)) }
            case ",", ";":
                guard depth > 0 else { throw TableSchemaEditError.unsupported(defaultRefusal(type)) }
            default:
                break
            }
            index += 1
        }
        guard depth == 0, quote == nil else {
            throw TableSchemaEditError.unsupported(defaultRefusal(type))
        }
        guard !expression.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw TableSchemaEditError.unsupported(defaultRefusal(type))
        }
        return expression
    }

    private static func defaultRefusal(_ type: String) -> String {
        "The default for \(type) is not a single value or expression. Remove anything after it."
    }

    /// The whole string must be the number — not a prefix of it.
    ///
    /// `Decimal(string:)` parses a leading number and ignores the rest, so it answers non-nil for
    /// `0, DROP COLUMN secret`, `1; DROP TABLE t --`, `0 OR 1=1` and `0x41`. Guarding on it and then
    /// emitting the ORIGINAL string verbatim is what made a numeric default an injection point.
    private static func isEntirelyNumeric(_ value: String) -> Bool {
        var scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        if scalars[0] == "+" || scalars[0] == "-" { scalars.removeFirst() }
        guard !scalars.isEmpty else { return false }

        var digits = 0, points = 0, exponents = 0, index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.decimalDigits.contains(scalar) {
                digits += 1
            } else if scalar == "." {
                points += 1
                guard points == 1, exponents == 0 else { return false }
            } else if scalar == "e" || scalar == "E" {
                exponents += 1
                guard exponents == 1, digits > 0, index + 1 < scalars.count else { return false }
                let next = scalars[index + 1]
                if next == "+" || next == "-" {
                    guard index + 2 < scalars.count else { return false }
                    index += 1
                }
            } else {
                return false
            }
            index += 1
        }
        return digits > 0
    }

    private static func literalExpression(_ value: String, type: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TableSchemaEditError.unsupported("Enter a default literal before reviewing SQL.")
        }
        if isNumericType(type) {
            guard isEntirelyNumeric(trimmed) else {
                throw TableSchemaEditError.unsupported("The default must be a valid number for \(type).")
            }
            return trimmed
        }
        if isBooleanType(type) {
            switch trimmed.lowercased() {
            case "true", "1": return "TRUE"
            case "false", "0": return "FALSE"
            default:
                throw TableSchemaEditError.unsupported("The default must be true, false, 1, or 0 for \(type).")
            }
        }
        return "'\(trimmed.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func baseType(_ type: String) -> String {
        type.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: { $0 == "(" || $0.isWhitespace })
            .first
            .map(String.init)?
            .lowercased() ?? ""
    }

    private static func isNumericType(_ type: String) -> Bool {
        ["tinyint", "smallint", "mediumint", "int", "integer", "bigint", "decimal", "numeric", "float", "double", "real"]
            .contains(baseType(type))
    }

    private static func isBooleanType(_ type: String) -> Bool {
        ["bool", "boolean"].contains(baseType(type))
    }

    private static func isTemporalType(_ type: String) -> Bool {
        ["timestamp", "datetime", "date", "time"].contains(baseType(type))
    }

    private static func object(
        _ database: String,
        _ table: String,
        quoteCharacter: Character
    ) throws -> String {
        "\(try identifier(database, quoteCharacter: quoteCharacter)).\(try identifier(table, quoteCharacter: quoteCharacter))"
    }

    private static func identifier(_ value: String, quoteCharacter: Character) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 256,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw TableSchemaEditError.invalidIdentifier(value)
        }
        let quote = String(quoteCharacter)
        return "\(quote)\(trimmed.replacingOccurrences(of: quote, with: quote + quote))\(quote)"
    }

    private static func validatedType(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "\"",
              trimmed.utf8.count <= 2_048,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw TableSchemaEditError.invalidType(value)
        }

        let characters = Array(trimmed)
        var parenthesisDepth = 0
        var bracketDepth = 0
        var quote: Character?
        var topLevel = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                if character == "\\", activeQuote == "'", index + 1 < characters.count {
                    index += 2
                    continue
                }
                if character == activeQuote {
                    if index + 1 < characters.count, characters[index + 1] == activeQuote {
                        index += 2
                        continue
                    }
                    quote = nil
                }
                index += 1
                continue
            }

            if character == "'" {
                guard parenthesisDepth > 0 else { throw TableSchemaEditError.invalidType(value) }
                quote = character
            } else if character == "\"" {
                quote = character
            } else if character == "(" {
                parenthesisDepth += 1
                if parenthesisDepth == 1 { topLevel.append(" ") }
            } else if character == ")" {
                parenthesisDepth -= 1
                guard parenthesisDepth >= 0 else { throw TableSchemaEditError.invalidType(value) }
            } else if character == "[" {
                guard parenthesisDepth == 0 else { throw TableSchemaEditError.invalidType(value) }
                bracketDepth += 1
            } else if character == "]" {
                bracketDepth -= 1
                guard parenthesisDepth == 0, bracketDepth >= 0 else {
                    throw TableSchemaEditError.invalidType(value)
                }
            } else if character == "," {
                guard parenthesisDepth > 0 else { throw TableSchemaEditError.invalidType(value) }
            } else {
                let scalarIsAllowed = character.unicodeScalars.allSatisfy {
                    CharacterSet.alphanumerics.contains($0)
                        || CharacterSet.whitespaces.contains($0)
                        || $0 == "_"
                        || $0 == "."
                }
                guard scalarIsAllowed else { throw TableSchemaEditError.invalidType(value) }
                if parenthesisDepth == 0 { topLevel.append(character) }
            }
            index += 1
        }

        guard quote == nil, parenthesisDepth == 0, bracketDepth == 0 else {
            throw TableSchemaEditError.invalidType(value)
        }

        let constraintKeywords: Set<String> = [
            "ADD", "ALTER", "AUTO_INCREMENT", "CHECK", "COLLATE", "COLUMN", "COMMENT",
            "CONSTRAINT", "DEFAULT", "DROP", "GENERATED", "KEY", "NOT", "NULL",
            "PRIMARY", "REFERENCES", "UNIQUE", "UNSIGNED"
        ]
        let topLevelWords = topLevel
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { $0.uppercased() }
        guard !topLevelWords.contains(where: constraintKeywords.contains) else {
            throw TableSchemaEditError.invalidType(value)
        }
        return trimmed
    }
}

private struct TableSchemaChange: Identifiable {
    let id = UUID()
    let title: String
    let operation: String
    let statements: [String]
    let destructive: Bool

    var sql: String { statements.joined(separator: ";\n") }

    init(title: String, operation: String, sql: String, destructive: Bool) {
        self.title = title
        self.operation = operation
        self.statements = [sql]
        self.destructive = destructive
    }

    init(title: String, operation: String, statements: [String], destructive: Bool) {
        self.title = title
        self.operation = operation
        self.statements = statements
        self.destructive = destructive
    }
}

private struct TableSchemaChangeFailure: Identifiable {
    let id = UUID()
    let error: String
    let sql: String
}

private struct TableSchemaMutationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct TableSchemaChangeSheet: View {
    let change: TableSchemaChange
    let engineName: String
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(
                    change.destructive ? "This change can remove stored data." : "Review the generated SQL before applying it.",
                    systemImage: change.destructive ? "exclamationmark.triangle.fill" : "checkmark.shield"
                )
                .foregroundStyle(change.destructive ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))

                Text(change.sql)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("\(engineName) controls DDL transaction behavior. \(GlassProduct.displayName) will refresh this tool after the server accepts the change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(change.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", role: change.destructive ? .destructive : nil) {
                        dismiss()
                        onApply()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}

@MainActor
private func applyTableSchemaChange(
    _ change: TableSchemaChange,
    session: DatabaseSession,
    database: String,
    table: String
) async throws {
    guard let connection = session.connection else {
        throw TableSchemaEditError.unsupported("The database session is disconnected.")
    }
    var transactionStarted = false
    var outcome: MutationOutcome = .serverStateUnknown
    do {
        if change.statements.count > 1, connection.capabilities.contains(.transactions) {
            try await connection.beginTransaction()
            transactionStarted = true
        }
        var affectedRows: UInt64?
        for statement in change.statements {
            let result = try await connection.execute(statement, parameters: [])
            if let serverError = result.error {
                throw TableSchemaMutationFailure(message: serverError)
            }
            affectedRows = result.affectedRows ?? affectedRows
        }
        if transactionStarted {
            try await connection.commitTransaction()
        }
        outcome = .committed
        MutationAuditStore.append(MutationAuditRecord(
            connectionID: session.connectionConfig.id,
            database: database,
            object: table,
            normalizedOperation: change.operation,
            source: "table-tools",
            outcome: .committed,
            affectedRows: affectedRows
        ))
    } catch {
        if transactionStarted {
            do {
                try await connection.rollbackTransaction()
                outcome = .rolledBack
            } catch {
                outcome = .serverStateUnknown
            }
        }
        MutationAuditStore.append(MutationAuditRecord(
            connectionID: session.connectionConfig.id,
            database: database,
            object: table,
            normalizedOperation: change.operation,
            source: "table-tools",
            outcome: outcome,
            affectedRows: nil
        ))
        throw error
    }
}

// MARK: - Structure Tab

struct StructureTabView: View {
    let sessionID: UUID
    let database: String
    let table: String
    var onOpenSQL: (() -> Void)?

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @State private var columns: [ColumnInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddColumn = false
    @State private var newColumnName = ""
    @State private var newColumnType = "VARCHAR(255)"
    @State private var newColumnNullable = true
    @State private var columnDraftError: String?
    @State private var editingColumn: ColumnInfo?
    @State private var editedColumnName = ""
    @State private var editedColumnType = ""
    @State private var editedColumnNullable = true
    @State private var editedColumnUnsigned = false
    @State private var editedDefaultMode: TableColumnDefaultMode = .keep
    @State private var editedDefaultLiteral = ""
    @State private var pendingChange: TableSchemaChange?
    @State private var changeFailure: TableSchemaChangeFailure?
    @State private var isApplyingChange = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolHeader
            Divider()

            if isLoading {
                ProgressView("Loading structure...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Structure Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if columns.isEmpty {
                ContentUnavailableView("No Columns", systemImage: "list.bullet.rectangle", description: Text("Table has no columns."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(columns) { column in
                            HStack(spacing: 14) {
                                Image(systemName: column.isPrimaryKey ? "key.fill" : "rectangle.split.3x1")
                                    .font(.title3)
                                    .foregroundStyle(column.isPrimaryKey ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(column.name)
                                            .font(.system(.body, design: .monospaced, weight: .semibold))
                                        if column.isPrimaryKey {
                                            Text("PRIMARY KEY")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.orange)
                                        }
                                        if column.isGenerated {
                                            Text("GENERATED")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack(spacing: 10) {
                                        Text(column.type)
                                            .font(.callout)
                                        Text(column.isNullable ? "Nullable" : "Required")
                                        if let defaultValue = column.defaultValue {
                                            Text("Default \(defaultValue)")
                                        }
                                        Text("Position \(column.ordinalPosition)")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                Menu {
                                    Button("Edit Column…", systemImage: "pencil") {
                                        beginEditing(column)
                                    }
                                    Divider()
                                    Button("Drop Column…", systemImage: "trash", role: .destructive) {
                                        prepareDrop(column)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .help("Column actions for \(column.name)")
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(Rectangle())
                            .onTapGesture { beginEditing(column) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Opens the column definition editor")
                        }
                    }
                    .padding(20)
                }
                .databaseLookScrollEnabled()
            }
        }
        .overlay {
            if isApplyingChange {
                ProgressView("Applying schema change…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task(id: "\(database).\(table)") {
            await loadStructure()
        }
        .sheet(isPresented: $showingAddColumn) { addColumnSheet }
        .sheet(item: $editingColumn) { column in editColumnSheet(column) }
        .sheet(item: $pendingChange) { change in
            TableSchemaChangeSheet(change: change, engineName: session?.connection?.engineName ?? "Database") {
                Task { await apply(change) }
            }
        }
        .sheet(item: $changeFailure) { failure in
            QueryErrorCard(
                error: failure.error,
                query: failure.sql,
                schemaContext: schemaContext,
                aiAssistant: session?.aiAssistant,
                summary: "The database rejected this schema change.",
                offersNotifications: false,
                offersAISuggestion: true,
                onUseSuggestedSQL: { suggestedSQL in
                    NotificationCenter.default.post(
                        name: .glassdbOpenSQLDraft,
                        object: SQLDraftRequest(sessionID: sessionID, sql: suggestedSQL)
                    )
                    changeFailure = nil
                    onOpenSQL?()
                },
                onDismiss: { changeFailure = nil }
            )
            .padding(24)
            .frame(minWidth: 580, minHeight: 360)
        }
    }

    private var toolHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Columns").font(.headline)
                Text("\(columns.count) column\(columns.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadStructure() } }
                .labelStyle(.iconOnly)
                .help("Reload columns")
            Button("Add Column", systemImage: "plus") {
                newColumnName = ""
                newColumnType = "VARCHAR(255)"
                newColumnNullable = true
                columnDraftError = nil
                showingAddColumn = true
            }
            .buttonStyle(.borderedProminent)
            .help("Add a column")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var addColumnSheet: some View {
        NavigationStack {
            Form {
                Section("Column") {
                    TextField("Name", text: $newColumnName)
                    TextField("SQL type", text: $newColumnType)
                        .font(.system(.body, design: .monospaced))
                    Toggle("Allow NULL values", isOn: $newColumnNullable)
                }
                Section {
                    Text("Types accept conservative SQL expressions such as VARCHAR(255), BIGINT, DECIMAL(10, 2), or TIMESTAMP WITH TIME ZONE.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let columnDraftError {
                        Label(columnDraftError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Column")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddColumn = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { prepareAddColumn() }
                        .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newColumnType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
    }

    private func editColumnSheet(_ column: ColumnInfo) -> some View {
        NavigationStack {
            Form {
                Section("Definition") {
                    TextField("Name", text: $editedColumnName)
                    TextField("SQL type", text: $editedColumnType)
                        .font(.system(.body, design: .monospaced))
                        .disabled(column.isGenerated)
                        .onChange(of: editedColumnType) { _, _ in
                            if !editedTypeSupportsUnsigned {
                                editedColumnUnsigned = false
                            }
                        }
                    Toggle("Allow NULL values", isOn: $editedColumnNullable)
                        .disabled(column.isPrimaryKey || column.isGenerated)
                    if session?.connection?.dialect == .mysql {
                        Toggle("Unsigned numeric values", isOn: $editedColumnUnsigned)
                            .disabled(column.isGenerated || !editedTypeSupportsUnsigned)
                    }
                }

                Section("Default") {
                    Picker("Behavior", selection: $editedDefaultMode) {
                        ForEach(TableColumnDefaultMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .disabled(column.isGenerated)

                    if editedDefaultMode == .literal {
                        TextField("Literal value", text: $editedDefaultLiteral)
                            .font(.system(.body, design: .monospaced))
                    }

                    LabeledContent("Current default", value: column.defaultValue ?? "None")
                        .foregroundStyle(.secondary)
                }

                Section {
                    if column.isPrimaryKey {
                        Label("Primary-key membership is managed in Indexes. Primary keys remain required here.", systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if column.isGenerated {
                        Label("Generated expressions are protected. Rename here, or open DDL in SQL for expression changes.", systemImage: "curlybraces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let columnDraftError {
                        Label(columnDraftError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit \(column.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingColumn = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { prepareColumnEdit(column) }
                        .disabled(!columnDraftHasChanges || editedColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedColumnType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 470)
    }

    private func loadStructure() async {
        guard let connection = session?.connection else { return }
        isLoading = true
        errorMessage = nil
        do {
            columns = try await connection.columns(in: table, database: database)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func prepareAddColumn() {
        guard let connection = session?.connection else { return }
        do {
            let sql = try TableSchemaSQL.addColumn(
                database: database,
                table: table,
                name: newColumnName,
                type: newColumnType,
                nullable: newColumnNullable,
                quoteCharacter: connection.identifierQuoteCharacter
            )
            showingAddColumn = false
            columnDraftError = nil
            pendingChange = TableSchemaChange(title: "Add Column?", operation: "add-column", sql: sql, destructive: false)
        } catch { columnDraftError = error.localizedDescription }
    }

    private func beginEditing(_ column: ColumnInfo) {
        editedColumnName = column.name
        editedColumnType = column.type
        editedColumnNullable = column.isPrimaryKey ? false : column.isNullable
        editedColumnUnsigned = column.isUnsigned
        editedDefaultMode = .keep
        editedDefaultLiteral = column.defaultValue ?? ""
        columnDraftError = nil
        editingColumn = column
    }

    private var columnDraftHasChanges: Bool {
        guard let column = editingColumn else { return false }
        return editedColumnName.trimmingCharacters(in: .whitespacesAndNewlines) != column.name
            || editedColumnType.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(column.type) != .orderedSame
            || editedColumnNullable != column.isNullable
            || editedColumnUnsigned != column.isUnsigned
            || editedDefaultMode != .keep
    }

    private var editedTypeSupportsUnsigned: Bool {
        let base = editedColumnType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "(" || $0.isWhitespace })
            .first?
            .lowercased() ?? ""
        return ["tinyint", "smallint", "mediumint", "int", "integer", "bigint", "decimal", "numeric", "float", "double", "real"].contains(base)
    }

    private var schemaContext: SchemaContext {
        SchemaContext(
            databaseName: database,
            tables: [
                SchemaContext.TableInfo(
                    name: table,
                    columns: columns.map { SchemaContext.ColumnInfo(name: $0.name, type: $0.type) }
                )
            ]
        )
    }

    private func prepareColumnEdit(_ column: ColumnInfo) {
        guard let connection = session?.connection else { return }
        do {
            let statements = try TableSchemaSQL.alterColumn(
                database: database,
                table: table,
                original: column,
                name: editedColumnName,
                type: editedColumnType,
                nullable: editedColumnNullable,
                unsigned: editedColumnUnsigned,
                defaultMode: editedDefaultMode,
                defaultLiteral: editedDefaultLiteral,
                dialect: connection.dialect,
                quoteCharacter: connection.identifierQuoteCharacter
            )
            let canRemoveData = editedColumnType.caseInsensitiveCompare(column.type) != .orderedSame
                || (column.isNullable && !editedColumnNullable)
            editingColumn = nil
            columnDraftError = nil
            pendingChange = TableSchemaChange(
                title: "Apply Column Changes?",
                operation: "alter-column",
                statements: statements,
                destructive: canRemoveData
            )
        } catch { columnDraftError = error.localizedDescription }
    }

    private func prepareDrop(_ column: ColumnInfo) {
        guard let connection = session?.connection else { return }
        do {
            pendingChange = TableSchemaChange(
                title: "Drop ‘\(column.name)’?",
                operation: "drop-column",
                sql: try TableSchemaSQL.dropColumn(database: database, table: table, name: column.name, quoteCharacter: connection.identifierQuoteCharacter),
                destructive: true
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ change: TableSchemaChange) async {
        guard let session else { return }
        isApplyingChange = true
        errorMessage = nil
        do {
            try await applyTableSchemaChange(change, session: session, database: database, table: table)
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            await loadStructure()
        } catch {
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            changeFailure = TableSchemaChangeFailure(
                error: "The server rejected the schema change. Refresh before retrying if its state may have changed. \(error.localizedDescription)",
                sql: change.sql
            )
        }
        isApplyingChange = false
    }
}

// MARK: - DDL Tab

struct DDLTabView: View {
    let sessionID: UUID
    let database: String
    let table: String
    var onOpenSQL: (() -> Void)?

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var ddl: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Table Definition").font(.headline)
                    Text("Server-generated CREATE TABLE SQL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadDDL() } }
                    .labelStyle(.iconOnly)
                    .help("Reload the table definition")
                if let ddl {
                    Button("Copy", systemImage: "doc.on.doc") { PlatformClipboard.copy(ddl) }
                        .help("Copy the table definition")
                    Button("Open as SQL", systemImage: "arrow.up.doc") {
                        NotificationCenter.default.post(
                            name: .glassdbOpenSQLDraft,
                            object: SQLDraftRequest(sessionID: sessionID, sql: ddl)
                        )
                        onOpenSQL?()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Open this definition in a new SQL tab for review or reuse")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if session?.connection?.capabilities.contains(.createTableDefinition) == false {
                ContentUnavailableView(
                    "Definition Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("\(session?.connection?.engineName ?? "This engine") does not expose a complete CREATE TABLE definition through its metadata API. Use the Structure, Indexes, and Foreign Keys tools to inspect and modify the table.")
                )
            } else if isLoading {
                ProgressView("Loading DDL...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let ddl {
                ScrollView {
                    Text(AttributedString(SQLHighlighter.highlight(ddl)))
                        .font(.system(size: settingsManager.editorFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .databaseCanvasSurface(opacity: settingsManager.windowOpacity, strength: 0.045)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(20)
                }
                .databaseLookScrollEnabled()
            }
        }
        .task(id: "\(database).\(table)") {
            await loadDDL()
        }
    }

    private func loadDDL() async {
        guard let connection = session?.connection,
              connection.capabilities.contains(.createTableDefinition) else { return }
        isLoading = true
        errorMessage = nil
        do {
            ddl = try await connection.showCreateTable(table, database: database)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Indexes Tab

private struct TableIndexGroup: Identifiable {
    let name: String
    let columns: [String]
    let isUnique: Bool
    let isPrimary: Bool
    let type: String
    var id: String { name }
}

struct IndexesTabView: View {
    let sessionID: UUID
    let database: String
    let table: String

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @State private var indexes: [IndexInfo] = []
    @State private var columns: [ColumnInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddIndex = false
    @State private var newIndexName = ""
    @State private var newIndexUnique = false
    @State private var selectedIndexColumns: Set<String> = []
    @State private var pendingChange: TableSchemaChange?
    @State private var isApplyingChange = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    private var indexGroups: [TableIndexGroup] {
        Dictionary(grouping: indexes, by: \.name)
            .map { name, members in
                let ordered = members.sorted { $0.sequenceInIndex < $1.sequenceInIndex }
                return TableIndexGroup(
                    name: name,
                    columns: ordered.map(\.columnName),
                    isUnique: ordered.first?.isUnique == true,
                    isPrimary: ordered.first?.isPrimary == true,
                    type: ordered.first?.type ?? ""
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Indexes").font(.headline)
                    Text("\(indexGroups.count) index\(indexGroups.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadIndexes() } }
                    .labelStyle(.iconOnly)
                    .help("Reload indexes")
                Button("Add Index", systemImage: "plus") {
                    newIndexName = ""
                    newIndexUnique = false
                    selectedIndexColumns = []
                    showingAddIndex = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(columns.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if isLoading {
                ProgressView("Loading indexes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if indexes.isEmpty {
                ContentUnavailableView("No Indexes", systemImage: "arrow.triangle.branch", description: Text("Add an index to accelerate common filters, joins, and sorts."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(indexGroups) { index in
                            HStack(spacing: 14) {
                                Image(systemName: index.isPrimary ? "key.fill" : (index.isUnique ? "checkmark.seal.fill" : "arrow.triangle.branch"))
                                    .font(.title3)
                                    .foregroundStyle(
                                        index.isPrimary
                                            ? AnyShapeStyle(.orange)
                                            : (index.isUnique ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                                    )
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(index.name).font(.system(.body, design: .monospaced, weight: .semibold))
                                        if index.isPrimary {
                                            Text("PRIMARY").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                                        } else if index.isUnique {
                                            Text("UNIQUE").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                                        }
                                    }
                                    Text(index.columns.joined(separator: "  →  "))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(index.type).font(.caption).foregroundStyle(.secondary)
                                if !index.isPrimary && !index.name.lowercased().hasPrefix("sqlite_autoindex_") {
                                    Button(role: .destructive) { prepareDrop(index) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Drop index \(index.name)")
                                }
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(20)
                }
                .databaseLookScrollEnabled()
            }
        }
        .overlay {
            if isApplyingChange {
                ProgressView("Applying index change…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task(id: "\(database).\(table)") {
            await loadIndexes()
        }
        .sheet(isPresented: $showingAddIndex) { addIndexSheet }
        .sheet(item: $pendingChange) { change in
            TableSchemaChangeSheet(change: change, engineName: session?.connection?.engineName ?? "Database") {
                Task { await apply(change) }
            }
        }
    }

    private var addIndexSheet: some View {
        NavigationStack {
            Form {
                Section("Index") {
                    TextField("Name", text: $newIndexName)
                    Toggle("Unique values only", isOn: $newIndexUnique)
                }
                Section("Columns") {
                    ForEach(columns) { column in
                        Button {
                            if selectedIndexColumns.contains(column.name) {
                                selectedIndexColumns.remove(column.name)
                            } else {
                                selectedIndexColumns.insert(column.name)
                            }
                        } label: {
                            HStack {
                                Text(column.name).font(.system(.body, design: .monospaced))
                                Spacer()
                                if selectedIndexColumns.contains(column.name) { Image(systemName: "checkmark") }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Index")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddIndex = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { prepareCreate() }
                        .disabled(newIndexName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIndexColumns.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 420)
    }

    private func loadIndexes() async {
        guard let connection = session?.connection else { return }
        isLoading = true
        errorMessage = nil
        do {
            indexes = try await connection.indexes(in: table, database: database)
            columns = try await connection.columns(in: table, database: database)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func prepareCreate() {
        guard let connection = session?.connection else { return }
        do {
            let orderedColumns = columns.map(\.name).filter(selectedIndexColumns.contains)
            let sql = try TableSchemaSQL.createIndex(
                database: database,
                table: table,
                name: newIndexName,
                columns: orderedColumns,
                unique: newIndexUnique,
                dialect: connection.dialect,
                quoteCharacter: connection.identifierQuoteCharacter
            )
            showingAddIndex = false
            pendingChange = TableSchemaChange(title: "Create Index?", operation: "create-index", sql: sql, destructive: false)
        } catch { errorMessage = error.localizedDescription }
    }

    private func prepareDrop(_ index: TableIndexGroup) {
        guard let connection = session?.connection else { return }
        do {
            pendingChange = TableSchemaChange(
                title: "Drop ‘\(index.name)’?",
                operation: "drop-index",
                sql: try TableSchemaSQL.dropIndex(database: database, table: table, name: index.name, dialect: connection.dialect, quoteCharacter: connection.identifierQuoteCharacter),
                destructive: true
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ change: TableSchemaChange) async {
        guard let session else { return }
        isApplyingChange = true
        errorMessage = nil
        do {
            try await applyTableSchemaChange(change, session: session, database: database, table: table)
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            await loadIndexes()
        } catch {
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            errorMessage = "The server may have changed. Refresh before retrying. \(error.localizedDescription)"
        }
        isApplyingChange = false
    }
}

// MARK: - Foreign Keys Tab

private struct TableForeignKeyGroup: Identifiable {
    let name: String
    let columns: [String]
    let referencedTable: String
    let referencedColumns: [String]
    var id: String { name }
}

struct ForeignKeysTabView: View {
    let sessionID: UUID
    let database: String
    let table: String

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var columns: [ColumnInfo] = []
    @State private var referencedTables: [String] = []
    @State private var referencedColumns: [ColumnInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddForeignKey = false
    @State private var constraintName = ""
    @State private var localColumn = ""
    @State private var referencedTable = ""
    @State private var referencedColumn = ""
    @State private var pendingChange: TableSchemaChange?
    @State private var isApplyingChange = false

    private var session: DatabaseSession? {
        sessionManager.session(for: sessionID)
    }

    private var canAlterForeignKeys: Bool {
        session?.connection?.dialect != .sqlite
    }

    private var foreignKeyGroups: [TableForeignKeyGroup] {
        Dictionary(grouping: foreignKeys, by: \.constraintName)
            .map { name, members in
                let ordered = members.sorted { $0.ordinalPosition < $1.ordinalPosition }
                return TableForeignKeyGroup(
                    name: name,
                    columns: ordered.map(\.columnName),
                    referencedTable: ordered.first?.referencedTable ?? "",
                    referencedColumns: ordered.map(\.referencedColumn)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Foreign Keys").font(.headline)
                    Text("\(foreignKeyGroups.count) relationship\(foreignKeyGroups.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadForeignKeys() } }
                    .labelStyle(.iconOnly)
                    .help("Reload foreign keys")
                Button("Add Foreign Key", systemImage: "plus") { prepareAddSheet() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAlterForeignKeys || columns.isEmpty || referencedTables.isEmpty)
                    .help(canAlterForeignKeys ? "Add a foreign-key constraint" : "SQLite requires a table-rebuild migration for foreign-key changes")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if isLoading {
                ProgressView("Loading foreign keys...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if foreignKeys.isEmpty {
                ContentUnavailableView(
                    "No Foreign Keys",
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    description: Text(canAlterForeignKeys ? "Add a relationship to enforce referential integrity." : "SQLite reports no foreign keys. Adding one requires rebuilding the table in a migration.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(foreignKeyGroups) { key in
                            HStack(spacing: 14) {
                                Image(systemName: "link")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(key.name).font(.system(.body, design: .monospaced, weight: .semibold))
                                    HStack(spacing: 8) {
                                        Text(key.columns.joined(separator: ", "))
                                        Image(systemName: "arrow.right")
                                        Text("\(key.referencedTable).\(key.referencedColumns.joined(separator: ", "))")
                                    }
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    NotificationCenter.default.post(
                                        name: .glassdbOpenTable,
                                        object: OpenTableRequest(sessionID: sessionID,
                                                                 database: database,
                                                                 table: key.referencedTable)
                                    )
                                } label: {
                                    Image(systemName: "arrow.up.forward.square")
                                }
                                .buttonStyle(.borderless)
                                .disabled(key.referencedTable.isEmpty)
                                .help("Open \(key.referencedTable)")
                                .accessibilityLabel("Open \(key.referencedTable)")
                                if canAlterForeignKeys {
                                    Button(role: .destructive) { prepareDrop(key) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Drop foreign key \(key.name)")
                                }
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(20)
                }
                .databaseLookScrollEnabled()
            }
        }
        .overlay {
            if isApplyingChange {
                ProgressView("Applying foreign-key change…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .task(id: "\(database).\(table)") {
            await loadForeignKeys()
        }
        .sheet(isPresented: $showingAddForeignKey) { addForeignKeySheet }
        .sheet(item: $pendingChange) { change in
            TableSchemaChangeSheet(change: change, engineName: session?.connection?.engineName ?? "Database") {
                Task { await apply(change) }
            }
        }
    }

    private var addForeignKeySheet: some View {
        NavigationStack {
            Form {
                Section("Constraint") {
                    TextField("Name", text: $constraintName)
                    Picker("Local column", selection: $localColumn) {
                        ForEach(columns, id: \.name) { Text($0.name).tag($0.name) }
                    }
                }
                Section("References") {
                    Picker("Table", selection: $referencedTable) {
                        ForEach(referencedTables, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: referencedTable) { _, value in
                        Task { await loadReferencedColumns(for: value) }
                    }
                    Picker("Column", selection: $referencedColumn) {
                        ForEach(referencedColumns, id: \.name) { Text($0.name).tag($0.name) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Foreign Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddForeignKey = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { prepareCreate() }
                        .disabled(constraintName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || localColumn.isEmpty || referencedTable.isEmpty || referencedColumn.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private func loadForeignKeys() async {
        guard let connection = session?.connection else { return }
        isLoading = true
        errorMessage = nil
        do {
            foreignKeys = try await connection.foreignKeys(in: table, database: database)
            columns = try await connection.columns(in: table, database: database)
            referencedTables = try await connection.tables(in: database)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func prepareAddSheet() {
        constraintName = "fk_\(table)_"
        localColumn = columns.first?.name ?? ""
        referencedTable = referencedTables.first ?? ""
        referencedColumn = ""
        showingAddForeignKey = true
        Task { await loadReferencedColumns(for: referencedTable) }
    }

    private func loadReferencedColumns(for referencedTable: String) async {
        guard let connection = session?.connection, !referencedTable.isEmpty else {
            referencedColumns = []
            referencedColumn = ""
            return
        }
        do {
            referencedColumns = try await connection.columns(in: referencedTable, database: database)
            referencedColumn = referencedColumns.first?.name ?? ""
        } catch {
            referencedColumns = []
            referencedColumn = ""
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCreate() {
        guard let connection = session?.connection else { return }
        do {
            let sql = try TableSchemaSQL.addForeignKey(
                database: database,
                table: table,
                name: constraintName,
                column: localColumn,
                referencedTable: referencedTable,
                referencedColumn: referencedColumn,
                dialect: connection.dialect,
                quoteCharacter: connection.identifierQuoteCharacter
            )
            showingAddForeignKey = false
            pendingChange = TableSchemaChange(title: "Add Foreign Key?", operation: "add-foreign-key", sql: sql, destructive: false)
        } catch { errorMessage = error.localizedDescription }
    }

    private func prepareDrop(_ key: TableForeignKeyGroup) {
        guard let connection = session?.connection else { return }
        do {
            pendingChange = TableSchemaChange(
                title: "Drop ‘\(key.name)’?",
                operation: "drop-foreign-key",
                sql: try TableSchemaSQL.dropForeignKey(database: database, table: table, name: key.name, dialect: connection.dialect, quoteCharacter: connection.identifierQuoteCharacter),
                destructive: true
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ change: TableSchemaChange) async {
        guard let session else { return }
        isApplyingChange = true
        errorMessage = nil
        do {
            try await applyTableSchemaChange(change, session: session, database: database, table: table)
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            await loadForeignKeys()
        } catch {
            sessionManager.invalidateTableStatistics(sessionID: sessionID, database: database)
            errorMessage = "The server may have changed. Refresh before retrying. \(error.localizedDescription)"
        }
        isApplyingChange = false
    }
}

/// Schema-wide completion identifiers: every database name, the focus
/// database's table names, and plain plus table-qualified column names for up
/// to 50 tables. One implementation serves both the SQL-document editor and
/// the table Data surface, so a fragment like `comm` completes to
/// `shop` everywhere an editor appears.
enum SchemaCompletionIdentifiers {
    /// Fetch only the requested database's tables, not every database's columns.
    /// Validate against live database names so an alias is not used as a database.
    static func qualifiedTables(
        connection: any DatabaseConnection,
        database: String
    ) async throws -> [String] {
        guard try await connection.databases().contains(database) else { return [] }
        return try await connection.tables(in: database).map { "\(database).\($0)" }
    }

    static func load(
        connection: any DatabaseConnection,
        database: String?
    ) async throws -> [String] {
        var identifiers = Set(try await connection.databases())
        if let database, !database.isEmpty {
            let tables = try await connection.tables(in: database)
            identifiers.formUnion(tables)
            // Dotted references complete as one token (the completion
            // context treats "." as an identifier character), so qualified
            // names must exist as candidates for `db.tab` prefixes to match.
            identifiers.formUnion(tables.map { "\(database).\($0)" })
            await withTaskGroup(of: [String].self) { group in
                for table in tables.prefix(50) {
                    group.addTask {
                        guard let columns = try? await connection.columns(
                            in: table,
                            database: database
                        ) else { return [] }
                        return columns.flatMap { [$0.name, "\(table).\($0.name)"] }
                    }
                }
                for await names in group {
                    identifiers.formUnion(names)
                }
            }
        }
        return identifiers.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
