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

    /// No undo manager for this view.
    ///
    /// `UndoCoordinator` is the single undo authority on both platforms. UIKit
    /// resolves undo through the responder chain, so returning `nil` here is
    /// what stops the shake-to-undo gesture and the keyboard's undo affordance
    /// from driving a second, disagreeing stack. It is best-effort by nature —
    /// UIKit may still find a manager further up a host app's chain — so the
    /// package additionally never records into one.
    public override var undoManager: UndoManager? { nil }

    // MARK: - Intent-bearing actions

    public override func paste(_ sender: Any?) {
        pendingIntent = .paste
        super.paste(sender)
    }

    public override func deleteBackward() {
        pendingIntent = .deleteBackward
        super.deleteBackward()
    }
}

#endif
