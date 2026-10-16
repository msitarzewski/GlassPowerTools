//
//  TerminalScaleTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D75 (the owner, 2026-10-16): a terminal that scales as well as resizes — "I may want a 120 x 40
//  terminal, but with a much smaller window." Under Scale the window's size changes the text's,
//  never the rows and columns, and the host never hears of a size it isn't keeping.
//

import Foundation
import Testing
import SwiftUI
@testable import GlassTerminalEmulator
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("A terminal that scales")
@MainActor
struct TerminalScaleTests {
    // MARK: Where the drawing goes

    @Test("the grid's frame has room for every column, whatever a cell's width")
    func contentSize() {
        let size = SwiftTermScaleLayout.contentSize(cell: CGSize(width: 7.2, height: 16), columns: 120, rows: 40,
                                                    reservedWidth: 15)
        #expect(Int((size.width - 15) / 7.2) == 120)
        #expect(Int(size.height / 16) == 40)
        #expect(size.width - 15 - 7.2 * 120 < 1, "less than a column over")
    }

    @Test("the drawing fills the narrower side, centred on the other")
    func fit() throws {
        let wide = try #require(SwiftTermScaleLayout.fit(CGSize(width: 1000, height: 500), in: CGSize(width: 500, height: 500)))
        #expect(wide.scale == 0.5)
        #expect(wide.origin == CGPoint(x: 0, y: 125))
        let tall = try #require(SwiftTermScaleLayout.fit(CGSize(width: 400, height: 800), in: CGSize(width: 600, height: 400)))
        #expect(tall.scale == 0.5)
        #expect(tall.origin == CGPoint(x: 200, y: 0))
        let grown = try #require(SwiftTermScaleLayout.fit(CGSize(width: 100, height: 50), in: CGSize(width: 300, height: 150)))
        #expect(grown.scale == 3)
        #expect(SwiftTermScaleLayout.fit(.zero, in: CGSize(width: 10, height: 10)) == nil)
    }

