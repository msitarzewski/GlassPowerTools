import Foundation
import SwiftUI
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Time in use (2026-10-20, the owner: "this show half truths! … I've had tmux sessions running for
/// days in a row now and that's not reflected"): each minute, every machine and kind of service
/// whose sessions had input or output in it counts once; the overview opens on those minutes.
@MainActor
@Suite("Time in use")
struct GlassTimeInUseTests {
    /// The terminal, with This Mac's Local Shell.
    @MainActor final class Shell: GlassCapability {
        static let endpointID = EndpointID(rawValue: UUID(uuidString: "4c4f4341-4c00-0000-0000-5348454c4c00")!)
        let kind: HostServiceKind = .ssh
        var displayName: String { "Terminal" }
        var symbolName: String { "terminal" }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
        func builtInLocalServices() -> [HostServiceLink] {
            [HostServiceLink(endpointID: Self.endpointID, kind: .ssh, displayName: "Local Shell")]
        }
        var supportsLocalSetup: Bool { false }
    }

    @MainActor final class Database: GlassCapability {
        let kind: HostServiceKind = .database
        var displayName: String { "Database" }
        var symbolName: String { "cylinder" }
        func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    }

    private struct Fixture {
        let model: GlassShellModel
        let root: URL
        let alpha: HostID
        let terminal: EndpointID
        let database: EndpointID
    }

    private func makeModel(_ root: URL, _ name: String = "app") -> GlassShellModel {
        let registry = GlassCapabilityRegistry()
        registry.register(Shell())
        registry.register(Database())
        return GlassShellModel(storageDirectory: root.appendingPathComponent(name),
                               sharedContainerURL: nil, resolveSharedContainer: false,
                               accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore(), registry: registry)
    }

    /// alpha, with a Terminal and a database.
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TimeInUse-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = makeModel(root)
        await model.load()
        let machine = try await model.addHost(displayName: "alpha", address: "192.0.2.10")
        let terminal = try await model.addService(kind: .ssh, displayName: "Terminal on alpha", to: machine.id)
        let database = try await model.addService(kind: .database, displayName: "MySQL on alpha", to: machine.id)
        return Fixture(model: model, root: root, alpha: machine.id, terminal: terminal.endpointID,
                       database: database.endpointID)
    }

    private func session(_ id: String, _ endpoint: EndpointID, lastActivity: Date?,
                         tabs: [GlassOpenSession] = []) -> GlassOpenSession {
        GlassOpenSession(id: id, title: id, symbolName: "terminal", endpointIDs: [endpoint],
                         activate: {}, close: {}, tabs: tabs, lastActivity: { lastActivity })
    }

    /// This device's minutes, by machine and kind, as the overview reads them.
    private func minutes(_ model: GlassShellModel) -> [String: Int] {
        var found: [String: Int] = [:]
        for count in model.usageByDevice.first?.counts ?? [] where count.minutes > 0 {
            found["\(count.hostID.rawValue.uuidString)|\(count.kind.rawValue)", default: 0] += count.minutes
        }
        return found
    }

    private func key(_ host: HostID, _ kind: HostServiceKind) -> String { "\(host.rawValue.uuidString)|\(kind.rawValue)" }

    @Test("a minute counts once for each machine and kind active in it, and not for an idle session")
    func counting() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let now = Date()
        f.model.countMinuteInUse(now: now, sessions: [
            session("one", f.terminal, lastActivity: now - 10),
            session("two", f.terminal, lastActivity: now - 20),      // the same machine and kind: still one minute
            session("db", f.database, lastActivity: now - 600),      // idle for ten minutes
            session("never", f.database, lastActivity: nil),
        ], activity: [])
        #expect(minutes(f.model) == [key(f.alpha, .ssh): 1])
    }

    @Test("activity counts for the minute after it, once: not again at the next count without more")
    func sinceTheLastCount() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let start = Date()
        f.model.countMinuteInUse(now: start, sessions: [session("one", f.terminal, lastActivity: start - 5)], activity: [])
        // A minute later, nothing new: the same activity isn't counted twice.
        f.model.countMinuteInUse(now: start + 60, sessions: [session("one", f.terminal, lastActivity: start - 5)], activity: [])
        #expect(minutes(f.model) == [key(f.alpha, .ssh): 1])
        f.model.countMinuteInUse(now: start + 120, sessions: [session("one", f.terminal, lastActivity: start + 90)], activity: [])
        #expect(minutes(f.model) == [key(f.alpha, .ssh): 2])
    }

    @Test("a window's tabs count each for its own machine, and the window itself not again")
    func tabs() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let now = Date()
        let window = session("window", f.terminal, lastActivity: now, tabs: [
            session("tab-ssh", f.terminal, lastActivity: now - 3),
            session("tab-db", f.database, lastActivity: now - 3),
        ])
        f.model.countMinuteInUse(now: now, sessions: [window], activity: [])
        #expect(minutes(f.model) == [key(f.alpha, .ssh): 1, key(f.alpha, .database): 1])
    }

    @Test("a Mac tab's local shell counts for This Mac, and for its machine once the two are linked")
    func localShell() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let now = Date()
        let local = [GlassUsageActivity(endpointID: Shell.endpointID, lastActivity: now - 2)]
        f.model.countMinuteInUse(now: now, sessions: [], activity: local)
        #expect(minutes(f.model) == [key(GlassLocalHost.id, .ssh): 1])

        // Linked, the minute before is the machine's too, as its row is This Mac's (D86).
        f.model.setThisMac(f.alpha)
        f.model.countMinuteInUse(now: now + 60, sessions: [],
                                 activity: [GlassUsageActivity(endpointID: Shell.endpointID, lastActivity: now + 30)])
        #expect(minutes(f.model) == [key(f.alpha, .ssh): 2])
    }

    @Test("another device gets This Mac's minutes under its machine's id once linked, never This Mac's own")
    func travelsLinked() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let phone = makeModel(f.root, "phone")
        await phone.load()
        f.model.setDeviceName("Ann's Mac")
        let shared = GlassFavoritesSyncTests.SharedStore()
        await f.model.startSynchronizingUsage(with: GlassSettingsSyncService(usageStore: shared.device()))
        await phone.startSynchronizingUsage(with: GlassSettingsSyncService(usageStore: shared.device()))

        let now = Date()
        f.model.countMinuteInUse(now: now, sessions: [],
                                 activity: [GlassUsageActivity(endpointID: Shell.endpointID, lastActivity: now - 1)])
        f.model.setThisMac(f.alpha)
        f.model.saveUsage()
        func fromMac() -> GlassDeviceUsage? { phone.usageByDevice.first { $0.name == "Ann's Mac" && !$0.counts.isEmpty } }
        for _ in 0..<50 where fromMac() == nil { try await Task.sleep(for: .milliseconds(20)) }
        let mac = try #require(fromMac(), "the Mac's minutes never arrived")
        #expect(mac.counts.map(\.hostID) == [f.alpha])
        #expect(mac.counts.map(\.minutes) == [1])
    }

    @Test("minutes are kept on the device across a relaunch")
    func kept() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let now = Date()
        f.model.countMinuteInUse(now: now, sessions: [session("one", f.terminal, lastActivity: now - 1)], activity: [])
        f.model.saveUsage()
        let again = makeModel(f.root)
        await again.load()
        #expect(minutes(again) == [key(f.alpha, .ssh): 1])
    }

    @Test("the overview's time in use: hours per day and kind, machines by time, connections apart")
    func statistics() throws {
        let alpha = GlassShellHost(members: [try HostProfile(displayName: "alpha")])
        let bravo = GlassShellHost(members: [try HostProfile(displayName: "bravo")])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = calendar.startOfDay(for: now)
        let counts = [
            GlassUsageCount(date: today, hostID: alpha.id, kind: .ssh, count: 1),                 // one connect…
            GlassUsageCount(date: today, hostID: alpha.id, kind: .ssh, count: 0, minutes: 600),   // …ten hours in use
            GlassUsageCount(date: today, hostID: bravo.id, kind: .ssh, count: 4),
            GlassUsageCount(date: today, hostID: bravo.id, kind: .ssh, count: 0, minutes: 30),
            GlassUsageCount(date: today, hostID: bravo.id, kind: .database, count: 0, minutes: 15),
        ]
        let stats = GlassLibraryStatistics.make(hosts: [alpha, bravo], isFavorite: { _ in false }, counts: counts,
                                                now: now, calendar: calendar)
        #expect(stats.minutesInWindow == 645 && stats.connectionsInWindow == 5)
        #expect(stats.perDay.first { $0.kind == .ssh }?.minutes == 630)
        #expect(stats.perDay.first { $0.kind == .ssh }?.count == 5)
        #expect(stats.perDay.first { $0.kind == .database }?.minutes == 15)
        #expect(stats.perDay.first { $0.kind == .database }?.count == 0)
        // By time, alpha leads; by connections, bravo does.
        #expect(stats.mostUsedByTime.map(\.name) == ["alpha", "bravo"])
        #expect(stats.mostUsedByTime.map(\.minutes) == [600, 45])
        #expect(stats.mostUsed.map(\.name) == ["bravo", "alpha"])
    }

    @Test("a machine used but never connected to from the library is in Most Used by time only")
    func timeOnly() throws {
        let alpha = GlassShellHost(members: [try HostProfile(displayName: "alpha")])
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let stats = GlassLibraryStatistics.make(
            hosts: [alpha], isFavorite: { _ in false },
            counts: [GlassUsageCount(date: now - 60, hostID: alpha.id, kind: .ssh, count: 0, minutes: 90)], now: now)
        #expect(stats.mostUsedByTime.map(\.name) == ["alpha"])
        #expect(stats.mostUsed.isEmpty && stats.connectionsInWindow == 0)
    }

    @Test("time is said in minutes under an hour, in hours from one up")
    func wording() {
        #expect(GlassUsageMeasure.spoken(minutes: 1) == "1 minute")
        #expect(GlassUsageMeasure.spoken(minutes: 59) == "59 minutes")
        #expect(GlassUsageMeasure.spoken(minutes: 60) == "1 hour")
        #expect(GlassUsageMeasure.spoken(minutes: 2_460) == "41 hours")
        #expect(GlassUsageMeasure.short(minutes: 45) == "45 min")
        #expect(GlassUsageMeasure.short(minutes: 60) == "1 h")
        #expect(GlassUsageMeasure.short(minutes: 150) == "2.5 h")
        #expect(GlassUsageMeasure.short(minutes: 2_460) == "41 h")
    }
}
