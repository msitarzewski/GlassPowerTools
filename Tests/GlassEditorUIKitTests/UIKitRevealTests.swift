#if canImport(UIKit) && !os(macOS)

import Testing
import Foundation
import UIKit
@testable import GlassEditorUI
import GlassEditorCore

/// The find bar and Go to Line select through the model, and the text view never followed it
/// (2026-10-22: Return in the find bar selected nothing on screen). Run on the iOS simulator, in a
/// phone-sized window, so a match far down the file has somewhere to scroll to.
@Suite("UIKit backend: revealing a selection")
@MainActor
struct UIKitRevealTests {
    private let content = (1...400).map { "line \($0)" }.joined(separator: "\n") + "\nneedle\n"

    private func makeEngine() -> (GlassEditorUIKitEngine, UIWindow) {
        let model = GlassEditorModel(snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
                                     configuration: GlassEditorConfiguration())
        let engine = GlassEditorUIKitEngine(model: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        engine.containerView.frame = window.bounds
        window.addSubview(engine.containerView)
        window.isHidden = false
        engine.containerView.layoutIfNeeded()
        engine.textView.layoutIfNeeded()
        return (engine, window)
    }

    private func settle(_ turns: Int = 40) async {
        for _ in 0..<turns { await Task.yield() }
    }

    @Test("a match revealed through the model is selected and scrolled to")
    func revealSelectsAndScrolls() async {
        let (engine, window) = makeEngine()
        let top = engine.textView.contentOffset.y
        let needle = (content as NSString).range(of: "needle")
        engine.model.reveal(needle.location..<NSMaxRange(needle))
        await settle()
        #expect(engine.textView.selectedRange == needle)
        // Measured: the match is about 6,700 points down, and the top of the file is at -62.
        #expect(engine.textView.contentOffset.y > top + 1000, "scrolled to the match: \(engine.textView.contentOffset.y)")
        _ = window
    }

    @Test("a caret revealed through the model, as Go to Line places it, is scrolled to")
    func revealACaret() async {
        let (engine, window) = makeEngine()
        let top = engine.textView.contentOffset.y
        let line = (content as NSString).range(of: "line 350").location
        engine.model.reveal(line..<line)
        await settle()
        #expect(engine.textView.selectedRange == NSRange(location: line, length: 0))
        #expect(engine.textView.contentOffset.y > top + 1000, "scrolled to the line: \(engine.textView.contentOffset.y)")
        _ = window
    }
}

#endif
