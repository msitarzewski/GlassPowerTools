#if canImport(AppKit) && os(macOS)

import Testing
import Foundation
import AppKit
@testable import GlassEditorUI
import GlassEditorCore

/// These run headlessly: an `NSTextView` on a TextKit 2 stack lays text out
/// without ever being in a window, which is exactly why the gutter's fragment
/// enumeration is testable in CI rather than only on a device.
@Suite("AppKit backend")
@MainActor
struct AppKitEngineTests {

    private func makeEngine(
        _ content: String,
        configuration: GlassEditorConfiguration = GlassEditorConfiguration()
    ) -> GlassEditorAppKitEngine {
        let model = GlassEditorModel(
            snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
            configuration: configuration
        )
        return GlassEditorAppKitEngine(model: model)
    }

    /// The engine applies theme/surface/configuration changes by observing the
    /// model, which delivers on a later main-actor turn (updates coalesce rather
    /// than repainting synchronously inside the setter). Drain a bounded number
    /// of turns so a stuck engine fails the assertion instead of hanging.
    private func settle(_ turns: Int = 40) async {
        for _ in 0..<turns { await Task.yield() }
    }

    /// Forces layout without a window by giving the container a finite width and
    /// asking the layout manager to lay out the whole document.
    private func layOut(_ engine: GlassEditorAppKitEngine, width: CGFloat) {
        engine.textView.frame = NSRect(x: 0, y: 0, width: width, height: 4000)
        engine.textView.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        engine.textView.textContainer?.widthTracksTextView = false
        guard let layoutManager = engine.textView.textLayoutManager,
              let content = layoutManager.textContentManager else { return }
        layoutManager.ensureLayout(for: content.documentRange)
    }

    // MARK: - TextKit 2

    @Test("the text view is on TextKit 2 and stays there")
    func textKit2IsActive() {
        let engine = makeEngine("SELECT 1")
        #expect(engine.textView.textLayoutManager != nil)
        #expect(engine.textView.isUsingTextKit2)
        #expect(engine.textView.contentStorage != nil)

        // A programmatic edit is the path most likely to trip a TextKit 1
        // downgrade, because it touches storage.
        try? engine.apply(TextEdit.insert(" FROM t", at: 8))
        #expect(engine.textView.textLayoutManager != nil)
    }

    @Test("the text view draws no background of its own and has no undo manager")
    func canvasAndUndoOwnership() {
        let engine = makeEngine("x")
        #expect(engine.textView.drawsBackground == false)
        #expect(engine.scrollView.drawsBackground == false)
        // One undo authority: `UndoCoordinator`.
        #expect(engine.textView.allowsUndo == false)
        #expect(engine.textView.undoManager == nil)
    }

    @Test("code-editing defaults are set on both platforms' behalf")
    func codeEditingDefaults() {
        let engine = makeEngine("x")
        let textView = engine.textView
        #expect(textView.isRichText == false)
        #expect(textView.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(textView.isAutomaticDashSubstitutionEnabled == false)
        #expect(textView.isAutomaticSpellingCorrectionEnabled == false)
        #expect(textView.isContinuousSpellCheckingEnabled == false)
    }

    // MARK: - Editing

    @Test("apply updates the text view and records undo")
    func applyUpdatesViewAndUndo() throws {
        let engine = makeEngine("SELECT")
        try engine.apply(TextEdit.insert(" 1", at: 6), intent: .typing)

        #expect(engine.text == "SELECT 1")
        #expect(engine.textView.string == "SELECT 1")
        #expect(engine.canUndo)

        #expect(engine.undo())
        #expect(engine.text == "SELECT")
        #expect(engine.textView.string == "SELECT")

        #expect(engine.redo())
        #expect(engine.textView.string == "SELECT 1")
    }

    @Test("a user edit routed through the delegate reaches the model exactly once")
    func delegateForwardsUserEdits() {
        let engine = makeEngine("abc")
        let coordinator = engine.coordinator

        let allowed = coordinator.textView(
            engine.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "d"
        )
        #expect(allowed)
        #expect(coordinator.forwardedEditCount == 1)
        #expect(engine.model.text == "abcd")
        #expect(engine.model.newestUndoIntent == .typing)
    }

