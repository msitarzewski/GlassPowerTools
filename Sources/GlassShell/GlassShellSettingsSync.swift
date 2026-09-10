//
//  GlassShellSettingsSync.swift
//  Glass Power Tools — GlassShell
//
//  iCloud key-value settings synchronization: the writer identity, Lamport-revision envelope,
//  deterministic merge, availability and status handling, and the ubiquitous store — moved
//  verbatim from glas.sh's ICloudSettingsSyncService.swift on 2026-09-10 and made generic over
//  the payload so every capability syncs through one shell service. A capability supplies a
//  `GlassSettingsSyncPayload` (its own schema, validation and convergence) and its store key.
//

import Foundation

/// What a capability synchronizes. `converged(with:)` reconciles this device's value with the
/// last accepted one before a push, so a slower writer never drops the other's records.
public protocol GlassSettingsSyncPayload: Codable, Equatable, Sendable {
    func validate() throws
    func converged(with other: Self) -> Self
}

public enum GlassSettingsSyncStatus: String, Equatable, Sendable {
    case disabled
    case syncing
    case synced
    case unavailable
    case quota
    case account
    case error
}

public enum GlassSettingsStoreChangeReason: Equatable, Sendable {
    case server
    case initialSync
    case quota
    case account
    case unknown(Int)
}

public struct GlassSettingsStoreChange: Equatable, Sendable {
    public let reason: GlassSettingsStoreChangeReason
    public let changedKeys: Set<String>

    public init(reason: GlassSettingsStoreChangeReason, changedKeys: Set<String>) {
        self.reason = reason
        self.changedKeys = changedKeys
    }
}

@MainActor
public protocol GlassSettingsKeyValueStore: AnyObject {
    var isAvailable: Bool { get }
    var isAccountAvailable: Bool { get }

    func refreshAccountAvailability() async -> Bool

    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    @discardableResult func synchronize() async -> Bool
    func observeExternalChanges(
        _ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void
    ) -> NSObjectProtocol
    func removeExternalChangeObserver(_ observer: NSObjectProtocol)
}

@MainActor
public extension GlassSettingsKeyValueStore {
    public func refreshAccountAvailability() async -> Bool {
        isAccountAvailable
    }
}

/// Live adapter for Apple's iCloud key-value store. The protocol boundary keeps
/// synchronization tests independent of the signed-in Apple account and app
/// entitlements on the machine running them.
@MainActor
public final class GlassUbiquitousSettingsStore: GlassSettingsKeyValueStore {
    private let notificationCenter: NotificationCenter
    public private(set) var isAccountAvailable = false

    public init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    public var isAvailable: Bool { true }

    public func refreshAccountAvailability() async -> Bool {
        let isAvailable = await Task.detached(priority: .utility) {
            FileManager.default.ubiquityIdentityToken != nil
        }.value
        isAccountAvailable = isAvailable
        return isAvailable
    }

    public func data(forKey key: String) -> Data? {
        NSUbiquitousKeyValueStore.default.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) {
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
    }

    @discardableResult
    public func synchronize() async -> Bool {
        await Task.detached(priority: .utility) {
            NSUbiquitousKeyValueStore.default.synchronize()
        }.value
    }

    public func observeExternalChanges(
        _ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { notification in
            let rawReason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey]
                as? Int ?? -1
            let reason: GlassSettingsStoreChangeReason
            switch rawReason {
            case NSUbiquitousKeyValueStoreServerChange:
                reason = .server
            case NSUbiquitousKeyValueStoreInitialSyncChange:
                reason = .initialSync
            case NSUbiquitousKeyValueStoreQuotaViolationChange:
                reason = .quota
            case NSUbiquitousKeyValueStoreAccountChange:
                reason = .account
            default:
                reason = .unknown(rawReason)
            }

            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String] ?? []
            let change = GlassSettingsStoreChange(
                reason: reason,
                changedKeys: Set(changedKeys)
            )
            Task { @MainActor in
                handler(change)
            }
        }
    }

    public func removeExternalChangeObserver(_ observer: NSObjectProtocol) {
        notificationCenter.removeObserver(observer)
    }
}

/// A platform-neutral color representation used only by the sync payload.
/// Keeping this independent from SwiftUI lets the transport remain
/// Foundation-only and makes validation deterministic in unit tests.

