import Foundation
import GlassEditorCore

#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit) || canImport(UIKit)

/// Fragment → line-number mapping for both gutters.
///
/// `NSTextLayoutManager` is the same type on AppKit and UIKit, so the entire
/// enumeration lives here and each backend contributes only its drawing. That is
/// the point of one package: the AppKit gutter's `O(log n)` behavior is not
/// re-derived on UIKit, where the shipped version was `O(n)` per fragment
/// (`HighlightedTextEditor.swift:166–169`, called out in INTEGRATION.md A3).
///
/// **Why layout fragments give the right answer for soft wrap.**
/// `NSTextContentStorage` emits one `NSTextParagraph` element per paragraph — one
/// *logical* line — and `NSTextLayoutManager` lays each out as one
/// `NSTextLayoutFragment` whose `textLineFragments` are the wrapped visual lines.
/// Enumerating layout fragments therefore visits each logical line exactly once,
/// whatever the container width, and soft wraps cannot increment a number. The
/// TextKit 1 approach this replaces had to test `character(at: index - 1) == 10`
/// on every visual line fragment to filter wraps back out
/// (`HighlightedTextEditor.swift:380`); TextKit 2 makes the filter unnecessary
/// rather than cheaper.
///
/// INTEGRATION.md A4 forbids porting the TextKit 1 gutter line-for-line, and this
/// is why: `glyphRange(forBoundingRect:in:)` has no TextKit 2 equivalent, and
/// reaching for `NSTextView.layoutManager` to get one silently downgrades the
/// whole view to TextKit 1.
@MainActor
public enum GutterLineNumbers {

    /// One line number and the rectangle of the logical line it labels, in the
    /// layout manager's coordinate space.
    public struct Label: Hashable, Sendable {
        /// One-based line number, as a reader counts.
        public var number: Int
        /// The whole logical line's layout rect — `minY` is where the number is
        /// drawn, `height` covers every wrapped visual line beneath it.
        public var frame: CGRect

        public init(number: Int, frame: CGRect) {
            self.number = number
            self.frame = frame
        }
    }

    /// Draws the visible line numbers into the current graphics context.
    ///
    /// Both backends put the gutter in a view *beside* the text, so both draw
    /// the same numbers in the same place and the only per-platform value is
    /// `offsetY`: the distance between the layout manager's coordinates and the
    /// gutter's own. On UIKit that is `contentOffset.y - textContainerInset.top`;
    /// on AppKit, the clip view's scrolled origin less the text container origin
    /// and the scroll view's top content inset. Everything downstream of that
    /// number — right alignment, the trailing gap, top alignment with the first
    /// visual line of a wrapped logical line — is the same sum on both, and is
    /// therefore written once.
    ///
    /// - Parameters:
    ///   - bounds: the gutter view's own bounds. Its width right-aligns the
    ///     numbers; its height is the visible band.
    ///   - offsetY: layout-space y of the gutter's top edge.
    public static func draw(
        in bounds: CGRect,
        offsetY: CGFloat,
        layoutManager: NSTextLayoutManager,
        model: GlassEditorModel
    ) {
        guard bounds.height > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AttributedAssembly.gutterFont(configuration: model.configuration),
            .foregroundColor: AttributedAssembly.gutterNumberColor(
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            ),
        ]

        let visible = labels(
            in: layoutManager,
            verticalRange: offsetY...(offsetY + bounds.height),
            lineCount: model.lineCount
        ) { utf16Offset in
            model.lineIndex(forUTF16Offset: utf16Offset)
        }

