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
import os
import GlassShell
import GlassLayers
import GlassConnectionKit
#if os(iOS)
import UIKit
#endif

public struct GlassDesktopScenes: Scene {
    private let runtime: GlassDesktopRuntime

    public init(runtime: GlassDesktopRuntime) { self.runtime = runtime }

    public var body: some Scene {
        WindowGroup(id: "desktop-session", for: UUID.self) { $endpointID in
            DesktopWindowRoot(runtime: runtime, endpointID: endpointID)
                .glassLayers(runtime.layers)
                .glassRegistersWindowOpener()
        }
        #if os(iOS) || os(visionOS)
        // A desktop dragged out of the library opens here, where it is dropped (`GlassServiceDrag`).
        .handlesExternalEvents(matching: [GlassServiceDrag.desktopActivity])
        #endif
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

        // W30: one window per display of a multi-display host, onto the desktop window's
        // connection. Keyed by desktop and display, so opening a display that already has a window
        // brings it forward. Not restored, like the desktop's own window: its connection is not.
        WindowGroup(id: DesktopDisplayWindowValue.windowID, for: DesktopDisplayWindowValue.self) { $value in
            DesktopDisplayWindowHost(runtime: runtime, value: value)
                .glassLayers(runtime.layers)
        }
        #if os(visionOS)
        .windowStyle(.plain)
        // Beside the desktop's other windows, as one monitor stands beside another, rather than
        // in front of them.
        .defaultWindowPlacement { _, context in
            if let beside = context.windows.last(where: {
                $0.id == DesktopDisplayWindowValue.windowID || $0.id == "desktop-session"
            }) {
                return WindowPlacement(.trailing(beside))
            }
            return WindowPlacement()
        }
        #endif
        #if !os(iOS)
        .defaultSize(width: 1280, height: 800)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

/// A desktop window: the desktop its value names, or — for a window made by dropping a desktop
/// dragged out of the library (D72), which has no value — the desktop the drop's activity names,
/// standing where it was let go.
struct DesktopWindowRoot: View {
    let runtime: GlassDesktopRuntime
    let endpointID: UUID?
    @State private var dropped: UUID?
    /// A moment for a drop's activity to arrive before a window with no desktop says so.
    @State private var waited = false

    var body: some View {
        Group {
            if let shown = endpointID ?? dropped {
                DesktopSessionHost(runtime: runtime, endpointID: EndpointID(rawValue: shown))
                    .id(shown)
            } else if waited {
                DesktopSessionHost(runtime: runtime, endpointID: nil)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(iOS) || os(visionOS)
        .onContinueUserActivity(GlassServiceDrag.desktopActivity) { activity in
            if endpointID == nil, dropped == nil { dropped = GlassServiceDrag.endpoint(from: activity) }
        }
        #endif
        .task {
            guard endpointID == nil else { return }
            try? await Task.sleep(for: .seconds(2))
            waited = true
        }
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
    #if os(iOS)
    /// This window's scene, so Close can end it (`closeWindow`).
    @State private var windowScene: UIWindowScene?
    #endif
    @State private var loaded = false
    /// The desktop's session still open in its display windows after its own window closed (W30),
    /// looked up once as the window appears: this window joins it rather than connecting again.
    @State private var liveSession: DesktopSessionModel?
    @State private var lookedForLiveSession = false

    /// Closes this window. On iOS neither `dismiss` nor `dismissWindow` closed a desktop window
    /// from its root — Close was tapped and the window stayed (the Duo simulator, 2026-10-13) — so
    /// its scene is ended through UIKit. That works where windows do (an iPad); a phone answers
    /// "not supported for this device idiom", which is logged.
    private func closeWindow() {
        #if os(iOS)
        let log = Logger(subsystem: "com.glasspowertools", category: "windows")
        if let session = windowScene?.session {
            log.notice("Closing a desktop window: ending its scene \(session.persistentIdentifier, privacy: .public)")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { error in
                log.error("A desktop window's scene did not end: \(String(describing: error), privacy: .public)")
            }
        } else {
            log.notice("Closing a desktop window: no scene found; dismissing")
            dismiss()
        }
        #else
        dismiss()
        #endif
    }

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
            // Offered on your other devices while in front (D72): Continue opens the same desktop.
            .glassHandoff(endpoint: endpointID?.rawValue,
                          title: endpointID.flatMap { runtime.connection(for: $0)?.name } ?? "Desktop")
            .desktopWindowBar()
            #if os(iOS)
            .background { WindowSceneReader { windowScene = $0 } }
            #endif
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
            if let live = liveSession {
                DesktopSessionView(session: live, viewport: live.primaryViewport,
                                   onOutcome: { runtime.reportOutcome($0, for: endpointID) },
                                   onClose: { closeWindow() },
                                   showActiveConnections: showActive)
            } else if !lookedForLiveSession {
                ProgressView().controlSize(.large)
            } else if let endpointID, let connection = runtime.connection(for: endpointID) {
                DesktopSessionView(connection: connection, app: runtime.app,
                                   onOutcome: { runtime.reportOutcome($0, for: endpointID) },
                                   onClose: { closeWindow() },
                                   showActiveConnections: showActive)
            } else if loaded {
                ContentUnavailableView {
                    Label("Desktop Not Found", systemImage: "display")
                } description: {
                    Text("This desktop has no saved configuration. Edit the service in the library to set it up, or remove it.")
                    // A phone cannot end a window itself ("not supported for this device idiom", the
                    // Duo, 2026-10-13), so it says where it can be closed instead of offering a
                    // button that does nothing (the owner: "this doesn't close, fwiw").
                    if !GlassWindowPresentation.canOpenWindows {
                        Text("Close this window in the app switcher.")
                    }
                } actions: {
                    // The window's own way out, where the system draws none — an iPad's.
                    if GlassWindowPresentation.canOpenWindows {
                        Button("Close") { closeWindow() }
                    }
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .onAppear {
            guard !lookedForLiveSession else { return }
            liveSession = endpointID.flatMap { runtime.app.liveSession(for: $0) }
            lookedForLiveSession = true
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
            // `initial`: a connection asked for while no Connections window was open — from the
            // Command Palette over a terminal window, or Siri — is carried out by the one that opens.
            .onChange(of: runtime.requestSerial, initial: true) { _, _ in drain() }
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


extension View {
    /// A desktop's own window on iPadOS, inside a navigation container — which is what draws the
    /// session's bar: its name, Settings, Clipboard and the ⚡. Without one none of it was drawn,
    /// and the window could be left only from the app switcher (2026-10-13, the owner on the
    /// unfolded iPhone Duo: "I see no way to get back to the previous screen"). The Mac draws the
    /// toolbar on the window itself; the headset puts it in an ornament.
    @ViewBuilder func desktopWindowBar() -> some View {
        #if os(iOS)
        NavigationStack { self }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// The window scene a SwiftUI view is in, read from a view of its own as it joins a window.
struct WindowSceneReader: UIViewRepresentable {
    let onScene: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> ReaderView { ReaderView(onScene: onScene) }
    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        private let onScene: (UIWindowScene?) -> Void
        init(onScene: @escaping (UIWindowScene?) -> Void) {
            self.onScene = onScene
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onScene(window?.windowScene)
        }
    }
}
#endif
