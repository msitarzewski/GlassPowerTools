//
//  ColumnTypeConstraint.swift
//  Glass Power Tools — GlassDatabase
//
//  What a column's *declared* type permits, parsed from the type string the schema already gives
//  us (`varchar(40)`, `decimal(10,2)`, `tinyint unsigned`). Deliberately not taken from result-set
//  metadata: MySQL reports `columnLength` in **bytes**, so a `varchar(40)` in utf8mb4 comes back as
//  160 and a limit built on it would let the user type 160 characters and fail at the server;
//  PostgreSQL reports no length at all. The declared type is the same on both engines and is
//  already on screen beside the field name.
//

import Foundation
import GlassDBKit

/// The limit a value must respect to be storable in its column.
enum ColumnTypeConstraint: Equatable, Sendable {
    /// `varchar(40)`, `char(8)` — a maximum number of **characters**.
    case characters(Int)
    /// `binary(16)`, `varbinary(255)` — a maximum number of **bytes**.
    case bytes(Int)
    /// `bit(8)` — a maximum number of bits.
    case bits(Int)
    /// An integer family, with the range its width and signedness allow.
    case integer(min: Decimal, max: Decimal)
    /// `decimal(10,2)` — total significant digits and digits after the point.
    case decimal(precision: Int, scale: Int)

    /// MySQL's four `TEXT` and four `BLOB` families, and the **bytes** each one stores.
    ///
    /// Bytes, not characters. MySQL 8.4 §13.7 gives the storage as `L + n` bytes with `L` bounded
    /// by `2^(8n)`, so a `TEXT` holds 65,535 bytes however many characters that is — the docs'
    /// "65,535 characters" is the ASCII case and they add that "the effective maximum length is
    /// less if the value contains multibyte characters". `usage(of:)` and `overflowMessage(for:)`
    /// already count `.bytes` as UTF-8 bytes, which is exact for a utf8mb4 column and
    /// conservative for a single-byte one: it can refuse a value the server would have taken, but
    /// it never lets through one the server would truncate.
    ///
    /// Six of these eight names exist only in MySQL. Bare `text` and bare `blob` do not — they
    /// are also PostgreSQL's and SQLite's names for effectively unbounded values — so those two
    /// need the dialect, and without it they are left unconstrained rather than wrongly limited.
    static let mysqlLargeObjectByteLimits: [String: Int] = [
        "tinytext": 255, "tinyblob": 255,
        "text": 65_535, "blob": 65_535,
        "mediumtext": 16_777_215, "mediumblob": 16_777_215,
        "longtext": 4_294_967_295, "longblob": 4_294_967_295,
    ]

    /// The two names above that are ambiguous across the three engines.
    private static let dialectAmbiguousLargeObjects: Set<String> = ["text", "blob"]

