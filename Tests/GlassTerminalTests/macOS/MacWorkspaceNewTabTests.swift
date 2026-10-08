#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

/// "+" and ⌘T open a shell at once, a pane never waits on a view that went away, the empty tab
/// can be seen, and a window has one controller however often SwiftUI makes its view
/// (2026-10-08: "New terminal with the + brings up a blank panel"; a dragged tab "makes a copy
/// of the tmux session instead of moving it").
///
/// Nothing here starts tmux: names come from `MacLocalTmuxTests.FakeServer`, and the one process
/// started is `/bin/sh`. Tests that swap `MacLocalTmux.server` never suspend, so no other test
/// runs while the fake is in place, and they put back whatever was there.
@MainActor
@Suite("New terminal tabs and one controller per window", .serialized)
struct MacWorkspaceNewTabTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacWorkspaceNewTabTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// A view's controller saves to the standard defaults; these tests take their records out
    /// again, and the window out of the registry.
    private func forget(_ request: MacWorkspaceLaunchRequest) {
        let prefix = UserDefaultsKeys.macWorkspaceRestoration
        for controller in MacWorkspacePreviewRegistry.shared.controllers(windowID: request.windowID) {
            for tab in controller.tabs {
                UserDefaults.standard.removeObject(forKey: "\(prefix).\(tab.workspaceID.uuidString.lowercased())")
            }
        }
        UserDefaults.standard.removeObject(forKey: "\(prefix).window.\(request.windowID.uuidString.lowercased())")
        MacWorkspacePreviewRegistry.shared.remove(request.windowID)
    }

    @Test("\"+\" gives a selected tab with a shell on this Mac, not the empty chooser")
    func plusOpensALocalShell() throws {
        try withDefaults { defaults in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            let tab = try #require(window.addTab())
            #expect(window.tabs.count == 2)
            #expect(window.selectedTabID == tab.workspaceID && window.selectedTab === tab)
            #expect(!tab.isEmpty, "a tab with a pane, not the chooser")
            #expect(tab.focusedPane?.intent.kind == .local)
        }
    }

    @Test("with tmux on, \"+\" takes a glass-N that no tab holds and nothing on the Mac runs")
    func plusInTmuxTakesItsOwnSession() throws {
        try withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            fake.running = ["glass-1", "glass-2"]
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)

            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(initialPaneIntent: .local), defaults: defaults)
            defer { window.closeAllSessions(sessionManager: SessionManager(loadImmediately: false)) }
            // The claim makes the session, so compare with what ran before "+".
            let runningBefore = fake.running
            let tab = try #require(window.addTab())
            let pane = try #require(tab.focusedPaneID)
            let name = try #require(tab.localTmuxSession(for: pane), "the new pane runs in tmux")
            #expect(TerminalTmux.glassNumber(name) != nil)
            #expect(!runningBefore.contains(name), "not a session already running on the Mac")
            let others = window.tabs.filter { $0 !== tab }
                .flatMap { $0.state.root?.panes.compactMap(\.intent.localTmuxSession) ?? [] }
            #expect(!others.isEmpty && !others.contains(name), "not the session another tab holds")
        }
    }

    @Test("a second terminal for a tmux session a tab here already shows is refused, until that tab lets go")
    func noSecondClientForASessionShownHere() throws {
        try withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let sessionManager = SessionManager(loadImmediately: false)

            let request = MacWorkspaceTabRequest(initialPaneIntent: .local)
            let shown = MacWorkspaceController(request: request, defaults: defaults)
            // The same tab restored a second time, with the same pane and session.
            let copy = MacWorkspaceController(request: request, defaults: defaults)
            defer { copy.closeAllSessions(sessionManager: sessionManager) }
            let pane = try #require(shown.focusedPaneID)
            let name = try #require(shown.localTmuxSession(for: pane))
            #expect(copy.localTmuxSession(for: pane) == name)

            #expect(shown.localRuntime(for: pane) != nil)
            #expect(copy.localRuntime(for: pane) == nil, "no second client on \(name)")
            #expect(MacLocalTmux.shownHere[name] == 1)

            shown.closeAllSessions(sessionManager: sessionManager)
            #expect(MacLocalTmux.shownHere[name] == nil)
            #expect(copy.localRuntime(for: pane) != nil, "shown nowhere else now")
            #expect(MacLocalTmux.shownHere[name] == 1)
        }
    }

    @Test("a terminal view torn down before its shell started leaves the next view to start it")
    func rebuiltHostViewStillStartsTheShell() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "glass-rebuilt-host-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%d' $$ > \"$1\"; while :; do sleep 1; done",
                        "glass-rebuilt-host-test", pidFile.path],
            executableName: "sh",
            currentDirectory: FileManager.default.temporaryDirectory.path
        )
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        let theme = SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 0), cursor: (1, 1, 1))
        let settings = SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100)
        func host() -> NSHostingView<SwiftTermLocalProcessHostView> {
            NSHostingView(rootView: SwiftTermLocalProcessHostView(
                runtime: runtime, configuration: configuration, theme: theme, runtimeSettings: settings))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }

        // The first view makes the engine and is gone again within one turn of the main queue,
        // before its deferred start can run — a tab switched away from as it opened.
        var first: NSHostingView<SwiftTermLocalProcessHostView>? = host()
        window.contentView = first
        first?.layoutSubtreeIfNeeded()
        #expect(runtime.hasEngine, "the first view made the engine")
        window.contentView = nil
        first = nil
        #expect(!runtime.processState.isRunning)

        let second = host()
        window.contentView = second
        second.layoutSubtreeIfNeeded()
        let started = await waitFor(seconds: 5) {
            runtime.processState.isRunning && FileManager.default.fileExists(atPath: pidFile.path)
        }
        #expect(started, "the shell started in the view that is still there")
        #expect(runtime.launchedShell == "/bin/sh")
    }

    @Test("the empty tab's chooser can be seen on a dark theme under Light appearance")
    func emptyTabIsVisibleOnADarkThemeUnderLightAppearance() async throws {
        let theme = TerminalTheme.default
        #expect(theme.resolvedAppearance == .dark)
        let view = NSHostingView(rootView: MacWorkspaceEmptyTab(
            theme: theme, opacity: 1, blur: 0, startLocal: {}, startSSH: {}))
        let frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        view.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        view.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        defer {
            window.contentView = nil
            window.close()
        }
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let canvas = brightness(image, x: 2, y: 2)
        #expect(canvas < 0.1, "the theme's canvas is black")
        var visible = 0
        for y in stride(from: 0, to: image.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: image.pixelsWide, by: 2) where brightness(image, x: x, y: y) > canvas + 0.3 {
                visible += 1
            }
        }
        #expect(visible > 100, "the icon, title and buttons draw: \(visible) bright pixels")
    }

    @Test("two views made from one request share one controller")
    func twoConstructionsShareOneController() {
        let request = MacWorkspaceLaunchRequest(startsEmpty: true)
        defer { forget(request) }
        let first = MacWorkspaceView(request: request)
        let second = MacWorkspaceView(request: request)
        withExtendedLifetime((first, second)) {
            #expect(MacWorkspacePreviewRegistry.shared.controllers(windowID: request.windowID).count == 1)
        }
    }

    /// The scene's content drawn again for a window it already shows: with an equal request that
    /// went through JSON, as SwiftUI hands back a scene value; with the very same request; and
    /// with a request for the same window that is not equal, which always makes SwiftUI run the
    /// window view's init again.
    @Test("a window drawn again with another request for it keeps one controller")
    func sceneUpdatesMakeNoTwin() async throws {
        let request = MacWorkspaceLaunchRequest(startsEmpty: true)
        defer { forget(request) }
        let sessionManager = SessionManager(loadImmediately: false)
        let settingsManager = SettingsManager(loadImmediately: false)
        let renders = RenderCount()
        func scene(_ request: MacWorkspaceLaunchRequest, generation: Int) -> AnyView {
            AnyView(SceneHost(request: request, generation: generation, renders: renders)
                .environment(sessionManager)
                .environment(settingsManager))
        }
        let view = NSHostingView(rootView: scene(request, generation: 0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil }
        func settle() async throws {
            for _ in 0..<5 {
                turnRunLoop(view)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        try await settle()
        func controllers() -> Int { MacWorkspacePreviewRegistry.shared.controllers(windowID: request.windowID).count }
        #expect(controllers() == 1)

        var generation = 0
        func drawAgain(with request: MacWorkspaceLaunchRequest) async throws {
            let drawn = renders.value
            generation += 1
            view.rootView = scene(request, generation: generation)
            try await settle()
            #expect(renders.value > drawn, "the scene's content was drawn again")
        }
        // Without the registry this made a second controller only when it was the first such
        // redraw in the process (seen 2026-10-08), so it comes first; the request below always did.
        let roundTripped = try JSONDecoder().decode(MacWorkspaceLaunchRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTripped == request)
        try await drawAgain(with: roundTripped)
        #expect(controllers() == 1, "an equal request through JSON: \(controllers()) controllers")

        try await drawAgain(with: request)
        #expect(controllers() == 1, "the same request: \(controllers()) controllers")

        let sameWindow = MacWorkspaceLaunchRequest(windowID: request.windowID, tabs: [MacWorkspaceTabRequest(startsEmpty: true)])
        #expect(sameWindow != request)
        try await drawAgain(with: sameWindow)
        #expect(controllers() == 1, "another request for the same window: \(controllers()) controllers")
    }

    @Test("a window whose controller is made but not yet on screen is not reopened a second time")
    func reopenSkipsAWindowAlreadyOpening() throws {
        try withDefaults { defaults in
            let window = MacWorkspaceWindowController(
                request: MacWorkspaceLaunchRequest(startsEmpty: true), defaults: defaults)
            defer { MacWorkspacePreviewRegistry.shared.remove(window.windowID) }
            defaults.set([window.windowID.uuidString], forKey: MacLocalTmux.reopenKey)
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults).isEmpty,
                    "macOS is already restoring it")

            MacWorkspacePreviewRegistry.shared.remove(window.windowID)
            defaults.set([window.windowID.uuidString], forKey: MacLocalTmux.reopenKey)
            #expect(MacLocalTmux.takeWindowsToReopen(defaults: defaults) == [window.windowID],
                    "once its window has closed, it opens again")
        }
    }

    /// Synchronous so it can turn the run loop, which SwiftUI needs to apply an observed change.
    private func turnRunLoop(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        view.layoutSubtreeIfNeeded()
    }

    private func brightness(_ image: NSBitmapImageRep, x: Int, y: Int) -> Double {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private final class RenderCount {
    var value = 0
}

/// The scene's content closure, with the request the scene hands it. `generation` makes it draw
/// again whatever the request.
private struct SceneHost: View {
    let request: MacWorkspaceLaunchRequest
    let generation: Int
    let renders: RenderCount

    var body: some View {
        renders.value += 1
        return MacWorkspaceSceneRoot(request: request)
    }
}
#endif
