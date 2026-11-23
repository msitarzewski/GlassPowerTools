#if canImport(UIKit) && !os(macOS)

import UIKit
import GlassEditorCore

/// The iOS / iPadOS / visionOS text view, on the same TextKit 2 stack and the
/// same canvas-ownership rule as the macOS one.
///
/// The shipped UIKit path (`HighlightedTextEditor.swift:12–188`) is the one that
/// drifted: no debounce, no marked-text guard, no re-entrancy guard, no typing
/// attribute preservation, and an `O(n)`-per-fragment gutter. None of that is
/// carried forward. What *is* carried forward is the list of things it got right
/// — a clear background, autocorrect and smart substitution off, the ASCII
/// keyboard — because those are behaviors a SQL editor depends on.
public final class GlassTextViewIOS: UITextView {

    /// Fill color for the canvas, from the theme at the surface's alpha.
    public var canvasColor: UIColor = .clear {
        didSet {
            canvasLayer.backgroundColor = canvasColor.cgColor
            setNeedsLayout()
        }
    }

    /// Font size the current attributes were built with — the UIKit half of
    /// `appliedFontSize` (INTEGRATION.md A3 requires the behavior on both).
    public var appliedFontSize: CGFloat = 0

    /// One-shot intent for the edit a UIKit action is about to cause.
    var pendingIntent: EditIntent?

    /// Wrap Long Lines. Off, the text container is unbounded and the view scrolls sideways to
    /// the longest line laid out. Both are held here, on every layout, because `UITextView` does
    /// neither on its own: it laid a container set unbounded before it had a size out to its own
    /// width when it got one — the owner's iPhone wrapped every long line with the setting off
    /// (2026-10-12) — and it keeps its content as wide as itself, so an unwrapped line was out of
    /// reach.
    public var wrapsLines = true {
        didSet {
            guard wrapsLines != oldValue else { return }
            textContainer.widthTracksTextView = wrapsLines
            if wrapsLines {
                // Back to the view's width: UIKit tracks it from here.
                textContainer.size = CGSize(width: max(bounds.width, 0), height: .greatestFiniteMagnitude)
                super.contentSize = CGSize(width: bounds.width, height: super.contentSize.height)
            } else {
                holdUnboundedContainer()
            }
            setNeedsLayout()
        }
    }

    /// A container this wide never wraps.
    static let unboundedWidth = CGFloat.greatestFiniteMagnitude

    private func holdUnboundedContainer() {
        if textContainer.widthTracksTextView { textContainer.widthTracksTextView = false }
        if textContainer.size.width != Self.unboundedWidth {
            textContainer.size = CGSize(width: Self.unboundedWidth, height: .greatestFiniteMagnitude)
        }
    }

    /// The content width the laid-out text needs, insets included; nil while wrapping.
    private var unwrappedContentWidth: CGFloat? {
        guard !wrapsLines, let layoutManager = textLayoutManager else { return nil }
        let used = layoutManager.usageBoundsForTextContainer
        guard used.maxX.isFinite, used.maxX < Self.unboundedWidth / 2 else { return nil }
        return ceil(used.maxX + textContainerInset.left + textContainerInset.right
                    + textContainer.lineFragmentPadding)
    }

    /// UIKit sets the content size from its own layout, as wide as the view; unwrapped, it is
    /// as wide as the text.
    public override var contentSize: CGSize {
        get { super.contentSize }
        set {
            var size = newValue
            if let width = unwrappedContentWidth { size.width = max(size.width, width) }
            super.contentSize = size
        }
    }

    /// The canvas.
    ///
    /// A layer rather than a `backgroundColor`, because `UITextView` is a
    /// `UIScrollView`: its background scrolls with the content view, so a colored
    /// background would slide away from the glyphs. This layer is repositioned to
    /// the viewport on every layout pass, so it behaves like the fixed ground the
    /// AppKit `draw(_:)` override paints.
    private let canvasLayer = CALayer()

