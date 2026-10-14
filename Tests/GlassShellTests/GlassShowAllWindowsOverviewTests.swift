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

    @Test("a search keeps a whole machine by its name, or the sessions whose title or kind match")
    func search() {
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "alpha").map(\.sessions.count) == [1])
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "mysql").map(\.name) == ["bravo"])
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "BUILD").map(\.name) == ["alpha"])
    }
}
