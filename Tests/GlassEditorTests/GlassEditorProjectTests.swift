//
//  GlassEditorProjectTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  A project is a folder on a machine, and which machine decides how its files are read.
//
//  The identity half is the interesting one. "Is this SSH connection actually this machine?" has
//  three tempting wrong answers — the hostname, the address, and "it looks local" — and one right
//  one: the SSH host key, which is the only thing a machine has that survives being renamed,
//  re-addressed and reached through a tunnel. These tests are about not accepting the wrong ones.
//

import Foundation
import Testing
@testable import GlassEditor

@MainActor
@Suite("Projects and machine identity (stage 5)")
struct GlassEditorProjectTests {

    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Project-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("Sources/Deep", isDirectory: true),
                                    withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent(".git", isDirectory: true),
                                    withIntermediateDirectories: true)
        try Data("main".utf8).write(to: root.appendingPathComponent("Sources/main.swift"))
        try Data("# readme".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("x".utf8).write(to: root.appendingPathComponent(".git/config"))
        return root
    }

    // MARK: The tree

    @Test func aProjectReadsItsRootFoldersFirstAndSkipsMachinery() throws {
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.project.\(UUID().uuidString)")!)

        let project = try #require(workspace.openProject(root))
        let node = try #require(workspace.projectRoots[project.id])
        let names = (node.children ?? []).map(\.name)

        #expect(names == ["Sources", "README.md"], "got \(names)")
        #expect(!names.contains(".git"), ".git was listed in a project tree")
    }

    /// A checkout can hold a hundred thousand files. Reading them all to draw a sidebar is how an
    /// editor earns a beachball, so a folder is read when it is opened and not before.
    @Test func foldersAreReadOnlyWhenTheyAreExpanded() throws {
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.project.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let node = try #require(workspace.projectRoots[project.id])
        let sources = try #require((node.children ?? []).first { $0.name == "Sources" })

        #expect(sources.children == nil, "a folder was read before it was expanded")
        sources.loadChildrenIfNeeded(using: GlassEditorLocalDirectoryReader())
        #expect((sources.children ?? []).map(\.name) == ["Deep", "main.swift"])
    }

    @Test func openingTheSameFolderTwiceIsOneProject() throws {
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.project.\(UUID().uuidString)")!)
        let first = try #require(workspace.openProject(root))
        let second = try #require(workspace.openProject(root))
        #expect(first.id == second.id)
        #expect(workspace.projects.count == 1)
    }

    @Test func aFileIsNotAProject() throws {
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults(suiteName: "editor.project.\(UUID().uuidString)")!)
        #expect(workspace.openProject(root.appendingPathComponent("README.md")) == nil)
        #expect(workspace.message?.contains("not a folder") == true)
    }

    // MARK: Machine identity

    /// One shared host key is proof: only the machine holding the private half can present it.
    @Test func aSharedHostKeyMeansTheSameMachine() {
        let shared = "SHA256:dwZSTpODvDloFr6s7D6NOzR/+JhKxFaG6jgQCzW9bKk"
        #expect(GlassMachineIdentity.isThisMachine(
            remoteFingerprints: [shared, "SHA256:other"],
            localFingerprints: ["SHA256:different", shared]))
    }

    @Test func differentKeysMeanDifferentMachines() {
        #expect(!GlassMachineIdentity.isThisMachine(
            remoteFingerprints: ["SHA256:aaa"],
            localFingerprints: ["SHA256:bbb"]))
    }

    /// **No keys is not a match.** A Vision Pro and an iPhone publish no host keys at all, and a
    /// Mac without Remote Login publishes none either. Treating "nothing on both sides" as identity
    /// would make every machine the same machine, and the editor would read local files for a
    /// folder that is not there.
    @Test func noKeysIsNeverAMatch() {
        #expect(!GlassMachineIdentity.isThisMachine(remoteFingerprints: [], localFingerprints: []))
        #expect(!GlassMachineIdentity.isThisMachine(remoteFingerprints: ["SHA256:aaa"], localFingerprints: []))
        #expect(!GlassMachineIdentity.isThisMachine(remoteFingerprints: [], localFingerprints: ["SHA256:aaa"]))
    }

    /// The catalog's own local host record (D8) is this device by construction — no key needed.
    @Test func theLocalHostRecordIsAlwaysThisMachine() {
        let reach = GlassMachineIdentity.reach(hostName: "This Mac", isLocalHostRecord: true,
                                               remoteFingerprints: [], hasTerminalService: false,
                                               localFingerprints: [])
        #expect(reach == .thisMachine)
    }

    /// The user's scenario: juliet is an SSH connection from the headset, and the same machine
    /// when you are sitting at it.
    @Test func theSameFolderIsLocalHereAndRemoteThere() {
        let julietKey = "SHA256:juliet-host-key"

        // Sitting at juliet: its host key is this machine's host key.
        let atTheMachine = GlassMachineIdentity.reach(
            hostName: "juliet", isLocalHostRecord: false,
            remoteFingerprints: [julietKey], hasTerminalService: true,
            localFingerprints: [julietKey])
        #expect(atTheMachine == .thisMachine)

        // In the headset: same project, same host record, reached over SSH.
        let inTheHeadset = GlassMachineIdentity.reach(
            hostName: "juliet", isLocalHostRecord: false,
            remoteFingerprints: [julietKey], hasTerminalService: true,
            localFingerprints: [])
        #expect(inTheHeadset == .overSSH(host: "juliet"))
    }

    /// A machine with no terminal service is named as unreachable rather than silently falling back
    /// to reading this device's own disk at that path — which would open the wrong files.
    @Test func aMachineWithNoWayInSaysSo() {
        let reach = GlassMachineIdentity.reach(hostName: "oscar", isLocalHostRecord: false,
                                               remoteFingerprints: ["SHA256:oscar"],
                                               hasTerminalService: false,
                                               localFingerprints: ["SHA256:thismac"])
        #expect(reach == .unreachable(host: "oscar"))
    }

    /// Reading a real `/etc/ssh` must not throw or hang on a device that has none.
    @Test func readingHostKeysFromAMissingDirectoryIsEmpty() {
        #expect(GlassMachineIdentity.localHostKeyFingerprints(directory: "/nonexistent/etc/ssh").isEmpty)
    }
}
