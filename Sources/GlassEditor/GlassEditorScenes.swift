//
//  GlassEditorScenes.swift
//  Glass Power Tools — GlassEditor
//
//  The editor's window, and the File menu items that belong to it.
//
//  One scene on every platform: the Mac opens a window, the iPad opens a window, the headset opens
//  a panel in space, and an iPhone gets the same scene full-screen. The workspaces live on the
//  runtime, one per window, and the runtime is what decides which window something opens in:
//  one project per window, loose files as tabs in the window in front.
//

import SwiftUI
import GlassConnectionKit
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import GlassShell
import GlassLayers
import GlassEditorCore

/// Owns the editor for the process. One per app, created in the composition root — the same shape
/// as every other capability's runtime.
@MainActor @Observable
public final class GlassEditorRuntime {
    /// **One workspace per window**, not one per app.
    ///
    /// It was one, and a second window was a second view of the same open documents — so ⇧⌘E
    /// produced a window with the same tabs already in it (reported 2026-09-17: *"I'd expect a new
    /// empty editor"*). A window full of tabs is what a Mac editor *is*; two windows sharing one
    /// set of tabs is a panel pretending to be a window.
    ///
    /// Preferences and recents stay shared, because they are true of the editor rather than of one
    /// window: text size set in one window is set everywhere, and a file opened in one is recent in
    /// all of them.
    private var workspaces: [UUID: GlassEditorWorkspace] = [:]
    /// The window most recently in front, so a file opened from the menu bar lands where the user
    /// is rather than in whichever window happens to be first in a dictionary.
    private(set) var frontmostWorkspaceID: UUID?
    public let preferences: GlassEditorPreferences
    /// Every project this person has, on any device — the list that outlives a window, and the
    /// editor's entry point in the library. See `GlassEditorProjectLibrary`.
    public let projects: GlassEditorProjectLibrary
    public let layers: GlassLayerStore
    private let defaults: UserDefaults

    public init(layers: GlassLayerStore? = nil, defaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        self.layers = layers ?? GlassLayerStore()
        self.defaults = defaults
        self.preferences = GlassEditorPreferences(defaults: defaults)
        self.projects = GlassEditorProjectLibrary(defaults: defaults)
    }

    /// The workspace for a window, made the first time anything asks for it.
    ///
    /// Asking from here counts as this launch wanting that window (`issuedWindowIDs`). The
    /// window's own scene asks through `windowWorkspace(for:)`, which does not.
    public func workspace(for id: UUID) -> GlassEditorWorkspace {
        issuedWindowIDs.insert(id)
        return windowWorkspace(for: id)
    }

    /// The workspace a window shows, **without** counting as a request for that window — so a
    /// window SwiftUI brings back from an earlier launch can be told from one this launch opened.
    func windowWorkspace(for id: UUID) -> GlassEditorWorkspace {
        if let existing = workspaces[id] { return existing }
        let workspace = GlassEditorWorkspace(preferences: preferences, defaults: defaults)
        workspace.securityScope = securityScope
        // A window's own settings are kept with its project, on this device (W23).
        workspace.keepWindowSettings = { [weak self] project, settings in
            self?.projects.setWindowSettings(settings, for: project)
        }
        workspaces[id] = workspace
        return workspace
    }

    /// Every window id this launch has asked for: opened, prepared, presented or made new.
    /// Not observed: it is written while scenes draw, and nothing draws from it.
    @ObservationIgnored private var issuedWindowIDs: Set<UUID> = []

    /// A new window's id, counted as asked for — what the scene opens when it is given no value.
    func newWindowID() -> UUID {
        let id = UUID()
        issuedWindowIDs.insert(id)
        return id
    }

    /// A new window holding one new, empty document, ready to type into — what ⇧⌘E opens on a Mac
    /// and **New Document** in Projects opens elsewhere. The caller shows it: a Mac's menu opens the
    /// window directly, the library asks through `present`.
    ///
    /// Off the Mac this was missing altogether: a blank document, or a file without its folder,
    /// could be had only from inside an editor window, and an editor window only by opening a
    /// project (2026-10-09, Vision Pro).
    public func prepareNewEditorWindow() -> UUID {
        let id = newWindowID()
        workspace(for: id).newDocument()
        return id
    }

    /// A window this launch never asked for, with nothing in it — one the system brought back from
    /// an earlier launch. A workspace is never saved, so such a window can only come back empty,
    /// and blank editor windows are not restored (decided 2026-10-08). Windows with something in
    /// them are this launch's own and are never closed by this.
    func isRestoredBlankWindow(_ id: UUID) -> Bool {
        !issuedWindowIDs.contains(id) && isBlank(id)
    }

    /// How access to a picked file or folder is asked for, handed to every workspace. The system's,
    /// except in a test that counts it.
    @ObservationIgnored var securityScope = GlassEditorSecurityScope.system {
        didSet { for workspace in workspaces.values { workspace.securityScope = securityScope } }
    }

