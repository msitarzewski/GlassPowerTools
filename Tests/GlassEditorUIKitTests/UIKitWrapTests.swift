#if canImport(UIKit) && !os(macOS)

import Testing
import Foundation
import UIKit
@testable import GlassEditorUI
import GlassEditorCore

/// Wrap Long Lines off on an iPhone (the owner, 2026-10-12: "disabling line wrap seems to be
/// ignored on iphone", with a package.json whose description wrapped onto five lines). Run on the
/// iOS simulator: a phone-wide window, laid out as UIKit lays it out, and the first paragraph's
/// lines counted from the text system itself.
@Suite("UIKit backend: long lines")
@MainActor
struct UIKitWrapTests {
    private let phone = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let longLine = String(repeating: "word ", count: 80) + "end"

    private func makeEngine(_ content: String, wraps: Bool) -> (GlassEditorUIKitEngine, UIWindow) {
        var configuration = GlassEditorConfiguration()
        configuration.wrapsLines = wraps
        let model = GlassEditorModel(
            snapshot: DocumentLoader.make(content: content, origin: .ephemeral(id: UUID())),
            configuration: configuration
        )
        let engine = GlassEditorUIKitEngine(model: model)
        let window = UIWindow(frame: phone)
        engine.containerView.frame = window.bounds
        window.addSubview(engine.containerView)
        window.isHidden = false
        layOut(engine)
        return (engine, window)
    }

    private func layOut(_ engine: GlassEditorUIKitEngine) {
        engine.containerView.setNeedsLayout()
        engine.containerView.layoutIfNeeded()
        engine.textView.setNeedsLayout()
        engine.textView.layoutIfNeeded()
    }

    /// The lines the first paragraph is laid out on.
    private func linesOfFirstParagraph(_ engine: GlassEditorUIKitEngine) -> Int {
        guard let layoutManager = engine.textView.textLayoutManager else { return -1 }
        var lines = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location,
                                                   options: [.ensuresLayout]) { fragment in
            lines = fragment.textLineFragments.count
            return false
        }
        return lines
    }

    private func settle(_ turns: Int = 40) async {
        for _ in 0..<turns { await Task.yield() }
    }

    @Test("wrap off: a long line stays one line, and the view scrolls sideways to it")
    func wrapOff() {
        let (engine, window) = makeEngine(longLine + "\nshort\n", wraps: false)
        defer { window.isHidden = true }
        #expect(linesOfFirstParagraph(engine) == 1)
        #expect(engine.textView.contentSize.width > phone.width, "content \(engine.textView.contentSize.width)")
        #expect(engine.textView.contentSize.width < 20_000, "as wide as the line, not the unbounded container")
        engine.textView.setContentOffset(CGPoint(x: engine.textView.contentSize.width - phone.width, y: 0), animated: false)
        #expect(engine.textView.contentOffset.x > 0, "and it scrolls there")
    }

    @Test("wrap on: the same line wraps to the phone's width, and nothing scrolls sideways")
    func wrapOn() {
        let (engine, window) = makeEngine(longLine + "\nshort\n", wraps: true)
        defer { window.isHidden = true }
        #expect(linesOfFirstParagraph(engine) > 1)
        #expect(engine.textView.contentSize.width <= phone.width + 0.5)
    }

    @Test("turned back on: the line wraps again and nothing is left to scroll sideways")
    func turnedBackOn() async {
        let (engine, window) = makeEngine(longLine + "\nshort\n", wraps: false)
        defer { window.isHidden = true }
        var configuration = engine.model.configuration
        configuration.wrapsLines = true
        engine.model.configuration = configuration
        await settle()
        layOut(engine)
        #expect(linesOfFirstParagraph(engine) > 1)
        #expect(engine.textView.contentSize.width <= phone.width + 0.5)
    }

    @Test("a rotation or a resize leaves an unwrapped line unwrapped")
    func resized() {
        let (engine, window) = makeEngine(longLine + "\nshort\n", wraps: false)
        defer { window.isHidden = true }
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        engine.containerView.frame = window.bounds
        layOut(engine)
        #expect(linesOfFirstParagraph(engine) == 1)
        #expect(engine.textView.contentSize.width > 844)
    }

    @Test("turned off while the file is open, as Settings and the gear do: the line unwraps")
    func turnedOffWhileOpen() async {
        let (engine, window) = makeEngine(longLine + "\nshort\n", wraps: true)
        defer { window.isHidden = true }
        #expect(linesOfFirstParagraph(engine) > 1)
        var configuration = engine.model.configuration
        configuration.wrapsLines = false
        engine.model.configuration = configuration
        await settle()
        layOut(engine)
        #expect(linesOfFirstParagraph(engine) == 1)
        #expect(engine.textView.contentSize.width > phone.width)
    }
}

#endif
