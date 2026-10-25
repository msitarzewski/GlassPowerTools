import Testing
import Foundation
import AppKit

/// A bare AppKit text view, none of our code, scrolled offscreen: TextKit 1 with non-contiguous
/// layout, the fast editors' setup, against TextKit 2 (2026-09-23, text engine research). Runs only
/// when `GPT_LARGE_FILE` names a file.
@Suite("TextKit 1 against TextKit 2 on a huge one-line file")
@MainActor
struct TextKitComparisonTests {
    private func run(_ name: String, textKit1: Bool, wraps: Bool, text: String) {
        let clock = ContinuousClock()
        let start = clock.now
        let textView = textKit1 ? NSTextView(usingTextLayoutManager: false) : NSTextView(usingTextLayoutManager: true)
        if textKit1 { textView.layoutManager?.allowsNonContiguousLayout = true }
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = wraps
        textView.textContainer?.size = NSSize(width: wraps ? 880 : 100_000, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: wraps ? 880 : 100_000, height: 700)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        textView.string = text
        scroll.layoutSubtreeIfNeeded()
        scroll.displayIfNeeded()
        let opened = clock.now - start
        var frames: [Double] = []
        for step in 1...200 {
            let t = clock.now
            scroll.contentView.scroll(to: NSPoint(x: 0, y: Double(step) * 40))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.layoutSubtreeIfNeeded()
            scroll.displayIfNeeded()
            let d = clock.now - t
            frames.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        let sorted = frames.sorted()
        print(String(format: "TK %@: open+layout %.2f s, scroll median %.1f ms, p95 %.1f ms, over 16.7 ms: %d/200",
                     name, Double(opened.components.seconds) + Double(opened.components.attoseconds) / 1e18,
                     sorted[100], sorted[190], frames.filter { $0 > 16.7 }.count))
        window.close()
    }

    /// A measurement of the system's text systems, printed, not a check: set GPT_LARGE_FILE.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPT_LARGE_FILE"] != nil, "a timing probe: set GPT_LARGE_FILE"))
    func compare() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GPT_LARGE_FILE"])
        let text = try String(contentsOfFile: path, encoding: .utf8)
        run("1 non-contiguous, wrapped", textKit1: true, wraps: true, text: text)
        run("2, wrapped", textKit1: false, wraps: true, text: text)
        run("1 non-contiguous, unwrapped", textKit1: true, wraps: false, text: text)
    }
}
