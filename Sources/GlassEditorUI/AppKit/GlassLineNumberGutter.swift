#if canImport(AppKit) && os(macOS)

import AppKit
import GlassEditorCore

/// TextKit 2 line-number gutter for the macOS backend.
///
/// An `NSRulerView` rather than numbers hand-drawn inside the text view: the
/// ruler scrolls in lockstep with the document by construction, so there is no
/// second scroll view to synchronise and no `textContainerInset` arithmetic to
/// keep in step with the gutter's width.
///
/// Line numbers come from `GutterLineNumbers`, shared with the UIKit gutter, and
/// resolve through `GlassEditorModel.lineIndex(forUTF16Offset:)` — the buffer's
/// `O(log n)` binary search. INTEGRATION.md A4 is explicit that the TextKit 1
/// gutter cannot be ported line-for-line, and A3 requires the binary-search
/// version on both platforms; this is where both land.
public final class GlassLineNumberGutter: NSRulerView {

    private weak var glassTextView: GlassTextView?
    private let model: GlassEditorModel

    public init(scrollView: NSScrollView, textView: GlassTextView, model: GlassEditorModel) {
        self.glassTextView = textView
        self.model = model
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = EditorMetrics.gutterWidth
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) {
        fatalError("GlassLineNumberGutter is created programmatically")
    }

    // MARK: - Drawing

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = glassTextView,
              let layoutManager = textView.textLayoutManager else { return }

        let font = AttributedAssembly.gutterFont(configuration: model.configuration)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: AttributedAssembly.gutterNumberColor(
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            ),
        ]

        // Three coordinate spaces meet here: the ruler's own, the text view's,
        // and the text container's — `layoutFragmentFrame` is in the last.
        // `textContainerOrigin` is the offset between the second and the third,
        // and is the right accessor rather than `textContainerInset` because it
        // also accounts for a container narrower than the view being centred.
        let containerOrigin = textView.textContainerOrigin
        let visible = convert(rect, to: textView)
        let band = (visible.minY - containerOrigin.y)...(visible.maxY - containerOrigin.y)

        let labels = GutterLineNumbers.labels(
            in: layoutManager,
            verticalRange: band,
            lineCount: model.lineCount
        ) { [model] offset in
            model.lineIndex(forUTF16Offset: offset)
        }

        for label in labels {
            let text = "\(label.number)" as NSString
            let size = text.size(withAttributes: attributes)
            // Right-aligned against the gutter's trailing edge, and top-aligned
            // with the first visual line of the logical line — a wrapped line's
            // number sits beside its first row, not centred over all of them.
            let origin = NSPoint(
                x: ruleThickness - size.width - EditorMetrics.gutterNumberTrailingGap,
                y: convert(
                    NSPoint(x: 0, y: label.frame.minY + containerOrigin.y), from: textView
                ).y
            )
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// Repaints when the document, theme or surface has moved underneath us.
    public func refresh() {
        needsDisplay = true
    }
}

#endif
