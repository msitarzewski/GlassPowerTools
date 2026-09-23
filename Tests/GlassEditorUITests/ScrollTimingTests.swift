import Testing
import Foundation
import AppKit
@testable import GlassEditorUI
import GlassEditorCore

/// Frame cost of scrolling the Mac editor, offscreen (2026-09-23: *"why scrolling isn't smooth"*).
/// Runs only when `GPT_SCROLL_TIMING` is set; prints per-frame times for a large one-line file
/// (`GPT_LARGE_FILE`, wrapped) and an ordinary 5,000-line source file.
@Suite("Scrolling cost")
@MainActor
struct ScrollTimingTests {
    private func measure(_ name: String, text: String, language: LanguageID, wraps: Bool) {
        var configuration = GlassEditorConfiguration()
        configuration.wrapsLines = wraps
        let snapshot = DocumentSnapshot(content: text, encoding: .utf8(hadBOM: false), lineEndings: .lf,
                                        origin: .ephemeral(id: UUID()))
        let model = GlassEditorModel(snapshot: snapshot, configuration: configuration, language: language)
        let engine = GlassEditorAppKitEngine(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = engine.containerView
        engine.containerView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        engine.containerView.layoutSubtreeIfNeeded()
        engine.containerView.displayIfNeeded()
        let clip = engine.scrollView.contentView
        var frames: [Double] = []
        let clock = ContinuousClock()
        let steps = Int(ProcessInfo.processInfo.environment["GPT_SCROLL_STEPS"] ?? "") ?? 120
        for step in 1...steps {
            let start = clock.now
            clip.scroll(to: NSPoint(x: 0, y: Double(step) * 40))   // 40 pt a frame, a brisk trackpad scroll
            engine.scrollView.reflectScrolledClipView(clip)
            engine.containerView.layoutSubtreeIfNeeded()
            engine.containerView.displayIfNeeded()
            let elapsed = clock.now - start
            frames.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        let slow = frames.enumerated().filter { $0.element > 16.7 }.map { "\($0.offset)" }
        print("SLOW-FRAMES \(name): \(slow.joined(separator: ","))")
        let sorted = frames.sorted()
        let over = frames.filter { $0 > 16.7 }.count
        print(String(format: "SCROLL %@: median %.1f ms, p95 %.1f ms, max %.1f ms, frames over 16.7 ms: %d/%d",
                     name, sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last!, over, sorted.count))
        window.close()
    }

    @Test func frames() throws {
        guard ProcessInfo.processInfo.environment["GPT_SCROLL_TIMING"] != nil else { return }
        var source = ""
        for i in 0..<5_000 { source += "func f\(i)(x: Int) -> Int { let y = x * \(i) // step \(i)\n  return y + \(i) }\n" }
        let only = ProcessInfo.processInfo.environment["GPT_SCROLL_CASE"]
        if only == nil || only == "unwrapped" { measure("swift 10k lines, unwrapped", text: source, language: .swift, wraps: false) }
        if only == nil || only == "wrapped" { measure("swift 10k lines, wrapped", text: source, language: .swift, wraps: true) }
        if only == nil || only == "large", let path = ProcessInfo.processInfo.environment["GPT_LARGE_FILE"],
           let big = try? String(contentsOfFile: path, encoding: .utf8) {
            measure("14.6 MB one-line SVG, wrapped", text: big, language: .xml, wraps: true)
        }
    }
}
