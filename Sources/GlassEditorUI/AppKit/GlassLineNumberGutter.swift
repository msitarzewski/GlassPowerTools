#if canImport(AppKit) && os(macOS)

import AppKit
import GlassEditorCore

/// TextKit 2 line-number gutter for the macOS backend.
///
/// A sibling view beside the scroll view, matching `GlassLineNumberGutterIOS`.
/// It was an `NSRulerView`, which scrolls in lockstep with the document for
/// free — but a ruler spans its whole scroll view and is not inset by the
/// scroll view's content insets, so in a window with a full-size content view
/// the strip of numbers carried on up past the tabs and sat beside the traffic
/// lights. Nothing at the scroll view's level moves it, because the ruler is
/// not part of what those insets inset.
///
/// Drawn beside the text instead, the gutter is laid out by the container that
/// holds it and can only ever occupy the space that container gives it. The
/// price is one number: `offsetY`, computed here and paid on every frame.
///
/// Line numbers come from `GutterLineNumbers`, shared with the UIKit gutter,
/// and resolve through `GlassEditorModel.lineIndex(forUTF16Offset:)` — the
/// buffer's `O(log n)` binary search. INTEGRATION.md A4 is explicit that the
/// TextKit 1 gutter cannot be ported line-for-line, and A3 requires the
/// binary-search version on both platforms; this is where both land.
public final class GlassLineNumberGutter: NSView {

    private weak var glassTextView: GlassTextView?
    private weak var scrollView: NSScrollView?
    private let model: GlassEditorModel

    public init(scrollView: NSScrollView, textView: GlassTextView, model: GlassEditorModel) {
        self.glassTextView = textView
        self.scrollView = scrollView
        self.model = model
        super.init(frame: .zero)

        // Scrolling moves the text under a gutter that does not move, so the
        // gutter has to be told. The clip view's bounds origin *is* the scroll
        // position; `postsBoundsChangedNotifications` is what makes it audible.
        // Registered target/selector rather than with a token, because that
        // form deregisters itself when the view is deallocated.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) {
        fatalError("GlassLineNumberGutter is created programmatically")
    }

    /// Flipped, so a layout fragment's `minY` and a drawing origin mean the
    /// same thing here as they do in the layout manager and in the UIKit gutter.
    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: EditorMetrics.gutterWidth, height: NSView.noIntrinsicMetric)
    }

    /// The gutter paints nothing of its own: the canvas behind it is the text
    /// view's, at the surface's alpha, and an opaque plate here would be a
    /// stripe down a window the user asked to see through.
    public override var isOpaque: Bool { false }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let textView = glassTextView else { return }
        let offsetY = verticalOffset(textView: textView)
        let visible = Self.labels(for: textView, model: model,
                                  verticalRange: offsetY...(offsetY + bounds.height))
        GutterLineNumbers.draw(visible, in: bounds, offsetY: offsetY, model: model)
    }

    /// The numbered lines in `verticalRange` (layout coordinates; nil for the whole document), on
    /// whichever text system the view was built with. The tests ask this, so they check what the
    /// gutter actually draws.
    public static func labels(for textView: GlassTextView, model: GlassEditorModel,
                              verticalRange: ClosedRange<CGFloat>?) -> [GutterLineNumbers.Label] {
        switch textView.textSystem {
        case .textKit2:
            guard let layoutManager = textView.textLayoutManager else { return [] }
            return GutterLineNumbers.labels(in: layoutManager, verticalRange: verticalRange,
                                            lineCount: model.lineCount) {
                model.lineIndex(forUTF16Offset: $0)
            }
        case .textKit1:
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return [] }
            return textKit1Labels(layoutManager: layoutManager, container: container,
                                  verticalRange: verticalRange, lineCount: model.lineCount,
                                  lineIndex: { model.lineIndex(forUTF16Offset: $0) },
                                  lineStart: { model.lineRange(ofLine: $0).lowerBound })
        }
    }

    /// TextKit 1: the line fragments in the band, numbered only where a fragment **starts a
    /// logical line** — a wrapped row continues the line above and gets no number. Asking the
    /// layout manager for the band's glyphs is what non-contiguous layout lays out, and no more.
    /// The document's final empty line is the layout manager's extra line fragment.
    ///
    /// `lineIndex` is the buffer's `O(log n)` search, passed in (as the TextKit 2 path takes it)
    /// so a test can count the lookups: one per visual row, never a rescan.
    static func textKit1Labels(layoutManager: NSLayoutManager, container: NSTextContainer,
                               verticalRange: ClosedRange<CGFloat>?, lineCount: Int,
                               lineIndex: (Int) -> Int,
                               lineStart: (Int) -> Int) -> [GutterLineNumbers.Label] {
        let glyphs: NSRange
        if let verticalRange {
            let band = CGRect(x: 0, y: verticalRange.lowerBound, width: container.size.width,
                              height: max(1, verticalRange.upperBound - verticalRange.lowerBound))
            glyphs = layoutManager.glyphRange(forBoundingRect: band, in: container)
        } else {
            layoutManager.ensureLayout(for: container)
            glyphs = layoutManager.glyphRange(for: container)
        }
        var labels: [GutterLineNumbers.Label] = []
        if glyphs.length > 0 {
            var rows: [(frame: CGRect, character: Int)] = []
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
                rows.append((rect, layoutManager.characterIndexForGlyph(at: range.location)))
            }
            for row in rows {
                let line = lineIndex(row.character)
                guard lineStart(line) == row.character else { continue }
                labels.append(.init(number: line + 1, frame: row.frame))
            }
        }
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0, labels.last?.number != lineCount {
            if verticalRange.map({ extra.maxY >= $0.lowerBound && extra.minY <= $0.upperBound }) ?? true {
                labels.append(.init(number: lineCount, frame: extra))
            }
        }
        return labels
    }

    /// Layout-space y of this view's top edge.
    ///
    /// Three coordinate spaces meet here: the gutter's own, the text view's and
    /// the text container's — `layoutFragmentFrame` is in the last.
    /// `textContainerOrigin` is the offset between the second and the third,
    /// and is the right accessor rather than `textContainerInset` because it
    /// also accounts for a container narrower than the view being centred. The
    /// content inset is the third term: the clip view starts that far below the
    /// scroll view's top edge, and the gutter's top is the scroll view's top.
    private func verticalOffset(textView: GlassTextView) -> CGFloat {
        guard let scrollView else { return 0 }
        return scrollView.contentView.bounds.origin.y
            - textView.textContainerOrigin.y
            - scrollView.contentInsets.top
    }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        needsDisplay = true
    }

    /// Repaints when the document, theme or surface has moved underneath us.
    public func refresh() {
        needsDisplay = true
    }
}

#endif
