#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GlassTerminal
import GlassShell

/// A terminal window's sidebar adds to the window (the owner, 2026-10-16: "make the left (and
/// eventually right) sidebars additive and not resize my terminal window to make room"): opened or
/// closed by its toolbar button, the window grows or shrinks and the terminal keeps its size and
/// place. Not when the window puts back the sidebar it opens with, whose saved frame already holds
/// it, nor for the overview, which hides the sidebar to give the terminals the whole window.
@MainActor
@Suite("A terminal window's sidebar adds to the window", .serialized)
struct MacTerminalSidebarTests {
    @MainActor
    @Observable
    final class Model {
        var visibility: NavigationSplitViewVisibility
        var overview = false
        /// Where SwiftUI lays the terminal out, in the window.
        var detail: CGRect = .zero
        let opensSidebar: Bool

        /// `opensSidebar`: as a window whose sidebar was open when it was last shown — SwiftUI
        /// builds it closed, and the window's reader opens it (`configureInitialSidebar`).
        init(opensSidebar: Bool) {
            self.opensSidebar = opensSidebar
            visibility = .detailOnly
        }
    }

    /// The parts of `MacWorkspaceView` that decide: its split view, and its window reader.
    struct Root: View {
        @Bindable var model: Model
        var body: some View {
            NavigationSplitView(columnVisibility: $model.visibility) {
                List { Text("tab") }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 520)
            } detail: {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        model.detail = frame
                    }
                }
            }
            .background {
                MacTerminalWindowReader(
                    tabbingIdentifier: "test.sidebar",
                    opensSidebarInitially: !model.overview && model.opensSidebar,
                    // What `MacWorkspaceView` passes: its binding, which follows the split view.
                    overviewPresented: model.overview,
                    sidebarShown: model.visibility == .detailOnly ? false : true
                )
            }
        }
    }

    @MainActor
    final class Hosted {
        let model: Model
        let window = NSWindow(contentRect: NSRect(x: 400, y: 300, width: 900, height: 500),
                              styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)

        init(opensSidebar: Bool) async {
            GlassAdditiveSidebars.animationDuration = 0
            model = Model(opensSidebar: opensSidebar)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Root(model: model))
            window.setFrame(NSRect(x: 400, y: 300, width: 900, height: 500), display: true)
            // On screen, unseen: AppKit grows a window toward where it keeps it on screen.
            window.alphaValue = 0
            window.orderFrontRegardless()
            await settle()
        }

        var splitController: NSSplitViewController? {
            var views = [window.contentView].compactMap { $0 }
            var index = 0
            while index < views.count {
                if let split = views[index] as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                    return controller
                }
                views += views[index].subviews
                index += 1
            }
            return nil
        }

        var sidebarCollapsed: Bool? {
            splitController?.splitViewItems.first { $0.behavior == .sidebar }?.isCollapsed
        }

        /// The terminal's laid-out part, on screen.
        var terminal: NSRect {
            guard let content = window.contentView else { return .zero }
            let frame = model.detail
            let flipped = NSRect(x: frame.minX, y: content.bounds.height - frame.maxY,
                                 width: frame.width, height: frame.height)
            return window.convertToScreen(content.convert(flipped, to: nil))
        }

        /// The sidebar's toolbar button and View ▸ Show Sidebar.
        func toggleSidebar() async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                splitController?.toggleSidebar(nil)
            }, completionHandler: nil)
            await settle()
        }

        /// Until the window and the terminal have stopped moving (200 ms still, 3 s at most): the
        /// window follows its sidebar over several turns of the main queue, and under load a fixed
        /// wait wasn't always enough.
        func settle() async {
            try? await Task.sleep(for: .milliseconds(150))
            var last = (window.frame, model.detail), still = 0
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline, still < 4 {
                for _ in 0..<5 { await Task.yield() }
                try? await Task.sleep(for: .milliseconds(50))
                window.contentView?.layoutSubtreeIfNeeded()
                let now = (window.frame, model.detail)
                if now == last { still += 1 } else { still = 0; last = now }
            }
        }

        func close() { window.close() }
    }

    private func same(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    /// The terminal window itself, an empty tab in it: what it holds can stop the window growing.
    /// A minimum held on its whole content did (2026-10-16): AppKit grows the window by raising its
    /// minimum width, SwiftUI put it back, and the sidebar squeezed the terminal.
    @Test("the terminal window itself: its sidebar grows and shrinks the window")
    func terminalWindow() async throws {
        GlassAdditiveSidebars.animationDuration = 0
        let sidebarKey = UserDefaultsKeys.macWorkspaceSidebarVisibility + ".terminal"
        UserDefaults.standard.removeObject(forKey: sidebarKey)
        let request = MacWorkspaceLaunchRequest(startsEmpty: true)
        let window = NSWindow(contentRect: NSRect(x: 400, y: 300, width: 1000, height: 600),
                              styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
            window.contentView = nil
            UserDefaults.standard.removeObject(forKey: sidebarKey)
            let prefix = UserDefaultsKeys.macWorkspaceRestoration
            for controller in MacWorkspacePreviewRegistry.shared.controllers(windowID: request.windowID) {
                for tab in controller.tabs {
                    UserDefaults.standard.removeObject(forKey: "\(prefix).\(tab.workspaceID.uuidString.lowercased())")
                }
            }
            UserDefaults.standard.removeObject(forKey: "\(prefix).window.\(request.windowID.uuidString.lowercased())")
            MacWorkspacePreviewRegistry.shared.remove(request.windowID)
        }
        window.contentView = NSHostingView(rootView: MacWorkspaceSceneRoot(request: request)
            .environment(SessionManager(loadImmediately: false))
            .environment(SettingsManager(loadImmediately: false)))
        window.setFrame(NSRect(x: 400, y: 300, width: 1000, height: 600), display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()
        // Until the window has stopped moving, as `Hosted.settle`.
        func settle() async {
            try? await Task.sleep(for: .milliseconds(150))
            var last = window.frame, still = 0
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline, still < 4 {
                for _ in 0..<5 { await Task.yield() }
                try? await Task.sleep(for: .milliseconds(50))
                window.contentView?.layoutSubtreeIfNeeded()
                if window.frame == last { still += 1 } else { still = 0; last = window.frame }
            }
        }
        await settle()
        let sidebar = try #require(GlassAdditiveSidebars.items(in: window).first { $0.behavior == .sidebar })
        let split = try #require(sidebar.viewController.parent as? NSSplitViewController)
        func toggle() async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                split.toggleSidebar(nil)
            }, completionHandler: nil)
            await settle()
        }
        #expect(sidebar.isCollapsed, "an empty window opens without its sidebar")
        let closed = window.frame

        await toggle()
        #expect(!sidebar.isCollapsed)
        let width = sidebar.viewController.view.frame.width
        #expect(width > 150, "the sidebar's width: \(width)")
        #expect(abs(window.frame.width - (closed.width + width)) < 1,
                "the window grew by the sidebar, the terminal's column kept its width: \(closed) → \(window.frame)")
        #expect(abs(window.frame.maxX - closed.maxX) < 1, "toward the sidebar's side: \(window.frame)")

        await toggle()
        #expect(sidebar.isCollapsed)
        #expect(abs(window.frame.width - closed.width) < 1 && abs(window.frame.minX - closed.minX) < 1,
                "closed, the window is as it was: \(window.frame)")
    }

    @Test("opened and closed by its button, the window grows and shrinks and the terminal stays")
    func toggled() async throws {
        let host = await Hosted(opensSidebar: false)
        defer { host.close() }
        #expect(host.sidebarCollapsed == true)
        let terminal = host.terminal, window = host.window.frame

        await host.toggleSidebar()
        #expect(host.sidebarCollapsed == false)
        #expect(same(host.terminal, terminal), "the terminal kept its size and place: \(terminal) → \(host.terminal)")
        #expect(host.window.frame.width > window.width + 150, "the window grew: \(window) → \(host.window.frame)")

        await host.toggleSidebar()
        #expect(host.sidebarCollapsed == true)
        #expect(same(host.terminal, terminal), "\(host.terminal)")
        #expect(abs(host.window.frame.width - window.width) < 1, "and the window is as it was: \(host.window.frame)")
    }

    @Test("the sidebar a window opens with is put in its saved frame, not added to it")
    func opensWithItsSidebar() async throws {
        let host = await Hosted(opensSidebar: true)
        defer { host.close() }
        #expect(host.sidebarCollapsed == false)
        #expect(abs(host.window.frame.width - 900) < 1, "the window kept its frame: \(host.window.frame)")
        // Then the button adds and takes away as anywhere else.
        let terminal = host.terminal
        await host.toggleSidebar()
        #expect(host.sidebarCollapsed == true)
        #expect(same(host.terminal, terminal), "\(terminal) → \(host.terminal)")
        #expect(host.window.frame.width < 900 - 150, "the window shrank: \(host.window.frame)")
    }

    @Test("the overview hides the sidebar and gives it back in the same window")
    func overview() async throws {
        let host = await Hosted(opensSidebar: true)
        defer { host.close() }
        let window = host.window.frame
        // As `MacWorkspaceView.openOverview` does it.
        GlassAdditiveSidebars.set(additive: false, in: host.window)
        host.model.overview = true
        host.model.visibility = .detailOnly
        await host.settle()
        #expect(host.sidebarCollapsed == true)
        #expect(same(host.window.frame, window), "the overview has the whole window: \(host.window.frame)")

        host.model.overview = false
        host.model.visibility = .all
        await host.settle()
        #expect(host.sidebarCollapsed == false)
        #expect(same(host.window.frame, window), "and gives it back with the sidebar in it: \(host.window.frame)")

        // Back to adding.
        let terminal = host.terminal
        await host.toggleSidebar()
        #expect(same(host.terminal, terminal), "\(terminal) → \(host.terminal)")
        #expect(host.window.frame.width < window.width - 150, "the window shrank: \(host.window.frame)")
    }
}
#endif
