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
            case .invalidAddress: return "The address must be a hostname or an IP address, with no user, port or spaces."
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

    /// The library's hosts: catalog records that describe the same machine, consolidated
    /// (see `GlassShellHostGrouping`). Never written back as one record before Stage 6.
    public private(set) var hosts: [GlassShellHost] = []
    /// The catalog as stored, one record per publishing app and endpoint. For diagnostics.
    public private(set) var records: [HostProfile] = []
    public private(set) var isLoaded = false
    public var errorMessage: String?
    public private(set) var hasSharedContainer: Bool
    public private(set) var hostLibraryStatus: String
    public private(set) var preferencesProblem: String?
    /// True while the preferences file exists but cannot be trusted or read; nothing is written
    /// over it until `resetPreferences()` or a later successful read.
    public private(set) var preferencesReadOnly = false

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
            #if DEBUG
            try await seedForUITestingIfRequested()
            #endif
            records = try await catalog.snapshot()
            hosts = GlassShellHostGrouping.group(records)
            migratePreferencesToCanonicalHosts()
            isLoaded = true
            errorMessage = nil
            await adoptKnownAddresses()
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
            let subtitle = Self.subtitle(for: kinds)
            return GlassLibraryItem(id: host.id, name: host.displayName, subtitle: subtitle,
                                    searchTerms: host.aliases + host.services.map(\.displayName),
                                    tags: host.tags, isFavorite: record.isFavorite,
                                    lastConnected: record.lastConnected, dateAdded: host.createdAt,
                                    sortKeys: [host.displayName, host.id.rawValue.uuidString])
        }
    }

    /// The consolidated host for a canonical id — or for any member record's id, so a selection
    /// or preference keyed on a record that later joined a group still resolves.
    /// The row's second line. Up to two kinds are named; three or more are counted, because the
    /// shared row middle-truncates a long subtitle ("Desk…abase") and the icons beside the row
    /// already say which kinds they are.
    static func subtitle(for kinds: [HostServiceKind]) -> String {
        switch kinds.count {
        case 0: "No services yet"
        case 1, 2: kinds.map(GlassServicePresentation.displayName(for:)).joined(separator: " · ")
        default: "\(kinds.count) services"
        }
    }

    public func host(_ id: HostID) -> GlassShellHost? {
        hosts.first { $0.id == id } ?? hosts.first { $0.contains(id) }
    }

    /// The stored record with this id, if any.
    public func record(_ id: HostID) -> HostProfile? { records.first { $0.id == id } }

    /// The canonical id for any host or member id.
    public func canonicalID(for id: HostID) -> HostID { host(id)?.id ?? id }

    public func services(for id: HostID) -> [HostServiceLink] { host(id)?.services ?? [] }

    public func serviceKinds(for id: HostID) -> [HostServiceKind] {
        let present = Set(services(for: id).map(\.kind))
        return HostServiceKind.allCases.filter(present.contains)
    }

    public func isFavorite(_ id: HostID) -> Bool { preferences[host: canonicalID(for: id)].isFavorite }
    public func lastConnected(_ id: HostID) -> Date? { preferences[host: canonicalID(for: id)].lastConnected }
    public func lastUsedService(for id: HostID) -> HostServiceLink? {
        guard let endpointID = preferences[host: canonicalID(for: id)].lastUsedEndpointID else { return nil }
        return services(for: id).first { $0.endpointID == endpointID }
    }

    /// Preferences written against a record that has since joined a group move to the group's
    /// canonical id: favorite if any member was, the latest connection time, and the last-used
    /// service of whichever member connected most recently. Idempotent; persisted only when the
    /// file is writable and something actually moved.
    private func migratePreferencesToCanonicalHosts() {
        var moved = false
        for host in hosts where host.isConsolidated {
            var canonical = preferences.hosts[host.id] ?? .init()
            for member in host.members.dropFirst() {
                guard let stray = preferences.hosts.removeValue(forKey: member.id) else { continue }
                moved = true
                canonical.isFavorite = canonical.isFavorite || stray.isFavorite
                if let strayDate = stray.lastConnected, strayDate > (canonical.lastConnected ?? .distantPast) {
                    canonical.lastConnected = strayDate
                    canonical.lastUsedEndpointID = stray.lastUsedEndpointID ?? canonical.lastUsedEndpointID
                } else if canonical.lastUsedEndpointID == nil {
                    canonical.lastUsedEndpointID = stray.lastUsedEndpointID
                }
            }
            if moved { preferences.hosts[host.id] = canonical }
        }
        guard moved, !preferencesReadOnly else { return }
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
    }

    // MARK: Mutations

    public func addHost(displayName: String, address: String? = nil, aliases: [String] = [], tags: [String] = []) async throws -> HostProfile {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let profile = try HostProfile(displayName: trimmed, address: Self.blankToNil(address), aliases: aliases, tags: tags,
                                      lastWriterID: preferences.writerID)
        try await catalog.upsert(profile)
        await load()
        return profile
    }

    /// Blank means "no address", never an empty string that the kit would reject.
    static func blankToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Renames every member record (so the group stays together) and applies aliases and tags to
    /// the canonical one. Each record is re-read right before writing so services another app
    /// paired since our last load survive. (Interim until the kit offers an in-lock field edit.)
    public func updateHost(_ id: HostID, displayName: String, address: String? = nil, aliases: [String], tags: [String]) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let newAddress = try Self.blankToNil(address).map(HostProfile.normalizedAddress)
        let snapshot = try await catalog.snapshot()
        var updatedMembers: [HostProfile] = []
        for member in host.members {
            let fresh = snapshot.first { $0.id == member.id } ?? member
            let isCanonical = member.id == host.id
            // The address is the machine's, so every member record carries the same one.
            let updated = try HostProfile(id: fresh.id, displayName: trimmed, address: newAddress,
                                          aliases: isCanonical ? aliases : fresh.aliases,
                                          services: fresh.services,
                                          tags: isCanonical ? tags : fresh.tags,
                                          createdAt: fresh.createdAt,
                                          updatedAt: max(Date(), fresh.updatedAt), lastWriterID: preferences.writerID)
            try await catalog.upsert(updated)
            updatedMembers.append(updated)
        }
        await load()
        if newAddress != host.address { notifyAddressChange(members: updatedMembers, address: newAddress) }
    }

    /// Sets only the address, leaving name, aliases and tags as they are. Used by the address
    /// prompt and by adoption from a capability's saved record, so the machine's identity is
    /// defined once, at the host.
    public func setHostAddress(_ address: String?, for id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        try await updateHost(host.id, displayName: host.displayName, address: address, aliases: host.aliases, tags: host.tags)
    }

    /// Every capability hears about each member record: a capability keys its services by the
    /// endpoint ids inside those records.
    private func notifyAddressChange(members: [HostProfile], address: String?) {
        for capability in registry.registered {
            for member in members where member.services.contains(where: { $0.kind == capability.kind }) {
                capability.hostAddressDidChange(host: member, address: address)
            }
        }
    }

    /// What a capability may read about a host while it sets a service up or connects.
    func hostAccess(for id: HostID) -> GlassCapabilityHostAccess {
        GlassCapabilityHostAccess(address: host(id)?.address)
    }

    /// An address one of the host's capabilities already stores for a service of the host — a
    /// record saved by the source app before hosts carried an address. Nil when none, or when
    /// the capabilities disagree (that is for the user to settle, not for the shell to guess).
    func knownAddress(for host: GlassShellHost) -> String? {
        var found = Set<String>()
        for member in host.members {
            for service in member.services {
                guard let capability = registry.capability(for: service.kind),
                      let address = capability.knownAddress(service: service, host: member)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { continue }
                found.insert(address.lowercased())
            }
        }
        return found.count == 1 ? found.first : nil
    }

    /// Hosts that predate the address gain it from the services already saved on their
    /// capabilities, once, so the detail never says "Not set" for a machine the terminal knows.
    /// Runs after each load; a host whose capabilities disagree is left for the user.
    private var isAdoptingAddresses = false
    private func adoptKnownAddresses() async {
        guard !isAdoptingAddresses else { return }
        isAdoptingAddresses = true
        defer { isAdoptingAddresses = false }
        let candidates = hosts.filter { $0.address == nil }.compactMap { host in
            knownAddress(for: host).map { (host.id, $0) }
        }
        for (id, address) in candidates {
            do { try await setHostAddress(address, for: id) } catch {
                // Not fatal: the host simply keeps "Not set" until the user enters it.
                continue
            }
        }
    }

    /// Deletes every record that makes up the host.
    public func deleteHost(_ id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        for member in host.members { try await catalog.delete(hostID: member.id) }
        for member in host.members { preferences.hosts[member.id] = nil }
        try persistPreferences()
        await load()
    }

    /// Links a service to the host's canonical record. `endpointID` is the key the owning
    /// capability stored the service's configuration under: the setup sheet commits the
    /// capability's draft first, then records the link, so a service never exists half-made.
    @discardableResult
    public func addService(kind: HostServiceKind, displayName: String, endpointID: EndpointID = EndpointID(),
                           to id: HostID) async throws -> HostServiceLink {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let link = HostServiceLink(endpointID: endpointID, kind: kind, displayName: trimmed)
        try await catalog.pair(link, with: canonicalID(for: id))
        await load()
        return link
    }

    /// Removes the service from whichever member record owns it, then lets the owning
    /// capability delete what it stored for it. The link goes first: a stray configuration is
    /// harmless, a link to nothing is not.
    public func removeService(_ endpointID: EndpointID, from id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        guard let owner = host.member(owning: endpointID),
              let service = owner.services.first(where: { $0.endpointID == endpointID }) else {
            throw GlassShellError.serviceNotFound(endpointID)
        }
        try await catalog.unpair(endpointID: endpointID, from: owner.id)
        if preferences[host: host.id].lastUsedEndpointID == endpointID {
            preferences[host: host.id].lastUsedEndpointID = nil
            try persistPreferences()
        }
        await load()
        try await registry.capability(for: service.kind)?.removeService(service, host: owner)
    }

    public func toggleFavorite(_ id: HostID) {
        preferences[host: canonicalID(for: id)].isFavorite.toggle()
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
    }

    /// Merges a consolidated host's member records into its canonical record **in the catalog**:
    /// every service moves to the canonical record, aliases and tags are unioned, and the emptied
    /// members are deleted. Written for Stage 6 and deliberately not reachable from the UI: the
    /// three source applications still read `hosts.json` by their own record ids, and moving their
    /// endpoints would strip those apps of their hosts until they are retired.
    public func consolidateRecords(of id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        guard host.isConsolidated else { return }
        for member in host.members.dropFirst() {
            for link in member.services { try await catalog.move(endpointID: link.endpointID, to: host.id) }
            // `move` tombstones a record once its last service leaves; delete only what is left.
            if member.services.isEmpty { try await catalog.delete(hostID: member.id) }
        }
        let fresh = (try await catalog.snapshot()).first { $0.id == host.id } ?? host.canonical
        let merged = try HostProfile(id: fresh.id, displayName: fresh.displayName, address: host.address, aliases: host.aliases,
                                     services: fresh.services, tags: host.tags, createdAt: fresh.createdAt,
                                     updatedAt: max(Date(), fresh.updatedAt), lastWriterID: preferences.writerID)
        try await catalog.upsert(merged)
        await load()
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
        guard host.services.contains(where: { $0.endpointID == endpointID }) else {
            errorMessage = GlassShellError.serviceNotFound(endpointID).localizedDescription; return
        }
        // The user chose this service, so remember it either way; but "last connected" is only
        // true when a capability reports a live session. A failed attempt and a cancelled prompt
        // connect nothing.
        preferences[host: host.id].lastUsedEndpointID = endpointID
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
        open(endpointID, on: host)
    }

    /// Every service on the host, in the order the host lists them. This is what the library
    /// row's play button does: the machine has three services, the user wants the machine.
    /// It records no "last used" service, because the user picked the host, not one service.
    /// A kind with no capability in this build reports itself and the rest still open.
    public func connectAll(hostID: HostID) {
        guard let host = host(hostID) else { errorMessage = GlassShellError.hostNotFound(hostID).localizedDescription; return }
        guard !host.services.isEmpty else { return }
        for service in host.services { open(service.endpointID, on: host) }
    }

    /// Hands one service to its capability. The capability receives the record that owns the
    /// endpoint — its endpoint id is what the capability's own store is keyed by.
    private func open(_ endpointID: EndpointID, on host: GlassShellHost) {
        guard let service = host.services.first(where: { $0.endpointID == endpointID }),
              let owner = host.member(owning: endpointID) else {
            errorMessage = GlassShellError.serviceNotFound(endpointID).localizedDescription; return
        }
        // A kind no capability in this build owns cannot be connected: say so and connect nothing.
        guard let capability = registry.capability(for: service.kind) else {
            errorMessage = Self.unavailableMessage(for: service.kind)
            return
        }
        let hostID = host.id
        capability.open(service: service, host: owner, hostAccess: hostAccess(for: hostID)) { [weak self] outcome in
            guard let self, case .connected = outcome else { return }
            self.preferences[host: hostID].lastConnected = Date()
            do { try self.persistPreferences() } catch { self.errorMessage = GlassShellError.message(for: error) }
        }
    }

    /// What the shell says about a kind this build has no capability for.
    public static func unavailableMessage(for kind: HostServiceKind) -> String {
        "\(GlassServicePresentation.displayName(for: kind)) is not part of this build yet. Nothing was connected."
    }

    #if DEBUG
    /// UI tests seed the isolated catalog through a launch argument, because the runner cannot
    /// reach the app's container on iOS or visionOS:
    /// `--ui-testing-seed-hosts "juliet:ssh|juliet:rdp|oscar:ssh+database"` creates one record
    /// per `|` entry, named before the colon, with one service per `+`-separated kind; a name may
    /// carry the host's address after `@` (`scratch@192.0.2.6:ssh`). Only honoured alongside
    /// `--ui-testing`, only into a catalog that is not under a real Group Container, and only when
    /// that catalog is empty.
    private func seedForUITestingIfRequested() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--ui-testing-seed-hosts"), arguments.indices.contains(index + 1),
              !catalogFileURL.path.contains("Group Containers"),
              try await catalog.snapshot().isEmpty else { return }
        for (offset, entry) in arguments[index + 1].split(separator: "|").enumerated() {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let nameAndAddress = parts.first.map(String.init), !nameAndAddress.isEmpty else { continue }
            let nameParts = nameAndAddress.split(separator: "@", maxSplits: 1).map(String.init)
            let name = nameParts[0]
            let address = nameParts.count > 1 ? nameParts[1] : nil
            guard !name.isEmpty else { continue }
            let kinds = parts.count > 1 ? parts[1].split(separator: "+").compactMap { HostServiceKind(rawValue: String($0)) } : []
            let services = kinds.map {
                HostServiceLink(endpointID: EndpointID(), kind: $0, displayName: "\(GlassServicePresentation.displayName(for: $0)) on \(name)")
            }
            let created = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            try await catalog.upsert(try HostProfile(displayName: name, address: address, aliases: [], services: services,
                                                     createdAt: created, updatedAt: created, lastWriterID: writerID))
        }
    }
    #endif

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
