#if canImport(AppKit) && os(macOS)

import Testing
import Foundation
import AppKit
@testable import GlassEditorUI
import GlassEditorCore

/// The Mac text view's indentation (2026-11-22): Return, Tab, ⇧Tab, ⌘] and ⌘[ as a person reaches them, through the
/// text view's own actions, so through its delegate to the document, each one undo step. A window never shown.
@Suite("AppKit backend: indentation", .serialized)
@MainActor
struct AppKitIndentationTests {
    private func makeEngine(_ content: String, language: LanguageID = .swift) throws -> (GlassEditorAppKitEngine, NSWindow) {
        let model = GlassEditorModel(snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
                                     language: language, builtInHighlighting: false)
        let engine = GlassEditorAppKitEngine(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        // ARC owns it; a window that also released itself on close is freed twice.
        window.isReleasedWhenClosed = false
        let content = try #require(window.contentView)
        engine.containerView.frame = content.bounds
        content.addSubview(engine.containerView)
        #expect(window.makeFirstResponder(engine.textView))
        return (engine, window)
    }

    private func select(_ range: NSRange, in engine: GlassEditorAppKitEngine) {
        engine.textView.setSelectedRange(range)
    }

    @Test("Return keeps the indent, a level more after a brace, and the closer goes to its own line")
    func returnKeepsTheIndent() throws {
        let (engine, window) = try makeEngine("func f() {}")
        defer { window.close() }
        select(NSRange(location: 10, length: 0), in: engine)
        engine.textView.insertNewline(nil)
        #expect(engine.textView.string == "func f() {\n    \n}")
        #expect(engine.model.text == engine.textView.string, "the document has it too")
        #expect(engine.textView.selectedRange() == NSRange(location: 15, length: 0), "the caret on the middle line")
        engine.textView.insertText("x", replacementRange: engine.textView.selectedRange())
        engine.textView.insertNewline(nil)
        #expect(engine.textView.string == "func f() {\n    x\n    \n}")
    }

    @Test("Tab in a file indented with tabs types a tab; in one with spaces, spaces to the next stop")
    func tabFollowsTheFile() throws {
        let (spaced, spacedWindow) = try makeEngine("if x {\n  a\n}\n")
        defer { spacedWindow.close() }
        #expect(spaced.model.configuration.indentation == Indentation(kind: .spaces, width: 2))
        select(NSRange(location: 10, length: 0), in: spaced)   // after "  a", column 3
        spaced.textView.insertTab(nil)
        #expect(spaced.textView.string == "if x {\n  a \n}\n", "one space reaches the stop at column 4")
        select(NSRange(location: 7, length: 0), in: spaced)    // the line's start
        spaced.textView.insertTab(nil)
        #expect(spaced.textView.string == "if x {\n    a \n}\n", "a whole level, two, from column 0")

        let (tabbed, tabbedWindow) = try makeEngine("if x {\n\ta\n}\n")
        defer { tabbedWindow.close() }
        select(NSRange(location: 7, length: 0), in: tabbed)
        tabbed.textView.insertTab(nil)
        #expect(tabbed.textView.string == "if x {\n\t\ta\n}\n")
    }

    @Test("Tab over lines indents them, ⇧Tab outdents, each one step undone as Indentation")
    func tabOverLines() throws {
        let (engine, window) = try makeEngine("a\nb\nc")
        defer { window.close() }
        select(NSRange(location: 0, length: 3), in: engine)   // "a\nb"
        engine.textView.insertTab(nil)
        #expect(engine.textView.string == "    a\n    b\nc")
        #expect(engine.model.text == engine.textView.string)
        #expect(engine.model.newestUndoIntent == .indentation)
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        #expect(engine.textView.validateMenuItem(undoItem))
        #expect(undoItem.title == "Undo Indentation")

        engine.textView.insertBacktab(nil)
        #expect(engine.textView.string == "a\nb\nc")
        #expect(engine.undo())
        #expect(engine.textView.string == "    a\n    b\nc", "the outdent undone alone")
        #expect(engine.undo())
        #expect(engine.textView.string == "a\nb\nc")
    }

    @Test("⌘] and ⌘[ reach the text from the menu as actions up the responder chain")
    func menuActions() throws {
        let (engine, window) = try makeEngine("let a = 1\nlet b = 2")
        defer { window.close() }
        select(NSRange(location: 4, length: 0), in: engine)
        #expect(engine.textView.tryToPerform(#selector(GlassTextView.indentLines(_:)), with: nil))
        #expect(engine.textView.string == "    let a = 1\nlet b = 2")
        #expect(engine.textView.selectedRange() == NSRange(location: 8, length: 0), "the caret moves with its text")
        #expect(engine.textView.tryToPerform(#selector(GlassTextView.outdentLines(_:)), with: nil))
        #expect(engine.textView.string == "let a = 1\nlet b = 2")
    }

    @Test("the line commands reach the text as menu actions, each one step named for itself")
    func lineCommands() throws {
        let (engine, window) = try makeEngine("let b = 2\nlet a = 1")
        defer { window.close() }
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        func perform(_ action: Selector) { #expect(engine.textView.tryToPerform(action, with: nil)) }

        select(NSRange(location: 0, length: 0), in: engine)
        perform(#selector(GlassTextView.toggleLineComments(_:)))
        #expect(engine.textView.string == "// let b = 2\nlet a = 1")
        #expect(engine.textView.validateMenuItem(undoItem) && undoItem.title == "Undo Comment")
        perform(#selector(GlassTextView.moveLinesDown(_:)))
        #expect(engine.textView.string == "let a = 1\n// let b = 2")
        #expect(engine.textView.selectedRange() == NSRange(location: 13, length: 0),
                "the caret, moved by the comment to before \"let\", went down with its line")
        #expect(engine.textView.validateMenuItem(undoItem) && undoItem.title == "Undo Move Lines")
        perform(#selector(GlassTextView.moveLinesUp(_:)))
        #expect(engine.textView.string == "// let b = 2\nlet a = 1")
        perform(#selector(GlassTextView.duplicateLines(_:)))
        #expect(engine.textView.string == "// let b = 2\n// let b = 2\nlet a = 1")
        perform(#selector(GlassTextView.deleteLines(_:)))
        #expect(engine.textView.string == "// let b = 2\nlet a = 1")
        select(NSRange(location: 0, length: (engine.textView.string as NSString).length), in: engine)
        perform(#selector(GlassTextView.toggleLineComments(_:)))
        #expect(engine.textView.string == "// // let b = 2\n// let a = 1", "mixed lines comment, not uncomment")
        perform(#selector(GlassTextView.toggleLineComments(_:)))
        #expect(engine.textView.string == "// let b = 2\nlet a = 1")
        perform(#selector(GlassTextView.sortLines(_:)))
        #expect(engine.textView.string == "// let b = 2\nlet a = 1", "already in order: nothing")
        perform(#selector(GlassTextView.joinLines(_:)))
        #expect(engine.textView.string == "// let b = 2 let a = 1")
        #expect(engine.model.text == engine.textView.string)
        #expect(engine.undo())
        #expect(engine.textView.string == "// let b = 2\nlet a = 1", "the join undone alone")
    }

    @Test("a tab is drawn the indentation's width in the document's font")
    func tabStops() throws {
        let (engine, window) = try makeEngine("\tx")
        defer { window.close() }
        let style = try #require(engine.textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                                 as? NSParagraphStyle)
        let font = AttributedAssembly.font(configuration: engine.model.configuration, surface: .opaque)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        #expect(abs(style.defaultTabInterval - space * 4) < 0.01)
        #expect(style.tabStops.isEmpty)
    }
}

#endif
