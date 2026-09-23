#if canImport(AppKit) && os(macOS)

import AppKit
import GlassEditorCore

/// The `NSTextView` delegate: every behavior INTEGRATION.md A3 marks "required
/// in the package", in one place.
///
/// The shipped AppKit path (`HighlightedTextEditor.swift:292–346`) is the
/// reference for all of it — debounce, marked-text guard, re-entrancy guard,
/// typing-attribute preservation, applied-font-size tracking. What changes here
/// is where the document lives: the shipped coordinator wrote back into a
/// SwiftUI binding and re-highlighted by replacing the whole attributed string,
/// while this one feeds `GlassEditorModel` and only ever moves attributes.
@MainActor
public final class GlassEditorNSCoordinator: NSObject, NSTextViewDelegate {

    /// The document session. The coordinator renders it and feeds user gestures
    /// into it; it never holds text of its own.
    public let model: GlassEditorModel

    /// True while any programmatic mutation of the text view is in flight —
    /// attribute application or a model-driven content sync.
    ///
    /// Re-entrancy guard, from `isApplyingHighlight`
    /// (`HighlightedTextEditor.swift:294, 338, 340`). Without it, applying
    /// attributes can re-enter `textDidChange`, which schedules another
    /// application, which re-enters again: a highlight pass that never settles
    /// and a `textDidChange` that reports the engine's own writes to the model as
    /// if the user had typed them.
    ///
    /// Backed by a **depth counter**, not a bare flag: a highlight pass can nest
    /// (a sync that repaints, a surface change during application), and a flag
    /// cleared by the inner `defer` would drop the guard while the outer pass is
    /// still writing — reported by the pen suite. The guard stays up until the
    /// outermost frame exits.
    public var isApplyingHighlight: Bool { applyDepth > 0 }

    private var applyDepth = 0

    /// Runs `body` with the re-entrancy guard raised, restoring the prior depth
    /// on every exit path so nesting is safe.
    private func withApplying(_ body: () -> Void) {
        applyDepth += 1
        defer { applyDepth -= 1 }
        body()
    }

    /// Completed highlight passes. Exists so the debounce contract can be
    /// asserted by counting rather than by sleeping.
    public private(set) var highlightPassCount = 0

    /// Edits forwarded from the text view into the model. Counted for the same
    /// reason: it is how a test proves the re-entrancy guard actually holds.
    public private(set) var forwardedEditCount = 0

    /// Debounced rehighlighting, at `configuration.highlightDebounceMilliseconds`
    /// (75 by default — the shipped interval, now configurable).
    let highlightDebounce: DebounceBox

    /// The gutter to invalidate when line structure changes. Weak: the scroll
    /// view owns it.
    weak var gutter: GlassLineNumberGutter?

    weak var textView: GlassTextView?

    public init(model: GlassEditorModel) {
        self.model = model
        self.highlightDebounce = DebounceBox(configuration: model.configuration)
        super.init()
    }

    // MARK: - Editing interception

    /// The single point where a user gesture becomes a `TextEdit`.
    ///
    /// The model is mutated *first* and the text view is then allowed to perform
    /// the identical change itself (`return true`), which keeps AppKit's own
    /// editing behavior — input methods, dictation, drag-and-drop, services —
    /// intact while `UndoCoordinator` remains the only undo authority. Rejecting
    /// the change and re-driving the view from the model instead would mean
    /// reimplementing all of that.
    ///
    /// **Input methods.** This fires for marked (provisional) text as well as
    /// committed text, and the marked change *is* applied to the model. That is
    /// deliberate: the buffer must mirror the view's storage exactly, and a
    /// composition step that changed one and not the other would leave every
    /// subsequent range invalid. The IME guarantee in A3 is about not *rewriting
    /// attributes* mid-composition, which `textDidChange` enforces; it is not a
    /// licence to let the two texts diverge. The cost is that a long composition
    /// lands as several undo units rather than one.
    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // Attribute-only change (`nil` replacement) — nothing to record.
        guard let replacementString else { return true }
        // Our own write, already in the model.
        guard !isApplyingHighlight else { return true }

