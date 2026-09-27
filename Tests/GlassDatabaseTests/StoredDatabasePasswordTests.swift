import Foundation
import Testing
import GlasSecretStore
@testable import GlassDatabase

/// Nothing stored means no password, on the first connect as on every reconnect (2026-09-22:
/// MySQL on bravo through the tunnel, root with no password, refused with a Keychain error).
@Suite("The password a saved service connects with")
@MainActor
struct StoredDatabasePasswordTests {
    @Test("A service with nothing stored connects with an empty password")
    func nothingStoredIsEmpty() throws {
        let config = DatabaseConnectionConfig(name: "MySQL on bravo", username: "root", usesHostTunnel: true)
        let password = try DatabaseSessionManager.storedDatabasePassword(for: config) { _ in
            throw SecretStoreError.notFound
        }
        #expect(password == "")
    }

    @Test("A stored password is the stored password; a Keychain that cannot be read is reported")
    func storedAndUnreadable() throws {
        let config = DatabaseConnectionConfig(name: "MySQL on alpha", username: "michael")
        #expect(try DatabaseSessionManager.storedDatabasePassword(for: config) { _ in "secret" } == "secret")
        struct Locked: Error {}
        #expect(throws: Locked.self) {
            try DatabaseSessionManager.storedDatabasePassword(for: config) { _ in throw Locked() }
        }
    }

    @Test("SQLite asks the Keychain for nothing")
    func sqliteAsksNothing() throws {
        let config = DatabaseConnectionConfig(name: "notes", engine: .sqlite)
        let password = try DatabaseSessionManager.storedDatabasePassword(for: config) { _ in
            Issue.record("SQLite has no credential to look up"); return "x"
        }
        #expect(password == "")
    }
}
