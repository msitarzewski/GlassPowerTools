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

/// `ssh://` links opened with the app (D72).
@Suite("SSH links")
struct TerminalSSHLinkTests {
    private func link(_ string: String) -> TerminalSSHLink? { URL(string: string).flatMap(TerminalSSHLink.init) }

    @Test("user, host and port are read as other SSH clients read them; the rest of the link is not used")
    func parsing() {
        #expect(link("ssh://alpha.example.com") == link("ssh://alpha.example.com:22"))
        let full = link("ssh://ann@alpha.example.com:2222/some/path?x=1")
        #expect(full?.host == "alpha.example.com" && full?.port == 2222 && full?.user == "ann")
        // `user;fingerprint=…`: the user alone — a link's fingerprint is never trusted.
        #expect(link("ssh://ann;fingerprint=ssh-ed25519-AAAA@alpha.example.com")?.user == "ann")
        #expect(link("ssh://ann%20b@alpha")?.user == "ann b")
        #expect(link("ssh://[2001:db8::1]:22")?.host == "2001:db8::1")
        #expect(link("ssh://@alpha")?.user == nil)
        #expect(link("ssh://") == nil)
        #expect(link("ssh://alpha:0") == nil)
        #expect(link("ssh://alpha:70000") == nil)
        #expect(link("https://alpha") == nil)
    }

    @Test("a saved server matches by host and port, and by user when the link names one")
    func matching() throws {
        let annOnAlpha = ServerConfiguration(name: "Alpha", host: "alpha.example.com", port: 22, username: "ann")
        let bobOnAlpha = ServerConfiguration(name: "Alpha (bob)", host: "ALPHA.example.com", port: 22, username: "bob")
        let other = ServerConfiguration(name: "Alpha 2222", host: "alpha.example.com", port: 2222, username: "ann")
        let servers = [annOnAlpha, bobOnAlpha, other]
        #expect(try #require(link("ssh://bob@alpha.example.com")).match(in: servers)?.id == bobOnAlpha.id)
        #expect(try #require(link("ssh://alpha.example.com")).match(in: servers)?.id == annOnAlpha.id)
        #expect(try #require(link("ssh://ann@alpha.example.com:2222")).match(in: servers)?.id == other.id)
        #expect(try #require(link("ssh://carol@alpha.example.com")).match(in: servers) == nil)
        let draft = try #require(link("ssh://carol@bravo.example.com:2200")).draft
        #expect(draft.host == "bravo.example.com" && draft.port == 2200 && draft.username == "carol")
    }
}

/// Files sent to a machine from Shortcuts or the share sheet (D72).
@Suite("Sending files to a machine")
struct GlassSentFilesTests {
    @Test("the folder is the home folder, a folder under it, or an absolute one, named back as written")
    func folders() {
        #expect(GlassSentFiles.remoteFolder(nil, home: "/home/ann") == ("/home/ann", "~"))
        #expect(GlassSentFiles.remoteFolder(" ~ ", home: "/home/ann/") == ("/home/ann", "~"))
        #expect(GlassSentFiles.remoteFolder("Uploads/", home: "/home/ann") == ("/home/ann/Uploads", "~/Uploads"))
        #expect(GlassSentFiles.remoteFolder("~/a b", home: "/home/ann") == ("/home/ann/a b", "~/a b"))
        #expect(GlassSentFiles.remoteFolder("/srv/share", home: "/home/ann") == ("/srv/share", "/srv/share"))
        #expect(GlassSentFiles.remoteFolder(nil, home: "/") == ("/", "~"))
    }

    @Test("one sentence says what arrived and what did not, and why")
    func summary() {
        let one = GlassSentFiles(machine: "alpha", folder: "~", arrived: ["notes.md"], failed: [])
        #expect(one.summary == "Sent notes.md to ~ on alpha.")
        let mixed = GlassSentFiles(machine: "alpha", folder: "~/Uploads", arrived: ["a.png", "b.png"],
                                   failed: [.init(name: "c.mov", reason: "the upload didn't finish. Send it again.")])
        #expect(mixed.summary == "Sent 2 files to ~/Uploads on alpha. c.mov wasn't sent: the upload didn't finish. Send it again.")
        #expect(GlassSentFiles(machine: "alpha", folder: "~", arrived: [], failed: []).summary == "Nothing was sent.")
    }
}

/// A terminal dragged out of the library and dropped in the room (D72, Vision Pro): the dropped
/// window reserves a workgroup for its server, and that server's next session goes into it.
@Suite("Windows waiting for a dropped terminal")
@MainActor
struct DroppedTerminalWindowTests {
    @Test("a reservation is taken once, by its own server; a released one is gone")
    func reservations() {
        let runtime = GlassTerminalRuntime()
        let alpha = UUID(), bravo = UUID()
        let window = runtime.reserveWindow(forServer: alpha)
        #expect(runtime.takeReservedWindow(forServer: bravo) == nil)
        #expect(runtime.takeReservedWindow(forServer: alpha) == window)
        #expect(runtime.takeReservedWindow(forServer: alpha) == nil, "a second session opens a window of its own")

        let failed = runtime.reserveWindow(forServer: bravo)
        runtime.releaseReservation(failed)
        #expect(runtime.takeReservedWindow(forServer: bravo) == nil)
    }
}

/// Handoff of a terminal in tmux (the owner, 2026-10-13: it "opened a new terminal window, with
/// tmux, in my home directory … and it left a detached tmux session in Active").
@Suite("A terminal continued from another device")
@MainActor
struct TerminalHandoffTests {
    @Test("in tmux, it attaches to that session by name — never a new one; outside tmux, it connects")
    func attachesByName() {
        let runtime = GlassTerminalRuntime()
        let server = UUID()
        #expect(runtime.requestContinue(serverID: server, tmuxSession: "glass-3") == false)
        let attached = runtime.takeRequests().contains { request in
            if case let .connect(id, _, _, tmux, _) = request { return id == server && tmux?.name == "glass-3" && tmux?.takeOver == false }
            return false
        }
        #expect(attached, "a continued tmux session attached by name")

        // A name tmux would not accept (it rejects ":") is not passed on: a plain connection, as the
        // library makes.
        runtime.requestContinue(serverID: server, tmuxSession: "glass:3")
        let plain = runtime.takeRequests().contains { request in
            if case let .connect(id, _, _, tmux, _) = request { return id == server && tmux == nil }
            return false
        }
        #expect(plain)
    }

}
