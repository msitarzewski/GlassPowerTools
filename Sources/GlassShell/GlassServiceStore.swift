//
//  GlassServiceStore.swift
//  Glass Power Tools — GlassShell
//
//  D26: the catalog is the one store for a connection.
//
//  A capability's own configuration — the terminal's server, the database's connection, the
//  desktop's record — lives on its `HostServiceLink`, encoded by the capability that owns it and
//  opaque to everything else. This is the narrow door capabilities reach it through.
//
//  It is a protocol rather than the model itself for the same reason `GlassCapabilityHostAccess`
//  is: a capability must not hold the shell model. It also makes the whole of D26 testable without
//  a catalog on disk, which is what the in-memory implementation below is for.
//

import Foundation
import GlassConnectionKit

/// Read and write the configuration a capability owns for one of its services.
///
/// **Never put a secret here.** Credentials have their own synchronized home in the Keychain and
/// the link's `credentialID` is how they are found; a configuration carries the metadata needed to
/// reach a machine, not the means to authenticate to it.
@MainActor
public protocol GlassServiceStore: AnyObject {
    /// The capability's encoded record for this service, or nil when it has never been set up.
    func configuration(for endpointID: EndpointID) -> Data?

    /// Writes the capability's record and publishes it, so the service is usable on every device
    /// the moment the catalog arrives there.
    func setConfiguration(_ data: Data?, for endpointID: EndpointID) async throws

    /// Every configured service of one kind. Capabilities that keep an in-memory index — the
    /// terminal's saved-server list, for instance — build it from this rather than a second store.
    func configurations(ofKind kind: HostServiceKind) -> [EndpointID: Data]

    /// Whether the catalog behind this store has actually been read yet.
    ///
    /// **Empty and unread are different answers, and telling them apart is what this is for.**
    /// The composition root attaches the store while building the app; the catalog is read from
    /// disk later, from the library's `.task`. In between, `configurations(ofKind:)` returns
    /// nothing — and a capability that takes that at face value concludes the user has no saved
    /// connections, then reconciles the catalog to match and deletes every one of them. That is
    /// exactly what happened: a machine kept its service link and lost the configuration behind
    /// it, and the sheet said "This terminal has no saved configuration behind it."
    var isCatalogLoaded: Bool { get }
}

public extension GlassServiceStore {
    /// A store with nothing behind it but memory is readable as soon as it exists. Only a store
    /// over a file the app has yet to read has to say otherwise, and `GlassShellModel` does.
    var isCatalogLoaded: Bool { true }

    /// Decode straight to the capability's own type, returning nil rather than throwing when the
    /// record was written by a build that knew a different shape.
    ///
    /// Skipping is deliberate and matches the catalog backend's rule for a record it cannot
    /// decode: one unreadable service must not take a whole library down with it.
    func configuration<T: Decodable>(_ type: T.Type, for endpointID: EndpointID) -> T? {
        guard let data = configuration(for: endpointID) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Encode the capability's own type and store it.
    ///
    /// **The label is load-bearing.** Without it this reads
    /// `setConfiguration<T: Encodable>(_ value: T, …)`, and `Data` is itself `Encodable` — so
    /// passing `Data` matches the generic exactly while matching the `Data?` requirement only
    /// through optional promotion, and Swift prefers the exact match. The body then encodes the
    /// `Data` to a base64 JSON string, producing more `Data`, and calls itself. It recursed
    /// forever, each turn allocating a larger blob, until the process was killed for using 90 GB —
    /// with no crash report and no output, because an out-of-memory kill leaves neither.
    ///
    /// The `Data?` local below is the second guard: even under the label, it makes the requirement
    /// the only thing this call can resolve to.
    func setConfiguration<T: Encodable>(encoding value: T, for endpointID: EndpointID) async throws {
        let encoded: Data? = try JSONEncoder().encode(value)
        try await setConfiguration(encoded, for: endpointID)
    }

    /// Every decodable record of one kind, in no particular order. Undecodable entries are skipped.
    func configurations<T: Decodable>(_ type: T.Type, ofKind kind: HostServiceKind) -> [EndpointID: T] {
        configurations(ofKind: kind).compactMapValues { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// A store with no catalog behind it, for tests and previews.
@MainActor
public final class GlassInMemoryServiceStore: GlassServiceStore {
    private var storage: [EndpointID: (kind: HostServiceKind, data: Data)] = [:]
    /// The kind a newly written configuration is filed under when the test has not said.
    private let defaultKind: HostServiceKind

    public init(defaultKind: HostServiceKind = .ssh) { self.defaultKind = defaultKind }

    public func configuration(for endpointID: EndpointID) -> Data? { storage[endpointID]?.data }

    public func setConfiguration(_ data: Data?, for endpointID: EndpointID) async throws {
        guard let data else { storage.removeValue(forKey: endpointID); return }
        let kind = storage[endpointID]?.kind ?? defaultKind
        storage[endpointID] = (kind, data)
    }

    public func configurations(ofKind kind: HostServiceKind) -> [EndpointID: Data] {
        storage.filter { $0.value.kind == kind }.mapValues(\.data)
    }

    /// Files a configuration under a specific kind, which the real store learns from the link.
    public func setConfiguration(_ data: Data, kind: HostServiceKind, for endpointID: EndpointID) {
        storage[endpointID] = (kind, data)
    }
}
