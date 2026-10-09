#if os(macOS)
import AppKit
import Foundation
import Testing
import SwiftUI
import SwiftTerm
@testable import GlassTerminalEmulator

/// The terminal's contextual menu on the Mac (owner, 2026-10-09: "we don't have any contextual
/// menus in terminal. Copy/Paste/Paste Text/Services"). Driven through the real remote terminal
/// view in an offscreen window, so the menu tested is the one a right-click gets.
@MainActor
@Suite("The terminal's contextual menu on the Mac")
struct MacTerminalContextMenuTests {
    private typealias HostedTerminal = TerminalFindTests.HostedTerminal

    private func terminalView(_ host: HostedTerminal) throws -> TerminalView {
        var views: [NSView] = host.hosting.map { [$0] } ?? []
        while !views.isEmpty {
            let view = views.removeFirst()
            if let terminal = view as? TerminalView { return terminal }
            views += view.subviews
        }
        throw CancellationError()
    }

    /// A right-click `x` points into row `row` of the screen.
    private func rightClick(_ view: TerminalView, x: CGFloat = 2, row: Int = 0) throws -> NSEvent {
        let cellHeight = view.getOptimalFrameSize().height / CGFloat(view.getTerminal().rows)
        let local = NSPoint(x: x, y: view.bounds.height - (CGFloat(row) + 0.5) * cellHeight)
        return try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: view.convert(local, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    private func item(_ menu: NSMenu, _ title: String) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title })
    }

    @Test("a right-click on a word selects it; Look Up, Copy, Paste and Select All follow")
    func rightClickOnAWord() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view)), "a right-click has a menu")
        #expect(titles(menu) == ["Look Up “hello”", "—", "Copy", "Paste", "Select All"])
        #expect(view.selection.active && view.selection.getSelectedText() == "hello",
                "the word under the pointer, as a Mac text view selects it")
        #expect(try item(menu, "Copy").isEnabled)
        #expect(try item(menu, "Select All").isEnabled)
        #expect(try item(menu, "Look Up “hello”").isEnabled)
    }

    @Test("a right-click inside the selection keeps it")
    func rightClickInsideSelection() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        view.selectAll(nil)
        let selected = view.selection.getSelectedText()

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(view.selection.getSelectedText() == selected, "not narrowed to the word")
        #expect(titles(menu).first == "Look Up “hello world”")
    }

    @Test("a right-click on blank space selects nothing: no Look Up, and nothing to copy")
    func rightClickOnBlankSpace() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view, row: 5)))
        #expect(!view.selection.active)
        #expect(titles(menu) == ["Copy", "Paste", "Select All"])
        #expect(try !item(menu, "Copy").isEnabled)
    }

    @Test("Services get the selection as text, and are never asked to write into the terminal")
    func servicesGetTheSelection() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        #expect(view.validRequestor(forSendType: .string, returnType: nil) == nil, "nothing selected, nothing offered")

        _ = view.menu(for: try rightClick(view))
        #expect(view.validRequestor(forSendType: .string, returnType: nil) as? NSView === view)
        #expect(view.validRequestor(forSendType: .string, returnType: .string) == nil,
                "a service that returns text would write over the program's screen")

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTerminalContextMenuTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let requestor = try #require(view as? NSServicesMenuRequestor)
        #expect(requestor.writeSelection?(to: pasteboard, types: [.string]) == true)
        #expect(pasteboard.string(forType: .string) == "hello")
    }

    @Test("Look Up's title: the first line, trimmed, shortened past 30 characters")
    func lookUpTitle() {
        #expect(MacTerminalContextMenu.lookUpPhrase("  from 192.0.2.10  ") == "from 192.0.2.10")
        #expect(MacTerminalContextMenu.lookUpPhrase("first line\nsecond") == "first line")
        #expect(MacTerminalContextMenu.lookUpPhrase(String(repeating: "a", count: 40)) == String(repeating: "a", count: 30) + "…")
        #expect(MacTerminalContextMenu.lookUpPhrase(" \n ") == nil)
    }
}
#endif
