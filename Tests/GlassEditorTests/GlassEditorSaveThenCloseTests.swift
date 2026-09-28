import Foundation
import Testing
import GlassConnectionKit
import GlassEditorCore
@testable import GlassEditor

/// "Close without saving?" ▸ Save used to save and then close regardless, so a save that failed
/// or stopped to ask about a changed file closed the document and lost the edits.
@MainActor
@Suite("Save, then close")
struct GlassEditorSaveThenCloseTests {
    @MainActor private final class Server {
        var files: [String: Data] = [:]
        var refusesWrites = false

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
                    guard let self, !self.refusesWrites else { throw CocoaError(.fileWriteNoPermission) }
                    self.files[path] = data
                    return RemoteStat(size: UInt64(data.count), modificationSeconds: 1)
                },
                stat: { [weak self] path in
                    self?.files[path].map { RemoteStat(size: UInt64($0.count), modificationSeconds: 1) }
                }
            )
        }
    }

    private func edited(on server: Server) async throws -> (GlassEditorWorkspace, GlassEditorDocument) {
        server.files["/srv/app/notes.md"] = Data("one\n".utf8)
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.savethenclose.\(UUID().uuidString)")!)
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: server.access(), reach: .overSSH(host: "bravo"))
        let document = try #require(await workspace.open(path: "/srv/app/notes.md"))
        try document.model.replaceAllContent(with: "two\n")
        #expect(document.isDirty)
        return (workspace, document)
    }

    @Test("a failed save keeps the document open with its edits")
    func failedSaveKeepsDocument() async throws {
        let server = Server()
        let (workspace, document) = try await edited(on: server)
        server.refusesWrites = true

        #expect(await workspace.saveThenClose(document.id) == false)

        #expect(workspace.documents.contains { $0.id == document.id })
        #expect(document.isDirty)
        #expect(workspace.message != nil, "the failure is said")
    }

    @Test("a successful save closes the document")
    func successfulSaveCloses() async throws {
        let server = Server()
        let (workspace, document) = try await edited(on: server)

        #expect(await workspace.saveThenClose(document.id))

        #expect(!workspace.documents.contains { $0.id == document.id })
        #expect(server.files["/srv/app/notes.md"] == Data("two\n".utf8))
    }
}