public struct GlassSettingsSyncEnvelope<Payload: GlassSettingsSyncPayload>: Codable, Equatable, Sendable {
    public static var currentSchemaVersion: Int { 1 }

    public let schemaVersion: Int
    public let revision: UInt64
    public let writerID: UUID
    public let writtenAt: Date
    public let payload: Payload

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        revision: UInt64,
        writerID: UUID,
        writtenAt: Date,
        payload: Payload
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.writerID = writerID
        self.writtenAt = writtenAt
        self.payload = payload
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GlassSettingsSyncError.unsupportedEnvelopeSchema(schemaVersion)
        }
        guard revision > 0 else {
            throw GlassSettingsSyncError.invalidPayload("Sync revisions must be greater than zero.")
        }
        try payload.validate()
    }

    /// A Lamport-style revision avoids device clock skew. Concurrent writers
    /// that produce the same revision resolve by canonical UUID ordering.
    public func isNewer(than other: Self) -> Bool {
        if revision != other.revision {
            return revision > other.revision
        }
        return writerID.uuidString > other.writerID.uuidString
    }
}

public enum GlassSettingsMergeResult<Payload: GlassSettingsSyncPayload>: Equatable, Sendable {
    case noValue
    case ignored(GlassSettingsSyncEnvelope<Payload>)
    case applied(GlassSettingsSyncEnvelope<Payload>)
}

public enum GlassSettingsSyncError: LocalizedError, Equatable, Sendable {
    case disabled
    case unavailable
    case accountUnavailable
    case quotaExceeded
    case encodedValueTooLarge(actual: Int, maximum: Int)
    case unsupportedEnvelopeSchema(Int)
    case unsupportedPayloadSchema(Int)
    case invalidPayload(String)
    case revisionOverflow
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "iCloud settings synchronization is disabled."
        case .unavailable:
            return "iCloud settings synchronization is unavailable."
        case .accountUnavailable:
            return "An iCloud account is required to synchronize settings."
        case .quotaExceeded:
            return "The iCloud key-value storage quota was exceeded."
        case .encodedValueTooLarge(let actual, let maximum):
            return "The synchronized settings value is \(actual) bytes; the maximum is \(maximum) bytes."
        case .unsupportedEnvelopeSchema(let version):
            return "The iCloud settings envelope schema \(version) is not supported."
        case .unsupportedPayloadSchema(let version):
            return "The iCloud settings payload schema \(version) is not supported."
        case .invalidPayload(let reason):
            return "The iCloud settings payload is invalid: \(reason)"
        case .revisionOverflow:
            return "The iCloud settings revision counter cannot be incremented."
        case .encodingFailed(let reason):
            return "The iCloud settings payload could not be encoded: \(reason)"
        case .decodingFailed(let reason):
            return "The iCloud settings payload could not be decoded: \(reason)"
        }
    }
}

@MainActor
public final class GlassSettingsSyncService<Payload: GlassSettingsSyncPayload> {
    public typealias MergeHandler = (Payload) -> Void
    public typealias StatusHandler = (GlassSettingsSyncStatus, String?) -> Void

    /// KVS permits 1 MB total. Reserving most of that quota avoids a single
    /// settings value crowding out future app metadata or server-side overhead.
    public static var maximumEncodedBytes: Int { 384 * 1024 }

    private let store: any GlassSettingsKeyValueStore
    private let writerID: UUID
    private let storeKey: String
    private let maximumEncodedBytes: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var externalChangeObserver: NSObjectProtocol?
    private var mergeHandler: MergeHandler?
    private var statusHandler: StatusHandler?
    private var isStarted = false
    private var startToken: UUID?

    public private(set) var status: GlassSettingsSyncStatus = .disabled {
        didSet { statusHandler?(status, lastErrorDescription) }
    }
    public private(set) var lastErrorDescription: String?
    public private(set) var acceptedEnvelope: GlassSettingsSyncEnvelope<Payload>?


