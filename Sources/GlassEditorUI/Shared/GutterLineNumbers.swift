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
        stoppedEarly: Bool,
        verticalRange: ClosedRange<CGFloat>?
    ) {
        guard !stoppedEarly,
              let lastNumber = labels.last?.number,
              lastNumber == lineCount - 1,
              let lastFrame = lastFragmentFrame
        else { return }

        let height = lastLineHeight ?? lastFrame.height
        let frame = CGRect(
            x: lastFrame.minX, y: lastFrame.maxY, width: lastFrame.width, height: height
        )
        if let verticalRange {
            guard frame.maxY >= verticalRange.lowerBound,
                  frame.minY <= verticalRange.upperBound else { return }
        }
        labels.append(Label(number: lineCount, frame: frame))
    }
}

#endif
