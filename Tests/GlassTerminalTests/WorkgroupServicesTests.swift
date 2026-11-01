import Foundation
import Testing
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers
import GlassShell
@testable import GlassTerminal

/// A workgroup's databases and remote desktops (B-F40, 2026-11-01): kept beside its terminals,
/// synced with them, and opened as the library's Connect opens each.
@MainActor
@Suite("Workgroup databases and desktops")
struct WorkgroupServicesTests {
    @Test("databases and desktops alone make a workgroup; nothing at all does not; at most sixteen")
    func validity() {
        var services = LayoutPreset(name: "Data", serverIDs: [])
        #expect(!services.isValidForPersistence, "no terminals and nothing else")
        services.services = [UUID(), UUID()]
        #expect(services.isValidForPersistence, "a database and a desktop, no terminals")
        services.services = (0...LayoutPreset.maximumServiceCount).map { _ in UUID() }
        #expect(!services.isValidForPersistence, "seventeen")
        var both = LayoutPreset(name: "Shop", serverIDs: [UUID()])
        both.services = [UUID()]
        #expect(both.isValidForPersistence)
    }

    @Test("kept in the saved form only when there are any, and read back; one saved before them reads none")
    func coding() throws {
        let plain = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        let plainJSON = try JSONEncoder().encode(plain)
        #expect(!String(decoding: plainJSON, as: UTF8.self).contains("\"services\""),
                "a workgroup without them saves as before")
        #expect(try JSONDecoder().decode(LayoutPreset.self, from: plainJSON).services.isEmpty)

        var mixed = plain
        mixed.services = [UUID(), UUID()]
        let read = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(mixed))
        #expect(read.services == mixed.services && read == mixed)

        // Ones that can't be read cost the workgroup them, never the workgroup.
        var object = try #require(JSONSerialization.jsonObject(with: plainJSON) as? [String: Any])
        object["services"] = ["not a uuid"]
        let damaged = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(damaged.services.isEmpty && damaged.sessionIntents == plain.sessionIntents)
    }

    @Test("saved on one device with its databases and desktops, it arrives with them; one of them alone travels too")
    func travels() async throws {
        let shared = WorkgroupsSyncTests.SharedStore()
        let (mac, macDefaults, macSuite) = try device(shared)
        let (phone, phoneDefaults, phoneSuite) = try device(shared)
        defer {
            macDefaults.removePersistentDomain(forName: macSuite)
            phoneDefaults.removePersistentDomain(forName: phoneSuite)
        }
        mac.startWorkgroupsSync()
        phone.startWorkgroupsSync()
        try await Task.sleep(for: .milliseconds(50))

        var mixed = LayoutPreset(name: "Shop", serverIDs: [UUID()])
        mixed.services = [UUID(), UUID()]
        var alone = LayoutPreset(name: "Dashboards", serverIDs: [])
        alone.services = [UUID()]
        mac.upsertLayoutPreset(mixed)
        mac.upsertLayoutPreset(alone)
        await eventually { phone.layoutPresets.count == 2 }
        #expect(phone.layoutPresets.first { $0.id == mixed.id }?.services == mixed.services)
        #expect(phone.layoutPresets.first { $0.id == alone.id }?.services == alone.services)
    }

    @Test("opening connects each through the library, shows one open already, and counts those the library lost")
    func opening() {
        let runtime = GlassTerminalRuntime(layers: GlassLayerStore.forTest())
        let database = UUID(), desktop = UUID(), gone = UUID()
        var events: [String] = []
        runtime.openSessions = {
            [GlassOpenSession(id: "desktop:1", title: "Desk", symbolName: "display",
                              endpointIDs: [EndpointID(rawValue: desktop)],
                              activate: { events.append("shown desktop") }, close: {})]
        }
        runtime.describeService = { id in
            guard id != gone else { return nil }
            return GlassFavoriteDescription(title: "\(id)", subtitle: "", symbol: .system("cylinder"),
                                            open: { events.append(id == database ? "connected database" : "connected desktop") })
        }
        var preset = LayoutPreset(name: "Shop", serverIDs: [UUID()])
        preset.services = [database, desktop, gone]

        #expect(runtime.openServices(of: preset) == 1, "the one the library lost")
        #expect(events == ["connected database", "shown desktop"], "the open desktop shown, never connected again")
    }

    private func device(_ shared: WorkgroupsSyncTests.SharedStore) throws -> (SettingsManager, UserDefaults, String) {
        let suite = "WorkgroupServices.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults,
                                       workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: shared.device()))
        return (settings, defaults, suite)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }
}
