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
        #if os(macOS)
        // File ▸ Import RDP File… (⇧⌘I), glassDT's menu item. Aimed by the library toolbar's
        // import button, so it works where that button is: the library window.
        .commands { DesktopImportCommands() }
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
    @Environment(\.openWindow) private var openWindow
    @State private var loaded = false

    /// The ⚡ in this window: bring the library forward on its Active list.
    private var showActive: (@MainActor () -> Void)? {
        guard let show = runtime.showActiveConnections else { return nil }
        return { openWindow.openConnections(); show() }
    }

    var body: some View {
        // `maxWidth/maxHeight: .infinity` is load-bearing, not decoration
        // (`../glassDT/App/glassDTApp.swift:79`). Without it the window sizes itself to whichever
        // branch is showing — the failure panel or the spinner — so a session that cannot connect
        // opens a ~640-point window, the toolbar collapses into an overflow chevron and every
        // label truncates. Observed 2026-09-14.
        demoOrContent.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var demoOrContent: some View {
        #if DEBUG
        if let endpointID, let demo = runtime.demoSessions[endpointID] {
            DesktopSessionView(previewSession: demo, showActiveConnections: showActive)
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        Group {
            if let endpointID, let connection = runtime.connection(for: endpointID) {
                DesktopSessionView(connection: connection, app: runtime.app,
                                   onOutcome: { runtime.reportOutcome($0, for: endpointID) },
                                   onClose: { dismiss() },
                                   showActiveConnections: showActive)
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
    /// The session to show **in place**, on a device with no second window to put it in.
    ///
    /// The *connection*, not an endpoint id: `glassDT` presented the resolved connection and this
    /// does the same. Handing the cover an id would make it resolve the desktop a second time, and
    /// that second lookup is the one that failed earlier today — `catalogDidLoad()` defers the
    /// read, so a view asking the model in the first moments after launch finds nothing and says
    /// the configuration is missing. The capability has already resolved it before enqueuing;
    /// carrying the answer is both simpler and the only version that cannot disagree with itself.
    @State private var activeDesktop: DesktopConnection?

    public init(runtime: GlassDesktopRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    public var body: some View {
        base
            .task { await runtime.loadIfNeeded() }
            .onChange(of: runtime.requestSerial) { _, _ in drain() }
            .alert("Desktop", isPresented: Binding(get: { failure != nil },
                                                   set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    @ViewBuilder
    private var base: some View {
        #if canImport(UIKit) && !os(visionOS)
        content
            .fullScreenCover(item: $activeDesktop) { connection in
                NavigationStack {
                    coverSession(connection)
                    .toolbar {
                        // A chevron, so the machine's name is the only wording in the bar —
                        // `glassDT`'s decision, kept.
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Connections", systemImage: "chevron.backward") {
                                activeDesktop = nil
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    // The ⚡. A desktop ends when its cover goes, which is what `dismissCurrent`
                    // does here — the same thing the chevron does. Offered anyway: being inside a
                    // desktop with no way to a terminal is the dead end this exists to remove.
                    .glassActiveConnectionsToolbar(show: runtime.showActiveConnections,
                                                   dismissCurrent: { activeDesktop = nil })
                }
                .glassLayers(runtime.layers)
            }
        #else
        content
        #endif
    }

    @ViewBuilder
    private func coverSession(_ connection: DesktopConnection) -> some View {
        #if DEBUG
        if let demo = runtime.demoSessions[connection.id] {
            DesktopSessionView(previewSession: demo)
        } else {
            DesktopSessionView(connection: connection, app: runtime.app,
                               onOutcome: { runtime.reportOutcome($0, for: connection.id) },
                               onClose: { activeDesktop = nil })
        }
        #else
        DesktopSessionView(connection: connection, app: runtime.app,
                           onOutcome: { runtime.reportOutcome($0, for: connection.id) },
                           onClose: { activeDesktop = nil })
        #endif
    }

    private func drain() {
        for request in runtime.takeRequests() {
            switch request {
            case let .connect(connectionID, report):
                // The window is what connects, so the outcome is reported from there. Saying
                // `.connected` here would report a session that has not been attempted yet.
                runtime.holdReport(report, for: connectionID)
                // **`openWindow` does nothing on an iPhone**, so asking it to open the session was
                // answering the user's tap by doing nothing at all — no window, no error (reported
                // 2026-09-17: *"desktop isn't opening in iPhone. Nothing happens."*). Where there
                // is no second window, the session covers the library, which is what a window is
                // on a phone anyway.
                if GlassWindowPresentation.canOpenWindows {
                    openWindow(id: "desktop-session", value: connectionID.rawValue)
                } else if let connection = runtime.connection(for: connectionID) {
                    activeDesktop = connection
                } else {
                    // The capability checked this before enqueuing, so reaching here means the
                    // record went away in between. Said out loud rather than presenting nothing,
                    // which is the failure this whole change is about.
                    failure = "That desktop's configuration could not be read. Edit the service in the library to set it up again."
                }
            case let .show(connectionID):
                // The same window value as the connect opened, so a Mac brings the existing
                // window forward rather than opening a second; a phone shows the cover again.
                if GlassWindowPresentation.canOpenWindows {
                    openWindow(id: "desktop-session", value: connectionID.rawValue)
                } else if let connection = runtime.connection(for: connectionID) {
                    activeDesktop = connection
                }
                #if DEBUG
                if !GlassWindowPresentation.canOpenWindows, let demo = runtime.demoSessions[connectionID] {
                    activeDesktop = demo.connection
                }
                #endif
            case let .showFailure(message):
                failure = message
            }
        }
    }
}