    /// Parses the declared type. Returns nil when the type carries no limit worth enforcing
    /// client-side (`json`, `timestamp`, a PostgreSQL `text`).
    ///
    /// `dialect` is the connection's, and only MySQL's large-object limits depend on it: on
    /// PostgreSQL `text` and `bytea` run to about a gigabyte and on SQLite to `SQLITE_MAX_LENGTH`,
    /// neither of which an editor field can reach. Passing nil keeps the six unambiguous MySQL
    /// names working and leaves bare `text`/`blob` unconstrained — the safe reading, since
    /// applying MySQL's 65,535 to a PostgreSQL `text` would refuse values that are perfectly
    /// storable.
    static func parse(
        _ declaredType: String,
        isUnsigned: Bool,
        dialect: DatabaseDialect? = nil
    ) -> ColumnTypeConstraint? {
        let lower = declaredType.lowercased()
        // `int unsigned`, `double precision`, `character varying(40)`
        let unsigned = isUnsigned || lower.contains("unsigned")
        let head = lower.split(separator: "(", maxSplits: 1).first.map(String.init) ?? lower
        let base = head
            .replacingOccurrences(of: "unsigned", with: "")
            .replacingOccurrences(of: "zerofill", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parameters = Self.parameters(in: lower)

        switch base {
        case "varchar", "char", "nvarchar", "nchar", "character varying", "character", "varchar2":
            return parameters.first.map { .characters($0) }
        case "binary", "varbinary":
            return parameters.first.map { .bytes($0) }
        case "bit":
            // PostgreSQL `bit(n)` is a bit string; MySQL `bit(n)` likewise. `tinyint(1)` is a
            // boolean elsewhere and never reaches here.
            return parameters.first.map { .bits($0) }
        case "decimal", "numeric", "dec", "fixed":
            guard let precision = parameters.first else { return nil }
            return .decimal(precision: precision, scale: parameters.count > 1 ? parameters[1] : 0)
        case "tinyint": return integerRange(bits: 8, unsigned: unsigned)
        case "smallint", "int2": return integerRange(bits: 16, unsigned: unsigned)
        case "mediumint": return integerRange(bits: 24, unsigned: unsigned)
        case "int", "integer", "int4": return integerRange(bits: 32, unsigned: unsigned)
        case "bigint", "int8": return integerRange(bits: 64, unsigned: unsigned)
        default:
            return largeObjectLimit(base: base, dialect: dialect)
        }
    }

    /// The `TEXT`/`BLOB` byte limit for this name, when it can be established.
    private static func largeObjectLimit(base: String, dialect: DatabaseDialect?) -> ColumnTypeConstraint? {
        guard let limit = mysqlLargeObjectByteLimits[base] else { return nil }
        if dialectAmbiguousLargeObjects.contains(base) {
            // Only MySQL bounds these at all, so an unknown dialect means no limit.
            guard dialect == .mysql else { return nil }
        } else if let dialect, dialect != .mysql {
            // A name that only MySQL has, reported by another engine: believe the engine, not
            // the name, and enforce nothing.
            return nil
        }
        return .bytes(limit)
    }

    /// The inclusive range a signed or unsigned integer of this width allows.
    private static func integerRange(bits: Int, unsigned: Bool) -> ColumnTypeConstraint {
        // `Decimal` rather than `Int64`, so an unsigned 64-bit maximum is representable exactly.
        let two = Decimal(2)
        if unsigned {
            return .integer(min: 0, max: pow(two, bits) - 1)
        }
        let half = pow(two, bits - 1)
        return .integer(min: -half, max: half - 1)
    }

    /// The integers inside the first parenthesised group, in order.
    private static func parameters(in lower: String) -> [Int] {
        guard let open = lower.firstIndex(of: "("),
              let close = lower[open...].firstIndex(of: ")") else { return [] }
        return lower[lower.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// How much of the column this text uses, and what the limit is — for the live counter. Nil
    /// for constraints a counter cannot express (a numeric range is reported as an error instead).
    func usage(of text: String) -> (used: Int, limit: Int)? {
        switch self {
        case .characters(let limit): (text.count, limit)
        case .bytes(let limit): (text.utf8.count, limit)
        case .bits(let limit): (text.filter { $0 == "0" || $0 == "1" }.count, limit)
        case .integer, .decimal: nil
        }
    }

    /// Why this text will not fit, or nil when it will. Assumes the value already parses as its
    /// type: this is the size check that runs after the type check.
    func overflowMessage(for text: String, column: String) -> String? {
        switch self {
        case .characters(let limit):
            guard text.count > limit else { return nil }
            return "‘\(column)’ holds \(limit) characters; this is \(text.count)."
        case .bytes(let limit):
            guard text.utf8.count > limit else { return nil }
            return "‘\(column)’ holds \(limit) bytes; this is \(text.utf8.count)."
        case .bits(let limit):
            let count = text.filter { $0 == "0" || $0 == "1" }.count
            guard count > limit else { return nil }
            return "‘\(column)’ holds \(limit) bits; this is \(count)."
        case .integer(let min, let max):
            guard let value = Decimal(string: text.trimmingCharacters(in: .whitespaces)) else { return nil }
            guard value < min || value > max else { return nil }
            return "‘\(column)’ takes \(Self.plain(min)) through \(Self.plain(max))."
        case .decimal(let precision, let scale):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, Decimal(string: trimmed) != nil else { return nil }
            let digits = trimmed.drop { $0 == "+" || $0 == "-" }
            let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let whole = parts.first.map { $0.filter(\.isNumber).count } ?? 0
            let fraction = parts.count > 1 ? parts[1].filter(\.isNumber).count : 0
            if fraction > scale {
                return "‘\(column)’ keeps \(scale) decimal place\(scale == 1 ? "" : "s"); this has \(fraction)."
            }
            if whole > precision - scale {
                return "‘\(column)’ holds \(precision - scale) digit\(precision - scale == 1 ? "" : "s") before the point; this has \(whole)."
            }
            return nil
        }
    }

    private static func plain(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, nil)
    }
}
