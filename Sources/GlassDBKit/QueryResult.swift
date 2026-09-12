//
//  QueryResult.swift
//  GlassDBKit
//
//  Unified result model for query execution across all database engines
//

import Foundation

public struct QueryResult: Identifiable, Sendable {
    public let id: UUID
    public let query: String
    public let columns: [ColumnInfo]
    public let rows: [[DatabaseValue]]
    public let affectedRows: UInt64?
    public let lastInsertID: UInt64?
    public let warningCount: UInt16?
    public let executionTime: TimeInterval
    public let timestamp: Date
    public let error: String?
    /// The maximum number of rows retained from a server-bounded query.
    /// `nil` means no result bound was applied by glassdb.
    public let appliedRowLimit: Int?
    /// True only when glassdb fetched an additional row proving that more rows
    /// were available, then removed that sentinel row from `rows`.
    public let isTruncated: Bool

    public init(
        id: UUID = UUID(),
        query: String,
        columns: [ColumnInfo] = [],
        rows: [[DatabaseValue]] = [],
        affectedRows: UInt64? = nil,
        lastInsertID: UInt64? = nil,
        warningCount: UInt16? = nil,
        executionTime: TimeInterval,
        timestamp: Date = Date(),
        error: String? = nil,
        appliedRowLimit: Int? = nil,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.query = query
        self.columns = columns
        self.rows = rows
        self.affectedRows = affectedRows
        self.lastInsertID = lastInsertID
        self.warningCount = warningCount
        self.executionTime = executionTime
        self.timestamp = timestamp
        self.error = error
        self.appliedRowLimit = appliedRowLimit
        self.isTruncated = isTruncated
    }

    public var isError: Bool { error != nil }
    public var rowCount: Int { rows.count }
    public var columnCount: Int { columns.count }
}

public struct ColumnInfo: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let type: String
    public let isNullable: Bool
    public let isPrimaryKey: Bool
    public let ordinalPosition: Int
    public let isUnsigned: Bool
    public let characterSetID: UInt8?
    public let sourceSchema: String?
    public let sourceTable: String?
    public let sourceColumn: String?
    public let length: UInt32?
    public let decimals: UInt8?
    public let defaultValue: String?
    public let isGenerated: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        type: String,
        isNullable: Bool = true,
        isPrimaryKey: Bool = false,
        ordinalPosition: Int = 0,
        isUnsigned: Bool = false,
        characterSetID: UInt8? = nil,
        sourceSchema: String? = nil,
        sourceTable: String? = nil,
        sourceColumn: String? = nil,
        length: UInt32? = nil,
        decimals: UInt8? = nil,
        defaultValue: String? = nil,
        isGenerated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.ordinalPosition = ordinalPosition
        self.isUnsigned = isUnsigned
        self.characterSetID = characterSetID
        self.sourceSchema = sourceSchema
        self.sourceTable = sourceTable
        self.sourceColumn = sourceColumn
        self.length = length
        self.decimals = decimals
        self.defaultValue = defaultValue
        self.isGenerated = isGenerated
    }
}

public struct DatabaseTemporalValue: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case date
        case time
        case dateTime
        case timestamp
        case year
    }

    /// The exact server representation, including fractional seconds when present.
    public let rawValue: String
    public let kind: Kind

    public init(rawValue: String, kind: Kind) {
        self.rawValue = rawValue
        self.kind = kind
    }
}

public enum DatabaseValue: Sendable, Hashable {
    case string(String)
    case int(Int64)
    case uint(UInt64)
    /// Exact base-10 representation. A String avoids Decimal/Double precision loss.
    case decimal(String)
    case double(Double)
    case data(Data)
    /// Valid JSON text in its original server representation.
    case json(String)
    case temporal(DatabaseTemporalValue)
    /// Exact bit-field bytes, most-significant byte first.
    case bit(Data)
    case null
    case date(Date)
    case bool(Bool)

    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .uint(let i): return String(i)
        case .decimal(let value): return value
        case .double(let d): return String(d)
        case .data(let d): return "<\(d.count) bytes>"
        case .json(let value): return value
        case .temporal(let value): return value.rawValue
        case .bit(let bytes):
            return bytes.map { String($0, radix: 2).leftPadding(toLength: 8, withPad: "0") }.joined()
        case .null: return "NULL"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .bool(let b): return b ? "true" : "false"
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// A lossless, deterministic text representation suitable for exports.
    /// Binary values use RFC 4648 Base64 rather than the abbreviated UI label.
    public var exportString: String {
        switch self {
        case .data(let data), .bit(let data): return data.base64EncodedString()
        default: return displayString
        }
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad pad: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(pad), count: toLength - count) + self
    }
}

public struct IndexInfo: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let columnName: String
    public let isUnique: Bool
    public let isPrimary: Bool
    public let type: String
    public let sequenceInIndex: Int

    public init(
        name: String,
        columnName: String,
        isUnique: Bool,
        isPrimary: Bool = false,
        type: String,
        sequenceInIndex: Int
    ) {
        self.name = name
        self.columnName = columnName
        self.isUnique = isUnique
        self.isPrimary = isPrimary
        self.type = type
        self.sequenceInIndex = sequenceInIndex
    }
}

public struct ForeignKeyInfo: Identifiable, Sendable {
    public let id = UUID()
    public let constraintName: String
    public let columnName: String
    public let referencedTable: String
    public let referencedColumn: String
    public let ordinalPosition: Int

    public init(constraintName: String, columnName: String, referencedTable: String, referencedColumn: String, ordinalPosition: Int) {
        self.constraintName = constraintName
        self.columnName = columnName
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
        self.ordinalPosition = ordinalPosition
    }
}

public enum TableRowCountAccuracy: Sendable, Equatable {
    case exact
    case estimated
}

public struct TableStatus: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let engine: String?
    public let rowCount: Int
    public let dataLength: Int
    public let collation: String?
    public let rowCountAccuracy: TableRowCountAccuracy
    public let statisticsUpdatedAt: Date?
    public let modifiedRowsSinceAnalysis: Int?

    public init(
        name: String,
        engine: String?,
        rowCount: Int,
        dataLength: Int,
        collation: String?,
        rowCountAccuracy: TableRowCountAccuracy = .estimated,
        statisticsUpdatedAt: Date? = nil,
        modifiedRowsSinceAnalysis: Int? = nil
    ) {
        self.name = name
        self.engine = engine
        self.rowCount = rowCount
        self.dataLength = dataLength
        self.collation = collation
        self.rowCountAccuracy = rowCountAccuracy
        self.statisticsUpdatedAt = statisticsUpdatedAt
        self.modifiedRowsSinceAnalysis = modifiedRowsSinceAnalysis
    }
}
