//
//  ServerManager.swift
//  glas.sh
//
//  Manages server configurations persistence and lifecycle
//

import SwiftUI
import Foundation
import Observation
import WidgetKit
import os
import GlasSecretStore
import GlassConnectionKit
import GlassShell

struct HostTrustMigrationReport: Codable, Equatable {
    enum State: String, Codable {
        case verified
        case completed
        case failed
    }

    let fromVersion: Int
    let toVersion: Int
    let state: State
    let globalSourceCount: Int
    let serverSourceCount: Int
    let uniqueCandidateCount: Int
    let duplicateCount: Int
    let migratedCount: Int
    let alreadyPresentCount: Int
    let verifiedCount: Int
    let failedCount: Int
    let failureCode: String?
    let recordedAt: Date
}

@MainActor
struct HostTrustMigrationStore {
    let save: @MainActor (PinnedSSHHostKey) throws -> Void
    let allRecords: @MainActor () throws -> [PinnedSSHHostKey]

    static let live = HostTrustMigrationStore(
        save: KeychainManager.savePinnedHostKey,
        allRecords: KeychainManager.allPinnedHostKeys
    )
}

/// Where the terminal's saved servers actually live.
///
/// Shaped after the database's `ConnectionPersistenceStore` (`ConnectionManager.swift:31-54`),
/// which had this seam before the terminal did: load, save, and a restore for rollback. The
/// terminal's *writes* were already injectable (`serverDataWriter`) but its *reads* went straight
/// to `UserDefaults`, so the store could never actually be swapped — which is what D26 needs.
///
/// `save` is async because the catalog behind it is an actor (`HostCatalogStore`). Everything the
/// caller relies on is unchanged by that: the readback check still happens before `save` returns,
/// so a failed write is still a thrown error and still reaches the rollback that follows it.
@MainActor
struct ServerPersistenceStore {
    /// The stored catalog's bytes, or nil when nothing has ever been written.
    let load: () -> Data?
    /// Whether *anything* is stored, whatever its type. `UserDefaults` returns nil from
    /// `data(forKey:)` for a value of the wrong persisted type, and that is corruption rather than
    /// an empty catalog — a distinction `loadServers` has always drawn and must keep drawing.
    let hasStoredValue: () -> Bool
    let save: (Data) async throws -> Void
    /// Puts back exactly what was there, including "nothing". Used by the one rollback that
    /// restores the catalog without going through an encode.
    let restore: (Data?) async throws -> Void

    /// D26: the catalog is the one store for a connection.
    ///
    /// Each saved server lives on its own service link. The reconcile itself is
    /// `GlassServiceRecords`, shared with the database and the desktop, because "make the stored
    /// set match this list" is the same problem for all three.
    ///
    /// **Order is by name, then id, and that is deliberate.** The catalog keys configurations by
    /// endpoint id and has no insertion order to give back, so sorting here makes `load` stable
    /// across launches instead of returning whatever order the dictionary iterated in. Nothing
    /// user-visible depended on the old insertion order — every library surface sorts for itself.
    @MainActor
    static func catalog(_ store: any GlassServiceStore) -> ServerPersistenceStore {
        let records = GlassServiceRecords<ServerConfiguration>(
            store: store, kind: .ssh, id: { EndpointID(rawValue: $0.id) })
        func decode(_ data: Data?) -> [ServerConfiguration] {
            data.flatMap { try? JSONDecoder().decode([ServerConfiguration].self, from: $0) } ?? []
        }
        return ServerPersistenceStore(
            load: {
                try? JSONEncoder().encode(records.all().values
                    .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) })
            },
            hasStoredValue: { !records.isStoreEmpty },
            save: { try await records.replaceAll(with: decode($0)) },
            restore: { try await records.replaceAll(with: decode($0)) }
        )
    }

    static func live(defaults: UserDefaults) -> ServerPersistenceStore {
        ServerPersistenceStore(
            load: { defaults.data(forKey: UserDefaultsKeys.servers) },
            hasStoredValue: { defaults.object(forKey: UserDefaultsKeys.servers) != nil },
            save: { data in defaults.set(data, forKey: UserDefaultsKeys.servers) },
            restore: { data in
                if let data {
                    defaults.set(data, forKey: UserDefaultsKeys.servers)
                } else {
                    defaults.removeObject(forKey: UserDefaultsKeys.servers)
                }
            }
        )
    }
}

@MainActor
struct ServerPasswordStore {
    let retrieve: (ServerConfiguration) throws -> String
    let save: (String, ServerConfiguration) throws -> Void
    let delete: (UUID) throws -> Void
    let deleteSharedCompatibility: (ServerConfiguration) throws -> Void
    let prepareRollback: (ServerConfiguration) throws -> ServerCredentialRollback

