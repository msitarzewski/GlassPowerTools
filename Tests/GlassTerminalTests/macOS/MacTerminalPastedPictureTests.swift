#if os(macOS)
import AppKit
import Foundation
import SwiftTerm
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// A picture pasted on a Mac terminal goes where a dropped one goes (2026-11-06: "No surprises for users (like not
/// being able to paste an image into the terminal)"). Every pasteboard here is the test's own: the person's
/// clipboard is never read or changed.
@MainActor
@Suite("Mac terminal: a picture pasted", .serialized)
struct MacTerminalPastedPictureTests {
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("gpt-paste-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private func picture() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image
    }

    private func pngData() throws -> Data {
        let tiff = try #require(picture().tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @Test("a picture alone is taken, as PNG; text or a file beside it, or nothing, and the paste is typed as before")
    func whatIsTaken() throws {
        let png = board()
        png.setData(try pngData(), forType: .png)
        let taken = try #require(MacTerminalPastedPicture.providers(on: png), "a screenshot on the clipboard")
        #expect(taken.first?.registeredTypeIdentifiers == [UTType.png.identifier])

        // Preview and Photos copy TIFF, which Claude Code doesn't read: redrawn as PNG.
        let tiff = board()
        tiff.setData(try #require(picture().tiffRepresentation), forType: .tiff)
        #expect(MacTerminalPastedPicture.providers(on: tiff) != nil)
        #expect(MacTerminalPastedPicture.pngData(on: tiff).map { Array($0.prefix(8)) } == Self.pngSignature)

        // Excel, Numbers and Word copy a picture of the cells with their text: the text is what's pasted.
        let cells = board()
        cells.declareTypes([.string, .png], owner: nil)
        cells.setString("a\tb\n1\t2", forType: .string)
        cells.setData(try pngData(), forType: .png)
        #expect(MacTerminalPastedPicture.providers(on: cells) == nil, "the cells' text, not their picture")

        // A file copied in the Finder (its URL, its name and its icon): pasted as before.
        let finder = board()
        finder.writeObjects([URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app") as NSURL])
        finder.setData(try #require(picture().tiffRepresentation), forType: .tiff)
        #expect(MacTerminalPastedPicture.providers(on: finder) == nil, "a copied file isn't its icon")

        #expect(MacTerminalPastedPicture.providers(on: board()) == nil)
    }

    @Test("⌘V in a local terminal with a picture: written to the drop folder and its path typed at the prompt")
    func localPaste() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("paste-picture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("PROMPT='%% '\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        let settings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 1_000)
        let theme = SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1), cursor: (1, 1, 1))
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/zsh", arguments: ["-l"],
            environment: ["HOME=\(home.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color", "LANG=en_US.UTF-8",
                          "USER=\(NSUserName())", "SHELL=/bin/zsh"],
            currentDirectory: home.path)
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        runtime.start(configuration: configuration, theme: theme, runtimeSettings: settings)
        let hosting = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1400, height: 400))
        hosting.frame = NSRect(x: 0, y: 0, width: 1400, height: 400)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        let model = runtime.model
        let screen = { model.getVisibleText(lastNLines: 4).joined(separator: "\n") }
        #expect(await waitFor(seconds: 20) { screen().contains("%") }, "no prompt: \(screen())")

        let pictureBoard = board()
        pictureBoard.setData(try pngData(), forType: .png)
        // As the pane sets it (`MacLocalTerminalPaneView`), with the test's pasteboard for the person's.
        model.pasteFiles = { [weak model] in
            guard let model else { return false }
            return MacTerminalPastedPicture.paste(into: model, pasteboard: pictureBoard)
        }
        let terminalView = try #require(firstTerminalView(in: hosting), "the terminal's view")
        terminalView.paste(terminalView)

        #expect(await waitFor(seconds: 10) { screen().contains(".png") }, "no path typed: \(screen())")
        let typed = screen()
        let path = try #require(typed.split(separator: " ").first { $0.hasSuffix(".png") }.map(String.init), "typed: \(typed)")
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent()) }
        #expect(path.contains("/com.glasspowertools/Dropped/"), "the drop folder: \(path)")
        let written = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(Array(written.prefix(8)) == Self.pngSignature, "a PNG")
        // Typed, never run: still on the prompt's line, nothing from zsh after it.
        try await Task.sleep(for: .milliseconds(500))
        let lastLine = model.getVisibleText(lastNLines: 4).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(lastLine?.hasPrefix("% ") == true && lastLine?.contains(path) == true, "run, or not at the prompt: \(screen())")
    }

    private func firstTerminalView(in view: NSView) -> TerminalView? {
        if let terminal = view as? TerminalView { return terminal }
        for subview in view.subviews { if let found = firstTerminalView(in: subview) { return found } }
        return nil
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
#endif
