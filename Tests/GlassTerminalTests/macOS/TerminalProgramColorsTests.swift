//
//  TerminalProgramColorsTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A program's own colours on a glass terminal (2026-11-24): GitHub Copilot's CLI sets GitHub Dark's background and
//  text as it starts (OSC 11, OSC 10) and asks for the terminal's own back as it quits (OSC 111, OSC 110). The
//  background stays as clear as the theme has it, and the reset puts the theme's colours back. The bytes are
//  Copilot's own (its script's `uMt`, `dMt` and `OSC_*_RESET`).
//

#if os(macOS)
import Foundation
import Testing
import SwiftUI
import AppKit
import SwiftTerm
@testable import GlassTerminalEmulator

@Suite("A program's colours on a glass terminal")
@MainActor
struct TerminalProgramColorsTests {
    /// A remote terminal's renderer in an offscreen window, on a glass theme: its background drawn by nothing
    /// (alpha 0), as every theme the app applies.
    @MainActor
    final class Hosted {
        let model = SwiftTermHostModel()
        private let window = NSWindow()
        private(set) var hosting: NSHostingView<SwiftTermHostView>?
        private var nonce: UInt64 = 0
        static let theme = SwiftTermTheme(fontSize: 13, foreground: (0.8, 0.8, 0.8), background: (0.1, 0.1, 0.1, 0),
                                          cursor: (1, 1, 1))

        init() async {
            let hosting = NSHostingView(rootView: SwiftTermHostView(
                model: model,
                theme: Self.theme,
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false,
                                                          scrollbackLines: 100),
                allowsFocusOwnership: false,
                onSendData: { _ in },
                onResize: { _, _ in }
            ))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: 600))
            hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            self.hosting = hosting
            await Task.yield()
        }

        func feed(_ text: String) async {
            nonce += 1
            model.ingest(data: Data(text.utf8), nonce: nonce)
            for _ in 0..<3_000 where model.pendingRendererByteCount != 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.pendingRendererByteCount == 0, "the terminal never read what it was fed")
        }

        var terminalView: TerminalView? {
            func find(_ view: NSView) -> TerminalView? {
                if let terminal = view as? TerminalView { return terminal }
                for child in view.subviews { if let found = find(child) { return found } }
                return nil
            }
            return hosting.flatMap(find)
        }

        func close() {
            window.contentView = nil
            hosting = nil
            model.releaseRenderer()
        }
    }

    /// sRGB parts, rounded to bytes, and the alpha.
    private func parts(_ color: NSColor?) -> [Int] {
        guard let color = color?.usingColorSpace(.sRGB) else { return [] }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    @Test("Copilot's GitHub Dark leaves the glass clear, and its reset gives the theme's colours back")
    func copilotPaintsAndResets() async throws {
        let host = await Hosted()
        defer { host.close() }
        await host.feed("$ ")
        let view = try #require(host.terminalView)
        #expect(parts(view.nativeBackgroundColor) == [26, 26, 26, 0], "the theme's, drawn by nothing")
        #expect(host.model.answeredColors == Hosted.theme.answeredColors, "noted for tmux to answer with")

        await host.feed("\u{1B}]11;#0D1117\u{07}\u{1B}]10;#F0F6FC\u{07}")
        #expect(parts(view.nativeBackgroundColor) == [0x0D, 0x11, 0x17, 0], "the program's colour, still clear")
        #expect(parts(view.nativeForegroundColor) == [0xF0, 0xF6, 0xFC, 255], "the program's text")

        await host.feed("\u{1B}]111;\u{07}\u{1B}]110;\u{07}")
        #expect(parts(view.nativeBackgroundColor) == [26, 26, 26, 0], "the theme's background back")
        #expect(parts(view.nativeForegroundColor) == [204, 204, 204, 255], "the theme's text back")
    }
}
#endif
