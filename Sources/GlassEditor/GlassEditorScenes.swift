//
//  GlassEditorScenes.swift
//  Glass Power Tools — GlassEditor
//
//  The editor's window, and the File menu items that belong to it.
//
//  One scene on every platform: the Mac opens a window, the iPad opens a window, the headset opens
//  a panel in space, and an iPhone gets the same scene full-screen. The workspace lives on the
//  runtime rather than in the scene, so a second window is a second view of the same open
//  documents rather than a second editor that does not know about the first.
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

    public init(layers: GlassLayerStore? = nil, defaults: UserDefaults = .standard) {
        self.layers = layers ?? GlassLayerStore()
        self.defaults = defaults
        self.preferences = GlassEditorPreferences(defaults: defaults)
        self.projects = GlassEditorProjectLibrary(defaults: defaults)
    }

    /// The workspace for a window, made the first time that window asks for it.
    public func workspace(for id: UUID) -> GlassEditorWorkspace {
        if let existing = workspaces[id] { return existing }
        let workspace = GlassEditorWorkspace(preferences: preferences, defaults: defaults)
        workspaces[id] = workspace
        return workspace
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
        // it is ended on purpose.
        if closesWorkspaceWithItsWindow { workspaces[id] = nil }
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
                    close: { [weak self] in self?.closeWorkspace(id) }
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

    /// Opens a file in the window in front, or **prepares a new window** for it and returns that
    /// window's id — the hook other capabilities use (the SFTP browser's "Edit") and the one the
    /// File menu uses, which runs its own panel and so has a URL before any window exists.
    ///
    /// Returns nil when an existing window took it, so the caller knows not to open one.
    @discardableResult
    public func open(_ url: URL) -> UUID? {
        // The window is decided now and the read happens after it: reading is asynchronous for the
        // same reason a listing is, and a window that appeared only once the bytes arrived would
        // look like a click that did nothing.
        let id = frontmostWindowID ?? UUID()
        let workspace = workspace(for: id)
        Task { await workspace.open(url) }
        return id
    }

    /// The window a file should land in: the one in front, or none when there is no window at all.
    private var frontmostWindowID: UUID? {
        if let id = frontmostWorkspaceID, liveWindows.contains(id) { return id }
        return liveWindows.count == 1 ? liveWindows.first : nil
    }

    /// Opens one file on another machine — **Edit** in the Files browser, with no project around
    /// it. Returns a window to show, or nil when an existing one took it.
    @discardableResult
    public func open(path: String, on hostID: HostID, machine: String) -> UUID? {
        guard let remoteAccess else { return nil }
        let windowID = frontmostWindowID ?? UUID()
        let workspace = workspace(for: windowID)
        Task { @MainActor in
            do {
                let access = try await remoteAccess(hostID)
                await workspace.open(path: path, through: access, machine: machine)
            } catch {
                workspace.message = error.localizedDescription
            }
        }
        return windowID
    }

    /// The same, for a folder opened as a project.
    @discardableResult
    public func openProject(_ url: URL) -> UUID? {
        let window = frontmostWindowID ?? UUID()
        let opened = workspace(for: window).openProject(url)
        // Opening a folder is what puts it in the library, so the two cannot disagree about what a
        // project is: there is one way in.
        if let opened { projects.remember(opened) }
        return window
    }

    // MARK: A window's project and the durable list

    /// Whether a project a window has open is actually **in** the list.
    ///
    /// Not every route through the editor puts it there: opening a folder from the Files browser
    /// and opening one from the library both go through `openProject`, which remembers it — but
    /// `Open Project…` in an editor window opens the folder straight into the workspace, and the
    /// folder is then a project you can work in and cannot find again (reported 2026-09-18).
    /// A window that notices offers to keep it rather than doing it silently: the list is the
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

    /// The ⚡ in the editor's toolbar. Supplied by the composition root.
    public var showActiveConnections: GlassShowActiveConnections?

    /// Opens a project already in the library, wherever it lives.
    ///
    /// Returns the id of a window to open, or nil when an existing window took it — or when the
    /// project could not be opened at all, in which case the workspace carries the reason.
    @discardableResult
    public func openProject(_ project: GlassEditorProject, reach: GlassEditorProjectReach) -> UUID? {
        projects.remember(project)
        if case .thisMachine = reach {
            return openProject(URL(filePath: project.path, directoryHint: .isDirectory))
        }
        guard let hostID = project.hostID, let remoteAccess else { return nil }
        // The window comes first and fills in, because connecting is not instant and an editor
        // that appears only once the SSH handshake finishes looks like a click that did nothing.
        let windowID = frontmostWindowID ?? UUID()
        let workspace = workspace(for: windowID)
        Task { @MainActor in
            do {
                let access = try await remoteAccess(hostID)
                workspace.openProject(project, access: access, reach: reach)
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

    /// Asks for a window. Nil is a request for a new, empty one.
    public func present(_ id: UUID?) {
        requestedWindowID = id ?? UUID()
        presentationSerial += 1
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
                    presented = GlassEditorWindowPresentation(id: id)
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
                        dismissal: GlassEditorDismissal(title: "Connections") {
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
    public init(id: UUID) { self.id = id }
}

public struct GlassEditorScenes: Scene {
    private let runtime: GlassEditorRuntime

    public init(runtime: GlassEditorRuntime) { self.runtime = runtime }

    public var body: some Scene {
        // **Value-based, keyed by a window id.** That is what makes each window its own set of
        // documents: the id is the workspace's, and a new id is a new, empty editor. Opening a file
        // when no window is up creates the workspace first and then opens a window *for* it, so the
        // document is there before the window draws.
        WindowGroup("Editor", id: GlassEditorRuntime.windowID, for: UUID.self) { $id in
            let windowID = id ?? UUID()
            GlassEditorWorkspaceView(workspace: runtime.workspace(for: windowID), windowID: windowID)
                .environment(runtime)
                .glassLayers(runtime.layers)
        } defaultValue: {
            UUID()
        }
        #if os(visionOS)
        .windowStyle(.plain)
        #endif
        #if !os(iOS)
        .defaultSize(width: 1100, height: 720)
        // Not on launch: the library is the app's front door, and an editor with nothing open is
        // not a useful first thing to see.
        .defaultLaunchBehavior(.suppressed)
        #endif
        #if os(macOS)
        .commands { GlassEditorCommands(runtime: runtime) }
        #endif
    }
}

public extension GlassEditorRuntime {
    static let windowID = "editor"
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
                let id = UUID()
                runtime.workspace(for: id).newDocument()
                openWindow(id: GlassEditorRuntime.windowID, value: id)
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
            Button("Open File…") { open(directories: false) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Project…") { open(directories: true) }
                .keyboardShortcut("o", modifiers: [.command, .option])
            // **Open Recent belongs here**, not in the sidebar. The sidebar is a project's tree;
            // recents are the app's memory of what you have been in lately, which is a File-menu
            // fact on this platform and has been since long before this app (2026-09-17).
            Menu("Open Recent") {
                ForEach(runtime.preferences.recents, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        if let id = runtime.open(url) {
                            openWindow(id: GlassEditorRuntime.windowID, value: id)
                        }
                    }
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

            Button("Find in Document…") { actions?.find() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(actions == nil)
            Button("Go to Line…") { actions?.goToLine() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}

private extension GlassEditorCommands {
    /// Runs the panel, then opens what came back. Cancelling does nothing at all — no window, no
    /// trace, which is the whole point of running the panel before anything is built.
    func open(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = !directories
        panel.prompt = directories ? "Open Project" : "Open"
        panel.message = directories ? "Choose a folder to open as a project."
                                    : "Choose a file to open."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        // Into the window in front — including the empty one ⇧⌘E just made — and only into a new
        // window when there is none. `open` returns the id of a workspace it had to create.
        var newWindow: UUID?
        for url in panel.urls {
            let created = directories ? runtime.openProject(url) : runtime.open(url)
            newWindow = newWindow ?? created
        }
        if let newWindow { openWindow(id: GlassEditorRuntime.windowID, value: newWindow) }
    }
}

/// What the focused editor window can do, published so the menu bar can ask without holding a view.
@MainActor
public struct GlassEditorActions {
    public let open: () -> Void
    public let openProject: () -> Void
    public let increaseFontSize: () -> Void
    public let decreaseFontSize: () -> Void
    public let resetFontSize: () -> Void
    public let find: () -> Void
    public let goToLine: () -> Void

    public init(open: @escaping () -> Void, openProject: @escaping () -> Void,
                increaseFontSize: @escaping () -> Void,
                decreaseFontSize: @escaping () -> Void,
                resetFontSize: @escaping () -> Void,
                find: @escaping () -> Void, goToLine: @escaping () -> Void) {
        self.open = open
        self.openProject = openProject
        self.increaseFontSize = increaseFontSize
        self.decreaseFontSize = decreaseFontSize
        self.resetFontSize = resetFontSize
        self.find = find
        self.goToLine = goToLine
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
