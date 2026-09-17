//
//  GlassKeyStore.swift
//  Glass Power Tools — GlassShell
//
//  What the shell needs from whoever holds SSH key material, so the key manager can be a library
//  surface without the shell importing a capability (rule 6).
//
//  **Why a protocol and not a move.** D26 says keys are workspace-level: they outlive the
//  connections that reference them, and the manager is a library panel beside Collections rather
//  than a page inside one capability's settings. But the *material* and its lifecycle already live
//  in one place — import, Secure Enclave generation, the deletion journal that survives a crash
//  midway through unassigning — and that code is correct, transactional and tested. Moving it to
//  satisfy a diagram would be a rewrite of the one part of the system where a rewrite is least
//  affordable. So the surface moves and the lifecycle stays, joined here.
//
//  **Why the sheets come through as views.** Import, Generate and Rename are already written to
//  rule 15's shape against the manager that owns the keys. Re-implementing them here would be a
//  second editor that can drift from the first. `GlassCapability` already hands the library whole
//  views for the same reason (`libraryToolbarItems()`, `serviceDetailActions(service:host:)`).
//

import SwiftUI
import GlasSecretStore

@MainActor
public protocol GlassKeyStore: AnyObject {
    /// Every key this device can offer, in the order the manager keeps them.
    ///
    /// Read during `body`, so the conformer must expose it from `@Observable` storage or the panel
    /// will not redraw when a key is added, renamed or deleted.
    var keys: [StoredSSHKey] { get }

    /// Idempotent: the panel calls it on appear, because the library can be opened before anything
    /// has asked the owning capability to load its persistent state.
    func loadIfNeeded()

    /// The `authorized_keys` line for this key, derived from the material on demand. Throws rather
    /// than returning an empty string, so a key whose material is missing reads as an error and not
    /// as a key with no public half.
    func publicKey(for keyID: UUID) throws -> String

    /// Removes the key and unassigns it from everything holding it. Whoever owns the material owns
    /// this, because it is transactional: partially deleting a key is worse than not deleting it.
    func delete(_ keyID: UUID) async throws

    /// Rule 15 sheets, supplied by their owner.
    func importKeySheet() -> AnyView
    func generateKeySheet() -> AnyView
    func renameSheet(for key: StoredSSHKey) -> AnyView
}

public extension GlassKeyStore {
    /// `SHA256:…`, taken over the wire-format public key rather than the text around it.
    func fingerprint(for keyID: UUID) -> String? {
        guard let line = try? publicKey(for: keyID) else { return nil }
        return OpenSSHPublicKeyLine.sha256Fingerprint(in: line)
    }
}

/// Where a key can be used, said plainly.
///
/// Secure Enclave material cannot leave the device that minted it (D26 stage 3), so a key is either
/// on every device signed into the account or on exactly this one. This is the *only* distinction
/// the badge draws, because it is the only one that changes what a user can expect to happen on
/// their other device.
public enum GlassKeyMobility: Sendable {
    case synchronized
    case thisDeviceOnly

    public init(_ key: StoredSSHKey) {
        self = key.storageKind == .secureEnclave ? .thisDeviceOnly : .synchronized
    }

    public var title: String {
        switch self {
        case .synchronized: "iCloud"
        case .thisDeviceOnly: "This device only"
        }
    }

    public var symbolName: String {
        switch self {
        case .synchronized: "icloud"
        case .thisDeviceOnly: "lock.iphone"
        }
    }

    public var explanation: String {
        switch self {
        case .synchronized:
            "This key is available on every device signed into your iCloud account."
        case .thisDeviceOnly:
            "This key was generated in this device's Secure Enclave. It cannot be copied, so services that use it do not appear on your other devices."
        }
    }
}