        for label in visible {
            let text = "\(label.number)" as NSString
            let size = text.size(withAttributes: attributes)
            // Right-aligned against the gutter's trailing edge, and top-aligned
            // with the first visual line of the logical line — a wrapped line's
            // number sits beside its first row, not centred over all of them.
            let origin = CGPoint(
                x: bounds.width - size.width - EditorMetrics.gutterNumberTrailingGap,
                y: label.frame.minY - offsetY
            )
            text.draw(at: origin, withAttributes: attributes)
        }
    }

    /// Labels for the logical lines laid out in `verticalRange`.
    ///
    /// - Parameters:
    ///   - layoutManager: the view's TextKit 2 layout manager. Reached through
    ///     `textLayoutManager`, never through `layoutManager`.
    ///   - verticalRange: the visible band in the layout manager's coordinates.
    ///     `nil` enumerates the whole document — what a test wants, and what a
    ///     short document costs nothing for.
    ///   - lineCount: the buffer's line count, used to detect the trailing empty
    ///     line TextKit 2 does not emit a fragment for. See below.
    ///   - lineIndex: zero-based line for a UTF-16 offset. Backends pass
    ///     `GlassEditorModel.lineIndex(forUTF16Offset:)`, which is the buffer's
    ///     `O(log n)` binary search over line starts.
    public static func labels(
        in layoutManager: NSTextLayoutManager,
        verticalRange: ClosedRange<CGFloat>?,
        lineCount: Int,
        lineIndex: (Int) -> Int
    ) -> [Label] {
        guard let content = layoutManager.textContentManager else { return [] }
        let documentStart = content.documentRange.location

        var labels: [Label] = []
        var lastFragmentFrame: CGRect?
        var lastLineHeight: CGFloat?
        /// Where the document's final empty line was actually laid out, when TextKit put it
        /// *inside* the last fragment rather than after it. See below.
        var extraLineTop: CGFloat?
        var stoppedEarly = false

        layoutManager.enumerateTextLayoutFragments(
            from: documentStart,
            // `.ensuresLayout` is what makes `layoutFragmentFrame` real rather
            // than estimated.
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            lastFragmentFrame = frame
            lastLineHeight = fragment.textLineFragments.last?.typographicBounds.height
            // **The extra line fragment belongs to the fragment above it.** Asked for
            // `.ensuresExtraLineFragment`, TextKit 2 lays the final empty line out as a
            // zero-length line fragment *within* the last paragraph's fragment — so for
            // `"one line\n"` there is one fragment, 32 points tall, holding two 16-point lines.
            // Placing the trailing number at the fragment's `maxY` therefore put it a whole line
            // below the caret it was supposed to sit beside (photographed 2026-09-20).
            if fragment.textLineFragments.count > 1,
               let extra = fragment.textLineFragments.last, extra.characterRange.length == 0 {
                extraLineTop = frame.minY + extra.typographicBounds.minY
            } else {
                extraLineTop = nil
            }

            if let verticalRange {
                if frame.maxY < verticalRange.lowerBound { return true }
                if frame.minY > verticalRange.upperBound {
                    stoppedEarly = true
                    return false
                }
            }
            let offset = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            labels.append(Label(number: lineIndex(offset) + 1, frame: frame))
            return true
        }

        appendTrailingEmptyLineIfNeeded(
            to: &labels,
            lineCount: lineCount,
            lastFragmentFrame: lastFragmentFrame,
            lastLineHeight: lastLineHeight,
            extraLineTop: extraLineTop,
            stoppedEarly: stoppedEarly,
            verticalRange: verticalRange
        )
        return labels
    }

    /// Adds the number for the final empty line of a document ending in a
    /// terminator.
    ///
    /// **Why this is not the enumeration's job.** `NSTextContentStorage` emits a
    /// paragraph element per terminator-delimited run of characters, so `"a\n"`
    /// is *one* element and produces *one* layout fragment — while
    /// `TextStorageBuffer` counts it as two lines, the second empty
    /// (`TextStorageBuffer.swift:33–36`). TextKit 2 does lay that empty line out,
    /// as the layout manager's extra line fragment, but exposes no public
    /// accessor for it and never yields it from
    /// `enumerateTextLayoutFragments` — `.ensuresExtraLineFragment` guarantees it
    /// is *laid out*, not that it is *enumerated*. Verified against the macOS 27
    /// SDK: `NSTextLayoutManager` has no `extraLineTextFragment` property.
    ///
    /// Leaving it out would mean the caret can sit on a line the gutter does not
    /// number, and that the gutter and the buffer disagree about how many lines
    /// the document has — so the label is synthesised directly beneath the last
    /// real fragment, at the height of that fragment's last visual line.
    ///
    /// Skipped when the enumeration stopped early, because then the last fragment
    /// seen is not the document's last one.
    private static func appendTrailingEmptyLineIfNeeded(
        to labels: inout [Label],
        lineCount: Int,
        lastFragmentFrame: CGRect?,
        lastLineHeight: CGFloat?,
        extraLineTop: CGFloat?,
        stoppedEarly: Bool,
        verticalRange: ClosedRange<CGFloat>?
    ) {
        guard !stoppedEarly,
              let lastNumber = labels.last?.number,
              lastNumber == lineCount - 1,
              let lastFrame = lastFragmentFrame
        else { return }

        let height = lastLineHeight ?? lastFrame.height
        // Where TextKit actually put the empty line when it put it inside the fragment above;
        // otherwise directly after that fragment, which is where a caret would sit.
        let top = extraLineTop ?? lastFrame.maxY
        let frame = CGRect(
            x: lastFrame.minX, y: top, width: lastFrame.width, height: height
        )
        if let verticalRange {
            guard frame.maxY >= verticalRange.lowerBound,
                  frame.minY <= verticalRange.upperBound else { return }
        }
        labels.append(Label(number: lineCount, frame: frame))
    }
}

#endif
