//
//  DatabaseServiceDraftTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  The draft's validation and the record it would write. Nothing here touches the Keychain or
//  UserDefaults: `configuration(id:address:name:)` is pure for exactly this reason.
//

import Foundation
import Testing
import GlassShell
@testable import GlassDatabase

@MainActor
@Suite("Database service draft")
struct DatabaseServiceDraftTests {

    /// A manager with an in-memory store, so a test never touches the user's saved connections.
    private func isolatedManager() -> ConnectionManager {
        nonisolated(unsafe) var storage: Data?
        let store = ConnectionPersistenceStore(
            load: { storage },
            save: { storage = $0 },
            restore: { storage = $0 }
        )
        return ConnectionManager(loadImmediately: false, persistenceStore: store)
    }

    private func networkDraft() -> DatabaseServiceDraft {
        let draft = DatabaseServiceDraft(connectionManager: isolatedManager())
        draft.engine = .postgresql
        draft.database = "gpt_test"
        draft.username = "reader"
        draft.password = "•"
        draft.port = "5432"
        return draft
    }

    @Test("A complete draft validates; the database name is optional, the credentials are not")
    func requiredFields() {
        let draft = networkDraft()
        #expect(draft.validate(address: "db.example.test").isEmpty)

        // Optional: connecting without naming a database opens the server and the browser lists
        // what is there. Only SQLite must name its file.
        draft.database = ""
        #expect(draft.issues(address: "db.example.test")[.database] == nil)
        #expect(draft.validate(address: "db.example.test").isEmpty, "a nameless database still saves")
        draft.database = "gpt_test"

        draft.username = "  "
        #expect(draft.issues(address: "db.example.test")[.username] != nil)
        draft.username = "reader"

        draft.password = ""
        #expect(draft.issues(address: "db.example.test")[.password] != nil)
    }

    @Test("A draft carries no address of its own: the host's is what gets validated")
    func addressComesFromTheHost() {
        let draft = networkDraft()
        #expect(!draft.issues(address: "").isEmpty)
        #expect(draft.issues(address: "db.example.test").isEmpty)

        let config = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(config.host == "db.example.test")
    }

    @Test("The port is bounded, and an out-of-range page size is refused rather than clamped silently")
    func advancedBounds() {
        let draft = networkDraft()
        for bad in ["0", "65536", "-1", "", "abc"] {
            draft.port = bad
            #expect(draft.issues(address: "h")[.port] != nil, "port \(bad) should be refused")
        }
        draft.port = "5432"

        draft.rowPageSize = "0"
        #expect(draft.issues(address: "h")[.rowPageSize] != nil)
        draft.rowPageSize = "10001"
        #expect(draft.issues(address: "h")[.rowPageSize] != nil)
        draft.rowPageSize = ""      // blank means "follow the app's setting"
        #expect(draft.issues(address: "h")[.rowPageSize] == nil)
        draft.rowPageSize = "500"
        #expect(draft.issues(address: "h")[.rowPageSize] == nil)
    }

    @Test("SQLite needs a file and nothing else: no address, no port, no credentials")
    func sqliteNeedsOnlyItsFile() throws {
        let file = URL.temporaryDirectory.appendingPathComponent("gpt-draft-\(UUID().uuidString).sqlite")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let draft = DatabaseServiceDraft(connectionManager: isolatedManager())
        draft.engine = .sqlite
        #expect(draft.issues(address: "")[.databaseFile] != nil)

        draft.sqlitePath = file.path
        // No address, no username, no password — and it validates.
        #expect(draft.validate(address: "").isEmpty)

        let config = draft.configuration(id: UUID(), address: "ignored.example.test", name: "Local")
        #expect(config.host == file.path, "SQLite's host is its managed file path, never the machine's address")
        #expect(config.port == 0)
        #expect(config.username.isEmpty)
        #expect(!config.usesHostTunnel)
    }

    @Test("A SQLite file that has gone missing is reported, not saved over")
    func sqliteMissingFile() {
        let draft = DatabaseServiceDraft(connectionManager: isolatedManager())
        draft.engine = .sqlite
        draft.sqlitePath = "/nonexistent/gpt-\(UUID().uuidString).sqlite"
        #expect(draft.issues(address: "")[.databaseFile] != nil)
    }

    @Test("Changing engine resets the previous engine's defaults, tunnel included")
    func engineChangeResets() {
        let draft = networkDraft()
        draft.usesHostTunnel = true
        draft.useTLS = true
        draft.engineDidChange(to: .mysql)
        #expect(draft.port == "3306")
        #expect(draft.username == "root")
        #expect(draft.database.isEmpty)
        #expect(!draft.usesHostTunnel)
        #expect(!draft.useTLS)
    }

    @Test("The advanced switches reach the record")
    func advancedReachesTheRecord() {
        let draft = networkDraft()
        draft.usesHostTunnel = true
        draft.isReadOnly = true
        draft.useTLS = true
        draft.rowPageSize = "250"
        draft.colorTag = .red

        let config = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(config.usesHostTunnel)
        #expect(config.isReadOnly)
        #expect(config.useTLS)
        #expect(config.rowPageSize == 250)
        #expect(config.colorTag == .red)
        #expect(config.databaseCredentialPolicy == .appOnly, "a database password is never shared")
    }

