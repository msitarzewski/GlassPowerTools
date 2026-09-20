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

/// Import material for the TLS rows: a self-signed CA that signed nothing, whose private key was
/// discarded. A certificate is public in any case.
private let draftCertificatePEM = """
-----BEGIN CERTIFICATE-----
MIIDVzCCAj+gAwIBAgIUV3wDIwbSRLq92vNQjAI7pW2jApswDQYJKoZIhvcNAQEL
BQAwOzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEg
cmVhbCBhdXRob3JpdHkpMB4XDTI2MDkxMjE5MzE1NVoXDTQ2MDkwNzE5MzE1NVow
OzE5MDcGA1UEAwwwR2xhc3MgUG93ZXIgVG9vbHMgVGVzdCBDQSAobm90IGEgcmVh
bCBhdXRob3JpdHkpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqAqJ
8fpDJY5Rn2EHZlqyHmK/7m3dbM3jtBEVq06n/zkvzMa44+wF4qsGvl94vHwO9qV6
kJdNUIH4+QQtsfpoln6ULCJ0KGeIpG8ALQp6vIEOAmLy2HRNkZG/AEDYZ2hxaoBo
GMnREfEeMoUotPpE+tgDWE28/K3kta9wIEQCZAITL6FCupI1fogvBZhEJLWF40p3
KbuWQENBS4X1B+ZknIFAem7t6SFHKCQfBroObfhJfBYSVb2c1KfUkbiqlwikvKK8
2ERqmhaSYT283kaRYCMN3oBroahgkMIVEYG8dyuXXFMzGVuiT7ioWtwCcHRPC0eq
abPnNA/GnX/m9Q4l3QIDAQABo1MwUTAdBgNVHQ4EFgQUJfKynwiJ4zo0PUrtXF4P
DCC1E4EwHwYDVR0jBBgwFoAUJfKynwiJ4zo0PUrtXF4PDCC1E4EwDwYDVR0TAQH/
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAXfdyHs0O/RcjXNf7HUFbgKEm1fQ2
EZ2iNjJsm8lPZl1Q+V/WSP3c/oDK/X1JdEO+nWP2JAAAfqEXn/jd9pVqIaqTRNhn
Mbn8jJNL8yhNYtTBuuzaEKqRl5uAWmuKaDiK59TM3FPtpWAuivzd9JYTUxXyit0m
8MTDkQFE/aCtjJyUFQMuw3i1N54vwfjmUY013EW0SUpd66pztIqeKffXkM+ztNkw
CAYTtMs2R+RUqIzOL/kK6V6Gltv5esnXLyhD7huTs/7TrgCyJAv2UnjL5RsQw4vl
DshIAueLo5G03I6meg5BZwifBCfJTQzcITj7WsfYg6s35c8puZ8uFpDIPw==
-----END CERTIFICATE-----
"""

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

        // **A blank password saves.** `auth_socket`, `trust`, `peer`, a tunnelled local
        // instance, a user created without one — all of them connect with nothing to send, and
        // refusing the service made this app unable to reach servers that work everywhere else
        // (reported 2026-09-20). Whether the password is right is the server's to say, at
        // connect time, where it can say so accurately.
        draft.password = ""
        #expect(draft.issues(address: "db.example.test")[.password] == nil)
        #expect(draft.validate(address: "db.example.test").isEmpty,
                "a service with no password is a service that saves")
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

    // MARK: TLS verification (D13 / R7)

    @Test("A pinned mode with no certificate refuses to save")
    func pinnedModeNeedsACertificate() {
        let draft = networkDraft()
        draft.useTLS = true

        draft.tlsVerification = .systemTrust
        #expect(draft.issues(address: "db.example.test")[.tlsCertificate] == nil)

        for mode in [DatabaseTLSVerification.pinnedCertificate, .pinnedCertificateAuthorityOnly] {
            draft.tlsVerification = mode
            #expect(draft.issues(address: "db.example.test")[.tlsCertificate] != nil,
                    "\(mode) verifies against a certificate and there is none")
        }

        draft.tlsCertificate = Data(draftCertificatePEM.utf8)
        #expect(draft.issues(address: "db.example.test")[.tlsCertificate] == nil)
    }

    @Test("A certificate is only demanded where it is actually used")
    func certificateIsNotDemandedWhenTLSIsOff() {
        let draft = networkDraft()
        draft.tlsVerification = .pinnedCertificateAuthorityOnly
        draft.useTLS = false
        // The mode is remembered rather than reset, but it verifies nothing while TLS is off, so
        // it must not block the save either.
        #expect(draft.issues(address: "db.example.test")[.tlsCertificate] == nil)
    }

    @Test("The certificate reaches the record only when the mode uses it")
    func certificateReachesTheRecordOnlyWhenUsed() {
        let draft = networkDraft()
        draft.useTLS = true
        draft.tlsVerification = .pinnedCertificateAuthorityOnly
        draft.tlsCertificate = Data(draftCertificatePEM.utf8)

        let pinned = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(pinned.tlsVerification == .pinnedCertificateAuthorityOnly)
        #expect(pinned.tlsCertificate != nil)

        // Moving back to system trust must not leave a trust root in the record that nothing
        // verifies against — it would read as a pinned connection to anyone inspecting it.
        draft.tlsVerification = .systemTrust
        let system = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(system.tlsCertificate == nil)

        draft.tlsVerification = .pinnedCertificate
        draft.useTLS = false
        let plaintext = draft.configuration(id: UUID(), address: "db.example.test", name: "Fixture")
        #expect(plaintext.tlsCertificate == nil)
    }

    @Test("Editing an existing service reloads its certificate and describes it")
    func editingReloadsTheCertificate() {
        let pem = Data(draftCertificatePEM.utf8)
        let saved = DatabaseConnectionConfig(
            name: "Fixture", engine: .mysql, host: "db.example.test", port: 3306,
            username: "reader", useTLS: true,
            tlsVerification: .pinnedCertificateAuthorityOnly, tlsCertificate: pem
        )
        let draft = DatabaseServiceDraft(editing: saved, connectionManager: isolatedManager())
        #expect(draft.tlsVerification == .pinnedCertificateAuthorityOnly)
        #expect(draft.tlsCertificate == pem)
        // Re-parsed on open, so an expiry that has happened since is visible in the sheet.
        #expect(draft.tlsCertificateSummary?.contains("SHA-256") == true)
        #expect(draft.certificateImportError == nil)
    }

    @Test("Saved bytes that no longer parse are reported, not discarded")
    func unparseableStoredCertificateIsReported() {
        let saved = DatabaseConnectionConfig(
            name: "Fixture", engine: .mysql, useTLS: true,
            tlsVerification: .pinnedCertificate, tlsCertificate: Data("not a certificate".utf8)
        )
        let draft = DatabaseServiceDraft(editing: saved, connectionManager: isolatedManager())
        #expect(draft.certificateImportError != nil)
        #expect(draft.tlsCertificateSummary == nil)
        #expect(draft.tlsCertificate != nil, "the user chose this file; it is reported, not dropped")
    }

    @Test("Changing engine resets the previous engine's defaults, tunnel included")
    func engineChangeResets() {
        let draft = networkDraft()
        draft.usesHostTunnel = true
        draft.useTLS = true
        draft.tlsVerification = .pinnedCertificateAuthorityOnly
        draft.tlsCertificate = Data(draftCertificatePEM.utf8)
        draft.engineDidChange(to: .mysql)
        #expect(draft.port == "3306")
        #expect(draft.username == "root")
        #expect(draft.database.isEmpty)
        #expect(!draft.usesHostTunnel)
        #expect(!draft.useTLS)
        // The trust root belonged to the previous server's authority.
        #expect(draft.tlsVerification == .systemTrust)
        #expect(draft.tlsCertificate == nil)
        #expect(draft.tlsCertificateSummary == nil)
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