    init(
        retrieve: @escaping (ServerConfiguration) throws -> String,
        save: @escaping (String, ServerConfiguration) throws -> Void,
        delete: @escaping (UUID) throws -> Void,
        deletePublished: ((ServerConfiguration) throws -> Void)? = nil,
        deleteSharedCompatibility: ((ServerConfiguration) throws -> Void)? = nil,
        prepareRollback: ((ServerConfiguration) throws -> ServerCredentialRollback)? = nil
    ) {
        self.retrieve = retrieve
        self.save = save
        self.delete = delete
        let resolvedDeletePublished = deletePublished ?? { server in
            try delete(server.id)
        }
        self.deleteSharedCompatibility = deleteSharedCompatibility ?? resolvedDeletePublished
        self.prepareRollback = prepareRollback ?? { server in
            let snapshot: String?
            do {
                snapshot = try retrieve(server)
            } catch SecretStoreError.notFound {
                snapshot = nil
            }
            return ServerCredentialRollback {
                if let snapshot {
                    try save(snapshot, server)
                    guard try retrieve(server) == snapshot else {
                        throw ServerManagerError.credentialReadbackMismatch
                    }
                } else {
                    do {
                        try resolvedDeletePublished(server)
                    } catch SecretStoreError.notFound {
                        // Absence is the captured state; verify it below.
                    }
                    do {
                        _ = try retrieve(server)
                        throw ServerManagerError.credentialReadbackMismatch
                    } catch SecretStoreError.notFound {
                        return
                    }
                }
            }
        }
    }

    static let live = ServerPasswordStore(
        retrieve: { server in
            try KeychainManager.retrievePassword(for: server)
        },
        save: { password, server in
            try KeychainManager.savePassword(password, for: server)
        },
        delete: { serverID in
            try KeychainManager.deletePassword(for: ServerPasswordStore.passwordReference(for: serverID))
        },
        deletePublished: { server in
            try KeychainManager.deletePublishedPassword(for: server)
        },
        deleteSharedCompatibility: { server in
            try KeychainManager.deleteSharedCompatibilityPassword(for: server)
        },
        prepareRollback: { server in
            try KeychainManager.passwordRollback(for: server)
        }
    )

    static func passwordReference(for serverID: UUID) -> ServerConfiguration {
        ServerConfiguration(id: serverID, name: "Credential", host: "", username: "")
    }
}

struct ServerCredentialDeletionJournal: Codable, Equatable {
    enum Operation: String, Codable, Equatable {
        case deleteServer
        case removePasswordAuthentication
    }

    struct Entry: Codable, Equatable {
        let serverID: UUID
        let operation: Operation
        let createdAt: Date
    }

    static let currentVersion = 1
    let version: Int
    var entries: [Entry]
}

private enum HostTrustMigrationError: LocalizedError {
    case malformedGlobalSource
    case conflictingKeys
    case keychainReadbackMismatch
    case persistenceReadbackMismatch

    var errorDescription: String? {
        switch self {
        case .malformedGlobalSource:
            return "The global legacy host-trust source could not be decoded."
        case .conflictingKeys:
            return "Multiple different legacy host keys exist for one endpoint."
        case .keychainReadbackMismatch:
            return "A migrated host key could not be verified in Keychain."
        case .persistenceReadbackMismatch:
            return "A migration persistence write could not be verified."
        }
    }

    var code: String {
        switch self {
        case .malformedGlobalSource: return "malformed-global-source"
        case .conflictingKeys: return "conflicting-keys"
        case .keychainReadbackMismatch: return "keychain-readback-mismatch"
        case .persistenceReadbackMismatch: return "persistence-readback-mismatch"
        }
    }
}

@MainActor
@Observable
class ServerManager {
    var servers: [ServerConfiguration] = []
    private(set) var serverCatalogLoadError: ServerManagerError?

    static let currentHostTrustMigrationVersion = 1
    static let credentialDeletionJournalDefaultsKey = "serverCredentialDeletionJournal"
    static let maximumCredentialDeletionJournalEntries = 128
    static let maximumCredentialDeletionJournalBytes = 64 * 1024
    static let maximumServerCatalogBytes = 1024 * 1024

    var familyCatalogLoaded: Bool { hasLoadedServers && serverCatalogLoadError == nil }
    private var hasLoadedServers = false
    private let defaults: UserDefaults
    private let hostTrustStore: HostTrustMigrationStore
    private let credentialMigrationStore: CredentialMigrationStore
    private let credentialMigrationMetadata: CredentialMigrationMetadata
    private let defersLiveCredentialMigration: Bool
    private let passwordStore: ServerPasswordStore
    private var store: ServerPersistenceStore

    /// D27: asks the shell to put a machine in the library for a server this capability is about
    /// to save, returning the endpoint id to save it under. Set by the composition root, because a
    /// capability must not hold the shell model (project rule 6).
    ///
    /// Nil in a unit test or a preview, where creation keeps its old behaviour — a fresh `UUID()`
    /// and no host record. That keeps the existing terminal tests meaningful instead of forcing a
    /// shell into every one of them.
    var adoptHost: (@MainActor (_ hostName: String, _ address: String, _ serviceName: String) async throws -> UUID)?

    /// Undoes an adoption whose server then failed to save, so a half-made machine never survives.
    var discardAdoption: (@MainActor (UUID) async -> Void)?

    /// The id a newly created server should use, and the cleanup to run if saving it fails.
    ///
    /// Returns a plain `UUID()` when no shell is attached, which is exactly what the callers did
    /// before D27 — so the change is "the library also learns about it", not "creation works
    /// differently".
    @MainActor
    func adoptedIdentity(hostName: String, address: String,
                         serviceName: String) async throws -> (id: UUID, discard: (@MainActor () async -> Void)?) {
        // No shell attached — a unit test or a preview — behaves exactly as this did before D27.
        guard let adoptHost else { return (UUID(), nil) }
        // A *failed* adoption is not the same thing, and must not be swallowed into it. Saving the
        // server anyway would produce precisely the orphan D27 exists to remove: a connection with
        // no machine, invisible in the library, with nowhere to be stored under D26.
        let id = try await adoptHost(hostName, address, serviceName)
        let discardAdoption = self.discardAdoption
        return (id, { await discardAdoption?(id) })
    }

