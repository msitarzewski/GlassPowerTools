//
//  GlassTerminalScenes.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's window scenes (glas_shApp.swift:99-280), minus the Connections window and Settings,
//  which the shell owns. The app includes this scene next to the shell's.
//

import SwiftUI
import GlassShell
import GlassLayers

public struct GlassTerminalScenes: Scene {
    private let runtime: GlassTerminalRuntime
    private var sessionManager: SessionManager { runtime.sessionManager }
    private var settingsManager: SettingsManager { runtime.settingsManager }
    private var windowRecoveryManager: WindowRecoveryManager { runtime.windowRecoveryManager }
    /// Something another capability needs present in the Mac's Files window — the editor's window
    /// presenter, so Open in Editor shows its window while Connections is closed. Supplied by the
    /// composition root, the only place that knows both; the terminal never learns what it is.
    private let filesWindowAccessory: (@MainActor () -> AnyView)?

    public init(runtime: GlassTerminalRuntime,
                filesWindowAccessory: (@MainActor () -> AnyView)? = nil) {
        self.runtime = runtime
        self.filesWindowAccessory = filesWindowAccessory
    }

    public var body: some Scene {
        #if os(macOS) || os(visionOS)
        // **No Workgroups window** (owner, 2026-10-08: "It's weird that we have a separate window
        // for that anyway"). Workgroups is a panel in the Connections window's sidebar; its menu
        // items open that panel (`TerminalLibraryCommands`). The window was a second copy of the
        // panel with a split view and toolbar of its own, and resizing it crashed the app.
        Window("Tailscale", id: "terminal-tailscale") {
            GlassLayeredWindow {
                TerminalTailscaleView()
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
            }
            .glassLayers(runtime.layers)
        }
        .defaultSize(width: 900, height: 600)
        // The Library menu (and Window ▸ Workgroups) rode on the Workgroups window's scene.
        .commands { TerminalLibraryCommands(runtime: runtime) }
        #endif
        #if os(macOS)
        WindowGroup("Terminal", id: "workspace", for: MacWorkspaceLaunchRequest.self) { $request in
            MacWorkspaceSceneRoot(request: request)
                // The reopen list and the launch offer, if this is the first window of the launch:
                // Connections need not have appeared (W12).
                .modifier(MacLaunchReopen(asker: "a terminal window"))
                .environment(runtime)
                .environment(sessionManager)
                .environment(settingsManager)
                .glassLayers(runtime.layers)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.suppressed)
        // The app reopens these windows from its own records, which know their tabs. macOS's
        // restoration brought them back as empty "New Terminal" windows instead, and stood in for
        // the windows the app would have opened (2026-10-09).
        .restorationBehavior(.disabled)
        .commands { MacWorkspaceCommands(sessionManager: sessionManager) }
        // **Glass, like every other window.** The browser was the one window painting an opaque
        // surface of its own: `.glassLayers` gave it the *state* and nothing painted it, because
        // painting is `GlassLayeredWindow`'s job and this scene never wrapped its content in one
        // (reported 2026-09-18, beside a translucent library window).
        WindowGroup(id: "sftp", for: SFTPBrowserContext.self) { $context in
            GlassLayeredWindow {
                if let context, sessionManager.session(for: context.sessionID) != nil {
                    SFTPBrowserView(sessionID: context.sessionID, initialPath: context.initialPath)
                        .environment(sessionManager)
                        .environment(settingsManager)
                        .environment(\.glassOpenFolderAsProject, runtime.openFolderAsProject)
                        .environment(\.glassOpenFileInEditor, runtime.openFileInEditor)
                        .environment(\.glassEditorFileScreen, runtime.editorFileScreen)
                    .glassLayers(runtime.layers)
                } else {
                    SFTPBrowserNotFoundView(context: context)
                }
            }
            .glassLayers(runtime.layers)
            .background { filesWindowAccessory?() }
        }
        .defaultSize(width: 820, height: 620)
        #if DEBUG
        WindowGroup(id: "html-preview", for: HTMLPreviewContext.self) { $context in
            if let context {
                HTMLPreviewWindow(context: context)
                    .environment(sessionManager)
            } else {
                HTMLPreviewNotFoundView(context: context)
            }
        }
        .defaultSize(width: 1000, height: 760)
        #endif
        #elseif os(visionOS)
        WindowGroup(id: "terminal", for: UUID.self) { $workgroupID in
            if let workgroupID {
                VisionTerminalWorkgroupView(workgroupID: workgroupID)
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
                    .trackWindowPresence(key: "terminal-workgroup-\(workgroupID.uuidString)", recovery: windowRecoveryManager)
                    // W15: an open window comes back after a relaunch; one closed by hand does not.
                    // The app's own list, not the system's restoration, which stays off below.
                    .modifier(TerminalWorkgroupWindowPresence(workgroupID: workgroupID))
            } else {
                ContentUnavailableView(
                    "Terminal Workgroup Not Found",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Open a terminal from Connections to begin.")
                )
                .trackWindowPresence(key: "terminal-workgroup-missing", recovery: windowRecoveryManager)
            }
        }
        // Plain, with Apple's glass drawn by the window itself (`VisionTerminalWindowGlass`), in
        // Apple's corner, as strong as the window's Blur. The system's own window (cfd5094) gave
        // the canvas a corner to nest in, but its glass is always there while the window has
        // focus, so the clearest a terminal could be was Apple's glass. The owner, on the headset
        // (2026-10-10): "We've lost complete transparency ... 100% transparent glass (the whole
        // point of the app)". At Blur 0 the window is completely clear again.
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 800)
        .restorationBehavior(.disabled)
        .commands { PlatformTerminalCommands() }
        Window("", id: "minimized") {
            MinimizedConnectionsView()
                .trackWindowPresence(key: "minimized", recovery: windowRecoveryManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 160, height: 160)
        .restorationBehavior(.disabled)
        #if DEBUG
        WindowGroup(id: "html-preview", for: HTMLPreviewContext.self) { $context in
            if let context {
                HTMLPreviewWindow(context: context)
                    .environment(sessionManager)
                    .trackWindowPresence(key: "html-preview-\(context.sessionID.uuidString)", recovery: windowRecoveryManager)
            } else {
                HTMLPreviewNotFoundView(context: context)
                    .trackWindowPresence(key: "html-preview-missing", recovery: windowRecoveryManager)
            }
        }
        // The system's window: a web page wants no transparency, and its glass and shape are the
        // system's (W16). It was `.plain` with a 28-point glass of its own drawn inside.
        .defaultSize(width: 1000, height: 800)
        .restorationBehavior(.disabled)
        #endif
        // Glass here too, for the same reason as the Mac's: `.windowStyle(.plain)` means the
        // scene paints nothing at all of its own. **Still `.plain`, on purpose** (W16, 2026-10-09):
        // here the browser's own system glass lies *over* the theme paint, so the opacity setting
        // tints the glass. In the system's window the paint lies over the window's glass instead,
        // and the same setting read nearly black in the simulator. The plain window's missing
        // shape is `GlassLayeredWindow`'s to supply (`GlassWindowShape`).
        WindowGroup(id: "sftp", for: SFTPBrowserContext.self) { $context in
            GlassLayeredWindow {
                if let context, sessionManager.session(for: context.sessionID) != nil {
                    SFTPBrowserView(sessionID: context.sessionID, initialPath: context.initialPath)
                        .environment(sessionManager)
                        .environment(settingsManager)
                        .environment(\.glassOpenFolderAsProject, runtime.openFolderAsProject)
                        .environment(\.glassOpenFileInEditor, runtime.openFileInEditor)
                        .environment(\.glassEditorFileScreen, runtime.editorFileScreen)
                    .glassLayers(runtime.layers)
                        .trackWindowPresence(key: "sftp-\(context.sessionID.uuidString)", recovery: windowRecoveryManager)
                } else {
                    SFTPBrowserNotFoundView(context: context)
                        .trackWindowPresence(key: "sftp-missing", recovery: windowRecoveryManager)
                }
            }
            .glassLayers(runtime.layers)
        }
        .windowStyle(.plain)
        .defaultSize(width: 700, height: 500)
        .restorationBehavior(.disabled)
        ImmersiveSpace(id: "focus-environment") {
            FocusEnvironmentView()
        }
        .immersionStyle(selection: .constant(.progressive), in: .progressive)
        .restorationBehavior(.disabled)
        #endif
    }
}
