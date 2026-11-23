#if canImport(AppKit) && os(macOS)

import AppKit
import GlassEditorCore

/// The macOS text view, on the text system it was built with, drawing its own canvas.
///
/// **D36 (2026-09-23): the Mac editor runs on TextKit 1**, built by `makeTextKit1()` with
/// non-contiguous layout — lay out only what is shown, even inside one enormous line. Measured on a
/// 14.6 MB one-line file: TextKit 1 opens in 0.3 s and scrolls at well under a frame; TextKit 2
/// took ~5 s in the app and could not scroll it, because its unit of layout is the paragraph. The
/// research is `memory-bank/tasks/2026-09/2026-09-23_text-engine-research.md`. TextKit 2 stays
/// available (`makeTextKit2()`) behind the same type; everything below that mentions it applies to
/// a view built that way.
///
/// **On TextKit 2, TextKit 2 is not optional.** `NSTextView` still ships a TextKit 1
/// compatibility mode, and it is entered *implicitly*: touching
/// `NSTextView.layoutManager` (or `NSTextContainer.layoutManager`) makes AppKit
/// tear down `NSTextLayoutManager` and rebuild the view on `NSLayoutManager`,
/// after which `textLayoutManager` is `nil` and the gutter's fragment
/// enumeration silently returns nothing. Nothing in this package reads
/// `layoutManager` — `assertUsingTextKit2()` is the tripwire.
///
/// The stack is built explicitly rather than via
/// `NSTextView(usingTextLayoutManager:)` so the container, the layout manager and
/// the content storage are all reachable by the coordinator and the gutter
/// without a second lookup, and so subclass identity is guaranteed by using the
/// designated initializer.
///
/// **Background ownership.** `drawsBackground` is off, exactly as the shipped
/// AppKit path does it (`HighlightedTextEditor.swift:219, 227`), and the canvas is
/// painted here instead: the theme background at the alpha
/// `AttributedAssembly.canvasBackgroundAlpha(for:)` derives from the surface. The
/// window's material and blur belong to the consumer; this view owns the text
/// canvas and nothing outside it.
public final class GlassTextView: NSTextView {

    /// Fill color for the canvas. Set by the engine whenever theme or surface
    /// changes; never a literal (projectRules.md, Theming).
    public var canvasColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    /// Font size the current attributes were built with.
    ///
    /// Reproduces `appliedFontSize` (`HighlightedTextEditor.swift:241, 273, 276`):
    /// a font-size change has to force a re-application even when the text is
    /// unchanged, because the size lives in the attributes rather than in the
    /// string. Without it, dragging the size slider leaves the document at the
    /// old size until the next keystroke.
    public var appliedFontSize: CGFloat = 0

    /// One-shot intent for the edit the user is about to make, set by the
    /// AppKit action that caused it (`paste:`, `deleteBackward:`,
    /// `deleteForward:`). Consumed by the coordinator on the next
    /// `shouldChangeTextIn`, then cleared.
    var pendingIntent: EditIntent?

    /// The text system this view was built on. Fixed at construction.
    public enum TextSystem: Sendable { case textKit1, textKit2 }
    public private(set) var textSystem: TextSystem = .textKit2

    /// The TextKit 2 content storage, reached without ever naming
    /// `layoutManager`. Nil on TextKit 1.
    public var contentStorage: NSTextContentStorage? {
        textLayoutManager?.textContentManager as? NSTextContentStorage
    }

    /// The characters and their attributes, on either text system — the one place that knows the
    /// difference, so no caller reaches for `layoutManager` on a TextKit 2 view by accident.
    public var glassTextStorage: NSTextStorage? {
        switch textSystem {
        case .textKit2: contentStorage?.textStorage
        case .textKit1: textStorage
        }
    }

    // MARK: - Construction

    /// Builds a TextKit 2 view: content storage → layout manager → container →
    /// view. Every link is explicit so none of it can be established lazily by
    /// AppKit in TextKit 1 mode.
    public static func makeTextKit2() -> GlassTextView {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)

