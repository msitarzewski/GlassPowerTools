//
//  DatabaseServiceDraft.swift
//  Glass Power Tools — GlassDatabase
//
//  The database's side of the shell's one-and-done setup sheet. Holds everything needed to
//  create or update one database service, and nothing the host owns: no address, ever — the
//  shell passes it in at commit — and no SSH configuration at all (D7).
//
//  Shaped after `Sources/GlassTerminal/ServerFormViews.swift:120`, the worked example: the same
//  touched-field/attempted-save reveal, the same `focusRequest` handoff to the field views, and
//  the same rule that a service is created complete, configuration and credential together.
//

import SwiftUI
import UniformTypeIdentifiers
import GlassShell
import GlassConnectionKit
import GlasSecretStore
import os

@MainActor @Observable
final class DatabaseServiceDraft: GlassServiceDraft {
    enum Field: String, Hashable, Sendable {
        case name, engine, databaseFile, database, username, password, port, rowPageSize
        case tlsCertificate
    }

    /// The order issues are reported and focus is moved in.
    static let orderedFields: [Field] = [.name, .engine, .databaseFile, .database, .username,
                                         .password, .port, .rowPageSize, .tlsCertificate]

    let kind: HostServiceKind = .database

    /// The saved connection being edited; nil for a new one.
    let editing: DatabaseConnectionConfig?
    private let connectionManager: ConnectionManager
    /// Whether this host can lend a forward, so the tunnel row can say so rather than leaving
    /// the user to discover it at connect time. Nil means not known — a service being added
    /// through the Add Host sheet has no host to ask yet, and a guess would be worse than
    /// silence, so the row simply does not warn.
    let hostCanForwardPorts: Bool?

    /// D14: settles this machine's SSH host-key trust, prompting once, so that a service set up
    /// to tunnel simply connects later. Supplied by the capability when there is a committed
    /// host to ask about.
    let resolveHostTrust: (@MainActor @Sendable () async -> GlassHostTrustOutcome)?
    /// What the last trust resolution said, for the tunnel row to report. Nil until asked.
    var hostTrustOutcome: GlassHostTrustOutcome?
    var isResolvingHostTrust = false

    // MARK: Required

    var engine: DatabaseEngineType
    var database: String
    var username: String
    var password = ""

    // MARK: Advanced

    /// Optional: the shell derives a default from the host when it is left blank.
    var name: String
    var port: String
    var useTLS: Bool
    /// How the certificate is checked once TLS is on (D13). Only ever changed by the user.
    var tlsVerification: DatabaseTLSVerification
    /// The imported trust root, staged in the draft until commit like every other field. Held as
    /// bytes rather than a file path: there is no managed copy to clean up if the sheet is
    /// abandoned, unlike the SQLite import below.
    var tlsCertificate: Data?
    /// What the imported file turned out to contain — count, fingerprint, validity — for the row
    /// to show. Nil when no certificate is staged or it has not been parsed yet.
    var tlsCertificateSummary: String?
    /// The chosen file's name, so the row can say which file this came from.
    var tlsCertificateFileName: String?
    /// Kept apart from `importError`, which belongs to the SQLite file: two importers reporting
    /// through one slot would show a SQLite failure under the certificate row.
    var certificateImportError: String?
    var usesHostTunnel: Bool
    var isReadOnly: Bool
    /// Blank means "follow the app's result-row setting".
    var rowPageSize: String
    var colorTag: ConnectionColorTag
    var credentialPolicy: CredentialStoragePolicy

    /// SQLite only: the managed copy's path, staged by the importer until commit.
    var sqlitePath: String
    private var stagedSQLiteURL: URL?

    // MARK: Reveal state

    var attemptedSave = false
    var touchedFields: Set<Field> = []
    /// Set by `focusFirstIssue`; the field views move focus and clear it.
    var focusRequest: Field?
    var importError: String?
    private var didLoadStoredPassword = false

