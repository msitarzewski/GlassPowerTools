import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

/// D41: the library overview's figures and the on-device connection history (2026-09-30).
@Suite("Library overview")
struct GlassLibraryOverviewTests {
    private func host(_ name: String, kinds: [HostServiceKind], tags: [String] = []) throws -> GlassShellHost {
        let services = kinds.map { HostServiceLink(endpointID: EndpointID(), kind: $0, displayName: name) }
        return GlassShellHost(members: [try HostProfile(displayName: name, services: services, tags: tags)])
    }

    @Test("counts machines, services by kind, favourites and collections")
    func counts() throws {
        let alpha = try host("alpha", kinds: [.ssh, .database], tags: ["Home", "Lab"])
        let bravo = try host("bravo", kinds: [.ssh, .rdp], tags: ["Lab"])
        let stats = GlassLibraryStatistics.make(hosts: [alpha, bravo], isFavorite: { $0 == bravo.id }, history: [])
        #expect(stats.machines == 2 && stats.services == 4)
        #expect(stats.servicesByKind == [.ssh: 2, .database: 1, .rdp: 1])
        #expect(stats.favorites == 1 && stats.collections == 2)
        #expect(stats.perDay.isEmpty && stats.mostUsed.isEmpty && stats.connectionsInWindow == 0)
    }

    @Test("connections per day and kind in the last 30 days, and the machines used most")
    func timeline() throws {
        let alpha = try host("alpha", kinds: [.ssh]), bravo = try host("bravo", kinds: [.rdp])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 86_400
        let history: [GlassShellPreferences.ConnectionEvent] = [
            .init(date: now - 40 * day, hostID: alpha.id, kind: .ssh),       // outside the window
            .init(date: now - 2 * day, hostID: alpha.id, kind: .ssh),
            .init(date: now - 2 * day, hostID: alpha.id, kind: .ssh),
            .init(date: now - 2 * day, hostID: bravo.id, kind: .rdp),
            .init(date: now - 60, hostID: bravo.id, kind: .rdp),
            .init(date: now - 60, hostID: HostID(), kind: .ssh),             // a machine since deleted
        ]
        let stats = GlassLibraryStatistics.make(hosts: [alpha, bravo], isFavorite: { _ in false },
                                                history: history, now: now, calendar: calendar)
        #expect(stats.connectionsInWindow == 5)
        // Two days, kinds in HostServiceKind order (desktop, terminal, database). The deleted
        // machine's connection still counts in the day, not in "most used".
        #expect(stats.perDay.map(\.count) == [1, 2, 1, 1])
        #expect(stats.perDay.map(\.kind) == [.rdp, .ssh, .rdp, .ssh])
        #expect(stats.mostUsed.map(\.name) == ["alpha", "bravo"] && stats.mostUsed.map(\.count) == [2, 2])
    }

    @Test("the history keeps 90 days and at most its limit, and an older file still reads")
    func historyBounds() throws {
        var preferences = GlassShellPreferences()
        let id = HostID(), start = Date(timeIntervalSince1970: 1_790_000_000)
        preferences.recordConnection(.init(date: start, hostID: id, kind: .ssh))
        preferences.recordConnection(.init(date: start + 91 * 86_400, hostID: id, kind: .ssh))
        #expect(preferences.connectionHistory?.count == 1, "the 91-day-old one is gone")
        for index in 0..<(GlassShellPreferences.historyLimit + 10) {
            preferences.recordConnection(.init(date: start + 91 * 86_400 + Double(index), hostID: id, kind: .rdp))
        }
        #expect(preferences.connectionHistory?.count == GlassShellPreferences.historyLimit)

        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GlassShellPreferences())) as! [String: Any]
        old.removeValue(forKey: "connectionHistory")
        let decoded = try JSONDecoder().decode(GlassShellPreferences.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.connectionHistory == nil)
    }
}
