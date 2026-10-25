//
//  GlassFavoriteItemsTests.swift
//  Glass Power Tools — GlassShellTests
//
//  The rest of Favorites (the owner, 2026-10-13: "Favorites should be machines OR services OR
//  projects OR Workgroups OR SFTP (at the current folder depth)"): services, projects, workgroups and
//  folders, starred on one device and kept on all of them by D49's rule, under a key of their own so
//  an older build's machine favourites are untouched.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@MainActor
@Suite("Favourites beyond machines")
struct GlassFavoriteItemsTests {
    private typealias SharedStore = GlassFavoritesSyncTests.SharedStore

    private func makeModel(_ root: URL, _ name: String) -> GlassShellModel {
        GlassShellModel(storageDirectory: root.appendingPathComponent(name),
                        sharedContainerURL: nil, resolveSharedContainer: false,
                        accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
    }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FavoriteItems-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("each kind can be starred and unstarred, comes back after a relaunch, and lists in section order")
    func starring() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root, "mac")
        await model.load()
        let service = GlassFavorite.service(EndpointID())
        let project = GlassFavorite.project(UUID())
        let workgroup = GlassFavorite.workgroup(UUID())
        let logs = GlassFavorite.folder(endpoint: EndpointID(), path: "/var/log")
        let older = Date(timeIntervalSince1970: 1_000), newer = Date(timeIntervalSince1970: 2_000)