    /// Windows that are actually on screen.
    ///
    /// **Not the same set as `workspaces`.** A workspace is made the first time a window *asks*
    /// for one, which is a side effect of SwiftUI rendering — so a workspace can exist with no
    /// window in front of it, and asking `workspaces` whether a window is open answers about the
    /// wrong thing. A file opened then went into a workspace nobody was looking at, and the second
    /// Edit after closing the editor appeared to do nothing at all.
    private var liveWindows: Set<UUID> = []

    /// The window in front, or the only one, or none — counting only windows that exist.
    public var frontmostWorkspace: GlassEditorWorkspace? {
        if let id = frontmostWorkspaceID, liveWindows.contains(id), let workspace = workspaces[id] {
            return workspace
        }
        guard liveWindows.count == 1, let only = liveWindows.first else { return nil }
        return workspaces[only]
    }

    func noteFrontmost(_ id: UUID) {
        liveWindows.insert(id)
        frontmostWorkspaceID = id
    }

    /// Whether a workspace ends when its window leaves the screen.
    ///
    /// **True where windows exist and false on a phone**, and the difference is the whole point.
    /// On a Mac, closing a window closes the editor and taking the documents with it is correct.
    /// A phone has no window to close: the cover's Connections button means "go back to the
    /// library", and discarding the workspace there threw the open documents away — unsaved
    /// edits included — with nothing said and no way back to them.
    ///
    /// Settable so a test can be a phone. `GlassWindowPresentation` answers from `UIApplication`,
    /// which on the machine the suite runs on always says a Mac.
    ///
    /// **Asked when it is needed, not stored at init.** As a stored default this read
    /// `GlassWindowPresentation.canOpenWindows` inside `GlassPowerToolsApp.init` — before any
    /// scene had connected, when `UIDevice.current.userInterfaceIdiom` is still `.unspecified`.
    /// `.unspecified != .phone`, so an iPhone answered "this device has windows", the workspace
    /// was discarded on every dismissal exactly as before, and the session switcher had nothing
    /// to list. A device capability read during app construction is read before the device has
    /// answered (rules 43 and 54).
    private var closesWorkspaceWithItsWindowOverride: Bool?
    public var closesWorkspaceWithItsWindow: Bool {
        get { closesWorkspaceWithItsWindowOverride ?? GlassWindowPresentation.canOpenWindows }
        set { closesWorkspaceWithItsWindowOverride = newValue }
    }

    func forget(_ id: UUID) {
        liveWindows.remove(id)
        if frontmostWorkspaceID == id { frontmostWorkspaceID = nil }
        // Kept on a phone: the switcher is how it is reached again, and `closeWorkspace` is how
        // it is ended on purpose. **Kept anywhere while it has unsaved changes** (2026-10-17): an
        // iPad's or Vision Pro's window can be dismissed with no way to ask first, and its edits
        // went with it. Active lists it, "1 unsaved", and choosing it brings the window back. A
        // Mac asks before its window closes (`GlassWindowCloseGate`), so only a quit gets here
        // with changes, and the app goes too.
        if closesWorkspaceWithItsWindow, workspaces[id]?.hasUnsavedChanges != true { workspaces[id] = nil }
    }