    /// Whether the **persisted** catalog still references this SSH key.
    ///
    /// Deliberately not a question about `servers`, which is what is in memory: this answers a
    /// crash-recovery question about what actually survived on disk, which is why the SSH key
    /// deletion journal asks it at startup. Nil means nothing is stored at all — ambiguous rather
    /// than "no", and the caller treats it as such.
    ///
    /// It exists because the caller used to read the catalog's defaults key directly
    /// (`SettingsManager.persistedServerMetadataReferences`), bypassing this type entirely. D26
    /// moves the catalog into the shell's store, so a raw defaults read would simply stop finding
    /// anything — silently answering "no key is referenced" and letting a key in use be deleted.
    func persistedCatalogReferences(sshKeyID: UUID) throws -> Bool? {
        guard let data = store.load() else { return nil }
        guard let servers = try? JSONDecoder().decode([ServerConfiguration].self, from: data) else {
            throw ServerManagerError.invalidServerCatalog
        }
        return servers.contains { $0.sshKeyID == sshKeyID }
    }

    /// The legacy host-trust migration kicked off by `loadServers`. Await it when the migration's
    /// result is what is being observed; it is nil when no load has happened.
    private(set) var legacyHostTrustMigration: Task<Void, Never>?

    /// `serverDataWriter` predates `store` and is kept because a dozen tests drive failure through
    /// it. When given, it replaces only the write half; reads and rollback stay where they were,
    /// which is what those tests assume. New callers pass `store`.
    init(
        loadImmediately: Bool = true,
        defaults: UserDefaults? = nil,
        hostTrustStore: HostTrustMigrationStore? = nil,
        credentialMigrationStore: CredentialMigrationStore? = nil,
        credentialMigrationMetadata: CredentialMigrationMetadata = .unavailable,
        passwordStore: ServerPasswordStore? = nil,
        store: ServerPersistenceStore? = nil,
        serverDataWriter: ((Data) -> Void)? = nil
    ) {
        self.defaults = defaults ?? SharedDefaults.defaults
        self.hostTrustStore = hostTrustStore ?? .live
        self.credentialMigrationStore = credentialMigrationStore
            ?? .live(defaults: defaults ?? SharedDefaults.defaults)
        self.credentialMigrationMetadata = credentialMigrationMetadata
        self.defersLiveCredentialMigration = credentialMigrationStore == nil && defaults == nil
        self.passwordStore = passwordStore ?? .live
        let resolvedDefaults = defaults ?? SharedDefaults.defaults
        let liveStore = ServerPersistenceStore.live(defaults: resolvedDefaults)
        if let store {
            self.store = store
        } else if let serverDataWriter {
            self.store = ServerPersistenceStore(
                load: liveStore.load,
                hasStoredValue: liveStore.hasStoredValue,
                save: { data in serverDataWriter(data) },
                restore: liveStore.restore
            )
        } else {
            self.store = liveStore
        }
        if loadImmediately {
            loadServersIfNeeded()
        }
    }

    /// False only while `attach(store:)` re-reads: see the note there.
    private var runsFirstLaunchMigrations = true

    /// Points this manager at a different store, and reloads from it.
    ///
    /// The composition root calls this once, with the catalog-backed store (D26). It exists as a
    /// method rather than an init parameter because the shell model does not exist yet when the
    /// terminal runtime is built — the runtime is registered *with* the model — and inverting that
    /// would mean the capability holding the model, which rule 6 forbids.
    func attach(store: ServerPersistenceStore) {
        self.store = store
        hasLoadedServers = false
        // Re-reading from a different store is not a first launch. The credential and host-trust
        // migrations run once, against whatever was there at startup; re-running them here would
        // reach the Keychain again for no reason, and in a test process with no real Keychain
        // behind it that is a hang rather than a no-op.
        runsFirstLaunchMigrations = false
        loadServersIfNeeded()
        runsFirstLaunchMigrations = true
    }

    func loadServersIfNeeded() {
        guard !hasLoadedServers else { return }
        hasLoadedServers = true
        loadServers()
    }

