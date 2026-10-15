import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

/// All Windows off the Mac (2026-10-14): what is open, by machine, searchable. Only what is open
/// here, as on the Mac: "the card view should only show connected services, like Mac."
@MainActor
@Suite("All Windows off the Mac")
struct GlassShowAllWindowsOverviewTests {
    private func session(_ id: String, _ title: String, _ subtitle: String? = nil) -> GlassOpenSession {
        GlassOpenSession(id: id, title: title, subtitle: subtitle, symbolName: "terminal", activate: {}, close: {})
    }

    private var machines: [GlassActiveMachine] {
        var alpha = GlassActiveMachine(id: "a", name: "alpha", sessions: [session("terminal:1", "build", "Terminal")])
        alpha.running = [GlassRunningSession(id: "tmux:1", title: "logs", symbolName: "terminal", endpointID: EndpointID(),
                                             isAttachedElsewhere: false, open: {}, takeOver: {}, end: {})]
        let bravo = GlassActiveMachine(id: "b", name: "bravo", sessions: [session("database:1", "orders", "MySQL")])
        var charlie = GlassActiveMachine(id: "c", name: "charlie", sessions: [])
        charlie.running = alpha.running
        return [alpha, bravo, charlie]
    }

    @Test("every machine with something open here; what only runs on a machine is Active's")
    func onlyWhatIsOpen() {
        let shown = GlassShowAllWindowsOverview.filtered(machines, by: "")
        #expect(shown.map(\.name) == ["alpha", "bravo"])
        #expect(shown.allSatisfy { $0.running.isEmpty })
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "logs").isEmpty)
    }

    /// The owner (2026-10-14): disconnected sessions were on the cards; "Should only be connected".
    @Test("only what is live: a session through services while connected through one; an editor's while open")
    func onlyWhatIsLive() {
        let endpoint = EndpointID()
        let live = GlassOpenSession(id: "terminal:live", title: "live", symbolName: "terminal",
                                    endpointIDs: [endpoint], activate: {}, close: {})
        let dropped = GlassOpenSession(id: "terminal:dropped", title: "dropped", symbolName: "terminal",
                                       endpointIDs: [endpoint], activate: {}, close: {}, isConnected: false)
        let editor = GlassOpenSession(id: "editor:1", title: "notes", symbolName: "doc", activate: {}, close: {})
        let quiet = GlassActiveMachine(id: "q", name: "quiet", sessions: [dropped])
        let shown = GlassShowAllWindowsOverview.filtered(
            [GlassActiveMachine(id: "a", name: "alpha", sessions: [live, dropped, editor]), quiet], by: "")
        #expect(shown.map(\.name) == ["alpha"], "a machine with nothing live is not listed")
        #expect(shown.first?.sessions.map(\.title) == ["live", "notes"])
    }

    @Test("a search keeps a whole machine by its name, or the sessions whose title or kind match")
    func search() {
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "alpha").map(\.sessions.count) == [1])
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "mysql").map(\.name) == ["bravo"])
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "BUILD").map(\.name) == ["alpha"])
    }
}
