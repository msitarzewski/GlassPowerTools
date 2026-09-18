//
//  GlassEditorRemoteFileScreen.swift
//  Glass Power Tools — GlassEditor
//
//  One file on another machine, opened in the editor on a device with no second window.
//
//  **Presented by the Files browser, not over it.** The browser holds its SSH session through a
//  lifetime object whose own comment says the rule: *"SwiftUI retains this owner through transient
//  disappearance (for example a child sheet). Only destroying the browser releases its dedicated
//  session."* A presentation raised from behind the browser's sheet dismisses that sheet, destroys
//  the browser and closes the session with it — which is what happened: the editor appeared, and
//  underneath it the browser had become "This SFTP window's source session is no longer active".
//
//  So the editor is a **child** of the browser. The browser stays alive behind it, its session
//  stays open, and Done returns to a browser that still works. It is also what the editor this
//  replaced always did: `SFTPRemoteEditorView` was a sheet attached to the browser.
//
//  Its own window id, so the file does not land in whatever workspace happens to be frontmost —
//  a phone has no frontmost editor window, and a document opened into one nobody is showing is
//  the other half of the same class of defect.
//

import SwiftUI
import GlassConnectionKit
import GlassLayers

public struct GlassEditorRemoteFileScreen: View {
    private let runtime: GlassEditorRuntime
    private let hostID: HostID
    private let machine: String
    private let path: String
    private let onDone: @MainActor () -> Void

    @State private var windowID = UUID()
    @State private var didOpen = false

    public init(runtime: GlassEditorRuntime, hostID: HostID, machine: String, path: String,
                onDone: @escaping @MainActor () -> Void) {
        self.runtime = runtime
        self.hostID = hostID
        self.machine = machine
        self.path = path
        self.onDone = onDone
    }

    public var body: some View {
        let workspace = runtime.workspace(for: windowID)
        GlassEditorWorkspaceView(
            workspace: workspace, windowID: windowID,
            dismissal: GlassEditorDismissal(title: "Files", action: done)
        )
            .environment(runtime)
            .glassLayers(runtime.layers)
            .task {
                // Once. A `task` re-runs when the view is rebuilt, and opening the same path twice
                // is harmless but the connection it makes is not free.
                guard !didOpen else { return }
                didOpen = true
                guard let remoteAccess = runtime.remoteAccess else {
                    workspace.message = "This build has no way to read files on another machine."
                    return
                }
                do {
                    let access = try await remoteAccess(hostID)
                    await workspace.open(path: path, through: access, machine: machine)
                } catch {
                    workspace.message = error.localizedDescription
                }
            }
    }

    /// Closing the screen closes the connection it opened, which is the workspace's own rule for
    /// a project and is no different for a single file.
    private func done() {
        let workspace = runtime.workspace(for: windowID)
        workspace.closeAllProjects()
        runtime.forget(windowID)
        onDone()
    }
}

/// How a presented editor is left: what to call the place it goes back to, and what to do.
public struct GlassEditorDismissal {
    public let title: String
    public let action: @MainActor () -> Void

    public init(title: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.action = action
    }
}
