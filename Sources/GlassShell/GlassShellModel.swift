import GlassLayers
import Foundation
import Observation
import GlassConnectionKit
import GlassHostCatalog
import GlasSecretStore

public enum GlassShellError: LocalizedError, Equatable {
    case hostNotFound(HostID)
    case serviceNotFound(EndpointID)
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .hostNotFound: "That host is no longer in the library."
        case .serviceNotFound: "That service is no longer on the host."
        case .invalidName: "Enter a name."
        }
    }
}

/// The shell's one model: the shared host catalog, shell preferences, the
/// credential boundary configuration and routing into capabilities.
/// Adapted from glassDT's `DesktopAppModel`, minus everything that existed only
/// to keep three processes agreeing (dual catalogs, publication, deletion outbox,
/// pairing). One catalog, one writer, one store.
@MainActor @Observable
public final class GlassShellModel {
    public static let sharedContainerIdentifier = "group.sh.glas.shared"
    public static let catalogRelativePath = "GlassHostCatalog/hosts.json"

    public private(set) var hosts: [HostProfile] = []
    public private(set) var isLoaded = false
    public var errorMessage: String?
    public private(set) var hasSharedContainer: Bool
    public private(set) var hostLibraryStatus: String
    public private(set) var preferencesProblem: String?
    public var placeholderRequest: GlassShellPlaceholderRequest?

    public let storageDirectory: URL
    public let catalog: HostCatalogStore
    /// Fixed at init; mirrored here so views and tests need not hop to the actor.
    public let catalogFileURL: URL
    public let writerID: WriterID
    public let layers: GlassLayerStore
    public let registry: GlassCapabilityRegistry
    public let secretConfiguration: SecretStoreConfiguration

    private let preferencesStore: GlassShellPreferencesStore
    private var preferences: GlassShellPreferences