        model.setFavorite(logs, true, at: older)
        model.setFavorite(workgroup, true, at: older)
        model.setFavorite(project, true, at: older)
        model.setFavorite(service, true, at: older)
        let etc = GlassFavorite.folder(endpoint: EndpointID(), path: "/etc")
        model.setFavorite(etc, true, at: newer)
        #expect(model.favoriteItems == [service, project, workgroup, etc, logs],
                "by kind, and the newest star first within one")

        model.toggleFavorite(project)
        #expect(!model.isFavorite(project))

        let relaunched = makeModel(root, "mac")
        await relaunched.load()
        #expect(relaunched.favoriteItems == [service, workgroup, etc, logs])
        #expect(!relaunched.isFavorite(project))
    }

    @Test("a folder must be an absolute path without control characters; a bad one is never kept")
    func folderPaths() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root, "mac")
        await model.load()
        for path in ["var/log", "/tmp/a\nb", "/" + String(repeating: "a", count: GlassFavorite.maximumPathLength)] {
            model.setFavorite(.folder(endpoint: EndpointID(), path: path), true)
        }
        #expect(model.favoriteItems.isEmpty)

        let good = GlassFavorite.folder(endpoint: EndpointID(), path: "/srv/app")
        let mark = GlassFavoriteItemsPayload.Mark(item: good, isFavorite: true, changedAt: Date())
        #expect(throws: Never.self) { try GlassFavoriteItemsPayload(marks: [good.key: mark]).validate() }
        #expect(throws: GlassSettingsSyncError.self) {
            try GlassFavoriteItemsPayload(marks: ["service:\(UUID().uuidString)": mark]).validate()
        }
        let bad = GlassFavorite.folder(endpoint: EndpointID(), path: "relative")
        #expect(throws: GlassSettingsSyncError.self) {
            try GlassFavoriteItemsPayload(marks: [bad.key: .init(item: bad, isFavorite: true, changedAt: Date())]).validate()
        }
    }

    @Test("a star made on one device arrives on the other, an unstar travels, and an older change never wins")
    func twoDevices() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let mac = makeModel(root, "mac"), phone = makeModel(root, "phone")
        await mac.load(); await phone.load()
        let shared = SharedStore()
        await mac.startSynchronizingFavoriteItems(with: GlassSettingsSyncService(favoriteItemsStore: shared.device()))
        await phone.startSynchronizingFavoriteItems(with: GlassSettingsSyncService(favoriteItemsStore: shared.device()))

        let logs = GlassFavorite.folder(endpoint: EndpointID(), path: "/var/log")
        mac.toggleFavorite(logs)
        for _ in 0..<100 where !phone.isFavorite(logs) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(phone.isFavorite(logs))

        try await Task.sleep(for: .milliseconds(5))
        phone.toggleFavorite(logs)
        mac.applyFavoriteItems(phone.favoriteItemsPayload)
        #expect(!mac.isFavorite(logs), "the unstar did not travel")

        mac.applyFavoriteItems(GlassFavoriteItemsPayload(marks: [logs.key: .init(item: logs, isFavorite: true, changedAt: .distantPast)]))
        #expect(!mac.isFavorite(logs), "an older star undid a newer unstar")
    }

    @Test("machine favourites keep their own key, so an older build neither reads nor overwrites these")
    func separateKey() async throws {
        #expect(GlassSettingsSyncService<GlassFavoriteItemsPayload>.favoriteItemsStoreKey
                != GlassSettingsSyncService<GlassFavoritesPayload>.favoritesStoreKey)
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root, "mac")
        await model.load()
        model.toggleFavorite(.workgroup(UUID()))
        #expect(model.favoritesPayload.marks.isEmpty, "a workgroup became a machine favourite")
    }

    @Test("an unstar is kept long enough to travel, then dropped")
    func tombstones() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root, "mac")
        await model.load()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let gone = GlassFavorite.project(UUID())
        model.setFavorite(gone, true, at: start)
        model.setFavorite(gone, false, at: start)
        #expect(model.favoriteItemsPayload.marks[gone.key]?.isFavorite == false, "the unstar must travel")
        model.setFavorite(.workgroup(UUID()), true, at: start.addingTimeInterval(GlassShellModel.favoriteTombstoneLifetime + 1))
        #expect(model.favoriteItemsPayload.marks[gone.key] == nil)
    }

    @Test("preferences written before these existed still read")
    func olderPreferences() throws {
        // A file as this build writes it with no favourites beyond machines, minus the key: what an
        // older build wrote.
        var older = GlassShellPreferences()
        older[host: HostID()].isFavorite = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(older)) as? [String: Any])
        object["favoriteItems"] = nil
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(GlassShellPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.favoriteItems == nil)
        #expect(decoded.hosts.values.first?.isFavorite == true)
    }

    @Test("Favorites lists what it can name: a service by its machine, the rest as described, filtered by search")
    func rows() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root, "mac")
        await model.load()
        _ = try await model.adoptService(kind: .ssh, hostName: "alpha", address: "alpha.example", serviceName: "Terminal")
        let alpha = try #require(model.catalogHosts.first { $0.displayName == "alpha" })
        let terminal = try #require(model.host(alpha.id)?.services.first { $0.kind == .ssh })

        let deploy = UUID(), gone = UUID()
        model.describeFavorite = { item in
            guard case .workgroup(let id) = item, id == deploy else { return nil }
            return GlassFavoriteDescription(title: "Deploy", subtitle: "3 terminals", symbol: .system("rectangle.3.group"),
                                            open: {})
        }
        model.toggleFavorite(.service(terminal.endpointID))
        model.toggleFavorite(.workgroup(deploy))
        model.toggleFavorite(.project(gone))

        let rows = model.favoriteRows(matching: "")
        #expect(rows.map(\.description.title) == ["alpha", "Deploy"],
                "a service called only by its kind is named by its machine; what is gone is not listed")
        #expect(rows.first?.description.openTitle == "Connect")
        #expect(model.favoriteRows(matching: "terminals").map(\.description.title) == ["Deploy"])
        #expect(model.favoriteRows(matching: "nothing like it").isEmpty)
        #expect(model.isFavorite(.project(gone)), "the star stays, for when the project arrives")

        // The service removed: its favourite is no longer listed.
        try await model.removeService(terminal.endpointID, from: alpha.id)
        #expect(model.favoriteRows(matching: "").map(\.description.title) == ["Deploy"])
    }
}