    /// What closing this workspace would lose, as a sentence; nil when nothing is unsaved.
    static func unsavedChanges(in workspace: GlassEditorWorkspace) -> String? {
        let names = workspace.documents.filter(\.isDirty).map(\.displayName)
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) has changes that haven't been saved."
        default:
            let list = ListFormatter.localizedString(byJoining: names)
            return "\(names.count) documents have changes that haven't been saved: \(list)."
        }
    }

    /// Every document with unsaved changes, in every editor window: what a quit would lose.
    public var unsavedDocumentNames: [String] {
        workspaces.sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap { $0.value.documents.filter(\.isDirty).map(\.displayName) }
    }

    /// Brings forward the first window with unsaved changes — where a quit that was called off
    /// takes the person, to save them.
    public func presentFirstUnsaved() {
        guard let id = workspaces.keys.sorted(by: { $0.uuidString < $1.uuidString })
            .first(where: { workspaces[$0]?.hasUnsavedChanges == true }) else { return }
        present(id)
    }

    /// Ends a workspace deliberately: the switcher's swipe, and the only way to close one on a
    /// device with no windows. Unlike `forget`, this always discards.
    public func closeWorkspace(_ id: UUID) {
        liveWindows.remove(id)
        if frontmostWorkspaceID == id { frontmostWorkspaceID = nil }
        // Closing the projects is what releases the readers behind them — an SFTP session for a
        // project on another machine. On a Mac `onDisappear` had already done it; on a phone this
        // is the only place it happens, so dropping the workspace without it would leak the
        // connection.
        workspaces[id]?.closeAllProjects()
        workspaces[id] = nil
    }

    /// The editor's contribution to the session switcher (D1). Registered by the composition root
    /// through `registerSessionProvider`, because a file is not a service and the editor is not a
    /// `GlassCapability` — the third feature to need that escape hatch, after settings pages and
    /// library panels.
    ///
    /// An empty workspace is not listed. One is made the first time a window *asks* for one, so
    /// listing them all would offer rows for windows that never held anything.
    public func openSessions() -> [GlassOpenSession] {
        workspaces
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .compactMap { id, workspace in
                guard let title = Self.sessionTitle(of: workspace) else { return nil }
                return GlassOpenSession(
                    id: Self.sessionID(windowID: id),
                    title: title,
                    subtitle: Self.sessionSubtitle(of: workspace),
                    // A folder when it is a project and a page when it is loose files: the row
                    // should look like the thing it returns to.
                    symbolName: workspace.projects.isEmpty ? "doc.text" : "folder",
                    // The machine the files are on: the project's, or this device for a project
                    // or loose file here.
                    hostID: workspace.projects.first?.hostID ?? GlassLocalHost.id,
                    activate: { [weak self] in self?.present(id) },
                    close: { [weak self] in self?.closeWorkspace(id) },
                    unsavedChanges: { [weak workspace] in workspace.flatMap(Self.unsavedChanges(in:)) }
                )
            }
    }

    /// The id the switcher gives an editor window; its own chrome excludes itself with it.
    public static func sessionID(windowID: UUID) -> String { "editor:\(windowID.uuidString)" }

    /// What to call a window: its project, or the document in front. Nil for a workspace holding
    /// neither, which is not a session anyone can be sent back to.
    static func sessionTitle(of workspace: GlassEditorWorkspace) -> String? {
        if let project = workspace.projects.first { return project.displayName }
        if let selected = workspace.selection,
           let document = workspace.documents.first(where: { $0.id == selected }) {
            return document.displayName
        }
        return workspace.documents.first?.displayName
    }

    /// How many files, and whether any of them would be lost. The unsaved count is said out loud
    /// because keeping a workspace alive across a dismissal is precisely what protects it.
    static func sessionSubtitle(of workspace: GlassEditorWorkspace) -> String? {
        let unsaved = workspace.documents.filter(\.isDirty).count
        let files = workspace.documents.count
        let count = files == 1 ? "1 file" : "\(files) files"
        if unsaved > 0 { return "\(count) · \(unsaved) unsaved" }
        if files > 0 { return count }
        // A project row with nothing open said nothing at all, which left a name floating on its
        // own. What it is, is a project you have not opened a file in yet.
        return workspace.projects.isEmpty ? nil : "No files open"
    }

    // MARK: Where things open

    /// Opens what was chosen — files and folders together, from one Open… — and returns the
    /// windows to show, in order. The panel, the File menu, a drop, the Projects list and the Files
    /// browser all come through here, so there is one answer to "which window?".
    ///
    /// **One project per window** (owner, 2026-10-08: *"Each new project should appear in its own
    /// editor window"*). Every project used to go into the window in front, where nothing showed
    /// it: the title, the footer, the overview and the switcher read only the first project, so a
    /// second one "died in a silent whisper". A folder now goes
    /// 1. to the window that already has it open, which comes forward;
    /// 2. else to the window in front when that window is blank (`GlassEditorWorkspace.isBlank`);
    /// 3. else to a new window.
    ///
    /// **Files are tabs in the window in front**, as they always were, or a new window when there
    /// is none. They are placed first, so a blank window taking the files does not also take a
    /// folder chosen beside them: a window holding loose files does not take a project.
    ///
    /// `window` is the window asking, when one is — its own Open… or a drop on it — and it is "in
    /// front" for this call. Off the Mac the runtime cannot tell which window has focus.
    ///
    /// The window is decided now and the reading happens after: a window that appeared only once
    /// the bytes arrived would look like a click that did nothing.
    @discardableResult
    public func open(urls: [URL], from window: UUID? = nil) -> [UUID] {
        var files: [URL] = []
        var folders: [URL] = []
        for url in urls {
            if securityScope.isFolder(url) { folders.append(url) } else { files.append(url) }
        }
        var shown: [UUID] = []
        if !files.isEmpty {
            let id = window ?? frontmostWindowID ?? UUID()
            let workspace = workspace(for: id)
            beginPending(id)
            Task { @MainActor in
                // In the order chosen, so the tabs are too.
                for url in files { await workspace.open(url) }
                self.endPending(id)
            }
            shown.append(id)
        }
        for folder in folders {
            let id = openFolder(folder, from: window)
            if !shown.contains(id) { shown.append(id) }
        }
        return shown
    }

    /// One file or folder; see `open(urls:from:)`. The id is the window to show — including one
    /// already on screen, so the caller can bring it forward.
    @discardableResult
    public func open(_ url: URL) -> UUID? {
        open(urls: [url]).first
    }

    /// A folder on this device, opened as a project; see `open(urls:from:)`.
    @discardableResult
    public func openProject(_ url: URL) -> UUID? {
        openFolder(url, from: nil)
    }

    /// The window a file should land in: the one in front, or none when there is no window at all.
    private var frontmostWindowID: UUID? {
        if let id = frontmostWorkspaceID, liveWindows.contains(id) { return id }
        return liveWindows.count == 1 ? liveWindows.first : nil
    }

    /// Opens one file on another machine — **Edit** in the Files browser, with no project around
    /// it — as a tab in the window in front. Returns the window to show.
    @discardableResult
    public func open(path: String, on hostID: HostID, machine: String) -> UUID? {
        guard let remoteAccess else { return nil }
        let windowID = frontmostWindowID ?? UUID()
        let workspace = workspace(for: windowID)
        beginPending(windowID)
        Task { @MainActor in
            defer { self.endPending(windowID) }
            do {
                let access = try await remoteAccess(hostID)
                await workspace.open(path: path, through: access, machine: machine)
            } catch {
                workspace.message = error.localizedDescription
            }
        }
        return windowID
    }

    /// A folder on this device, in the window the rule picks.
    ///
    /// Opening a folder is what puts it in the library, so the two cannot disagree about what a
    /// project is: there is one way in. A folder that needed granted access — one picked from
    /// Files — also leaves this device a bookmark, so it opens again from the list after a
    /// relaunch.
    ///
    /// The folder opens as the project the list already has for it — `known`, or the one it lists
    /// at that path — so the window, the list and whatever is kept by the project's id agree on
    /// which project it is; and the window takes what it set last time it showed that project here.
    private func openFolder(_ url: URL, from asking: UUID?, known: GlassEditorProject? = nil) -> UUID {
        securityScope.withAccess(to: url) { scoped in
            let path = url.standardizedFileURL.path(percentEncoded: false)
            let place = ProjectPlace(path: path, hostID: nil)
            let target = window(holding: place) ?? windowForNewProject(from: asking)
            let workspace = workspace(for: target)
            if let opened = workspace.openProject(url, as: known ?? projects.project(at: path, on: nil)) {
                let kept = projects.remember(opened)
                if scoped { projects.keepBookmark(of: url, forPath: opened.path) }
                workspace.takeWindowSettings(projects.windowSettings(for: kept.id))
            }
            return target
        }
    }

    /// A folder on a machine, for telling whether it is already open somewhere. `hostID` nil is
    /// this device, whatever the project record calls it: the reach decides which machine it is.
    struct ProjectPlace: Hashable {
        let path: String
        let hostID: HostID?

        init(path: String, hostID: HostID?) {
            self.path = GlassEditorProject.normalized(path)
            self.hostID = hostID
        }
    }

    /// Windows waiting on something they were given: files still being read, or a project still
    /// connecting. Neither is in the workspace yet, and a window waiting for one is not blank.
    @ObservationIgnored private var pendingOpens: [UUID: Int] = [:]
    @ObservationIgnored private var pendingProjects: [UUID: ProjectPlace] = [:]

    private func beginPending(_ id: UUID) { pendingOpens[id, default: 0] += 1 }

    private func endPending(_ id: UUID) {
        let remaining = (pendingOpens[id] ?? 1) - 1
        pendingOpens[id] = remaining > 0 ? remaining : nil
    }

    /// The window with this folder open — or on its way to being open — in any workspace this
    /// device keeps. On a phone those are the switcher's sessions, kept after their screen goes.
    private func window(holding place: ProjectPlace) -> UUID? {
        if let pending = pendingProjects.first(where: { $0.value == place }) { return pending.key }
        return workspaces.first { $0.value.holdsProject(at: place.path, on: place.hostID) }?.key
    }

    /// The window in front when it is blank, emptied of its untouched Untitled; else a new one.
    private func windowForNewProject(from asking: UUID?) -> UUID {
        guard let front = asking ?? frontmostWindowID, isBlank(front) else { return UUID() }
        workspaces[front]?.discardUntouchedUntitled()
        return front
    }

    private func isBlank(_ id: UUID) -> Bool {
        guard pendingOpens[id] == nil, pendingProjects[id] == nil else { return false }
        return workspaces[id]?.isBlank ?? true
    }

    /// Where a project on this device is, as this device can reach it: through the bookmark kept
    /// when its folder was picked from Files, else its path.
    func localURL(for project: GlassEditorProject) -> URL {
        guard let found = projects.bookmarkedURL(forPath: project.path) else {
            return URL(filePath: project.path, directoryHint: .isDirectory)
        }
        if found.isStale {
            // Remade while access is held, which is the only time it can be.
            securityScope.withAccess(to: found.url) { scoped in
                if scoped { projects.keepBookmark(of: found.url, forPath: project.path) }
            }
        }
        return found.url
    }

    /// Whether a project's folder on this device is still there — asked with the access a folder
    /// picked from Files needs, which a plain look at its path does not have.
    public func localFolderExists(_ project: GlassEditorProject) -> Bool {
        securityScope.isFolder(localURL(for: project))
    }

    // MARK: A window's project and the durable list

    /// Whether a project a window has open is actually **in** the list.
    ///
    /// Every route in remembers it now — Open…, a drop, the Files browser and the library all go
    /// through `open(urls:from:)` or `openProject` (2026-10-08). It used not to: `Open Project…` in
    /// an editor window opened the folder straight into the workspace, and the folder was then a
    /// project you could work in and could not find again (reported 2026-09-18). A project can
    /// still be open and out of the list — removed from it while its window was open — and a
    /// window that notices offers to keep it rather than doing it silently: the list is the
    /// user's, and it syncs to their other devices.
    public func isRemembered(_ project: GlassEditorProject) -> Bool {
        projects.project(at: project.path, on: project.hostID) != nil
    }

    /// Keeps it — the act behind that offer.
    @discardableResult
    public func remember(_ project: GlassEditorProject) -> GlassEditorProject {
        projects.remember(project)
    }

    /// One project's name, changed in the window and in the list together. The sheet used to
    /// rename only the window's copy, so the new name was gone at the next launch.
    public func rename(_ id: GlassEditorProject.ID, to name: String,
                       in workspace: GlassEditorWorkspace) {
        workspace.rename(id, to: name)
        projects.rename(id, to: name)
    }

    /// One project's text settings, likewise: the open window follows immediately, the list keeps
    /// it and carries it to the other devices.
    public func setTextOverrides(_ overrides: GlassEditorTextOverrides,
                                 forProject id: GlassEditorProject.ID,
                                 in workspace: GlassEditorWorkspace) {
        workspace.setTextOverrides(overrides, forProject: id)
        projects.setTextOverrides(overrides, for: id)
    }

    /// How a machine other than this one is reached, supplied by whatever owns SSH.
    ///
    /// The editor does not import the terminal: SFTP belongs to the capability that owns the
    /// connection, the trust prompt and the session. Nil means this build has no way to reach
    /// another machine, and a remote project says so rather than failing quietly.
    public var remoteAccess: ((HostID) async throws -> any GlassEditorFileAccess)?

    /// Favorites, for a project's star (2026-10-13). Supplied by the composition root.
    public var favorites: GlassFavoritesAccess?

    /// The ⚡ in the editor's toolbar. Supplied by the composition root.
    public var showActiveConnections: GlassShowActiveConnections?

    /// Opens a project already in the library, wherever it lives, by the rule in
    /// `open(urls:from:)`: its own window, or the window that already has it.
    ///
    /// Returns the id of the window to show — one already on screen included, so it comes
    /// forward — or nil when this build cannot reach the machine at all. A project that could not
    /// be opened says why in the window.
    @discardableResult
    public func openProject(_ project: GlassEditorProject, reach: GlassEditorProjectReach) -> UUID? {
        let project = projects.remember(project)
        if case .thisMachine = reach {
            return openFolder(localURL(for: project), from: nil, known: project)
        }
        guard let hostID = project.hostID, let remoteAccess else { return nil }
        let place = ProjectPlace(path: project.path, hostID: hostID)
        // Already open, or still connecting: that window comes forward and nothing connects twice.
        if let holder = window(holding: place) { return holder }
        // The window comes first and fills in, because connecting is not instant and an editor
        // that appears only once the SSH handshake finishes looks like a click that did nothing.
        let windowID = windowForNewProject(from: nil)
        let workspace = workspace(for: windowID)
        pendingProjects[windowID] = place
        Task { @MainActor in
            defer { if self.pendingProjects[windowID] == place { self.pendingProjects[windowID] = nil } }
            do {
                let access = try await remoteAccess(hostID)
                let opened = workspace.openProject(project, access: access, reach: reach)
                workspace.takeWindowSettings(self.projects.windowSettings(for: opened.id))
            } catch {
                workspace.message = error.localizedDescription
            }
        }
        return windowID
    }

    /// A window something has asked to be shown, and the count that makes a repeat request
    /// visible even when it names the same window.
    ///
    /// Requested rather than opened directly, because **not every platform can open a window.**
    /// An iPhone has one scene: `openWindow` there does nothing at all, silently, so a Projects
    /// panel that called it would list projects and refuse to open any of them. The bootstrap
    /// below decides — a window where windows exist, a full-screen presentation where they do not.
    public private(set) var requestedWindowID: UUID?
    public private(set) var presentationSerial = 0
    /// On a phone, where the window covers the screen, what its back button says it returns to:
    /// the screen that asked. Nil is Connections.
    public private(set) var requestedReturnTitle: String?

    /// Asks for a window. Nil is a request for a new, empty one.
    public func present(_ id: UUID?, returningTo returnTitle: String? = nil) {
        let id = id ?? newWindowID()
        issuedWindowIDs.insert(id)
        requestedWindowID = id
        requestedReturnTitle = returnTitle
        presentationSerial += 1
    }

    /// Shows the windows an open named: each as a window where windows exist; on a phone, the last
    /// of them in place, since only one is on screen. One rule for an editor window's own Open…
    /// and for the library's.
    public func show(_ windows: [UUID], with openWindow: OpenWindowAction) {
        if GlassWindowPresentation.canOpenWindows {
            for id in windows { openWindow(id: Self.windowID, value: id) }
        } else if let last = windows.last {
            present(last)
        }
    }

    /// Clears the request once something has shown it.
    public func clearPresentation() {
        requestedWindowID = nil
    }

    /// How many editor windows are on screen. Counted by the windows themselves, because SwiftUI
    /// will not say what scenes are open.
    public var openWindowCount: Int { liveWindows.count }

    public var hasOpenWindow: Bool { !liveWindows.isEmpty }
}

