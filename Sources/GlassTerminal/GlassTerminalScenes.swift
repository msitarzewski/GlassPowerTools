//
//  GlassTerminalScenes.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's window scenes (glas_shApp.swift:99-280), minus the Connections window and Settings,
//  which the shell owns. The app includes this scene next to the shell's.
//

import SwiftUI
import GlassShell
import GlassConnectionUI
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
                // Windows opened from outside any window — Siri, a Finder service — open from here
                // too (`GlassWindowOpener`, D72).
                .glassRegistersWindowOpener()
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
                        .environment(\.glassFavorites, runtime.favorites)
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
                    .glassRegistersWindowOpener()
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
                    .trackWindowPresence(key: "terminal-workgroup-\(workgroupID.uuidString)", recovery: windowRecoveryManager)
                    // W15: an open window comes back after a relaunch; one closed by hand does not.
                    // The app's own list, not the system's restoration, which stays off below.
                    .modifier(TerminalWorkgroupWindowPresence(workgroupID: workgroupID))
            } else {
                // A window with no workgroup: one made by dropping a terminal dragged out of the
                // library (D72), which becomes that terminal where it stands; or the old "not found".
                VisionTerminalDropWindow()
                    .glassRegistersWindowOpener()
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                    .glassLayers(runtime.layers)
                    .trackWindowPresence(key: "terminal-workgroup-missing", recovery: windowRecoveryManager)
            }
        }
        // A terminal dragged out of the library opens here, where it is dropped (`GlassServiceDrag`);
        // so does a tab dragged out of a window (`TerminalTabDrag`).
        .handlesExternalEvents(matching: [GlassServiceDrag.terminalActivity, TerminalTabDrag.activityType])
        // Plain, with Apple's glass drawn by the window itself (`GlassSpatialWindowGlass`), in
        // Apple's corner, as strong as the window's Blur. The system's own window (cfd5094) gave
        // the canvas a corner to nest in, but its glass is always there while the window has
        // focus, so the clearest a terminal could be was Apple's glass. The owner, on the headset
        // (2026-10-10): "We've lost complete transparency ... 100% transparent glass (the whole
        // point of the app)". At Blur 0 the window is completely clear again.
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 800)
        .restorationBehavior(.disabled)
        // Asked for from the orb dock, it comes back above the dock (D88).
        .glassComesBackByOrbDock()
        .commands { PlatformTerminalCommands() }
        // No orb scene here: Connections becomes its own orb, in its own window (the shell's
        // `glassConnectionsIdleShrink`, W29 and W39), showing the library's Active count, which
        // only the shell can read.
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
        //
        // **Opacity paints the window edge to edge** (W32, 2026-10-10), in the window's shape:
        // W28's canvas, set in from the window's edges, read as a dark panel, and the owner asked
        // for it gone while keeping Opacity ("Opacity is essential transparency is essential").
        // **The window draws its own glass** (W33), as strong as Glass and none at 0, behind that
        // paint: the browser is our own column rather than a `NavigationStack`, whose system
        // glass nothing could clear (`SFTPBrowserView.spatialBrowser`). Glass 0 and Opacity 0
        // leave only the text and controls, as a terminal's window does.
        WindowGroup(id: "sftp", for: SFTPBrowserContext.self) { $context in
            GlassLayeredWindow(paintsTheme: GlassWindowGlass.paintsTheme(SFTPBrowserView.navigationOpacity)) {
                if let context, sessionManager.session(for: context.sessionID) != nil {
                    SFTPBrowserView(sessionID: context.sessionID, initialPath: context.initialPath)
                        .environment(sessionManager)
                        .environment(settingsManager)
                        .environment(\.glassOpenFolderAsProject, runtime.openFolderAsProject)
                        .environment(\.glassFavorites, runtime.favorites)
                        .environment(\.glassOpenFileInEditor, runtime.openFileInEditor)
                        .environment(\.glassEditorFileScreen, runtime.editorFileScreen)
                    .glassLayers(runtime.layers)
                        .trackWindowPresence(key: "sftp-\(context.sessionID.uuidString)", recovery: windowRecoveryManager)
                } else {
                    SFTPBrowserNotFoundView(context: context)
                        .trackWindowPresence(key: "sftp-missing", recovery: windowRecoveryManager)
                }
            }
            // **In the window's shape**, as the editor's is (7538a54): the shelf at the bottom — the
            // selection's actions, a transfer's progress — is a square `.bar`, and a plain window
            // gives its content no shape, so it filled the window's bottom corners outside the
            // rounded glass. Ornaments are outside this.
            .clipShape(RoundedRectangle(cornerRadius: GlassWindowShape.spatialWindowCornerRadius, style: .continuous))
            .glassSpatialWindowGlass()
            .glassLayers(runtime.layers)
        }
        .windowStyle(.plain)
        .defaultSize(width: 700, height: 500)
        .restorationBehavior(.disabled)
        ImmersiveSpace(id: "focus-environment") {
            FocusEnvironmentView()
                .environment(settingsManager)
                // Steps aside for Show All Windows around the person, and comes back after it.
                .glassImmersiveSpacePresence("focus-environment")
        }
        // Partway, the Digital Crown dialling it in, as Focus Mode always opened; or all the way
        // round with Open Immersed (Settings ▸ Terminal ▸ Focus Mode), the Crown still bringing the
        // room back.
        .immersionStyle(selection: .constant(focusImmersion), in: focusImmersion)
        .restorationBehavior(.disabled)
        // Try Out: one of the person's 3D environments, fitted from a window beside it.
        WindowGroup(id: FocusEnvironmentFitView.windowID, for: String.self) { $environmentID in
            if let environmentID {
                FocusEnvironmentFitView(environmentID: environmentID)
            }
        }
        .defaultSize(width: 460, height: 680)
        .restorationBehavior(.disabled)
        // Fine Position: Focus Mode's steps of a couple of centimetres, in a small window the system
        // places beside the person.
        Window("Fine Position", id: FocusEnvironmentNudgeView.windowID) {
            FocusEnvironmentNudgeView()
        }
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        #endif
    }

    #if os(visionOS)
    private var focusImmersion: any ImmersionStyle {
        FocusEnvironmentStage.immersion(opensImmersed: settingsManager.focusOpensImmersed
                                        || FocusEnvironmentStage.shared.tryingOut != nil)
    }
    #endif
}
