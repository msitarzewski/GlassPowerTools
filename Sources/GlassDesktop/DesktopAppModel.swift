import Foundation
import Darwin
import Observation
import GlassConnectionKit
import GlassHostCatalog
import GlasSecretStore

/// Synchronous credential boundary. Production delegates directly to the family
/// store; tests can exercise transaction failures without creating secret items.
@MainActor
public struct DesktopCredentialAccess {
    public var retrieve: (UUID, SecretStoreConfiguration, String?) throws -> RDPCredential
    public var save: (RDPCredential, UUID, SecretStoreConfiguration) throws -> Void
    public var delete: (UUID, SecretStoreConfiguration) throws -> Void
    public var availability: (UUID, SecretStoreConfiguration) -> RDPCredentialAvailability
    public var migrate: (UUID, SecretStoreConfiguration, SecretStoreConfiguration) throws -> Void

    public init(retrieve: @escaping (UUID, SecretStoreConfiguration, String?) throws -> RDPCredential,
                save: @escaping (RDPCredential, UUID, SecretStoreConfiguration) throws -> Void,
                delete: @escaping (UUID, SecretStoreConfiguration) throws -> Void,
                availability: @escaping (UUID, SecretStoreConfiguration) -> RDPCredentialAvailability,
                migrate: @escaping (UUID, SecretStoreConfiguration, SecretStoreConfiguration) throws -> Void) {
        self.retrieve = retrieve; self.save = save; self.delete = delete
        self.availability = availability; self.migrate = migrate
    }

    public static var live: Self {
        Self(retrieve: { try RDPCredentialStore.retrieve(for: $0, config: $1, authenticationPrompt: $2) },
             save: { try RDPCredentialStore.save($0, for: $1, config: $2) },
             delete: { try RDPCredentialStore.delete(for: $0, config: $1) },
             availability: { RDPCredentialStore.availability(for: $0, config: $1) },
             migrate: { _ = try RDPCredentialStore.prepareMobilityMigration(for: $0, from: $1, to: $2) })
    }

    /// A store that lives in memory for the duration of a test. Exists so the desktop's own tests
    /// can exercise the real save path without writing into the user's Keychain — the same
    /// isolation the UI tests needed after they filled the real saved-server list.
    public static func inMemory() -> Self {
        final class Box: @unchecked Sendable {
            var values: [UUID: RDPCredential] = [:]
        }
        let box = Box()
        return Self(
            retrieve: { id, _, _ in
                guard let credential = box.values[id] else { throw SecretStoreError.notFound }
                return credential
            },
            save: { credential, id, _ in box.values[id] = credential },
            delete: { id, _ in box.values.removeValue(forKey: id) },
            availability: { id, _ in box.values[id] == nil ? .missing : .available },
            migrate: { _, _, _ in }
        )
    }
}

@MainActor @Observable
public final class DesktopAppModel {
    public private(set) var connections: [DesktopConnection] = []
    public private(set) var isLoaded = false
    public var errorMessage: String?
    public let notices: DesktopNotices
    public let storageDirectory: URL
    private let repository: DesktopRepository
    private let accessGroup: String?
    private let credentials: DesktopCredentialAccess
    private var mutationLocked = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(storageDirectory: URL? = nil, accessGroup: String? = nil,
                repository: DesktopRepository? = nil,
                credentialAccess: DesktopCredentialAccess? = nil, notices: DesktopNotices = .shared) {
        self.notices = notices
        let directory = storageDirectory ?? URL.applicationSupportDirectory
            .appendingPathComponent("GlassPowerTools/Desktop", isDirectory: true)
        self.storageDirectory = directory
        self.repository = repository ?? DesktopRepository(fileURL: directory.appendingPathComponent("connections.json"))
        self.accessGroup = accessGroup
        self.credentials = credentialAccess ?? .live
    }

    public func load() async {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            connections = try await repository.load()
            isLoaded = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func configuration(for connection: DesktopConnection) -> SecretStoreConfiguration {
        SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup: accessGroup,
                                 useDataProtectionKeychain: true, mobilityPolicy: connection.mobility)
    }

    public func credential(for connection: DesktopConnection) throws -> RDPCredential {
        let value = try connection.validated()
        let credential = try credentials.retrieve(value.credentialID.rawValue, configuration(for: value), "Connect to \(value.name)")
        guard credential.username == value.credentialAccountName, (credential.domain ?? "") == value.domain else {
            throw AppStorageError.credentialAccountMismatch
        }
        return credential
    }

    public func credentialAvailability(for connection: DesktopConnection) -> RDPCredentialAvailability {
        credentials.availability(connection.credentialID.rawValue, configuration(for: connection))
    }

