import Foundation
import Testing
@testable import GlassTerminal

/// What the terminal gives Shortcuts, Siri and the Finder (D72, 2026-10-13).
@Suite("The terminal's system integration")
struct GlassTerminalSystemIntegrationTests {
    @Test("a folder opens a terminal in itself; a file, in the folder that holds it")
    func folderOfAFileOrFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("glass-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.md")
        try Data("x".utf8).write(to: file)

        let expected = folder.standardizedFileURL.path(percentEncoded: false)
        #expect(GlassTerminalRuntime.folderPath(for: folder) == expected)
        #expect(GlassTerminalRuntime.folderPath(for: file).hasPrefix(expected.hasSuffix("/") ? String(expected.dropLast()) : expected))
        #expect(!GlassTerminalRuntime.folderPath(for: file).hasSuffix("notes.md"))
        // A path with a space, as the Finder hands one over, is a path — not percent-encoded.
        let spaced = folder.appendingPathComponent("two words", isDirectory: true)
        try FileManager.default.createDirectory(at: spaced, withIntermediateDirectories: true)
        #expect(GlassTerminalRuntime.folderPath(for: spaced).hasSuffix("two words/") || GlassTerminalRuntime.folderPath(for: spaced).hasSuffix("two words"))
    }
}
