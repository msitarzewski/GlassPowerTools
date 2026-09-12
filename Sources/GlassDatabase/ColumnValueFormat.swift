//
//  ColumnValueFormat.swift
//  Glass Power Tools — GlassDatabase
//
//  Whether a value is *well formed* for its column, as distinct from whether it *fits*
//  (`ColumnTypeConstraint`). Temporal columns used to accept any string at all and fail at the
//  server; `enum` and `set` carry their permitted values in the declared type and were never
//  checked against it.
//

import Foundation

/// A format a column's value must satisfy, parsed from the declared type.
enum ColumnValueFormat: Equatable, Sendable {
    case date
    case time
    case dateTime
    case year
    case uuid
    /// `enum('draft','sent')` — exactly one of these.
    case oneOf([String])
    /// `set('read','write')` — a comma-separated subset, possibly empty.
    case subsetOf([String])

    static func parse(_ declaredType: String) -> ColumnValueFormat? {
        let lower = declaredType.lowercased()
        let base = (lower.split(separator: "(", maxSplits: 1).first.map(String.init) ?? lower)
            .trimmingCharacters(in: .whitespaces)
        switch base {
        case "date": return .date
        case "time", "timetz", "time with time zone", "time without time zone": return .time
        case "datetime", "timestamp", "timestamptz",
             "timestamp with time zone", "timestamp without time zone": return .dateTime
        case "year": return .year
        case "uuid": return .uuid
        case "enum": return .oneOf(members(in: declaredType))
        case "set": return .subsetOf(members(in: declaredType))
        default: return nil
        }
    }

    /// Why this text is not well formed, or nil when it is. An empty string is never rejected
    /// here: emptiness is NULL-ability's business, decided before this runs.
    func formatMessage(for text: String, column: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        switch self {
        case .date:
            guard Self.isDate(value) else {
                return "‘\(column)’ takes a date as YYYY-MM-DD."
            }
        case .time:
            guard Self.isTime(value) else {
                return "‘\(column)’ takes a time as HH:MM:SS."
            }
        case .dateTime:
            guard Self.isDateTime(value) else {
                return "‘\(column)’ takes a date and time as YYYY-MM-DD HH:MM:SS."
            }
        case .year:
            guard let year = Int(value), value.count == 4, (1901...2155).contains(year) || year == 0 else {
                return "‘\(column)’ takes a four-digit year from 1901 through 2155."
            }
        case .uuid:
            guard UUID(uuidString: value) != nil else {
                return "‘\(column)’ takes a UUID."
            }
        case .oneOf(let members):
            guard !members.isEmpty else { return nil }
            guard members.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                return "‘\(column)’ takes one of: \(members.joined(separator: ", "))."
            }
        case .subsetOf(let members):
            guard !members.isEmpty else { return nil }
            let chosen = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let unknown = chosen.filter { candidate in
                !members.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }
            guard unknown.isEmpty else {
                return "‘\(column)’ takes any of: \(members.joined(separator: ", ")). Not recognised: \(unknown.joined(separator: ", "))."
            }
        }
        return nil
    }

    // MARK: Parsing

    /// The quoted members of `enum(...)` / `set(...)`, unescaping a doubled quote as the server
    /// writes it.
    private static func members(in declaredType: String) -> [String] {
        guard let open = declaredType.firstIndex(of: "("),
              let close = declaredType.lastIndex(of: ")"), open < close else { return [] }
        let body = declaredType[declaredType.index(after: open)..<close]
        var members: [String] = []
        var current = ""
        var inQuotes = false
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "'" {
                let next = body.index(after: index)
                if inQuotes, next < body.endIndex, body[next] == "'" {
                    current.append("'")            // a doubled quote is a literal one
                    index = body.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                members.append(current)
                current = ""
            } else if inQuotes {
                current.append(character)
            }
            index = body.index(after: index)
        }
        if !current.isEmpty || !members.isEmpty { members.append(current) }
        return members.filter { !$0.isEmpty }
    }

    // MARK: Temporal shapes

    /// `YYYY-MM-DD`, and a real day: 2026-02-30 is rejected, 2028-02-29 is not.
    static func isDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, let year = Int(parts[0]),
              parts[1].count <= 2, let month = Int(parts[1]),
              parts[2].count <= 2, let day = Int(parts[2]) else { return false }
        // The zero date is what MySQL writes for an unset value; accept it rather than fight it.
        if year == 0, month == 0, day == 0 { return true }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return components.isValidDate(in: calendar)
    }

    /// `HH:MM`, `HH:MM:SS`, optional fractional seconds, optional leading sign. MySQL's `TIME`
    /// is a duration as well as a clock time, so hours run to 838 and may be negative.
    static func isTime(_ value: String) -> Bool {
        var body = Substring(value)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        let fractionSplit = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if fractionSplit.count == 2 {
            guard !fractionSplit[1].isEmpty, fractionSplit[1].allSatisfy(\.isNumber) else { return false }
        }
        let clock = fractionSplit[0].split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(clock.count) else { return false }
        guard let hours = Int(clock[0]), (0...838).contains(hours), !clock[0].isEmpty else { return false }
        guard let minutes = Int(clock[1]), (0...59).contains(minutes), (1...2).contains(clock[1].count) else { return false }
        if clock.count == 3 {
            guard let seconds = Int(clock[2]), (0...59).contains(seconds), (1...2).contains(clock[2].count) else { return false }
        }
        return true
    }

    /// `YYYY-MM-DD HH:MM:SS`, also accepting the ISO `T` separator and a trailing time-zone
    /// offset or `Z`, which is what PostgreSQL hands back for `timestamptz`.
    static func isDateTime(_ value: String) -> Bool {
        var body = Substring(value)
        // Strip a trailing zone: `Z`, `+01`, `+01:00`, `-0500`.
        if body.hasSuffix("Z") || body.hasSuffix("z") { body = body.dropLast() }
        if let zone = body.lastIndex(where: { $0 == "+" || $0 == "-" }),
           zone > body.startIndex,
           body.distance(from: body.startIndex, to: zone) > 10 {
            body = body[body.startIndex..<zone]
        }
        let separated = body.contains("T") || body.contains("t")
            ? body.split(separator: body.contains("T") ? "T" : "t", maxSplits: 1)
            : body.split(separator: " ", maxSplits: 1)
        guard let datePart = separated.first else { return false }
        guard isDate(String(datePart)) else { return false }
        // A bare date is a valid datetime; the server fills midnight in.
        guard separated.count == 2 else { return true }
        return isTime(String(separated[1]).trimmingCharacters(in: .whitespaces))
    }
}
