#if canImport(UIKit) && !os(macOS)

import UIKit
import Observation
import GlassEditorCore

/// The iOS / iPadOS / visionOS backend, bound to one `GlassEditorModel`.
///
/// Structurally identical to `GlassEditorAppKitEngine` — same model, same
/// coordinator responsibilities, same gutter mapping, same canvas ownership —
/// differing only where the two frameworks genuinely differ. `GlassEditorEngine`
/// is what lets a consumer hold either one without knowing which.
@MainActor
public final class GlassEditorUIKitEngine: GlassEditorEngine {

    public let model: GlassEditorModel

    /// The view to install. Holds the gutter and the text view side by side.
    public let containerView: UIView
    public let textView: GlassTextViewIOS
    public let coordinator: GlassEditorUICoordinator
    public private(set) var gutter: GlassLineNumberGutterIOS?

    private var gutterWidthConstraint: NSLayoutConstraint?

    // MARK: - Construction

    public init(model: GlassEditorModel) {
        self.model = model
        self.textView = GlassTextViewIOS.makeTextKit2()
        self.containerView = UIView()
        self.coordinator = GlassEditorUICoordinator(model: model)

        containerView.backgroundColor = .clear
        textView.delegate = coordinator
        textView.isEditable = model.configuration.isEditable
        textView.textContainer.widthTracksTextView = model.configuration.wrapsLines
        textView.textContainer.size = CGSize(
            width: model.configuration.wrapsLines ? 0 : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        coordinator.textView = textView

        installViews()
        applyThemeToCanvas()
        loadInitialContent()
        textView.assertUsingTextKit2()
        appliedConfiguration = model.configuration
        observeModelHighlights()
        observeModelRevision()
        observeModelAppearance()
        observeModelConfiguration()
    }

    // MARK: - Model observation

    // Mirror of GlassEditorAppKitEngine's model observation, for the same
    // reason: the model is the API, and a SwiftUI consumer never holds the
    // engine. `highlightRuns` changes repaint (deferred under composition);
    // `revision` changes resync only when the view has genuinely diverged, so
    // typing-driven bumps stay no-ops and the debounce owns rehighlighting;
    // `theme`/`surfaceCondition` changes re-resolve; `configuration` changes
    // diff against the last-applied config.

    /// The configuration last pushed to the view, for delta computation.
    private var appliedConfiguration = GlassEditorConfiguration()

    private func observeModelAppearance() {
        withObservationTracking { [weak self] in
            _ = self?.model.theme
            _ = self?.model.surfaceCondition
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.repaintForAppearanceChange()
                self.observeModelAppearance()
            }
        }
    }

