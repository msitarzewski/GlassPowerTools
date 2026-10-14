//
//  GlassEditorOutsideChangeTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  B-X2: the editor looks at a file again when its window comes forward, not only when it saves —
//  the legacy SFTP sheet did, and the editor that replaced it did not, so edits went onto a stale
//  copy and the question came only at ⌘S. What must hold: a real change is asked about, with the
//  answers that fit; a touch, a silent machine or an unchanged file asks nothing; one question per
//  change, however often the window comes forward; and the editor's own save is never mistaken for
//  somebody else's.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("The editor looks again when its window comes forward")
struct GlassEditorOutsideChangeTests {

    private static let path = "/srv/app/main.swift"

    @MainActor private final class Machine {
        var files: [String: Data] = [path: Data("let x = 1\n".utf8)]
        var stats: [String: RemoteStat] = [path: RemoteStat(size: 10, modificationSeconds: 1_000)]
        var reads = 0
        /// Set to hold a write after it has landed and before it answers: the moment a check that
        /// overlaps the save would see the editor's own bytes.
        var holdsWrites = false
        var heldWrite: CheckedContinuation<Void, Never>?

        func access() -> GlassEditorRemoteFileAccess {
            GlassEditorRemoteFileAccess(
                listing: { _ in [] },
                read: { [weak self] path in
                    self?.reads += 1
                    guard let data = self?.files[path] else { throw CocoaError(.fileNoSuchFile) }
                    return data
                },
                write: { [weak self] data, path, _ in
                    guard let self else { return nil }
                    self.files[path] = data
                    let stat = RemoteStat(size: UInt64(data.count), modificationSeconds: 7_000)
                    self.stats[path] = stat
                    if self.holdsWrites { await withCheckedContinuation { self.heldWrite = $0 } }
                    return stat
                },
                stat: { [weak self] path in self?.stats[path] }
            )
        }

        /// Somebody else writes the file: new bytes and a new stat.
        func changeElsewhere(to text: String, at seconds: Int64) {
            files[path] = Data(text.utf8)
            stats[path] = RemoteStat(size: UInt64(text.utf8.count), modificationSeconds: seconds)
        }
    }

    private func workspace() -> GlassEditorWorkspace {
        GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.forward.\(UUID().uuidString)")!)
    }

    private func openRemote(_ machine: Machine, into workspace: GlassEditorWorkspace) async throws
    -> GlassEditorDocument {
        workspace.openProject(GlassEditorProject(hostID: HostID(), path: "/srv/app"),
                              access: machine.access(), reach: .overSSH(host: "bravo"))
        let opened = await workspace.open(path: Self.path)
        return try #require(opened)
    }

    @Test("a file changed elsewhere is asked about when the window comes forward, before any edit")
    func aChangeIsAskedAboutOnReturn() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)

        machine.changeElsewhere(to: "theirs\n", at: 2_000)
        await workspace.checkForOutsideChange(document.id)

        let conflict = try #require(workspace.pendingConflict, "coming forward did not notice the change")
        #expect(conflict.cause == .cameForward)
        #expect(conflict.state == .remoteChangedLocalClean)
        // Nothing here is newer than the file, so replacing it is not offered.
        #expect(conflict.resolutions == [.discardLocalAndReload, .keepEditing])

        await workspace.resolveConflict(.discardLocalAndReload)
        #expect(document.model.text == "theirs\n")
        #expect(workspace.documents.count == 1)
    }

    @Test("with edits in the copy, every answer is offered")
    func editsGetEveryAnswer() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        machine.changeElsewhere(to: "theirs\n", at: 2_000)
        await workspace.checkForOutsideChange(document.id)

        let conflict = try #require(workspace.pendingConflict)
        #expect(conflict.state == .remoteChangedLocalDirty)
        #expect(conflict.resolutions == [.overwriteRemote, .discardLocalAndReload, .keepEditing])
        #expect(machine.files[Self.path] == Data("theirs\n".utf8), "the check wrote something")
    }

    @Test("an unchanged file, a touch or a machine that does not answer asks nothing")
    func nothingToAskAbout() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict == nil, "an unchanged file raised a question")

        // A build touched it: the time moved, the bytes did not.
        machine.stats[Self.path] = RemoteStat(size: 10, modificationSeconds: 9_999)
        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict == nil, "a touch raised a question")

        // The machine cannot be asked. Not "unchanged" — the save still says it could not check —
        // but no question every time the window comes forward over a dropped connection.
        machine.stats[Self.path] = nil
        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict == nil, "a machine that did not answer raised a question")
        await workspace.save(document.id)
        #expect(workspace.pendingConflict?.state == .indeterminate, "the save stopped reporting what it could not check")
    }

    @Test("one question per change, however often the window comes forward")
    func askedOncePerChange() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        machine.changeElsewhere(to: "theirs\n", at: 2_000)
        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict != nil)
        await workspace.resolveConflict(.keepEditing)

        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict == nil, "the same change was asked about twice")

        // Nor is the file downloaded again to find that out.
        let reads = machine.reads
        await workspace.checkForOutsideChange(document.id)
        #expect(machine.reads == reads, "an answered change was downloaded again on coming forward")

        machine.changeElsewhere(to: "theirs again\n", at: 3_000)
        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict != nil, "a further change was not asked about")

        // And the save asks for itself, whatever was answered on coming forward.
        await workspace.resolveConflict(.keepEditing)
        await workspace.save(document.id)
        #expect(workspace.pendingConflict?.cause == .saving)
    }

    @Test("the editor's own save is not taken for somebody else's change")
    func ownSaveIsNotAChange() async throws {
        let machine = Machine()
        let workspace = workspace()
        let document = try await openRemote(machine, into: workspace)
        try document.model.replaceAllContent(with: "mine\n")

        // The write has landed on the machine and not yet answered when the window comes forward.
        machine.holdsWrites = true
        let saving = Task { await workspace.save(document.id) }
        while machine.heldWrite == nil { try await Task.sleep(for: .milliseconds(5)) }
        await workspace.checkForOutsideChange(document.id)
        machine.heldWrite?.resume()
        await saving.value

        #expect(workspace.pendingConflict == nil, "the editor's own write was reported as a change")
        #expect(!document.isDirty)

        // And afterwards, the saved file is the baseline.
        await workspace.checkForOutsideChange(document.id)
        #expect(workspace.pendingConflict == nil)
    }

    @Test("a document that has never been saved is never checked")
    func nothingToCheck() async throws {
        let workspace = workspace()
        let untitled = workspace.newDocument()
        await workspace.checkForOutsideChange(untitled.id)
        #expect(workspace.pendingConflict == nil)
    }
}