    /// The TextKit 2 content storage, reached without naming `layoutManager`.
    public var contentStorage: NSTextContentStorage? {
        textLayoutManager?.textContentManager as? NSTextContentStorage
    }

    // MARK: - Construction

    /// Builds the TextKit 2 stack explicitly, exactly as the AppKit view does.
    ///
    /// `UITextView(usingTextLayoutManager:)` would also produce a TextKit 2 view,
    /// but building the stack by hand keeps the content storage and layout
    /// manager reachable for the coordinator and the gutter without a second
    /// lookup, and it is the same code shape on both platforms.
    public static func makeTextKit2() -> GlassTextViewIOS {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)

        let view = GlassTextViewIOS(frame: .zero, textContainer: container)
        view.assertUsingTextKit2()
        return view
    }

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureForCodeEditing()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("GlassTextViewIOS is created programmatically; use makeTextKit2()")
    }

    private func configureForCodeEditing() {
        backgroundColor = .clear
        layer.insertSublayer(canvasLayer, at: 0)

        isScrollEnabled = true
        alwaysBounceVertical = true
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        // visionOS and iOS have no `.smartQuotesDisabled()` equivalent at the
        // SwiftUI layer, so the shipped app pins the keyboard to ASCII
        // (`HighlightedTextEditor.swift:49`). Keeping it means a typed quote is
        // the quote the parser expects, not a typographic one.
        keyboardType = .asciiCapable
        textContainerInset = UIEdgeInsets(
            top: EditorMetrics.containerInset,
            left: EditorMetrics.containerInset,
            bottom: EditorMetrics.containerInset,
            right: EditorMetrics.containerInset
        )
    }

    // MARK: - Canvas

    public override func layoutSubviews() {
        if !wrapsLines { holdUnboundedContainer() }
        super.layoutSubviews()
        if let width = unwrappedContentWidth, width > super.contentSize.width {
            super.contentSize = CGSize(width: width, height: super.contentSize.height)
        }
        // Pin the canvas to the viewport, not the content, and do it without an
        // implicit animation — an animated background during a scroll reads as a
        // flicker.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvasLayer.frame = CGRect(origin: contentOffset, size: bounds.size)
        CATransaction.commit()
    }

    // MARK: - TextKit 2 tripwire

    /// Traps in debug if the view has fallen back to TextKit 1. Reading
    /// `UITextView.layoutManager` is what would cause it; nothing here does.
    public func assertUsingTextKit2() {
        assert(
            textLayoutManager != nil,
            "GlassTextViewIOS fell back to TextKit 1 — something read `layoutManager`"
        )
    }

    public var isUsingTextKit2: Bool { textLayoutManager != nil }

    // MARK: - Undo authority

    /// The editor's own undo, as this view's undo manager (`GlassEditorUndoManager`, set by the engine).
    ///
    /// `UndoCoordinator` is the single undo authority on both platforms. UIKit resolves undo through the responder
    /// chain — ⌘Z, shake to undo, the three-finger swipe, the keyboard's undo button — so this view's manager is what
    /// they all reach; it records nothing (registration is disabled, so UIKit's own typing records add nothing) and
    /// answers from the coordinator. Until 2026-11-03 this returned nil and none of them did anything.
    var editorUndoManager: UndoManager?
    public override var undoManager: UndoManager? { editorUndoManager }

    // MARK: - Intent-bearing actions

    public override func paste(_ sender: Any?) {
        pendingIntent = .paste
        super.paste(sender)
    }

    public override func cut(_ sender: Any?) {
        pendingIntent = .cut
        super.cut(sender)
    }

    public override func deleteBackward() {
        pendingIntent = .deleteBackward
        super.deleteBackward()
    }

    // MARK: - Indentation (2026-11-22)

    // The Mac's rules (`GlassTextView`), from `LineEditing`: Return keeps the line's indent; Tab over lines indents
    // them and otherwise types to the next tab stop; ⇧Tab, ⌘[ and ⌘] outdent and indent, from a keyboard. Return and
    // Tab are answered by the delegate (`GlassEditorUICoordinator.typedReturnOrTab`), which every keyboard asks before
    // it types: an override of `insertText` changes the view without asking it, so the document would never see the
    // indent (measured on the simulator, 2026-11-22).

    var editorCoordinator: GlassEditorUICoordinator? { delegate as? GlassEditorUICoordinator }

    /// Editable, attached, and no input method composing.
    var canEditLines: Bool { isEditable && editorCoordinator != nil && markedTextRange == nil }

    public override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        guard isEditable else { return commands }
        let indent = UIKeyCommand(title: "Indent", action: #selector(indentLines(_:)), input: "]",
                                  modifierFlags: .command)
        let outdent = UIKeyCommand(title: "Outdent", action: #selector(outdentLines(_:)), input: "[",
                                   modifierFlags: .command)
        // Not the system's move to the previous control: in a text editor ⇧Tab outdents.
        let backtab = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLines(_:)))
        // The Mac's keys for the line commands (`GlassEditorCommands`).
        let comment = UIKeyCommand(title: "Comment or Uncomment Lines", action: #selector(toggleLineComments(_:)),
                                   input: "/", modifierFlags: .command)
        let up = UIKeyCommand(title: "Move Lines Up", action: #selector(moveLinesUp(_:)),
                              input: UIKeyCommand.inputUpArrow, modifierFlags: [.control, .command])
        let down = UIKeyCommand(title: "Move Lines Down", action: #selector(moveLinesDown(_:)),
                                input: UIKeyCommand.inputDownArrow, modifierFlags: [.control, .command])
        let delete = UIKeyCommand(title: "Delete Lines", action: #selector(deleteLines(_:)), input: "k",
                                  modifierFlags: [.command, .shift])
        let all = [indent, outdent, backtab, comment, up, down, delete]
        for command in all { command.wantsPriorityOverSystemBehavior = true }
        commands += all
        return commands
    }

    // MARK: - Line commands (2026-11-22)

    @objc public func toggleLineComments(_ sender: Any?) {
        perform(.comment) { LineEditing.toggleComment($0, selection: $1, language: $2.language) }
    }

    @objc public func duplicateLines(_ sender: Any?) {
        perform(.duplicate) { text, selection, _ in LineEditing.duplicate(text, selection: selection) }
    }

    @objc public func moveLinesUp(_ sender: Any?) {
        perform(.moveUp) { text, selection, _ in LineEditing.move(text, selection: selection, up: true) }
    }

    @objc public func moveLinesDown(_ sender: Any?) {
        perform(.moveDown) { text, selection, _ in LineEditing.move(text, selection: selection, up: false) }
    }

    @objc public func deleteLines(_ sender: Any?) {
        perform(.delete) { text, selection, _ in LineEditing.delete(text, selection: selection) }
    }

    @objc public func joinLines(_ sender: Any?) {
        perform(.join) { text, selection, _ in LineEditing.join(text, selection: selection) }
    }

    @objc public func sortLines(_ sender: Any?) {
        perform(.sort) { text, selection, _ in LineEditing.sort(text, selection: selection) }
    }

    private func perform(_ command: LineCommand,
                         _ make: (NSString, Range<Int>, GlassEditorModel) -> LineEdit?) {
        guard canEditLines else { return }
        editorCoordinator?.performLineEdit(in: self, intent: .lineCommand(command), make)
    }

    /// One level more on every line the selection touches.
    @objc public func indentLines(_ sender: Any?) {
        guard canEditLines else { return }
        editorCoordinator?.performLineEdit(in: self, intent: .indentation) { text, selection, model in
            LineEditing.indent(text, selection: selection, indentation: model.configuration.indentation)
        }
    }

    /// One level less on every line the selection touches.
    @objc public func outdentLines(_ sender: Any?) {
        guard canEditLines else { return }
        editorCoordinator?.performLineEdit(in: self, intent: .indentation) { text, selection, model in
            LineEditing.outdent(text, selection: selection, indentation: model.configuration.indentation)
        }
    }
}

#endif