/// Wraps the library so the editor can be presented on a platform with no second window.
///
/// The three other capabilities each have one of these (`GlassTerminalBootstrap`,
/// `GlassDatabaseBootstrap`, `GlassDesktopBootstrap`) and for the same reason: a capability's
/// surface has to arrive *somewhere*, and where depends on the platform rather than on the
/// capability. `supportsMultipleScenes` is the runtime answer rather than an `#if`, because the
/// difference is iPhone against iPad and both are `os(iOS)`.
public struct GlassEditorBootstrap<Content: View>: View {
    private let runtime: GlassEditorRuntime
    private let content: Content
    @Environment(\.openWindow) private var openWindow

    public init(runtime: GlassEditorRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    /// The window to show in place, held here rather than read back out of the runtime through a
    /// computed `Binding`.
    ///
    /// A binding's getter is a closure, so it does not run while the body is being evaluated and
    /// registers no dependency on what it reads. The presentation therefore never arrived: the
    /// runtime's request changed, and nothing in this view had asked to be told. `@State` set from
    /// an `onChange` is the shape the desktop's session uses, and it works because the change is
    /// observed where SwiftUI can see it.
    @State private var presented: GlassEditorWindowPresentation?

    public var body: some View {
        base
            .onChange(of: runtime.presentationSerial) { _, _ in
                guard let id = runtime.requestedWindowID else { return }
                if Self.canOpenWindows {
                    openWindow(id: GlassEditorRuntime.windowID, value: id)
                    runtime.clearPresentation()
                } else {
                    presented = GlassEditorWindowPresentation(id: id,
                                                              returnTitle: runtime.requestedReturnTitle ?? "Connections")
                }
            }
    }

    @ViewBuilder
    private var base: some View {
        #if os(iOS)
        content
            .fullScreenCover(item: $presented, onDismiss: { runtime.clearPresentation() }) { window in
                let id = window.id
                if true {
                    // **No `NavigationStack` around it.** The editor is a `NavigationSplitView`,
                    // and one nested inside a navigation stack draws its toolbar and none of its
                    // content on an iPhone — a black screen under a working navigation bar. Done
                    // is the view's own toolbar item instead.
                    GlassEditorWorkspaceView(
                        workspace: runtime.workspace(for: id), windowID: id,
                        dismissal: GlassEditorDismissal(title: window.returnTitle) {
                            presented = nil
                        }
                    )
                        .environment(runtime)
                        .glassLayers(runtime.layers)
                }
            }
        #else
        content
        #endif
    }

    /// Whether this device has more than one scene to put a window in. Shared with every other
    /// capability that opens windows, because they all have to ask it.
    static var canOpenWindows: Bool { GlassWindowPresentation.canOpenWindows }
}

/// One editor window on its way to a full-screen presentation.
public struct GlassEditorWindowPresentation: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// What its back button returns to.
    public let returnTitle: String
    public init(id: UUID, returnTitle: String = "Connections") {
        self.id = id
        self.returnTitle = returnTitle
    }
}

