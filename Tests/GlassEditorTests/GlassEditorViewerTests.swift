import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditor

/// A file that is not text opens as what it is (2026-09-23: *"when I click a png I get the image,
/// not the binary?"*).
@Suite("Files that are not text open in a viewer")
@MainActor
struct GlassEditorViewerTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 64)

    /// Another machine, in memory: a file's bytes and the size its stat reports.
    private final class FakeRemote: GlassEditorFileAccess {
        var files: [String: Data] = [:]
        var reportedSizes: [String: UInt64] = [:]
        var reads = 0
        func contents(ofDirectory path: String) async throws -> [GlassEditorProjectNode] { [] }
        func read(_ path: String) async throws -> Data {
            reads += 1
            guard let data = files[path] else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
        func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat? {
            Issue.record("a viewer must never write"); return nil
        }
        func stat(_ path: String) async throws -> RemoteStat? {
            RemoteStat(size: reportedSizes[path] ?? UInt64(files[path]?.count ?? 0))
        }
    }

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "glass-viewer-\(UUID().uuidString)")!)
    }

    private func localFile(_ name: String, _ data: Data) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-viewer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test("A local PNG opens as an image, in place, and is never dirty")
    func localImage() async throws {
        let url = try localFile("logo.png", Self.png)
        let workspace = workspace()
        let document = try #require(await workspace.open(url))
        let viewer = try #require(document.viewer, "a PNG was decoded as text")
        #expect(viewer.kind == .image)
        #expect(viewer.fileURL.path(percentEncoded: false) == url.path(percentEncoded: false),
                "a local file is shown where it is, not copied")
        #expect(document.model.text.isEmpty && !document.isDirty)
        // Saving a viewer writes nothing: the picture on disk is untouched.
        try await document.save(through: GlassEditorLocalFileAccess())
        #expect(try Data(contentsOf: url) == Self.png)
    }

    @Test("A remote PNG is copied to a temporary file the viewer can open, and the copy goes with it")
    func remoteImageCopy() async throws {
        let remote = FakeRemote()
        remote.files["/srv/app/logo.png"] = Self.png
        let workspace = workspace()
        var folder: URL?
        do {
            let document = try #require(await workspace.open(path: "/srv/app/logo.png", through: remote, machine: "alpha"))
            let viewer = try #require(document.viewer)
            #expect(viewer.kind == .image)
            #expect(viewer.fileURL.lastPathComponent == "logo.png", "the name, so viewers read the extension")
            #expect(try Data(contentsOf: viewer.fileURL) == Self.png)
            folder = viewer.fileURL.deletingLastPathComponent()
            workspace.close(document.id)
        }
        let copy = try #require(folder)
        #expect(!FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)),
                "the temporary copy outlived its viewer")
    }

    @Test("A large remote media file asks first; yes downloads it, no reads nothing")
    func largeRemoteAsks() async throws {
        let remote = FakeRemote()
        remote.files["/srv/movie.mp4"] = Data([0, 0, 0, 0x18] + Array("ftypisom".utf8) + Array(repeating: 0, count: 20))
        remote.reportedSizes["/srv/movie.mp4"] = GlassEditorOpenError.remoteMediaLimit + 1
        let workspace = workspace()

        #expect(await workspace.open(path: "/srv/movie.mp4", through: remote, machine: "alpha") == nil)
        #expect(workspace.pendingLargeOpen?.path == "/srv/movie.mp4")
        #expect(remote.reads == 0, "nothing was downloaded before asking")
        #expect(workspace.message == nil, "a question, not an error")

        workspace.cancelLargeOpen()
        #expect(workspace.pendingLargeOpen == nil && remote.reads == 0)

        _ = await workspace.open(path: "/srv/movie.mp4", through: remote, machine: "alpha")
        await workspace.confirmLargeOpen()
        #expect(workspace.documents.first?.viewer?.kind == .video)
    }

    @Test("A large remote text file does not ask: text is read as always")
    func largeRemoteTextDoesNotAsk() async throws {
        let remote = FakeRemote()
        remote.files["/var/log/big.log"] = Data("line\n".utf8)
        remote.reportedSizes["/var/log/big.log"] = GlassEditorOpenError.remoteMediaLimit + 1
        let workspace = workspace()
        let document = try #require(await workspace.open(path: "/var/log/big.log", through: remote, machine: "alpha"))
        #expect(document.viewer == nil && workspace.pendingLargeOpen == nil)
    }

    @Test("Open as Text replaces the viewer with the decoded file, in the same tab position")
    func openAsText() async throws {
        let first = try localFile("a.txt", Data("a\n".utf8))
        let blob = try localFile("server", Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0x41]))
        let last = try localFile("b.txt", Data("b\n".utf8))
        let workspace = workspace()
        _ = await workspace.open(first)
        let binary = try #require(await workspace.open(blob))
        _ = await workspace.open(last)
        #expect(binary.viewer?.kind == .binary)

        await workspace.openAsText(binary)
        #expect(workspace.documents.count == 3)
        let middle = workspace.documents[1]
        #expect(middle.viewer == nil, "it is text now")
        #expect(middle.path == blob.path(percentEncoded: false))
    }
}

/// A file with a line past `veryLongLine` opens wrapped, on that file only (2026-09-23: the
/// user's 14.6 MB one-line SVG took 26 s to lay out unwrapped on the Mac, about 1 s wrapped).
@Suite("A very long line opens wrapped")
@MainActor
struct GlassEditorVeryLongLineTests {
    private func file(_ text: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-longline-\(UUID().uuidString).svg")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("Over the limit: wrapped, as this file's own setting; under it: the global setting")
    func wrapsOnlyTheLongOne() async throws {
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "glass-longline-\(UUID().uuidString)")!)
        let long = try file("<svg><path d=\"" + String(repeating: "L1 2 ", count: 30_000) + "\"/></svg>")
        let short = try file("<svg><path d=\"M0 0\"/></svg>")
        let wide = try #require(await workspace.open(long))
        #expect(wide.hasVeryLongLine)
        #expect(wide.textOverrides.wrapsLines == true)
        #expect(wide.model.configuration.wrapsLines, "the override reached the engine's configuration")
        let narrow = try #require(await workspace.open(short))
        #expect(!narrow.hasVeryLongLine)
        #expect(narrow.textOverrides.wrapsLines == nil, "an ordinary file is not touched")
        #expect(workspace.previewModes[wide.id] == nil, "not a phone: the text is shown, wrapped")
    }
}