    public func save(_ connection: DesktopConnection, password: String?) async throws {
        await acquireMutation()
        defer { releaseMutation() }
        try Task.checkCancellation()
        var value = try connection.validated()
        let current = try await repository.load()
        let previous = current.first { $0.id == value.id }
        if let previous {
            value.createdAt = previous.createdAt
            value.lastConnectedAt = previous.lastConnectedAt
            // A caller cannot rebind an existing profile to an arbitrary secret.
            value.credentialID = previous.credentialID
            if previous.host != value.host || previous.port != value.port || previous.authentication != value.authentication {
                value.certificateSHA256 = nil
            } else {
                // General edits cannot install a pin or restore an older one.
                value.certificateSHA256 = previous.certificateSHA256
            }
            if password == nil && (previous.username != value.username || previous.domain != value.domain) {
                throw AppStorageError.passwordRequiredForAccountChange
            }
        }
        // The shell owns host identity now, so nothing is derived from a catalog here. An edit
        // keeps whatever host the record already belongs to; a new record is placed by the
        // capability, which is the only thing that knows which host the shell is adding it to.
        value.hostID = value.hostID ?? previous?.hostID
        var newCredentialID: UUID?
        if let password {
            value.credentialID = CredentialID()
            let credential = RDPCredential(username: value.credentialAccountName, domain: value.domain, password: password)
            do { try credentials.save(credential, value.credentialID.rawValue, configuration(for: value)) }
            catch SecretStoreError.unableToSave {
                throw AppStorageError.recovery("The password could not be saved in Keychain, so these desktop changes were not saved. Unlock the device and retry. If it still fails, check that this build has access to its configured Keychain group.")
            }
            newCredentialID = value.credentialID.rawValue
        } else if let previous, previous.mobility != value.mobility {
            // No availability preflight: locked/missing/failed migration must
            // abort the metadata update instead of silently losing access.
            try credentials.migrate(previous.credentialID.rawValue, configuration(for: previous), configuration(for: value))
        }
        do {
            connections = try await repository.save(value, replacing: previous)
        } catch {
            if let newCredentialID {
                do { try credentials.delete(newCredentialID, configuration(for: value)) }
                catch { throw AppStorageError.recovery("The connection could not be saved and its new credential could not be cleaned up. The previous connection and credential were preserved.") }
            }
            throw error
        }
    }

    public func toggleFavorite(_ id: EndpointID) async {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            guard var value = try await repository.load().first(where: { $0.id == id }) else { throw DesktopError.missingConnection }
            let previous = value
            value.isFavorite.toggle()
            connections = try await repository.save(value, replacing: previous)
        } catch { errorMessage = error.localizedDescription }
    }

    public func delete(_ connection: DesktopConnection) async {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            // The shell removes the host record and cascades to this capability (D25); this
            // deletes only what the capability itself stored.
            connections = try await repository.delete(connection.id)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func recordConnected(_ id: EndpointID, expectedConnection: DesktopConnection? = nil, at date: Date = Date()) async {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            try Task.checkCancellation()
            connections = try await repository.recordConnection(id, at: date, expectedConnection: expectedConnection)
        } catch is CancellationError {
            // A canceled attempt cannot publish delayed success history.
        } catch DesktopError.connectionChanged where expectedConnection != nil {
            // The saved endpoint changed while this session's history awaited I/O.
        } catch { errorMessage = error.localizedDescription }
    }

    public func approveCertificate(_ fingerprint: String, for id: EndpointID,
                                   expectedConnection: DesktopConnection) async throws -> DesktopConnection {
        await acquireMutation()
        defer { releaseMutation() }
        guard var value = try await repository.load().first(where: { $0.id == id }) else { throw DesktopError.missingConnection }
        let expected = try expectedConnection.validated()
        guard expected.id == id, value.host == expected.host, value.port == expected.port,
              value.authentication == expected.authentication,
              value.certificateSHA256 == expected.certificateSHA256 else { throw DesktopError.connectionChanged }
        let previous = value
        value.certificateSHA256 = fingerprint
        value = try value.validated()
        connections = try await repository.save(value, replacing: previous)
        return value
    }

    // The pairing surface, the dual local/shared catalog, its availability probe and the
    // publication journal all lived here. They existed so three separate processes could agree
    // on one library; there is one process now, and the shell owns the catalog.


    private func acquireMutation() async {
        if mutationLocked {
            await withCheckedContinuation { mutationWaiters.append($0) }
        } else { mutationLocked = true }
    }

    private func releaseMutation() {
        if mutationWaiters.isEmpty { mutationLocked = false }
        else { mutationWaiters.removeFirst().resume() }
    }
}

public enum AppStorageError: Error, LocalizedError {
    case recovery(String)
    case passwordRequiredForAccountChange
    case credentialAccountMismatch
    public var errorDescription: String? {
        switch self {
        case .recovery(let message): message
        case .passwordRequiredForAccountChange: "Enter the password to save an account or domain change. The previous credential is still preserved."
        case .credentialAccountMismatch: "This credential belongs to a different account. Save the account and password together before connecting."
        }
    }
}