    init(editing: DatabaseConnectionConfig? = nil,
         connectionManager: ConnectionManager,
         hostCanForwardPorts: Bool? = nil,
         resolveHostTrust: (@MainActor @Sendable () async -> GlassHostTrustOutcome)? = nil) {
        self.editing = editing
        self.connectionManager = connectionManager
        self.hostCanForwardPorts = hostCanForwardPorts
        self.resolveHostTrust = resolveHostTrust
        engine = editing?.engine ?? .mysql
        database = editing?.defaultDatabase ?? ""
        username = editing?.username ?? DatabaseEngineType.mysql.defaultUsername
        name = editing?.name ?? ""
        port = editing.map { String($0.port) } ?? String(DatabaseEngineType.mysql.defaultPort)
        useTLS = editing?.useTLS ?? false
        tlsVerification = editing?.tlsVerification ?? .systemTrust
        tlsCertificate = editing?.tlsCertificate
        usesHostTunnel = editing?.usesHostTunnel ?? false
        isReadOnly = editing?.isReadOnly ?? false
        rowPageSize = editing?.rowPageSize.map(String.init) ?? ""
        colorTag = editing?.colorTag ?? .none
        // Defensive clamp mirroring the decoder: database passwords are never shared.
        let storedPolicy = editing?.databaseCredentialPolicy ?? .appOnly
        credentialPolicy = storedPolicy == .sharedWithGlas ? .appOnly : storedPolicy
        sqlitePath = editing?.engine == .sqlite ? (editing?.host ?? "") : ""
        if let editing { username = editing.username }
        // Re-parsed rather than trusted: a certificate saved a year ago may have expired since,
        // and the row must say so while the sheet is open rather than at the next connection.
        describeStagedCertificate()
        loadStoredPasswordIfNeeded()
    }

    var isEditing: Bool { editing != nil }

    // MARK: - Engine changes

    /// Changing the engine resets what the previous engine's defaults filled in, the way
    /// glassdb's form did (`../glassdb/glassdb/ConnectionFormView.swift:416-427`) — minus the
    /// tunnel fields, which no longer exist.
    func engineDidChange(to newEngine: DatabaseEngineType) {
        port = String(newEngine.defaultPort)
        username = newEngine.defaultUsername
        database = ""
        useTLS = false
        // The trust root belongs to one server's certificate authority, so it does not survive a
        // change of engine any more than the port or the username does.
        tlsVerification = .systemTrust
        clearCertificate()
        usesHostTunnel = false
        if newEngine != .sqlite { discardStagedSQLiteFile() }
    }

    // MARK: - Host-key trust (D14)

    /// Called when the tunnel switch goes on. Settles the machine's fingerprint now rather than
    /// at first connect, and **never blocks Save**: `.declined` and `.unavailable` are both
    /// reported in the row and both leave the service perfectly saveable.
    ///
    /// `.unavailable` is the honest answer for the one-and-done case the sheet exists for — a
    /// host, its Terminal and its Database created in a single save have no committed SSH
    /// service to challenge yet, so trust is settled at first connect instead.
    func resolveHostTrustIfPossible() async {
        guard let resolveHostTrust, !isResolvingHostTrust else {
            if resolveHostTrust == nil { hostTrustOutcome = .unavailable }
            return
        }
        isResolvingHostTrust = true
        defer { isResolvingHostTrust = false }
        hostTrustOutcome = await resolveHostTrust()
    }

    // MARK: - Validation

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// What blocks a save. `address` is the host's; a database service never has its own, so it
    /// is only checked for the engines that speak over a network.
    func issues(address: String) -> [Field: String] {
        var issues: [Field: String] = [:]

        if engine == .sqlite {
            let path = Self.normalized(sqlitePath)
            if path.isEmpty {
                issues[.databaseFile] = "Choose a SQLite database file."
            } else if !FileManager.default.fileExists(atPath: path) {
                issues[.databaseFile] = "The imported SQLite file is no longer available."
            }
            // SQLite is a local file: no address, no port, no credentials, no tunnel, no TLS.
            appendRowPageSizeIssue(&issues)
            return issues
        }

        if Self.normalized(address).isEmpty {
            // The shell normally catches this first; a draft still refuses to commit without it
            // rather than writing a record that points nowhere. (Until 2026-09-12 an empty
            // Database field wrote over this message, so a missing address read as a missing
            // database. The database is optional now, so this is the only user of the key.)
            issues[.database] = "This machine needs an address before a database service can be added."
        }
        if Self.normalized(username).isEmpty {
            issues[.username] = "Enter the database username."
        }
        if password.isEmpty, !isEditing {
            issues[.password] = "Enter the database password."
        }
        if Int(port).map({ (1...65_535).contains($0) }) != true {
            issues[.port] = "Enter a port from 1 through 65535."
        }
        // A mode that verifies against a supplied certificate and has none cannot connect at
        // all. Refusing the save is the only honest option: the alternative is a service that
        // looks configured and fails at every connection, or one quietly moved to a different
        // way of verifying the server than the user asked for.
        if engine.supportsTLS, useTLS, tlsVerification.requiresCertificate, tlsCertificate == nil {
            issues[.tlsCertificate] = "Choose the certificate this connection should verify against."
        }
        appendRowPageSizeIssue(&issues)
        return issues
    }