/// Shows the editor window something asked for (`GlassEditorRuntime.present`), from whichever
/// window carries it.
///
/// **Not only the Connections window.** That was the one place a request was answered, so with
/// Connections closed, Open in Editor in the Files browser opened a project into a window nothing
/// ever showed. Every editor window and the Mac's Files window carry one too; the first to see a
/// request shows it and clears it, so the others find nothing to do.
struct GlassEditorWindowPresenter: ViewModifier {
    let runtime: GlassEditorRuntime
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: runtime.presentationSerial) { _, _ in
                // Where there are no windows the bootstrap presents in place; this has nothing to add.
                guard GlassWindowPresentation.canOpenWindows,
                      let id = runtime.requestedWindowID else { return }
                openWindow(id: GlassEditorRuntime.windowID, value: id)
                runtime.clearPresentation()
            }
    }
}

public extension View {
    /// Lets this window show the editor windows other surfaces ask for — the Files browser's Open
    /// in Editor, the Projects list — while the Connections window is closed.
    func glassEditorWindowPresenter(_ runtime: GlassEditorRuntime) -> some View {
        modifier(GlassEditorWindowPresenter(runtime: runtime))
    }
}

/// Closes an editor window the system brought back from an earlier launch with nothing in it.
///
/// Blank editor windows are not restored (decided 2026-10-08), and nothing in a workspace is
/// saved, so a restored editor window is always blank. The Mac and the headset are told not to
/// restore the scene at all; an iPad cannot be (`SceneRestorationBehavior.disabled` does not exist
/// there), so the window closes as it arrives. **Alone, it hands over to Connections first** — the
/// app's front door — rather than closing the only window and leaving nothing on screen.
struct GlassEditorRestoredWindowGuard: ViewModifier {
    let runtime: GlassEditorRuntime
    let windowID: UUID
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .task {
                guard runtime.isRestoredBlankWindow(windowID) else { return }
                if UIApplication.shared.connectedScenes.count <= 1 { openWindow.openConnections() }
                dismissWindow()
            }
            #endif
    }
}

