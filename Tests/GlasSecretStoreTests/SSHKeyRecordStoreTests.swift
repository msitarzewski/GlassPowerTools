import Testing
import Foundation
import Security
@testable import GlasSecretStore

/// D26: a key's record lives beside its material, so the two can never disagree and there is no
/// second store to merge. These pin the three things that follow from that.
@Suite("SSHKeyRecordStore")
struct SSHKeyRecordStoreTests {

    private let config: SecretStoreConfiguration

    init() {
        config = SecretStoreConfiguration(
            serviceNamePrefix: "test.SSHKeyRecord.\(UUID().uuidString.prefix(8))",
            accessGroup: nil,
            legacyServiceNamePrefixes: []
        )
    }

    private func cleanup() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.sshKeysRecordService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func key(_ name: String, kind: SSHKeyStorageKind = .imported,
                     createdAt: Date = Date()) -> StoredSSHKey {
        StoredSSHKey(name: name, algorithm: "ssh-ed25519", storageKind: kind, createdAt: createdAt)
    }

    @Test("A record round-trips, and saving again replaces rather than duplicates")
    func roundTripAndReplace() throws {
        defer { cleanup() }
        var record = key("alpha")
        try SSHKeyRecordStore.save(record, config: config)

        #expect(try SSHKeyRecordStore.all(config: config).map(\.name) == ["alpha"])

        record.name = "alpha renamed"
        try SSHKeyRecordStore.save(record, config: config)

        let all = try SSHKeyRecordStore.all(config: config)
        #expect(all.count == 1, "a rename created a second record instead of replacing one")
        #expect(all.first?.name == "alpha renamed")
        #expect(all.first?.id == record.id)
    }

    @Test("Records come back oldest first, so the library has a stable order")
    func stableOrder() throws {
        defer { cleanup() }
        let old = key("first", createdAt: Date(timeIntervalSince1970: 1_000))
        let new = key("second", createdAt: Date(timeIntervalSince1970: 2_000))
        try SSHKeyRecordStore.save(new, config: config)
        try SSHKeyRecordStore.save(old, config: config)

        #expect(try SSHKeyRecordStore.all(config: config).map(\.name) == ["first", "second"])
    }

    @Test("Deleting a record removes it and leaves the others")
    func deleteOne() throws {
        defer { cleanup() }
        let kept = key("kept")
        let gone = key("gone")
        try SSHKeyRecordStore.save(kept, config: config)
        try SSHKeyRecordStore.save(gone, config: config)

        try SSHKeyRecordStore.delete(gone.id, config: config)

        #expect(try SSHKeyRecordStore.all(config: config).map(\.name) == ["kept"])
    }

    /// The rule the whole design rests on: a record may travel only where its material can. A
    /// Secure Enclave record on another device would name a key guaranteed to fail there.
    @Test("The record service is eligible to synchronize, and the Secure Enclave services are not")
    func mobilityMatchesTheMaterial() {
        let synchronizable = config.synchronizableServices
        #expect(synchronizable.contains(config.sshKeysRecordService))
        #expect(synchronizable.contains(config.sshKeysPrivateService))
        #expect(!synchronizable.contains(config.sealedP256Service))
        #expect(!synchronizable.contains(config.sealedP256TagService))
    }
}
