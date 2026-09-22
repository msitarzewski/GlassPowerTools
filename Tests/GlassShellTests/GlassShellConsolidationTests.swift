import SwiftUI
import GlassLayers
import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
@testable import GlassShell

/// Records written by different family apps for the same machine are one library host.
@MainActor
private func makeModel() throws -> (GlassShellModel, URL, HostCatalogStore) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellConsolidation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore())
    // Another app's writer, as glas.sh and glassDT are today.
    let sibling = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
    return (model, root, sibling)
}

private func record(_ name: String, aliases: [String] = [], kinds: [HostServiceKind], createdAt: Date) throws -> HostProfile {
    try HostProfile(displayName: name, aliases: aliases,
                    services: kinds.map { HostServiceLink(endpointID: EndpointID(), kind: $0, displayName: "\($0.rawValue) on \(name)") },
                    createdAt: createdAt, updatedAt: createdAt)
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
private final class RecordingCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { "Recorder" }
    var symbolName: String { "circle" }
    var opened: [(HostServiceLink, HostProfile)] = []
    /// The shell's outcome callback for the latest `open`; tests deliver it explicitly.
    var pendingReport: ((GlassCapabilityOutcome) -> Void)?
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
        opened.append((service, host))
        pendingReport = report
    }
}

@Suite("GlassShell host consolidation", .serialized)
@MainActor
struct GlassShellConsolidationTests {
    @Test("Two records with the same name in different case are one host with both services")
    func sameNameDifferentCase() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", kinds: [.ssh], createdAt: t0)
        let newer = try record("Juliet.local", kinds: [.rdp], createdAt: t0.addingTimeInterval(60))
        try await sibling.upsert(newer)
        try await sibling.upsert(older)
        await model.load()

