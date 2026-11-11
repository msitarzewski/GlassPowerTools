#if os(macOS)
import AppKit
import Foundation
import Testing
import SwiftUI
import SwiftTerm
@testable import GlassTerminalEmulator

/// Moving along the command line as a Mac moves along text (2026-11-10: a request to edit "like Apple's terminal",
/// holding keys while using the arrows). Before, ⌥← / ⌥→, ⌥⌫ and ⌘⌫ sent nothing, ⌘← / ⌘→ moved a word, and ⌥-click
/// did nothing (SwiftTerm `PATCHES.md` S5). Driven through the real view in an offscreen window, as the app makes it.
/// The bytes are Apple's Terminal's, iTerm2's Natural Text Editing's and Ghostty's macOS defaults.
@MainActor
@Suite("Arrows and Delete with modifiers, and ⌥-click, on the Mac", .serialized)
struct MacTerminalArrowKeysTests {
    final class Sent { var bytes: [UInt8] = [] }

    private final class Host {
        let sent = Sent()
        let model = SwiftTermHostModel()
        let window = NSWindow()
        var view: TerminalView!
        private var nonce: UInt64 = 0

        init() async throws {
            let sent = sent
            let hosting = NSHostingView(rootView: SwiftTermHostView(
                model: model,
                theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1)),
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100),
                allowsFocusOwnership: false,
                onSendData: { data in sent.bytes += Array(data) },
                onResize: { _, _ in }
            ))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: 400))
            hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            await Task.yield()
            var views: [NSView] = [hosting]
            while !views.isEmpty {
                let next = views.removeFirst()
                if let terminal = next as? TerminalView { view = terminal; break }
                views += next.subviews
            }
            try #require(view != nil)
            window.makeFirstResponder(view)
        }

        func feed(_ text: String) async {
            nonce += 1
            model.ingest(data: Data(text.utf8), nonce: nonce)
            for _ in 0..<3_000 where model.pendingRendererByteCount != 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            sent.bytes.removeAll()
        }

        /// What one key sends: the arrows carry the numeric-pad and function flags, as the keyboard sends them.
        func press(_ code: UInt16, _ character: Character, _ flags: NSEvent.ModifierFlags = []) throws -> [UInt8] {
            let all = (123...126).contains(code) || code == 117 ? flags.union([.function]).union((123...126).contains(code) ? [.numericPad] : []) : flags
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: all, timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil,
                                                      characters: String(character), charactersIgnoringModifiers: String(character),
                                                      isARepeat: false, keyCode: code))
            sent.bytes.removeAll()
            view.keyDown(with: event)
            return sent.bytes
        }

        /// What a click on cell `col` of screen row `row` sends, with `flags` held.
        func click(col: Int, row: Int, _ flags: NSEvent.ModifierFlags) throws -> [UInt8] {
            let terminal = view.getTerminal()
            let size = view.getOptimalFrameSize().size
            let cell = CGSize(width: size.width / CGFloat(terminal.cols), height: size.height / CGFloat(terminal.rows))
            let local = NSPoint(x: (CGFloat(col) + 0.5) * cell.width, y: view.frame.height - (CGFloat(row) + 0.5) * cell.height)
            let point = view.convert(local, to: nil)
            sent.bytes.removeAll()
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                                                            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                            clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
            return sent.bytes
        }

        func close() {
            window.contentView = nil
            model.releaseRenderer()
        }
    }

    private static let left = Character(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private static let right = Character(UnicodeScalar(NSRightArrowFunctionKey)!)
    private static let forwardDelete = Character(UnicodeScalar(NSDeleteFunctionKey)!)
    private static func esc(_ text: String) -> [UInt8] { [0x1B] + Array(text.utf8) }

    @Test("⌥← / ⌥→ a word, ⌘← / ⌘→ the line's start and end, ⌥⌫ / ⌥⌦ a word, ⌘⌫ to the line's start")
    func editingKeys() async throws {
        let host = try await Host()
        defer { host.close() }
        #expect(try host.press(123, Self.left, .option) == Self.esc("b"))
        #expect(try host.press(124, Self.right, .option) == Self.esc("f"))
        #expect(try host.press(123, Self.left, .command) == [0x01])
        #expect(try host.press(124, Self.right, .command) == [0x05])
        #expect(try host.press(51, "\u{7F}", .option) == [0x1B, 0x7F])
        let forwardWord = try host.press(117, Self.forwardDelete, .option)
        #expect(forwardWord == Self.esc("d"), "sent \(forwardWord)")
        #expect(try host.press(51, "\u{7F}", .command) == [0x15])
    }

    @Test("the keys that already worked are unchanged")
    func unchanged() async throws {
        let host = try await Host()
        defer { host.close() }
        #expect(try host.press(123, Self.left) == Self.esc("[D"))
        #expect(try host.press(124, Self.right) == Self.esc("[C"))
        #expect(try host.press(123, Self.left, .control) == Self.esc("[1;5D"))
        #expect(try host.press(123, Self.left, .shift) == Self.esc("[1;2D"))
        #expect(try host.press(51, "\u{7F}") == [0x7F])
    }

    @Test("a program that asked for the kitty keyboard protocol: the arrows as above, ⌘⌫ encoded by the protocol")
    func kittyProtocol() async throws {
        let host = try await Host()
        defer { host.close() }
        await host.feed("\u{1B}[>1u")
        #expect(host.view.getTerminal().keyboardEnhancementFlags.contains(.disambiguate))
        #expect(try host.press(123, Self.left, .option) == Self.esc("b"), "as Ghostty does, whatever the protocol")
        #expect(try host.press(123, Self.left, .command) == [0x01])
        #expect(try host.press(51, "\u{7F}", .command) == Self.esc("[127;9u"), "super+Backspace, as the protocol has it")
    }

    @Test("⌥-click on the line being typed moves the cursor there; off it, or in a full-screen program, nothing")
    func optionClick() async throws {
        let host = try await Host()
        defer { host.close() }
        await host.feed("\u{1B}[2J\u{1B}[Hold line\r\nann$ hello world")
        #expect(try host.click(col: 11, row: 1, .option) == Array(repeating: Self.esc("[D"), count: 5).flatMap { $0 },
                "from after \"world\" back to its \"w\": five to the left")
        await host.feed("\u{1B}[4D")
        #expect(try host.click(col: 16, row: 1, .option) == Array(repeating: Self.esc("[C"), count: 4).flatMap { $0 },
                "and forward again")
        #expect(try host.click(col: 2, row: 0, .option).isEmpty, "a line above the one being typed")
        #expect(try host.click(col: 11, row: 1, []).isEmpty, "a plain click selects, as before")
        await host.feed("\u{1B}[?1049h")
        #expect(try host.click(col: 3, row: 3, .option).isEmpty, "a full-screen program has its own cursor")
    }
}
#endif
