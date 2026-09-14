import Foundation

// MARK: - Clock injection

/// The only source of time the undo system is allowed to read.
///
/// Coalescing depends on elapsed time, and a correctness rule that cannot be
/// tested deterministically is not a correctness rule. Nothing in `Undo/` calls
/// `Date()`, `ContinuousClock.now`, or any other ambient clock directly — every
/// reading goes through the instance injected at `init`.
public protocol UndoClock: Sendable {
    func now() -> ContinuousClock.Instant
}

/// The production clock: monotonic, unaffected by wall-clock adjustments.
public struct ContinuousUndoClock: UndoClock {
    public init() {}

    public func now() -> ContinuousClock.Instant {
        ContinuousClock.now
    }
}

// MARK: - Steps and units

/// A sequence of edits the engine applies **one at a time, in order**.
///
/// This is deliberately not a `TextEditBatch`. A batch's ranges are all
/// interpreted against the document state *before* the batch, and
/// `TextStorageBuffer` applies them back-to-front to keep them valid. An
/// `UndoStep` is the opposite: each edit's range is valid against the state
/// produced by the edit before it, so the engine must apply them front-to-back,
/// one by one, never simultaneously. Reversing a group of edits requires
/// sequential semantics — the two shapes are not interchangeable, so they are
/// different types.
public struct UndoStep: Sendable, Hashable {
    public var edits: [TextEdit]

    public init(edits: [TextEdit]) {
        self.edits = edits
    }

    public var isEmpty: Bool { edits.isEmpty }
}

/// One entry on the undo stack: the edits that were applied together, in the
/// order the buffer applied them, plus the intent that caused them.
public struct UndoUnit: Sendable, Hashable {
    public var intent: EditIntent
    /// Applied edits in application order. Element *n*'s `replacementRange` is
    /// valid against the document state produced by element *n-1*.
    public var edits: [AppliedEdit]

    /// When the newest edit in this unit was recorded, per the injected clock.
    var lastInstant: ContinuousClock.Instant
    /// A sealed unit never accepts further coalescing. Undo and redo seal the
    /// boundary they leave behind, so a run resumed after an undo starts fresh.
    var isSealed: Bool

    init(
        intent: EditIntent,
        edits: [AppliedEdit],
        lastInstant: ContinuousClock.Instant,
        isSealed: Bool = false
    ) {
        self.intent = intent
        self.edits = edits
        self.lastInstant = lastInstant
        self.isSealed = isSealed
    }

    /// The step that reverses this unit: inverses, newest first.
    ///
    /// `AppliedEdit.inverse` is valid against the state immediately after that
    /// edit, so walking the group backward keeps every range valid — undoing the
    /// last edit restores the state the second-to-last edit produced, and so on.
    public var undoStep: UndoStep {
        UndoStep(edits: edits.reversed().map(\.inverse))
    }

    /// The step that re-applies this unit: the original edits, oldest first.
    /// Valid because a completed undo restores exactly the pre-unit state.
    public var redoStep: UndoStep {
        UndoStep(edits: edits.map(\.edit))
    }

    /// Approximate retained size in UTF-16 code units: every edit holds both the
    /// text it inserted and the text it replaced (the inverse needs both). Used
    /// by the coordinator's byte budget so a run of whole-document replacements
    /// cannot retain unbounded memory (pen finding M-3).
    var retainedCodeUnits: Int {
        edits.reduce(0) { $0 + $1.edit.text.utf16.count + $1.replacedText.utf16.count }
    }
}

// MARK: - Coordinator

/// Owns the undo and redo stacks for one document.
///
/// A `final class` rather than a value type or actor: it is mutable state owned
/// by a single `@MainActor` engine, mutated on every keystroke, and never shared
/// across isolation domains. It imports Foundation only and needs no view to be
/// exercised — the whole coalescing contract is testable headlessly.
///
/// Ordering contract for `record`: the `AppliedEdit`s handed to this type must
/// be in the order the buffer actually applied them, each range valid against
/// the state immediately before it. For a `TextEditBatch` — which
/// `TextStorageBuffer` applies back-to-front — that means the edits arrive
/// highest-offset-first. Recording them in the batch's declaration order instead
/// would produce inverses that drift.
public final class UndoCoordinator {
    private let clock: any UndoClock
    private let maximumUnitCount: Int
    private let maximumRetainedCodeUnits: Int

    private var undoStack: [UndoUnit] = []
    private var redoStack: [UndoUnit] = []

