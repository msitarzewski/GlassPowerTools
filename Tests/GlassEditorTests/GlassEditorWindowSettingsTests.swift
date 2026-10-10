//
//  GlassEditorWindowSettingsTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  W23 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
//  overridden per window." An editor window keeps its own glass and text over Settings ▸ Editor and
//  Appearance; its documents follow at once, under their projects' and files' own settings; the
//  window's project keeps them on this device, so they come back when the project opens again.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("An editor window keeps its own settings")
struct GlassEditorWindowSettingsTests {

    // MARK: Fixtures

    private func defaults() -> UserDefaults {
        UserDefaults.forTest(suiteName: "editor.window-settings.\(UUID().uuidString)")!
    }

    /// A project folder with one Swift file in it.
    private func folder(_ name: String = "shop") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorWindowSettings-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("let total = 1\n".utf8).write(to: url.appendingPathComponent("main.swift"))
        return url
    }

    private func path(of url: URL) -> String {
        GlassEditorProject.normalized(url.standardizedFileURL.path(percentEncoded: false))
    }

    private func settle(_ workspace: GlassEditorWorkspace, projects: Int, turns: Int = 400) async {
        for _ in 0..<turns where workspace.projects.count < projects { await Task.yield() }
    }

    /// A window that sets something of each kind: its glass and its text.
    private var mine: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.4
        window[GlassEditorWindowSettings.fontSize] = 18
        window[GlassEditorWindowSettings.wrapsLines] = true
        return window
    }

    // MARK: What a window can keep

    @Test("the editor's three settings, under keys of its own that never change")
    func declarations() {
        #expect(GlassEditorWindowSettings.fontSize.key == "editor.fontSize")
        #expect(GlassEditorWindowSettings.showsLineNumbers.key == "editor.showsLineNumbers")
        #expect(GlassEditorWindowSettings.wrapsLines.key == "editor.wrapsLines")
        #expect(GlassEditorWindowSettings.textKeys
                == ["editor.fontSize", "editor.showsLineNumbers", "editor.wrapsLines"])
        // `appearance.*` is every window's glass, not the editor's to declare.
        #expect(GlassEditorWindowSettings.textKeys.isDisjoint(with: GlassLayerSettings.keys))
    }

    @Test("a window's text size is whole points in the editor's range, whatever a record says")
    func textSizeIsChecked() {
        var window = GlassWindowOverrides()
        window[GlassEditorWindowSettings.fontSize] = 400
        #expect(window[GlassEditorWindowSettings.fontSize] == 32)
        window[GlassEditorWindowSettings.fontSize] = 1
        #expect(window[GlassEditorWindowSettings.fontSize] == 8)
        window[GlassEditorWindowSettings.fontSize] = 14.6
        #expect(window[GlassEditorWindowSettings.fontSize] == 15)
        window[GlassEditorWindowSettings.fontSize] = .nan
        #expect(!window.sets(GlassEditorWindowSettings.fontSize), "not a number keeps nothing")
    }

    @Test("a window's text goes over Settings ▸ Editor field by field")
    func textOverlaysFieldByField() {
        var global = GlassEditorConfiguration()
        global.fontSize = 13
        global.showsLineNumbers = true
        global.wrapsLines = false
        #expect(global.overlaid(by: GlassWindowOverrides()) == global, "a window that sets nothing is the editor's")

        var window = GlassWindowOverrides()
        window[GlassEditorWindowSettings.fontSize] = 18
        let resolved = global.overlaid(by: window)
        #expect(resolved.fontSize == 18)
        #expect(resolved.showsLineNumbers, "and what the window doesn't set follows the editor")
        #expect(!resolved.wrapsLines)

        window[GlassEditorWindowSettings.showsLineNumbers] = false
        window[GlassEditorWindowSettings.wrapsLines] = true
        #expect(!global.overlaid(by: window).showsLineNumbers)
        #expect(global.overlaid(by: window).wrapsLines)
    }

    // MARK: What a window's documents use

    @Test("a document follows its file, then its project, then its window, then the editor")
    func theWindowSitsBetweenTheEditorAndTheProject() async throws {
        let runtime = GlassEditorRuntime(defaults: defaults())
        runtime.preferences.fontSize = 13
        runtime.preferences.wrapsLines = false
        let root = try folder()
        let id = try #require(runtime.openProject(root))
        let workspace = runtime.workspace(for: id)
        let document = try #require(await workspace.open(path: path(of: root) + "/main.swift"))
        let other = runtime.workspace(for: UUID())
        let elsewhere = other.newDocument()

        workspace.setWindowSettings(mine)
        #expect(document.model.configuration.fontSize == 18, "the window's size reached its document")
        #expect(document.model.configuration.wrapsLines)
        #expect(elsewhere.model.configuration.fontSize == 13, "and no other window's")

        // A project that disagrees still does: it is about the text, the window about where it's read.
        let project = try #require(workspace.projects.first)
        runtime.setTextOverrides(GlassEditorTextOverrides(fontSize: 11), forProject: project.id, in: workspace)
        #expect(document.model.configuration.fontSize == 11, "the project's size over the window's")
        #expect(document.model.configuration.wrapsLines, "the window's wrapping, which the project doesn't set")

        // And a file over both.
        workspace.setTextOverrides(GlassEditorTextOverrides(wrapsLines: false), for: document)
        #expect(!document.model.configuration.wrapsLines)

        // A document opened later starts from the window's settings too.
        let later = workspace.newDocument()
        #expect(later.model.configuration.fontSize == 18)
        #expect(later.model.configuration.wrapsLines)
    }

    @Test("⌘+, ⌘− and ⌘0 change the size a window follows: its own, else every window's")
    func textSizeKeysChangeTheSizeInFront() {
        let runtime = GlassEditorRuntime(defaults: defaults())
        runtime.preferences.fontSize = 13
        let workspace = runtime.workspace(for: UUID())

        workspace.adjustFontSize(by: 1)
        #expect(runtime.preferences.fontSize == 14, "a window that follows every window's size changes it")
        #expect(!workspace.windowSettings.sets(GlassEditorWindowSettings.fontSize))

        var own = GlassWindowOverrides()
        own[GlassEditorWindowSettings.fontSize] = 18
        workspace.setWindowSettings(own)
        let document = workspace.newDocument()
        workspace.adjustFontSize(by: 1)
        #expect(workspace.windowSettings[GlassEditorWindowSettings.fontSize] == 19)
        #expect(document.model.configuration.fontSize == 19, "the text in front got larger")
        #expect(runtime.preferences.fontSize == 14, "and every other window's size stayed")
        workspace.adjustFontSize(by: -3)
        #expect(workspace.windowSettings[GlassEditorWindowSettings.fontSize] == 16)

        workspace.resetFontSize()
        #expect(workspace.windowSettings[GlassEditorWindowSettings.fontSize] == 13, "Actual Size, for this window")
        #expect(runtime.preferences.fontSize == 14)
    }

    // MARK: Where a window keeps them

    @Test("a project's window has its settings again after a relaunch, kept on this device only")
    func aProjectsWindowComesBack() async throws {
        let storage = defaults()
        let root = try folder()
        do {
            let runtime = GlassEditorRuntime(defaults: storage)
            let id = try #require(runtime.openProject(root))
            runtime.workspace(for: id).setWindowSettings(mine)
        }

        // A new runtime over the same storage is the next launch.
        let relaunched = GlassEditorRuntime(defaults: storage)
        let id = try #require(relaunched.openProject(root))
        let workspace = relaunched.workspace(for: id)
        #expect(workspace.windowSettings == mine)
        let document = try #require(await workspace.open(path: path(of: root) + "/main.swift"))
        #expect(document.model.configuration.fontSize == 18)

        // Never in the synced list: what a window overrides is this device's own.
        let synced = String(decoding: try JSONEncoder().encode(relaunched.projects.payload), as: UTF8.self)
        #expect(!synced.contains("editor.fontSize") && !synced.contains("appearance.opacity"))
        #expect(!synced.contains("windowSettings"))
        #expect(storage.data(forKey: GlassEditorProjectLibrary.windowsDefaultsKey) != nil)
    }

    @Test("a window on another machine's project takes what it kept, once connected")
    func aRemoteProjectsWindowComesBack() async throws {
        let runtime = GlassEditorRuntime(defaults: defaults())
        runtime.remoteAccess = { @MainActor _ in
            GlassEditorRemoteFileAccess(listing: { _ in [] }, read: { _ in Data() },
                                        write: { _, _, _ in nil }, stat: { _ in nil })
        }
        let project = runtime.projects.remember(GlassEditorProject(hostID: HostID(), path: "/srv/app"))
        runtime.projects.setWindowSettings(mine, for: project.id)

        let id = try #require(runtime.openProject(project, reach: .overSSH(host: "bravo")))
        let workspace = runtime.workspace(for: id)
        await settle(workspace, projects: 1)
        #expect(workspace.windowSettings == mine)
    }

    @Test("a blank window taking a project keeps what it set, and takes the rest")
    func aBlankWindowKeepsItsOwn() throws {
        let storage = defaults()
        let root = try folder()
        do {
            let runtime = GlassEditorRuntime(defaults: storage)
            let id = try #require(runtime.openProject(root))
            runtime.workspace(for: id).setWindowSettings(mine)
        }

        let runtime = GlassEditorRuntime(defaults: storage)
        let blank = runtime.prepareNewEditorWindow()
        runtime.noteFrontmost(blank)
        var chosenHere = GlassWindowOverrides()
        chosenHere[GlassEditorWindowSettings.fontSize] = 20
        chosenHere[GlassEditorWindowSettings.showsLineNumbers] = false
        runtime.workspace(for: blank).setWindowSettings(chosenHere)

        #expect(runtime.openProject(root) == blank, "the blank window in front took the project")
        let settings = runtime.workspace(for: blank).windowSettings
        #expect(settings[GlassEditorWindowSettings.fontSize] == 20, "its own size, not the one kept")
        #expect(settings[GlassEditorWindowSettings.showsLineNumbers] == false)
        #expect(settings[GlassEditorWindowSettings.wrapsLines] == true, "and the rest the project's window kept")
        #expect(settings[GlassLayerSettings.opacity] == 0.4)
    }

    @Test("a window with no project keeps its settings while it is open, and stores nothing")
    func aWindowWithoutAProjectStoresNothing() {
        let storage = defaults()
        let runtime = GlassEditorRuntime(defaults: storage)
        let workspace = runtime.workspace(for: runtime.prepareNewEditorWindow())
        workspace.setWindowSettings(mine)
        #expect(workspace.windowSettings == mine)
        #expect(storage.data(forKey: GlassEditorProjectLibrary.windowsDefaultsKey) == nil)
    }

    @Test("a folder the list knows opens as that project: its id, name and text settings")
    func aKnownFolderOpensAsTheListsProject() throws {
        let storage = defaults()
        let root = try folder()
        let library = GlassEditorProjectLibrary(defaults: storage)
        let known = library.remember(GlassEditorProject.local(root))
        library.rename(known.id, to: "Shop Front")
        library.setTextOverrides(GlassEditorTextOverrides(fontSize: 11), for: known.id)

        let runtime = GlassEditorRuntime(defaults: storage)
        let id = try #require(runtime.openProject(root))
        let opened = try #require(runtime.workspace(for: id).projects.first)
        #expect(opened.id == known.id, "the window and the list name two different projects")
        #expect(opened.displayName == "Shop Front")
        #expect(opened.textOverrides?.fontSize == 11)
        // Opening it must not put the folder's own name and no settings back into the list.
        #expect(runtime.projects.projects.count == 1)
        #expect(runtime.projects.projects.first?.displayName == "Shop Front")
        #expect(runtime.projects.projects.first?.textOverrides?.fontSize == 11)
    }

    @Test("a machine's project opened on that machine stays one project, on that machine")
    func aMachinesProjectOpenedHereIsOneProject() throws {
        let root = try folder()
        let runtime = GlassEditorRuntime(defaults: defaults())
        let host = HostID()
        let listed = runtime.projects.remember(GlassEditorProject.local(root, hostID: host))

        let id = try #require(runtime.openProject(listed, reach: .thisMachine))
        #expect(runtime.workspace(for: id).projects.first?.id == listed.id)
        #expect(runtime.projects.projects.count == 1, "opening it here added a second, local record")
        #expect(runtime.projects.projects.first?.hostID == host, "and the list's record lost its machine")
    }

    // MARK: The device's records

    @Test("forgetting a project forgets what its window kept")
    func forgettingAProjectForgetsItsWindow() {
        let storage = defaults()
        let library = GlassEditorProjectLibrary(defaults: storage)
        let project = library.remember(GlassEditorProject(path: "/Users/x/work"))
        library.setWindowSettings(mine, for: project.id)
        #expect(library.windowSettings(for: project.id) == mine)

        library.forget(project.id)
        #expect(library.windowSettings(for: project.id).isEmpty)
        #expect(GlassEditorProjectLibrary(defaults: storage).windowSettings(for: project.id).isEmpty)
        #expect(storage.data(forKey: GlassEditorProjectLibrary.windowsDefaultsKey) == nil)
    }

    @Test("only a project in the list keeps a window, and a window that sets nothing keeps no record")
    func onlyListedProjectsKeepAWindow() {
        let storage = defaults()
        let library = GlassEditorProjectLibrary(defaults: storage)
        let stranger = UUID()
        library.setWindowSettings(mine, for: stranger)
        #expect(library.windowSettings(for: stranger).isEmpty)
        #expect(storage.data(forKey: GlassEditorProjectLibrary.windowsDefaultsKey) == nil)

        let project = library.remember(GlassEditorProject(path: "/Users/x/work"))
        library.setWindowSettings(mine, for: project.id)
        library.setWindowSettings(GlassWindowOverrides(), for: project.id)
        #expect(storage.data(forKey: GlassEditorProjectLibrary.windowsDefaultsKey) == nil)
    }

    @Test("the device's records read leniently: one bad entry costs that entry, never the rest")
    func recordsReadLeniently() throws {
        #expect(GlassEditorWindowRecords.decoded(from: Data("not json".utf8)).byProject.isEmpty)
        #expect(GlassEditorWindowRecords.decoded(from: nil).byProject.isEmpty)

        let kept = UUID(), unreadable = UUID()
        let stored: [String: Any] = [
            kept.uuidString: ["windowSettings": ["editor.fontSize": 18, "editor.future": "kept"]],
            unreadable.uuidString: "not a record",
            "not-a-project": ["windowSettings": ["editor.fontSize": 12]],
        ]
        let records = GlassEditorWindowRecords.decoded(from: try JSONSerialization.data(withJSONObject: stored))
        #expect(records.byProject.keys.sorted { $0.uuidString < $1.uuidString } == [kept])
        #expect(records.settings(for: kept)[GlassEditorWindowSettings.fontSize] == 18)
        #expect(records.settings(for: kept).keys.contains("editor.future"), "a newer build's setting survives this one")

        // And back the way it came.
        #expect(GlassEditorWindowRecords.decoded(from: records.encoded()) == records)
    }

    // MARK: What the settings say

    @Test("\"Default\" names the window when the window sets the text, and only then")
    func defaultNamesTheWindow() async throws {
        let runtime = GlassEditorRuntime(defaults: defaults())
        let root = try folder()
        let id = try #require(runtime.openProject(root))
        let workspace = runtime.workspace(for: id)
        let document = try #require(await workspace.open(path: path(of: root) + "/main.swift"))

        #expect(GlassEditorInheritedName.forFile(document, in: workspace) == GlassEditorInheritedName.editorDefaults)
        var glassOnly = GlassWindowOverrides()
        glassOnly[GlassLayerSettings.opacity] = 0.2
        workspace.setWindowSettings(glassOnly)
        #expect(GlassEditorInheritedName.forProject(in: workspace) == GlassEditorInheritedName.editorDefaults,
                "the window's glass is not its text")

        workspace.setWindowSettings(mine)
        #expect(GlassEditorInheritedName.forProject(in: workspace) == GlassEditorInheritedName.thisWindow)
        #expect(GlassEditorInheritedName.forFile(document, in: workspace) == GlassEditorInheritedName.thisWindow)
        #expect(workspace.inheritedConfiguration(for: document).fontSize == 18)

        let project = try #require(workspace.projects.first)
        runtime.setTextOverrides(GlassEditorTextOverrides(fontSize: 11), forProject: project.id, in: workspace)
        #expect(GlassEditorInheritedName.forFile(document, in: workspace) == "shop's settings")
    }

    @Test("Editor Settings opens on This Window where there are windows; a phone has none")
    func sections() {
        #expect(GlassEditorSettingsSection.offered(hasWindows: true) == [.thisWindow, .thisFile, .allEditors])
        #expect(GlassEditorSettingsSection.first(hasWindows: true) == .thisWindow)
        #expect(GlassEditorSettingsSection.offered(hasWindows: false) == [.thisFile, .allEditors])
        #expect(GlassEditorSettingsSection.first(hasWindows: false) == .thisFile)
    }
}
