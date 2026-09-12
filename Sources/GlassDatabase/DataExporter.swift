//
//  DataExporter.swift
//  glassdb
//
//  Type-preserving CSV, JSON, SQL, and TSV serialization for bounded results.
//

import SwiftUI
import UniformTypeIdentifiers
import GlassDBKit

enum GridExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json
    case sql

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .sql: return UTType(filenameExtension: "sql") ?? .plainText
        }
    }
}

struct GridExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .json, UTType(filenameExtension: "sql") ?? .plainText]
    }

    let text: String

    init(
        result: QueryResult,
        format: GridExportFormat,
        database: String,
        table: String,
        identifierQuote: Character = "`"
    ) {
        switch format {
        case .csv:
            text = GridExportFormatter.csv(result: result)
        case .json:
            text = GridExportFormatter.json(result: result)
        case .sql:
            text = GridExportFormatter.sql(
                result: result,
                database: database,
                table: table,
                identifierQuote: identifierQuote
            )
        }
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum GridExportFormatter {
    static func csv(result: QueryResult) -> String {
        var output = result.columns.map { escapeCSV($0.name) }.joined(separator: ",")
        for row in result.rows {
            output.append("\n")
            for index in result.columns.indices {
                if index > 0 { output.append(",") }
                output.append(escapeCSV(index < row.count ? row[index].exportString : ""))
            }
        }
        return output
    }

    static func tsv(
        result: QueryResult,
        rowRange: ClosedRange<Int>,
        columnRange: ClosedRange<Int>
    ) -> String {
        let validRows = rowRange.clamped(to: result.rows.indices)
        let validColumns = columnRange.clamped(to: result.columns.indices)
        guard let validRows, let validColumns else { return "" }
        var output = ""
        for rowIndex in validRows {
            if rowIndex > validRows.lowerBound { output.append("\n") }
            for columnIndex in validColumns {
                if columnIndex > validColumns.lowerBound { output.append("\t") }
                if columnIndex < result.rows[rowIndex].count {
                    let value = result.rows[rowIndex][columnIndex]
                    if value.isNull {
                        output.append("\\N")
                    } else if case .bit = value {
                        output.append(escapeTSV(value.displayString))
                    } else {
                        output.append(escapeTSV(value.exportString))
                    }
                }
            }
        }
        return output
    }

    static func json(result: QueryResult) -> String {
        let object: [String: Any] = [
            "columns": result.columns.map { ["name": $0.name, "type": $0.type] },
            "rows": result.rows.map { $0.map(jsonObject) }
        ]
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func sql(
        result: QueryResult,
        database: String,
        table: String,
        identifierQuote: Character = "`"
    ) -> String {
        guard !result.columns.isEmpty, !result.rows.isEmpty else { return "" }
        let qualifiedTable = "\(quoteIdentifier(database, quote: identifierQuote)).\(quoteIdentifier(table, quote: identifierQuote))"
        let columns = result.columns
            .map { quoteIdentifier($0.name, quote: identifierQuote) }
            .joined(separator: ", ")
        var output = ""
        for (rowIndex, row) in result.rows.enumerated() {
            if rowIndex > 0 { output.append("\n") }
            output.append("INSERT INTO \(qualifiedTable) (\(columns)) VALUES (")
            for index in result.columns.indices {
                if index > 0 { output.append(", ") }
                output.append(index < row.count ? sqlLiteral(row[index]) : "NULL")
            }
            output.append(");")
        }
        return output
    }

    private static func jsonObject(_ value: DatabaseValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .uint(let value):
            return value <= 9_007_199_254_740_991 ? value : String(value)
        case .double(let value): return value.isFinite ? value : value.description
        case .decimal(let value): return value
        case .data(let value): return ["$binary": value.base64EncodedString()]
        case .bit(let value): return ["$bit": value.map { String($0, radix: 2).leftPadded(to: 8) }.joined()]
        case .string(let value): return value
        case .json(let value):
            return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) ?? value
        case .temporal(let value): return value.rawValue
        case .date(let value): return ISO8601DateFormatter().string(from: value)
        }
    }

    private static func sqlLiteral(_ value: DatabaseValue) -> String {
        switch value {
        case .null: return "NULL"
        case .bool(let value): return value ? "TRUE" : "FALSE"
        case .int(let value): return String(value)
        case .uint(let value): return String(value)
        case .decimal(let value): return value
        case .double(let value): return value.isFinite ? String(value) : "NULL"
        case .data(let value): return "X'\(value.hexEncoded)'"
        case .bit(let value):
            return "B'\(value.map { String($0, radix: 2).leftPadded(to: 8) }.joined())'"
        case .string(let value), .json(let value): return quoteString(value)
        case .temporal(let value): return quoteString(value.rawValue)
        case .date(let value): return quoteString(ISO8601DateFormatter().string(from: value))
        }
    }

    private static func quoteIdentifier(_ identifier: String, quote: Character) -> String {
        let delimiter = String(quote)
        return delimiter + identifier.replacingOccurrences(of: delimiter, with: delimiter + delimiter) + delimiter
    }

    private static func quoteString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func escapeTSV(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private extension ClosedRange where Bound == Int {
    func clamped(to indices: Range<Int>) -> ClosedRange<Int>? {
        guard !indices.isEmpty else { return nil }
        let lower = Swift.max(lowerBound, indices.lowerBound)
        let upper = Swift.min(upperBound, indices.upperBound - 1)
        return lower <= upper ? lower...upper : nil
    }
}

private extension Data {
    var hexEncoded: String { map { String(format: "%02X", $0) }.joined() }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
