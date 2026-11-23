import Foundation
import Testing
@testable import GlassEditorCore

/// The editor's first gaps (2026-11-22): Return keeps a line's indent, Tab and the indent commands indent by the
/// document's own indentation, which its lines decide when they say anything.
@Suite("Indentation and the line rules")
struct LineEditingTests {

    // MARK: Detection

    @Test("a file's own indentation is found: tabs, two spaces, four, and none")
    func detection() {
        let tabbed = "func a() {\n\tlet x = 1\n\tif x {\n\t\treturn\n\t}\n}\n"
        #expect(Indentation.detect(in: tabbed, defaultWidth: 4) == Indentation(kind: .tabs, width: 4))
        #expect(Indentation.detect(in: tabbed, defaultWidth: 8) == Indentation(kind: .tabs, width: 8),
                "a tab's width is the reader's")

        let two = "a:\n  b:\n    c: 1\n  d: 2\n"
        #expect(Indentation.detect(in: two, defaultWidth: 4) == Indentation(kind: .spaces, width: 2))

        let four = "def f():\n    if x:\n        return 1\n    return 2\n"
        #expect(Indentation.detect(in: four, defaultWidth: 2) == Indentation(kind: .spaces, width: 4))

        #expect(Indentation.detect(in: "one\ntwo\n\nthree", defaultWidth: 4) == nil, "nothing indented says nothing")
        #expect(Indentation.detect(in: "", defaultWidth: 4) == nil)
        // A block comment's single-space " *" is not a style.
        #expect(Indentation.detect(in: "/**\n * doc\n */\nlet x = 1\n", defaultWidth: 4) == nil)
        // CRLF reads the same.
        #expect(Indentation.detect(in: "a {\r\n  b\r\n    c\r\n}\r\n", defaultWidth: 4)
                == Indentation(kind: .spaces, width: 2))
    }

    @Test("a document's own indentation stays when settings change; a tab's width follows them")
    func followingSettings() {
        let settings = Indentation(kind: .spaces, width: 2)
        #expect(Indentation.standard.following(settings, from: .settings) == settings)
        #expect(Indentation(kind: .spaces, width: 4).following(settings, from: .file) == Indentation(kind: .spaces, width: 4))
        #expect(Indentation(kind: .tabs, width: 4).following(settings, from: .file) == Indentation(kind: .tabs, width: 2))
        #expect(Indentation(kind: .tabs, width: 8).following(settings, from: .chosen) == Indentation(kind: .tabs, width: 8))
    }

    // MARK: Return

    private func newline(_ text: String, at caret: Int, _ indentation: Indentation = .standard,
                         _ language: LanguageID = .swift) -> String {
        let result = LineEditing.newline(in: text as NSString, replacing: caret..<caret, indentation: indentation,
                                         language: language)
        let inserted = (text as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: result.text)
        // The caret, marked with |, where the rule puts it.
        return (inserted as NSString).replacingCharacters(in: NSRange(location: caret + result.caret, length: 0),
                                                         with: "|")
    }

    @Test("Return keeps the line's indent, and goes a level deeper after an opening bracket")
    func returnKeepsTheIndent() {
        #expect(newline("    let x = 1", at: 13) == "    let x = 1\n    |")
        #expect(newline("\tlet x = 1", at: 10, Indentation(kind: .tabs, width: 4)) == "\tlet x = 1\n\t|")
        #expect(newline("if x {", at: 6) == "if x {\n    |")
        #expect(newline("  call(", at: 7, Indentation(kind: .spaces, width: 2)) == "  call(\n    |")
        // Between a pair: the closer to a line of its own, at the old level.
        #expect(newline("    if x {}", at: 10) == "    if x {\n        |\n    }")
        #expect(newline("[]", at: 1, .standard, .json) == "[\n    |\n]")
        // Python and YAML after a colon; not Swift.
        #expect(newline("def f():", at: 8, .standard, .python) == "def f():\n    |")
        #expect(newline("case 1:", at: 7, .standard, .swift) == "case 1:\n|")
        // Prose keeps the indent and no more.
        #expect(newline("  (aside", at: 8, .standard, .plaintext) == "  (aside\n  |")
        // A caret inside the indent keeps only what is before it.
        #expect(newline("        x", at: 4) == "    \n    |    x")
        #expect(newline("", at: 0) == "\n|")
    }

    // MARK: Tab

    @Test("Tab types to the next tab stop in spaces, or a tab")
    func tabToTheNextStop() {
        let spaces = Indentation(kind: .spaces, width: 4)
        #expect(LineEditing.tab(in: "", at: 0, indentation: spaces) == "    ")
        #expect(LineEditing.tab(in: "ab", at: 2, indentation: spaces) == "  ")
        #expect(LineEditing.tab(in: "abcd", at: 4, indentation: spaces) == "    ")
        #expect(LineEditing.tab(in: "\tx", at: 2, indentation: spaces) == "   ", "a tab counts to its stop")
        #expect(LineEditing.tab(in: "ab", at: 2, indentation: Indentation(kind: .tabs, width: 4)) == "\t")
        #expect(LineEditing.selectionSpansLines(0..<4, in: "ab\ncd") == true)
        #expect(LineEditing.selectionSpansLines(0..<2, in: "ab\ncd") == false, "inside one line, Tab types")
        #expect(LineEditing.selectionSpansLines(0..<3, in: "ab\ncd") == true,
                "a whole line with its break, as a triple click selects it, is indented, not typed over")
        #expect(LineEditing.selectionSpansLines(1..<1, in: "ab\ncd") == false)
    }

    // MARK: Indent and outdent

    private func apply(_ lineEdit: LineEdit?, to text: String) -> (String, Range<Int>)? {
        guard let lineEdit else { return nil }
        let range = NSRange(location: lineEdit.edit.replacementRange.lowerBound,
                            length: lineEdit.edit.replacementRange.count)
        return ((text as NSString).replacingCharacters(in: range, with: lineEdit.edit.text), lineEdit.selection)
    }

    @Test("indent adds a level to every line the selection touches, not to empty ones, and keeps the selection's text")
    func indentLines() throws {
        let text = "a\n\nb\nc\n"
        // "a" to "b", by a selection ending inside "b".
        let (indented, selection) = try #require(apply(LineEditing.indent(text as NSString, selection: 0..<4,
                                                                          indentation: .standard), to: text))
        #expect(indented == "    a\n\n    b\nc\n")
        #expect((indented as NSString).substring(with: NSRange(location: selection.lowerBound,
                                                               length: selection.count)) == "    a\n\n    b",
                "whole lines from their start take the new indent in")
        // A caret moves with its text.
        let (_, caret) = try #require(apply(LineEditing.indent(text as NSString, selection: 5..<5,
                                                               indentation: .standard), to: text))
        #expect(caret == 9..<9)
        // A selection ending at a line's start leaves that line alone.
        let (twoLines, _) = try #require(apply(LineEditing.indent("a\nb\nc" as NSString, selection: 0..<4,
                                                                  indentation: .standard), to: "a\nb\nc"))
        #expect(twoLines == "    a\n    b\nc")
        // Tabs.
        let (tabbed, _) = try #require(apply(LineEditing.indent("x" as NSString, selection: 0..<0,
                                                                indentation: Indentation(kind: .tabs, width: 4)), to: "x"))
        #expect(tabbed == "\tx")
        #expect(LineEditing.indent("\n\n" as NSString, selection: 0..<2, indentation: .standard) == nil,
                "only empty lines: nothing to do")
    }

    @Test("outdent takes a tab or up to a level of spaces from each line, and nothing from a line with none")
    func outdentLines() throws {
        let text = "        a\n  b\n\tc\nd"
        let (outdented, selection) = try #require(apply(LineEditing.outdent(text as NSString,
                                                                            selection: 0..<(text as NSString).length,
                                                                            indentation: .standard), to: text))
        #expect(outdented == "    a\nb\nc\nd")
        #expect(selection == 0..<(outdented as NSString).length)
        // A caret inside the removed indent goes to the line's new start of text.
        let (_, caret) = try #require(apply(LineEditing.outdent("    a" as NSString, selection: 2..<2,
                                                                indentation: .standard), to: "    a"))
        #expect(caret == 0..<0)
        #expect(LineEditing.outdent("a\nb" as NSString, selection: 0..<3, indentation: .standard) == nil)
    }
}
