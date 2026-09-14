#if canImport(UIKit) && !os(macOS)

import UIKit
import GlassEditorCore

/// The `UITextView` delegate — the same parity behaviors as
/// `GlassEditorNSCoordinator`, method for method.
///
/// This file is the reason the package exists. INTEGRATION.md A3 lists nine
/// behaviors the AppKit path has and the UIKit path does not, and calls the
/// missing marked-text guard "a live bug, not just a gap": rehighlighting during
/// IME composition replaces marked-text attributes, and in glassdb that is
/// masked only by the ASCII keyboard. Every one of those behaviors is
/// implemented here, against the same `GlassEditorModel`, so a fix on one
/// platform is a fix on both by construction rather than by discipline.
@MainActor
public final class GlassEditorUICoordinator: NSObject, UITextViewDelegate {

    public let model: GlassEditorModel

    /// Re-entrancy guard — the UIKit half of `isApplyingHighlight`. Depth-counted
    /// so a nested pass cannot drop the outer pass's guard (pen-suite finding);
    /// mirrors `GlassEditorNSCoordinator`.
    public var isApplyingHighlight: Bool { applyDepth > 0 }

    private var applyDepth = 0

    /// Runs `body` with the re-entrancy guard raised, restoring the prior depth
    /// on every exit path so nesting is safe.
    private func withApplying(_ body: () -> Void) {
        applyDepth += 1
        defer { applyDepth -= 1 }
        body()
    }

    /// Completed highlight passes; counted so the debounce is provable.
    public private(set) var highlightPassCount = 0

    /// Edits forwarded from the text view into the model.
    public private(set) var forwardedEditCount = 0

    let highlightDebounce: DebounceBox

    weak var gutter: GlassLineNumberGutterIOS?
    weak var textView: GlassTextViewIOS?

    public init(model: GlassEditorModel) {
        self.model = model
        self.highlightDebounce = DebounceBox(configuration: model.configuration)
        super.init()
    }

    // MARK: - Editing interception

    /// The single point where a user gesture becomes a `TextEdit`, identical in
    /// contract to the AppKit path: mutate the model, then let UIKit perform the
    /// same change so input methods, dictation and drag-and-drop keep working,
    /// with `UndoCoordinator` as the only undo authority.
    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard !isApplyingHighlight else { return true }

        let glassTextView = textView as? GlassTextViewIOS
        let intent = glassTextView?.pendingIntent
            ?? (text.isEmpty ? EditIntent.deleteBackward : .typing)
        glassTextView?.pendingIntent = nil