    /// - Parameters:
    ///   - clock: time source for coalescing gaps. Inject a controllable clock
    ///     in tests; the default is monotonic.
    ///   - maximumUnitCount: how many undo units to retain. Oldest units are
    ///     evicted first once the cap is reached.
    ///   - maximumRetainedCodeUnits: a byte-ish budget (in UTF-16 code units)
    ///     across all retained undo units, evicted oldest-first alongside the
    ///     unit cap. Without it, a run of whole-document replacements retains two
    ///     full copies per unit — 1000 replace-alls at the 8 MB ceiling is ~16 GB
    ///     (pen finding M-3). The newest unit is always kept even if it alone
    ///     exceeds the budget, so undo of the last action never silently no-ops.
    ///     Default ~32M code units (~64 MB).
    public init(
        clock: any UndoClock = ContinuousUndoClock(),
        maximumUnitCount: Int = 1000,
        maximumRetainedCodeUnits: Int = 32 * 1024 * 1024
    ) {
        precondition(maximumUnitCount > 0, "Undo depth cap must be at least one unit")
        precondition(maximumRetainedCodeUnits > 0, "Undo byte budget must be positive")
        self.clock = clock
        self.maximumUnitCount = maximumUnitCount
        self.maximumRetainedCodeUnits = maximumRetainedCodeUnits
    }

    // MARK: State

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Number of undoable units — not the number of edits inside them.
    public var undoDepth: Int { undoStack.count }
    /// Number of redoable units.
    public var redoDepth: Int { redoStack.count }

    /// The intent of the newest undoable unit, if any. Useful for UI menu titles
    /// ("Undo Typing", "Undo Paste").
    public var newestIntent: EditIntent? { undoStack.last?.intent }

    /// Drops both stacks. Used when a document's identity changes underneath the
    /// editor and no recorded inverse would be meaningful.
    public func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: Recording

    /// Records a single applied edit, coalescing it into the open unit when
    /// `CoalescingPolicy` allows.
    public func record(_ applied: AppliedEdit, intent: EditIntent) {
        record([applied], intent: intent)
    }

    /// Records several applied edits as one candidate unit — a replace-all, a
    /// multi-cursor commit, a reindent.
    ///
    /// The group is never split, and a group of more than one edit never
    /// coalesces with a neighbour: it is one undo unit by construction.
    /// Recording anything clears the redo stack.
    public func record(_ applied: [AppliedEdit], intent: EditIntent) {
        guard !applied.isEmpty else { return }

        redoStack.removeAll()
        let now = clock.now()

        if applied.count == 1,
           let open = undoStack.last,
           !open.isSealed,
           let previousEdit = open.edits.last {
            let previous = RecordedEdit(applied: previousEdit, intent: open.intent)
            let next = RecordedEdit(applied: applied[0], intent: intent)
            let gap = open.lastInstant.duration(to: now)

            if CoalescingPolicy.shouldCoalesce(previous: previous, next: next, gap: gap) {
                undoStack[undoStack.count - 1].edits.append(applied[0])
                undoStack[undoStack.count - 1].lastInstant = now
                return
            }
        }

        undoStack.append(UndoUnit(intent: intent, edits: applied, lastInstant: now))
        enforceDepthCap()
    }

    // MARK: Undo / redo

    /// The step reversing the newest unit, which moves to the redo stack.
    /// The engine applies `step.edits` one at a time, in order.
    public func undoUnit() -> UndoStep? {
        guard let unit = undoStack.popLast() else { return nil }
        sealNewestUndoUnit()
        redoStack.append(unit)
        return unit.undoStep
    }

    /// The step re-applying the newest undone unit, which moves back to the undo
    /// stack. Sealed on the way back so a typing run resumed after a redo starts
    /// a fresh unit rather than growing the redone one.
    public func redoUnit() -> UndoStep? {
        guard var unit = redoStack.popLast() else { return nil }
        let step = unit.redoStep
        unit.isSealed = true
        unit.lastInstant = clock.now()
        undoStack.append(unit)
        enforceDepthCap()
        return step
    }

    // MARK: Private

    private func sealNewestUndoUnit() {
        guard !undoStack.isEmpty else { return }
        undoStack[undoStack.count - 1].isSealed = true
    }

    private func enforceDepthCap() {
        if undoStack.count > maximumUnitCount {
            undoStack.removeFirst(undoStack.count - maximumUnitCount)
        }
        // Then evict oldest until the retained-bytes budget is satisfied, always
        // keeping at least the newest unit so the last action stays undoable.
        var retained = undoStack.reduce(0) { $0 + $1.retainedCodeUnits }
        while undoStack.count > 1, retained > maximumRetainedCodeUnits {
            retained -= undoStack[0].retainedCodeUnits
            undoStack.removeFirst()
        }
    }
}
