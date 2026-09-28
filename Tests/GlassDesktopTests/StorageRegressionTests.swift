//
//  StorageRegressionTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/StorageRegressionTests.swift` on 2026-09-27.
//
//  glassDT kept its desktops in its own `connections.json` (an actor with `flock`, atomic rename and
//  a schema version) and published them to a separate App Group `HostCatalogStore` through
//  publication and removal journals. D26 replaced both with one store: `DesktopRepository` keeps
//  each desktop on its service link in the shell's catalog, through `GlassServiceRecords` and a
//  `GlassServiceStore`. So these tests drive the same behaviours onto that store:
//
//  - The file-backed repository's injectable `writer` became `ControlledServiceStore` below, a
//    test-only `GlassServiceStore` that can refuse writes, report itself unread, and suspend on
//    each write the way the shell's real store does (it awaits the catalog actor).
//  - "Corrupt shared catalog" became "catalog not read yet": in GPT a corrupt catalog is the
//    shell's to report, and what reaches the desktop is `isCatalogLoaded == false`. The removed
//    `hostLibraryStatus` / `errorMessage` checks became `!app.isLoaded`, the model's signal for
//    "unknown, not empty".
//  - "Catalog bytes unchanged" became "the store's contents unchanged".
//  - The profile-deletion test keeps its "other services survive" half; its removal-journal
//    retry half is gone with the journal.
//  - The concurrent-writers test lost its `0o600` file-permission check: there is no file.
//
//  Dropped, because GPT deliberately removed the mechanism they test (D22/D26; stage-4 plan,
//  "Deleted, not parity"): the shared-container fallback and pairing recovery, offline deletion
//  journal, publication acknowledgement, catalog failure after commit (there is no second write
//  after the commit any more), paired-service move/detach, stale host cache vs. pairing (host
//  identity is the shell's), and the legacy version-1 `connections.json` document.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
import GlasSecretStore
@testable import GlassDesktop

enum DesktopStorageTestFailure: Error, Equatable { case write, locked, missing }

/// A `GlassServiceStore` for failure tests. The shell's `GlassInMemoryServiceStore` cannot fail,
/// cannot be unread and never suspends; the real store can do all three.
@MainActor
private final class ControlledServiceStore: GlassServiceStore {
    private var storage: [EndpointID: (kind: HostServiceKind, data: Data)] = [:]
    var isCatalogLoaded = true
    var writeFailure: (any Error)?
    /// Yield before each write, as the shell's store does while it awaits the catalog actor.
    var suspendsOnWrite = false

    func configuration(for endpointID: EndpointID) -> Data? { storage[endpointID]?.data }

    func setConfiguration(_ data: Data?, for endpointID: EndpointID) async throws {
        if suspendsOnWrite { await Task.yield() }
        if let writeFailure { throw writeFailure }
        guard let data else { storage.removeValue(forKey: endpointID); return }
        storage[endpointID] = (storage[endpointID]?.kind ?? .rdp, data)
    }

    func configurations(ofKind kind: HostServiceKind) -> [EndpointID: Data] {
        storage.filter { $0.value.kind == kind }.mapValues(\.data)
    }

    /// Another capability's configuration, filed under its own kind.
    func seed(_ data: Data, kind: HostServiceKind, for endpointID: EndpointID) {
        storage[endpointID] = (kind, data)
    }

    /// Everything stored, of every kind, for "nothing changed" checks.
    var contents: [EndpointID: Data] { storage.mapValues(\.data) }
}

@MainActor
private final class CredentialFixture {
    struct Key: Hashable { let id: UUID; let policy: SecretMobilityPolicy }
    var items: [Key: RDPCredential] = [:]
    var saved: [UUID] = []
    var deleted: [UUID] = []
    var migrations: [UUID] = []
    var migrationFailure: DesktopStorageTestFailure?