    /// - Parameters:
    ///   - storageDirectory: per-app state (preferences, fallback catalog). Defaults to
    ///     Application Support/GlassPowerTools.
    ///   - sharedContainerURL: the App Group container. `nil` resolves the real one;
    ///     tests pass a temporary directory and never touch the real group.
    ///   - accessGroup: Keychain access group for `SecretStoreConfiguration`.
    public init(storageDirectory: URL? = nil, sharedContainerURL: URL? = nil,
                resolveSharedContainer: Bool = true, accessGroup: String? = nil,
                layers: GlassLayerStore, registry: GlassCapabilityRegistry = GlassCapabilityRegistry()) {
        let directory = storageDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("GlassPowerTools", isDirectory: true)
        self.storageDirectory = directory
        self.layers = layers
        self.registry = registry
        self.preferencesStore = GlassShellPreferencesStore(fileURL: directory.appendingPathComponent("shell-preferences.json"))
        let loaded = GlassShellPreferencesStore(fileURL: directory.appendingPathComponent("shell-preferences.json")).load()
        let writerID = loaded.preferences.writerID
        self.preferences = loaded.preferences
        self.preferencesProblem = loaded.problem

        let shared = sharedContainerURL ?? (resolveSharedContainer
            ? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.sharedContainerIdentifier) : nil)
        self.writerID = writerID
        if let shared {
            catalogFileURL = shared.appendingPathComponent(Self.catalogRelativePath)
            catalog = HostCatalogStore(fileURL: catalogFileURL, writerID: writerID)
            hasSharedContainer = true
            hostLibraryStatus = "Host library is shared with glas.sh, glassdb and glassDT on this device."
        } else {
            catalogFileURL = directory.appendingPathComponent(Self.catalogRelativePath)
            catalog = HostCatalogStore(fileURL: catalogFileURL, writerID: writerID)
            hasSharedContainer = false
            hostLibraryStatus = "The shared App Group is unavailable, so hosts are kept in this app only. Check the group.sh.glas.shared entitlement and signing."
        }
        secretConfiguration = SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup: accessGroup,
                                                       useDataProtectionKeychain: true, mobilityPolicy: .deviceOnly)
        if loaded.problem != nil { try? preferencesStore.save(loaded.preferences) }
    }

    // MARK: Loading

    public func load() async {
        do {
            hosts = try await catalog.snapshot()
            isLoaded = true
            errorMessage = nil
        } catch {
            isLoaded = true
            errorMessage = "The host library could not be read: \(error.localizedDescription)"
        }
    }

    // MARK: Projection

    public var items: [GlassLibraryItem<HostID>] {
        hosts.map { host in
            let record = preferences[host: host.id]
            let kinds = HostServiceKind.allCases.filter { kind in host.services.contains { $0.kind == kind } }
            let subtitle = kinds.isEmpty ? "No services yet"
                : kinds.map(GlassServicePresentation.displayName(for:)).joined(separator: " · ")
            return GlassLibraryItem(id: host.id, name: host.displayName, subtitle: subtitle,
                                    searchTerms: host.aliases + host.services.map(\.displayName),
                                    tags: host.tags, isFavorite: record.isFavorite,
                                    lastConnected: record.lastConnected, dateAdded: host.createdAt,
                                    sortKeys: [host.displayName, host.id.rawValue.uuidString])
        }
    }

    public func host(_ id: HostID) -> HostProfile? { hosts.first { $0.id == id } }

    public func services(for id: HostID) -> [HostServiceLink] { host(id)?.services ?? [] }

    public func serviceKinds(for id: HostID) -> [HostServiceKind] {
        let present = Set(services(for: id).map(\.kind))
        return HostServiceKind.allCases.filter(present.contains)
    }

    public func isFavorite(_ id: HostID) -> Bool { preferences[host: id].isFavorite }
    public func lastConnected(_ id: HostID) -> Date? { preferences[host: id].lastConnected }
    public func lastUsedService(for id: HostID) -> HostServiceLink? {
        guard let endpointID = preferences[host: id].lastUsedEndpointID else { return nil }
        return services(for: id).first { $0.endpointID == endpointID }
    }

    // MARK: Mutations

    public func addHost(displayName: String, aliases: [String] = [], tags: [String] = []) async throws -> HostProfile {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let profile = try HostProfile(displayName: trimmed, aliases: aliases, tags: tags, lastWriterID: preferences.writerID)
        try await catalog.upsert(profile)
        await load()
        return profile
    }

    public func updateHost(_ id: HostID, displayName: String, aliases: [String], tags: [String]) async throws {
        guard let existing = host(id) else { throw GlassShellError.hostNotFound(id) }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let updated = try HostProfile(id: existing.id, displayName: trimmed, aliases: aliases,
                                      services: existing.services, tags: tags, createdAt: existing.createdAt,
                                      updatedAt: max(Date(), existing.updatedAt), lastWriterID: preferences.writerID)
        try await catalog.upsert(updated)
        await load()
    }

    public func deleteHost(_ id: HostID) async throws {
        try await catalog.delete(hostID: id)
        preferences.hosts[id] = nil
        try persistPreferences()
        await load()
    }

    /// Creates a metadata-only service on the host. The capability that owns the
    /// endpoint record fills it in later; nothing here can connect.
    @discardableResult
    public func addService(kind: HostServiceKind, displayName: String, to id: HostID) async throws -> HostServiceLink {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let link = HostServiceLink(endpointID: EndpointID(), kind: kind, displayName: trimmed)
        try await catalog.pair(link, with: id)
        await load()
        return link
    }

    public func removeService(_ endpointID: EndpointID, from id: HostID) async throws {
        try await catalog.unpair(endpointID: endpointID, from: id)
        if preferences[host: id].lastUsedEndpointID == endpointID {
            preferences[host: id].lastUsedEndpointID = nil
            try persistPreferences()
        }
        await load()
    }

    public func toggleFavorite(_ id: HostID) {
        preferences[host: id].isFavorite.toggle()
        do { try persistPreferences() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Connecting

    /// Connect picks the sole service, else the last-used one if still present,
    /// else the first. Returns the chosen service, or nil if the host has none.
    @discardableResult
    public func connect(hostID: HostID) -> HostServiceLink? {
        let available = services(for: hostID)
        guard let chosen = available.count == 1 ? available.first
            : (lastUsedService(for: hostID) ?? available.first) else { return nil }
        connect(hostID: hostID, endpointID: chosen.endpointID)
        return chosen
    }

    public func connect(hostID: HostID, endpointID: EndpointID) {
        guard let host = host(hostID) else { errorMessage = GlassShellError.hostNotFound(hostID).localizedDescription; return }
        guard let service = host.services.first(where: { $0.endpointID == endpointID }) else {
            errorMessage = GlassShellError.serviceNotFound(endpointID).localizedDescription; return
        }
        preferences[host: hostID].lastUsedEndpointID = endpointID
        preferences[host: hostID].lastConnected = Date()
        do { try persistPreferences() } catch { errorMessage = error.localizedDescription }
        if let capability = registry.capability(for: service.kind) {
            capability.open(service: service, host: host)
        } else {
            placeholderRequest = GlassShellPlaceholderRequest(host: host, service: service)
        }
    }

    private func persistPreferences() throws { try preferencesStore.save(preferences) }
}
