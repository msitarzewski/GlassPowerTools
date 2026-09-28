import Foundation
import Testing
import GlassConnectionKit
import GlassEditorCore
@testable import GlassEditor

/// New files and a new document's first save, in a project on this Mac or on a server. The editor
/// could make neither on a server (2026-09-26: an SFTP window had no New File, and a new document
/// could only be saved to this Mac).
@MainActor
@Suite("New files and first saves into projects")
struct GlassEditorNewFileTests {

    /// A server in memory: one object answers listing, reading and writing.
    @MainActor private final class Server {
        var files: [String: Data] = [:]
        private(set) var writes: [String] = []

        func access() -> GlassEditorRemoteFileAccess {
            GlassEditorRemoteFileAccess(
                listing: { [weak self] folder in
                    (self?.files.keys ?? [:].keys)
                        .filter { ($0 as NSString).deletingLastPathComponent == folder }
                        .map { GlassEditorDirectoryEntry(name: ($0 as NSString).lastPathComponent, isDirectory: false) }
                },
                read: { [weak self] path in
                    guard let data = self?.files[path] else { throw CocoaError(.fileNoSuchFile) }
                    return data
                },
                write: { [weak self] data, path, _ in
                    self?.writes.append(path)
                    self?.files[path] = data
                    return RemoteStat(size: UInt64(data.count), modificationSeconds: 1)
                },
                stat: { [weak self] path in
                    self?.files[path].map { RemoteStat(size: UInt64($0.count), modificationSeconds: 1) }
                }
            )
        }
    }

    private func workspace(with server: Server) -> GlassEditorWorkspace {
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.newfile.\(UUID().uuidString)")!)
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: server.access(), reach: .overSSH(host: "bravo"))
        return workspace
    }

    @Test("New File on a server makes an empty file there and opens it on that machine")
    func newFileOnAServer() async throws {
        let server = Server()
        server.files["/srv/app/README.md"] = Data("readme".utf8)
        let workspace = workspace(with: server)

        let document = try #require(try await workspace.createFile(named: "notes.md", inFolder: "/srv/app"))

        #expect(server.files["/srv/app/notes.md"] == Data())
        #expect(document.path == "/srv/app/notes.md")
        #expect(document.machine == "bravo")
        #expect(workspace.selectedDocument?.id == document.id)
    }

    @Test("New File never replaces an existing file, and refuses names that are not one file")
    func newFileRefusesExistingAndInvalidNames() async throws {
        let server = Server()
        server.files["/srv/app/README.md"] = Data("readme".utf8)
        let workspace = workspace(with: server)

        await #expect(throws: GlassEditorWorkspace.CreateFileError.exists("README.md")) {
            try await workspace.createFile(named: "README.md", inFolder: "/srv/app")
        }
        for name in ["", "  ", ".", "..", "a/b"] {
            await #expect(throws: GlassEditorWorkspace.CreateFileError.invalidName) {
                try await workspace.createFile(named: name, inFolder: "/srv/app")
            }
        }
        #expect(server.writes.isEmpty, "nothing was written")
        #expect(server.files["/srv/app/README.md"] == Data("readme".utf8))
    }

    @Test("a new document saved into a server folder lands there and takes that name and machine")
    func firstSaveIntoAServerProject() async throws {
        let server = Server()
        let workspace = workspace(with: server)
        let document = workspace.newDocument()
        try document.model.replaceAllContent(with: "KEY=value\n")

        try await workspace.saveNewDocument(document.id, named: ".env", inFolder: "/srv/app")

        #expect(server.files["/srv/app/.env"] == Data("KEY=value\n".utf8))
        #expect(document.path == "/srv/app/.env")
        #expect(document.displayName == ".env")
        #expect(document.machine == "bravo")
        #expect(!document.isDirty)
    }

    @Test("a first save refuses to replace a file that is already there")
    func firstSaveRefusesAnExistingFile() async throws {
        let server = Server()
        server.files["/srv/app/.env"] = Data("OLD=1\n".utf8)
        let workspace = workspace(with: server)
        let document = workspace.newDocument()
        try document.model.replaceAllContent(with: "NEW=2\n")

        await #expect(throws: GlassEditorWorkspace.CreateFileError.exists(".env")) {
            try await workspace.saveNewDocument(document.id, named: ".env", inFolder: "/srv/app")
        }
        #expect(server.files["/srv/app/.env"] == Data("OLD=1\n".utf8))
        #expect(document.hasNeverBeenSaved)
    }

    @Test("New File in a project on this Mac makes the file on disk")
    func newFileLocally() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.newfile.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))

        let document = try #require(try await workspace.createFile(named: "main.swift", inFolder: project.path))

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("main.swift").path))
        #expect(document.machine == nil)
    }
}