    func key(_ id: UUID, _ config: SecretStoreConfiguration) -> Key {
        Key(id: id, policy: config.mobilityPolicy)
    }
    func seed(_ connection: DesktopConnection, username: String? = nil) {
        items[Key(id: connection.credentialID.rawValue, policy: connection.mobility)] =
            RDPCredential(username: username ?? connection.username, domain: connection.domain, password: "test secret")
    }
    var access: DesktopCredentialAccess {
        DesktopCredentialAccess(retrieve: { id, config, _ in
            guard let item = self.items[self.key(id, config)] else { throw DesktopStorageTestFailure.missing }
            return item
        }, save: { item, id, config in
            self.items[self.key(id, config)] = item
            self.saved.append(id)
        }, delete: { id, config in
            self.items.removeValue(forKey: self.key(id, config))
            self.deleted.append(id)
        }, availability: { id, config in
            self.items[self.key(id, config)] == nil ? .missing : .available
        }, migrate: { id, source, destination in
            self.migrations.append(id)
            if let failure = self.migrationFailure { throw failure }
            guard let item = self.items[self.key(id, source)] else { throw DesktopStorageTestFailure.missing }
            self.items[self.key(id, destination)] = item
        })
    }
}

@MainActor
private final class StorageFixture {
    let directory: URL
    let store = ControlledServiceStore()
    let repository: DesktopRepository
    let credentials = CredentialFixture()
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("glassdt-storage-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = DesktopRepository(store: store)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func model(accessGroup: String? = nil, access: DesktopCredentialAccess? = nil) async -> DesktopAppModel {
        let app = DesktopAppModel(storageDirectory: directory, accessGroup: accessGroup,
                                  credentialAccess: access ?? credentials.access)
        await app.attach(store: store)
        return app
    }
    func seed() async throws -> DesktopConnection {
        let connection = DesktopConnection(name: "Workstation", host: "work.example", username: "alice")
        _ = try await repository.save(connection)
        credentials.seed(connection)
        return connection
    }
}

