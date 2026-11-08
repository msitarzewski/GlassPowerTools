#if !os(macOS)
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// Type-ahead's chips (D102, 2026-11-06) on iPhone, iPad and Vision Pro. Drawn with SwiftUI's own renderer (a
/// package's test process has no window scene to draw a window in), which doesn't draw Liquid Glass: these check
/// sizes and when the chips are there; the look is checked in the app (`--demo-open terminal-typeahead`). The picture
/// is written to `GPT_TYPEAHEAD_CHIPS_PNG` when that is set.
@MainActor
@Suite("Type-ahead: the chips")
struct TypeAheadChipsTests {
    /// `view` as drawn at a phone's width, or nil when it draws nothing.
    private func render(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390))
        renderer.scale = 2
        guard let image = renderer.uiImage, image.size.height >= 1 else { return nil }
        return image
    }

    @Test("the commands offered: one row of chips")
    func chips() throws {
        let model = SwiftTermHostModel()
        model.setTypeAhead(nil, choices: ["git status", "git stash list", "git switch main"])
        let image = try #require(render(TerminalTypeAheadChips(model: model)), "drew nothing with three commands to offer")
        #expect(image.size.height >= 24 && image.size.height <= 60, "one row: \(image.size)")
        if let path = ProcessInfo.processInfo.environment["GPT_TYPEAHEAD_CHIPS_PNG"] {
            try image.pngData()?.write(to: URL(fileURLWithPath: path))
        }
    }

    #if os(iOS)
    /// The owner's choice (2026-11-06): above the keyboard's bar, like QuickType, never over the terminal's text.
    @Test("iPhone and iPad: the row stands while the keyboard is up and type-ahead is on, one height with or without chips")
    func row() {
        let model = SwiftTermHostModel()
        model.keyboardAccessoryMoved(shown: true)
        #expect(render(TerminalTypeAheadChipRow(model: model)) == nil, "type-ahead off: no row")
        model.offersTypeAheadChips = true
        model.keyboardAccessoryMoved(shown: false)
        #expect(render(TerminalTypeAheadChipRow(model: model)) == nil, "keyboard down: no row over the output")
        model.keyboardAccessoryMoved(shown: true)
        #expect(render(TerminalTypeAheadChipRow(model: model))?.size.height == TerminalTypeAheadChipRow.height,
                "nothing offered: the row stands, so the terminal keeps its size")
        model.setTypeAhead(nil, choices: ["ls -la"])
        #expect(render(TerminalTypeAheadChipRow(model: model))?.size.height == TerminalTypeAheadChipRow.height)
    }
    #endif
}
#endif
