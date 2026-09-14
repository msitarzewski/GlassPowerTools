#if canImport(AppKit) && os(macOS)

import AppKit
import GlassEditorCore

/// The macOS text view, forced into TextKit 2 and drawing its own canvas.
///
/// **TextKit 2 is not optional here.** `NSTextView` still ships a TextKit 1
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

    /// The TextKit 2 content storage, reached without ever naming
    /// `layoutManager`.
    public var contentStorage: NSTextContentStorage? {
        textLayoutManager?.textContentManager as? NSTextContentStorage
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

    /// No undo manager for this view.
    ///
    /// `allowsUndo = false` stops `NSTextView` recording, and returning `nil`
    /// here stops the responder chain handing it the window's manager for
    /// ⌘Z — which would otherwise undo *the consumer's* last document action
    /// while the editor had focus. Undo and redo arrive through
    /// `GlassEditorAppKitEngine.undo()` / `redo()`.
    public override var undoManager: UndoManager? { nil }

    // MARK: - Intent-bearing actions

    // Intent is editorial and cannot be recovered from the resulting `TextEdit`:
    // a one-character insertion is typing, a pasted single character is a paste,
    // and they coalesce differently (`CoalescingPolicy`). AppKit already tells us
    // which action ran, so each one tags the edit it is about to cause.

    public override func paste(_ sender: Any?) {
        pendingIntent = .paste
        super.paste(sender)
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

    public override func insertTab(_ sender: Any?) {
        pendingIntent = .indentation
        super.insertTab(sender)
    }

    public override func insertBacktab(_ sender: Any?) {
        pendingIntent = .indentation
        super.insertBacktab(sender)
    }
}

#endif