        // Two records a moment ago; one after load, because consolidation runs itself now
        // (2026-09-21). The group projection is the mechanism, no longer a lasting state.
        #expect(model.records.count == 1)
        #expect(model.catalogHosts.count == 1)
        let host = try #require(model.catalogHosts.first)
        #expect(host.id == older.id, "canonical is the oldest record")
        #expect(host.displayName == "juliet")
        #expect(host.services.count == 2)
        #expect(model.serviceKinds(for: host.id) == [.rdp, .ssh])
        #expect(model.catalogItems.count == 1)
        #expect(model.catalogItems.first?.subtitle == "Desktop · Terminal")
        #expect(host.member(owning: newer.services[0].endpointID)?.id == older.id,
                "the newer record's service now lives on the canonical record")
    }

    @Test("A shared alias groups records whose names differ")
    func aliasOverlapGroups() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        try await sibling.upsert(try record("Max Beast", aliases: ["10.0.0.5"], kinds: [.ssh], createdAt: t0))
        try await sibling.upsert(try record("juliet-desktop", aliases: ["10.0.0.5"], kinds: [.rdp], createdAt: t0.addingTimeInterval(1)))
        await model.load()
        #expect(model.catalogHosts.count == 1)
        #expect(model.catalogHosts.first?.services.count == 2)
        #expect(model.catalogHosts.first?.aliases == ["10.0.0.5"])
    }

    @Test("Unrelated names stay separate, and loopback aliases never group")
    func unrelatedStaySeparate() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        try await sibling.upsert(try record("alpha", aliases: ["127.0.0.1"], kinds: [.ssh], createdAt: t0))
        try await sibling.upsert(try record("beta", aliases: ["localhost"], kinds: [.database], createdAt: t0))
        try await sibling.upsert(try record("gamma", kinds: [.rdp], createdAt: t0))
        await model.load()
        #expect(model.catalogHosts.count == 3)
        #expect(model.catalogHosts.allSatisfy { !$0.isConsolidated })
    }

    @Test("A record that already holds two services is one host and is left exactly as stored")
    func alreadySingleRecordUntouched() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let oscar = try record("oscar", kinds: [.rdp, .ssh], createdAt: t0)
        try await sibling.upsert(oscar)
        await model.load()
        let host = try #require(model.catalogHosts.first)
        #expect(host.id == oscar.id)
        #expect(!host.isConsolidated)
        #expect(host.services.map(\.endpointID) == oscar.services.map(\.endpointID))
        let stored = try await sibling.snapshot()
        #expect(stored.count == 1)
        #expect(stored.first?.id == oscar.id && stored.first?.services == oscar.services
                && stored.first?.displayName == oscar.displayName, "nothing rewritten")
    }

    @Test("Preferences keyed on a member record migrate to the canonical id once")
    func preferencesMigrate() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", kinds: [.ssh], createdAt: t0)
        let newer = try record("juliet", kinds: [.rdp], createdAt: t0.addingTimeInterval(60))
        try await sibling.upsert(older); try await sibling.upsert(newer)
        // A favorite and a connection recorded against the newer record before grouping existed.
        var prefs = GlassShellPreferences()
        prefs[host: newer.id].isFavorite = true
        prefs[host: newer.id].lastConnected = t0.addingTimeInterval(500)
        prefs[host: newer.id].lastUsedEndpointID = newer.services[0].endpointID
        try GlassShellPreferencesStore(fileURL: root.appendingPathComponent("app/shell-preferences.json")).save(prefs)
        // A fresh model reads those preferences at init, as a launch would.
        _ = model
        let fresh = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore())
        await fresh.load()
        #expect(fresh.isFavorite(older.id))
        #expect(fresh.isFavorite(newer.id), "member id resolves to the canonical preference")
        #expect(fresh.lastConnected(older.id) == t0.addingTimeInterval(500))
        #expect(fresh.lastUsedService(for: older.id)?.endpointID == newer.services[0].endpointID)
        let saved = GlassShellPreferencesStore(fileURL: root.appendingPathComponent("app/shell-preferences.json")).load().preferences
        #expect(saved.hosts[newer.id] == nil, "stray record removed")
        #expect(saved.hosts[older.id]?.isFavorite == true)
    }

    @Test("Deleting a host deletes every member record")
    func deleteRemovesAllMembers() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        try await sibling.upsert(try record("juliet", kinds: [.ssh], createdAt: t0))
        try await sibling.upsert(try record("juliet", kinds: [.rdp], createdAt: t0.addingTimeInterval(1)))
        try await sibling.upsert(try record("other", kinds: [.ssh], createdAt: t0))
        await model.load()
        let host = try #require(model.catalogHosts.first { $0.displayName == "juliet" })
        try await model.deleteHost(host.id)
        #expect(model.catalogHosts.map(\.displayName) == ["other"])
        #expect(try await sibling.snapshot().count == 1)
    }

    @Test("Adding a service goes to the canonical record; removing one leaves the owning record")
    func addAndRemoveService() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", kinds: [.ssh], createdAt: t0)
        let newer = try record("juliet", kinds: [.rdp], createdAt: t0.addingTimeInterval(1))
        try await sibling.upsert(older); try await sibling.upsert(newer)
        await model.load()
        // `newer.id` is a tombstone after load; adding through it still lands on the machine it
        // meant, because a merged member id keeps resolving to its canonical record.
        let added = try await model.addService(kind: .database, displayName: "db", to: newer.id)
        let stored = try await sibling.snapshot()
        #expect(stored.count == 1)
        #expect(stored.first { $0.id == older.id }?.services.contains { $0.endpointID == added.endpointID } == true)
        #expect(stored.first { $0.id == newer.id } == nil, "the member record was folded in and deleted")
        #expect(model.catalogHosts.first?.services.count == 3)

        try await model.removeService(newer.services[0].endpointID, from: older.id)
        let after = try await sibling.snapshot()
        #expect(after.first { $0.id == older.id }?.services.count == 2)
        #expect(model.catalogHosts.first?.services.count == 2)
    }

    @Test("The picker lists every service of the group and Connect hands the owning record to the capability")
    func pickerAndConnect() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", kinds: [.ssh], createdAt: t0)
        let newer = try record("juliet", kinds: [.rdp], createdAt: t0.addingTimeInterval(1))
        try await sibling.upsert(older); try await sibling.upsert(newer)
        let desktop = RecordingCapability(kind: .rdp)
        model.registry.register(desktop)
        await model.load()
        let host = try #require(model.catalogHosts.first)
        #expect(Set(model.services(for: host.id).map(\.endpointID)) == Set([older.services[0].endpointID, newer.services[0].endpointID]))
        model.connect(hostID: newer.id, endpointID: newer.services[0].endpointID)
        #expect(desktop.opened.count == 1)
        #expect(desktop.opened.first?.1.id == older.id, "the record that owns the endpoint — the canonical one, after consolidation")
        #expect(model.lastUsedService(for: host.id)?.endpointID == newer.services[0].endpointID)
        #expect(model.lastConnected(host.id) == nil, "opened is not connected: the capability has not reported yet")
        desktop.pendingReport?(.connected)
        #expect(model.lastConnected(host.id) != nil, "stamped when the capability reports a live session")
    }

    @Test("A failed or dismissed attempt never stamps last connected; the chosen service is still remembered")
    func failedAttemptDoesNotStampLastConnected() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try record("juliet", kinds: [.ssh], createdAt: t0)
        try await sibling.upsert(record)
        let terminal = RecordingCapability(kind: .ssh)
        model.registry.register(terminal)
        await model.load()
        let host = try #require(model.catalogHosts.first)

        model.connect(hostID: host.id)
        terminal.pendingReport?(.failed("authentication failed"))
        #expect(model.lastConnected(host.id) == nil)
        #expect(model.lastUsedService(for: host.id)?.endpointID == record.services[0].endpointID)

        model.connect(hostID: host.id)
        terminal.pendingReport?(.dismissed)
        #expect(model.lastConnected(host.id) == nil)
        #expect(terminal.opened.count == 2)

        // The stamp survives a reload only once a connection was reported.
        model.connect(hostID: host.id)
        terminal.pendingReport?(.connected)
        let stamped = try #require(model.lastConnected(host.id))
        await model.load()
        #expect(model.lastConnected(host.id) == stamped)
    }

    @Test("consolidateRecords merges members into the canonical record in the catalog (Stage 6 operation)")
    func consolidateMergesInCatalog() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", aliases: ["10.0.0.5"], kinds: [.ssh], createdAt: t0)
        let newer = try record("juliet", aliases: ["juliet.local"], kinds: [.rdp], createdAt: t0.addingTimeInterval(1))
        try await sibling.upsert(older); try await sibling.upsert(newer)
        await model.load()
        try await model.consolidateRecords(of: older.id)
        let stored = try await sibling.snapshot()
        #expect(stored.count == 1)
        #expect(stored.first?.id == older.id)
        #expect(stored.first?.services.count == 2)
        #expect(Set(stored.first?.aliases ?? []) == ["10.0.0.5", "juliet.local"])
        #expect(model.catalogHosts.count == 1 && model.records.count == 1)
    }

    @Test("The play button opens every service on the host, in order, and remembers no single one")
    func connectAllOpensEveryService() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let older = try record("juliet", kinds: [.ssh], createdAt: t0)
        let newer = try record("juliet", kinds: [.rdp], createdAt: t0.addingTimeInterval(1))
        try await sibling.upsert(older); try await sibling.upsert(newer)
        let terminal = RecordingCapability(kind: .ssh)
        let desktop = RecordingCapability(kind: .rdp)
        model.registry.register(terminal); model.registry.register(desktop)
        await model.load()
        let host = try #require(model.catalogHosts.first)

        model.connectAll(hostID: host.id)

        let opened = terminal.opened.map(\.0.endpointID) + desktop.opened.map(\.0.endpointID)
        #expect(Set(opened) == Set(host.services.map(\.endpointID)), "every service was opened")
        #expect(terminal.opened.first?.1.id == older.id, "each capability gets the record owning its endpoint")
        #expect(desktop.opened.first?.1.id == older.id, "consolidated: the canonical record owns every endpoint")
        #expect(model.lastUsedService(for: host.id) == nil, "connecting the machine chooses no one service")

        terminal.pendingReport?(.connected)
        #expect(model.lastConnected(host.id) != nil, "a reported session still stamps the host")
    }

    @Test("Connecting every service reports the kinds this build cannot open and still opens the rest")
    func connectAllReportsUnavailableKinds() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try record("juliet", kinds: [.ssh, .database], createdAt: t0)
        try await sibling.upsert(host)
        let terminal = RecordingCapability(kind: .ssh)
        model.registry.register(terminal)      // no database capability in this build
        await model.load()
        let grouped = try #require(model.catalogHosts.first)

        model.connectAll(hostID: grouped.id)

        #expect(terminal.opened.count == 1, "the kind with a capability still opened")
        #expect(model.errorMessage?.contains("Database") == true, "and the one without says so")
    }
}

