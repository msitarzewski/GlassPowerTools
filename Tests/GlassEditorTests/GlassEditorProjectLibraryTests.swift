//
//  GlassEditorProjectLibraryTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  The project list is the first thing in the editor that outlives its window, so the questions
//  here are the ones a synchronized list gets wrong: does a deletion stay deleted when a device
//  that never saw it publishes next, and do two devices that merge in opposite orders agree?
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
import GlassEditorCore
@testable import GlassEditor

@Suite("The project library: validation, merge and tombstones")
struct GlassEditorProjectLibraryTests {

    private func record(_ path: String, id: UUID = UUID(), modifiedAt: Date,
                        deletedAt: Date? = nil) -> GlassEditorProjectRecord {
        GlassEditorProjectRecord(
            project: GlassEditorProject(id: id, path: path, openedAt: modifiedAt),
            modifiedAt: modifiedAt,
            deletedAt: deletedAt
        )
    }

    // MARK: - Validation

    @Test("a well-formed list validates")
    func validatesAGoodList() throws {
        let payload = GlassEditorProjectsPayload(records: [
            record("/Users/x/work", modifiedAt: Date()),
            record("/Users/x/other", modifiedAt: Date()),
        ])
        try payload.validate()
    }

    @Test("a relative path, a trailing separator or a repeated identifier is refused")
    func refusesMalformedRecords() {
        let now = Date()
        #expect(throws: (any Error).self) {
            try GlassEditorProjectsPayload(records: [record("work", modifiedAt: now)]).validate()
        }
        // `GlassEditorProject` normalizes on the way in, so a trailing separator can only arrive
        // from a decoded payload — which is exactly where an unchecked one would do its damage:
        // "/work/thing/" is not a prefix of "/work/thing/main.swift" by any string comparison.
        var trailing = record("/work/thing", modifiedAt: now)
        trailing.project.path = "/work/thing/"
        #expect(throws: (any Error).self) {
            try GlassEditorProjectsPayload(records: [trailing]).validate()
        }
        let shared = UUID()
        #expect(throws: (any Error).self) {
            try GlassEditorProjectsPayload(records: [
                record("/a", id: shared, modifiedAt: now),
                record("/b", id: shared, modifiedAt: now),
            ]).validate()
        }
    }

    // MARK: - Merge

    @Test("a deletion survives a stale device publishing the project again")
    func tombstonesAreNotResurrected() {
        let id = UUID()
        let opened = Date(timeIntervalSinceReferenceDate: 1_000)
        let deleted = opened.addingTimeInterval(60)

        let thisDevice = GlassEditorProjectsPayload(records: [
            record("/work/thing", id: id, modifiedAt: opened)
        ])
        let elsewhere = GlassEditorProjectsPayload(records: [
            record("/work/thing", id: id, modifiedAt: opened, deletedAt: deleted)
        ])

        #expect(thisDevice.converged(with: elsewhere).projects.isEmpty)
        // And the other way round: the merge cannot depend on which side is asked.
        #expect(elsewhere.converged(with: thisDevice).projects.isEmpty)
    }

    @Test("reopening a project after it was deleted brings it back")
    func aLaterEditWinsOverATombstone() {
        let id = UUID()
        let deleted = Date(timeIntervalSinceReferenceDate: 1_000)
        let reopened = deleted.addingTimeInterval(60)

        let tombstone = GlassEditorProjectsPayload(records: [
            record("/work/thing", id: id, modifiedAt: deleted.addingTimeInterval(-60),
                   deletedAt: deleted)
        ])
        let reopen = GlassEditorProjectsPayload(records: [
            record("/work/thing", id: id, modifiedAt: reopened)
        ])

        #expect(reopen.converged(with: tombstone).projects.map(\.path) == ["/work/thing"])
        #expect(tombstone.converged(with: reopen).projects.map(\.path) == ["/work/thing"])
    }

    @Test("two devices merging in opposite orders reach the same list")
    func mergeIsOrderIndependent() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let mine = GlassEditorProjectsPayload(records: [
            record("/a", modifiedAt: now),
            record("/b", modifiedAt: now.addingTimeInterval(10)),
        ])
        let theirs = GlassEditorProjectsPayload(records: [
            record("/c", modifiedAt: now.addingTimeInterval(20))
        ])
        #expect(mine.converged(with: theirs) == theirs.converged(with: mine))
        #expect(Set(mine.converged(with: theirs).projects.map(\.path)) == ["/a", "/b", "/c"])
    }

    @Test("the list a device shows is newest first and excludes the deleted")
    func presentationOrder() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let payload = GlassEditorProjectsPayload(records: [
            record("/older", modifiedAt: now),
            record("/newest", modifiedAt: now.addingTimeInterval(20)),
            record("/gone", modifiedAt: now.addingTimeInterval(10),
                   deletedAt: now.addingTimeInterval(30)),
        ])
        #expect(payload.projects.map(\.path) == ["/newest", "/older"])
    }

    // MARK: - Transport

    @Test("the payload round-trips through the envelope the sync service writes")
    func roundTripsThroughTheEnvelope() throws {
        let payload = GlassEditorProjectsPayload(records: [
            record("/work/thing", modifiedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        ])
        let envelope = GlassSettingsSyncEnvelope(
            revision: 1, writerID: UUID(), writtenAt: Date(), payload: payload
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let decoded = try decoder.decode(
            GlassSettingsSyncEnvelope<GlassEditorProjectsPayload>.self,
            from: encoder.encode(envelope)
        )
        try decoded.validate()
        #expect(decoded.payload.projects.map(\.path) == ["/work/thing"])
    }
}

@MainActor
@Suite("The project library: what outlives a window")
struct GlassEditorProjectLibraryStoreTests {

    /// Its own suite per test, so nothing is written into the real Mac's preferences — the
    /// pollution this project already had to clean up once.
    private func makeLibrary() -> (GlassEditorProjectLibrary, UserDefaults, String) {
        let name = "com.glasspowertools.tests.projects.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (GlassEditorProjectLibrary(defaults: defaults), defaults, name)
    }

    private func discard(_ name: String) {
        UserDefaults().removePersistentDomain(forName: name)
    }

    @Test("a project survives the object that recorded it")
    func projectsOutliveTheWindow() {
        let (library, defaults, name) = makeLibrary()
        defer { discard(name) }

        library.remember(GlassEditorProject(path: "/Users/x/work"))
        #expect(library.projects.map(\.path) == ["/Users/x/work"])

        // A new library over the same storage is what the next launch is.
        let relaunched = GlassEditorProjectLibrary(defaults: defaults)
        #expect(relaunched.projects.map(\.path) == ["/Users/x/work"])
    }

    @Test("opening the same folder twice is one project")
    func openingTwiceIsOneProject() {
        let (library, _, name) = makeLibrary()
        defer { discard(name) }

        let first = library.remember(GlassEditorProject(path: "/Users/x/work"))
        // The same folder spelled with a trailing separator is the same folder.
        let second = library.remember(GlassEditorProject(path: "/Users/x/work/"))
        #expect(library.projects.count == 1)
        #expect(first.id == second.id)
    }

    @Test("the same path on two machines is two projects")
    func pathsAreScopedToTheirMachine() {
        let (library, _, name) = makeLibrary()
        defer { discard(name) }

        library.remember(GlassEditorProject(hostID: HostID(), path: "/srv/app"))
        library.remember(GlassEditorProject(hostID: HostID(), path: "/srv/app"))
        #expect(library.projects.count == 2)
    }

    @Test("forgetting a project removes it from the list and keeps a tombstone")
    func forgettingLeavesATombstone() {
        let (library, _, name) = makeLibrary()
        defer { discard(name) }

        let project = library.remember(GlassEditorProject(path: "/Users/x/work"))
        library.forget(project.id)
        #expect(library.projects.isEmpty)
        #expect(library.payload.records.count == 1)
        #expect(library.payload.records[0].isDeleted)
    }

    @Test("renaming changes the name and nothing else")
    func renaming() {
        let (library, _, name) = makeLibrary()
        defer { discard(name) }

        let project = library.remember(GlassEditorProject(path: "/Users/x/work"))
        #expect(project.displayName == "work")
        library.rename(project.id, to: "  The Thing  ")
        #expect(library.projects.first?.displayName == "The Thing")
        #expect(library.projects.first?.path == "/Users/x/work")
        // An empty name is not a rename; the old one stands.
        library.rename(project.id, to: "   ")
        #expect(library.projects.first?.displayName == "The Thing")
    }

    @Test("storage that cannot be read leaves an empty list rather than a crash")
    func corruptStorageIsSurvivable() {
        let name = "com.glasspowertools.tests.projects.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults().removePersistentDomain(forName: name) }

        defaults.set(Data("not a payload".utf8), forKey: GlassEditorProjectLibrary.defaultsKey)
        #expect(GlassEditorProjectLibrary(defaults: defaults).projects.isEmpty)
    }
}

@MainActor
@Suite("The remote file access (stage D)")
struct GlassEditorRemoteDirectoryReaderTests {

    /// A stand-in for the terminal's SFTP client: it records what it was asked for and answers
    /// from a fixture, which is what makes a remote tree testable with no server in the room.
    @MainActor private final class FakeServer {
        var asked: [String] = []
        var listings: [String: [GlassEditorDirectoryEntry]] = [:]
        var failure: (any Error)?

        func list(_ path: String) async throws -> [GlassEditorDirectoryEntry] {
            asked.append(path)
            if let failure { throw failure }
            return listings[path] ?? []
        }
    }

    private struct Unreachable: LocalizedError {
        var errorDescription: String? { "bravo is not answering." }
    }

    @Test("a remote listing becomes the same tree a local one does")
    func remoteListingsBecomeNodes() async throws {
        let server = FakeServer()
        server.listings["/srv/app"] = [
            .init(name: "README.md", isDirectory: false),
            .init(name: "Sources", isDirectory: true),
            .init(name: ".git", isDirectory: true),
            .init(name: "node_modules", isDirectory: true),
            .init(name: "Makefile", isDirectory: false),
        ]
        let reader = GlassEditorRemoteFileAccess(listing: { try await server.list($0) },
                                                 read: { _ in Data() },
                                                 write: { _, _, _ in nil },
                                                 stat: { _ in nil })
        let nodes = try await reader.contents(ofDirectory: "/srv/app")

        // Folders first then names, machinery hidden — the local reader's rules, because they are
        // the same rules and there is one implementation of them.
        #expect(nodes.map(\.name) == ["Sources", "Makefile", "README.md"])
        #expect(nodes.first?.isDirectory == true)
    }

    @Test("a child's path is its parent's, whatever spelling the server answers in")
    func childPathsComeFromTheParent() async throws {
        let server = FakeServer()
        server.listings["/srv/app"] = [.init(name: "main.swift", isDirectory: false)]
        let reader = GlassEditorRemoteFileAccess(listing: { try await server.list($0) },
                                                 read: { _ in Data() },
                                                 write: { _, _, _ in nil },
                                                 stat: { _ in nil })

        // Asked with a trailing separator, as a URL-shaped caller would.
        let nodes = try await reader.contents(ofDirectory: "/srv/app/")
        #expect(nodes.map(\.path) == ["/srv/app/main.swift"])
        #expect(server.asked == ["/srv/app"], "the server was asked in the project's own spelling")
    }

    @Test("a folder reads once, and a second expansion does not ask again")
    func foldersAreReadOnce() async throws {
        let server = FakeServer()
        server.listings["/srv/app"] = [.init(name: "Sources", isDirectory: true)]
        let reader = GlassEditorRemoteFileAccess(listing: { try await server.list($0) },
                                                 read: { _ in Data() },
                                                 write: { _, _, _ in nil },
                                                 stat: { _ in nil })
        let root = GlassEditorProjectNode(name: "app", path: "/srv/app", isDirectory: true)

        await root.loadChildrenIfNeeded(using: reader)
        await root.loadChildrenIfNeeded(using: reader)
        #expect(server.asked == ["/srv/app"])

        // And after a refresh it does ask again, because that is what refresh means.
        root.invalidate()
        await root.loadChildrenIfNeeded(using: reader)
        #expect(server.asked.count == 2)
    }

    @Test("a machine that is not answering leaves the reason on the folder, not an empty tree")
    func aFailedListingSaysWhy() async throws {
        let server = FakeServer()
        server.failure = Unreachable()
        let reader = GlassEditorRemoteFileAccess(listing: { try await server.list($0) },
                                                 read: { _ in Data() },
                                                 write: { _, _, _ in nil },
                                                 stat: { _ in nil })
        let root = GlassEditorProjectNode(name: "app", path: "/srv/app", isDirectory: true)

        await root.loadChildrenIfNeeded(using: reader)
        #expect(root.children?.isEmpty == true)
        #expect(root.loadError == "bravo is not answering.")
        #expect(!root.isLoading)
    }
}

@MainActor
@Suite("A project on another machine")
struct GlassEditorRemoteProjectTests {

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.remote.\(UUID().uuidString)")!)
    }

    private func access(_ entries: [String: [GlassEditorDirectoryEntry]] = [:],
                        onClose: @escaping @MainActor () async -> Void = {})
    -> GlassEditorRemoteFileAccess {
        GlassEditorRemoteFileAccess(listing: { entries[$0] ?? [] },
                                    read: { _ in Data() },
                                    write: { _, _, _ in nil },
                                    stat: { _ in nil },
                                    onClose: onClose)
    }

    /// A remote project cannot be checked against this device's file system, and must not be: the
    /// folder is on a server, and `FileManager` would say it is not there — true of this Mac, and
    /// not the answer to the question.
    @Test("a remote project opens without asking the local file system whether it exists")
    func remoteProjectsSkipTheLocalCheck() async throws {
        let workspace = workspace()
        let project = GlassEditorProject(hostID: HostID(), path: "/srv/app")
        let opened = workspace.openProject(project, access: access([
            "/srv/app": [.init(name: "main.swift", isDirectory: false)]
        ]), reach: .overSSH(host: "bravo"))

        #expect(workspace.projects.map(\.path) == ["/srv/app"])
        #expect(workspace.projectReach[opened.id] == .overSSH(host: "bravo"))
        let root = try #require(workspace.projectRoots[opened.id])
        for _ in 0..<200 where root.children == nil { await Task.yield() }
        #expect((root.children ?? []).map(\.name) == ["main.swift"])
    }

    @Test("a file in a remote project names the machine it is on rather than failing locally")
    func remoteFilesNameTheirMachine() async throws {
        let workspace = workspace()
        let project = GlassEditorProject(hostID: HostID(), path: "/srv/app")
        let opened = workspace.openProject(project, access: access([
            "/srv/app": [.init(name: "main.swift", isDirectory: false)]
        ]), reach: .overSSH(host: "bravo"))
        let root = try #require(workspace.projectRoots[opened.id])
        for _ in 0..<200 where root.children == nil { await Task.yield() }
        let file = try #require((root.children ?? []).first)

        #expect(workspace.machineOf(file) == "bravo")
        // And a local project's file has no machine to name.
        #expect(workspace.machineOf(
            GlassEditorProjectNode(name: "x", path: "/tmp/x", isDirectory: false)
        ) == nil)
    }

    @Test("closing a remote project drops the connection it opened")
    func closingAProjectClosesItsConnection() async throws {
        let workspace = workspace()
        final class Flag: @unchecked Sendable { var closed = false }
        let flag = Flag()
        let project = GlassEditorProject(hostID: HostID(), path: "/srv/app")
        let opened = workspace.openProject(project,
                                           access: access(onClose: { flag.closed = true }),
                                           reach: .overSSH(host: "bravo"))

        workspace.closeProject(opened.id)
        for _ in 0..<200 where !flag.closed { await Task.yield() }
        #expect(flag.closed, "the SFTP session outlived the project that opened it")
    }

    @Test("the same path on two machines opens as two projects")
    func theSamePathOnTwoMachines() {
        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: access(), reach: .overSSH(host: "one"))
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: access(), reach: .overSSH(host: "two"))
        #expect(workspace.projects.count == 2)
    }
}

