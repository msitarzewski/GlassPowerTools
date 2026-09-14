import Foundation

/// An `AppliedEdit` paired with the intent that produced it. This is the unit
/// `CoalescingPolicy` reasons over: coalescing is a function of geometry
/// (`AppliedEdit`), editorial cause (`EditIntent`), and elapsed time.
public struct RecordedEdit: Sendable, Hashable {
    public var applied: AppliedEdit
    public var intent: EditIntent

    public init(applied: AppliedEdit, intent: EditIntent) {
        self.applied = applied
        self.intent = intent
    }

    /// Convenience passthrough — the geometry of the change.
    public var edit: TextEdit { applied.edit }

    /// The text this edit removed from the document.
    public var replacedText: String { applied.replacedText }

    /// True when either side of the change crosses a line boundary. A newline is
    /// a structural boundary: typing runs and delete runs both end at one, so
    /// undo lands on line edges rather than swallowing them.
    var touchesNewline: Bool {
        edit.text.contains(where: \.isNewline)
            || replacedText.contains(where: \.isNewline)
    }
}

/// Pure, side-effect-free rules deciding whether two adjacent recorded edits
/// belong to the same undoable unit.
///
/// Every rule here is a function of its arguments alone — no clock reads, no
/// stored state, no coordinator access. `UndoCoordinator` supplies the gap it
/// measured from its injected clock and does nothing but obey the answer.
public enum CoalescingPolicy: Sendable {
    /// The longest pause that still keeps a typing or deleting run together.
    /// A pause longer than this is treated as the user having stopped and
    /// started again — undo should land at that pause.
    public static let maximumRunGap: Duration = .seconds(1)

    /// Whether `next` should be merged into the unit `previous` belongs to.
    ///
    /// - Parameters:
    ///   - previous: the most recent edit already in the open unit — the *last*
    ///     edit of that unit, not its first.
    ///   - next: the edit being recorded now.
    ///   - gap: elapsed time between the two, measured by the coordinator's
    ///     injected clock.
    ///
    /// Only two intents ever coalesce:
    ///
    /// - `.typing` merges with `.typing` when the new insertion begins exactly
    ///   where the previous one ended.
    /// - `.deleteBackward` merges with `.deleteBackward` when the new deletion
    ///   ends exactly where the previous one began (backspace walking leftward).
    ///
    /// Everything else — `.paste`, `.drop`, `.replaceAll`, `.indentation`,
    /// `.completion`, `.programmatic`, `.deleteForward`, `.remoteReload` — is
    /// always its own unit. `.remoteReload` is additionally a barrier: nothing
    /// coalesces across it in either direction.
    public static func shouldCoalesce(
        previous: RecordedEdit,
        next: RecordedEdit,
        gap: Duration
    ) -> Bool {
        // A barrier on either side ends the run, whatever else is true.
        guard !previous.intent.isBarrier, !next.intent.isBarrier else { return false }
        guard previous.intent == next.intent else { return false }
        guard !previous.intent.formsOwnUnit else { return false }

        // A clock that ran backward is not evidence of a fast typist.
        guard gap >= .zero, gap <= maximumRunGap else { return false }

        // A crossed line boundary ends the run on either side.
        guard !previous.touchesNewline, !next.touchesNewline else { return false }

        switch previous.intent {
        case .typing:
            // Both sides must actually insert something, and the new insertion
            // must begin where the previous one finished.
            guard !previous.edit.text.isEmpty, !next.edit.text.isEmpty else { return false }
            let previousEnd = previous.edit.replacementRange.lowerBound
                + previous.edit.insertedLength
            return next.edit.replacementRange.lowerBound == previousEnd

        case .deleteBackward:
            // Both sides must be pure deletions, and the new one must end where
            // the previous one started.
            guard previous.edit.text.isEmpty, next.edit.text.isEmpty else { return false }
            guard !previous.edit.replacementRange.isEmpty,
                  !next.edit.replacementRange.isEmpty else { return false }
            return next.edit.replacementRange.upperBound
                == previous.edit.replacementRange.lowerBound

        case .deleteForward, .paste, .drop, .replaceAll,
             .indentation, .completion, .programmatic, .remoteReload:
            return false
        }
    }
}