        let view = GlassTextView(frame: .zero, textContainer: container)
        view.assertUsingTextKit2()
        return view
    }

    /// Builds a TextKit 1 view: storage → layout manager → container → view, with **non-contiguous
    /// layout** on, which is the whole reason for building it (D36).
    public static func makeTextKit1() -> GlassTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(container)
        let view = GlassTextView(frame: .zero, textContainer: container)
        view.textSystem = .textKit1
        return view
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureForCodeEditing()
    }

    /// This view is constructed programmatically by `makeTextKit2()`; a coder
    /// path would have to re-establish the TextKit 2 stack and there is no
    /// storyboard or nib in a Swift package to load it from.
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("GlassTextView is created programmatically; use makeTextKit2()")
    }

    /// The typing behaviors both shipped backends already agree on
    /// (INTEGRATION.md A3): no autocorrect, no smart quotes or dashes, no
    /// spell-check, no rich text. A SQL editor that turns `"` into `"` corrupts
    /// queries.
    private func configureForCodeEditing() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        isEditable = true
        isSelectable = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false

        // One undo authority. `UndoCoordinator` owns the stacks; AppKit's own
        // undo would record the same keystrokes into a second stack with
        // different unit boundaries, and the two would disagree the first time a
        // typing run coalesced differently. The shipped AppKit path set
        // `allowsUndo = true` (`HighlightedTextEditor.swift:230`) because it had
        // no coordinator to defer to — that is the behavior being replaced, not
        // the behavior being preserved.
        allowsUndo = false

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = NSSize(
            width: EditorMetrics.containerInset, height: EditorMetrics.containerInset
        )
        textContainer?.widthTracksTextView = true
    }

    // MARK: - TextKit 2 tripwire

    /// Traps in debug if the view has fallen back to TextKit 1.
    ///
    /// Called after construction and after every programmatic content change:
    /// the downgrade is triggered by a property *read*, so it can be introduced
    /// by an innocuous-looking line anywhere and would otherwise present as a
    /// gutter that quietly stops drawing.
    public func assertUsingTextKit2() {
        assert(
            textLayoutManager != nil,
            "GlassTextView fell back to TextKit 1 — something read `layoutManager`"
        )
    }

    /// The tripwire for whichever system the view was built on: a TextKit 2 view must still be on
    /// TextKit 2; a TextKit 1 view must still have its non-contiguous layout manager.
    public func assertOnItsTextSystem() {
        switch textSystem {
        case .textKit2: assertUsingTextKit2()
        case .textKit1:
            assert(layoutManager?.allowsNonContiguousLayout == true,
                   "GlassTextView lost its non-contiguous TextKit 1 layout manager")
        }
    }

    /// Whether TextKit 2 is still in force. Public so a consumer embedding this
    /// view can assert it too.
    public var isUsingTextKit2: Bool { textLayoutManager != nil }

    // MARK: - Background

    public override func draw(_ dirtyRect: NSRect) {
        canvasColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    // MARK: - Undo authority

    /// The editor's own undo, as this view's undo manager (`GlassEditorUndoManager`, set by the engine).
    ///
    /// `allowsUndo = false` stops `NSTextView` recording into it, and the manager records nothing anyway: it answers
    /// from `UndoCoordinator`, the one undo authority. Being this view's manager is what lets Edit ▸ Undo and ⌘Z reach
    /// it — the window sends `undo:` to its first responder's manager, and validates and names the menu item from it
    /// ("Undo Typing") — and never the window's own, which would undo *the consumer's* last document action while the
    /// editor had focus. Until 2026-11-03 this returned nil, and ⌘Z did nothing in the editor.
    var editorUndoManager: UndoManager?
    public override var undoManager: UndoManager? { editorUndoManager }

    // MARK: - Undo from the Edit menu and ⌘Z

    // **AppKit's Edit ▸ Undo is the window's, unless the first responder answers it.** `NSWindow` handles `undo:` and
    // `redo:` with its own undo manager and never asks the text view's (measured 2026-11-03, a probe and the tests):
    // with these absent, the menu item stayed grey in the editor and ⌘Z did nothing, or undid the window's last
    // action. Answered here, the editor is first in the chain while it has the keyboard, as TextEdit's text is.

    @objc public func undo(_ sender: Any?) { editorUndoManager?.undo() }
    @objc public func redo(_ sender: Any?) { editorUndoManager?.redo() }

    public override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let enabled = validateUndo(menuItem) { return enabled }
        return super.validateMenuItem(menuItem)
    }

    public override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let enabled = validateUndo(item) { return enabled }
        return super.validateUserInterfaceItem(item)
    }

    /// Undo and Redo enabled when there is something to undo or redo, titled with what it is ("Undo Typing").
    private func validateUndo(_ item: any NSValidatedUserInterfaceItem) -> Bool? {
        switch item.action {
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = editorUndoManager?.undoMenuItemTitle ?? "Undo"
            return editorUndoManager?.canUndo == true
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = editorUndoManager?.redoMenuItemTitle ?? "Redo"
            return editorUndoManager?.canRedo == true
        default:
            return nil
        }
    }

    // MARK: - Intent-bearing actions

    // Intent is editorial and cannot be recovered from the resulting `TextEdit`:
    // a one-character insertion is typing, a pasted single character is a paste,
    // and they coalesce differently (`CoalescingPolicy`). AppKit already tells us
    // which action ran, so each one tags the edit it is about to cause.

    public override func paste(_ sender: Any?) {
        pendingIntent = .paste
        super.paste(sender)
    }

    public override func cut(_ sender: Any?) {
        pendingIntent = .cut
        super.cut(sender)
    }

    // Edit ▸ Transformations: each its own step, "Undo Change Case".
    public override func uppercaseWord(_ sender: Any?) {
        pendingIntent = .changeCase
        super.uppercaseWord(sender)
    }

    public override func lowercaseWord(_ sender: Any?) {
        pendingIntent = .changeCase
        super.lowercaseWord(sender)
    }

    public override func capitalizeWord(_ sender: Any?) {
        pendingIntent = .changeCase
        super.capitalizeWord(sender)
    }

    public override func pasteAsPlainText(_ sender: Any?) {
        pendingIntent = .paste
        super.pasteAsPlainText(sender)
    }

    public override func pasteAsRichText(_ sender: Any?) {
        pendingIntent = .paste
        super.pasteAsRichText(sender)
    }

    public override func deleteBackward(_ sender: Any?) {
        pendingIntent = .deleteBackward
        super.deleteBackward(sender)
    }

    public override func deleteWordBackward(_ sender: Any?) {
        pendingIntent = .deleteBackward
        super.deleteWordBackward(sender)
    }

    public override func deleteToBeginningOfLine(_ sender: Any?) {
        pendingIntent = .deleteBackward
        super.deleteToBeginningOfLine(sender)
    }

    public override func deleteForward(_ sender: Any?) {
        pendingIntent = .deleteForward
        super.deleteForward(sender)
    }

    public override func deleteWordForward(_ sender: Any?) {
        pendingIntent = .deleteForward
        super.deleteWordForward(sender)
    }

    // MARK: - Indentation (2026-11-22)

    // Return keeps the line's indent; Tab over lines indents them and otherwise types to the next tab stop, in spaces
    // when the document indents with spaces; ⇧Tab outdents. The rules are `LineEditing`'s, shared with UIKit's view.

    /// The document, through the coordinator that feeds it. Nil in a view nobody attached.
    private var editorModel: GlassEditorModel? { (delegate as? GlassEditorNSCoordinator)?.model }

    /// Whether this view may run an editing rule now: it is editable, a document is attached, and no input method is
    /// composing (marked text belongs to the input method until it commits).
    private var canEditLines: Bool { isEditable && editorModel != nil && !hasMarkedText() }

    public override func insertNewline(_ sender: Any?) {
        guard canEditLines, let model = editorModel else {
            super.insertNewline(sender)
            return
        }
        let selection = selectedRange()
        let newline = LineEditing.newline(in: string as NSString,
                                          replacing: selection.location..<NSMaxRange(selection),
                                          indentation: model.configuration.indentation, language: model.language)
        insertText(newline.text, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + newline.caret, length: 0))
    }

    public override func insertTab(_ sender: Any?) {
        guard canEditLines, let model = editorModel else {
            pendingIntent = .indentation
            super.insertTab(sender)
            return
        }
        let text = string as NSString
        let selection = selectedRange()
        if LineEditing.selectionSpansLines(selection.location..<NSMaxRange(selection), in: text) {
            indentLines(sender)
            return
        }
        pendingIntent = .indentation
        insertText(LineEditing.tab(in: text, at: selection.location, indentation: model.configuration.indentation),
                   replacementRange: selection)
    }

    public override func insertBacktab(_ sender: Any?) {
        guard canEditLines else {
            pendingIntent = .indentation
            super.insertBacktab(sender)
            return
        }
        outdentLines(sender)
    }

    /// One level more on every line the selection touches (⌘], and Tab over lines).
    @objc public func indentLines(_ sender: Any?) {
        performLineEdit(intent: .indentation) { text, selection, model in
            LineEditing.indent(text, selection: selection, indentation: model.configuration.indentation)
        }
    }

    /// One level less on every line the selection touches (⌘[, and ⇧Tab).
    @objc public func outdentLines(_ sender: Any?) {
        performLineEdit(intent: .indentation) { text, selection, model in
            LineEditing.outdent(text, selection: selection, indentation: model.configuration.indentation)
        }
    }

    // MARK: - Line commands (2026-11-22)

    /// ⌘/: the lines commented out by the document's language, or back in.
    @objc public func toggleLineComments(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.comment)) { text, selection, model in
            LineEditing.toggleComment(text, selection: selection, language: model.language)
        }
    }

    @objc public func duplicateLines(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.duplicate)) { text, selection, _ in
            LineEditing.duplicate(text, selection: selection)
        }
    }

    @objc public func moveLinesUp(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.moveUp)) { text, selection, _ in
            LineEditing.move(text, selection: selection, up: true)
        }
    }

    @objc public func moveLinesDown(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.moveDown)) { text, selection, _ in
            LineEditing.move(text, selection: selection, up: false)
        }
    }

    @objc public func deleteLines(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.delete)) { text, selection, _ in
            LineEditing.delete(text, selection: selection)
        }
    }

    @objc public func joinLines(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.join)) { text, selection, _ in
            LineEditing.join(text, selection: selection)
        }
    }

    @objc public func sortLines(_ sender: Any?) {
        performLineEdit(intent: .lineCommand(.sort)) { text, selection, _ in
            LineEditing.sort(text, selection: selection)
        }
    }

    /// Makes a line command's edit as the text view makes any edit: asked of the delegate, which records it in the
    /// document under `intent` as one step, then made in the text, so only the lines it covers change. Nothing to do
    /// (outdenting lines with no indent) is a beep, as a refused command is on a Mac.
    func performLineEdit(intent: EditIntent,
                         _ make: (NSString, Range<Int>, GlassEditorModel) -> LineEdit?) {
        guard canEditLines, let model = editorModel, let storage = textStorage else {
            NSSound.beep()
            return
        }
        let selection = selectedRange()
        guard let lineEdit = make(string as NSString, selection.location..<NSMaxRange(selection), model) else {
            NSSound.beep()
            return
        }
        let range = NSRange(location: lineEdit.edit.replacementRange.lowerBound,
                            length: lineEdit.edit.replacementRange.count)
        pendingIntent = intent
        guard shouldChangeText(in: range, replacementString: lineEdit.edit.text) else {
            pendingIntent = nil
            return
        }
        storage.replaceCharacters(in: range, with: lineEdit.edit.text)
        didChangeText()
        let selected = NSRange(location: lineEdit.selection.lowerBound, length: lineEdit.selection.count)
        setSelectedRange(selected)
        scrollRangeToVisible(selected)
    }
}

#endif
