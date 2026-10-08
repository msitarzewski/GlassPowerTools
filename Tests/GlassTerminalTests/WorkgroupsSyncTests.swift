import Foundation
import Testing
import GlassShell
@testable import GlassTerminal

/// Workgroups on every device (2026-10-08): the newest change per workgroup wins, a deletion
/// travels, and when one was last opened stays on the device.
@MainActor
@Suite("Workgroups sync")
struct WorkgroupsSyncTests {
    @MainActor final class SharedStore {
        var value: [String: Data] = [:]
        var devices: [DeviceStore] = []
        var writes = 0
        func device() -> DeviceStore { let store = DeviceStore(shared: self); devices.append(store); return store }
    }

    @MainActor final class DeviceStore: GlassSettingsKeyValueStore {
        let shared: SharedStore
        var handler: (@MainActor @Sendable (GlassSettingsStoreChange) -> Void)?
        init(shared: SharedStore) { self.shared = shared }
        var isAvailable: Bool { true }
        var isAccountAvailable: Bool { true }
        func data(forKey key: String) -> Data? { shared.value[key] }
        func set(_ data: Data, forKey key: String) {
            shared.value[key] = data
            shared.writes += 1
            for other in shared.devices where other !== self {
                other.handler?(GlassSettingsStoreChange(reason: .server, changedKeys: [key]))
            }
        }
        func synchronize() async -> Bool { true }
        func observeExternalChanges(_ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void) -> NSObjectProtocol {
            self.handler = handler
            return NSObject()
        }
        func removeExternalChangeObserver(_ observer: NSObjectProtocol) { handler = nil }
    }

    private func device(_ shared: SharedStore) throws -> (SettingsManager, UserDefaults, String) {
        let suite = "WorkgroupsSync.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults,
                                       workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: shared.device()))
        return (settings, defaults, suite)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("the newest change per workgroup wins; a deletion is a change; every order agrees")
    func merging() {
        let id = UUID()
        let saved = ICloudWorkgroupsPayload.Record(id: id, changedAt: Date(timeIntervalSince1970: 1_000), preset: Data("a".utf8))
        let deleted = ICloudWorkgroupsPayload.Record(id: id, changedAt: Date(timeIntervalSince1970: 2_000), preset: nil)
        let one = ICloudWorkgroupsPayload(records: [saved]), two = ICloudWorkgroupsPayload(records: [deleted])
        #expect(one.converged(with: two) == two && two.converged(with: one) == two)
        let tie = ICloudWorkgroupsPayload.Record(id: id, changedAt: saved.changedAt, preset: nil)
        #expect(ICloudWorkgroupsPayload.newer(saved, tie) == saved && ICloudWorkgroupsPayload.newer(tie, saved) == saved,
                "on a tie the workgroup outlives its deletion")
    }

    @Test("saved on one device, it appears on the other; deleted there, it goes here too")
    func twoDevices() async throws {
        let shared = SharedStore()
        let (mac, macDefaults, macSuite) = try device(shared)
        let (headset, headsetDefaults, headsetSuite) = try device(shared)
        defer {
            macDefaults.removePersistentDomain(forName: macSuite)
            headsetDefaults.removePersistentDomain(forName: headsetSuite)
        }
        mac.startWorkgroupsSync()
        headset.startWorkgroupsSync()
        try await Task.sleep(for: .milliseconds(50))

        let preset = LayoutPreset(name: "Builds", serverIDs: [UUID(), UUID()])
        mac.upsertLayoutPreset(preset)
        await eventually { headset.layoutPresets.contains { $0.id == preset.id } }
        let arrived = try #require(headset.layoutPresets.first { $0.id == preset.id })
        #expect(arrived.name == "Builds" && arrived.serverIDs == preset.serverIDs)

        // Opening it is this device's business: nothing is sent.
        let writes = shared.writes
        headset.updateLayoutPresetLastUsed(preset.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(shared.writes == writes)

        try await Task.sleep(for: .milliseconds(5))
        headset.deleteLayoutPreset(arrived)
        await eventually { !mac.layoutPresets.contains { $0.id == preset.id } }
        #expect(!mac.layoutPresets.contains { $0.id == preset.id }, "deleting travels")
    }

    /// D51's clock was never written: after a relaunch every workgroup counted from when it was
    /// made, so an edit not yet sent could lose to an older copy from another device.
    @Test("when a workgroup was last saved survives a relaunch, and stays its sync clock")
    func savedTimeSurvivesRelaunch() throws {
        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()], createdAt: Date(timeIntervalSince1970: 1_000))
        preset.modifiedAt = Date(timeIntervalSince1970: 2_000.25)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded.modifiedAt == preset.modifiedAt)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as! [String: Any]
        old.removeValue(forKey: "modifiedAt")
        #expect(try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: old)).modifiedAt == nil,
                "a workgroup saved before it had one still reads, counting from createdAt")

        let suite = "WorkgroupsSync.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        settings.upsertLayoutPreset(preset)
        let saved = try #require(settings.layoutPresets.first?.modifiedAt)
        #expect(saved > preset.createdAt)

        let relaunched = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        relaunched.loadLayoutPresets()
        #expect(relaunched.layoutPresets.first?.modifiedAt == saved)
        #expect(relaunched.workgroupsPayload.records.first?.changedAt == saved, "not createdAt")
    }
}
