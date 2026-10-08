//
//  GlassEditorWindowRoutingTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  Which window something opens in: one project per window, loose files in the window in front
//  (owner, 2026-10-08: *"Each new project should appear in its own editor window"*).
//
//  The second project used to go into the first project's window, where nothing showed it — the
//  title, the footer, the overview and the switcher read only the first — so opening it "died in a
//  silent whisper". These run the runtime's one routing rule with no window anywhere: a window is
//  an id, and "in front" is `noteFrontmost`, which is what a window says when it comes forward.
//

import Foundation
import Testing
import GlassConnectionKit
@testable import GlassEditor

@MainActor
@Suite("Which editor window something opens in")
struct GlassEditorWindowRoutingTests {

    // MARK: Fixtures

    private func runtime() -> GlassEditorRuntime {
        GlassEditorRuntime(defaults: UserDefaults.forTest(suiteName: "editor.routing.\(UUID().uuidString)")!)
    }

    private func folder(_ name: String = "project") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorRouting-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("# \(name)\n".utf8).write(to: url.appendingPathComponent("README.md"))
        return url
    }

    private func file(_ name: String = "notes.txt") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorRouting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data("hello\n".utf8).write(to: url)
        return url
    }

    private func path(of url: URL) -> String {
        GlassEditorProject.normalized(url.standardizedFileURL.path(percentEncoded: false))
    }

    private func settle(_ workspace: GlassEditorWorkspace, documents: Int, turns: Int = 400) async {
        for _ in 0..<turns where workspace.documents.count < documents { await Task.yield() }
    }

    private func settle(_ workspace: GlassEditorWorkspace, projects: Int, turns: Int = 400) async {
        for _ in 0..<turns where workspace.projects.count < projects { await Task.yield() }
    }

    /// A machine that answers with an empty folder, and counts how often it was connected to.
    @MainActor private final class FakeMachine {
        var connections = 0
        func access() -> GlassEditorRemoteFileAccess {
            connections += 1
            return GlassEditorRemoteFileAccess(listing: { _ in [] }, read: { _ in Data() },
                                               write: { _, _, _ in nil }, stat: { _ in nil })
        }
    }

    /// Counts the access asked for and given back, by path. A real URL in a test run is never
    /// security-scoped, so the system's calls would prove nothing either way.
    @MainActor private final class ScopeLedger {
        var held: [String: Int] = [:]
        let grants: Bool

        init(grants: Bool = true) { self.grants = grants }

        var scope: GlassEditorSecurityScope {
            GlassEditorSecurityScope(
                start: { [self] url in
                    guard grants else { return false }
                    held[key(url), default: 0] += 1
                    return true
                },
                stop: { [self] url in held[key(url), default: 0] -= 1 })
        }

        func key(_ url: URL) -> String {
            GlassEditorProject.normalized(url.standardizedFileURL.path(percentEncoded: false))
        }
    }

    // MARK: One project per window

    @Test("a second project opens in a window of its own")
    func aSecondProjectGetsItsOwnWindow() throws {
        let runtime = runtime()
        let first = try folder("alpha"), second = try folder("bravo")

        let a = try #require(runtime.openProject(first))
        runtime.noteFrontmost(a)
        let b = try #require(runtime.openProject(second))

        #expect(a != b, "the second project went into the first project's window")
        #expect(runtime.workspace(for: a).projects.map(\.path) == [path(of: first)])
        #expect(runtime.workspace(for: b).projects.map(\.path) == [path(of: second)])
    }

    @Test("opening a project that is already open brings its window forward")
    func reopeningAProjectFindsItsWindow() throws {
        let runtime = runtime()
        let first = try folder("alpha"), second = try folder("bravo")
        let a = try #require(runtime.openProject(first))
        runtime.noteFrontmost(a)
        let b = try #require(runtime.openProject(second))
        runtime.noteFrontmost(b)

        #expect(runtime.openProject(first) == a)
        #expect(runtime.workspace(for: b).projects.count == 1, "B's window gained a second project")
        // The same folder from the Projects list is the same project, and the same window.
        let listed = GlassEditorProject.local(first)
        #expect(runtime.openProject(listed, reach: .thisMachine) == a)
        #expect(runtime.workspace(for: a).projects.count == 1)
    }

    @Test("a window holding a file does not take a project")
    func aWindowWithAFileDoesNotTakeAProject() async throws {
        let runtime = runtime()
        let loose = try file()
        let front = try #require(runtime.open(loose))
        await settle(runtime.workspace(for: front), documents: 1)
        runtime.noteFrontmost(front)

        let project = try #require(runtime.openProject(try folder()))

        #expect(project != front)
        #expect(runtime.workspace(for: front).projects.isEmpty)
        #expect(runtime.workspace(for: front).documents.count == 1)
        #expect(runtime.workspace(for: project).projects.count == 1)
    }

    @Test("a project on another machine opens in its own window, and connects once")
    func aRemoteProjectGetsItsOwnWindow() async throws {
        let runtime = runtime()
        let machine = FakeMachine()
        runtime.remoteAccess = { @MainActor _ in machine.access() }
        let front = try #require(runtime.openProject(try folder("local")))
        runtime.noteFrontmost(front)

        let remote = GlassEditorProject(hostID: HostID(), path: "/srv/app")
        let window = try #require(runtime.openProject(remote, reach: .overSSH(host: "bravo")))
        // Asked again while it is still connecting: the same window, not a second connection.
        let again = runtime.openProject(remote, reach: .overSSH(host: "bravo"))
        await settle(runtime.workspace(for: window), projects: 1)

        #expect(window != front, "the remote project went into the window in front")
        #expect(again == window)
        #expect(runtime.workspace(for: window).projects.map(\.path) == ["/srv/app"])
        #expect(runtime.workspace(for: front).projects.count == 1)
        #expect(machine.connections == 1)
    }

    @Test("files and a folder chosen together: the files to the window in front, the folder to its own")
    func filesAndAFolderTogether() async throws {
        let runtime = runtime()
        let front = UUID()
        _ = runtime.workspace(for: front)
        runtime.noteFrontmost(front)
        let loose = try file(), project = try folder()

        let windows = runtime.open(urls: [loose, project])
        await settle(runtime.workspace(for: front), documents: 1)

        #expect(windows.count == 2)
        #expect(windows.first == front)
        let other = try #require(windows.last)
        #expect(other != front, "the blank window took the files and the folder both")
        #expect(runtime.workspace(for: front).documents.map(\.displayName) == ["notes.txt"])
        #expect(runtime.workspace(for: front).projects.isEmpty)
        #expect(runtime.workspace(for: other).projects.map(\.path) == [path(of: project)])
    }

    @Test("a folder handed to open is a project, with nothing to apologise for")
    func aFolderThroughOpenIsAProject() throws {
        let runtime = runtime()
        let project = try folder()

        let window = try #require(runtime.open(project))
        let workspace = runtime.workspace(for: window)

        #expect(workspace.projects.map(\.path) == [path(of: project)])
        #expect(workspace.message == nil)
        #expect(workspace.documents.isEmpty)
        // Opening a folder is what puts it in the list, wherever the folder was chosen.
        #expect(runtime.projects.projects.map(\.path) == [path(of: project)])
        // And Open Recent offers it.
        #expect(runtime.preferences.recents.contains { $0.hasDirectoryPath && path(of: $0) == path(of: project) })
    }

    // MARK: What must not change

    @Test("a blank window in front takes the project")
    func aBlankFrontWindowTakesTheProject() throws {
        let runtime = runtime()
        let front = UUID()
        _ = runtime.workspace(for: front)
        runtime.noteFrontmost(front)

        #expect(runtime.openProject(try folder()) == front)
        #expect(runtime.workspace(for: front).projects.count == 1)
    }

    @Test("a window holding only the untouched Untitled of ⇧⌘E takes the project, and lets it go")
    func anUntouchedUntitledWindowTakesTheProject() throws {
        let runtime = runtime()
        let front = UUID()
        runtime.workspace(for: front).newDocument()
        runtime.noteFrontmost(front)

        #expect(runtime.openProject(try folder()) == front)
        #expect(runtime.workspace(for: front).documents.isEmpty)
    }

    @Test("an Untitled with something typed in it is work, and its window keeps it")
    func aTypedUntitledKeepsItsWindow() throws {
        let runtime = runtime()
        let front = UUID()
        let draft = runtime.workspace(for: front).newDocument()
        try draft.model.replaceAllContent(with: "worth keeping\n")
        runtime.noteFrontmost(front)

        let window = try #require(runtime.openProject(try folder()))
        #expect(window != front)
        #expect(runtime.workspace(for: front).documents.count == 1)
    }

    @Test("a file still opens as a tab in the window in front, project or not")
    func aFileStillGoesToTheFrontWindow() async throws {
        let runtime = runtime()
        let front = try #require(runtime.openProject(try folder()))
        runtime.noteFrontmost(front)

        #expect(runtime.open(try file()) == front)
        await settle(runtime.workspace(for: front), documents: 1)
        #expect(runtime.workspace(for: front).documents.count == 1)
    }

    @Test("on a phone, a project in a kept workspace is found there, window or not")
    func aPhoneFindsTheProjectInTheSwitcher() throws {
        let runtime = runtime()
        runtime.closesWorkspaceWithItsWindow = false
        let project = try folder()
        let window = try #require(runtime.openProject(project))
        runtime.noteFrontmost(window)
        // The cover goes away; the session stays in the switcher.
        runtime.forget(window)

        #expect(runtime.openProject(project) == window)
        #expect(runtime.openSessions().count == 1)
    }

    // MARK: Access to a picked folder

    @Test("a picked folder's access is held while the project is open, and given back on close")
    func scopedAccessLastsAsLongAsTheProject() throws {
        let runtime = runtime()
        let ledger = ScopeLedger()
        runtime.securityScope = ledger.scope
        let project = try folder()
        let key = ledger.key(project)

        let window = try #require(runtime.openProject(project))
        let workspace = runtime.workspace(for: window)
        #expect(ledger.held[key] == 1, "access was given back while the project was open")

        // Opened again: the project already holds it, and does not hold it twice.
        _ = runtime.openProject(project)
        #expect(ledger.held[key] == 1)

        let opened = try #require(workspace.projects.first)
        workspace.closeProject(opened.id)
        #expect(ledger.held[key] == 0, "closing the project did not give its access back")
    }

    @Test("a picked folder leaves this device a bookmark, never the synced list")
    func aPickedFolderIsBookmarkedOnThisDeviceOnly() throws {
        let runtime = runtime()
        runtime.securityScope = ScopeLedger().scope
        let project = try folder()

        _ = runtime.openProject(project)
        let listed = try #require(runtime.projects.projects.first)
        let kept = try #require(runtime.projects.bookmarkedURL(forPath: listed.path))
        #expect(path(of: kept.url) == path(of: project))
        #expect(path(of: runtime.localURL(for: listed)) == path(of: project))
        #expect(runtime.localFolderExists(listed))

        // Device-only: nothing of it is in what synchronizes.
        let synced = try JSONEncoder().encode(runtime.projects.payload)
        #expect(!String(decoding: synced, as: UTF8.self).localizedCaseInsensitiveContains("bookmark"))

        runtime.projects.forget(listed.id)
        #expect(runtime.projects.bookmarkedURL(forPath: listed.path) == nil)
    }

    @Test("a folder that needed no access leaves no bookmark")
    func anOrdinaryFolderIsNotBookmarked() throws {
        let runtime = runtime()
        runtime.securityScope = ScopeLedger(grants: false).scope
        let project = try folder()

        _ = runtime.openProject(project)
        #expect(runtime.projects.bookmarkedURL(forPath: path(of: project)) == nil)
    }

    // MARK: Restoration

    @Test("a blank window this launch never asked for is a restored one; any other is not")
    func onlyARestoredBlankWindowIsDiscarded() throws {
        let runtime = runtime()

        // What SwiftUI does when it brings a window back: draws it with a saved id.
        let restored = UUID()
        _ = runtime.windowWorkspace(for: restored)
        #expect(runtime.isRestoredBlankWindow(restored))

        // A window this launch opened, even an empty one, is not.
        let fresh = runtime.newWindowID()
        _ = runtime.windowWorkspace(for: fresh)
        #expect(!runtime.isRestoredBlankWindow(fresh))
        let opened = try #require(runtime.openProject(try folder()))
        #expect(!runtime.isRestoredBlankWindow(opened))
        let presented = UUID()
        runtime.present(presented)
        #expect(!runtime.isRestoredBlankWindow(presented))

        // And a window with something in it is never closed by this.
        let busy = UUID()
        runtime.windowWorkspace(for: busy).openProject(try folder())
        #expect(!runtime.isRestoredBlankWindow(busy))
    }
}