    private func appendRowPageSizeIssue(_ issues: inout [Field: String]) {
        let trimmed = Self.normalized(rowPageSize)
        guard !trimmed.isEmpty else { return }
        if Int(trimmed).map({ (1...10_000).contains($0) }) != true {
            issues[.rowPageSize] = "Enter a page size from 1 through 10000, or leave it blank to use the app's setting."
        }
    }

    /// The message a view shows for a field: only once it was touched or a save was tried.
    func message(for field: Field, in issues: [Field: String]) -> String? {
        guard attemptedSave || touchedFields.contains(field) else { return nil }
        return issues[field]
    }

    func markTouched(_ field: Field) { touchedFields.insert(field) }

    func revealIssuesAndFocus(_ issues: [Field: String]) {
        attemptedSave = true
        touchedFields.formUnion(issues.keys)
        guard let first = Self.orderedFields.first(where: { issues[$0] != nil }) else { return }
        switch first {
        case .name, .database, .username, .password, .port, .rowPageSize: focusRequest = first
        // Not text fields: revealing the message is all that can be done.
        case .engine, .databaseFile, .tlsCertificate: focusRequest = nil
        }
    }

    // MARK: - GlassServiceDraft

    func serviceDisplayName(hostName: String) -> String {
        let trimmed = Self.normalized(name)
        if !trimmed.isEmpty { return trimmed }
        if engine == .sqlite, !sqlitePath.isEmpty {
            return URL(fileURLWithPath: sqlitePath).deletingPathExtension().lastPathComponent
        }
        let db = Self.normalized(database)
        return db.isEmpty ? "\(engine.displayName) on \(hostName)" : "\(db) on \(hostName)"
    }

    func requiredFields() -> AnyView { AnyView(DatabaseRequiredFields(draft: self)) }

    func advancedFields() -> AnyView { AnyView(DatabaseAdvancedFields(draft: self)) }

    func validate(address: String) -> [GlassSetupIssue] {
        let issues = self.issues(address: address)
        return Self.orderedFields.compactMap { field in
            issues[field].map { GlassSetupIssue(field: field.rawValue, message: $0) }
        }
    }

    func focusFirstIssue(_ issues: [GlassSetupIssue]) {
        var byField: [Field: String] = [:]
        for issue in issues { if let field = Field(rawValue: issue.field) { byField[field] = issue.message } }
        revealIssuesAndFocus(byField)
    }

    /// Writes the connection record and its password under the shell's endpoint id, which is
    /// the link. A service is created complete: both, or neither.
    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        let issues = self.issues(address: address)
        guard issues.isEmpty else {
            revealIssuesAndFocus(issues)
            throw DatabaseServiceDraftError.invalid(issues.values.sorted().joined(separator: " "))
        }

        let config = configuration(id: endpointID.rawValue, address: address,
                                   name: serviceDisplayName(hostName: host.displayName))

