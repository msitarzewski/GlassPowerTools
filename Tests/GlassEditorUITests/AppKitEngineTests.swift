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
        configuration: GlassEditorConfiguration = GlassEditorConfiguration(),
        _ system: GlassTextView.TextSystem = .textKit1
    ) -> GlassEditorAppKitEngine {
        let model = GlassEditorModel(
            snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
            configuration: configuration
        )
        return GlassEditorAppKitEngine(model: model, textSystem: system)
    }

    /// The height of one line of this engine's text, from its own text system.
    private func lineHeight(of engine: GlassEditorAppKitEngine) -> CGFloat? {
        if let layoutManager = engine.textView.textLayoutManager {
            var height: CGFloat = 0
            layoutManager.enumerateTextLayoutFragments(
                from: layoutManager.textContentManager?.documentRange.location,
                options: [.ensuresLayout, .ensuresExtraLineFragment]
            ) { fragment in
                height = fragment.textLineFragments.first?.typographicBounds.height ?? 0
                return false
            }
            return height
        }
        guard let layoutManager = engine.textView.layoutManager, layoutManager.numberOfGlyphs > 0 else { return nil }
        return layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    }

    /// What the gutter draws, on whichever system the engine was built with.
    private func gutterLabels(_ engine: GlassEditorAppKitEngine,
                              _ band: ClosedRange<CGFloat>? = nil) -> [GutterLineNumbers.Label] {
        GlassLineNumberGutter.labels(for: engine.textView, model: engine.model, verticalRange: band)
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
        if let layoutManager = engine.textView.textLayoutManager, let content = layoutManager.textContentManager {
            layoutManager.ensureLayout(for: content.documentRange)
        } else if engine.textView.textSystem == .textKit1, let container = engine.textView.textContainer {
            engine.textView.layoutManager?.ensureLayout(for: container)
        }
    }

    // MARK: - Text system

    /// D36: the Mac editor is TextKit 1 with non-contiguous layout, and an edit must not lose it.
    @Test("the Mac text view is on TextKit 1 with non-contiguous layout, and stays there")
    func textKit1IsTheMacDefault() throws {
        let engine = makeEngine("SELECT 1")
        #expect(engine.textView.textSystem == .textKit1)
        #expect(engine.textView.layoutManager?.allowsNonContiguousLayout == true)
        #expect(engine.textView.glassTextStorage?.string == "SELECT 1")
        try engine.apply(TextEdit.insert(" FROM t", at: 8))
        #expect(engine.textView.layoutManager?.allowsNonContiguousLayout == true)
        #expect(engine.textView.glassTextStorage?.string == "SELECT 1 FROM t")
    }

    @Test("a TextKit 2 text view, when asked for, is on TextKit 2 and stays there")
    func textKit2IsActive() {
        let engine = makeEngine("SELECT 1", .textKit2)
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
        let storage = engine.textView.glassTextStorage
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

    /// **A number has to sit beside its line, not merely exist.**
    ///
    /// Reported 2026-09-20 with a screenshot: one line of text and a caret on the empty line
    /// below it, and the gutter reading 1 … 2 with the 2 a whole line too low. Asked for
    /// `.ensuresExtraLineFragment`, TextKit 2 lays the final empty line out *inside* the last
    /// paragraph's fragment — `"…\n"` is one fragment, two line fragments, 32 points tall — so
    /// the trailing number was placed at the fragment's bottom rather than at the empty line.
    @Test("the trailing empty line's number sits on that line, not below the fragment", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func gutterPlacesTheTrailingNumberOnItsOwnLine(_ system: GlassTextView.TextSystem) throws {
        let engine = makeEngine("Moving to a new place, open to pretty much anything.\n", system)
        layOut(engine, width: 600)
        let labels = gutterLabels(engine)

        #expect(labels.map(\.number) == [1, 2])
        let first = try #require(labels.first)
        let second = try #require(labels.last)
        // The line's own height, taken from the layout rather than assumed: the height of one
        // line of this document's text, from the text system that laid it out.
        let lineHeight = try #require(lineHeight(of: engine))
        #expect(lineHeight > 0)
        #expect(second.frame.minY == first.frame.minY + lineHeight,
                "the second number belongs one line down, where the caret is — not one line below that")
    }

    @Test("the gutter numbers 100 logical lines 1...100", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func gutterNumbersHundredLines(_ system: GlassTextView.TextSystem) {
        let content = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let engine = makeEngine(content, system)
        layOut(engine, width: 600)

        let labels = gutterLabels(engine)

        #expect(labels.count == 100)
        #expect(labels.map(\.number) == Array(1...100))
        // Numbers march down the page.
        #expect(zip(labels, labels.dropFirst()).allSatisfy { $0.frame.minY <= $1.frame.minY })
    }

    @Test("soft wraps do not increment the line number", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func softWrapsDoNotIncrement(_ system: GlassTextView.TextSystem) {
        // Three logical lines, the middle one long enough to wrap several times
        // in a narrow container.
        let long = String(repeating: "wrap ", count: 80)
        let engine = makeEngine("first\n\(long)\nlast", system)
        layOut(engine, width: 120)

        let labels = gutterLabels(engine)

        #expect(labels.map(\.number) == [1, 2, 3])
        // The wrapped line really did wrap — otherwise this proves nothing: line 3 starts more
        // than two rows below line 2.
        #expect(labels[2].frame.minY - labels[1].frame.minY > (labels[0].frame.height) * 2)
    }

    @Test("inserting a line early shifts every number below it", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func numbersShiftAfterAnEdit(_ system: GlassTextView.TextSystem) throws {
        let engine = makeEngine("alpha\nbeta\ngamma", system)
        layOut(engine, width: 600)

        func numbers() -> [Int] {
            gutterLabels(engine).map(\.number)
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

    @Test("a trailing terminator produces a final empty numbered line", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func trailingTerminatorGetsALine(_ system: GlassTextView.TextSystem) {
        let engine = makeEngine("one\ntwo\n", system)
        layOut(engine, width: 600)
        let labels = gutterLabels(engine)
        // `TextStorageBuffer` counts three lines for "one\ntwo\n"; the gutter
        // agrees, which is the property that matters — the two must not disagree
        // about what a line is.
        #expect(engine.model.lineCount == 3)
        #expect(labels.map(\.number) == [1, 2, 3])
    }

    @Test("an empty document still gets a line 1", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func emptyDocumentHasOneLine(_ system: GlassTextView.TextSystem) {
        let engine = makeEngine("", system)
        layOut(engine, width: 600)
        let labels = gutterLabels(engine)
        #expect(engine.model.lineCount == 1)
        #expect(labels.map(\.number) == [1])
    }

    @Test("a document that is nothing but terminators numbers every empty line", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func onlyTerminators(_ system: GlassTextView.TextSystem) {
        let engine = makeEngine("\n\n\n", system)
        layOut(engine, width: 600)
        let labels = gutterLabels(engine)
        #expect(engine.model.lineCount == 4)
        #expect(labels.map(\.number) == [1, 2, 3, 4])
    }

    @Test("clipping to a visible band returns only the lines in it", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func verticalRangeClipsLabels(_ system: GlassTextView.TextSystem) {
        let engine = makeEngine((1...100).map { "line \($0)" }.joined(separator: "\n"), system)
        layOut(engine, width: 600)
        let all = gutterLabels(engine)
        guard all.count > 1, case let lineHeight = all[1].frame.minY - all[0].frame.minY, lineHeight > 0 else {
            Issue.record("no laid-out lines")
            return
        }

        // A band starting part-way down the document.
        let band = (lineHeight * 10)...(lineHeight * 14)
        let clipped = gutterLabels(engine, band)

        #expect(clipped.count < all.count)
        #expect(clipped.isEmpty == false)
        #expect(clipped.first!.number > 1)
        #expect(clipped.last!.number < 100)
        // Contiguous, and a subsequence of the full list.
        #expect(clipped.map(\.number) == Array(clipped.first!.number...clipped.last!.number))
    }

    @Test("a clipped band that stops early does not invent a trailing line", arguments: [GlassTextView.TextSystem.textKit1, .textKit2])
    func clippedBandDoesNotSynthesiseTrailingLine(_ system: GlassTextView.TextSystem) {
        let engine = makeEngine((1...50).map { "line \($0)" }.joined(separator: "\n") + "\n", system)
        layOut(engine, width: 600)
        let all = gutterLabels(engine)
        // The trailing empty line is line 51 and is synthesised, since TextKit 2
        // emits no fragment for it.
        #expect(engine.model.lineCount == 51)
        #expect(all.map(\.number) == Array(1...51))

        guard all.count > 1, case let lineHeight = all[1].frame.minY - all[0].frame.minY, lineHeight > 0 else {
            Issue.record("no laid-out lines")
            return
        }
        let topBand = 0...(lineHeight * 3)
        let clipped = gutterLabels(engine, topBand)
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

    /// **In a window, the number sits beside its line.** Reported 2026-09-29 from the database's
    /// SQL pane: the query on line 1 and the "1" a line below it. Hosted in a real window the
    /// text view's frame sits above its clip view, offset by the clip view's scroll, and the
    /// gutter summed offsets that assumed the frame started at zero: 50 points against the
    /// text's 12 here, before the fix. Both the editor's own settings and the SQL pane's
    /// (horizontally resizable, with a horizontal scroller) are checked.
    @Test("in a window, line 1's number is level with line 1", arguments: [false, true])
    func gutterNumberIsLevelWithItsLineInAWindow(sqlPaneSettings: Bool) throws {
        let engine = makeEngine("SELECT name FROM items LIMIT 10;")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 140),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let content = try #require(window.contentView)
        engine.containerView.frame = content.bounds
        content.addSubview(engine.containerView)
        if sqlPaneSettings {
            engine.scrollView.hasHorizontalScroller = true
            engine.textView.isHorizontallyResizable = true
        }
        engine.containerView.layoutSubtreeIfNeeded()
        let layoutManager = try #require(engine.textView.layoutManager)
        layoutManager.ensureLayout(for: try #require(engine.textView.textContainer))
        let gutter = try #require(engine.gutter)

        let label = try #require(gutterLabels(engine).first)
        let drawnY = label.frame.minY - gutter.verticalOffset(textView: engine.textView)
        var line = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        line.origin.y += engine.textView.textContainerOrigin.y
        let lineY = gutter.convert(line, from: engine.textView).minY
        #expect(abs(drawnY - lineY) < 0.5, "drawn at \(drawnY), the line is at \(lineY)")
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

        let storage = engine.textView.glassTextStorage
        let keyword = storage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let plain = storage?.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
        #expect(keyword != nil)
        #expect(keyword != plain)
    }

    @Test("a surface change re-resolves colors and the canvas without touching the text")
    func surfaceChangeReResolves() async {
        let engine = makeEngine("SELECT 1")
        engine.setHighlightRuns([HighlightRun(range: 0..<6, role: .keyword)])

        let storage = engine.textView.glassTextStorage
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
