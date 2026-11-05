#if canImport(UIKit) && !os(macOS)

import Testing
import Foundation
import UIKit
@testable import GlassEditorUI
import GlassEditorCore

/// Undo on iPhone, iPad and Vision Pro (the owner, 2026-11-03: "UNDO! LOL. It must be first class.. like say
/// TextEdit"). UIKit has no undo action for a view to answer: ⌘Z, the iPad's Edit ▸ Undo, shake to undo, the
/// three-finger swipe and the keyboard's undo button all ask the first responder for its `undoManager`. The editor's
/// text view had none, so none of them did anything. Run on the iOS simulator (`EditorUITests` scheme).
@Suite("UIKit backend: undo as the system offers it")
@MainActor
struct UIKitUndoTests {
    private func makeEngine(_ content: String) -> (GlassEditorUIKitEngine, UIWindow) {
        let model = GlassEditorModel(snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
                                     configuration: GlassEditorConfiguration())
        let engine = GlassEditorUIKitEngine(model: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        engine.containerView.frame = window.bounds
        window.addSubview(engine.containerView)
        window.isHidden = false
        engine.containerView.layoutIfNeeded()
        return (engine, window)
    }

    /// A change as UIKit makes one from a keystroke: asked of the text view's delegate, then made in its text. (A test
    /// host has no keyboard session for `insertText` to type into.)
    private func type(_ text: String, replacing range: NSRange, in engine: GlassEditorUIKitEngine) {
        guard engine.coordinator.textView(engine.textView, shouldChangeTextIn: range, replacementText: text) else { return }
        engine.textView.textStorage.replaceCharacters(in: range, with: text)
        engine.textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
        engine.coordinator.textViewDidChange(engine.textView)
    }

    @Test("the text view's undo manager is the editor's: typing undone and redone through it, named as TextEdit names it")
    func undoThroughTheTextViewsManager() throws {
        let (engine, window) = makeEngine("let x = 1")
        _ = window
        let manager = try #require(engine.textView.undoManager, "UIKit's undo finds a manager on the first responder")
        #expect(!manager.canUndo)

        type("0", replacing: NSRange(location: 9, length: 0), in: engine)
        #expect(engine.text == "let x = 10")
        #expect(manager.canUndo)
        #expect(manager.undoMenuItemTitle == "Undo Typing")

        manager.undo()
        #expect(engine.text == "let x = 1")
        #expect(engine.textView.text == "let x = 1")
        #expect(manager.redoMenuItemTitle == "Redo Typing")
        manager.redo()
        #expect(engine.textView.text == "let x = 10")
    }

    @Test("what UIKit registers on its own adds nothing: the editor's undo is the only one")
    func noSecondRecord() throws {
        let (engine, window) = makeEngine("abc")
        _ = window
        let manager = try #require(engine.textView.undoManager)
        #expect(manager.isUndoRegistrationEnabled == false)
        // As UIKit's text system records its own typing: nothing kept.
        var undoneByUIKitsRecord = false
        manager.registerUndo(withTarget: engine.textView) { _ in undoneByUIKitsRecord = true }
        #expect(!manager.canUndo, "nothing typed in the editor, nothing to undo")

        type("d", replacing: NSRange(location: 3, length: 0), in: engine)
        type("e", replacing: NSRange(location: 4, length: 0), in: engine)
        #expect(engine.text == "abcde")
        // One typing run, one undo: back to the start, not one letter.
        manager.undo()
        #expect(engine.text == "abc")
        #expect(!manager.canUndo)
        #expect(!undoneByUIKitsRecord)
    }

    @Test("a backspace and a paste are their own steps, named Typing and Paste")
    func namedSteps() throws {
        let (engine, window) = makeEngine("alpha")
        _ = window
        let manager = try #require(engine.textView.undoManager)
        type("", replacing: NSRange(location: 4, length: 1), in: engine)
        #expect(engine.text == "alph")
        #expect(manager.undoMenuItemTitle == "Undo Typing")
        // As `paste(_:)` tags it, without touching the pasteboard here.
        engine.textView.pendingIntent = .paste
        type(" bravo", replacing: NSRange(location: 4, length: 0), in: engine)
        #expect(engine.text == "alph bravo")
        #expect(manager.undoMenuItemTitle == "Undo Paste")
        manager.undo()
        #expect(engine.text == "alph")
        manager.undo()
        #expect(engine.text == "alpha")
    }

    @Test("the selection's menu has Transformations: one step each, named Change Case, the change left selected")
    func transformations() throws {
        let (engine, window) = makeEngine("let shopName = 1")
        _ = window
        let manager = try #require(engine.textView.undoManager)
        let selection = NSRange(location: 4, length: 8)

        // The menu shown on a selection: the system's actions, then Transformations.
        let menu = try #require(engine.coordinator.textView(engine.textView, editMenuForTextIn: selection,
                                                             suggestedActions: []))
        let transformations = try #require(menu.children.compactMap { $0 as? UIMenu }.first { $0.title == "Transformations" })
        #expect(transformations.children.compactMap { ($0 as? UIAction)?.title }
                    == ["Make Upper Case", "Make Lower Case", "Capitalize"])
        // Nothing selected: the system's own menu.
        #expect(engine.coordinator.textView(engine.textView, editMenuForTextIn: NSRange(location: 4, length: 0),
                                            suggestedActions: []) == nil)

        engine.coordinator.changeCase(in: engine.textView, range: selection) { $0.uppercased() }
        #expect(engine.text == "let SHOPNAME = 1")
        #expect(engine.textView.selectedRange == selection, "the change left selected")
        #expect(manager.undoMenuItemTitle == "Undo Change Case")
        manager.undo()
        #expect(engine.text == "let shopName = 1")
    }
}

#endif