    public init(
        store: any GlassSettingsKeyValueStore,
        writerID: UUID = UUID(),
        storeKey: String,
        maximumEncodedBytes: Int = 384 * 1024
    ) {
        precondition(!storeKey.isEmpty && storeKey.utf16.count <= 128)
        precondition(maximumEncodedBytes > 0 && maximumEncodedBytes < 1024 * 1024)

        self.store = store
        self.writerID = writerID
        self.storeKey = storeKey
        self.maximumEncodedBytes = maximumEncodedBytes

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    isolated deinit {
        if let externalChangeObserver {
            store.removeExternalChangeObserver(externalChangeObserver)
        }
    }

    public func start(
        enabled: Bool = true,
        onMerge: @escaping MergeHandler,
        onStatusChange: StatusHandler? = nil
    ) async {
        stop()
        mergeHandler = onMerge
        statusHandler = onStatusChange

        guard enabled else {
            updateStatus(.disabled)
            return
        }

        isStarted = true
        let token = UUID()
        startToken = token

        guard store.isAvailable else {
            updateStatus(.unavailable, error: GlassSettingsSyncError.unavailable)
            return
        }
        externalChangeObserver = store.observeExternalChanges { [weak self] change in
            self?.handleExternalChange(change)
        }
        let isAccountAvailable = await store.refreshAccountAvailability()
        guard !Task.isCancelled, isStarted, startToken == token else { return }
        guard isAccountAvailable else {
            updateStatus(.account, error: GlassSettingsSyncError.accountUnavailable)
            return
        }

        updateStatus(.syncing)
        let synchronized = await store.synchronize()
        guard !Task.isCancelled, isStarted, startToken == token else { return }
        guard synchronized else {
            updateStatus(.unavailable, error: GlassSettingsSyncError.unavailable)
            return
        }
        mergeExternalValueReportingErrors()
    }

    public func stop() {
        if let externalChangeObserver {
            store.removeExternalChangeObserver(externalChangeObserver)
        }
        externalChangeObserver = nil
        mergeHandler = nil
        statusHandler = nil
        isStarted = false
        startToken = nil
        lastErrorDescription = nil
        status = .disabled
    }

    @discardableResult
    public func push(
        _ payload: Payload,
        writtenAt: Date = Date()
    ) async throws -> GlassSettingsSyncEnvelope<Payload> {
        do {
            try requireAvailableStore()
            guard let token = startToken else {
                throw GlassSettingsSyncError.disabled
            }
            updateStatus(.syncing)
            try payload.validate()
            let storedEnvelope = try decodeStoredEnvelopeIfPresent()
            var convergedPayload = payload
            if let acceptedEnvelope {
                convergedPayload = convergedPayload.converged(with: acceptedEnvelope.payload)
            }
            if let storedEnvelope {
                convergedPayload = convergedPayload.converged(with: storedEnvelope.payload)
            }
            try convergedPayload.validate()
            let latestRevision = max(
                acceptedEnvelope?.revision ?? 0,
                storedEnvelope?.revision ?? 0
            )
            guard latestRevision < UInt64.max else {
                throw GlassSettingsSyncError.revisionOverflow
            }

            let envelope = GlassSettingsSyncEnvelope<Payload>(
                revision: latestRevision + 1,
                writerID: writerID,
                writtenAt: writtenAt,
                payload: convergedPayload
            )
            let encoded = try encode(envelope)
            store.set(encoded, forKey: storeKey)
            let synchronized = await store.synchronize()
            guard !Task.isCancelled, isStarted, startToken == token else {
                throw CancellationError()
            }
            guard synchronized else {
                throw GlassSettingsSyncError.unavailable
            }

            acceptedEnvelope = envelope
            updateStatus(.synced)
            return envelope
        } catch let error as CancellationError {
            throw error
        } catch {
            record(error)
            throw error
        }
    }

    /// Reads, validates, and deterministically merges the current KVS value.
    /// SettingsManager owns applying the returned allowlisted payload locally.
    @discardableResult
    public func merge() throws -> GlassSettingsMergeResult<Payload> {
        do {
            try requireAvailableStore()
            updateStatus(.syncing)
            guard let candidate = try decodeStoredEnvelopeIfPresent() else {
                updateStatus(.synced)
                return .noValue
            }
            let result = merge(candidate)
            updateStatus(.synced)
            return result
        } catch {
            record(error)
            throw error
        }
    }

    /// Direct envelope merge is useful for deterministic unit tests and for
    /// future transports that deliver already-decoded values.
    @discardableResult
    public func merge(_ candidate: GlassSettingsSyncEnvelope<Payload>) -> GlassSettingsMergeResult<Payload> {
        do {
            try candidate.validate()
        } catch {
            record(error)
            return .ignored(candidate)
        }

        if let acceptedEnvelope, !candidate.isNewer(than: acceptedEnvelope) {
            return .ignored(candidate)
        }

        acceptedEnvelope = candidate
        mergeHandler?(candidate.payload)
        return .applied(candidate)
    }

    private func handleExternalChange(_ change: GlassSettingsStoreChange) {
        guard isStarted else { return }
        switch change.reason {
        case .quota:
            updateStatus(.quota, error: GlassSettingsSyncError.quotaExceeded)
        case .account:
            // Revisions belong to one iCloud account namespace. Never compare
            // a newly signed-in account against an envelope accepted from the
            // previous account.
            acceptedEnvelope = nil
            let token = UUID()
            startToken = token
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isAccountAvailable = await self.store.refreshAccountAvailability()
                guard !Task.isCancelled, self.isStarted, self.startToken == token else { return }
                guard isAccountAvailable else {
                    self.updateStatus(.account, error: GlassSettingsSyncError.accountUnavailable)
                    return
                }
                self.updateStatus(.syncing)
                let synchronized = await self.store.synchronize()
                guard !Task.isCancelled, self.isStarted, self.startToken == token else { return }
                guard synchronized else {
                    self.updateStatus(.unavailable, error: GlassSettingsSyncError.unavailable)
                    return
                }
                self.mergeExternalValueReportingErrors()
            }
        case .server, .initialSync, .unknown:
            guard change.changedKeys.isEmpty || change.changedKeys.contains(storeKey) else {
                return
            }
            mergeExternalValueReportingErrors()
        }
    }

