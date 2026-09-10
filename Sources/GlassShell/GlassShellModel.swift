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
    case preferencesReadOnly

    public var errorDescription: String? {
        switch self {
        case .hostNotFound: "That host is no longer in the library."
        case .serviceNotFound: "That service is no longer on the host."
        case .invalidName: "Enter a name."
        case .preferencesReadOnly: "Favorites and recent services are read-only until the preferences file can be read or is reset in Settings."
        }
    }

    /// User-facing text for any error the shell surfaces. The kit's validation and catalog errors
    /// carry no `LocalizedError` text of their own, so they are mapped here; everything else
    /// keeps its own description.
    public static func message(for error: Error) -> String {
        switch error {
        case let error as GlassShellError:
            return error.localizedDescription
        case let error as HostProfileError:
            switch error {
            case .invalidName: return "The name is empty or longer than 1,024 bytes."
            case .invalidAlias: return "An alias is empty or longer than 1,024 bytes."
            case .invalidTag: return "A collection name is empty or longer than 1,024 bytes."
            case .tooManyEntries: return "Too many entries: a host allows up to 64 aliases, 64 collections and 128 services."
            case .duplicateService: return "That service is already on this host."
            case .invalidTimestamp: return "The host record has an invalid timestamp."
            case .unsupportedVersion(let v): return "The host record uses schema version \(v), which this build does not understand."
            }
        case let error as HostCatalogError:
            switch error {
            case .unsupportedVersion(let v): return "The host library uses schema version \(v), which this build does not understand. Update the app; nothing was changed."
            case .tooLarge: return "The host library is too large to load safely (more than 8 MB or 10,000 hosts). Nothing was changed."
            case .duplicateHost: return "A host with that identity already exists."
            case .endpointAlreadyPaired: return "That service is already attached to a host."
            case .endpointNotFound: return "That service is no longer on the host."
            case .hostNotFound: return "That host is no longer in the library."
            case .hostDeleted: return "That host was deleted; restore it before editing."
            case .fileLockFailed(let code): return "The host library is busy in another app (lock error \(code)). Try again in a moment."
            }
        default:
            return error.localizedDescription
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
    /// True while the preferences file exists but cannot be trusted or read; nothing is written
    /// over it until `resetPreferences()` or a later successful read.
    public private(set) var preferencesReadOnly = false
    public var placeholderRequest: GlassShellPlaceholderRequest?

    public let storageDirectory: URL
    public private(set) var catalog: HostCatalogStore
    /// Mirrored here so views and tests need not hop to the actor.
    public private(set) var catalogFileURL: URL
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
        self.preferencesProblem = loaded.outcome.problem
        self.preferencesReadOnly = !loaded.outcome.isWritable
        self.preferencesUnavailable = { if case .unavailable = loaded.outcome { true } else { false } }()

        let shared = sharedContainerURL ?? (resolveSharedContainer
            ? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.sharedContainerIdentifier) : nil)
        self.writerID = writerID
        if let shared {
            let fileURL = shared.appendingPathComponent(Self.catalogRelativePath)
            catalogFileURL = fileURL
            catalog = HostCatalogStore(fileURL: fileURL, writerID: writerID)
            hasSharedContainer = true
            hostLibraryStatus = "Host library is shared with glas.sh, glassdb and glassDT on this device."
        } else {
            let fileURL = directory.appendingPathComponent(Self.catalogRelativePath)
            catalogFileURL = fileURL
            catalog = HostCatalogStore(fileURL: fileURL, writerID: writerID)
            hasSharedContainer = false
            hostLibraryStatus = "The shared App Group is unavailable, so hosts are kept in this app only. Check the group.sh.glas.shared entitlement and signing."
        }
        secretConfiguration = SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup: accessGroup,
                                                       useDataProtectionKeychain: true, mobilityPolicy: .deviceOnly)
    }

    /// Set when the file was unreadable for availability reasons (protected before first
    /// unlock); `load()` retries it, and a successful read lifts read-only.
    private var preferencesUnavailable = false

    /// Retries an unavailable preferences file. Never overwrites; only adopts a successful read.
    public func reloadPreferencesIfUnavailable() {
        guard preferencesReadOnly, preferencesUnavailable else { return }
        let loaded = preferencesStore.load()
        guard loaded.outcome.isWritable else {
            preferencesProblem = loaded.outcome.problem
            preferencesUnavailable = { if case .unavailable = loaded.outcome { true } else { false } }()
            return
        }
        preferences = loaded.preferences
        preferencesProblem = nil
        preferencesReadOnly = false
        preferencesUnavailable = false
    }

    /// The user's explicit choice to start fresh: the unreadable file is moved aside, not deleted.
    public func resetPreferences() throws {
        try preferencesStore.setAside()
        preferences = GlassShellPreferences()
        preferencesProblem = nil
        preferencesReadOnly = false
        preferencesUnavailable = false
        try preferencesStore.save(preferences)
    }

    // MARK: Loading

    public func load() async {
        reloadPreferencesIfUnavailable()
        do {
            hosts = try await catalog.snapshot()
            isLoaded = true
            errorMessage = nil
        } catch {
            isLoaded = true
            if hasSharedContainer, Self.isPermissionDenied(error) {
                // The container resolves but the sandbox refuses it: the App Group entitlement is
                // not granted by this build's provisioning profile. Degrade to the private
                // catalog and say so where the user will see it, instead of alerting every launch.
                switchToLocalCatalog(reason: "This build is not allowed to use the shared host library "
                    + "(the App Group entitlement is not granted by its provisioning profile), so hosts are "
                    + "kept in this app only until it is signed with the group.")
                await load()
                return
            }
            errorMessage = "The host library could not be read: \(GlassShellError.message(for: error))"
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
        // Re-read right before writing so services another app paired since our last load
        // survive; only the fields the editor changed are applied. (Interim until the kit
        // offers a field-level in-lock edit.)
        let fresh = (try await catalog.snapshot()).first { $0.id == id } ?? existing
        let updated = try HostProfile(id: fresh.id, displayName: trimmed, aliases: aliases,
                                      services: fresh.services, tags: tags, createdAt: fresh.createdAt,
                                      updatedAt: max(Date(), fresh.updatedAt), lastWriterID: preferences.writerID)
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
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
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
        // The user chose this service, so remember it either way; but "last connected" is only
        // true when a capability actually opens it. The placeholder connects nothing.
        preferences[host: hostID].lastUsedEndpointID = endpointID
        if let capability = registry.capability(for: service.kind) {
            preferences[host: hostID].lastConnected = Date()
            do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
            capability.open(service: service, host: host)
        } else {
            do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
            placeholderRequest = GlassShellPlaceholderRequest(host: host, service: service)
        }
    }

    private func switchToLocalCatalog(reason: String) {
        catalogFileURL = storageDirectory.appendingPathComponent(Self.catalogRelativePath)
        catalog = HostCatalogStore(fileURL: catalogFileURL, writerID: writerID)
        hasSharedContainer = false
        hostLibraryStatus = reason
        errorMessage = nil
    }

    /// EACCES/EPERM from the kit's lock, or Cocoa's no-permission codes from directory creation.
    static func isPermissionDenied(_ error: Error) -> Bool {
        if case HostCatalogError.fileLockFailed(let code) = error { return code == EACCES || code == EPERM }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code)
                || (ns.underlyingErrors.first.map(isPermissionDenied) ?? false)
        }
        return ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM))
    }

    private func persistPreferences() throws {
        guard !preferencesReadOnly else { throw GlassShellError.preferencesReadOnly }
        try preferencesStore.save(preferences)
    }
}