@Suite("Credential and host storage recovery")
@MainActor
struct StorageRegressionTests {
    /// Was `deniedSharedDirectoryDoesNotBypassCredentialFailure`: the denied App Group container is
    /// gone, the rule is not — a Keychain failure saves nothing, and is not retried under another
    /// group or policy.
    @Test func credentialFailureSavesNothingAndKeepsConfiguredGroupAndPolicy() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        var access = fixture.credentials.access
        var attemptedGroups: [String?] = []
        var attemptedPolicies: [SecretMobilityPolicy] = []
        access.save = { _, _, configuration in
            attemptedGroups.append(configuration.accessGroup)
            attemptedPolicies.append(configuration.mobilityPolicy)
            throw DesktopStorageTestFailure.locked
        }
        let app = await fixture.model(accessGroup: "TEAM.unchanged", access: access)
        var connection = DesktopConnection(name: "Desktop", host: "work.example", username: "alice")
        connection.mobility = .iCloudKeychain
        await #expect(throws: DesktopStorageTestFailure.locked) { try await app.save(connection, password: "test secret") }
        #expect(try fixture.repository.load().isEmpty)
        #expect(attemptedGroups == ["TEAM.unchanged"])
        #expect(attemptedPolicies == [.iCloudKeychain])
    }

    @Test func keychainSaveFailureExplainsUncommittedEditWithoutPolicyFallback() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let previous = try #require(try fixture.repository.load().first)
        var attemptedGroups: [String?] = []
        var attemptedPolicies: [SecretMobilityPolicy] = []
        var access = fixture.credentials.access
        access.save = { _, _, configuration in
            attemptedGroups.append(configuration.accessGroup)
            attemptedPolicies.append(configuration.mobilityPolicy)
            throw SecretStoreError.unableToSave
        }
        let app = await fixture.model(accessGroup: "TEAM.existing.group", access: access)
        var edited = previous
        edited.name = "Attempted edit"
        edited.mobility = .iCloudKeychain
        do {
            try await app.save(edited, password: "replacement")
            Issue.record("Expected a Keychain save failure")
        } catch let error as AppStorageError {
            #expect(error.localizedDescription.contains("desktop changes were not saved"))
            #expect(error.localizedDescription.contains("configured Keychain group"))
        }
        #expect(try fixture.repository.load() == [previous])
        #expect(attemptedGroups == ["TEAM.existing.group"])
        #expect(attemptedPolicies == [.iCloudKeychain])
        #expect(fixture.credentials.items.count == 1)
        #expect(fixture.credentials.deleted.isEmpty)
    }

    /// Was `corruptSharedCatalogNeverFallsBackToAnEmptyLibrary`. What reaches the desktop in GPT is
    /// a catalog that has not been read: it must not be taken for an empty library.
    @Test func unreadCatalogNeverFallsBackToAnEmptyLibrary() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        fixture.store.isCatalogLoaded = false
        let before = fixture.store.contents
        let app = await fixture.model()
        #expect(!app.isLoaded)
        let connection = DesktopConnection(name: "Desktop", host: "work.example", username: "alice")
        await #expect(throws: (any Error).self) { try await app.save(connection, password: "test secret") }
        #expect(try fixture.repository.load().isEmpty)
        #expect(fixture.credentials.saved.isEmpty)
        #expect(fixture.store.contents == before)
    }

    @Test(arguments: [DesktopStorageTestFailure.locked, .missing])
    func failedMobilityMigrationPreservesSourceAndPolicy(_ failure: DesktopStorageTestFailure) async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        await app.load()
        let previous = try #require(try fixture.repository.load().first)
        fixture.credentials.migrationFailure = failure
        var edited = previous
        edited.mobility = .iCloudKeychain
        await #expect(throws: failure) { try await app.save(edited, password: nil) }
        #expect(try fixture.repository.load() == [previous])
        #expect(fixture.credentials.migrations == [previous.credentialID.rawValue])
        #expect(fixture.credentials.items.count == 1)
        #expect(fixture.credentials.deleted.isEmpty)
    }

    @Test func successfulMobilityMigrationKeepsIdentityAndSource() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        await app.load()
        let previous = try #require(try fixture.repository.load().first)
        var edited = previous
        edited.mobility = .iCloudKeychain
        try await app.save(edited, password: nil)
        let saved = try #require(try fixture.repository.load().first)
        #expect(saved.credentialID == previous.credentialID)
        #expect(saved.mobility == .iCloudKeychain)
        #expect(fixture.credentials.items.count == 2)
        #expect(fixture.credentials.deleted.isEmpty)
    }

    @Test func accountChangeRequiresCredentialAndMismatchCannotConnect() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        await app.load()
        let previous = try #require(try fixture.repository.load().first)
        var edited = previous
        edited.username = "bob"
        await #expect(throws: AppStorageError.self) { try await app.save(edited, password: nil) }
        #expect(try fixture.repository.load() == [previous])
        fixture.credentials.seed(previous, username: "another account")
        #expect(throws: AppStorageError.self) { try app.credential(for: previous) }
        #expect(fixture.credentials.saved.isEmpty)
    }

    @Test func failedProfileWriteCleansOnlyNewCredential() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        let previous = try #require(try fixture.repository.load().first)
        fixture.store.writeFailure = DesktopStorageTestFailure.write
        var edited = previous
        edited.username = "bob"
        await #expect(throws: DesktopStorageTestFailure.write) { try await app.save(edited, password: "new secret") }
        #expect(try fixture.repository.load() == [previous])
        #expect(fixture.credentials.saved.count == 1)
        #expect(fixture.credentials.deleted == fixture.credentials.saved)
        #expect(!fixture.credentials.deleted.contains(previous.credentialID.rawValue))
        #expect(fixture.credentials.items.count == 1)
    }

    /// Was `profileDeletionRetriesCatalogAndPreservesOtherServices`. The retry half tested the
    /// removal journal, which D26 deleted; removing a desktop still must not touch the host's
    /// other services.
    @Test func profileDeletionPreservesOtherServices() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        await app.load()
        let saved = try #require(try fixture.repository.load().first)
        let terminal = EndpointID()
        let terminalConfiguration = Data("terminal configuration".utf8)
        fixture.store.seed(terminalConfiguration, kind: .ssh, for: terminal)
        await app.delete(saved)
        #expect(try fixture.repository.load().isEmpty)
        #expect(app.errorMessage == nil)
        #expect(fixture.store.contents == [terminal: terminalConfiguration])
    }

    @Test func failedProfileDeletionLeavesCatalogAndSecretUntouched() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        let saved = try #require(try fixture.repository.load().first)
        let before = fixture.store.contents
        fixture.store.writeFailure = DesktopStorageTestFailure.write
        await app.delete(saved)
        #expect(app.errorMessage != nil)
        #expect(try fixture.repository.load() == [saved])
        #expect(fixture.store.contents == before)
        #expect(fixture.credentials.deleted.isEmpty)
    }

    @Test(arguments: ["host", "port", "authentication"])
    func endpointEditClearsPinAndRejectsOldChallenge(_ field: String) async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        var connection = try await fixture.seed()
        connection.certificateSHA256 = String(repeating: "a", count: 64)
        _ = try await fixture.repository.save(connection)
        let app = await fixture.model()
        await app.load()
        let previous = try #require(try fixture.repository.load().first)
        var edited = previous
        switch field {
        case "host": edited.host = "other.example"
        case "port": edited.port = 3390
        default: edited.authentication = .tls
        }
        try await app.save(edited, password: nil)
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
        await #expect(throws: DesktopError.connectionChanged) {
            try await app.approveCertificate(String(repeating: "b", count: 64), for: previous.id, expectedConnection: previous)
        }
        #expect(try fixture.repository.load().first?.certificateSHA256 == nil)
    }

    @Test func ordinaryEditsCannotOverwriteNewerCertificateDecision() async throws {
        let fixture = try StorageFixture()
        defer { fixture.clean() }
        _ = try await fixture.seed()
        let app = await fixture.model()
        await app.load()
        let previous = try #require(try fixture.repository.load().first)
        let fingerprint = String(repeating: "a", count: 64)
        _ = try await app.approveCertificate(fingerprint, for: previous.id, expectedConnection: previous)
        var stale = previous
        stale.name = "Renamed"
        try await app.save(stale, password: nil)
        #expect(try fixture.repository.load().first?.certificateSHA256 == fingerprint)
        await #expect(throws: DesktopError.connectionChanged) {
            try await app.approveCertificate(String(repeating: "b", count: 64), for: previous.id, expectedConnection: previous)
        }
        #expect(try fixture.repository.load().first?.certificateSHA256 == fingerprint)
    }
}