@MainActor
@Suite("One document path for both machines")
struct GlassEditorFileAccessTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.access.\(UUID().uuidString)")!)
    }

    /// A machine in memory. The same object answers listing, reading, writing and stat, which is
    /// the point: the editor asks one thing for all four.
    @MainActor private final class FakeMachine {
        var files: [String: Data] = [:]
        var writes: [String: Data] = [:]
        var stats: [String: RemoteStat] = [:]

        func access() -> GlassEditorRemoteFileAccess {
            GlassEditorRemoteFileAccess(
                listing: { [weak self] path in
                    (self?.files.keys ?? [:].keys)
                        .filter { $0.hasPrefix(path + "/") }
                        .map { GlassEditorDirectoryEntry(name: ($0 as NSString).lastPathComponent,
                                                         isDirectory: false) }
                },
                read: { [weak self] path in
                    guard let data = self?.files[path] else { throw CocoaError(.fileNoSuchFile) }
                    return data
                },
                write: { [weak self] data, path, expecting in
                    // The machine refuses a write that is not replacing what the editor last saw
                    // — the window between the check and the commit.
                    if let expecting, let now = self?.stats[path],
                       expecting.size != now.size || expecting.modificationSeconds != now.modificationSeconds {
                        throw GlassEditorWriteError.targetChanged((path as NSString).lastPathComponent)
                    }
                    self?.writes[path] = data
                    self?.files[path] = data
                    let committed = RemoteStat(size: UInt64(data.count), modificationSeconds: 5_000)
                    self?.stats[path] = committed
                    return committed
                },
                stat: { [weak self] path in self?.stats[path] }
            )
        }
    }

    // MARK: The local half

    /// The conflict check is not a remote feature. A checkout, a build or another editor changes a
    /// local file underneath this one, and saving over it without asking is the failure an editor
    /// cannot come back from.
    @Test("a local file changed underneath the editor stops the save and asks")
    func aLocalChangeStopsTheSave() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes.txt")
        try Data("one\n".utf8).write(to: url)
        let workspace = workspace()
        let opened = await workspace.open(url)
        let document = try #require(opened)

        try document.model.replaceAllContent(with: "mine\n")
        // Something else writes the file. A whole second later, so a coarse modification time
        // notices it rather than the test proving only that the digest tier works.
        try await Task.sleep(for: .milliseconds(1_100))
        try Data("theirs\n".utf8).write(to: url)

        await workspace.save(document.id)
        let conflict = try #require(workspace.pendingConflict, "the save did not stop to ask")
        #expect(conflict.state == .remoteChangedLocalDirty)
        #expect(conflict.machine == nil, "a local conflict must not claim to be on another machine")
        #expect(try String(contentsOf: url, encoding: .utf8) == "theirs\n",
                "the file was overwritten before the question was answered")

        // Answering it goes ahead.
        await workspace.resolveConflict(.overwriteRemote)
        #expect(try String(contentsOf: url, encoding: .utf8) == "mine\n")
        #expect(workspace.pendingConflict == nil)
    }

    @Test("an unchanged local file saves without asking anything")
    func anUnchangedFileJustSaves() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes.txt")
        try Data("one\n".utf8).write(to: url)
        let workspace = workspace()
        let opened = await workspace.open(url)
        let document = try #require(opened)

        try document.model.replaceAllContent(with: "two\n")
        await workspace.save(document.id)
        #expect(workspace.pendingConflict == nil, "an unchanged file should not raise a question")
        #expect(try String(contentsOf: url, encoding: .utf8) == "two\n")

        // And the baseline moved with the save: saving again must not report our own write as
        // somebody else's change.
        try document.model.replaceAllContent(with: "three\n")
        await workspace.save(document.id)
        #expect(workspace.pendingConflict == nil, "the editor reported its own save as a conflict")
        #expect(try String(contentsOf: url, encoding: .utf8) == "three\n")
    }

    // MARK: The remote half, through the same path

    @Test("a file on another machine opens, edits and saves through the same methods")
    func aRemoteFileMakesTheRoundTrip() async throws {
        let machine = FakeMachine()
        machine.files["/srv/app/main.swift"] = Data("let x = 1\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 10, modificationSeconds: 1_000)

        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))

        let opened = await workspace.open(path: "/srv/app/main.swift")
        let document = try #require(opened, "a file on another machine did not open")
        #expect(document.model.text == "let x = 1\n")
        #expect(document.machine == "bravo")
        // The machine is named under the filename, because /srv/app on two machines is two files.
        #expect(document.locationDescription == "bravo · /srv/app")

        try document.model.replaceAllContent(with: "let x = 2\n")
        await workspace.save(document.id)
        #expect(workspace.pendingConflict == nil)
        #expect(machine.writes["/srv/app/main.swift"] == Data("let x = 2\n".utf8),
                "the edit did not reach the machine")
        #expect(!document.isDirty)
    }

    @Test("a file on another machine that changed there stops the save too")
    func aRemoteChangeStopsTheSave() async throws {
        let machine = FakeMachine()
        machine.files["/srv/app/main.swift"] = Data("let x = 1\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 10, modificationSeconds: 1_000)

        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: "/srv/app/main.swift")
        let document = try #require(opened)

        try document.model.replaceAllContent(with: "mine\n")
        // Somebody else writes the file: new bytes *and* a new stat, which is what a real change
        // is. A new stat alone is a `touch`, and tier 2 is there to not ask about those.
        machine.files["/srv/app/main.swift"] = Data("theirs\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 7, modificationSeconds: 2_000)

        await workspace.save(document.id)
        let conflict = try #require(workspace.pendingConflict)
        #expect(conflict.machine == "bravo")
        #expect(conflict.explanation.contains("bravo"))
        #expect(machine.writes.isEmpty, "the machine was written to before the question was answered")
    }

    /// The tier that stops the editor nagging: a build touched the file and changed nothing, so
    /// the modification time moved and the bytes did not. No question is asked.
    @Test("a file whose timestamp moved but whose bytes did not saves without asking")
    func aTouchIsNotAConflict() async throws {
        let machine = FakeMachine()
        machine.files["/srv/app/main.swift"] = Data("let x = 1\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 10, modificationSeconds: 1_000)

        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: "/srv/app/main.swift")
        let document = try #require(opened)
        try document.model.replaceAllContent(with: "mine\n")

        // Same bytes, later timestamp.
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 10, modificationSeconds: 9_999)

        await workspace.save(document.id)
        #expect(workspace.pendingConflict == nil, "a metadata-only touch raised a question")
        #expect(machine.writes["/srv/app/main.swift"] == Data("mine\n".utf8))
    }

    /// A stat that could not be read is not evidence of sameness. Reporting `.noConflict` for it
    /// would be the editor claiming to have looked when it had not.
    @Test("a machine that cannot be asked reports indeterminate, not unchanged")
    func anUnreadableStatIsIndeterminate() async throws {
        let machine = FakeMachine()
        machine.files["/srv/app/main.swift"] = Data("let x = 1\n".utf8)
        // No stat recorded at all: the access returns nil.
        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: "/srv/app/main.swift")
        let document = try #require(opened)

        try document.model.replaceAllContent(with: "mine\n")
        await workspace.save(document.id)
        #expect(workspace.pendingConflict?.state == .indeterminate)
    }

    @Test("discarding local edits re-reads the file into the tab that is already open")
    func reloadingKeepsTheTab() async throws {
        let machine = FakeMachine()
        machine.files["/srv/app/main.swift"] = Data("let x = 1\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 10, modificationSeconds: 1_000)

        let workspace = workspace()
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: "/srv/app/main.swift")
        let document = try #require(opened)
        try document.model.replaceAllContent(with: "mine\n")

        machine.files["/srv/app/main.swift"] = Data("theirs\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 7, modificationSeconds: 2_000)
        await workspace.save(document.id)
        await workspace.resolveConflict(.discardLocalAndReload)

        #expect(document.model.text == "theirs\n")
        #expect(!document.isDirty)
        #expect(workspace.documents.count == 1, "reloading opened a second tab")
        #expect(workspace.documents.first?.id == document.id, "reloading replaced the tab")
    }
}