    @Test("The service name falls back to the database and host rather than making the user type one")
    func derivedDisplayName() {
        let draft = networkDraft()
        #expect(draft.serviceDisplayName(hostName: "carbon") == "gpt_test on carbon")
        draft.name = "  Reporting  "
        #expect(draft.serviceDisplayName(hostName: "carbon") == "Reporting")
    }

    @Test("Editing keeps the saved password when the field is left blank")
    func editingMayLeavePasswordBlank() {
        let existing = DatabaseConnectionConfig(name: "Fixture", engine: .postgresql,
                                                host: "db.example.test", port: 5432,
                                                username: "reader", defaultDatabase: "gpt_test")
        let draft = DatabaseServiceDraft(editing: existing, connectionManager: isolatedManager())
        draft.password = ""
        #expect(draft.issues(address: "db.example.test")[.password] == nil)
        #expect(draft.isEditing)
    }

    @Test("A missing address reads as a missing address, not as a missing database")
    func addressIssueIsNotMaskedByTheDatabaseField() {
        let draft = networkDraft()
        draft.database = ""
        let message = draft.issues(address: "")[.database]
        #expect(message?.contains("address") == true,
                "both used the .database key; the database check used to overwrite this one")
    }

    @Test("Focus moves to the first problem in field order, and only for fields that take focus")
    func focusFirstIssue() {
        let draft = networkDraft()
        draft.username = ""
        draft.password = ""
        draft.focusFirstIssue(draft.validate(address: "h"))
        #expect(draft.attemptedSave)
        #expect(draft.focusRequest == .username, "the first field that actually blocks the save")

        let sqlite = DatabaseServiceDraft(connectionManager: isolatedManager())
        sqlite.engine = .sqlite
        sqlite.focusFirstIssue(sqlite.validate(address: ""))
        // The file row is a button, not a text field: the message is revealed, focus is not moved.
        #expect(sqlite.focusRequest == nil)
        #expect(sqlite.message(for: .databaseFile, in: sqlite.issues(address: "")) != nil)
    }
}

@MainActor
@Suite("Database draft host trust (D14)")
struct DatabaseServiceDraftTrustTests {

    private func isolatedManager() -> ConnectionManager {
        nonisolated(unsafe) var storage: Data?
        return ConnectionManager(loadImmediately: false, persistenceStore: ConnectionPersistenceStore(
            load: { storage }, save: { storage = $0 }, restore: { storage = $0 }))
    }

    private func draft(resolving outcome: GlassHostTrustOutcome?) -> DatabaseServiceDraft {
        var resolver: (@MainActor @Sendable () async -> GlassHostTrustOutcome)?
        if let outcome { resolver = { outcome } }
        let draft = DatabaseServiceDraft(connectionManager: isolatedManager(),
                                         resolveHostTrust: resolver)
        draft.engine = .postgresql
        draft.database = "gpt_test"
        draft.username = "reader"
        draft.password = "•"
        draft.port = "5432"
        return draft
    }

    @Test("Trust is settled at setup when the machine is committed and has a Terminal service")
    func settlesAtSetup() async {
        let draft = draft(resolving: .trusted)
        draft.usesHostTunnel = true
        await draft.resolveHostTrustIfPossible()
        #expect(draft.hostTrustOutcome == .trusted)
    }

    @Test("The create-everything case reports unavailable rather than contriving an answer")
    func combinedCreateIsUnavailable() async {
        // No resolver: the Add Host sheet can create host + terminal + database in one save, so
        // at the moment the tunnel switch flips there is no committed SSH service to challenge.
        let draft = draft(resolving: nil)
        draft.usesHostTunnel = true
        await draft.resolveHostTrustIfPossible()
        #expect(draft.hostTrustOutcome == .unavailable)
    }

    @Test("Declining never blocks Save: the service is still valid and still saveable")
    func decliningDoesNotBlockSave() async {
        let draft = draft(resolving: .declined)
        draft.usesHostTunnel = true
        await draft.resolveHostTrustIfPossible()
        #expect(draft.hostTrustOutcome == .declined)
        #expect(draft.validate(address: "db.example.test").isEmpty, "trust is not a validation gate")

        let config = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(config.usesHostTunnel, "the user's choice to tunnel is still what gets saved")
    }

    @Test("Every outcome leaves the draft saveable — none of the three is a validation error")
    func noOutcomeBlocksSave() async {
        for outcome in [GlassHostTrustOutcome.trusted, .declined, .unavailable] {
            let draft = draft(resolving: outcome)
            draft.usesHostTunnel = true
            await draft.resolveHostTrustIfPossible()
            #expect(draft.validate(address: "db.example.test").isEmpty, "\(outcome) blocked Save")
        }
    }
}