    @Test("a delete with no replacement is recorded as a backspace")
    func deleteIntentInference() {
        let engine = makeEngine("abc")
        _ = engine.coordinator.textView(
            engine.textView,
            shouldChangeTextIn: NSRange(location: 2, length: 1),
            replacementString: ""
        )
        #expect(engine.model.newestUndoIntent == .deleteBackward)
    }

    @Test("a paste action tags its edit as a paste, so it never joins a typing run")
    func pasteIntentIsTagged() {
        let engine = makeEngine("abc")
        engine.textView.pendingIntent = .paste
        _ = engine.coordinator.textView(
            engine.textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "def"
        )
        #expect(engine.model.newestUndoIntent == .paste)
        // And it is consumed, not sticky.
        #expect(engine.textView.pendingIntent == nil)
    }

    // MARK: - Re-entrancy

    @Test("programmatic attribute application does not feed back into the model")
    func reentrancyGuardBlocksFeedback() {
        let engine = makeEngine("SELECT 1 FROM t")
        engine.model.setHighlights([HighlightRun(range: 0..<6, role: .keyword)])
        let coordinator = engine.coordinator

        let editsBefore = coordinator.forwardedEditCount
        let revisionBefore = engine.model.revision

        coordinator.applyHighlightAttributes(to: engine.textView)

        // Attributes moved; the document did not.
        #expect(engine.model.revision == revisionBefore)
        #expect(coordinator.forwardedEditCount == editsBefore)
        #expect(engine.model.text == "SELECT 1 FROM t")

        // And a delegate callback arriving *during* an application is ignored —
        // this is the guard doing its job, not an accident of ordering.
        coordinator.withHighlightApplication {
            coordinator.textDidChange(
                Notification(name: NSText.didChangeNotification, object: engine.textView)
            )
            _ = coordinator.textView(
                engine.textView,
                shouldChangeTextIn: NSRange(location: 0, length: 6),
                replacementString: "XXXXXX"
            )
        }
        #expect(coordinator.forwardedEditCount == editsBefore)
        #expect(engine.model.text == "SELECT 1 FROM t")
    }

    @Test("typing attributes survive a highlight pass, with the font refreshed")
    func typingAttributesPreserved() {
        let engine = makeEngine("SELECT 1")
        engine.model.setHighlights([HighlightRun(range: 0..<6, role: .keyword)])

        // A marker attribute the engine has no reason to touch.
        let marker = NSAttributedString.Key("GlassEditorTestMarker")
        engine.textView.typingAttributes[marker] = "kept"

        engine.coordinator.applyHighlightAttributes(to: engine.textView)

        #expect(engine.textView.typingAttributes[marker] as? String == "kept")
        let font = engine.textView.typingAttributes[.font] as? NSFont
        #expect(font?.pointSize == CGFloat(engine.configuration.fontSize))
    }

