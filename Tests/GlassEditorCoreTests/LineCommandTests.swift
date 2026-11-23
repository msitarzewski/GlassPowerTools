import Foundation
import Testing
@testable import GlassEditorCore

/// The line commands (2026-11-22): ⌘/ comments by the language, and duplicate, move, delete, join and sort lines, each
/// one edit over whole lines with the selection where it belongs after.
@Suite("Line commands")
struct LineCommandTests {
    /// The text after `lineEdit`, with the selection marked: [ and ] around a selection, | at a caret.
    private func result(_ lineEdit: LineEdit?, on text: String) -> String? {
        guard let lineEdit else { return nil }
        let range = NSRange(location: lineEdit.edit.replacementRange.lowerBound,
                            length: lineEdit.edit.replacementRange.count)
        let changed = NSMutableString(string: (text as NSString).replacingCharacters(in: range, with: lineEdit.edit.text))
        if lineEdit.selection.isEmpty {
            changed.insert("|", at: lineEdit.selection.lowerBound)
        } else {
            changed.insert("]", at: lineEdit.selection.upperBound)
            changed.insert("[", at: lineEdit.selection.lowerBound)
        }
        return changed as String
    }

    // MARK: Comment

    @Test("⌘/ comments lines out at their shallowest indent, and back in when every line with text is commented")
    func lineComments() {
        let swift = "func f() {\n    let a = 1\n\n        b()\n}"
        // From the second line's start to the end of "b()".
        let out = LineEditing.toggleComment(swift as NSString, selection: 11..<37, language: .swift)
        #expect(result(out, on: swift) == "func f() {\n[    // let a = 1\n\n    //     b()]\n}")
        let commented = "func f() {\n    // let a = 1\n\n    //     b()\n}"
        let back = LineEditing.toggleComment(commented as NSString, selection: 11..<43, language: .swift)
        #expect(result(back, on: commented) == "func f() {\n[    let a = 1\n\n        b()]\n}")
        // A caret moves with its text; mixed lines comment rather than uncomment.
        #expect(result(LineEditing.toggleComment("x = 1" as NSString, selection: 2..<2, language: .python),
                       on: "x = 1") == "# x |= 1")
        #expect(result(LineEditing.toggleComment("-- a\nb" as NSString, selection: 0..<6, language: .sql),
                       on: "-- a\nb") == "[-- -- a\n-- b]")
        // "#" with no space after comes out too.
        #expect(result(LineEditing.toggleComment("#x" as NSString, selection: 0..<0, language: .bash), on: "#x") == "|x")
        // JSON and plain text have no comments; blank lines alone are nothing to do.
        #expect(LineEditing.toggleComment("{}" as NSString, selection: 0..<0, language: .json) == nil)
        #expect(LineEditing.toggleComment("  \n" as NSString, selection: 0..<1, language: .swift) == nil)
    }

    @Test("HTML, XML and Markdown wrap their lines in one block comment, and unwrap it")
    func blockComments() {
        let html = "  <p>a</p>\n  <p>b</p>"
        let wrapped = LineEditing.toggleComment(html as NSString, selection: 0..<21, language: .html)
        #expect(result(wrapped, on: html) == "[  <!-- <p>a</p>\n  <p>b</p> -->]")
        let back = "  <!-- <p>a</p>\n  <p>b</p> -->"
        #expect(result(LineEditing.toggleComment(back as NSString, selection: 0..<30, language: .html), on: back)
                == "[  <p>a</p>\n  <p>b</p>]")
        // A selection past the end, as a view that has since changed could hand over, is clamped, not trusted.
        #expect(result(LineEditing.toggleComment(back as NSString, selection: 0..<99, language: .html), on: back)
                == "[  <p>a</p>\n  <p>b</p>]")
        // UTF-16 offsets past an emoji.
        let emoji = "🙂 x"
        #expect(result(LineEditing.toggleComment(emoji as NSString, selection: 0..<0, language: .markdown), on: emoji)
                == "<!-- |🙂 x -->")
    }

    // MARK: Duplicate, move, delete

    @Test("duplicate puts the lines below themselves and the selection on the copy; the last line takes a break")
    func duplicate() {
        #expect(result(LineEditing.duplicate("a\nb\n" as NSString, selection: 0..<1), on: "a\nb\n") == "a\n[a]\nb\n")
        #expect(result(LineEditing.duplicate("a\nb" as NSString, selection: 3..<3), on: "a\nb") == "a\nb\nb|")
        #expect(result(LineEditing.duplicate("a\r\nb" as NSString, selection: 3..<3), on: "a\r\nb") == "a\r\nb\r\n|b",
                "the file's own break; the caret at the copy's start, as it was at the line's")
    }

    @Test("move swaps the lines with the one above or below, breaks staying in place, the selection with its text")
    func move() {
        let text = "one\ntwo\nthree"
        #expect(result(LineEditing.move(text as NSString, selection: 5..<5, up: true), on: text) == "t|wo\none\nthree")
        #expect(result(LineEditing.move(text as NSString, selection: 5..<5, up: false), on: text) == "one\nthree\nt|wo")
        // Whole lines down to the next line's start: the selection keeps them. Breaks stay in their places, so the
        // file still ends without one.
        #expect(result(LineEditing.move(text as NSString, selection: 0..<8, up: false), on: text)
                == "three\n[one\ntwo]")
        // The last line moved up: the break that was before it stays at the file's end... none.
        #expect(result(LineEditing.move(text as NSString, selection: 9..<9, up: true), on: text) == "one\nt|hree\ntwo")
        #expect(LineEditing.move(text as NSString, selection: 0..<0, up: true) == nil, "at the top")
        #expect(LineEditing.move(text as NSString, selection: 9..<9, up: false) == nil, "at the bottom")
    }

    @Test("delete takes the lines and their breaks; the last line takes the break before it")
    func delete() {
        #expect(result(LineEditing.delete("a\nb\nc" as NSString, selection: 2..<2), on: "a\nb\nc") == "a\n|c")
        #expect(result(LineEditing.delete("a\nb\nc" as NSString, selection: 4..<5), on: "a\nb\nc") == "a\nb|")
        #expect(result(LineEditing.delete("a" as NSString, selection: 0..<0), on: "a") == "|")
        #expect(LineEditing.delete("" as NSString, selection: 0..<0) == nil)
    }

    // MARK: Join and sort

    @Test("join puts a caret's line and the next together with one space; a selection's lines all together")
    func join() {
        #expect(result(LineEditing.join("let a =  \n    1\nb" as NSString, selection: 3..<3), on: "let a =  \n    1\nb")
                == "let a =| 1\nb")
        #expect(result(LineEditing.join("a\n  b\n\n  c\nd" as NSString, selection: 0..<9), on: "a\n  b\n\n  c\nd")
                == "[a b c]\nd")
        #expect(LineEditing.join("a" as NSString, selection: 0..<0) == nil, "no next line")
    }

    @Test("sort orders the selection's lines as Finder orders names, breaks in place; nil when already in order")
    func sort() {
        let text = "item10\nItem2\nitem1"
        #expect(result(LineEditing.sort(text as NSString, selection: 0..<18), on: text) == "[item1\nItem2\nitem10]")
        #expect(LineEditing.sort("a\nb" as NSString, selection: 0..<3) == nil)
        #expect(LineEditing.sort("b\na" as NSString, selection: 0..<0) == nil, "one line")
    }
}