    @Test("⌘+ and ⌘− size the window around the text by a step; ⌘0 to the font's own size")
    func zoomedWindow() throws {
        // A pane 800 × 600 under 40 points of the window's own, drawing 1600 × 1200 at half size.
        let window = CGSize(width: 800, height: 640), space = CGSize(width: 800, height: 600)
        let content = CGSize(width: 1600, height: 1200)
        #expect(SwiftTermScaleLayout.zoomedWindow(window: window, space: space, content: content, factor: 1.1)
                == CGSize(width: 880, height: 700), "a tenth larger, the window's own 40 points kept")
        #expect(SwiftTermScaleLayout.zoomedWindow(window: window, space: space, content: content, factor: nil)
                == CGSize(width: 1600, height: 1240), "the text at its font's own size")
        #expect(SwiftTermScaleLayout.zoomedWindow(window: window, space: space, content: content, factor: 100) == nil,
                "nothing so far from now that it can't be meant")
    }

    // MARK: A terminal in a window

    #if os(macOS)
    /// A remote terminal's renderer in an offscreen window, with what it tells the host recorded.
    final class Hosted {
        let model = SwiftTermHostModel()
        let window = NSWindow()
        private(set) var hosting: NSHostingView<SwiftTermHostView>?
        private(set) var told: [String] = []

        init() async {
            let hosting = NSHostingView(rootView: view(fontSize: 13))
            window.isReleasedWhenClosed = false
            hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window.contentView = hosting
            window.setContentSize(NSSize(width: 800, height: 600))
            hosting.layoutSubtreeIfNeeded()
            self.hosting = hosting
            await settle()
        }

        func view(fontSize: CGFloat) -> SwiftTermHostView {
            SwiftTermHostView(
                model: model,
                theme: SwiftTermTheme(fontSize: fontSize, foreground: (1, 1, 1), background: (0, 0, 0, 1),
                                      cursor: (1, 1, 1)),
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false,
                                                          scrollbackLines: 100),
                allowsFocusOwnership: false,
                onSendData: { _ in },
                onResize: { [weak self] columns, rows in self?.told.append("\(columns)x\(rows)") }
            )
        }

        var grid: String? { model.rendererGrid.map { "\($0.columns)x\($0.rows)" } }

        func resize(to size: NSSize) async {
            window.setContentSize(size)
            hosting?.frame = NSRect(origin: .zero, size: size)
            hosting?.layoutSubtreeIfNeeded()
            await settle()
        }

        func setFontSize(_ size: CGFloat) async {
            hosting?.rootView = view(fontSize: size)
            hosting?.layoutSubtreeIfNeeded()
            await settle()
        }

        /// The terminal's own view: its layer is what draws the text.
        var terminalView: NSView? {
            func find(_ view: NSView) -> NSView? {
                if String(describing: type(of: view)).contains("ReviewingMacTerminalView") { return view }
                for child in view.subviews { if let found = find(child) { return found } }
                return nil
            }
            return hosting.flatMap(find)
        }

        func settle() async {
            for _ in 0..<5 { await Task.yield() }
            try? await Task.sleep(for: .milliseconds(30))
        }

        func close() {
            window.contentView = nil
            hosting = nil
            model.releaseRenderer()
        }
    }

    @Test("under Scale a smaller window keeps the grid and makes the text smaller")
    func smallerWindowKeepsTheGrid() async throws {
        let host = await Hosted()
        defer { host.close() }
        let opened = try #require(host.grid)
        #expect(host.told.last == opened, "Resize: the host has the window's grid")

        host.model.setScaling(true)
        await host.settle()
        let kept = try #require(host.model.scaledGrid)
        #expect("\(kept.columns)x\(kept.rows)" == opened, "Scale keeps the grid the terminal had")
        let toldBefore = host.told

        await host.resize(to: NSSize(width: 400, height: 300))
        #expect(host.grid == opened, "half the window, the same rows and columns")
        #expect(host.told == toldBefore, "the host heard nothing")
        let terminal = try #require(host.terminalView)
        #expect(terminal.frame.size == kept.size, "the terminal keeps its grid's frame at its font")
        let shown = terminal.convert(terminal.bounds, to: nil).size
        let scale = min(400 / kept.size.width, 300 / kept.size.height)
        #expect(abs(shown.width - kept.size.width * scale) < 1, "drawn at the window's size")
        let backing = host.window.backingScaleFactor
        #expect(abs((terminal.layer?.contentsScale ?? 0) - backing * scale) < 0.01,
                "AppKit draws its text for the pixels it covers, not large and shrunk as a picture")
    }

    @Test("a font change under Scale keeps the grid, and the host never hears another")
    func fontChangeKeepsTheGrid() async throws {
        let host = await Hosted()
        defer { host.close() }
        let opened = try #require(host.grid)
        host.model.setScaling(true)
        await host.settle()
        let before = try #require(host.model.scaledGrid)
        let toldBefore = host.told

        await host.setFontSize(20)
        #expect(host.grid == opened)
        let after = try #require(host.model.scaledGrid)
        #expect(after.columns == before.columns && after.rows == before.rows)
        #expect(after.size.width > before.size.width, "the same grid at a larger font is larger before it is scaled")
        let heard = Array(host.told.dropFirst(toldBefore.count))
        #expect(heard.allSatisfy { $0 == opened }, "the host heard only the kept grid: \(heard)")
    }

    @Test("⌘− under Scale makes the window smaller, not the grid; ⌘0 brings the text to its font's size")
    func zoomUnderScale() async throws {
        let host = await Hosted()
        defer { host.close() }
        let opened = try #require(host.grid)
        #expect(!host.model.zoomScaledWindow(by: 0.5), "under Resize the font's size is the font's")
        host.model.setScaling(true)
        await host.settle()
        let kept = try #require(host.model.scaledGrid)
        let before = try #require(host.window.contentView?.frame.size)

        #expect(host.model.zoomScaledWindow(by: 0.5))
        await host.settle()
        let smaller = try #require(host.window.contentView?.frame.size)
        #expect(abs(smaller.width - before.width / 2) < 2 && abs(smaller.height - before.height / 2) < 2,
                "half the window: \(before) → \(smaller)")
        #expect(host.grid == opened, "the same rows and columns")

        #expect(host.model.zoomScaledWindow(by: nil))
        await host.settle()
        let actual = try #require(host.window.contentView?.frame.size)
        #expect(abs(actual.width - kept.size.width) < 2 && abs(actual.height - kept.size.height) < 2,
                "the window the grid's size at its font: \(actual) for \(kept.size)")
        #expect(host.grid == opened)
    }

    @Test("back to Resize, the window sets the grid again")
    func backToResize() async throws {
        let host = await Hosted()
        defer { host.close() }
        let opened = try #require(host.grid)
        host.model.setScaling(true)
        await host.settle()
        await host.resize(to: NSSize(width: 400, height: 300))
        #expect(host.grid == opened)

        host.model.setScaling(false)
        await host.settle()
        #expect(host.model.scaledGrid == nil)
        let resized = try #require(host.grid)
        #expect(resized != opened, "a smaller window, fewer rows and columns")
        #expect(host.told.last == resized, "the host has the new grid")
        let terminal = try #require(host.terminalView)
        #expect(terminal.convert(terminal.bounds, to: nil).size == terminal.frame.size, "unscaled")
        #expect(terminal.layer?.contentsScale == host.window.backingScaleFactor)
    }
    #endif
}
