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
    /// A PostgreSQL array — `integer[]`, `text[][]`, or the internal spelling `_int4`. The
    /// payload is the element type's own format when it has one, so a `date[]` checks its
    /// elements as dates; `indirect` because that element format is a `ColumnValueFormat`.
    indirect case array(elementTypeName: String, element: ColumnValueFormat?)

    static func parse(_ declaredType: String) -> ColumnValueFormat? {
        let lower = declaredType.lowercased()
        if let elementTypeName = Self.arrayElementTypeName(in: lower) {
            return .array(elementTypeName: elementTypeName, element: Self.parse(elementTypeName))
        }
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
        case .array(let elementTypeName, let element):
            let elements: [ArrayElement]
            do {
                elements = try Self.parseArrayLiteral(value)
            } catch let error as ArrayLiteralError {
                return "‘\(column)’ takes a PostgreSQL array such as {1,2,3}. \(error.reason)"
            } catch {
                return "‘\(column)’ takes a PostgreSQL array such as {1,2,3}."
            }
            guard let element else { return nil }
            // Each element is checked as its own type, so `date[]` rejects {2026-02-30} for the
            // same reason a bare `date` column does. An unquoted NULL is the array's null and is
            // not a value to check.
            for entry in elements where !entry.isUnquotedNull {
                if let message = element.formatMessage(for: entry.text, column: column) {
                    return "‘\(column)’ is an array of \(elementTypeName). \(message)"
                }
            }
        }
        return nil
    }

    // MARK: PostgreSQL arrays

    /// The element type of an array type, or nil when this is not one.
    ///
    /// Two spellings reach us. `information_schema` and `format_type` give the SQL one,
    /// `integer[]` — and `integer[][]`, which in PostgreSQL is the *same* type as `integer[]`
    /// (the number of dimensions is not enforced), so every trailing `[]` is stripped. `pg_type`
    /// gives the internal one, `_int4`, a leading underscore on the element type's name.
    static func arrayElementTypeName(in lower: String) -> String? {
        var body = lower.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        if body.hasSuffix("[]") {
            while body.hasSuffix("[]") { body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces) }
            return body.isEmpty ? nil : body
        }
        // `_int4`, but not a column type that merely starts with an underscore and is not an
        // array: PostgreSQL's internal array names are exactly "underscore + element type".
        if body.hasPrefix("_"), body.count > 1, !body.dropFirst().hasPrefix("_") {
            return String(body.dropFirst())
        }
        return nil
    }

    struct ArrayElement: Equatable, Sendable {
        let text: String
        /// PostgreSQL's array NULL is the bare word; `"NULL"` in quotes is the four-character
        /// string, which is why the distinction is carried rather than compared after the fact.
        let isUnquotedNull: Bool
    }

    struct ArrayLiteralError: Error {
        let reason: String
    }

    /// Parses a PostgreSQL array literal into its leaf elements, flattened across dimensions.
    ///
    /// Only checks that the literal is *well formed* — braces balanced, quotes closed, escapes
    /// complete. It does not check that the dimensions are rectangular, which the server does and
    /// which cannot be decided without also deciding what an empty array means.
    static func parseArrayLiteral(_ value: String) throws -> [ArrayElement] {
        var elements: [ArrayElement] = []
        var depth = 0
        var sawOpeningBrace = false
        var current = ""
        var currentWasQuoted = false
        var inQuotes = false
        var index = value.startIndex

        func finishElement() {
            let trimmed = currentWasQuoted ? current : current.trimmingCharacters(in: .whitespaces)
            // `{}` is the empty array, and `{1,}` is a syntax error the server would reject; an
            // unquoted empty run between separators is only legitimate for the empty array,
            // which never reaches here because it closes before any separator.
            if !trimmed.isEmpty || currentWasQuoted {
                elements.append(ArrayElement(
                    text: trimmed,
                    isUnquotedNull: !currentWasQuoted && trimmed.lowercased() == "null"
                ))
            }
            current = ""
            currentWasQuoted = false
        }

        while index < value.endIndex {
            let character = value[index]
            if inQuotes {
                if character == "\\" {
                    let next = value.index(after: index)
                    guard next < value.endIndex else {
                        throw ArrayLiteralError(reason: "The literal ends in an incomplete escape.")
                    }
                    current.append(value[next])
                    index = value.index(after: next)
                    continue
                }
                if character == "\"" {
                    inQuotes = false
                } else {
                    current.append(character)
                }
                index = value.index(after: index)
                continue
            }
            switch character {
            case "{":
                guard current.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ArrayLiteralError(reason: "A value appears outside any braces.")
                }
                depth += 1
                sawOpeningBrace = true
                current = ""
            case "}":
                guard depth > 0 else {
                    throw ArrayLiteralError(reason: "There is a closing brace with no opening one.")
                }
                finishElement()
                depth -= 1
            case ",":
                guard depth > 0 else {
                    throw ArrayLiteralError(reason: "A separator appears outside any braces.")
                }
                finishElement()
            case "\"":
                currentWasQuoted = true
                inQuotes = true
            default:
                guard depth > 0 || character.isWhitespace else {
                    throw ArrayLiteralError(reason: "A value appears outside any braces.")
                }
                if depth > 0 { current.append(character) }
            }
            index = value.index(after: index)
        }

        if inQuotes { throw ArrayLiteralError(reason: "A quoted value is not closed.") }
        guard sawOpeningBrace else {
            throw ArrayLiteralError(reason: "An array literal is written inside braces.")
        }
        guard depth == 0 else { throw ArrayLiteralError(reason: "A brace is not closed.") }
        return elements
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