@Suite("Repository write transactions")
@MainActor
struct RepositoryStorageRegressionTests {
    /// Independent repositories over one store, each write suspending as the real catalog's does.
    @Test func independentWritersPreserveConcurrentAdditions() async throws {
        let store = ControlledServiceStore()
        store.suspendsOnWrite = true
        // Unstructured main-actor tasks rather than a task group: the group's closure trips a
        // region-isolation checker crash in this toolchain ("pattern ... does not understand").
        let writers = (0..<30).map { index in
            Task { @MainActor in
                _ = try await DesktopRepository(store: store)
                    .save(DesktopConnection(name: "Host \(index)", host: "host\(index).example"))
            }
        }
        for writer in writers { try await writer.value }
        #expect(try DesktopRepository(store: store).load().count == 30)
    }

    @Test func staleCompareAndSwapDoesNotOverwriteCommittedChanges() async throws {
        let store = ControlledServiceStore()
        let a = DesktopRepository(store: store), b = DesktopRepository(store: store)
        let initial = DesktopConnection(name: "Host", host: "host.example")
        _ = try await a.save(initial, replacing: nil)
        var newer = initial
        newer.name = "Committed name"
        _ = try await b.save(newer, replacing: initial)
        var stale = initial
        stale.host = "stale.example"
        await #expect(throws: DesktopError.connectionChanged) { try await a.save(stale, replacing: initial) }
        #expect(try a.load() == [newer])
    }
}