        let edit = TextEdit(
            replacementRange: range.lowerBound..<range.upperBound,
            text: text
        )
        do {
            try model.apply(edit, intent: intent)
            forwardedEditCount += 1
            return true
        } catch {
            assertionFailure("Rejected edit from UITextView: \(error)")
            return false
        }
    }

    // MARK: - Change notifications

    public func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingHighlight,
              let glassTextView = textView as? GlassTextViewIOS else { return }

        model.selectedRange = range(of: textView.selectedRange)
        gutter?.setNeedsDisplay()

        highlightDebounce.cancel()
        // UIKit's marked-text signal. `markedTextRange` is non-nil for exactly
        // the interval `hasMarkedText()` is true on AppKit, so the guard is the
        // same guard — this is the behavior A3 flags as missing today.
        guard textView.markedTextRange == nil else { return }

        scheduleHighlight(for: glassTextView)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isApplyingHighlight else { return }
        model.selectedRange = range(of: textView.selectedRange)
    }

    /// Keeps the sibling gutter aligned while the text view scrolls.
    /// `UITextViewDelegate` refines `UIScrollViewDelegate`, so this arrives
    /// without a second delegate.
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        gutter?.setNeedsDisplay()
    }

    func scheduleHighlight(for textView: GlassTextViewIOS) {
        let snapshot = textView.text ?? ""
        highlightDebounce.schedule { [weak self, weak textView] in
            guard let self, let textView,
                  (textView.text ?? "") == snapshot,
                  textView.markedTextRange == nil else { return }
            self.applyHighlightAttributes(to: textView)
        }
    }

    /// Runs any pending highlight pass immediately.
    public func flushPendingHighlight() {
        highlightDebounce.flush()
    }

    // MARK: - Attribute application

    /// Re-resolves attributes from the model's runs, theme and surface.
    ///
    /// **This is where the UIKit regression is fixed.** The shipped path rebuilt
    /// the entire attributed string on every keystroke
    /// (`HighlightedTextEditor.swift:110`), which is both the performance problem
    /// and the marked-text bug. Here the characters are never touched: attributes
    /// are reset to the base and the runs are re-applied over them, inside one
    /// `beginEditing`/`endEditing` transaction, only when the debounce fires and
    /// only when no composition is in flight.
    ///
    /// v1 re-applies over the whole document rather than over changed ranges
    /// only. The debounce plus attribute-only application is what removes the
    /// per-keystroke cost; narrowing to the edited range is a further
    /// optimization that needs the highlighter to report which runs changed,
    /// which is a `GlassEditorCore` concern rather than a backend one.
    public func applyHighlightAttributes(to textView: GlassTextViewIOS) {
        guard let storage = textView.contentStorage?.textStorage else { return }

        withApplying {
            let savedSelection = textView.selectedRange
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
            textView.selectedRange = GlassEditorUICoordinator.clamped(
                savedSelection, maximum: storage.length
            )
            textView.appliedFontSize = CGFloat(model.configuration.fontSize)
            textView.assertUsingTextKit2()
            gutter?.setNeedsDisplay()
            highlightPassCount += 1
        }
    }

    private func restoreTypingAttributes(
        _ attributes: [NSAttributedString.Key: Any],
        on textView: GlassTextViewIOS
    ) {
        var restored = attributes
        restored[.font] = AttributedAssembly.font(
            configuration: model.configuration, surface: model.surfaceCondition
        )
        textView.typingAttributes = restored
    }

    /// Pushes the model's content into the text view — undo, redo, a
    /// programmatic edit, a remote reload.
    public func syncTextViewFromModel(_ textView: GlassTextViewIOS) {
        guard let storage = textView.contentStorage?.textStorage else { return }
        guard storage.string != model.text else {
            applyHighlightAttributes(to: textView)
            return
        }

        withApplying {
            let savedSelection = textView.selectedRange
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
            textView.selectedRange = GlassEditorUICoordinator.clamped(
                savedSelection, maximum: storage.length
            )
            textView.appliedFontSize = CGFloat(model.configuration.fontSize)

            textView.assertUsingTextKit2()
            model.selectedRange = range(of: textView.selectedRange)
            gutter?.setNeedsDisplay()
            highlightPassCount += 1
        }
    }

    /// Applies a configuration change, forcing a pass when the font size moved.
    public func configurationDidChange(on textView: GlassTextViewIOS) {
        highlightDebounce.delay = .milliseconds(
            max(0, model.configuration.highlightDebounceMilliseconds)
        )
        if textView.appliedFontSize != CGFloat(model.configuration.fontSize) {
            applyHighlightAttributes(to: textView)
        }
    }

    // MARK: - Helpers

    /// Selection clamping on UTF-16 counts — the same rule as AppKit, replacing
    /// the shipped inline version at `HighlightedTextEditor.swift:81–93`.
    static func clamped(_ range: NSRange, maximum: Int) -> NSRange {
        let location = min(max(range.location, 0), maximum)
        return NSRange(location: location, length: min(range.length, maximum - location))
    }

    private func range(of nsRange: NSRange) -> Range<Int> {
        let lower = max(nsRange.location, 0)
        return lower..<(lower + max(nsRange.length, 0))
    }

    func withHighlightApplication(_ body: () -> Void) {
        withApplying(body)
    }
}

#endif