@MainActor
private final class ContributingCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { "Contributor" }
    var symbolName: String { "circle" }
    var detailActionRequests: [HostServiceKind] = []
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    var settingsPages: [GlassCapabilitySettingsPage] {
        [GlassCapabilitySettingsPage(id: "\(kind.rawValue)-page", title: "\(kind.rawValue.capitalized) Settings", systemImage: symbolName) { AnyView(Text("page")) }]
    }
    func serviceDetailActions(service: HostServiceLink, host: HostProfile) -> AnyView {
        detailActionRequests.append(service.kind)
        return AnyView(Text("action"))
    }
}

@Suite("GlassShell capability hooks")
@MainActor
struct GlassShellCapabilityHookTests {
    @Test("A registered capability's settings page joins the selection after the shell's pages")
    func settingsPageAppears() {
        let registry = GlassCapabilityRegistry()
        registry.register(ContributingCapability(kind: .rdp))
        registry.register(ContributingCapability(kind: .ssh))
        let options = GlassShellSettingsSelection.options(capabilityPages: registry.settingsPages)
        #expect(Array(options.prefix(4)) == GlassShellSettingsPage.allCases.map(GlassShellSettingsSelection.shell))
        #expect(Array(options.dropFirst(4)) == [.capability("rdp-page"), .capability("ssh-page")], "kind order, after the shell's")
        #expect(registry.settingsPages.map(\.title) == ["Rdp Settings", "Ssh Settings"])
    }