        // The credential goes first: a record the user can see but not connect with is worse
        // than no record, and a failed credential write here leaves nothing behind.
        if config.engine.supportsCredentials, !password.isEmpty {
            _ = try KeychainManager.saveCredentials(databasePassword: password, for: config,
                                                    replacing: editing)
        }
        do {
            if isEditing {
                try connectionManager.update(config)
            } else {
                try connectionManager.add(config)
            }
        } catch {
            // The record did not persist, so the credential it was written for has nothing to
            // belong to. Only remove it for a *new* service: an edit's previous password is
            // still the saved record's.
            if !isEditing, config.engine.supportsCredentials {
                try? KeychainManager.deletePassword(for: config)
            }
            throw error
        }
        stagedSQLiteURL = nil
    }

    func rollback(endpointID: EndpointID) async {
        guard let config = connectionManager.connection(for: endpointID.rawValue) else { return }
        do {
            _ = try KeychainManager.deleteCredentials(for: config)
            try connectionManager.delete(config)
        } catch {
            Logger.connections.error(
                "Rollback of \(endpointID.rawValue.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - The record this draft would write

    /// Pure, so the draft → configuration → draft round trip is testable without a Keychain.
    func configuration(id: UUID, address: String, name: String) -> DatabaseConnectionConfig {
        let isFile = engine == .sqlite
        return DatabaseConnectionConfig(
            id: id,
            name: name,
            engine: engine,
            // The host owns the address; SQLite's "host" is its managed file path instead.
            host: isFile ? Self.normalized(sqlitePath) : Self.normalized(address),
            port: isFile ? 0 : (Int(port) ?? engine.defaultPort),
            username: isFile ? "" : Self.normalized(username),
            defaultDatabase: isFile ? nil : Self.normalized(database).nilWhenEmpty,
            usesHostTunnel: engine.supportsNetworkTransport && usesHostTunnel,
            isReadOnly: isReadOnly,
            rowPageSize: Int(Self.normalized(rowPageSize)).map(DatabaseConnectionConfig.clampedRowPageSize),
            databaseCredentialPolicy: credentialPolicy,
            useTLS: engine.supportsTLS && useTLS,
            tlsVerification: tlsVerification,
            // Written only when it is actually used, so turning TLS off or moving back to system
            // trust does not leave a trust root in the record that nothing verifies against.
            tlsCertificate: (engine.supportsTLS && useTLS && tlsVerification.requiresCertificate)
                ? tlsCertificate
                : nil,
            isFavorite: editing?.isFavorite ?? false,
            colorTag: colorTag,
            dateAdded: editing?.dateAdded ?? Date(),
            lastConnected: editing?.lastConnected
        )
    }

    // MARK: - Certificate import (D13)

    /// Reads the chosen certificate, parses it, and stages it on the draft. A file that is not a
    /// certificate is rejected here, with the reason, rather than being saved and failing at the
    /// next connection.
    func importCertificateFile(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let (bytes, inspection) = try DatabaseCertificateImport.read(from: url)
            tlsCertificate = bytes
            tlsCertificateFileName = url.lastPathComponent
            tlsCertificateSummary = DatabaseCertificateImport.summary(of: inspection)
            certificateImportError = nil
            markTouched(.tlsCertificate)
        } catch {
            // The previously staged certificate is left alone: a failed attempt to replace one
            // must not silently remove the one that was working.
            certificateImportError = error.localizedDescription
        }
    }

    func clearCertificate() {
        tlsCertificate = nil
        tlsCertificateFileName = nil
        tlsCertificateSummary = nil
        certificateImportError = nil
    }

    /// Parses whatever is staged and refreshes the summary. Called when the draft is created for
    /// an existing service, where the bytes came from the record rather than from a file.
    private func describeStagedCertificate() {
        guard let tlsCertificate else { return }
        do {
            tlsCertificateSummary = DatabaseCertificateImport.summary(
                of: try DatabaseCertificateImport.inspect(tlsCertificate)
            )
        } catch {
            // Saved bytes that no longer parse are reported, not discarded: the user chose this
            // file, and dropping it silently would turn a broken trust root into an absent one.
            tlsCertificateSummary = nil
            certificateImportError = error.localizedDescription
        }
    }

    // MARK: - SQLite import

    static var sqliteContentTypes: [UTType] {
        var types: [UTType] = [.data]
        for filenameExtension in ["sqlite", "sqlite3", "db"] {
            if let type = UTType(filenameExtension: filenameExtension) {
                types.insert(type, at: 0)
            }
        }
        return types
    }

    /// Copies the chosen file into managed storage, as glassdb's form did
    /// (`../glassdb/glassdb/ConnectionFormView.swift:18-104`). The original is never opened
    /// directly and never modified.
    func importSQLiteFile(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let importedURL = try SQLiteFileImporter.importFile(at: url)
            discardStagedSQLiteFile()
            stagedSQLiteURL = importedURL
            sqlitePath = importedURL.path
            if Self.normalized(name).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
            importError = nil
            markTouched(.databaseFile)
        } catch {
            importError = "The SQLite file could not be imported. \(error.localizedDescription)"
        }
    }

    /// Removes a staged copy the user never committed, so an abandoned sheet leaves no file.
    func discardStagedSQLiteFile() {
        guard let stagedSQLiteURL else { return }
        do {
            try FileManager.default.removeItem(at: stagedSQLiteURL)
        } catch {
            Logger.connections.error(
                "Failed to remove abandoned SQLite import: \(error.localizedDescription, privacy: .public)"
            )
        }
        self.stagedSQLiteURL = nil
    }

    // MARK: - Stored password

    /// In edit mode the field starts with the saved password, so leaving it alone keeps it.
    /// A password that cannot be read is reported rather than silently blanked.
    func loadStoredPasswordIfNeeded() {
        guard !didLoadStoredPassword, let config = editing, config.engine.supportsCredentials else { return }
        didLoadStoredPassword = true
        do {
            password = try KeychainManager.retrievePassword(for: config)
        } catch SecretStoreError.notFound {
            password = ""
        } catch {
            importError = "The saved database password could not be read: \(error.localizedDescription)"
        }
    }
}

enum DatabaseServiceDraftError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
