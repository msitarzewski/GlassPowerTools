import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

/// All Windows off the Mac (2026-10-14): Active's machines as cards, searchable, with the
/// sessions running elsewhere and none a window here already shows.
@MainActor
@Suite("All Windows off the Mac")
struct GlassShowAllWindowsOverviewTests {
    private func session(_ id: String, _ title: String, _ subtitle: String? = nil) -> GlassOpenSession {
        GlassOpenSession(id: id, title: title, subtitle: subtitle, symbolName: "terminal", activate: {}, close: {})
    }

    private func running(_ id: String, _ title: String, openHere: Bool = false) -> GlassRunningSession {
        GlassRunningSession(id: id, title: title, symbolName: "terminal", endpointID: EndpointID(),
                            isAttachedElsewhere: false, isOpenHere: openHere, open: {}, takeOver: {}, end: {})
    }

    private var machines: [GlassActiveMachine] {
        var alpha = GlassActiveMachine(id: "a", name: "alpha", sessions: [session("terminal:1", "build", "Terminal")])
        alpha.running = [running("tmux:1", "logs"), running("tmux:2", "shown", openHere: true)]
        let bravo = GlassActiveMachine(id: "b", name: "bravo", sessions: [session("database:1", "orders", "MySQL")])
        let quiet = GlassActiveMachine(id: "c", name: "charlie", sessions: [])
        return [alpha, bravo, quiet]
    }

    @Test("every machine with something open or running, without what a window here shows")
    func everything() {
        let shown = GlassShowAllWindowsOverview.filtered(machines, by: "")
        #expect(shown.map(\.name) == ["alpha", "bravo"])
        #expect(shown[0].running.map(\.title) == ["logs"])
    }

    @Test("a search keeps a whole machine by its name, or the sessions whose title or kind match")
    func search() {
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "alpha").map { $0.sessions.count + $0.running.count } == [2])
        let byKind = GlassShowAllWindowsOverview.filtered(machines, by: "mysql")
        #expect(byKind.map(\.name) == ["bravo"])
        let byTitle = GlassShowAllWindowsOverview.filtered(machines, by: "LOGS")
        #expect(byTitle.map(\.name) == ["alpha"] && byTitle[0].sessions.isEmpty && byTitle[0].running.map(\.title) == ["logs"])
        #expect(GlassShowAllWindowsOverview.filtered(machines, by: "shown").isEmpty, "a window here shows it")
    }
}