    @Test("a font-size change forces a pass even though the text is unchanged")
    func fontSizeChangeForcesPass() async {
        let engine = makeEngine("SELECT 1")
        let before = engine.coordinator.highlightPassCount

        var configuration = engine.configuration
        configuration.fontSize = 22
        engine.configuration = configuration
        await settle()

        #expect(engine.coordinator.highlightPassCount > before)
        #expect(engine.textView.appliedFontSize == 22)
        let storage = engine.textView.contentStorage?.textStorage
        let font = storage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 22)
    }

    @Test("selection is clamped to the UTF-16 length")
    func selectionClamping() {
        let engine = makeEngine("abcde")
        engine.selectedRange = 3..<99
        #expect(engine.selectedRange == 3..<5)
        engine.selectedRange = 99..<120
        #expect(engine.selectedRange == 5..<5)
    }

    // MARK: - Gutter

    @Test("the gutter numbers 100 logical lines 1...100")
    func gutterNumbersHundredLines() {
        let content = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let engine = makeEngine(content)
        layOut(engine, width: 600)

        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let labels = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }

        #expect(labels.count == 100)
        #expect(labels.map(\.number) == Array(1...100))
        // Numbers march down the page.
        #expect(zip(labels, labels.dropFirst()).allSatisfy { $0.frame.minY <= $1.frame.minY })
    }

    @Test("soft wraps do not increment the line number")
    func softWrapsDoNotIncrement() {
        // Three logical lines, the middle one long enough to wrap several times
        // in a narrow container.
        let long = String(repeating: "wrap ", count: 80)
        let engine = makeEngine("first\n\(long)\nlast")
        layOut(engine, width: 120)

        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let labels = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }

        #expect(labels.map(\.number) == [1, 2, 3])
        // The wrapped line really did wrap — otherwise this proves nothing.
        let wrapped = labels[1]
        #expect(wrapped.frame.height > labels[0].frame.height * 2)
    }

    @Test("inserting a line early shifts every number below it")
    func numbersShiftAfterAnEdit() throws {
        let engine = makeEngine("alpha\nbeta\ngamma")
        layOut(engine, width: 600)

        func numbers() -> [Int] {
            guard let layoutManager = engine.textView.textLayoutManager else { return [] }
            return GutterLineNumbers.labels(
                in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
            ) { engine.model.lineIndex(forUTF16Offset: $0) }.map(\.number)
        }
        #expect(numbers() == [1, 2, 3])

        try engine.apply(TextEdit.insert("zero\n", at: 0), intent: .paste)
        layOut(engine, width: 600)
        #expect(engine.text == "zero\nalpha\nbeta\ngamma")
        #expect(numbers() == [1, 2, 3, 4])

        #expect(engine.undo())
        layOut(engine, width: 600)
        #expect(numbers() == [1, 2, 3])
    }

    @Test("a trailing terminator produces a final empty numbered line")
    func trailingTerminatorGetsALine() {
        let engine = makeEngine("one\ntwo\n")
        layOut(engine, width: 600)
        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let labels = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        // `TextStorageBuffer` counts three lines for "one\ntwo\n"; the gutter
        // agrees, which is the property that matters — the two must not disagree
        // about what a line is.
        #expect(engine.model.lineCount == 3)
        #expect(labels.map(\.number) == [1, 2, 3])
    }

    @Test("an empty document still gets a line 1")
    func emptyDocumentHasOneLine() {
        let engine = makeEngine("")
        layOut(engine, width: 600)
        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let labels = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        #expect(engine.model.lineCount == 1)
        #expect(labels.map(\.number) == [1])
    }

    @Test("a document that is nothing but terminators numbers every empty line")
    func onlyTerminators() {
        let engine = makeEngine("\n\n\n")
        layOut(engine, width: 600)
        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let labels = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        #expect(engine.model.lineCount == 4)
        #expect(labels.map(\.number) == [1, 2, 3, 4])
    }

    @Test("clipping to a visible band returns only the lines in it")
    func verticalRangeClipsLabels() {
        let engine = makeEngine((1...100).map { "line \($0)" }.joined(separator: "\n"))
        layOut(engine, width: 600)
        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let all = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        guard let lineHeight = all.first?.frame.height, lineHeight > 0 else {
            Issue.record("no laid-out lines")
            return
        }

        // A band starting part-way down the document.
        let band = (lineHeight * 10)...(lineHeight * 14)
        let clipped = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: band, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }

        #expect(clipped.count < all.count)
        #expect(clipped.isEmpty == false)
        #expect(clipped.first!.number > 1)
        #expect(clipped.last!.number < 100)
        // Contiguous, and a subsequence of the full list.
        #expect(clipped.map(\.number) == Array(clipped.first!.number...clipped.last!.number))
    }

    @Test("a clipped band that stops early does not invent a trailing line")
    func clippedBandDoesNotSynthesiseTrailingLine() {
        let engine = makeEngine((1...50).map { "line \($0)" }.joined(separator: "\n") + "\n")
        layOut(engine, width: 600)
        guard let layoutManager = engine.textView.textLayoutManager else {
            Issue.record("no TextKit 2 layout manager")
            return
        }
        let all = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: nil, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        // The trailing empty line is line 51 and is synthesised, since TextKit 2
        // emits no fragment for it.
        #expect(engine.model.lineCount == 51)
        #expect(all.map(\.number) == Array(1...51))

        guard let lineHeight = all.first?.frame.height, lineHeight > 0 else {
            Issue.record("no laid-out lines")
            return
        }
        let topBand = 0...(lineHeight * 3)
        let clipped = GutterLineNumbers.labels(
            in: layoutManager, verticalRange: topBand, lineCount: engine.model.lineCount
        ) { engine.model.lineIndex(forUTF16Offset: $0) }
        // Enumeration stopped well before the end, so line 51 must not be
        // appended beneath line 4.
        #expect(clipped.contains { $0.number == 51 } == false)
        #expect(clipped.last!.number < 10)
    }

    /// The shape, not the numbers: a gutter that is a *sibling* of the scroll
    /// view can only occupy what the container gives it, where an `NSRulerView`
    /// spans its whole scroll view and is not inset by the scroll view's content
    /// insets — which is how the strip of numbers reached the title bar.
    @Test("the gutter is a view beside the text, not a ruler spanning the scroll view")
    func gutterIsBesideTheText() throws {
        let engine = makeEngine("x")
        let gutter = try #require(engine.gutter)

        #expect(engine.scrollView.verticalRulerView == nil)
        #expect(engine.scrollView.rulersVisible == false)
        #expect(gutter.superview === engine.containerView)
        #expect(engine.scrollView.superview === engine.containerView)

        engine.containerView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        engine.containerView.layoutSubtreeIfNeeded()

        // Vertically the scroll view's band exactly, horizontally the leading
        // 44 points, and the text starts where the gutter ends.
        #expect(gutter.frame.minY == engine.scrollView.frame.minY)
        #expect(gutter.frame.maxY == engine.scrollView.frame.maxY)
        #expect(gutter.frame.minX == 0)
        #expect(gutter.frame.width == EditorMetrics.gutterWidth)
        #expect(engine.scrollView.frame.minX == EditorMetrics.gutterWidth)
    }

    @Test("turning line numbers off collapses the gutter instead of tearing it down")
    func gutterVisibility() async {
        var configuration = GlassEditorConfiguration()
        configuration.showsLineNumbers = false
        let engine = makeEngine("x", configuration: configuration)
        engine.containerView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        engine.containerView.layoutSubtreeIfNeeded()
        #expect(engine.gutter?.isHidden == true)
        #expect(engine.gutter?.frame.width == 0)

        configuration.showsLineNumbers = true
        engine.configuration = configuration
        await settle()
        engine.containerView.layoutSubtreeIfNeeded()
        #expect(engine.gutter?.isHidden == false)
        #expect(engine.gutter?.frame.width == EditorMetrics.gutterWidth)
        // The shipped metric: gutter + container inset == 56.
        #expect(EditorMetrics.gutteredLeadingInset == 56)
    }

    // MARK: - Highlighting and surface

    @Test("setHighlightRuns paints the runs into the view's storage")
    func setHighlightRunsPaints() {
        let engine = makeEngine("SELECT 1")
        engine.setHighlightRuns([HighlightRun(range: 0..<6, role: .keyword)])

        let storage = engine.textView.contentStorage?.textStorage
        let keyword = storage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let plain = storage?.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
        #expect(keyword != nil)
        #expect(keyword != plain)
    }

    @Test("a surface change re-resolves colors and the canvas without touching the text")
    func surfaceChangeReResolves() async {
        let engine = makeEngine("SELECT 1")
        engine.setHighlightRuns([HighlightRun(range: 0..<6, role: .keyword)])

        let storage = engine.textView.contentStorage?.textStorage
        let before = storage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let canvasBefore = engine.textView.canvasColor

        engine.surfaceCondition = SurfaceCondition(
            windowOpacity: 0.2, backing: .material(.ultraThin), ambient: .unknown
        )
        await settle()

        let after = storage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(after != before)
        #expect(engine.textView.canvasColor != canvasBefore)
        #expect(engine.textView.canvasColor.alphaComponent == 0.2)
        #expect(engine.text == "SELECT 1")
    }

    @Test("replace-all through the engine is one undo unit and repaints the view")
    func engineReplaceAll() throws {
        let engine = makeEngine("cat cat cat")
        let count = try engine.replaceAll(
            of: FindQuery(pattern: "cat", kind: .literal, caseSensitive: true), with: "dog"
        )
        #expect(count == 3)
        #expect(engine.textView.string == "dog dog dog")
        #expect(engine.undo())
        #expect(engine.textView.string == "cat cat cat")
    }

    @Test("findNext selects the match")
    func engineFindNext() throws {
        let engine = makeEngine("alpha beta alpha")
        let hit = try engine.findNext(
            FindQuery(pattern: "alpha", kind: .literal, caseSensitive: true)
        )
        #expect(hit == 0..<5)
        #expect(engine.selectedRange == 0..<5)
    }
}

#endif