    @Test("Detail actions are requested from the owning capability only")
    func detailActionsRoutedByKind() throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ContributingCapability(kind: .ssh), rdp = ContributingCapability(kind: .rdp)
        registry.register(ssh); registry.register(rdp)
        let host = try HostProfile(displayName: "h")
        _ = registry.serviceDetailActions(service: HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "t"), host: host)
        _ = registry.serviceDetailActions(service: HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "d"), host: host)
        #expect(ssh.detailActionRequests == [.ssh])
        #expect(rdp.detailActionRequests.isEmpty)
    }
}

/// 2026-09-21: eleven records named oscar on the phone, two fully configured, grouped into one row
/// that listed the Mac's Terminal and the phone's Terminal. Consolidation runs itself now, and a
/// service the machine has twice is kept once.
@MainActor
@Suite("Two devices that set up one machine become one record")
struct GlassShellAutoConsolidationTests {
    private func link(_ kind: HostServiceKind, _ name: String, id: String) -> HostServiceLink {
        HostServiceLink(endpointID: EndpointID(rawValue: UUID(uuidString: id)!), kind: kind, displayName: name)
    }

    @Test("Loading merges same-address records and keeps a duplicated service once")
    func loadConsolidatesAndDeduplicates() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        // The Mac's oscar and the phone's oscar: each with its own Terminal and Desktop, the Mac's
        // with MySQL too. Endpoint ids chosen so the winner is not simply "the older record's".
        let mac = try HostProfile(displayName: "oscar", address: "192.0.2.10",
                                  services: [link(.ssh, "Terminal on oscar", id: "BBBBBBBB-0000-0000-0000-000000000001"),
                                             link(.database, "MySQL on oscar", id: "BBBBBBBB-0000-0000-0000-000000000002"),
                                             link(.rdp, "oscar", id: "AAAAAAAA-0000-0000-0000-000000000003")],
                                  createdAt: t0, updatedAt: t0)
        let phone = try HostProfile(displayName: "oscar", address: "192.0.2.10",
                                    services: [link(.ssh, "Terminal on oscar", id: "AAAAAAAA-0000-0000-0000-000000000001"),
                                               link(.rdp, "oscar", id: "BBBBBBBB-0000-0000-0000-000000000003")],
                                    createdAt: t0.addingTimeInterval(60), updatedAt: t0.addingTimeInterval(60))
        let empty = try HostProfile(displayName: "oscar", address: "192.0.2.10", services: [],
                                    createdAt: t0.addingTimeInterval(120), updatedAt: t0.addingTimeInterval(120))
        try await sibling.upsert(mac); try await sibling.upsert(phone); try await sibling.upsert(empty)

        await model.load()

