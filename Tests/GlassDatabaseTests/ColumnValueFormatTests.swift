import Foundation
import Testing
@testable import GlassDatabase

@Suite("Column value formats")
struct ColumnValueFormatTests {

    private func message(_ type: String, _ value: String) -> String? {
        ColumnValueFormat.parse(type)?.formatMessage(for: value, column: "c")
    }

    // MARK: PostgreSQL arrays

    @Test("Array types are recognised in both spellings, including nested dimensions")
    func arrayTypesAreRecognised() {
        #expect(ColumnValueFormat.arrayElementTypeName(in: "integer[]") == "integer")
        #expect(ColumnValueFormat.arrayElementTypeName(in: "_int4") == "int4")
        // In PostgreSQL `integer[][]` is the same type as `integer[]`; the dimension count is
        // documentation, not a constraint, so every trailing pair is stripped.
        #expect(ColumnValueFormat.arrayElementTypeName(in: "integer[][]") == "integer")
        #expect(ColumnValueFormat.arrayElementTypeName(in: "text[]") == "text")
        #expect(ColumnValueFormat.arrayElementTypeName(in: "integer") == nil)
        #expect(ColumnValueFormat.arrayElementTypeName(in: "_") == nil)
    }

    @Test("An array column takes an array literal and says so when it does not")
    func arrayLiteralShape() {
        #expect(message("integer[]", "{1,2,3}") == nil)
        #expect(message("integer[]", "{}") == nil, "the empty array")
        #expect(message("integer[]", "{{1,2},{3,4}}") == nil)
        #expect(message("integer[]", "{1,NULL,3}") == nil)
        #expect(message("_int4", "{1,2}") == nil)

        // The gap this closes: before it, every one of these was accepted and failed at the
        // server.
        #expect(message("integer[]", "1,2,3") != nil, "no braces")
        #expect(message("integer[]", "{1,2") != nil, "unclosed brace")
        #expect(message("integer[]", "1}") != nil)
        #expect(message("integer[]", "{\"unterminated}") != nil)
    }

    @Test("Elements are checked as their own type")
    func arrayElementsAreChecked() {
        // The reuse that makes this worth having: `date[]` inherits the date check, so the day
        // that a bare `date` column rejects is rejected inside an array too.
        #expect(message("date[]", "{2026-09-12,2028-02-29}") == nil)
        #expect(message("date[]", "{2026-02-30}") != nil)
        #expect(message("date[]", "{yesterday}") != nil)
        #expect(message("date[]", "{2026-09-12,NULL}") == nil, "an unquoted NULL is the array null")
        #expect(message("uuid[]", "{\(UUID().uuidString)}") == nil)
        #expect(message("uuid[]", "{not-a-uuid}") != nil)
        // An element type with no format of its own leaves the literal check as the whole check.
        #expect(message("integer[]", "{not-a-number}") == nil,
                "integers are ColumnTypeConstraint's business, not this file's")
    }

    @Test("Quoting is honoured, so a quoted NULL is the four-character string")
    func arrayQuoting() {
        #expect(message("text[]", "{\"a,b\",c}") == nil, "the comma is inside quotes")
        #expect(message("date[]", "{\"NULL\"}") != nil,
                "quoted, so it is a value and not the array null — and not a date")
        #expect(message("text[]", "{\"he said \\\"hi\\\"\"}") == nil, "an escaped quote")
    }

    @Test("Dates must be real days, not merely the right shape")
    func dates() {
        #expect(message("date", "2026-09-12") == nil)
        #expect(message("date", "2028-02-29") == nil, "a leap day in a leap year")
        #expect(message("date", "2026-02-29") != nil, "not a leap year")
        #expect(message("date", "2026-02-30") != nil)
        #expect(message("date", "2026-13-01") != nil)
        #expect(message("date", "12/09/2026") != nil)
        #expect(message("date", "yesterday") != nil)
        #expect(message("date", "0000-00-00") == nil, "MySQL's zero date is what it writes for unset")
    }

    @Test("Times accept MySQL's duration range and reject nonsense")
    func times() {
        #expect(message("time", "09:41") == nil)
        #expect(message("time", "09:41:30") == nil)
        #expect(message("time", "09:41:30.125") == nil)
        #expect(message("time", "-838:59:59") == nil, "TIME is a duration as well as a clock time")
        #expect(message("time", "24:00:00") == nil, "still within the duration range")
        #expect(message("time", "839:00:00") != nil)
        #expect(message("time", "09:60") != nil)
        #expect(message("time", "9") != nil)
        #expect(message("time", "half past nine") != nil)
    }

    @Test("Datetimes take a space or an ISO T, and a trailing zone is fine")
    func datetimes() {
        #expect(message("datetime", "2026-09-12 09:41:30") == nil)
        #expect(message("timestamp", "2026-09-12T09:41:30") == nil)
        #expect(message("timestamptz", "2026-09-12T09:41:30Z") == nil)
        #expect(message("timestamptz", "2026-09-12 09:41:30+01:00") == nil)
        #expect(message("datetime", "2026-09-12") == nil, "a bare date; the server fills midnight in")
        #expect(message("datetime", "2026-02-30 09:41:30") != nil, "the date half is still checked")
        #expect(message("datetime", "2026-09-12 25:00") == nil, "hours run past 24 in the time half")
        #expect(message("datetime", "not a timestamp") != nil)
    }

    @Test("Year takes four digits in MySQL's range")
    func years() {
        #expect(message("year", "2026") == nil)
        #expect(message("year", "1900") != nil)
        #expect(message("year", "2156") != nil)
        #expect(message("year", "26") != nil)
    }

    @Test("UUID columns take a UUID")
    func uuids() {
        #expect(message("uuid", UUID().uuidString) == nil)
        #expect(message("uuid", "not-a-uuid") != nil)
    }

    @Test("enum takes exactly one of its declared members")
    func enums() {
        #expect(ColumnValueFormat.parse("enum('draft','sent')") == .oneOf(["draft", "sent"]))
        #expect(message("enum('draft','sent')", "draft") == nil)
        #expect(message("enum('draft','sent')", "DRAFT") == nil, "members match case-insensitively")
        #expect(message("enum('draft','sent')", "archived")?.contains("draft, sent") == true)
        // A member containing a comma or an escaped quote must survive parsing.
        #expect(ColumnValueFormat.parse("enum('a,b','it''s')") == .oneOf(["a,b", "it's"]))
        #expect(message("enum('a,b','it''s')", "a,b") == nil)
    }

    @Test("set takes any subset, and names the members it did not recognise")
    func sets() {
        #expect(ColumnValueFormat.parse("set('read','write')") == .subsetOf(["read", "write"]))
        #expect(message("set('read','write')", "read") == nil)
        #expect(message("set('read','write')", "read,write") == nil)
        #expect(message("set('read','write')", "read, write") == nil, "spaces after the comma are fine")
        #expect(message("set('read','write')", "read,delete")?.contains("delete") == true)
    }

    @Test("An empty value is NULL-ability's business, not this check's")
    func emptyIsNotAFormatError() {
        #expect(message("date", "") == nil)
        #expect(message("enum('a')", "   ") == nil)
    }

    @Test("Types with no format to check are left alone")
    func unformatted() {
        #expect(ColumnValueFormat.parse("varchar(40)") == nil)
        #expect(ColumnValueFormat.parse("int") == nil)
        #expect(ColumnValueFormat.parse("json") == nil, "JSON is validated where it is parsed")
    }
}