        let glassTextView = textView as? GlassTextView
        let intent = glassTextView?.pendingIntent
            ?? inferredIntent(range: affectedCharRange, replacement: replacementString)
        glassTextView?.pendingIntent = nil

        let edit = TextEdit(
            replacementRange: affectedCharRange.lowerBound..<affectedCharRange.upperBound,
            text: replacementString
        )
        do {
            try model.apply(edit, intent: intent)
            forwardedEditCount += 1
            return true
        } catch {
            // The view proposed a range the buffer rejects — out of bounds, or
            // splitting a surrogate pair. Refusing the change keeps the two texts
            // identical, which is the invariant everything else depends on.
            assertionFailure("Rejected edit from NSTextView: \(error)")
            return false
        }
    }

    /// Intent when no AppKit action claimed the edit.
    ///
    /// `GlassTextView` tags the cases that are genuinely ambiguous from geometry
    /// alone — paste, the delete family, tab — so what reaches here is ordinary
    /// keystroke input or a system-driven insertion (dictation, drag). An
    /// insertion is typing; a bare deletion is a backspace, which is the only
    /// delete AppKit routes here untagged.
    private func inferredIntent(range: NSRange, replacement: String) -> EditIntent {
        replacement.isEmpty ? .deleteBackward : .typing
    }

    // MARK: - Change notifications

    public func textDidChange(_ notification: Notification) {
        guard !isApplyingHighlight,
              let textView = notification.object as? GlassTextView else { return }

        model.selectedRange = range(of: textView.selectedRange())
        gutter?.needsDisplay = true

        // Cancel first, then bail on marked text — the shipped order
        // (`HighlightedTextEditor.swift:312–313`). An in-flight pass scheduled
        // before composition started must not land *during* composition, so the
        // cancel is unconditional and the guard follows it.
        highlightDebounce.cancel()
        guard !textView.hasMarkedText() else { return }

        scheduleHighlight(for: textView)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingHighlight,
              let textView = notification.object as? NSTextView else { return }
        model.selectedRange = range(of: textView.selectedRange())
    }

    /// Schedules one debounced highlight pass for the text view's current
    /// content.
    ///
    /// The captured `snapshot` is checked again when the timer lands: a pass
    /// computed for text that no longer exists is dropped rather than applied to
    /// whatever replaced it. The marked-text check is repeated too, because
    /// composition can begin during the idle interval — this is the second of the
    /// two guards at `HighlightedTextEditor.swift:313` and `:320`.
    func scheduleHighlight(for textView: GlassTextView) {
        let snapshot = textView.string
        highlightDebounce.schedule { [weak self, weak textView] in
            guard let self, let textView,
                  textView.string == snapshot,
                  !textView.hasMarkedText() else { return }
            self.applyHighlightAttributes(to: textView)
        }
    }

    /// Runs any pending highlight pass immediately. Deterministic alternative to
    /// waiting out the debounce.
    public func flushPendingHighlight() {
        highlightDebounce.flush()
    }

    // MARK: - Attribute application

    /// Re-resolves every attribute from the model's runs, theme and surface.
    ///
    /// Attributes only — the characters are never touched. Replacing the whole
    /// attributed string, as the shipped path did
    /// (`HighlightedTextEditor.swift:339`), discards marked text and makes every
    /// highlight pass look like a document mutation to the layout system.
    public func applyHighlightAttributes(to textView: GlassTextView) {
        guard let storage = textView.glassTextStorage else { return }

        withApplying {
            let savedSelection = textView.selectedRange()
            let savedTypingAttributes = textView.typingAttributes

            storage.beginEditing()
            AttributedAssembly.resetBaseAttributes(
                on: storage,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
            AttributedAssembly.applyRuns(
                model.highlightRuns,
                to: storage,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
            storage.endEditing()

            restoreTypingAttributes(savedTypingAttributes, on: textView)
            textView.setSelectedRange(
                GlassEditorNSCoordinator.clamped(savedSelection, maximum: storage.length)
            )
            textView.appliedFontSize = CGFloat(model.configuration.fontSize)
            textView.assertOnItsTextSystem()
            gutter?.needsDisplay = true
            highlightPassCount += 1
        }
    }

    /// Restores the caret's typing attributes, with the font refreshed.
    ///
    /// Preserving them keeps a caret sitting inside a string literal typing in
    /// the string color instead of snapping to plain (the reason the shipped path
    /// saves and restores them at `HighlightedTextEditor.swift:322, 324`). The
    /// font is the one attribute that must *not* survive verbatim: a size or
    /// surface-weight change has to reach the next character typed, which is what
    /// `appliedFontSize` tracking exists to guarantee.
    private func restoreTypingAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        on textView: GlassTextView
    ) {
        var restored = attributes
        restored[.font] = AttributedAssembly.font(
            configuration: model.configuration, surface: model.surfaceCondition
        )
        textView.typingAttributes = restored
    }

    /// Pushes the model's content into the text view — undo, redo, a
    /// programmatic edit, a remote reload.
    ///
    /// Guarded, so the resulting `textDidChange` is not read back as a user edit
    /// and re-recorded into the undo stack it just came out of.
    public func syncTextViewFromModel(_ textView: GlassTextView) {
        guard let storage = textView.glassTextStorage else { return }
        guard storage.string != model.text else {
            applyHighlightAttributes(to: textView)
            return
        }

        withApplying {
            let savedSelection = textView.selectedRange()
            let savedTypingAttributes = textView.typingAttributes

            storage.beginEditing()
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length), with: model.text
            )
            AttributedAssembly.resetBaseAttributes(
                on: storage,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
            AttributedAssembly.applyRuns(
                model.highlightRuns,
                to: storage,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
            storage.endEditing()

            restoreTypingAttributes(savedTypingAttributes, on: textView)
            textView.setSelectedRange(
                GlassEditorNSCoordinator.clamped(savedSelection, maximum: storage.length)
            )
            textView.appliedFontSize = CGFloat(model.configuration.fontSize)

            textView.assertOnItsTextSystem()
            model.selectedRange = range(of: textView.selectedRange())
            gutter?.needsDisplay = true
            highlightPassCount += 1
        }
    }

    /// Applies a configuration change, forcing a pass when the font size moved.
    ///
    /// `appliedFontSize` is the whole reason this is not a no-op when the text is
    /// unchanged: point size lives in the attributes, so nothing about the string
    /// tells the view it is now stale
    /// (`HighlightedTextEditor.swift:241, 273, 276`).
    public func configurationDidChange(on textView: GlassTextView) {
        highlightDebounce.delay = .milliseconds(
            max(0, model.configuration.highlightDebounceMilliseconds)
        )
        if textView.appliedFontSize != CGFloat(model.configuration.fontSize) {
            applyHighlightAttributes(to: textView)
        }
    }

    // MARK: - Helpers

    /// Selection clamping on UTF-16 counts (INTEGRATION.md A3; the shipped
    /// `clamped(_:maximum:)` at `HighlightedTextEditor.swift:286–289`).
    static func clamped(_ range: NSRange, maximum: Int) -> NSRange {
        let location = min(max(range.location, 0), maximum)
        return NSRange(location: location, length: min(range.length, maximum - location))
    }

    private func range(of nsRange: NSRange) -> Range<Int> {
        let lower = max(nsRange.location, 0)
        return lower..<(lower + max(nsRange.length, 0))
    }

    /// Runs `body` inside the re-entrancy guard.
    ///
    /// The guard is what makes "the engine's own writes are not user edits" true;
    /// this is the seam that lets a test prove it by driving a delegate callback
    /// while a programmatic application is notionally in flight.
    func withHighlightApplication(_ body: () -> Void) {
        withApplying(body)
    }
}

#endif