@MainActor
@Suite("The window between the question and the write")
struct GlassEditorVerifiedWriteTests {

    @MainActor private final class Machine {
        var files: [String: Data] = ["/srv/app/main.swift": Data("let x = 1\n".utf8)]
        var stats: [String: RemoteStat] = ["/srv/app/main.swift": RemoteStat(size: 10, modificationSeconds: 1_000)]
        var refusals = 0
        var committed: [String: Data] = [:]

        func access() -> GlassEditorRemoteFileAccess {
            GlassEditorRemoteFileAccess(
                listing: { _ in [] },
                read: { [weak self] path in
                    guard let data = self?.files[path] else { throw CocoaError(.fileNoSuchFile) }
                    return data
                },
                write: { [weak self] data, path, expecting in
                    guard let self else { return nil }
                    // The machine is the authority on what it is replacing, which is the whole
                    // point of sending an expectation rather than trusting a check that has
                    // already finished.
                    if let expecting, let now = self.stats[path],
                       expecting.size != now.size
                        || expecting.modificationSeconds != now.modificationSeconds {
                        self.refusals += 1
                        throw GlassEditorWriteError.targetChanged("main.swift")
                    }
                    self.committed[path] = data
                    self.files[path] = data
                    let stat = RemoteStat(size: UInt64(data.count), modificationSeconds: 7_000)
                    self.stats[path] = stat
                    return stat
                },
                stat: { [weak self] path in self?.stats[path] }
            )
        }
    }

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.verified.\(UUID().uuidString)")!)
    }

    private func openRemote(_ machine: Machine, into workspace: GlassEditorWorkspace) async throws
    -> GlassEditorDocument {
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: "/srv/app/main.swift")
        return try #require(opened)
    }

    /// The case the expectation exists for: the file changes **after** the check said it was safe
    /// and **before** the bytes land. Nothing is written, and the editor says so rather than
    /// reporting a save that replaced somebody's work.
    @Test("a file that changes after the check and before the write is not overwritten")
    func aChangeMidSaveIsRefused() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        // Save, with the machine moving underneath at the moment the write is attempted. The
        // access is asked for the stat during the check and again inside the write, so changing it
        // in between is exactly the race.
        let racing = GlassEditorRemoteFileAccess(
            listing: { _ in [] },
            read: { machine.files[$0] ?? Data() },
            write: { data, path, expecting in
                // Somebody else got there first.
                machine.stats[path] = RemoteStat(size: 99, modificationSeconds: 8_888)
                return try await machine.access().write(data, to: path, expecting: expecting)
            },
            stat: { machine.stats[$0] }
        )
        var thrown: (any Error)?
        do {
            try await document.save(through: racing, expecting: machine.stats["/srv/app/main.swift"])
        } catch { thrown = error }

        #expect(thrown as? GlassEditorWriteError == .targetChanged("main.swift"))
        #expect(machine.committed.isEmpty, "the write landed on a version nobody had seen")
        #expect(document.isDirty, "the edit was marked saved when nothing was written")
    }

    /// Answering "save anyway" authorises replacing **what was on screen when the question was
    /// asked** — not whatever the file has become while the dialog sat there.
    @Test("save anyway replaces what the question was about, and refuses a third version")
    func overwriteAuthorisesOneObservation() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        machine.files["/srv/app/main.swift"] = Data("theirs\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 7, modificationSeconds: 2_000)
        await workspace.save(document.id)
        let conflict = try #require(workspace.pendingConflict)
        #expect(conflict.observed?.modificationSeconds == 2_000)

        // It changes a third time while the question is on screen.
        machine.files["/srv/app/main.swift"] = Data("someone else\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 13, modificationSeconds: 3_000)
        await workspace.resolveConflict(.overwriteRemote)

        #expect(machine.committed.isEmpty, "a version nobody was asked about was overwritten")
        #expect(machine.refusals == 1)
        #expect(workspace.message?.contains("changed while it was being saved") == true)
    }

    /// And when nothing moved, "save anyway" does write.
    @Test("save anyway writes when the file is still the one the question was about")
    func overwriteWritesWhenNothingMoved() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        machine.files["/srv/app/main.swift"] = Data("theirs\n".utf8)
        machine.stats["/srv/app/main.swift"] = RemoteStat(size: 7, modificationSeconds: 2_000)
        await workspace.save(document.id)
        #expect(workspace.pendingConflict != nil)

        await workspace.resolveConflict(.overwriteRemote)
        #expect(machine.committed["/srv/app/main.swift"] == Data("mine\n".utf8))
        #expect(!document.isDirty)
    }
}
