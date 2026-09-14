//
//  GlassDesktopScenes.swift
//  Glass Power Tools — GlassDesktop
//
//  glassDT's session window, minus its own library and settings, which the shell owns. The app
//  includes this scene next to the shell's, the terminal's and the database's.
//
//  Shaped after `Sources/GlassDatabase/GlassDatabaseScenes.swift`. The bootstrap view is the
//  piece that matters: it is the *single* place a connect request turns into a window, so a link
//  with nothing behind it produces one failure message rather than silently doing nothing.
//

import SwiftUI
import GlassShell
import GlassLayers
import GlassConnectionKit

public struct GlassDesktopScenes: Scene {
    private let runtime: GlassDesktopRuntime

    public init(runtime: GlassDesktopRuntime) { self.runtime = runtime }

    public var body: some Scene {
        WindowGroup(id: "desktop-session", for: UUID.self) { $endpointID in
            DesktopSessionHost(runtime: runtime, endpointID: endpointID.map(EndpointID.init(rawValue:)))
                .glassLayers(runtime.layers)
        }
        #if os(visionOS)
        .windowStyle(.plain)
        #endif
        #if !os(iOS)
        .defaultSize(width: 1280, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

/// Resolves the saved desktop behind an endpoint and shows its session, or says plainly why it
/// cannot. Separated from the scene so the "no configuration behind this link" case has one
/// rendering rather than one per call site.
struct DesktopSessionHost: View {
    let runtime: GlassDesktopRuntime
    let endpointID: EndpointID?
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false

    var body: some View {
        // `maxWidth/maxHeight: .infinity` is load-bearing, not decoration
        // (`../glassDT/App/glassDTApp.swift:79`). Without it the window sizes itself to whichever
        // branch is showing — the failure panel or the spinner — so a session that cannot connect
        // opens a ~640-point window, the toolbar collapses into an overflow chevron and every
        // label truncates. Observed 2026-09-14.
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        Group {
            if let endpointID, let connection = runtime.connection(for: endpointID) {
                DesktopSessionView(connection: connection, app: runtime.app,
                                   onOutcome: { runtime.reportOutcome($0, for: endpointID) },
                                   onClose: { dismiss() })
            } else if loaded {
                ContentUnavailableView(
                    "Desktop Not Found",
                    systemImage: "display",
                    description: Text("This desktop has no saved configuration. Edit the service in the library to set it up, or remove it.")
                )
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            await runtime.loadIfNeeded()
            loaded = true
        }
    }
}

/// Drains the runtime's request queue and opens windows for it. Mounted once, on the library
/// window, exactly as the terminal and database bootstraps are — a capability cannot open a
/// window by itself, and this is the one place that translates a request into `openWindow`.
public struct GlassDesktopBootstrap<Content: View>: View {
    private let runtime: GlassDesktopRuntime
    private let content: Content
    @Environment(\.openWindow) private var openWindow
    @State private var failure: String?

    public init(runtime: GlassDesktopRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    public var body: some View {
        content
            .task { await runtime.loadIfNeeded() }
            .onChange(of: runtime.requestSerial) { _, _ in drain() }
            .alert("Desktop", isPresented: Binding(get: { failure != nil },
                                                   set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func drain() {
        for request in runtime.takeRequests() {
            switch request {
            case let .connect(connectionID, report):
                // The window is what connects, so the outcome is reported from there. Saying
                // `.connected` here would report a session that has not been attempted yet.
                runtime.holdReport(report, for: connectionID)
                openWindow(id: "desktop-session", value: connectionID.rawValue)
            case let .showFailure(message):
                failure = message
            }
        }
    }
}