    private func observeModelConfiguration() {
        withObservationTracking { [weak self] in
            _ = self?.model.configuration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.appliedConfiguration
                self.appliedConfiguration = self.model.configuration
                self.applyConfiguration(from: previous)
                self.observeModelConfiguration()
            }
        }
    }

    private func observeModelHighlights() {
        withObservationTracking { [weak self] in
            _ = self?.model.highlightRuns
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.textView.markedTextRange != nil {
                    self.coordinator.scheduleHighlight(for: self.textView)
                } else {
                    self.coordinator.applyHighlightAttributes(to: self.textView)
                }
                self.observeModelHighlights()
            }
        }
    }

    private func observeModelRevision() {
        withObservationTracking { [weak self] in
            _ = self?.model.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.textView.text != self.model.text {
                    self.coordinator.syncTextViewFromModel(self.textView)
                }
                self.observeModelRevision()
            }
        }
    }

    private func installViews() {
        let gutterView = GlassLineNumberGutterIOS(textView: textView, model: model)
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(gutterView)
        containerView.addSubview(textView)

        let width = gutterView.widthAnchor.constraint(
            equalToConstant: model.configuration.showsLineNumbers ? EditorMetrics.gutterWidth : 0
        )
        gutterWidthConstraint = width
        gutterView.isHidden = !model.configuration.showsLineNumbers

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: containerView.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            width,

            textView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        gutter = gutterView
        coordinator.gutter = gutterView
    }

    private func loadInitialContent() {
        guard let storage = textView.contentStorage?.textStorage else { return }
        storage.setAttributedString(
            AttributedAssembly.attributedString(
                text: model.text,
                runs: model.highlightRuns,
                theme: model.theme,
                surface: model.surfaceCondition,
                configuration: model.configuration
            )
        )
        textView.appliedFontSize = CGFloat(model.configuration.fontSize)
        textView.typingAttributes = AttributedAssembly.baseAttributes(
            theme: model.theme,
            surface: model.surfaceCondition,
            configuration: model.configuration
        )
    }

    private func applyThemeToCanvas() {
        textView.canvasColor = AttributedAssembly.canvasColor(
            theme: model.theme, surface: model.surfaceCondition
        )
        gutter?.refresh()
    }

    // MARK: - GlassEditorEngine

    // Setters write only the model; observation installed in `init` runs the
    // view side-effects, so model-first and engine-first mutation share one
    // path. See the matching note in `GlassEditorAppKitEngine`.

    public var configuration: GlassEditorConfiguration {
        get { model.configuration }
        set { model.configuration = newValue }
    }

    public var surfaceCondition: SurfaceCondition {
        get { model.surfaceCondition }
        set { model.surfaceCondition = newValue }
    }

    public var theme: EditorTheme {
        get { model.theme }
        set { model.theme = newValue }
    }

    /// Applies a configuration delta to the view, diffing the branch-triggering
    /// fields against the previously-applied configuration.
    private func applyConfiguration(from previous: GlassEditorConfiguration) {
        let current = model.configuration
        textView.isEditable = current.isEditable
        if previous.wrapsLines != current.wrapsLines {
            textView.textContainer.widthTracksTextView = current.wrapsLines
            textView.textContainer.size = CGSize(
                width: current.wrapsLines ? 0 : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        if previous.showsLineNumbers != current.showsLineNumbers {
            gutterWidthConstraint?.constant =
                current.showsLineNumbers ? EditorMetrics.gutterWidth : 0
            gutter?.isHidden = !current.showsLineNumbers
            containerView.setNeedsLayout()
        }
        coordinator.configurationDidChange(on: textView)
        // See the AppKit note: family and contrast floor change the ink without
        // touching `appliedFontSize`, so they must force a re-resolve too.
        if previous.fontName != current.fontName
            || previous.fontSize != current.fontSize
            || previous.minimumContrastRatio != current.minimumContrastRatio {
            repaintForAppearanceChange()
        }
    }

    /// Re-resolves canvas and every run against the current theme/surface.
    private func repaintForAppearanceChange() {
        applyThemeToCanvas()
        coordinator.applyHighlightAttributes(to: textView)
    }

    public var text: String { model.text }

    public func apply(_ edit: TextEdit) throws {
        try apply(edit, intent: .programmatic)
    }

    public func apply(_ edit: TextEdit, intent: EditIntent) throws {
        try model.apply(edit, intent: intent)
        coordinator.syncTextViewFromModel(textView)
    }

    public func apply(_ batch: TextEditBatch) throws {
        try apply(batch, intent: .programmatic)
    }

    public func apply(_ batch: TextEditBatch, intent: EditIntent) throws {
        try model.apply(batch, intent: intent)
        coordinator.syncTextViewFromModel(textView)
    }

    public func setHighlightRuns(_ runs: [HighlightRun]) {
        model.setHighlights(runs)
        guard textView.markedTextRange == nil else {
            coordinator.scheduleHighlight(for: textView)
            return
        }
        coordinator.applyHighlightAttributes(to: textView)
    }

    public var selectedRange: Range<Int> {
        get { model.selectedRange }
        set {
            let clamped = GlassEditorUICoordinator.clamped(
                NSRange(location: newValue.lowerBound, length: newValue.count),
                maximum: model.utf16Length
            )
            textView.selectedRange = clamped
            model.selectedRange = clamped.lowerBound..<clamped.upperBound
        }
    }

    // MARK: - Undo / redo

    @discardableResult
    public func undo() -> Bool {
        guard model.undo() else { return false }
        coordinator.syncTextViewFromModel(textView)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard model.redo() else { return false }
        coordinator.syncTextViewFromModel(textView)
        return true
    }

    public var canUndo: Bool { model.canUndo }
    public var canRedo: Bool { model.canRedo }

    // MARK: - Find

    @discardableResult
    public func replaceAll(of query: FindQuery, with replacement: String) throws -> Int {
        let count = try model.replaceAll(of: query, with: replacement)
        if count > 0 { coordinator.syncTextViewFromModel(textView) }
        return count
    }

    @discardableResult
    public func findNext(_ query: FindQuery, wrapping: Bool = true) throws -> Range<Int>? {
        guard let hit = try model.nextMatch(of: query, wrapping: wrapping) else { return nil }
        selectedRange = hit
        textView.scrollRangeToVisible(NSRange(location: hit.lowerBound, length: hit.count))
        return hit
    }
}

#endif