    func loadServers() {
        do {
            let loadedServers: [ServerConfiguration]
            let hasStoredCatalog = store.hasStoredValue()
            let persistedCatalog = store.load()
            if let data = persistedCatalog {
                guard data.count <= Self.maximumServerCatalogBytes else {
                    throw ServerManagerError.invalidServerCatalog
                }
                loadedServers = try JSONDecoder().decode([ServerConfiguration].self, from: data)
            } else if !hasStoredCatalog {
                loadedServers = []
            } else {
                // UserDefaults returns nil from data(forKey:) for a value of the
                // wrong persisted type. That is corruption, not an empty catalog.
                throw ServerManagerError.invalidServerCatalog
            }
            try Self.validateServerCatalog(loadedServers)
            servers = loadedServers
            serverCatalogLoadError = nil
            do {
                if defaults.data(forKey: Self.credentialDeletionJournalDefaultsKey) != nil,
                   persistedCatalog == nil {
                    throw ServerManagerError.invalidServerCatalog
                }
                try reconcileCredentialDeletionJournal()
            } catch {
                Logger.keychain.error("Server credential deletion recovery did not complete: \(error.localizedDescription)")
            }
            guard runsFirstLaunchMigrations else { return }
            migrateLegacyCredentialsIfNeeded(from: servers)
            // The host-trust migration writes the catalog, which is now an async store, while
            // `loadServers` stays synchronous because `init` calls it. The task is held rather
            // than detached so anything that needs the migration finished can wait for it —
            // `loadServers` alone no longer guarantees it has run.
            //
            // D26 removes this migration entirely along with the defaults-backed catalog: it
            // reads `sh.glas.app`'s legacy `trustedHostKeys`, and the decision is that the new
            // build reads nothing old.
            legacyHostTrustMigration = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.migrateLegacyHostTrustIfNeeded(from: self.servers)
            }
        } catch {
            Logger.servers.error("Failed to load servers: \(error)")
            // Retain both the previously verified in-memory catalog and a durable
            // failure state. Mutations must not reinterpret unreadable bytes as []
            // and overwrite the only remaining copy.
            serverCatalogLoadError = .invalidServerCatalog
        }
    }

    private func migrateLegacyCredentialsIfNeeded(from loadedServers: [ServerConfiguration]) {
        if defersLiveCredentialMigration {
            let servers = KeychainManager.credentialMigrationServers(from: loadedServers)
            let metadata = credentialMigrationMetadata
            Task.detached(priority: .utility) {
                do {
                    _ = try KeychainManager.runCredentialMigrationIfNeeded(
                        serverSnapshots: servers,
                        metadata: metadata,
                        store: .live(defaults: SharedDefaults.defaults)
                    )
                } catch {
                    Logger.keychain.error(
                        "Credential namespace migration did not complete: \(error.localizedDescription)"
                    )
                }
            }
            return
        }

        do {
            _ = try KeychainManager.runCredentialMigrationIfNeeded(
                servers: loadedServers,
                metadata: credentialMigrationMetadata,
                store: credentialMigrationStore
            )
        } catch {
            Logger.keychain.error("Credential namespace migration did not complete: \(error.localizedDescription)")
        }
    }

    func saveServers() async {
        do {
            try await persistServersAndVerify(servers)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Logger.servers.error("Failed to save servers: \(error)")
        }
    }

    func persistServersOrThrow() async throws {
        try await persistServersAndVerify(servers)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func addServer(_ server: ServerConfiguration) async {
        do {
            try await addServerOrThrow(server)
        } catch {
            Logger.servers.error("Failed to add server: \(error.localizedDescription)")
        }
    }

    func updateServer(_ server: ServerConfiguration) async {
        do {
            try await updateServerOrThrow(server)
        } catch {
            Logger.servers.error("Failed to update server: \(error.localizedDescription)")
        }
    }

    func addServerOrThrow(_ server: ServerConfiguration, password: String? = nil) async throws {
        try ensureServerCatalogAvailable()
        guard !servers.contains(where: { $0.id == server.id }) else {
            throw ServerManagerError.serverAlreadyExists
        }
        let candidateServers = servers + [server]
        if let password {
            try await stagePasswordAndPersist(password, for: server, candidateServers: candidateServers)
        } else {
            try await persistServerMutation(candidateServers)
        }
    }

    func updateServerOrThrow(_ server: ServerConfiguration, password: String? = nil) async throws {
        try ensureServerCatalogAvailable()
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else {
            throw ServerManagerError.serverNotFound
        }
        let originalServer = servers[index]
        var candidateServers = servers
        candidateServers[index] = server

        if let password {
            try await stagePasswordAndPersist(password, for: server, candidateServers: candidateServers)
        } else if originalServer.authMethod == .password && server.authMethod != .password {
            try await removePasswordAndPersist(
                for: originalServer,
                candidateServers: candidateServers
            )
        } else {
            try await persistServerMutation(candidateServers)
        }
    }

    func password(for server: ServerConfiguration) throws -> String {
        try ensureServerCatalogAvailable()
        return try passwordStore.retrieve(server)
    }

    func server(for id: UUID) -> ServerConfiguration? {
        servers.first { $0.id == id }
    }

    func deleteServer(_ server: ServerConfiguration) async throws {
        try ensureServerCatalogAvailable()
        guard servers.contains(where: { $0.id == server.id }) else {
            throw ServerManagerError.serverNotFound
        }
        let originalServers = servers
        let remainingServers = servers.filter { $0.id != server.id }
        let passwordRollback = try passwordStore.prepareRollback(server)
        var journal = try loadCredentialDeletionJournal()
        if let existing = journal.entries.first(where: { $0.serverID == server.id }) {
            guard existing.operation == .deleteServer else {
                throw ServerManagerError.invalidDeletionJournal
            }
        } else {
            guard journal.entries.count < Self.maximumCredentialDeletionJournalEntries else {
                throw ServerManagerError.deletionJournalFull
            }
            journal.entries.append(.init(
                serverID: server.id,
                operation: .deleteServer,
                createdAt: Date()
            ))
            try persistCredentialDeletionJournal(journal)
        }

        do {
            try await persistServersAndVerify(remainingServers)
            try deletePasswordAndVerifyAbsence(for: server.id)
            journal.entries.removeAll { $0.serverID == server.id }
            try persistCredentialDeletionJournal(journal)
        } catch {
            do {
                try passwordRollback.restore()
                try await persistServersAndVerify(originalServers)
                journal.entries.removeAll { $0.serverID == server.id }
                try persistCredentialDeletionJournal(journal)
            } catch {
                throw ServerManagerError.rollbackFailed
            }
            throw error
        }
        servers = remainingServers
        // D26/D27: the machine's service link goes with the server. Deleting from the terminal's
        // own surfaces used to leave the catalog's link pointing at nothing — the same orphan D25
        // fixed in the other direction, where deleting a machine left the capability's record. The
        // link goes last, after the record it describes is definitely gone: a stray link is
        // recoverable from the library, a record nothing points at is not.
        await discardAdoption?(server.id)
        WidgetCenter.shared.reloadAllTimelines()
    }

    #if DEBUG
    /// Removes the isolated UI-test fixture and its cross-app compatibility
    /// credential. The fixed documentation-only endpoint prevents this test
    /// hook from matching a real host.
    func purgeConnectionLibraryUITestFixtures() async throws {
        try ensureServerCatalogAvailable()
        let fixtures = servers.filter {
            $0.name.hasPrefix(Self.connectionLibraryUITestNamePrefix)
                && $0.host == Self.connectionLibraryUITestHost
                && $0.port == 22
                && $0.username == Self.connectionLibraryUITestUsername
                && $0.authMethod == .password
        }
        for server in fixtures {
            try await deleteServer(server)
        }

        let compatibilityReference = ServerConfiguration(
            name: Self.connectionLibraryUITestNamePrefix,
            host: Self.connectionLibraryUITestHost,
            port: 22,
            username: Self.connectionLibraryUITestUsername,
            authMethod: .password
        )
        try passwordStore.deleteSharedCompatibility(compatibilityReference)
    }

    static let connectionLibraryUITestNamePrefix = "Connection Library UI Test "
    static let connectionLibraryUITestHost = "192.0.2.1"
    static let connectionLibraryUITestUsername = "ui-test"
    #endif

    func updateLastConnected(_ serverID: UUID) async {
        do {
            try ensureServerCatalogAvailable()
            guard let index = servers.firstIndex(where: { $0.id == serverID }) else { return }
            var candidateServers = servers
            candidateServers[index].lastConnected = Date()
            try await persistServerMutation(candidateServers)
        } catch {
            Logger.servers.error("Failed to update recent server metadata: \(error.localizedDescription)")
        }
    }

    func toggleFavorite(_ server: ServerConfiguration) async {
        do {
            try ensureServerCatalogAvailable()
            guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
            var candidateServers = servers
            candidateServers[index].isFavorite.toggle()
            try await persistServerMutation(candidateServers)
        } catch {
            Logger.servers.error("Failed to update favorite server metadata: \(error.localizedDescription)")
        }
    }

    func trustHostKey(_ challenge: HostKeyTrustChallenge, for serverID: UUID) async throws {
        try ensureServerCatalogAvailable()
        guard let index = servers.firstIndex(where: { $0.id == serverID }) else {
            throw ServerManagerError.serverNotFound
        }

        // Replacing trust for an endpoint must revoke every prior key for that
        // endpoint. Keeping an old key active after the user accepts a changed
        // fingerprint defeats the meaning of the warning.
        try KeychainManager.replaceHostKey(with: challenge)

        servers[index].trustedHostKeys = nil
        await saveServers()
    }

    private func stagePasswordAndPersist(
        _ password: String,
        for server: ServerConfiguration,
        candidateServers: [ServerConfiguration]
    ) async throws {
        let originalServers = servers
        let passwordRollback = try passwordStore.prepareRollback(server)
        do {
            try passwordStore.save(password, server)
            guard try passwordStore.retrieve(server) == password else {
                throw ServerManagerError.credentialReadbackMismatch
            }
            try await persistServersAndVerify(candidateServers)
        } catch {
            do {
                try passwordRollback.restore()
                try await persistServersAndVerify(originalServers)
            } catch {
                throw ServerManagerError.rollbackFailed
            }
            throw error
        }
        servers = candidateServers
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func removePasswordAndPersist(
        for server: ServerConfiguration,
        candidateServers: [ServerConfiguration]
    ) async throws {
        let originalServers = servers
        let passwordRollback = try passwordStore.prepareRollback(server)
        var journal = try loadCredentialDeletionJournal()
        if let existing = journal.entries.first(where: { $0.serverID == server.id }) {
            guard existing.operation == .removePasswordAuthentication else {
                throw ServerManagerError.invalidDeletionJournal
            }
        } else {
            guard journal.entries.count < Self.maximumCredentialDeletionJournalEntries else {
                throw ServerManagerError.deletionJournalFull
            }
            journal.entries.append(.init(
                serverID: server.id,
                operation: .removePasswordAuthentication,
                createdAt: Date()
            ))
            try persistCredentialDeletionJournal(journal)
        }
        do {
            try await persistServersAndVerify(candidateServers)
            try deletePasswordAndVerifyAbsence(for: server.id)
            journal.entries.removeAll { $0.serverID == server.id }
            try persistCredentialDeletionJournal(journal)
        } catch {
            do {
                try passwordRollback.restore()
                try await persistServersAndVerify(originalServers)
                journal.entries.removeAll { $0.serverID == server.id }
                try persistCredentialDeletionJournal(journal)
            } catch {
                throw ServerManagerError.rollbackFailed
            }
            throw error
        }
        servers = candidateServers
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persistServerMutation(_ candidateServers: [ServerConfiguration]) async throws {
        try ensureServerCatalogAvailable()
        let originalServers = servers
        do {
            try await persistServersAndVerify(candidateServers)
        } catch {
            do {
                try await persistServersAndVerify(originalServers)
            } catch {
                throw ServerManagerError.rollbackFailed
            }
            throw error
        }
        servers = candidateServers
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deletePasswordAndVerifyAbsence(for serverID: UUID) throws {
        do {
            try passwordStore.delete(serverID)
        } catch SecretStoreError.notFound {
            // Absence is verified below through the same UUID-scoped store.
        }
        do {
            _ = try passwordStore.retrieve(ServerPasswordStore.passwordReference(for: serverID))
            throw ServerManagerError.credentialReadbackMismatch
        } catch SecretStoreError.notFound {
            return
        }
    }

    private func loadCredentialDeletionJournal() throws -> ServerCredentialDeletionJournal {
        guard let data = defaults.data(forKey: Self.credentialDeletionJournalDefaultsKey) else {
            return .init(version: ServerCredentialDeletionJournal.currentVersion, entries: [])
        }
        guard data.count <= Self.maximumCredentialDeletionJournalBytes,
              let journal = try? JSONDecoder().decode(ServerCredentialDeletionJournal.self, from: data),
              journal.version == ServerCredentialDeletionJournal.currentVersion,
              journal.entries.count <= Self.maximumCredentialDeletionJournalEntries,
              Set(journal.entries.map(\.serverID)).count == journal.entries.count else {
            throw ServerManagerError.invalidDeletionJournal
        }
        return journal
    }

    private func persistCredentialDeletionJournal(
        _ journal: ServerCredentialDeletionJournal
    ) throws {
        guard journal.version == ServerCredentialDeletionJournal.currentVersion,
              journal.entries.count <= Self.maximumCredentialDeletionJournalEntries,
              Set(journal.entries.map(\.serverID)).count == journal.entries.count else {
            throw ServerManagerError.invalidDeletionJournal
        }
        if journal.entries.isEmpty {
            defaults.removeObject(forKey: Self.credentialDeletionJournalDefaultsKey)
            guard defaults.data(forKey: Self.credentialDeletionJournalDefaultsKey) == nil else {
                throw ServerManagerError.persistenceReadbackMismatch
            }
            return
        }
        let data = try JSONEncoder().encode(journal)
        guard data.count <= Self.maximumCredentialDeletionJournalBytes else {
            throw ServerManagerError.deletionJournalFull
        }
        defaults.set(data, forKey: Self.credentialDeletionJournalDefaultsKey)
        guard let persistedData = defaults.data(forKey: Self.credentialDeletionJournalDefaultsKey),
              let persisted = try? JSONDecoder().decode(ServerCredentialDeletionJournal.self, from: persistedData),
              persisted == journal else {
            throw ServerManagerError.persistenceReadbackMismatch
        }
    }

    private func reconcileCredentialDeletionJournal() throws {
        var journal = try loadCredentialDeletionJournal()
        guard !journal.entries.isEmpty else { return }

        for entry in journal.entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            let persistedServer = servers.first { $0.id == entry.serverID }
            let metadataProvesCommit: Bool
            switch entry.operation {
            case .deleteServer:
                metadataProvesCommit = persistedServer == nil
            case .removePasswordAuthentication:
                metadataProvesCommit = persistedServer?.authMethod != .password
            }

            // Metadata is the commit marker. A journal interrupted before its
            // corresponding metadata change describes an aborted operation, so
            // the still-live password wins and the journal is cleared.
            if !metadataProvesCommit {
                journal.entries.removeAll { $0.serverID == entry.serverID }
                try persistCredentialDeletionJournal(journal)
                continue
            }

            try deletePasswordAndVerifyAbsence(for: entry.serverID)
            journal.entries.removeAll { $0.serverID == entry.serverID }
            try persistCredentialDeletionJournal(journal)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func migrateLegacyHostTrustIfNeeded(from loadedServers: [ServerConfiguration]) async {
        let previousVersion = defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion)
        let globalData = defaults.data(forKey: UserDefaultsKeys.trustedHostKeys)
        let hasServerEntries = loadedServers.contains { $0.trustedHostKeys != nil }
        guard previousVersion < Self.currentHostTrustMigrationVersion || globalData != nil || hasServerEntries else {
            return
        }

        var globalSourceCount = 0
        let serverSourceCount = loadedServers.reduce(0) { $0 + ($1.trustedHostKeys?.count ?? 0) }
        var uniqueCandidateCount = 0
        var duplicateCount = 0
        var migratedCount = 0
        var alreadyPresentCount = 0
        var verifiedCount = 0

        do {
            let globalEntries: [TrustedHostKeyEntry]
            if let globalData {
                guard let decoded = try? JSONDecoder().decode([TrustedHostKeyEntry].self, from: globalData) else {
                    throw HostTrustMigrationError.malformedGlobalSource
                }
                globalEntries = decoded
            } else {
                globalEntries = []
            }
            globalSourceCount = globalEntries.count

            let allEntries = globalEntries + loadedServers.flatMap { $0.trustedHostKeys ?? [] }
            var candidatesByID: [String: PinnedSSHHostKey] = [:]
            for entry in allEntries {
                let candidate = try KeychainManager.pinnedHostKey(from: entry)
                if let existing = candidatesByID[candidate.storageAccount] {
                    duplicateCount += 1
                    let firstSeen = min(existing.createdAt, candidate.createdAt)
                    candidatesByID[candidate.storageAccount] = PinnedSSHHostKey(
                        host: existing.host,
                        port: existing.port,
                        algorithm: existing.algorithm,
                        publicKeyData: existing.publicKeyData,
                        sha256Fingerprint: existing.sha256Fingerprint,
                        createdAt: firstSeen,
                        lastSeenAt: max(existing.lastSeenAt, candidate.lastSeenAt)
                    )
                } else {
                    candidatesByID[candidate.storageAccount] = candidate
                }
            }

            let candidates = candidatesByID.values.sorted { $0.storageAccount < $1.storageAccount }
            uniqueCandidateCount = candidates.count
            let endpointGroups = Dictionary(grouping: candidates) { $0.lookupAccount }
            guard endpointGroups.values.allSatisfy({ $0.count <= 1 }) else {
                throw HostTrustMigrationError.conflictingKeys
            }

            let recordsBefore = candidates.isEmpty ? [] : try hostTrustStore.allRecords()
            guard candidates.allSatisfy({ candidate in
                recordsBefore.allSatisfy { record in
                    record.lookupAccount != candidate.lookupAccount
                        || record.storageAccount == candidate.storageAccount
                }
            }) else {
                throw HostTrustMigrationError.conflictingKeys
            }
            let recordIDsBefore = Set(recordsBefore.map(\.storageAccount))
            for candidate in candidates {
                if recordIDsBefore.contains(candidate.storageAccount) {
                    alreadyPresentCount += 1
                } else {
                    migratedCount += 1
                }
                try hostTrustStore.save(candidate)
            }

            let recordsAfter = candidates.isEmpty ? [] : try hostTrustStore.allRecords()
            for candidate in candidates {
                guard recordsAfter.contains(where: { record in
                    record.storageAccount == candidate.storageAccount
                        && record.host == candidate.host
                        && record.port == candidate.port
                        && record.algorithm == candidate.algorithm
                        && record.publicKeyData == candidate.publicKeyData
                        && record.sha256Fingerprint == candidate.sha256Fingerprint
                }) else {
                    throw HostTrustMigrationError.keychainReadbackMismatch
                }
                verifiedCount += 1
            }

            let verifiedReport = HostTrustMigrationReport(
                fromVersion: previousVersion,
                toVersion: Self.currentHostTrustMigrationVersion,
                state: .verified,
                globalSourceCount: globalSourceCount,
                serverSourceCount: serverSourceCount,
                uniqueCandidateCount: candidates.count,
                duplicateCount: duplicateCount,
                migratedCount: migratedCount,
                alreadyPresentCount: alreadyPresentCount,
                verifiedCount: verifiedCount,
                failedCount: 0,
                failureCode: nil,
                recordedAt: Date()
            )
            try persistReportAndVerify(verifiedReport)

            var sanitizedServers = loadedServers
            for index in sanitizedServers.indices {
                sanitizedServers[index].trustedHostKeys = nil
            }
            try await commitLegacySourceRemoval(
                sanitizedServers: sanitizedServers,
                originalServers: loadedServers,
                originalGlobalData: globalData,
                originalMigrationVersion: previousVersion,
                verifiedReport: verifiedReport
            )
            servers = sanitizedServers
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            let failureCode = (error as? HostTrustMigrationError)?.code ?? "validation-or-store-failure"
            let failedReport = HostTrustMigrationReport(
                fromVersion: previousVersion,
                toVersion: Self.currentHostTrustMigrationVersion,
                state: .failed,
                globalSourceCount: globalSourceCount,
                serverSourceCount: serverSourceCount,
                uniqueCandidateCount: uniqueCandidateCount,
                duplicateCount: duplicateCount,
                migratedCount: migratedCount,
                alreadyPresentCount: alreadyPresentCount,
                verifiedCount: verifiedCount,
                failedCount: 1,
                failureCode: failureCode,
                recordedAt: Date()
            )
            do {
                try persistReportAndVerify(failedReport)
            } catch {
                Logger.servers.error("Host-trust migration failure report could not be persisted: \(error)")
            }
            Logger.servers.error("Host-trust migration did not complete: \(error)")
        }
    }

    private func commitLegacySourceRemoval(
        sanitizedServers: [ServerConfiguration],
        originalServers: [ServerConfiguration],
        originalGlobalData: Data?,
        originalMigrationVersion: Int,
        verifiedReport: HostTrustMigrationReport
    ) async throws {
        let originalServersData = defaults.data(forKey: UserDefaultsKeys.servers)
        do {
            try await persistServersAndVerify(sanitizedServers)
            defaults.removeObject(forKey: UserDefaultsKeys.trustedHostKeys)
            guard defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == nil else {
                throw HostTrustMigrationError.persistenceReadbackMismatch
            }

            let completedReport = HostTrustMigrationReport(
                fromVersion: verifiedReport.fromVersion,
                toVersion: verifiedReport.toVersion,
                state: .completed,
                globalSourceCount: verifiedReport.globalSourceCount,
                serverSourceCount: verifiedReport.serverSourceCount,
                uniqueCandidateCount: verifiedReport.uniqueCandidateCount,
                duplicateCount: verifiedReport.duplicateCount,
                migratedCount: verifiedReport.migratedCount,
                alreadyPresentCount: verifiedReport.alreadyPresentCount,
                verifiedCount: verifiedReport.verifiedCount,
                failedCount: 0,
                failureCode: nil,
                recordedAt: Date()
            )
            try persistReportAndVerify(completedReport)
            defaults.set(Self.currentHostTrustMigrationVersion, forKey: UserDefaultsKeys.hostTrustMigrationVersion)
            guard defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion)
                    == Self.currentHostTrustMigrationVersion else {
                throw HostTrustMigrationError.persistenceReadbackMismatch
            }
        } catch {
            if let originalServersData {
                defaults.set(originalServersData, forKey: UserDefaultsKeys.servers)
            } else {
                defaults.removeObject(forKey: UserDefaultsKeys.servers)
            }
            if let originalGlobalData {
                defaults.set(originalGlobalData, forKey: UserDefaultsKeys.trustedHostKeys)
            } else {
                defaults.removeObject(forKey: UserDefaultsKeys.trustedHostKeys)
            }
            if originalMigrationVersion > 0 {
                defaults.set(originalMigrationVersion, forKey: UserDefaultsKeys.hostTrustMigrationVersion)
            } else {
                defaults.removeObject(forKey: UserDefaultsKeys.hostTrustMigrationVersion)
            }
            servers = originalServers
            throw error
        }
    }

    /// Writes the catalog and proves it landed.
    ///
    /// The readback compares *decoded* servers rather than bytes, because two encodings of the
    /// same catalog are the same catalog and a byte comparison would fail a store that round-trips
    /// through anything but the exact encoder used here.
    private func persistServersAndVerify(_ candidateServers: [ServerConfiguration]) async throws {
        try ensureServerCatalogAvailable()
        try Self.validateServerCatalog(candidateServers)
        let data = try JSONEncoder().encode(candidateServers)
        guard data.count <= Self.maximumServerCatalogBytes else {
            throw ServerManagerError.invalidServerCatalog
        }
        try await store.save(data)
        // Compared by identity rather than as an ordered list. The catalog keeps configurations in
        // a dictionary keyed by endpoint id, so it has no insertion order to give back, and two
        // orderings of the same servers are the same catalog. What the check still guarantees is
        // the part that matters: every server that went in came back, unchanged, and nothing else
        // came back with it.
        guard let persistedData = store.load(),
              let persistedServers = try? JSONDecoder().decode([ServerConfiguration].self, from: persistedData),
              Dictionary(persistedServers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                == Dictionary(candidateServers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) else {
            throw ServerManagerError.persistenceReadbackMismatch
        }
        defaults.set(SharedDefaults.currentSchemaVersion, forKey: SharedDefaults.schemaVersionKey)
    }

    private static func validateServerCatalog(_ candidateServers: [ServerConfiguration]) throws {
        var serverIDs = Set<UUID>()
        guard candidateServers.allSatisfy({ server in
            guard serverIDs.insert(server.id).inserted else { return false }
            switch (server.initialTerminalColumns, server.initialTerminalRows) {
            case (nil, nil):
                return true
            case (.some(let columns), .some(let rows)):
                return TerminalGeometry.contains(rows: rows, columns: columns)
            default:
                return false
            }
        }) else {
            throw ServerManagerError.invalidServerCatalog
        }
    }

    private func ensureServerCatalogAvailable() throws {
        if let serverCatalogLoadError {
            throw serverCatalogLoadError
        }
    }

    private func persistReportAndVerify(_ report: HostTrustMigrationReport) throws {
        let data = try JSONEncoder().encode(report)
        defaults.set(data, forKey: UserDefaultsKeys.hostTrustMigrationReport)
        guard let persistedData = defaults.data(forKey: UserDefaultsKeys.hostTrustMigrationReport),
              let persistedReport = try? JSONDecoder().decode(HostTrustMigrationReport.self, from: persistedData),
              persistedReport == report else {
            throw HostTrustMigrationError.persistenceReadbackMismatch
        }
    }
}

enum ServerManagerError: LocalizedError, Equatable {
    case serverNotFound
    case serverAlreadyExists
    case persistenceReadbackMismatch
    case credentialReadbackMismatch
    case invalidDeletionJournal
    case invalidServerCatalog
    case deletionJournalFull
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "The server configuration is no longer available."
        case .serverAlreadyExists:
            return "A server configuration with this identifier already exists."
        case .persistenceReadbackMismatch:
            return "The saved server configuration could not be verified."
        case .credentialReadbackMismatch:
            return "The UUID-scoped server credential could not be verified."
        case .invalidDeletionJournal:
            return "The pending server credential deletion journal is invalid."
        case .invalidServerCatalog:
            return "The persisted server catalog is missing, malformed, or too large for credential recovery."
        case .deletionJournalFull:
            return "Too many server credential deletions are pending recovery."
        case .rollbackFailed:
            return "The server change failed and its credential or configuration rollback could not be verified."
        }
    }
}
