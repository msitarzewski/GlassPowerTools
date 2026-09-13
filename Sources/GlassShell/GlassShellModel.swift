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
    /// The device's own host cannot be deleted (D8): it is not a record the user created, and
    /// removing it would take its saved databases with it.
    case localHostNotRemovable
    /// A built-in local service has nothing stored behind it, so there is nothing to edit or
    /// remove. See `GlassCapability.builtInLocalServices()`.
    case builtInServiceNotEditable(String)
    /// The local host has no address and never asks for one (D8).
    case localHostHasNoAddress

    public var errorDescription: String? {
        switch self {
        case .hostNotFound: "That host is no longer in the library."
        case .serviceNotFound: "That service is no longer on the host."
        case .invalidName: "Enter a name."
        case .preferencesReadOnly: "Favorites and recent services are read-only until the preferences file can be read or is reset in Settings."
        case .localHostNotRemovable: "\(GlassLocalHost.displayName) is this device and is always in the library. Remove its services instead."
        case .builtInServiceNotEditable(let name): "\(name) is built in to this device. There is nothing to configure and nothing to remove."
        case .localHostHasNoAddress: "\(GlassLocalHost.displayName) is this device, so it has no address to set."
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

    /// Why the device's own host is missing from the library, when it is. Nil in the normal case.
    /// Surfaced in Settings rather than as an alert: the rest of the library still works, and
    /// `load()` runs on every activation, so an alert would nag on every switch back to the app.
    public private(set) var localHostProblem: String?

    public let storageDirectory: URL
    public private(set) var catalog: HostCatalogStore
    /// The device's own host (D8), kept in this app's private storage and **never** in the App
    /// Group file the three source applications also read: a record they cannot open has no
    /// business appearing in their libraries, and the device's host is local to the device.
    public let localCatalog: HostCatalogStore
    /// Mirrored like `catalogFileURL`, so views and tests need not hop to the actor.
    public let localCatalogFileURL: URL
    /// The stored local record, once `load()` has read or created it.
    public private(set) var localRecord: HostProfile?
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
        // Always the app's own directory, never `shared`: that is the whole point (D8).
        localCatalogFileURL = directory.appendingPathComponent(GlassLocalHost.storeRelativePath)
        localCatalog = HostCatalogStore(fileURL: localCatalogFileURL, writerID: writerID)
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
        // D18/D21: on by default, so a host defined on one device is usable from the next.
        secretConfiguration = SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup: accessGroup,
                                                       useDataProtectionKeychain: true,
                                                       mobilityPolicy: .iCloudKeychain)
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
            await loadLocalHost()
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

    // MARK: The device's own host (D8)

    /// Reads the device's host from its own store, creating it the first time, and puts it at the
    /// head of the library: the machine you are holding comes before the ones you reach. It never
    /// goes through `GlassShellHostGrouping`, so it can never merge with a discovered machine that
    /// happens to share its name.
    private func loadLocalHost() async {
        do {
            let stored = try await localCatalog.snapshot()
            let record: HostProfile
            if let existing = stored.first(where: { $0.id == GlassLocalHost.id }) {
                record = existing
            } else {
                record = try HostProfile(id: GlassLocalHost.id, displayName: GlassLocalHost.displayName,
                                         lastWriterID: writerID)
                try await localCatalog.upsert(record)
            }
            #if DEBUG
            try await seedLocalServicesForUITestingIfRequested(on: record)
            #endif
            let current = (try await localCatalog.snapshot()).first { $0.id == GlassLocalHost.id } ?? record
            localRecord = current
            localHostProblem = nil
            hosts.insert(GlassShellHost(local: current, builtInServices: registry.builtInLocalServices), at: 0)
        } catch {
            // The library is still usable without it, so this is reported rather than thrown:
            // silence would be the honest-status failure, an alert on every activation would be
            // noise. Settings says what happened.
            localRecord = nil
            localHostProblem = "\(GlassLocalHost.displayName) is not in the library: its record could not be read or created (\(GlassShellError.message(for: error)))."
        }
    }

    /// True for the device's own host, for any of its ids.
    public func isLocalHost(_ id: HostID) -> Bool { id == GlassLocalHost.id }

    /// The local host, when it loaded.
    public var localHost: GlassShellHost? { hosts.first { $0.isLocal } }

    /// The library minus this device: the machines that came from the shared catalog. What
    /// diagnostics about that file should count, and what a test about it should assert on.
    public var catalogHosts: [GlassShellHost] { hosts.filter { !$0.isLocal } }

    /// `items` without this device. Internal: the library itself always shows every row, and
    /// this exists so a test about the shared catalog can say which rows it means.
    var catalogItems: [GlassLibraryItem<HostID>] { items.filter { $0.id != GlassLocalHost.id } }

    /// Writes the device's own record and reloads. Separate from `updateHost` because the local
    /// record lives in its own store and carries no address.
    private func updateLocalRecord(_ body: (inout HostProfile) -> Void) async throws {
        let stored = try await localCatalog.snapshot()
        guard let current = stored.first(where: { $0.id == GlassLocalHost.id }) else {
            throw GlassShellError.hostNotFound(GlassLocalHost.id)
        }
        var updated = current
        body(&updated)
        try updated.validate()
        try await localCatalog.upsert(updated)
        await load()
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

    /// The stored record with this id, if any — the device's own included, though it is not in
    /// `records`, which is the shared catalog as stored.
    public func record(_ id: HostID) -> HostProfile? {
        if id == GlassLocalHost.id { return localRecord }
        return records.first { $0.id == id }
    }

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
        if host.isLocal {
            // Rename, aliases and collections are the user's; an address is not a thing this host
            // has, and an attempt to set one is refused rather than quietly dropped.
            guard Self.blankToNil(address) == nil else { throw GlassShellError.localHostHasNoAddress }
            try await updateLocalRecord { record in
                record.displayName = trimmed
                record.aliases = aliases
                record.tags = tags
            }
            return
        }
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

    /// What a capability may read about a host while it sets a service up or connects, plus the
    /// brokered forward: when the machine has an SSH service, any capability may borrow it to
    /// reach a service that only listens on the machine itself (D7), without importing the
    /// capability that owns it.
    /// Public because the composition root hands it to capabilities that need it outside a
    /// connect — the database's setup sheet settles host-key trust through it (D14).
    /// The tidier-looking alternative, passing access through `setupDraft(for:host:)`, was
    /// considered and rejected: `makeSetupDraft()` has no host, so it would cover only half the
    /// cases — exactly the one-and-done sheet that creates a host and its services in one save.
    public func hostAccess(for id: HostID) -> GlassCapabilityHostAccess {
        guard let host = host(id) else { return GlassCapabilityHostAccess(address: nil) }
        return GlassCapabilityHostAccess(address: host.address,
                                         openForward: portForwardProvider(for: host),
                                         resolveTrust: hostTrustResolver(for: host))
    }

    /// The forward provider for a host, or nil when there is nothing to borrow: the machine has
    /// no SSH service, no registered capability owns that kind, or the machine is this device.
    /// Resolved once per access so a caller's `canForwardPorts` answers the same question the
    /// call will.
    ///
    /// **The local host is excluded explicitly (D8), and it has to be**: it carries a Terminal
    /// service — the Mac's own shell — so the plain "does this host have an `.ssh` service?" test
    /// says yes, and the database capability would then tunnel to loopback through loopback to
    /// reach a server already listening on it.
    /// The member whose SSH service a borrowed forward runs through.
    ///
    /// **A host is a group, not a machine.** `GlassShellHostGrouping.group` joins records whose
    /// normalised display names match, which is one of three ways in and does not require the
    /// addresses to agree — `GlassShellHost` says so itself, keeping `addresses` plural and taking
    /// `address` as the first. Two records both called "db" on different machines are one row.
    ///
    /// Taking simply "the first member with an `.ssh` service" therefore picks a machine by
    /// creation order. A database on the newer record would be tunnelled through the SSH service on
    /// the older one, and `DatabaseSessionManager` then opens the forward to `127.0.0.1:port` **as
    /// that other machine sees it** and sends the username and password down it. With TLS off — the
    /// ordinary setting for a tunnelled database — nothing notices.
    ///
    /// So the SSH service must belong to the machine the host *is*: the address shown in the UI and
    /// the one the user believes they are reaching. When no SSH member carries that address the
    /// group is genuinely ambiguous, and this returns nil rather than guessing — tunnelling to the
    /// wrong machine is worse than not tunnelling, and the caller already reports the absence.
    ///
    /// One selection serves both the forward and the trust resolver on purpose, so a fingerprint
    /// the user approves belongs to the machine the bytes go to.
    /// Internal rather than private so the selection can be tested directly. Reaching it through
    /// `hostAccess` proves nothing without a registered `.ssh` capability, and the rule being
    /// tested — which machine is chosen — is independent of whether one is registered.
    func sshMember(of host: GlassShellHost) -> HostProfile? {
        let candidates = host.members.filter { $0.services.contains { $0.kind == .ssh } }
        guard let address = host.address, !address.isEmpty else {
            // No address to agree with: only one candidate is unambiguous.
            return candidates.count == 1 ? candidates.first : nil
        }
        let matching = candidates.filter { $0.address == address }
        // More than one member at the same address is the same machine recorded twice, which is
        // what grouping exists for; any of them reaches it.
        return matching.first
    }

    private func portForwardProvider(for host: GlassShellHost)
    -> (@MainActor @Sendable (String, Int) async throws -> any GlassHostPortForward)? {
        guard !host.isLocal else { return nil }
        guard let capability = registry.capability(for: .ssh),
              let member = sshMember(of: host)
        else { return nil }
        return { remoteHost, port in
            try await capability.openPortForward(host: member, toHost: remoteHost, port: port)
        }
    }

    /// The host-key trust resolver for a host (D14), resolved against the same SSH service the
    /// forward would use so that settling trust settles it for the forward. Nil on exactly the
    /// same conditions, so `resolveHostTrust` cannot promise more than `forwardPort` can deliver.
    private func hostTrustResolver(for host: GlassShellHost)
    -> (@MainActor @Sendable () async -> GlassHostTrustOutcome)? {
        guard !host.isLocal else { return nil }
        guard let capability = registry.capability(for: .ssh),
              let member = sshMember(of: host)
        else { return nil }
        return { await capability.resolveHostTrust(host: member) }
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
        // The local host is skipped: it has no address by design, and a SQLite file path or a
        // loopback literal saved on one of its services is not a machine to adopt.
        let candidates = hosts.filter { $0.address == nil && !$0.isLocal }.compactMap { host in
            knownAddress(for: host).map { (host.id, $0) }
        }
        for (id, address) in candidates {
            do { try await setHostAddress(address, for: id) } catch {
                // Not fatal: the host simply keeps "Not set" until the user enters it.
                continue
            }
        }
    }

    /// Deletes every record that makes up the host. The device's own host is not one the user
    /// created and is not one they can remove (D8) — its services are removed individually.
    public func deleteHost(_ id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        guard !host.isLocal else { throw GlassShellError.localHostNotRemovable }
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
        if isLocalHost(canonicalID(for: id)) {
            try await localCatalog.pair(link, with: GlassLocalHost.id)
        } else {
            try await catalog.pair(link, with: canonicalID(for: id))
        }
        await load()
        return link
    }

    /// Removes the service from whichever member record owns it, then lets the owning
    /// capability delete what it stored for it. The link goes first: a stray configuration is
    /// harmless, a link to nothing is not.
    public func removeService(_ endpointID: EndpointID, from id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        if host.isBuiltIn(endpointID) {
            let name = host.services.first { $0.endpointID == endpointID }?.displayName ?? "That service"
            throw GlassShellError.builtInServiceNotEditable(name)
        }
        guard let owner = host.member(owning: endpointID),
              let service = owner.services.first(where: { $0.endpointID == endpointID }) else {
            throw GlassShellError.serviceNotFound(endpointID)
        }
        if host.isLocal {
            try await localCatalog.unpair(endpointID: endpointID, from: owner.id)
        } else {
            try await catalog.unpair(endpointID: endpointID, from: owner.id)
        }
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
    ///
    /// **Not offered on the local host (D8).** "Connect the machine" is an act of reaching a box;
    /// this device is already here, and its services are unrelated local things — a shell, a
    /// SQLite file, a MySQL instance, a VM. Opening all of them at once is never what anyone
    /// means, and it is the one host where a mis-click costs a window per service on the display
    /// you are looking at. Its row shows the service picker alone (`GlassShellConnectControl`),
    /// so this is the model-level guarantee behind that, not a second opinion about it.
    public func connectAll(hostID: HostID) {
        guard let host = host(hostID) else { errorMessage = GlassShellError.hostNotFound(hostID).localizedDescription; return }
        guard host.allowsConnectAll else { return }
        guard !host.services.isEmpty else { return }
        for service in host.services { open(service.endpointID, on: host) }
    }

    /// Hands one service to its capability. The capability receives the record that owns the
    /// endpoint — its endpoint id is what the capability's own store is keyed by.
    private func open(_ endpointID: EndpointID, on host: GlassShellHost) {
        guard let service = host.services.first(where: { $0.endpointID == endpointID }),
              let owner = host.record(owning: endpointID) else {
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
    private var didSeedHostsForUITesting = false
    private var didSeedLocalServicesForUITesting = false

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
              !catalogFileURL.path.contains("Group Containers"), !didSeedHostsForUITesting else { return }
        // Claimed before the first await. `load()` has two callers — the library's `.task` and
        // its scene-phase observer — which can interleave, and an emptiness check made *after*
        // an await is passed by both of them, seeding the same hosts twice.
        didSeedHostsForUITesting = true
        guard try await catalog.snapshot().isEmpty else { return }
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

    #if DEBUG
    /// The device's own host cannot be seeded through `--ui-testing-seed-hosts`, which writes the
    /// shared catalog, so it has its own argument with the same shape and the same guards:
    /// `--ui-testing-seed-local-services "database:notes.sqlite|database:gpt_test"` pairs one link
    /// per `|` entry, kind before the colon. Only alongside `--ui-testing`, only into a store
    /// outside a real Group Container, and only when the host has no services yet.
    private func seedLocalServicesForUITestingIfRequested(on record: HostProfile) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--ui-testing-seed-local-services"),
              arguments.indices.contains(index + 1),
              !localCatalogFileURL.path.contains("Group Containers"),
              !didSeedLocalServicesForUITesting, record.services.isEmpty else { return }
        // One shot, claimed before the first await: see `seedForUITestingIfRequested`.
        didSeedLocalServicesForUITesting = true
        for entry in arguments[index + 1].split(separator: "|") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let kind = parts.first.flatMap({ HostServiceKind(rawValue: String($0)) }) else { continue }
            let name = parts.count > 1 ? String(parts[1]) : GlassServicePresentation.displayName(for: kind)
            guard !name.isEmpty else { continue }
            try await localCatalog.pair(HostServiceLink(endpointID: EndpointID(), kind: kind, displayName: name),
                                        with: GlassLocalHost.id)
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