        let stored = try await sibling.snapshot()
        #expect(stored.count == 1, "one record for one machine")
        let survivor = try #require(stored.first)
        #expect(survivor.id == mac.id, "the oldest record is canonical")
        #expect(survivor.services.count == 3, "Terminal, MySQL, Desktop — each once")
        #expect(Set(survivor.services.map(\.kind)) == [.ssh, .database, .rdp])
        // The smallest endpoint id wins regardless of which record it came from, so every device
        // decides the same way.
        #expect(survivor.services.first { $0.kind == .ssh }?.endpointID.rawValue.uuidString == "AAAAAAAA-0000-0000-0000-000000000001")
        #expect(survivor.services.first { $0.kind == .rdp }?.endpointID.rawValue.uuidString == "AAAAAAAA-0000-0000-0000-000000000003")
        #expect(model.catalogHosts.count == 1)
        #expect(model.catalogHosts.first?.isConsolidated == false)
    }

    @Test("A dropped duplicate is handed to its capability to clean up, like a removal would be")
    func droppedDuplicatesReachTheCapability() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        final class Removing: GlassCapability {
            let kind: HostServiceKind = .ssh
            let displayName = "Terminal"; let symbolName = "terminal"
            var removed: [EndpointID] = []
            func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
            func removeService(_ service: HostServiceLink, host: HostProfile) async throws { removed.append(service.endpointID) }
        }
        let terminal = Removing()
        model.registry.register(terminal)
        let a = try HostProfile(displayName: "oscar", address: "10.0.0.9",
                                services: [link(.ssh, "Terminal on oscar", id: "AAAAAAAA-0000-0000-0000-000000000001")],
                                createdAt: t0, updatedAt: t0)
        let b = try HostProfile(displayName: "oscar", address: "10.0.0.9",
                                services: [link(.ssh, "terminal on OSCAR", id: "BBBBBBBB-0000-0000-0000-000000000001")],
                                createdAt: t0.addingTimeInterval(1), updatedAt: t0.addingTimeInterval(1))
        try await sibling.upsert(a); try await sibling.upsert(b)

        await model.load()

        #expect(terminal.removed.map(\.rawValue.uuidString) == ["BBBBBBBB-0000-0000-0000-000000000001"],
                "the loser, matched case-insensitively by name, is removed through its capability")
        #expect(try await sibling.snapshot().first?.services.count == 1)
    }

    @Test("A library with nothing to merge is left exactly as it was")
    func cleanLibraryIsUntouched() async throws {
        let (model, root, sibling) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let one = try record("juliet", kinds: [.ssh, .rdp], createdAt: t0)
        let two = try record("oscar", kinds: [.database], createdAt: t0)
        try await sibling.upsert(one); try await sibling.upsert(two)
        let before = try await sibling.snapshot()

        await model.load()
        await model.consolidateDuplicateHosts()

        #expect(try await sibling.snapshot() == before, "nothing rewritten, so nothing republished")
    }

    @Test("Deduplication is pure and deterministic")
    func deduplicationIsDeterministic() {
        let links = [link(.ssh, "Terminal on oscar", id: "BBBBBBBB-0000-0000-0000-000000000001"),
                     link(.ssh, "Terminal on oscar", id: "AAAAAAAA-0000-0000-0000-000000000001"),
                     link(.ssh, "Other terminal", id: "CCCCCCCC-0000-0000-0000-000000000001"),
                     link(.rdp, "Terminal on oscar", id: "DDDDDDDD-0000-0000-0000-000000000001")]
        let (kept, dropped) = GlassShellModel.deduplicated(links)
        #expect(kept.map(\.endpointID.rawValue.uuidString) == ["AAAAAAAA-0000-0000-0000-000000000001",
                                                                 "CCCCCCCC-0000-0000-0000-000000000001",
                                                                 "DDDDDDDD-0000-0000-0000-000000000001"],
                "same kind and name collapse to the smallest id; a different name or kind is a different service")
        #expect(dropped.map(\.endpointID.rawValue.uuidString) == ["BBBBBBBB-0000-0000-0000-000000000001"])
        // The same winners whichever order the records arrived in — the property every device
        // relies on to reach the same catalog as the others.
        #expect(Set(GlassShellModel.deduplicated(links.reversed()).kept.map(\.endpointID)) == Set(kept.map(\.endpointID)))
    }
}
