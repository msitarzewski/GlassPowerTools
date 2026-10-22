import AppKit
import SwiftUI
import Testing
@testable import GlassLayers
@testable import GlassTerminal
@testable import GlassTerminalEmulator

@MainActor
@Suite("The Coding Agent look, drawn")
struct TerminalAgentBackdropRenderTests {
    @Test("the agent's mark is drawn in the middle, in its colour")
    func markIsDrawn() throws {
        let view = TerminalAgentBackdrop(agent: .claudeCode, color: Color(red: 0.85, green: 0.47, blue: 0.34),
                                         working: false, still: true, frameInterval: 1.0 / 30, intensity: 1)
            .frame(width: 400, height: 300)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        var brightest = 0.0
        for x in stride(from: 120, to: 280, by: 4) {
            for y in stride(from: 80, to: 220, by: 4) {
                let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                brightest = max(brightest, c.redComponent)
            }
        }
        #expect(brightest > 0.12, "the middle is dark: \(brightest)")
    }

    @Test("in a window's backdrop, scrim and ceiling included, the mark still shows")
    func markInTheBackdrop() throws {
        let style = TerminalLookStyle.resolved(TerminalLookPreset.agent.applied(to: GlassWindowOverrides()))
        let view = TerminalBackdropView(style: style, theme: .default, findAgent: { .claudeCode })
            .frame(width: 400, height: 300)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        var brightest = 0.0
        for x in stride(from: 120, to: 280, by: 4) {
            for y in stride(from: 80, to: 220, by: 4) {
                let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                brightest = max(brightest, c.redComponent)
            }
        }
        #expect(brightest > 0.2, "the middle is too dark to see the mark: \(brightest)")
    }
}
