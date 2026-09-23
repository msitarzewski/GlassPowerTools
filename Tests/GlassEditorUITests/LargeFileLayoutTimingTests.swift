import Testing
import Foundation
import AppKit
@testable import GlassEditorUI
import GlassEditorCore

/// How long the Mac's text view takes to lay out and draw a huge one-line file, offscreen
/// (2026-09-23). Runs only when `GPT_LARGE_FILE` names a file; prints each stage.
@Suite("Laying out a very large one-line file")
@MainActor
struct LargeFileLayoutTimingTests {
    @Test(arguments: [false, true])
    func stages(wraps: Bool) throws {
        guard let path = ProcessInfo.processInfo.environment["GPT_LARGE_FILE"] else { return }
        let clock = ContinuousClock()
        var t = clock.now
        func lap(_ name: String) { let now = clock.now; print("LAYOUT wraps=\(wraps) \(name): \(now - t)"); t = now }
        let text = try String(contentsOfFile: path, encoding: .utf8); lap("read")
        var configuration = GlassEditorConfiguration()
        configuration.wrapsLines = wraps
        let snapshot = DocumentSnapshot(content: text, encoding: .utf8(hadBOM: false), lineEndings: .lf,
                                        origin: .local(URL(filePath: path)))
        let model = GlassEditorModel(snapshot: snapshot, configuration: configuration, language: .xml); lap("model")
        let engine = GlassEditorAppKitEngine(model: model); lap("engine")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = engine.containerView
        engine.containerView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        engine.containerView.layoutSubtreeIfNeeded(); lap("layout")
        engine.containerView.displayIfNeeded(); lap("first draw")
        engine.containerView.frame = NSRect(x: 0, y: 0, width: 450, height: 700)
        engine.containerView.layoutSubtreeIfNeeded()
        engine.containerView.displayIfNeeded(); lap("resize to half and draw")
        window.close()
    }
}
