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

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public var body: some Scene {
        #if os(macOS) || os(visionOS)
        Window("Workgroups", id: "terminal-workgroups") {
            GlassLayeredWindow {
                TerminalWorkgroupsView()
                    .environment(runtime)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
            }
            .glassLayers(runtime.layers)
        }
        .defaultSize(width: 900, height: 600)
        .commands { TerminalLibraryCommands(runtime: runtime) }
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
        #endif
        #if os(macOS)
        WindowGroup("Terminal", id: "workspace", for: MacWorkspaceLaunchRequest.self) { $request in
            MacWorkspaceSceneRoot(request: request)
                .environment(runtime)
                .environment(sessionManager)
                .environment(settingsManager)
                .glassLayers(runtime.layers)
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .commands { MacWorkspaceCommands(sessionManager: sessionManager) }
        WindowGroup(id: "sftp", for: SFTPBrowserContext.self) { $context in
            if let context, sessionManager.session(for: context.sessionID) != nil {
                SFTPBrowserView(sessionID: context.sessionID)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
            } else {
                SFTPBrowserNotFoundView(context: context)
            }
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
            } else {
                ContentUnavailableView(
                    "Terminal Workgroup Not Found",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Open a terminal from Connections to begin.")
                )
                .trackWindowPresence(key: "terminal-workgroup-missing", recovery: windowRecoveryManager)
            }
        }
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
        .windowStyle(.plain)
        .defaultSize(width: 1000, height: 800)
        .restorationBehavior(.disabled)
        #endif
        WindowGroup(id: "sftp", for: SFTPBrowserContext.self) { $context in
            if let context, sessionManager.session(for: context.sessionID) != nil {
                SFTPBrowserView(sessionID: context.sessionID)
                    .environment(sessionManager)
                    .environment(settingsManager)
                .glassLayers(runtime.layers)
                    .trackWindowPresence(key: "sftp-\(context.sessionID.uuidString)", recovery: windowRecoveryManager)
            } else {
                SFTPBrowserNotFoundView(context: context)
                    .trackWindowPresence(key: "sftp-missing", recovery: windowRecoveryManager)
            }
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
