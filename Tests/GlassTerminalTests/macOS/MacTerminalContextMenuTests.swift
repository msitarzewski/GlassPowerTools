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

    /// The owner (2026-10-11): "Looks like we broke copy" — right-click ▸ Copy. Output arriving
    /// while the menu is open can clear the view's selection before Copy is chosen.
    @Test("Copy copies what was selected when the menu opened, even if the selection is gone by the time it is chosen")
    func copyUsesTheSelectionTheMenuShowed() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTerminalContextMenuTests.copy.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let general = MacTerminalContextMenu.copyPasteboard
        MacTerminalContextMenu.copyPasteboard = pasteboard
        defer { MacTerminalContextMenu.copyPasteboard = general }

        let menu = try #require(view.menu(for: try rightClick(view)))
        // A redraw while the menu is open takes the selection away.
        view.selection.selectNone()
        let copy = try #require(menu.items.firstIndex { $0.title == "Copy" })
        menu.performActionForItem(at: copy)
        #expect(pasteboard.string(forType: .string) == "hello")
    }

    @Test("choosing Select All selects the terminal's text")
    func selectAllIsChosen() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view, row: 5)))
        let selectAll = try #require(menu.items.firstIndex { $0.title == "Select All" })
        menu.performActionForItem(at: selectAll)
        #expect(view.selection.active)
        #expect(view.selection.getSelectedText().contains("hello world"))
    }

    /// The owner (2026-10-11): "I can't drag select past the current screen buffer so I can't copy
    /// all of the output." In tmux the terminal holds only the screen; Select All takes tmux's history.
    @Test("Select All over a program that keeps its own history takes all of it; Copy copies it; a click lets it go")
    func selectAllTakesTheProgramsHistory() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        host.model.onFullHistory = { "line 1\nline 2\nthe screen" }
        await host.feed("\u{1B}[?1049hthe screen")
        let view = try terminalView(host)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTerminalContextMenuTests.history.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let general = MacTerminalContextMenu.copyPasteboard
        MacTerminalContextMenu.copyPasteboard = pasteboard
        defer { MacTerminalContextMenu.copyPasteboard = general }

        // ⌘A, as the key reaches the view.
        view.window?.makeFirstResponder(view)
        let commandA = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                     windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                                     characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        #expect(view.performKeyEquivalent(with: commandA))
        #expect(view.selection.active, "the screen is highlighted")
        for _ in 0..<50 where MacTerminalContextMenu.selectedText(of: view) != "line 1\nline 2\nthe screen" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(MacTerminalContextMenu.selectedText(of: view) == "line 1\nline 2\nthe screen")
        view.copy(view)
        #expect(pasteboard.string(forType: .string) == "line 1\nline 2\nthe screen", "⌘C copies the history")

        let menu = try #require(view.menu(for: try rightClick(view)))
        pasteboard.clearContents()
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Copy" }))
        #expect(pasteboard.string(forType: .string) == "line 1\nline 2\nthe screen", "and so does the menu's Copy")

        let click = try rightClick(view)
        view.mouseDown(with: try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: click.locationInWindow, modifierFlags: [],
                                                             timestamp: 0, windowNumber: click.windowNumber, context: nil,
                                                             eventNumber: 0, clickCount: 1, pressure: 1)))
        #expect(MacTerminalContextMenu.selectedText(of: view) != "line 1\nline 2\nthe screen", "a click starts over")
    }

    @Test("on the main screen, which keeps its own scrollback, Select All selects the terminal's text alone")
    func selectAllOnTheMainScreen() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        nonisolated(unsafe) var asked = false
        host.model.onFullHistory = { asked = true; return "not this" }
        await host.feed("hello world\r\n")
        let view = try terminalView(host)
        MacTerminalContextMenu.selectAll(in: view)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!asked)
        #expect(MacTerminalContextMenu.selectedText(of: view)?.contains("hello world") == true)
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

    // MARK: A link under the pointer (2026-10-14)

    /// The owner: "detect a local path to a log … and offer a right click > watch log file".
    @Test("a right-click on a path offers Watch Log File and Copy Path; Watch hands the host the path")
    func rightClickOnAPath() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        var watched: [String] = []
        host.model.onWatchFile = { watched.append($0) }
        await host.feed("/var/log/glass-test.log:42 rotated\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(Array(titles(menu).prefix(3)) == ["Watch Log File", "Copy Path", "—"])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Watch Log File" }))
        #expect(watched == ["/var/log/glass-test.log"], "the file, without the line the log named")
    }

    /// The owner (2026-10-14): "open a path with a context menu".
    @Test("a path offers Open in Editor and its host's Show in Finder or Files, which hand the host the path")
    func openAndRevealAPath() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        var opened: [String] = [], revealed: [String] = []
        host.model.onOpenPath = { opened.append($0) }
        host.model.onRevealPath = { revealed.append($0) }
        host.model.revealPathTitle = "Show in Finder"
        host.model.onWatchFile = { _ in }
        await host.feed("/var/log/glass-test.log:42 rotated\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(Array(titles(menu).prefix(5)) == ["Open in Editor", "Show in Finder", "Watch Log File", "Copy Path", "—"])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Open in Editor" }))
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Show in Finder" }))
        #expect(opened == ["/var/log/glass-test.log"] && revealed == ["/var/log/glass-test.log"])
    }

    /// The owner (2026-10-16): Quick Look on a path's menu, its file over the terminal.
    @Test("a path offers Quick Look first, where the window can preview, and choosing it asks for that path's file")
    func quickLookAPath() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        var asked: [String] = []
        host.model.previewFile = { path in
            asked.append(path)
            return nil
        }
        host.model.previewContent = { _ in AnyView(EmptyView()) }
        host.model.onOpenPath = { _ in }
        await host.feed("/var/log/glass-test.log:42 rotated\r\n")
        let view = try terminalView(host)

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(Array(titles(menu).prefix(2)) == ["Quick Look", "Open in Editor"])
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Quick Look" }))
        for _ in 0..<50 where asked.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(asked == ["/var/log/glass-test.log"], "the file, without the line the log named")
    }

    @Test("a window that can't preview offers no Quick Look; an address never does")
    func noQuickLookWithoutAPreview() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        host.model.onOpenPath = { _ in }
        await host.feed("/var/log/glass-test.log rotated\r\nhttps://example.com/docs\r\n")
        let view = try terminalView(host)
        #expect(!titles(try #require(view.menu(for: try rightClick(view)))).contains("Quick Look"))

        host.model.previewFile = { _ in nil }
        host.model.previewContent = { _ in AnyView(EmptyView()) }
        #expect(titles(try #require(view.menu(for: try rightClick(view)))).first == "Quick Look")
        #expect(!titles(try #require(view.menu(for: try rightClick(view, row: 1)))).contains("Quick Look"))
    }

    /// Mouseover + Space (2026-10-16): Space alone, never held or with a modifier, and never a repeat.
    @Test("only a plain Space press is the preview's")
    func plainSpace() throws {
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags = [], repeated: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                          windowNumber: 0, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: repeated, keyCode: 49))
        }
        #expect(MacTerminalPathPreviewer.isPlainSpace(try key(" ")))
        #expect(!MacTerminalPathPreviewer.isPlainSpace(try key(" ", .shift)))
        #expect(!MacTerminalPathPreviewer.isPlainSpace(try key(" ", .control)))
        #expect(!MacTerminalPathPreviewer.isPlainSpace(try key(" ", repeated: true)))
        #expect(!MacTerminalPathPreviewer.isPlainSpace(try key("a")))
    }

    @Test("with no host that can watch, a path offers Copy Path alone, and it copies the path")
    func pathWithoutAWatcher() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("/var/log/glass-test.log rotated\r\n")
        let view = try terminalView(host)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTerminalContextMenuTests.path.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let general = MacTerminalContextMenu.copyPasteboard
        MacTerminalContextMenu.copyPasteboard = pasteboard
        defer { MacTerminalContextMenu.copyPasteboard = general }

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(!titles(menu).contains("Watch Log File"))
        #expect(titles(menu).first == "Copy Path")
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Copy Path" }))
        #expect(pasteboard.string(forType: .string) == "/var/log/glass-test.log")
    }

    @Test("a right-click on an address offers Open Link, which asks first as a ⌘-click does, and Copy Link")
    func rightClickOnAnAddress() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("https://example.com/docs is up\r\n")
        let view = try terminalView(host)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacTerminalContextMenuTests.link.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let general = MacTerminalContextMenu.copyPasteboard
        MacTerminalContextMenu.copyPasteboard = pasteboard
        defer { MacTerminalContextMenu.copyPasteboard = general }

        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(Array(titles(menu).prefix(3)) == ["Open Link", "Copy Link", "—"])
        #expect(try item(menu, "Open Link").isEnabled)
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Copy Link" }))
        #expect(pasteboard.string(forType: .string) == "https://example.com/docs")
        menu.performActionForItem(at: try #require(menu.items.firstIndex { $0.title == "Open Link" }))
        #expect(host.model.pendingExternalLink != nil, "the same question a ⌘-click asks")
    }

    @Test("a bare domain, which SwiftTerm's rules leave alone, is found by Apple's detector")
    func bareDomain() async throws {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed("example.com is up\r\n")
        let view = try terminalView(host)
        let menu = try #require(view.menu(for: try rightClick(view)))
        #expect(titles(menu).first == "Open Link")
    }
}
#endif
