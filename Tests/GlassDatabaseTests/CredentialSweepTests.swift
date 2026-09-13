//
//  CredentialSweepTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `KeychainManager` is 773 lines, live on every database service, and had **no tests at all**
//  until the 2026-09-13 security review. These cover the three findings that review produced.
//
//  The seam used here is the one that already existed and was never exercised:
//  `store: CredentialMutationStore = .live` on every mutation entry point. A fake records what
//  would have been written and deleted, so the *shape* of a sweep can be asserted without touching
//  the real Keychain — which matters more than usual now that D18 landed, because a test credential
//  written to the real Keychain would **synchronize to the user's own devices**.
//

import Foundation
import Testing
import GlasSecretStore
@testable import GlassDatabase

@Suite("Credential sweep")
struct CredentialSweepTests {
    /// Records deletions instead of performing them.
    /// A Keychain that starts with a secret at every descriptor and honours deletes.
    ///
    /// Both halves matter. Reporting a secret everywhere **is** the scenario — a stranded password
    /// is one sitting at a descriptor nothing sweeps, so a fake that answered nil would make every
    /// sweep look complete. And the delete path *verifies*: after removing a secret it re-reads to
    /// confirm the secret is gone and throws `.verificationFailed` if not. A fake that keeps
    /// answering "stored" fails that check, which is the store being careful rather than a bug.
    private final class RecordingStore: @unchecked Sendable {
        var deleted: [(account: String, service: String)] = []
        var saved: [(account: String, service: String)] = []
        private var removed: Set<String> = []

        private func key(_ account: String, _ service: String) -> String { "\(account)|\(service)" }

        var asMutationStore: KeychainManager.CredentialMutationStore {
            KeychainManager.CredentialMutationStore(
                retrieve: { [self] account, descriptor in
                    removed.contains(key(account, descriptor.service)) ? nil : "stored"
                },
                save: { [self] _, account, descriptor in
                    saved.append((account, descriptor.service))
                    removed.remove(key(account, descriptor.service))
                },
                delete: { [self] account, descriptor in
                    deleted.append((account, descriptor.service))
                    removed.insert(key(account, descriptor.service))
                }
            )
        }
    }

    private func config(engine: DatabaseEngineType = .mysql,
                        policy: CredentialStoragePolicy = .appOnly) -> DatabaseConnectionConfig {
        var connection = DatabaseConnectionConfig(
            name: "fixture", engine: engine, host: "10.0.0.1", port: 3306,
            username: "u", defaultDatabase: "d")
        connection.databaseCredentialPolicy = policy
        return connection
    }

    /// The asymmetry the review found: the SSH password was swept across every policy, the database
    /// password only at the record's current one.
    ///
    /// Two reachable ways that stranded a secret with nothing pointing at it — a password that no
    /// later delete will ever find, because nothing records that it was there:
    ///   • change the engine to SQLite, then delete: `supportsCredentials` is false, so the password
    ///     saved under MySQL was never swept;
    ///   • change the storage policy: the secret lives at the OLD descriptor, and only the new one
    ///     was swept.
    @Test("Deleting a service sweeps the database password at every policy, not just the current one")
    func deleteSweepsEveryDatabaseDescriptor() throws {
        let store = RecordingStore()
        _ = try KeychainManager.deleteCredentials(for: config(), store: store.asMutationStore)

        let services = Set(store.deleted.map(\.service))
        #expect(services.count >= 3,
                "every policy's descriptor is visited, not only the record's current one")
    }

    /// The engine condition is gone: what a record can hold *today* says nothing about what was
    /// written under it before. A service switched to SQLite still has the password it had as MySQL.
    @Test("A SQLite service still sweeps the password it held as a networked engine")
    func sqliteServiceStillSweepsItsOldPassword() throws {
        let store = RecordingStore()
        _ = try KeychainManager.deleteCredentials(for: config(engine: .sqlite),
                                                  store: store.asMutationStore)
        #expect(!store.deleted.isEmpty,
                "a SQLite record cannot hold a password, but it may have held one before")
    }

    /// Both kinds are swept, so neither can be stranded by a policy change.
    @Test("Both the database and the SSH account are swept")
    func bothAccountsAreSwept() throws {
        let store = RecordingStore()
        let connection = config()
        _ = try KeychainManager.deleteCredentials(for: connection, store: store.asMutationStore)

        let accounts = Set(store.deleted.map(\.account))
        #expect(accounts.count >= 2, "the database account and the SSH account are distinct")
    }
}
