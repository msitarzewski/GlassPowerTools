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
import GlassShell
import GlassLayers
import GlassEditorCore

/// Owns the editor for the process. One per app, created in the composition root — the same shape
/// as every other capability's runtime.
@MainActor @Observable
public final class GlassEditorRuntime {
    public let workspace: GlassEditorWorkspace
    public let layers: GlassLayerStore

    public init(layers: GlassLayerStore? = nil, defaults: UserDefaults = .standard) {
        self.layers = layers ?? GlassLayerStore()
        self.workspace = GlassEditorWorkspace(defaults: defaults)
    }

    /// Opens a file and returns whether the editor now holds it — the hook other capabilities use
    /// (the SFTP browser's "Edit", a `.sql` file dropped on the library) without importing the
    /// editor's views.
    @discardableResult
    public func open(_ url: URL) -> Bool { workspace.open(url) != nil }
}

public struct GlassEditorScenes: Scene {
    private let runtime: GlassEditorRuntime

    public init(runtime: GlassEditorRuntime) { self.runtime = runtime }

    public var body: some Scene {
        WindowGroup("Editor", id: GlassEditorRuntime.windowID) {
            GlassEditorWorkspaceView(workspace: runtime.workspace)
                .environment(runtime)
                .glassLayers(runtime.layers)
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
            Button("New Editor Window") { openWindow(id: GlassEditorRuntime.windowID) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Open File…") {
                openWindow(id: GlassEditorRuntime.windowID)
                actions?.open()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Button("Save Document") { actions?.save() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(actions?.canSave != true)
        }
        CommandMenu("Text") {
            Button("Find in Document…") { actions?.find() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(actions == nil)
            Button("Go to Line…") { actions?.goToLine() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}

/// What the focused editor window can do, published so the menu bar can ask without holding a view.
@MainActor
public struct GlassEditorActions {
    public let canSave: Bool
    public let open: () -> Void
    public let save: () -> Void
    public let find: () -> Void
    public let goToLine: () -> Void

    public init(canSave: Bool, open: @escaping () -> Void, save: @escaping () -> Void,
                find: @escaping () -> Void, goToLine: @escaping () -> Void) {
        self.canSave = canSave
        self.open = open
        self.save = save
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