public struct GlassEditorScenes: Scene {
    private let runtime: GlassEditorRuntime

    public init(runtime: GlassEditorRuntime) { self.runtime = runtime }

    public var body: some Scene {
        // **Value-based, keyed by a window id.** That is what makes each window its own set of
        // documents: the id is the workspace's, and a new id is a new, empty editor. Opening a file
        // when no window is up creates the workspace first and then opens a window *for* it, so the
        // document is there before the window draws.
        //
        // **Still a value-keyed group on the headset**, never a singleton `Window`: visionOS once
        // handed the app two saved sessions for one, and SwiftUI stops the app on the second.
        WindowGroup("Editor", id: GlassEditorRuntime.windowID, for: UUID.self) { $id in
            // Never nil: `defaultValue` gives a window opened without one its id.
            let windowID = id
            // `windowWorkspace`, not `workspace`: drawing a window is not this launch asking for
            // it, which is how a window restored from an earlier launch is recognised.
            GlassEditorWorkspaceView(workspace: runtime.windowWorkspace(for: windowID), windowID: windowID)
                .environment(runtime)
                .glassLayers(runtime.layers)
                .glassEditorWindowPresenter(runtime)
                .glassRegistersWindowOpener()
                .modifier(GlassEditorRestoredWindowGuard(runtime: runtime, windowID: windowID))
        } defaultValue: {
            runtime.newWindowID()
        }
        #if os(visionOS)
        .windowStyle(.plain)
        #endif
        #if !os(iOS)
        .defaultSize(width: 1100, height: 720)
        // Not on launch: the library is the app's front door, and an editor with nothing open is
        // not a useful first thing to see.
        .defaultLaunchBehavior(.suppressed)
        // Nor after a relaunch (decided 2026-10-08). A workspace is never saved, so every editor
        // window brought back was a blank one; windows with work in them never came back with it.
        // An iPad cannot say this per scene, so there `GlassEditorRestoredWindowGuard` closes them.
        .restorationBehavior(.disabled)
        #endif
        #if os(macOS)
        .commands { GlassEditorCommands(runtime: runtime) }
        #endif
    }
}