    private func mergeExternalValueReportingErrors() {
        do {
            _ = try merge()
        } catch {
            // merge() records a stable status and public-safe error description.
        }
    }

    private func requireAvailableStore() throws {
        guard isStarted else {
            throw GlassSettingsSyncError.disabled
        }
        guard store.isAvailable else {
            throw GlassSettingsSyncError.unavailable
        }
        guard store.isAccountAvailable else {
            throw GlassSettingsSyncError.accountUnavailable
        }
    }

    private func decodeStoredEnvelopeIfPresent() throws -> GlassSettingsSyncEnvelope<Payload>? {
        guard let data = store.data(forKey: storeKey) else { return nil }
        guard data.count <= maximumEncodedBytes else {
            throw GlassSettingsSyncError.encodedValueTooLarge(
                actual: data.count,
                maximum: maximumEncodedBytes
            )
        }

        do {
            let envelope = try decoder.decode(GlassSettingsSyncEnvelope<Payload>.self, from: data)
            try envelope.validate()
            return envelope
        } catch let error as GlassSettingsSyncError {
            throw error
        } catch {
            throw GlassSettingsSyncError.decodingFailed(error.localizedDescription)
        }
    }

    private func encode(_ envelope: GlassSettingsSyncEnvelope<Payload>) throws -> Data {
        do {
            try envelope.validate()
            let data = try encoder.encode(envelope)
            guard data.count <= maximumEncodedBytes else {
                throw GlassSettingsSyncError.encodedValueTooLarge(
                    actual: data.count,
                    maximum: maximumEncodedBytes
                )
            }
            return data
        } catch let error as GlassSettingsSyncError {
            throw error
        } catch {
            throw GlassSettingsSyncError.encodingFailed(error.localizedDescription)
        }
    }

    private func record(_ error: Error) {
        switch error {
        case GlassSettingsSyncError.disabled:
            updateStatus(.disabled, error: error)
        case GlassSettingsSyncError.accountUnavailable:
            updateStatus(.account, error: error)
        case GlassSettingsSyncError.quotaExceeded:
            updateStatus(.quota, error: error)
        case GlassSettingsSyncError.unavailable:
            updateStatus(.unavailable, error: error)
        default:
            updateStatus(.error, error: error)
        }
    }

    private func updateStatus(
        _ newStatus: GlassSettingsSyncStatus,
        error: Error? = nil
    ) {
        lastErrorDescription = error?.localizedDescription
        status = newStatus
    }
}
