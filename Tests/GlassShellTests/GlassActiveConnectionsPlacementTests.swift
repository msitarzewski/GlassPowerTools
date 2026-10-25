#if os(macOS)
import SwiftUI
import AppKit
import Testing
@testable import GlassShell

/// The ⚡ is the last item on the right of a Mac toolbar (2026-10-05). Measured on a real, if
/// transparent, window: a toolbar's order and positions are AppKit's, and nothing short of laying
/// one out shows them. The database's shape: Back and a title at window level, and panes that push
/// their own buttons right with a flexible spacer — where a ⚡ added at window level drew on the left.
@MainActor
@Suite("Active Connections placement", .serialized)
struct GlassActiveConnectionsPlacementTests {
    /// Each toolbar item's label and left edge in the window, in toolbar order.
    private func layout(_ view: some View) async -> [(label: String, x: CGFloat)] {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        defer { window.close() }
        func items() -> [(label: String, x: CGFloat)] {
            (window.toolbar?.items ?? []).compactMap { item in
                guard !item.label.isEmpty, let view = item.view else { return nil }
                return (item.label, view.convert(view.bounds, to: nil).minX)
            }
        }
        // Until SwiftUI has put a labelled item in the toolbar, for up to 10 s, then a few more
        // passes so the rest arrive and the positions settle. A fixed second stood for all of it,
        // and an empty toolbar passed the test that looks for an absence (2026-10-24).
        let deadline = ContinuousClock.now + .seconds(10)
        while items().isEmpty, ContinuousClock.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        for _ in 0..<10 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        return items()
    }

    private func pane() -> some View {
        Text("pane")
            .glassActiveConnectionsLastInToolbar()
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem { Button { } label: { Label("Settings", systemImage: "gear") } }
                ToolbarItem { Button { } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
    }

    @Test("a pane that pushes its buttons right ends with the ⚡")
    func lastOnTheRight() async throws {
        let window = NavigationSplitView { Text("schema") } detail: { pane() }
            .toolbar {
                ToolbarItem(placement: .navigation) { Button { } label: { Label("Back", systemImage: "chevron.left") } }
                ToolbarItem { Text("Title") }
            }
            .environment(\.glassActiveConnectionsRoute, GlassActiveConnectionsRoute(show: {}))
        let items = await layout(window)
        let bolt = try #require(items.first { $0.label == "Active Connections" }, "\(items)")
        let refresh = try #require(items.first { $0.label == "Refresh" }, "\(items)")
        let back = try #require(items.first { $0.label == "Back" }, "\(items)")
        #expect(bolt.x > refresh.x, "after the pane's last button: \(items)")
        #expect(items.last?.label == "Active Connections", "\(items)")
        #expect(bolt.x > back.x + 300, "on the right, not beside Back: \(items)")
    }

    @Test("panes kept alive behind the shown one add no ⚡ of their own")
    func oneBoltForManyPanes() async {
        func pane(_ active: Bool) -> some View {
            Text("pane").glassActiveConnectionsLastInToolbar(isActive: active).opacity(active ? 1 : 0)
        }
        let window = NavigationSplitView { Text("schema") } detail: {
            ZStack { pane(false); pane(true); pane(false) }
        }
        .environment(\.glassActiveConnectionsRoute, GlassActiveConnectionsRoute(show: {}))
        let items = await layout(window)
        #expect(items.filter { $0.label == "Active Connections" }.count == 1, "\(items)")
    }

    @Test("without a route there is no ⚡")
    func noRouteNoBolt() async {
        let items = await layout(NavigationSplitView { Text("schema") } detail: { pane() })
        #expect(items.contains { $0.label == "Refresh" }, "the pane's own buttons are there: \(items)")
        #expect(!items.contains { $0.label == "Active Connections" }, "\(items)")
    }
}
#endif
