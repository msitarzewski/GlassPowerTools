import Foundation
import GlassSSHTransport
import Testing
@testable import GlassTerminal

/// Where the Files browser opens (2026-10-09). Open Folder Here passes the shell's working
/// directory; the connection then set the home folder over it, so the browser always opened at
/// home (owner, on the Vision Pro). Driven through the real `SFTPClient` over an in-memory host.
@Suite("Where the Files browser opens")
@MainActor
struct SFTPBrowserStartTests {
    @Test("the folder asked for, when the host says it is one; home otherwise")
    func startingFolder() async throws {
        let host = DropTestHost(home: "/home/alpha")
        await host.makeFolders(["/home/alpha/src/app/Sources"])
        await host.put("/home/alpha/notes.txt", "notes")
        let client = SFTPClient(session: host, extensions: SFTPServerExtensions([:]))
        func start(_ requested: String?) async throws -> String {
            try await SFTPBrowserView.startingFolder(requested: requested, client: client)
        }

        #expect(try await start("/home/alpha/src/app/Sources") == "/home/alpha/src/app/Sources",
                "Open Folder Here: the shell's own folder, not home")
        #expect(try await start(nil) == "/home/alpha", "nothing asked for: home")
        #expect(try await start("src/app") == "/home/alpha", "a relative path is not a place to go")
        #expect(try await start("/home/alpha/gone") == "/home/alpha", "a folder that has gone: home")
        #expect(try await start("/home/alpha/notes.txt") == "/home/alpha", "a file is not a folder")
    }
}
