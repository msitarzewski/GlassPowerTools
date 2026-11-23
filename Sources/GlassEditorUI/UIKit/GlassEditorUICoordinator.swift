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

        // Return and Tab become more than they were: the line's indent, spaces to the next stop, an indent of lines.
        if let glassTextView = textView as? GlassTextViewIOS,
           typedReturnOrTab(text, replacing: range, in: glassTextView) {
            return false
        }

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

    // MARK: - The selection's own menu

    /// The selection's menu, with the Mac's Edit ▸ Transformations in it (2026-11-03): iPad, iPhone and Vision Pro have
    /// no Edit menu to hold them. Make Upper Case, Make Lower Case and Capitalize each change the selection as one
    /// step, "Undo Change Case", and leave it selected.
    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                         suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard textView.isEditable, let glassTextView = textView as? GlassTextViewIOS else { return nil }
        // The line commands, for a finger: no keyboard means no ⌘] (2026-11-22). At a caret too.
        func line(_ title: String, _ symbol: String, _ run: @escaping (GlassTextViewIOS) -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak glassTextView] _ in
                if let glassTextView { run(glassTextView) }
            }
        }
        let lines = UIMenu(title: "Lines", children: [
            line("Indent", "increase.indent") { $0.indentLines(nil) },
            line("Outdent", "decrease.indent") { $0.outdentLines(nil) },
            line("Comment or Uncomment", "number") { $0.toggleLineComments(nil) },
            line("Move Up", "arrow.up") { $0.moveLinesUp(nil) },
            line("Move Down", "arrow.down") { $0.moveLinesDown(nil) },
            line("Duplicate", "plus.square.on.square") { $0.duplicateLines(nil) },
            line("Delete", "trash") { $0.deleteLines(nil) },
            line("Join", "arrow.right.and.line.vertical.and.arrow.left") { $0.joinLines(nil) },
            line("Sort", "arrow.up.arrow.down") { $0.sortLines(nil) },
        ])
        guard range.length > 0 else { return UIMenu(children: suggestedActions + [lines]) }
        let transformations = UIMenu(title: "Transformations", children: [
            changeCase("Make Upper Case", in: glassTextView, range: range) { $0.uppercased() },
            changeCase("Make Lower Case", in: glassTextView, range: range) { $0.lowercased() },
            changeCase("Capitalize", in: glassTextView, range: range) { $0.capitalized },
        ])
        return UIMenu(children: suggestedActions + [transformations, lines])
    }

    private func changeCase(_ title: String, in textView: GlassTextViewIOS, range: NSRange,
                            _ change: @escaping (String) -> String) -> UIAction {
        UIAction(title: title) { [weak self, weak textView] _ in
            guard let self, let textView else { return }
            self.changeCase(in: textView, range: range, change)
        }
    }

    /// Return and Tab, by the Mac's rules (`LineEditing`, 2026-11-22). The keyboard asks this delegate before it types
    /// either, so this is where they are made: the document first, as one typing step (Tab's as Indentation), then the
    /// view under the guard, then the caret. UIKit is then told no, and types nothing more.
    ///
    /// - Returns: whether it made the change; false leaves the keystroke to UIKit as it was.
    func typedReturnOrTab(_ text: String, replacing range: NSRange, in textView: GlassTextViewIOS) -> Bool {
        guard text == "\n" || text == "\t", textView.canEditLines else { return false }
        let content = textView.textStorage.string as NSString
        let selection = self.range(of: range)
        let indentation = model.configuration.indentation
        if text == "\t", LineEditing.selectionSpansLines(selection, in: content) {
            textView.indentLines(nil)
            return true
        }
        let typed: (text: String, caret: Int)
        if text == "\n" {
            typed = LineEditing.newline(in: content, replacing: selection, indentation: indentation,
                                        language: model.language)
        } else {
            let tab = LineEditing.tab(in: content, at: selection.lowerBound, indentation: indentation)
            typed = (tab, (tab as NSString).length)
        }
        do {
            try model.apply(TextEdit(replacementRange: selection, text: typed.text),
                            intent: text == "\t" ? .indentation : .typing)
        } catch {
            assertionFailure("Rejected a typed \(text == "\n" ? "Return" : "Tab"): \(error)")
            return false
        }
        textView.inputDelegate?.textWillChange(textView)
        withApplying {
            textView.textStorage.replaceCharacters(
                in: range, with: NSAttributedString(string: typed.text, attributes: textView.typingAttributes))
        }
        textView.inputDelegate?.textDidChange(textView)
        let caret = NSRange(location: range.location + typed.caret, length: 0)
        textView.selectedRange = caret
        textView.scrollRangeToVisible(caret)
        // What a keystroke's change notice does: the selection to the document, the gutter, the next highlight.
        textViewDidChange(textView)
        return true
    }

    /// A line command (`LineEditing`), made as a change of case is: one step of the model under `intent`, then the view
    /// follows it, and the selection goes where the command says.
    func performLineEdit(in textView: GlassTextViewIOS, intent: EditIntent,
                         _ make: (NSString, Range<Int>, GlassEditorModel) -> LineEdit?) {
        let selection = range(of: textView.selectedRange)
        guard let lineEdit = make(textView.textStorage.string as NSString, selection, model) else { return }
        do {
            try model.apply(lineEdit.edit, intent: intent)
        } catch {
            assertionFailure("Rejected a line command: \(error)")
            return
        }
        syncTextViewFromModel(textView)
        textView.selectedRange = NSRange(location: lineEdit.selection.lowerBound, length: lineEdit.selection.count)
        model.selectedRange = lineEdit.selection
    }

    /// One step of the model, then the view follows it, as an undo does.
    func changeCase(in textView: GlassTextViewIOS, range: NSRange, _ change: (String) -> String) {
        let selection = self.range(of: range)
        guard let selected = try? model.substring(in: selection) else { return }
        let changed = change(selected)
        guard changed != selected else { return }
        do {
            try model.apply(TextEdit(replacementRange: selection, text: changed), intent: .changeCase)
        } catch {
            assertionFailure("Rejected a change of case: \(error)")
            return
        }
        syncTextViewFromModel(textView)
        let length = (changed as NSString).length
        textView.selectedRange = NSRange(location: range.location, length: length)
        model.selectedRange = selection.lowerBound..<(selection.lowerBound + length)
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
        // And the tab width, which a font change moves too (2026-11-22).
        restored[.paragraphStyle] = AttributedAssembly.paragraphStyle(
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
