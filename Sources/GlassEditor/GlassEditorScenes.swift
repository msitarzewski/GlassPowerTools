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
    public let layers: GlassLayerStore
    private let defaults: UserDefaults

    public init(layers: GlassLayerStore? = nil, defaults: UserDefaults = .standard) {
        self.layers = layers ?? GlassLayerStore()
        self.defaults = defaults
        self.preferences = GlassEditorPreferences(defaults: defaults)
    }

    /// The workspace for a window, made the first time that window asks for it.
    public func workspace(for id: UUID) -> GlassEditorWorkspace {
        if let existing = workspaces[id] { return existing }
        let workspace = GlassEditorWorkspace(preferences: preferences, defaults: defaults)
        workspaces[id] = workspace
        return workspace
    }

    /// The window in front, or the only one, or none.
    public var frontmostWorkspace: GlassEditorWorkspace? {
        if let id = frontmostWorkspaceID, let workspace = workspaces[id] { return workspace }
        return workspaces.count == 1 ? workspaces.values.first : nil
    }

    func noteFrontmost(_ id: UUID) { frontmostWorkspaceID = id }

    func forget(_ id: UUID) {
        workspaces[id] = nil
        if frontmostWorkspaceID == id { frontmostWorkspaceID = nil }
    }

    /// Opens a file in the window in front, or **prepares a new window** for it and returns that
    /// window's id — the hook other capabilities use (the SFTP browser's "Edit") and the one the
    /// File menu uses, which runs its own panel and so has a URL before any window exists.
    ///
    /// Returns nil when an existing window took it, so the caller knows not to open one.
    @discardableResult
    public func open(_ url: URL) -> UUID? {
        if let workspace = frontmostWorkspace {
            workspace.open(url)
            return nil
        }
        let id = UUID()
        workspace(for: id).open(url)
        return id
    }

    /// The same, for a folder opened as a project.
    @discardableResult
    public func openProject(_ url: URL) -> UUID? {
        if let workspace = frontmostWorkspace {
            workspace.openProject(url)
            return nil
        }
        let id = UUID()
        workspace(for: id).openProject(url)
        return id
    }

    /// How many editor windows are on screen.
    ///
    /// The File menu needs to know whether to open one: a freshly made, empty editor window is
    /// exactly where the file the user just chose should appear, and opening a second one beside it
    /// leaves them with two windows and one document (reported 2026-09-17). Counted by the windows
    /// themselves, because SwiftUI will not say what scenes are open.
    public private(set) var openWindowCount = 0

    func noteWindowOpened() { openWindowCount += 1 }
    func noteWindowClosed() { openWindowCount = max(0, openWindowCount - 1) }

    /// Whether a window is already showing this workspace — every window is a view of the same one.
    public var hasOpenWindow: Bool { openWindowCount > 0 }
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
            // A new id is a new workspace, so ⇧⌘E is an **empty** editor rather than a second view
            // of the documents already open.
            Button("New Editor Window") {
                openWindow(id: GlassEditorRuntime.windowID, value: UUID())
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
        CommandGroup(after: .saveItem) {
            Button("Save Document") { actions?.save() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(actions?.canSave != true)
        }
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
    public let canSave: Bool
    public let open: () -> Void
    public let openProject: () -> Void
    public let save: () -> Void
    public let increaseFontSize: () -> Void
    public let decreaseFontSize: () -> Void
    public let resetFontSize: () -> Void
    public let find: () -> Void
    public let goToLine: () -> Void

    public init(canSave: Bool, open: @escaping () -> Void, openProject: @escaping () -> Void,
                save: @escaping () -> Void,
                increaseFontSize: @escaping () -> Void,
                decreaseFontSize: @escaping () -> Void,
                resetFontSize: @escaping () -> Void,
                find: @escaping () -> Void, goToLine: @escaping () -> Void) {
        self.canSave = canSave
        self.open = open
        self.openProject = openProject
        self.save = save
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
