import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// Favourites on every device (2026-10-08): the newest change per host wins, an unfavourite
/// travels like a favourite, earlier favourites are kept together, and the device's own host stays
/// its own.
@MainActor
@Suite("Favourites sync")
struct GlassFavoritesSyncTests {
    /// iCloud's key-value store as two devices see it: one value, and a change notice for the other.
    @MainActor final class SharedStore {
        var value: [String: Data] = [:]
        var devices: [DeviceStore] = []
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

    private func makeModel(_ root: URL, _ name: String) -> GlassShellModel {
        GlassShellModel(storageDirectory: root.appendingPathComponent(name),
                        sharedContainerURL: nil, resolveSharedContainer: false,
                        accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
    }

    @Test("the newest change per host wins; on a tie, the favourite; every order agrees")
    func merging() {
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        let host = UUID().uuidString
        let on = GlassFavoritesPayload(marks: [host: .init(isFavorite: true, changedAt: early)])
        let off = GlassFavoritesPayload(marks: [host: .init(isFavorite: false, changedAt: late)])
        #expect(on.converged(with: off) == off && off.converged(with: on) == off, "turning it off later wins")

        let tieOff = GlassFavoritesPayload(marks: [host: .init(isFavorite: false, changedAt: early)])
        #expect(on.converged(with: tieOff) == on && tieOff.converged(with: on) == on)

        let other = UUID().uuidString
        let legacyHere = GlassFavoritesPayload(marks: [host: .init(isFavorite: true, changedAt: GlassFavoritesPayload.legacyChange)])
        let legacyThere = GlassFavoritesPayload(marks: [other: .init(isFavorite: true, changedAt: GlassFavoritesPayload.legacyChange)])
        #expect(legacyHere.converged(with: legacyThere).marks.count == 2, "earlier favourites from each device are kept together")

        #expect(throws: GlassSettingsSyncError.self) { try GlassFavoritesPayload(marks: ["not a host": on.marks[host]!]).validate() }
    }

    @Test("a favourite made on one device arrives on the other, and so does taking it away")
    func twoDevices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Favorites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeModel(root, "mac"), phone = makeModel(root, "phone")
        await mac.load(); await phone.load()
        _ = try await mac.adoptService(kind: .ssh, hostName: "alpha", address: "alpha.example", serviceName: "Terminal")
        let alpha = try #require(mac.catalogHosts.first { $0.displayName == "alpha" }).id

        let shared = SharedStore()
        await mac.startSynchronizingFavorites(with: GlassSettingsSyncService(favoritesStore: shared.device()))
        await phone.startSynchronizingFavorites(with: GlassSettingsSyncService(favoritesStore: shared.device()))

        mac.toggleFavorite(alpha)
        for _ in 0..<100 where phone.favoritesPayload.marks[alpha.rawValue.uuidString]?.isFavorite != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(phone.favoritesPayload.marks[alpha.rawValue.uuidString]?.isFavorite == true)

        // The phone takes it away; the Mac follows.
        try await Task.sleep(for: .milliseconds(5))
        phone.applyFavorites(GlassFavoritesPayload(marks: [alpha.rawValue.uuidString: .init(isFavorite: false, changedAt: Date())]))
        #expect(phone.favoritesPayload.marks[alpha.rawValue.uuidString]?.isFavorite == false)
        mac.applyFavorites(phone.favoritesPayload)
        #expect(!mac.isFavorite(alpha))

        // An older change never undoes a newer one.
        mac.applyFavorites(GlassFavoritesPayload(marks: [alpha.rawValue.uuidString: .init(isFavorite: true, changedAt: .distantPast)]))
        #expect(!mac.isFavorite(alpha))
    }

    @Test("the device's own host is not synced: a favourite This Mac is not a favourite This iPhone")
    func ownHostStaysHere() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Favorites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeModel(root, "mac")
        await mac.load()
        mac.toggleFavorite(GlassLocalHost.id)
        #expect(mac.isFavorite(GlassLocalHost.id))
        #expect(mac.favoritesPayload.marks[GlassLocalHost.id.rawValue.uuidString] == nil)
        mac.toggleFavorite(GlassLocalHost.id)
        mac.applyFavorites(GlassFavoritesPayload(marks: [GlassLocalHost.id.rawValue.uuidString: .init(isFavorite: true, changedAt: Date())]))
        #expect(!mac.isFavorite(GlassLocalHost.id), "another device's own host never marks this one")
    }
}
