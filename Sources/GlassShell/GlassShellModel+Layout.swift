//
//  GlassShellModel+Layout.swift
//  Glass Power Tools — GlassShell
//
//  The shared layout in the library (phase 1, 2026-11-22): what this device has open, gathered from every capability
//  and published whenever it changes; the other devices' windows, for Active. Plan:
//  memory-bank/tasks/2026-11/2026-11-21_shared-layout.md.
//

import Foundation
import Observation
import GlassConnectionKit
import GlassLayers

/// Another device's windows as Active lists them.
public struct GlassLayoutDevice: Identifiable, Equatable {
    public struct Window: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let tabs: [Tab]
    }

    public struct Tab: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        /// Where it is: its machine and whether it's kept in tmux, or the device a shell lives on.
        public let detail: String
    }

    public let id: String
    public let name: String
    public let windows: [Window]
}

public extension GlassShellModel {
    /// The setting: this device's windows in the layout, and the other devices' in Active. On unless turned off.
    static let sharesLayoutKey = "com.glasspowertools.layout.sharesWindows"

    static var sharesLayout: Bool {
        (GlassUITestRun.settingsDefaults.object(forKey: sharesLayoutKey) as? Bool) ?? true
    }

    /// Starts the shared layout's sync through `backend`: CloudKit in the app, a store in memory in a test.
    func enableLayoutSync(_ backend: any GlassLayoutSyncBackend) {
        guard layoutSync == nil else { return }
        let sync = GlassLayoutSync(
            backend: backend,
            snapshot: { [weak self] in self?.layoutSnapshot() },
            loadPublished: { [weak self] in self?.layoutPublished ?? [] },
            savePublished: { [weak self] in self?.layoutPublished = $0 },
            device: { [weak self] in (self?.thisDeviceKey ?? "", self?.deviceName ?? "") })
        layoutSync = sync
        Task { [weak self] in
            try? await backend.subscribeToChanges()
            self?.listenForLayoutChanges()
        }
        watchLayout()
    }

    /// The setting changed: this device's windows go into the layout or leave it.
    func layoutSettingChanged() {
        layoutSync?.publishSoon(after: .zero)
    }

    /// The layout's sync in a few words, as the library's is said (`catalogSyncStatusDescription`).
    static func layoutStatusDescription(_ status: GlassCatalogSyncStatus) -> String {
        switch status {
        case .idle: "Waiting to sync"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let reason, _): reason
        case .failed(let message): "Not synced — \(message)"
        }
    }

    /// Every other device's open windows, by device, for Active. Nothing while the setting is off.
    func layoutOnOtherDevices() -> [GlassLayoutDevice] {
        guard Self.sharesLayout, let account = layoutSync?.account else { return [] }
        var byDevice: [String: (name: String, windows: [GlassLayoutDevice.Window])] = [:]
        for window in account.openWindows where window.device != thisDeviceKey {
            let tabs = account.openTabs(in: window.id).map { tab in
                GlassLayoutDevice.Tab(id: tab.id, title: tab.title, detail: layoutDetail(of: tab))
            }
            guard !tabs.isEmpty else { continue }
            byDevice[window.device, default: (window.deviceName, [])].windows
                .append(GlassLayoutDevice.Window(id: window.id, name: window.name, tabs: tabs))
        }
        return byDevice.map { GlassLayoutDevice(id: $0.key, name: $0.value.name, windows: $0.value.windows) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

extension GlassShellModel {
    /// What every capability has open here; nil while any can't say yet. With the setting off, nothing: this device's
    /// windows leave the layout.
    func layoutSnapshot() -> GlassLayoutSnapshot? {
        guard isLoaded else { return nil }
        guard Self.sharesLayout else { return GlassLayoutSnapshot(windows: []) }
        return registry.layoutSnapshot()
    }

    /// "alpha · in tmux", "On Mac, not in tmux".
    func layoutDetail(of tab: GlassLayoutTab) -> String {
        if let device = tab.shellDeviceName, tab.shellDevice != nil {
            let machine = tab.endpointID.flatMap { host(owningEndpoint: $0)?.displayName }
            return machine.map { "\($0), on \(device), not in tmux" } ?? "On \(device), not in tmux"
        }
        let machine = tab.endpointID.flatMap { host(owningEndpoint: $0)?.displayName } ?? "A machine not in this library"
        return "\(machine) · in tmux"
    }

    /// Publishes a moment after anything a snapshot reads changes, and watches again.
    func watchLayout() {
        withObservationTracking {
            _ = layoutSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.layoutSync?.publishSoon()
                // Watched again after a second: a terminal printing changes its title many times a second, and each
                // change needn't build the snapshot again to be noticed.
                try? await Task.sleep(for: .seconds(1))
                self?.watchLayout()
            }
        }
    }

    /// Reads the layout again whenever iCloud says something changed elsewhere: the same notice the library's sync
    /// hears (every push in the container is one).
    func listenForLayoutChanges() {
        guard layoutChangesTask == nil else { return }
        layoutChangesTask = Task { [weak self] in
            for await notice in NotificationCenter.default.notifications(named: Self.remoteChangeNotification) {
                guard let self, !Task.isCancelled else { return }
                guard notice.object == nil || (notice.object as AnyObject?) === self else { continue }
                await layoutSync?.synchronize()
            }
        }
    }
}
