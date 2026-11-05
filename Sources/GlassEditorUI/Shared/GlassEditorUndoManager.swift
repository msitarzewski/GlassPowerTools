//
//  GlassEditorUndoManager.swift
//  Glass Power Tools — GlassEditorUI
//
//  The text view's undo manager, standing in for the editor's own undo (the owner, 2026-11-03: "making sure that all
//  of the expected text editor functions work in the... Editor. Like, for example, UNDO! LOL. It must be first
//  class.. like say TextEdit"). The editor keeps one undo authority, `UndoCoordinator`, and its text views had no undo
//  manager at all, so nothing the system offers reached it: Edit ▸ Undo stayed grey and ⌘Z did nothing on the Mac,
//  and on iPhone, iPad and Vision Pro neither ⌘Z, shake, the three-finger swipe nor the keyboard's undo button worked.
//  Only the iPhone Duo's own Undo button called it.
//
//  This manager records nothing — registration is disabled, so a text system that registers its own actions (UIKit's
//  typing) adds nothing — and answers every question and request from the editor: whether there is something to undo,
//  what it is called ("Undo Typing", "Redo Paste"), and doing it. Every system way to undo now arrives at the one
//  authority, through the responder chain as in TextEdit.
//

import Foundation
import GlassEditorCore

final class GlassEditorUndoManager: UndoManager {
    /// What the editor answers with; weak, as the text view holds this manager and the engine holds the view.
    struct Editor {
        let canUndo: @MainActor () -> Bool
        let canRedo: @MainActor () -> Bool
        let undo: @MainActor () -> Void
        let redo: @MainActor () -> Void
        let undoIntent: @MainActor () -> EditIntent?
        let redoIntent: @MainActor () -> EditIntent?
    }

    private let editor: Editor
    private var acting: (undoing: Bool, redoing: Bool) = (false, false)

    init(_ editor: Editor) {
        self.editor = editor
        super.init()
        // The editor records every change itself (`UndoCoordinator`); a second record would disagree with it.
        disableUndoRegistration()
    }

    override var canUndo: Bool { MainActor.assumeIsolated { editor.canUndo() } }
    override var canRedo: Bool { MainActor.assumeIsolated { editor.canRedo() } }

    override func undo() {
        guard canUndo else { return }
        acting.undoing = true
        defer { acting.undoing = false }
        MainActor.assumeIsolated { editor.undo() }
    }

    override func redo() {
        guard canRedo else { return }
        acting.redoing = true
        defer { acting.redoing = false }
        MainActor.assumeIsolated { editor.redo() }
    }

    /// One unit is one group here: what a system "undo the last group" asks for.
    override func undoNestedGroup() { undo() }

    override var isUndoing: Bool { acting.undoing }
    override var isRedoing: Bool { acting.redoing }

    override var undoActionName: String { MainActor.assumeIsolated { Self.name(of: editor.undoIntent()) } }
    override var redoActionName: String { MainActor.assumeIsolated { Self.name(of: editor.redoIntent()) } }
    // With no name, Foundation's title keeps the space before it ("Undo "): trimmed.
    override var undoMenuItemTitle: String {
        undoMenuTitle(forUndoActionName: undoActionName).trimmingCharacters(in: .whitespaces)
    }
    override var redoMenuItemTitle: String {
        redoMenuTitle(forUndoActionName: redoActionName).trimmingCharacters(in: .whitespaces)
    }

    // Nothing is kept here, so nothing is grouped, named or dropped here.
    override func setActionName(_ actionName: String) {}
    override func removeAllActions() {}
    override func removeAllActions(withTarget target: Any) {}

    /// What the menu calls an undo of this kind of change, as TextEdit names its own: "Undo Typing", "Undo Paste".
    static func name(of intent: EditIntent?) -> String {
        switch intent {
        case .typing?, .deleteBackward?: "Typing"
        case .deleteForward?: "Delete"
        case .paste?: "Paste"
        case .cut?: "Cut"
        case .drop?: "Drop"
        case .replaceAll?: "Replace All"
        case .replace?: "Replace"
        case .changeCase?: "Change Case"
        case .indentation?: "Indentation"
        case .completion?: "Completion"
        case .remoteReload?: "Reload"
        case .programmatic?, nil: ""
        }
    }
}
