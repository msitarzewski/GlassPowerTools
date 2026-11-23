#if canImport(UIKit) && !os(macOS)

import Testing
import Foundation
import UIKit
@testable import GlassEditorUI
import GlassEditorCore

/// Indentation on iPhone, iPad and Vision Pro (2026-11-22): the Mac's rules, from the same `LineEditing`. ⌘], ⌘[ and
/// ⇧Tab are the text view's own key commands; the selection menu has them under Lines for a finger. Run on the iOS
/// simulator (`EditorUITests` scheme).
@Suite("UIKit backend: indentation", .serialized)
@MainActor
struct UIKitIndentationTests {
    private func makeEngine(_ content: String) -> (GlassEditorUIKitEngine, UIWindow) {
        let model = GlassEditorModel(snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
                                     language: .swift, builtInHighlighting: false)
        let engine = GlassEditorUIKitEngine(model: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        engine.containerView.frame = window.bounds
        window.addSubview(engine.containerView)
        window.isHidden = false
        engine.containerView.layoutIfNeeded()
        return (engine, window)
    }

    @Test("⌘] and ⌘[ indent and outdent the selection's lines, one step each, and the view follows the document")
    func indentAndOutdent() throws {
        let (engine, window) = makeEngine("a\nb\nc")
        _ = window
        engine.textView.selectedRange = NSRange(location: 0, length: 3)
        engine.textView.indentLines(nil)
        #expect(engine.text == "    a\n    b\nc")
        #expect(engine.textView.text == engine.text)
        #expect(engine.textView.selectedRange == NSRange(location: 0, length: 11))
        #expect(engine.model.newestUndoIntent == .indentation)
        let manager = try #require(engine.textView.undoManager)
        #expect(manager.undoMenuItemTitle == "Undo Indentation")

        engine.textView.outdentLines(nil)
        #expect(engine.textView.text == "a\nb\nc")
        manager.undo()
        #expect(engine.textView.text == "    a\n    b\nc", "the outdent undone alone")
    }

    @Test("the key commands are the text view's, titled for the ⌘ overlay, ⇧Tab ahead of the system's")
    func keyCommands() throws {
        let (engine, window) = makeEngine("x")
        _ = window
        let commands = engine.textView.keyCommands ?? []
        let indent = try #require(commands.first { $0.input == "]" && $0.modifierFlags == .command })
        #expect(indent.title == "Indent")
        let outdent = try #require(commands.first { $0.input == "[" && $0.modifierFlags == .command })
        #expect(outdent.title == "Outdent")
        let backtab = try #require(commands.first { $0.input == "\t" && $0.modifierFlags == .shift })
        #expect(backtab.wantsPriorityOverSystemBehavior)
        engine.textView.isEditable = false
        #expect((engine.textView.keyCommands ?? []).allSatisfy { $0.input != "]" }, "read-only text has none")
    }

    @Test("the selection menu has Lines, with Indent and Outdent, at a caret too")
    func linesMenu() throws {
        let (engine, window) = makeEngine("let a = 1")
        _ = window
        let menu = try #require(engine.coordinator.textView(engine.textView,
                                                             editMenuForTextIn: NSRange(location: 3, length: 0),
                                                             suggestedActions: []))
        let lines = try #require(menu.children.compactMap { $0 as? UIMenu }.first { $0.title == "Lines" })
        #expect(lines.children.compactMap { ($0 as? UIAction)?.title }
                == ["Indent", "Outdent", "Comment or Uncomment", "Move Up", "Move Down", "Duplicate", "Delete", "Join",
                    "Sort"])
    }

    @Test("the line commands: each one step, named for itself, and the view follows the document")
    func lineCommands() throws {
        let (engine, window) = makeEngine("let b = 2\nlet a = 1")
        _ = window
        let manager = try #require(engine.textView.undoManager)
        engine.textView.selectedRange = NSRange(location: 0, length: 0)
        engine.textView.toggleLineComments(nil)
        #expect(engine.textView.text == "// let b = 2\nlet a = 1")
        #expect(manager.undoMenuItemTitle == "Undo Comment")
        engine.textView.moveLinesDown(nil)
        #expect(engine.textView.text == "let a = 1\n// let b = 2")
        #expect(engine.textView.selectedRange == NSRange(location: 13, length: 0),
                "the caret, moved by the comment to before \"let\", went down with its line")
        #expect(manager.undoMenuItemTitle == "Undo Move Lines")
        engine.textView.duplicateLines(nil)
        #expect(engine.textView.text == "let a = 1\n// let b = 2\n// let b = 2")
        engine.textView.deleteLines(nil)
        #expect(engine.textView.text == "let a = 1\n// let b = 2")
        engine.textView.selectedRange = NSRange(location: 0, length: (engine.text as NSString).length)
        engine.textView.sortLines(nil)
        #expect(engine.textView.text == "// let b = 2\nlet a = 1")
        engine.textView.joinLines(nil)
        #expect(engine.textView.text == "// let b = 2 let a = 1")
        #expect(engine.model.text == engine.textView.text)
        manager.undo()
        #expect(engine.textView.text == "// let b = 2\nlet a = 1", "the join undone alone")
    }

    @Test("the line commands' keys are the Mac's")
    func lineCommandKeys() throws {
        let (engine, window) = makeEngine("x")
        _ = window
        let commands = engine.textView.keyCommands ?? []
        #expect(commands.contains { $0.input == "/" && $0.modifierFlags == .command })
        #expect(commands.contains { $0.input == UIKeyCommand.inputUpArrow && $0.modifierFlags == [.control, .command] })
        #expect(commands.contains { $0.input == UIKeyCommand.inputDownArrow && $0.modifierFlags == [.control, .command] })
        #expect(commands.contains { $0.input == "k" && $0.modifierFlags == [.command, .shift] })
    }

    /// Return and Tab as the keyboard sends them: it asks the delegate first, and the delegate makes them itself and
    /// answers no. (An override of `insertText` was tried first: UIKit changed the view without asking the delegate,
    /// and the document never had the indent. That is what the last expectation of each step guards.)
    private func press(_ key: String, in engine: GlassEditorUIKitEngine) -> Bool {
        engine.coordinator.textView(engine.textView, shouldChangeTextIn: engine.textView.selectedRange,
                                    replacementText: key)
    }

    @Test("Return keeps the indent and Tab types to the stop, made by the delegate in the document and the view alike")
    func returnAndTabAsTheKeyboardAsks() throws {
        let (engine, window) = makeEngine("func f() {}\n    x")
        _ = window
        engine.textView.selectedRange = NSRange(location: 10, length: 0)
        #expect(press("\n", in: engine) == false, "made here; UIKit types nothing more")
        #expect(engine.text == "func f() {\n    \n}\n    x")
        #expect(engine.textView.text == engine.text)
        #expect(engine.textView.selectedRange == NSRange(location: 15, length: 0))
        #expect(engine.model.selectedRange == 15..<15)

        engine.textView.selectedRange = NSRange(location: (engine.text as NSString).length, length: 0)
        #expect(press("\n", in: engine) == false)
        #expect(engine.text.hasSuffix("\n    x\n    "))
        #expect(press("\t", in: engine) == false)
        #expect(engine.text.hasSuffix("\n    x\n        "), "spaces to the next stop: the file indents with spaces")
        #expect(engine.textView.text == engine.text)

        // Tab over lines indents them.
        engine.textView.selectedRange = NSRange(location: 0, length: 12)
        #expect(press("\t", in: engine) == false)
        #expect(engine.text.hasPrefix("    func f() {\n        \n"))
        #expect(engine.textView.text == engine.text)
        // Any other key is UIKit's to type, as before.
        engine.textView.selectedRange = NSRange(location: 4, length: 0)
        #expect(press("a", in: engine) == true)
    }

    @Test("a tab is drawn the indentation's width in the document's font")
    func tabStops() throws {
        let (engine, window) = makeEngine("\tx")
        _ = window
        let style = try #require(engine.textView.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                                 as? NSParagraphStyle)
        let font = AttributedAssembly.font(configuration: engine.model.configuration, surface: .opaque)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        #expect(abs(style.defaultTabInterval - space * CGFloat(engine.model.configuration.indentation.width)) < 0.01)
    }
}

#endif
