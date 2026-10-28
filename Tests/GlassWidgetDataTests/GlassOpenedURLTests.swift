import Foundation
import Testing
@testable import GlassWidgetData

/// What opening something with the app asks for, and requests left by extensions (D72).
@Suite("Opened files, links and extensions' requests")
struct GlassOpenedURLTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glass-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("on the Mac a folder opens a terminal, a .command runs, a package and a file go to the editor")
    func routingOnTheMac() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("build.command")
        let notes = folder.appendingPathComponent("notes.md")
        let package = folder.appendingPathComponent("Thing.app", isDirectory: true)
        try Data("echo hi\n".utf8).write(to: script)
        try Data("# hi\n".utf8).write(to: notes)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        #expect(GlassWidgetRequest.forOpened(folder, isMac: true) == .newLocalTerminal(folder: folder))
        #expect(GlassWidgetRequest.forOpened(script, isMac: true) == .runInTerminal(script))
        #expect(GlassWidgetRequest.forOpened(notes, isMac: true) == .openInEditor([notes]))
        #expect(GlassWidgetRequest.forOpened(package, isMac: true) == .openInEditor([package]))
        // Off the Mac there is no local terminal: everything goes to the editor.
        #expect(GlassWidgetRequest.forOpened(script, isMac: false) == .openInEditor([script]))
    }

    @Test("A Terminal profile opened with the app becomes a terminal theme, on every device, whatever its case")
    func terminalProfiles() throws {
        let tango = URL(fileURLWithPath: "/tmp/Tango Dark.terminal")
        #expect(GlassWidgetRequest.forOpened(tango, isMac: true) == .importTerminalThemes([tango]))
        #expect(GlassWidgetRequest.forOpened(tango, isMac: false) == .importTerminalThemes([tango]))
        let shouting = URL(fileURLWithPath: "/tmp/GLACIER.TERMINAL")
        #expect(GlassWidgetRequest.forOpened(shouting, isMac: false) == .importTerminalThemes([shouting]))
        let request = GlassWidgetRequest.importTerminalThemes([tango])
        #expect(try JSONDecoder().decode(GlassWidgetRequest.self, from: JSONEncoder().encode(request)) == request,
                "an extension can leave it for the app")
    }

    @Test("an ssh link is a connection; another scheme is not the app's")
    func links() throws {
        let ssh = try #require(URL(string: "ssh://ann@alpha.example.com:2222"))
        #expect(GlassWidgetRequest.forOpened(ssh, isMac: true) == .openSSHLink(ssh))
        #expect(GlassWidgetRequest.forOpened(try #require(URL(string: "SSH://alpha")), isMac: false) != nil)
        #expect(GlassWidgetRequest.forOpened(try #require(URL(string: "https://example.com")), isMac: true) == nil)
    }

    @Test("an extension's requests reach the app oldest first, once; a stale or unreadable one is dropped")
    func externalRequests() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let here = URL(fileURLWithPath: "/tmp", isDirectory: true)
        try GlassExternalRequests.leave(.newLocalTerminalTab(folder: here), in: folder, now: now.addingTimeInterval(-2))
        try GlassExternalRequests.leave(.showActive, in: folder, now: now.addingTimeInterval(-1))
        try GlassExternalRequests.leave(.openInEditor([here]), in: folder, now: now.addingTimeInterval(-600))
        try Data("not a request".utf8).write(to: folder.appendingPathComponent("\(now.timeIntervalSince1970)-x.json"))

        #expect(GlassExternalRequests.take(from: folder, now: now) == [.newLocalTerminalTab(folder: here), .showActive])
        #expect(GlassExternalRequests.take(from: folder, now: now).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test("every request survives the trip between processes")
    func codable() throws {
        let url = URL(fileURLWithPath: "/tmp/a b", isDirectory: true)
        let all: [GlassWidgetRequest] = [
            .connect(machine: UUID(), service: UUID()), .showMachine(UUID()), .showActive, .showAllWindows, .openWorkgroup(UUID()), .openSavedQuery(UUID()),
            .newLocalTerminal(folder: nil), .newLocalTerminal(folder: url), .newLocalTerminalTab(folder: url),
            .runInTerminal(url), .openInEditor([url, url]), .openSSHLink(try #require(URL(string: "ssh://alpha"))),
            .continueSession(endpoint: UUID(), tmux: nil), .continueSession(endpoint: UUID(), tmux: "glass-3"),
            .sendFiles([url], machine: UUID(), folder: nil), .sendFiles([url, url], machine: UUID(), folder: "Uploads"),
        ]
        for request in all {
            #expect(try JSONDecoder().decode(GlassWidgetRequest.self, from: JSONEncoder().encode(request)) == request)
        }
    }

    @Test("files staged for a send that never reached the app go after a day; newer ones stay")
    func staleStaging() throws {
        let staging = try scratch()
        defer { try? FileManager.default.removeItem(at: staging) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let old = staging.appendingPathComponent("old", isDirectory: true)
        let fresh = staging.appendingPathComponent("fresh", isDirectory: true)
        for folder in [old, fresh] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.creationDate: now.addingTimeInterval(-90_000)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.creationDate: now.addingTimeInterval(-60)], ofItemAtPath: fresh.path)

        GlassExternalRequests.clearStaleStaging(in: staging, now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }
}
