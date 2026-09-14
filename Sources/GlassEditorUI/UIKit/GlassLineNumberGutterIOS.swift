#if canImport(UIKit) && !os(macOS)

import UIKit
import GlassEditorCore

/// TextKit 2 line-number gutter for the UIKit backend.
///
/// A sibling view rather than numbers drawn inside the text view: `UITextView`
/// is a scroll view, so anything drawn in its `draw(_:)` scrolls with the content
/// and has to be re-derived from `contentOffset` anyway
/// (`HighlightedTextEditor.swift:150–181`). Drawing beside it makes the offset
/// arithmetic explicit and one-directional.
///
/// The line-number mapping is `GutterLineNumbers`, shared verbatim with the
/// macOS gutter. That is what retires the `O(n)`-per-fragment regression
/// INTEGRATION.md A3 flags at `HighlightedTextEditor.swift:166–169`: the shipped
/// UIKit version counted newlines in the whole document prefix for every visible
/// line fragment, so scrolling a large file was quadratic. The shared helper is
/// `O(log n)` per logical line, on both platforms, because there is only one
/// implementation to be right.
public final class GlassLineNumberGutterIOS: UIView {

    private weak var textView: GlassTextViewIOS?
    private let model: GlassEditorModel

    public init(textView: GlassTextViewIOS, model: GlassEditorModel) {
        self.textView = textView
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("GlassLineNumberGutterIOS is created programmatically")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: EditorMetrics.gutterWidth, height: UIView.noIntrinsicMetric)
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard let textView, let layoutManager = textView.textLayoutManager else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: AttributedAssembly.gutterFont(configuration: model.configuration),
            .foregroundColor: AttributedAssembly.gutterNumberColor(
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            ),
        ]

        // Layout-fragment frames are in the text view's content coordinates; the
        // gutter draws in its own bounds. The scroll offset and the container's
        // top inset are the whole difference between the two.
        let offsetY = textView.contentOffset.y - textView.textContainerInset.top
        let visible = offsetY...(offsetY + bounds.height)

        let labels = GutterLineNumbers.labels(
            in: layoutManager,
            verticalRange: visible,
            lineCount: model.lineCount
        ) { [model] utf16Offset in
            model.lineIndex(forUTF16Offset: utf16Offset)
        }

        for label in labels {
            let text = "\(label.number)" as NSString
            let size = text.size(withAttributes: attributes)
            let origin = CGPoint(
                x: bounds.width - size.width - EditorMetrics.gutterNumberTrailingGap,
                y: label.frame.minY - offsetY
            )
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// Repaints when the document, theme or surface has moved underneath us.
    public func refresh() {
        setNeedsDisplay()
    }
}

#endif
