import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

/// A server's file copied here for its preview over a terminal (2026-10-16), and gone after.
@MainActor
@Suite("A server's file, copied for its preview")
struct TerminalRemotePreviewTests {
    @Test("kept under its own name in a folder of its own, which closing the preview removes")
    func savedAndDiscarded() throws {
        let file = try #require(TerminalRemotePreview.save(Data("# Notes\n".utf8), named: "README.md"))
        #expect(file.url.lastPathComponent == "README.md", "a viewer that goes by the name sees what it is")
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "# Notes\n")
        let folder = file.url.deletingLastPathComponent()
        let other = try #require(TerminalRemotePreview.save(Data([1, 2, 3]), named: "README.md"))
        #expect(other.url.deletingLastPathComponent() != folder, "each preview its own folder")

        file.discard?()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: other.url.path), "another's copy stays")
        other.discard?()
        #expect(!FileManager.default.fileExists(atPath: other.url.deletingLastPathComponent().path))
    }

    @Test("a file with no name is not saved")
    func noName() {
        #expect(TerminalRemotePreview.save(Data([1]), named: "") == nil)
    }
}
