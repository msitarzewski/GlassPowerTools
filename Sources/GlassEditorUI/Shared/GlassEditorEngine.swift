import Foundation
import GlassEditorCore

/// The seam that keeps D-001 reversible: everything above this protocol is
/// backend-agnostic, and a fallback engine (e.g. Runestone on UIKit) would
/// implement exactly this. TextKit 2 assumptions must never leak above it.
@MainActor
public protocol GlassEditorEngine: AnyObject {
    var configuration: GlassEditorConfiguration { get set }
    var surfaceCondition: SurfaceCondition { get set }

    /// The full document text. Setting replaces content as a single edit.
    var text: String { get }

    /// Apply one edit through the single mutation path.
    func apply(_ edit: TextEdit) throws

    /// Apply a batch as one undoable unit.
    func apply(_ batch: TextEditBatch) throws

    /// Replace highlight runs for the current content version.
    func setHighlightRuns(_ runs: [HighlightRun])

    /// Current selection in UTF-16 code units (empty range = caret).
    var selectedRange: Range<Int> { get set }
}