public extension GlassEditorRuntime {
    static let windowID = "editor"

    #if DEBUG
    /// Screenshots only (App/GlassDemoMode.swift): an editor window's own settings (W23) — lighter
    /// glass, larger text, long lines wrapped — over the demo's Appearance and Settings ▸ Editor.
    static var demoWindowSettings: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.45
        window[GlassEditorWindowSettings.fontSize] = 17
        window[GlassEditorWindowSettings.wrapsLines] = true
        return window
    }
    #endif
}

#if os(macOS)
/// The editor's File items, **appended** to the shell's New group rather than replacing it
/// (rule 34). ⌘N stays the shell's one contextual New; when an editor window is focused it means
/// a new document, which is what `\.glassNewItem` is for.
struct GlassEditorCommands: Commands {
    let runtime: GlassEditorRuntime
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.glassEditorActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            // A new id is a new workspace, so ⇧⌘E is a fresh editor rather than a second view of
            // the documents already open — and it opens **on a new, empty document**, ready to
            // type into. An editor with nothing in it asked for a second step (⌘N) before it was
            // any use (2026-09-25: *"Shift-command-e should open a new blank text document, ready
            // to edit"*). Opening a file or project from there is File ▸ Open, as before.
            Button("New Editor Window") {
                openWindow(id: GlassEditorRuntime.windowID, value: runtime.prepareNewEditorWindow())
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            // **The panel first, a window only on a successful pick.**
            //
            // These used to call `openWindow` and then ask the focused window to present a
            // `fileImporter` — a view modifier, so a view had to exist before the panel could be
            // shown. That put an empty editor window on screen before the panel, and left it there
            // when the panel was cancelled. `NSOpenPanel` needs no window, so the order can be the
            // one a person expects: choose something, and only then does a window appear.
            // ⌘O, the key every Mac application opens something with. It runs its own panel, so it
            // works from any window in this app — including an editor with nothing in it, which is
            // where it was first found not to (2026-09-17).
            //
            // **One Open… for files and folders.** There was an Open Project… on ⌥⌘O beside it,
            // which asked the user to know in advance what the panel would decide anyway
            // (2026-10-08: *"we've just asked the user to remember something that can be decided
            // at selection time"*). A folder chosen here is a project in a window of its own.
            Button("Open…") { show(GlassEditorOpenPanel.run(runtime: runtime)) }
                .keyboardShortcut("o", modifiers: .command)
            // **Open Recent belongs here**, not in the sidebar. The sidebar is a project's tree;
            // recents are the app's memory of what you have been in lately, which is a File-menu
            // fact on this platform and has been since long before this app (2026-09-17). Folders
            // are listed too, and open as the projects they were.
            Menu("Open Recent") {
                ForEach(runtime.preferences.recents, id: \.self) { url in
                    Button(url.lastPathComponent) { show(runtime.open(urls: [url])) }
                }
                if !runtime.preferences.recents.isEmpty { Divider() }
                Button("Clear Menu") { runtime.preferences.clearRecents() }
                    .disabled(runtime.preferences.recents.isEmpty)
            }
            .disabled(runtime.preferences.recents.isEmpty)
        }
        // No Save here: ⌘S is the shell's one File ▸ Save, and an editor window publishes
        // `\.glassSaveItem` so that there it saves the document in front. It was "Save Document"
        // on ⌥⌘S, which left ⌘S — the key everyone presses — beeping in an editor (2026-09-25).
        CommandMenu("Text") {
            // The terminal's shape, key for key (`MacWorkspaceCommands`): ⌘+ with a hidden ⌘=
            // alternate so the unshifted key works too, and ⌘− to go back down.
            Button("Increase Text Size") { actions?.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(actions == nil)
            Button("Increase Text Size") { actions?.increaseFontSize() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(actions == nil)
                .hidden()
            Button("Decrease Text Size") { actions?.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(actions == nil)
            Button("Actual Size") { actions?.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(actions == nil)

            Divider()

            Button("Go to Line…") { actions?.goToLine() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(actions == nil)

            Divider()

            // What changed since the last commit (2026-10-23), on VS Code's key for it.
            Button("Show Changes") { actions?.showChanges?() }
                .keyboardShortcut("g", modifiers: [.control, .shift])
                .disabled(actions?.showChanges == nil)
        }
    }
}

private extension GlassEditorCommands {
    /// Brings forward, or opens, each window an open named — the one in front included, which is
    /// where files go.
    func show(_ windows: [UUID]) {
        for id in windows { openWindow(id: GlassEditorRuntime.windowID, value: id) }
    }
}

/// The Mac's one Open…: files and folders in one panel, and what is chosen decides what happens to
/// it (`GlassEditorRuntime.open(urls:from:)`). The File menu and an empty editor window's own
/// Open… both run this, so they cannot drift apart.
@MainActor
enum GlassEditorOpenPanel {
    /// Runs the panel, then opens what came back, and returns the windows to show. Cancelling
    /// returns none — no window, no trace, which is the whole point of running the panel before
    /// anything is built.
    static func run(runtime: GlassEditorRuntime, from window: UUID? = nil) -> [UUID] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"
        panel.message = "Choose files to open, or a folder to open as a project."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return [] }
        return runtime.open(urls: panel.urls, from: window)
    }
}

/// What the focused editor window can do, published so the menu bar can ask without holding a view.
/// Open… is not here: the menu runs its own panel, so it works with no editor window at all.
@MainActor
public struct GlassEditorActions {
    public let increaseFontSize: () -> Void
    public let decreaseFontSize: () -> Void
    public let resetFontSize: () -> Void
    public let goToLine: () -> Void
    /// The project's Changes tab; nil when the window's project is in no repository.
    public let showChanges: (() -> Void)?

    public init(increaseFontSize: @escaping () -> Void,
                decreaseFontSize: @escaping () -> Void,
                resetFontSize: @escaping () -> Void,
                goToLine: @escaping () -> Void,
                showChanges: (() -> Void)? = nil) {
        self.increaseFontSize = increaseFontSize
        self.decreaseFontSize = decreaseFontSize
        self.resetFontSize = resetFontSize
        self.goToLine = goToLine
        self.showChanges = showChanges
    }
}

private struct GlassEditorActionsKey: FocusedValueKey {
    typealias Value = GlassEditorActions
}

public extension FocusedValues {
    var glassEditorActions: GlassEditorActions? {
        get { self[GlassEditorActionsKey.self] }
        set { self[GlassEditorActionsKey.self] = newValue }
    }
}
#endif
