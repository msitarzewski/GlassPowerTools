#if canImport(AppKit) && os(macOS)

import AppKit
import Observation
import GlassEditorCore

/// The macOS backend: an `NSScrollView` + `GlassTextView` + gutter, bound to one
/// `GlassEditorModel`.
///
/// Everything above `GlassEditorEngine` is backend-agnostic, and TextKit 2
/// assumptions stop here — that is what keeps D-001 reversible. The engine owns
/// view construction and the model↔view sync; the coordinator owns the delegate
/// behaviors; the model owns the document.
@MainActor
public final class GlassEditorAppKitEngine: GlassEditorEngine {

    /// The document session. Consumers may hold this directly — it is the same
    /// object a SwiftUI `GlassEditorView` binds to.
    public let model: GlassEditorModel

    /// The view to install. Holds the gutter and the scroll view side by side,
    /// exactly as `GlassEditorUIKitEngine.containerView` holds the gutter and
    /// the text view.
    public let containerView: NSView
    public let textView: GlassTextView
    public let scrollView: NSScrollView
    public let coordinator: GlassEditorNSCoordinator
    public private(set) var gutter: GlassLineNumberGutter?

    private var gutterWidthConstraint: NSLayoutConstraint?

    // MARK: - Construction

    public init(model: GlassEditorModel) {
        self.model = model
        self.textView = GlassTextView.makeTextKit2()
        self.scrollView = NSScrollView()
        self.containerView = NSView()
        self.coordinator = GlassEditorNSCoordinator(model: model)

        // The scroll view draws no background for the same reason the text view
        // does not: the canvas is painted from the theme at the surface's alpha,
        // and anything else would put an opaque plate behind a window the user
        // asked to see through.
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // **The window's title bar is not this view's to inset for.** SwiftUI
        // already places this view below the tab strip, in a column that starts
        // where it should, so an automatic inset the height of a title bar is a
        // second correction for something already corrected. The gutter reads
        // whatever inset does end up here (`verticalOffset`), so this setting
        // decides where the text sits and nothing else.
        scrollView.automaticallyAdjustsContentInsets = false

        textView.delegate = coordinator
        textView.isEditable = model.configuration.isEditable
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = model.configuration.wrapsLines
        textView.textContainer?.size = NSSize(
            width: model.configuration.wrapsLines ? 0 : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
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

    // The model is the API, not the view (GlassEditorView.swift). A consumer
    // that only holds the model — every SwiftUI consumer — calls
    // `model.setHighlights(_:)`, `model.apply(_:intent:)`, and mutates
    // `model.theme` / `model.surfaceCondition` / `model.configuration` directly,
    // so the engine must notice on its own; requiring the `engine.*` setters
    // would quietly make the model a second-class entry point. Separate scopes,
    // because the responses differ:
    //
    // - `highlightRuns` changed → repaint now (or after composition ends).
    // - `revision` changed → repaint only if the view has actually diverged
    //   from the model. Typing bumps `revision` too, but by the time this
    //   handler runs the coordinator has already mirrored the edit, the texts
    //   compare equal, and this is a no-op — which is what keeps the 75ms
    //   debounce, not this path, in charge of typing-driven rehighlights.
    // - `theme` / `surfaceCondition` changed → re-resolve canvas + every run.
    // - `configuration` changed → diff against the last-applied config.

    /// The configuration last pushed to the view, so the configuration observer
    /// can diff wrap-mode and gutter-visibility transitions.
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
                if self.textView.hasMarkedText() {
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
                // O(length) compare, but only on content mutations, and equal
                // strings short-circuit at the first differing code unit.
                if self.textView.string != self.model.text {
                    self.coordinator.syncTextViewFromModel(self.textView)
                }
                self.observeModelRevision()
            }
        }
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

    /// Lays the gutter out beside the scroll view. The mirror of
    /// `GlassEditorUIKitEngine.installViews()`, and for the same reason: a
    /// gutter that is a sibling of the text can only occupy the space its
    /// container gives it, where a ruler spans its whole scroll view.
    ///
    /// Turning line numbers off collapses the width to zero and hides the view
    /// rather than tearing it down, so the transition is one constant and the
    /// gutter keeps its scroll observation.
    private func installViews() {
        let gutterView = GlassLineNumberGutter(
            scrollView: scrollView, textView: textView, model: model
        )
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(gutterView)
        containerView.addSubview(scrollView)

        let width = gutterView.widthAnchor.constraint(
            equalToConstant: model.configuration.showsLineNumbers ? EditorMetrics.gutterWidth : 0
        )
        gutterWidthConstraint = width
        gutterView.isHidden = !model.configuration.showsLineNumbers

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            // Pinned to the scroll view rather than to the container, so that a
            // consumer which insets the scroll view insets the numbers with it.
            gutterView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            width,

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        gutter = gutterView
        coordinator.gutter = gutterView
    }

    private func applyThemeToCanvas() {
        textView.canvasColor = AttributedAssembly.canvasColor(
            theme: model.theme, surface: model.surfaceCondition
        )
        gutter?.refresh()
    }

    // MARK: - GlassEditorEngine

    // Theme, configuration, and surface all live on the model — it is the single
    // source of truth and the consumer-facing API. These setters therefore only
    // *write the model*; the observation installed in `init` runs the view
    // side-effects, so a consumer mutating `engine.theme` and one mutating
    // `model.theme` directly travel the identical path. Doing the side-effects
    // in the setter instead left model-first mutation silently unrendered — and
    // made `GlassEditorView`'s `engine.X != model.X` update guards tautological,
    // since the getter reads straight back from the model (both found by the pen
    // suite).

    public var configuration: GlassEditorConfiguration {
        get { model.configuration }
        set { model.configuration = newValue }
    }

    public var surfaceCondition: SurfaceCondition {
        get { model.surfaceCondition }
        set { model.surfaceCondition = newValue }
    }

    /// The palette. Changing it re-resolves everything, canvas included.
    public var theme: EditorTheme {
        get { model.theme }
        set { model.theme = newValue }
    }

    /// Applies a configuration delta to the view. Called from observation with
    /// the previously-applied configuration so the branch-triggering fields
    /// (wrap mode, gutter visibility) are diffed rather than reapplied blindly.
    private func applyConfiguration(from previous: GlassEditorConfiguration) {
        let current = model.configuration
        textView.isEditable = current.isEditable
        if previous.wrapsLines != current.wrapsLines {
            textView.textContainer?.widthTracksTextView = current.wrapsLines
            textView.textContainer?.size = NSSize(
                width: current.wrapsLines ? 0 : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        if previous.showsLineNumbers != current.showsLineNumbers {
            gutterWidthConstraint?.constant =
                current.showsLineNumbers ? EditorMetrics.gutterWidth : 0
            gutter?.isHidden = !current.showsLineNumbers
            containerView.needsLayout = true
        }
        coordinator.configurationDidChange(on: textView)
        // Any field that changes how a glyph is inked must force a re-resolve —
        // not just font size. Font *family* and the contrast floor both change
        // the rendered attributes while leaving `appliedFontSize` untouched, so
        // the shipped font-size-only trigger dropped them (pen-suite finding).
        if previous.fontName != current.fontName
            || previous.fontSize != current.fontSize
            || previous.minimumContrastRatio != current.minimumContrastRatio {
            repaintForAppearanceChange()
        }
    }

    /// Re-resolves the canvas and every run against the current theme/surface.
    /// A surface or theme change re-resolves color through `ContrastAdapter` and
    /// can change glyph weight, so it is a full, immediate attribute pass — it
    /// often comes from a slider the user is dragging and must track it.
    private func repaintForAppearanceChange() {
        applyThemeToCanvas()
        coordinator.applyHighlightAttributes(to: textView)
    }

    public var text: String { model.text }

    public func apply(_ edit: TextEdit) throws {
        try apply(edit, intent: .programmatic)
    }

    /// Applies an edit under an explicit intent — the richer form the protocol's
    /// single-argument requirement funnels into.
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
        // Straight to the view: the debounce governs how often a *parse* is
        // turned into a pass after typing, not how long a parse that has already
        // arrived waits. Composition is still respected — attributes are never
        // rewritten under marked text.
        guard !textView.hasMarkedText() else {
            coordinator.scheduleHighlight(for: textView)
            return
        }
        coordinator.applyHighlightAttributes(to: textView)
    }

    public var selectedRange: Range<Int> {
        get { model.selectedRange }
        set {
            let clamped = GlassEditorNSCoordinator.clamped(
                NSRange(location: newValue.lowerBound, length: newValue.count),
                maximum: model.utf16Length
            )
            textView.setSelectedRange(clamped)
            model.selectedRange = clamped.lowerBound..<clamped.upperBound
        }
    }

    // MARK: - Undo / redo

    /// Reverses the newest undo unit and repaints. The one undo path — the text
    /// view has no undo manager of its own.
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

    /// Replaces every match as one undo unit and repaints.
    @discardableResult
    public func replaceAll(of query: FindQuery, with replacement: String) throws -> Int {
        let count = try model.replaceAll(of: query, with: replacement)
        if count > 0 { coordinator.syncTextViewFromModel(textView) }
        return count
    }

    /// Selects the next match, scrolling it into view.
    @discardableResult
    public func findNext(_ query: FindQuery, wrapping: Bool = true) throws -> Range<Int>? {
        guard let hit = try model.nextMatch(of: query, wrapping: wrapping) else { return nil }
        selectedRange = hit
        textView.scrollRangeToVisible(NSRange(location: hit.lowerBound, length: hit.count))
        return hit
    }
}

#endif
