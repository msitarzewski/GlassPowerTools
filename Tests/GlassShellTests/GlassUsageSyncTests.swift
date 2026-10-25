import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Use on every device (D81; the owner, 2026-10-17: "display the cross device use … So maybe totals,
/// then a way to choose which device?"): each device counts its connections per day, machine and
/// kind of service, sends only its own counts, and every device's overview adds them up.
@MainActor
@Suite("Use on every device")
struct GlassUsageSyncTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_792_260_000)   // 2026-10-17, afternoon in Chicago

    private func event(_ host: HostID, _ kind: HostServiceKind, daysAgo: Int, hour: Int = 10) -> GlassShellPreferences.ConnectionEvent {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return .init(date: calendar.date(byAdding: .hour, value: hour, to: day)!, hostID: host, kind: kind)
    }

    @Test("a device's history is counted per day, machine and kind, for the overview's 30 days")
    func counting() throws {
        let alpha = HostID(), bravo = HostID()
        let history = [event(alpha, .ssh, daysAgo: 0, hour: 9), event(alpha, .ssh, daysAgo: 0, hour: 11),
                       event(alpha, .database, daysAgo: 0), event(bravo, .ssh, daysAgo: 1),
                       event(bravo, .ssh, daysAgo: 40)]
        let device = GlassUsagePayload.Device(name: "Ann's Mac", history: history, now: now, calendar: calendar)
        #expect(device.name == "Ann's Mac")
        #expect(device.days.count == 2, "40 days ago is outside the overview's window")
        let counts = device.counts(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        #expect(counts.first { $0.hostID == alpha && $0.kind == .ssh }?.count == 2)
        #expect(counts.first { $0.hostID == alpha && $0.kind == .ssh }?.date == today)
        #expect(counts.first { $0.hostID == alpha && $0.kind == .database }?.count == 1)
        #expect(counts.reduce(0) { $0 + $1.count } == 4)
        // No time of day travels: only the day, as its key. (This looked for ":00" in an encoding that
        // has no date in it to find, until 2026-10-24.)
        #expect(device.days.keys.allSatisfy { $0.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil }, "\(device.days.keys)")
    }

    @Test("minutes in use travel with the counts, under the same machines; a minute-only day is kept")
    func minutesTravel() throws {
        let alpha = HostID(), bravo = HostID()
        let today = GlassUsagePayload.dayKey(now, calendar: calendar)
        let old = GlassUsagePayload.dayKey(calendar.date(byAdding: .day, value: -40, to: now)!, calendar: calendar)
        let usage = [today: ["\(alpha.rawValue.uuidString)|ssh": 600, "\(bravo.rawValue.uuidString)|database": 5_000],
                     old: ["\(alpha.rawValue.uuidString)|ssh": 30]]
        let device = GlassUsagePayload.Device(name: "Ann's Mac", history: [event(alpha, .ssh, daysAgo: 0)],
                                              minutes: usage, now: now, calendar: calendar)
        #expect(device.hosts.count == 2, "alpha once, for its connection and its minutes")
        let decoded = try JSONDecoder().decode(GlassUsagePayload.Device.self, from: JSONEncoder().encode(device))
        let counts = decoded.counts(calendar: calendar)
        #expect(counts.first { $0.hostID == alpha }.map { [$0.count, $0.minutes] } == [1, 600])
        #expect(counts.first { $0.hostID == bravo }.map { [$0.count, $0.minutes] } == [0, 24 * 60],
                "a day holds at most 1,440 minutes")
        #expect(counts.count == 2, "40 days ago is outside the window")
        try GlassUsagePayload(devices: [UUID().uuidString: decoded]).validate()
    }

    @Test("a payload from before minutes still reads; one with more minutes than a day is refused")
    func minutesCompatibility() throws {
        let alpha = UUID()
        let older = Data(#"{"name":"headset","updatedAt":0,"hosts":["\#(alpha.uuidString)"],"days":{"2026-10-17":[{"host":0,"kind":"ssh","count":2}]}}"#.utf8)
        let device = try JSONDecoder().decode(GlassUsagePayload.Device.self, from: older)
        #expect(device.counts(calendar: calendar).map { [$0.count, $0.minutes] } == [[2, 0]])
        let tooMany = GlassUsagePayload(devices: [UUID().uuidString: .init(
            name: "x", updatedAt: now, hosts: [alpha.uuidString],
            days: ["2026-10-17": [.init(host: 0, kind: "ssh", count: 0, minutes: 24 * 60 + 1)]])])
        #expect(throws: GlassSettingsSyncError.self) { try tooMany.validate() }
    }

    @Test("each device's newest entry wins, and the other devices' are kept; every order agrees")
    func merging() throws {
        let mac = UUID().uuidString, phone = UUID().uuidString
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        let older = GlassUsagePayload(devices: [mac: .init(name: "Ann's Mac", updatedAt: early)])
        let newer = GlassUsagePayload(devices: [mac: .init(name: "Ann's Mac", updatedAt: late, hosts: [UUID().uuidString],
                                                            days: ["2026-10-17": [.init(host: 0, kind: "ssh", count: 3)]])])
        let other = GlassUsagePayload(devices: [phone: .init(name: "Work iPhone", updatedAt: early)])
        #expect(older.converged(with: newer) == newer && newer.converged(with: older) == newer)
        let both = newer.converged(with: other)
        #expect(both.devices.keys.sorted() == [mac, phone].sorted())
        #expect(both == other.converged(with: newer))
    }

    @Test("a payload whose counts name no machine is refused")
    func validating() {
        let bad = GlassUsagePayload(devices: [UUID().uuidString: .init(
            name: "alpha", updatedAt: now, hosts: [], days: ["2026-10-17": [.init(host: 0, kind: "ssh", count: 1)]])])
        #expect(throws: GlassSettingsSyncError.self) { try bad.validate() }
        #expect(throws: GlassSettingsSyncError.self) {
            try GlassUsagePayload(devices: ["not a device": .init(name: "x", updatedAt: now)]).validate()
        }
    }

    @Test("a kind this build has no name for is skipped, not the whole device")
    func unknownKind() {
        let alpha = UUID()
        let device = GlassUsagePayload.Device(name: "headset", updatedAt: now, hosts: [alpha.uuidString],
                                              days: ["2026-10-17": [.init(host: 0, kind: "ssh", count: 2),
                                                                    .init(host: 0, kind: "teleporter", count: 9)]])
        #expect(device.counts(calendar: calendar).map(\.count) == [2])
    }

    @Test("the overview adds every device's counts, and one device's alone when chosen")
    func statistics() throws {
        let alpha = GlassShellHost(members: [try HostProfile(displayName: "alpha")])
        let today = calendar.startOfDay(for: now)
        let mac = [GlassUsageCount(date: today, hostID: alpha.id, kind: .ssh, count: 3)]
        let phone = [GlassUsageCount(date: today, hostID: alpha.id, kind: .ssh, count: 2),
                     GlassUsageCount(date: today, hostID: alpha.id, kind: .database, count: 1)]
        let all = GlassLibraryStatistics.make(hosts: [alpha], isFavorite: { _ in false }, counts: mac + phone,
                                              now: now, calendar: calendar)
        #expect(all.connectionsInWindow == 6)
        #expect(all.mostUsed.first?.count == 6)
        #expect(all.perDay.first { $0.kind == .ssh }?.count == 5)
        let one = GlassLibraryStatistics.make(hosts: [alpha], isFavorite: { _ in false }, counts: phone,
                                              now: now, calendar: calendar)
        #expect(one.connectionsInWindow == 3)
    }

    private func makeModel(_ root: URL, _ name: String) -> GlassShellModel {
        GlassShellModel(storageDirectory: root.appendingPathComponent(name),
                        sharedContainerURL: nil, resolveSharedContainer: false,
                        accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
    }

    @Test("a connection made on one device is counted in the other's overview, under the device's name")
    func twoDevices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeModel(root, "mac"), phone = makeModel(root, "phone")
        await mac.load(); await phone.load()
        mac.setDeviceName("Ann's Mac")
        phone.setDeviceName("Work iPhone")
        _ = try await mac.adoptService(kind: .ssh, hostName: "alpha", address: "alpha.example", serviceName: "Terminal")
        let alpha = try #require(mac.catalogHosts.first { $0.displayName == "alpha" }).id

        let shared = GlassFavoritesSyncTests.SharedStore()
        await mac.startSynchronizingUsage(with: GlassSettingsSyncService(usageStore: shared.device()))
        await phone.startSynchronizingUsage(with: GlassSettingsSyncService(usageStore: shared.device()))

        mac.recordConnection(hostID: alpha, kind: .ssh)
        mac.recordConnection(hostID: alpha, kind: .ssh)
        for _ in 0..<50 where !(phone.usageByDevice.contains { $0.name == "Ann's Mac" && !$0.counts.isEmpty }) {
            try await Task.sleep(for: .milliseconds(20))
        }

        let devices = phone.usageByDevice
        #expect(devices.first?.isThisDevice == true, "this device first")
        #expect(devices.first?.name == "Work iPhone")
        let fromMac = try #require(devices.first { $0.name == "Ann's Mac" }, "the Mac's counts never arrived: \(devices.map(\.name))")
        #expect(!fromMac.isThisDevice)
        #expect(fromMac.counts.map(\.hostID) == [alpha])
        #expect(fromMac.counts.reduce(0) { $0 + $1.count } == 2)
    }
}
