//
//  TestSettings.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Terminal settings of a test's own. `SettingsManager(loadImmediately: false)` keeps its settings in
//  the process's standard domain — shared by every test in the run, and by every run — builds its
//  layer store there and migrates the owner's old preferences into it, and syncs workgroups through
//  the real iCloud key-value store (2026-10-24, the test audit).
//

import Foundation
import GlassLayers
import GlassShell
@testable import GlassTerminal

/// An iCloud key-value store in memory: available, signed in, and talking to nobody.
@MainActor
final class InMemorySettingsStore: GlassSettingsKeyValueStore {
    private var values: [String: Data] = [:]
    var isAvailable: Bool { true }
    var isAccountAvailable: Bool { true }
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data, forKey key: String) { values[key] = data }
    func synchronize() async -> Bool { true }
    func observeExternalChanges(_ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void) -> NSObjectProtocol {
        NSObject()
    }
    func removeExternalChangeObserver(_ observer: NSObjectProtocol) {}
}

extension SettingsManager {
    /// Its own defaults suite, removed when the process exits; its own layer store; and both sync
    /// services on stores in memory.
    @MainActor static func forTest(loadImmediately: Bool = false) -> SettingsManager {
        let defaults = UserDefaults.forTest(suiteName: "sh.glas.test.settings.\(UUID().uuidString)")!
        return SettingsManager(loadImmediately: loadImmediately, settingsDefaults: defaults, sshKeyDefaults: defaults,
                               iCloudSettingsSyncService: ICloudSettingsSyncService(store: InMemorySettingsStore(), writerID: UUID()),
                               workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: InMemorySettingsStore()),
                               layers: GlassLayerStore.forTest())
    }
}
