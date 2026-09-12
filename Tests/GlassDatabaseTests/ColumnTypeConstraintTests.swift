import Foundation
import Testing
@testable import GlassDatabase

@Suite("Column type constraints")
struct ColumnTypeConstraintTests {

    @Test("Character types read their declared length, not a byte count")
    func characterLengths() {
        #expect(ColumnTypeConstraint.parse("varchar(40)", isUnsigned: false) == .characters(40))
        #expect(ColumnTypeConstraint.parse("VARCHAR(40)", isUnsigned: false) == .characters(40))
        #expect(ColumnTypeConstraint.parse("char(8)", isUnsigned: false) == .characters(8))
        #expect(ColumnTypeConstraint.parse("character varying(120)", isUnsigned: false) == .characters(120))
        // The whole point of parsing the declared type: MySQL's wire metadata would report 160
        // bytes for this column in utf8mb4, and a limit built on that would be wrong by 4x.
        let constraint = try! #require(ColumnTypeConstraint.parse("varchar(40)", isUnsigned: false))
        #expect(constraint.usage(of: String(repeating: "é", count: 40))?.used == 40,
                "counted in characters; these are two bytes each")
        #expect(constraint.overflowMessage(for: String(repeating: "é", count: 40), column: "c") == nil)
    }

    @Test("An unbounded type has no limit to enforce")
    func unbounded() {
        #expect(ColumnTypeConstraint.parse("text", isUnsigned: false) == nil)
        #expect(ColumnTypeConstraint.parse("json", isUnsigned: false) == nil)
        #expect(ColumnTypeConstraint.parse("timestamp", isUnsigned: false) == nil)
        #expect(ColumnTypeConstraint.parse("blob", isUnsigned: false) == nil)
    }

    @Test("Binary types count bytes, not characters")
    func binaryLengths() {
        let constraint = try! #require(ColumnTypeConstraint.parse("varbinary(4)", isUnsigned: false))
        #expect(constraint == .bytes(4))
        #expect(constraint.overflowMessage(for: "abcd", column: "b") == nil)
        #expect(constraint.overflowMessage(for: "ééé", column: "b")?.contains("4 bytes") == true)
    }

    @Test("Integer ranges follow the width and the signedness")
    func integerRanges() {
        let tiny = try! #require(ColumnTypeConstraint.parse("tinyint", isUnsigned: false))
        #expect(tiny == .integer(min: -128, max: 127))
        #expect(tiny.overflowMessage(for: "127", column: "n") == nil)
        #expect(tiny.overflowMessage(for: "128", column: "n")?.contains("-128 through 127") == true)
        #expect(tiny.overflowMessage(for: "-129", column: "n") != nil)

        let unsignedTiny = try! #require(ColumnTypeConstraint.parse("tinyint", isUnsigned: true))
        #expect(unsignedTiny == .integer(min: 0, max: 255))
        #expect(unsignedTiny.overflowMessage(for: "-1", column: "n") != nil)

        // `unsigned` in the declared type counts even when the flag is not set.
        #expect(ColumnTypeConstraint.parse("int unsigned", isUnsigned: false) == .integer(min: 0, max: 4_294_967_295))

        // A 64-bit unsigned maximum is exact, which is why the range is Decimal and not Int64.
        let big = try! #require(ColumnTypeConstraint.parse("bigint unsigned", isUnsigned: false))
        #expect(big.overflowMessage(for: "18446744073709551615", column: "n") == nil)
        #expect(big.overflowMessage(for: "18446744073709551616", column: "n") != nil)
    }

    @Test("Decimal checks the digits before the point and after it, separately")
    func decimalPrecision() {
        let money = try! #require(ColumnTypeConstraint.parse("decimal(10,2)", isUnsigned: false))
        #expect(money == .decimal(precision: 10, scale: 2))
        #expect(money.overflowMessage(for: "12345678.90", column: "amount") == nil)
        #expect(money.overflowMessage(for: "1.234", column: "amount")?.contains("2 decimal places") == true)
        #expect(money.overflowMessage(for: "123456789.0", column: "amount")?.contains("8 digits") == true)
        #expect(money.overflowMessage(for: "-12345678.90", column: "amount") == nil, "the sign is not a digit")
    }

    @Test("The counter reports what is used and what is allowed")
    func usageCounter() {
        let constraint = try! #require(ColumnTypeConstraint.parse("varchar(40)", isUnsigned: false))
        let usage = try! #require(constraint.usage(of: "triage-v0.1"))
        #expect(usage.used == 11 && usage.limit == 40)
        // A numeric range has nothing meaningful to count; it reports an error instead.
        #expect(ColumnTypeConstraint.parse("int", isUnsigned: false)?.usage(of: "5") == nil)
    }

    @Test("A value that does not parse is not reported as the wrong size")
    func garbageIsNotAnOverflow() {
        let int = try! #require(ColumnTypeConstraint.parse("int", isUnsigned: false))
        #expect(int.overflowMessage(for: "not a number", column: "n") == nil,
                "the type check reports that; this one only judges size")
    }
}

@Suite("Boolean detection")
struct RecordEditorBooleanTests {

    private func edit(type: String) -> StagedEdit {
        StagedEdit(columnIndex: 0, columnName: "c", columnType: type, isPrimaryKey: false,
                   isNullable: true, isUnsigned: false, isGenerated: false, defaultValue: nil,
                   originalValue: .null, editText: "", isNull: false, useDefault: false)
    }

    @Test("tinyint(1) is a boolean; a bare tinyint is an integer")
    func tinyintIsNotABoolean() {
        #expect(edit(type: "tinyint(1)").isBool, "MySQL's boolean convention")
        #expect(edit(type: "boolean").isBool)
        #expect(edit(type: "bool").isBool)

        // The regression this guards: a score column rendered as a toggle reading "False", and
        // saving would have written 0 over the real value.
        #expect(!edit(type: "tinyint").isBool)
        #expect(!edit(type: "tinyint(4)").isBool)
        #expect(!edit(type: "tinyint unsigned").isBool)
    }

    @Test("A bare tinyint binds as an integer and keeps its value")
    func tinyintBindsAsAnInteger() throws {
        var staged = edit(type: "tinyint")
        staged.editText = "7"
        #expect(staged.validationError == nil)
        #expect(try staged.boundValue() == .int(7))

        // And still refuses what will not fit.
        staged.editText = "300"
        #expect(staged.validationError != nil)
    }
}
