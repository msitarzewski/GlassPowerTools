import Foundation
import Testing
@testable import GlassTerminal
import GlasSecretStore

/// Key records sync through iCloud Keychain, and each device reads its list once per launch. Saving
/// the list whole deleted every record a device didn't know about, so a key imported on another device
/// after this one launched lost its record at this one's next import, rename or delete (found reading
/// the source for more than one Mac, 2026-10-30). Each change now writes and deletes only its own.
///
/// Two devices here share one store of records standing for the Keychain; no Keychain is used.
@MainActor
@Suite("SSH key records on more than one device")
struct SSHKeyRecordsAcrossDevicesTests {
    /// The synchronized Keychain's key records, as every device sees them.
    @MainActor final class SharedRecords {
        var records: [UUID: StoredSSHKey] = [:]
        var store: SettingsManager.SSHKeyCatalogStore {
            .records(all: { [unowned self] in records.values.sorted { $0.createdAt < $1.createdAt } },
                     write: { [unowned self] in records[$0.id] = $0 },
                     delete: { [unowned self] in records[$0] = nil })
        }
    }

    /// A key's material, on the device that holds it.
    private func materialStore() -> SSHKeyLifecycleStore {
        var material: [UUID: SSHKeyMaterial] = [:]
        return SSHKeyLifecycleStore(
            retrieve: { material[$0] },
            delete: { material[$0] = nil },
            restore: { material[$0] = $1 },
            addIfAbsent: { id, value in
                guard material[id] == nil else { return false }
                material[id] = value
                return true
            }
        )
    }

    private func device(_ shared: SharedRecords, _ defaults: UserDefaults) -> SettingsManager {
        let settings = SettingsManager(loadImmediately: false, sshKeyDefaults: defaults, sshKeyLifecycleStore: materialStore())
        settings.sshKeyCatalogStore = shared.store
        settings.loadSSHKeys()
        return settings
    }

    private func key(_ name: String, age: TimeInterval) -> StoredSSHKey {
        StoredSSHKey(name: name, algorithm: "Ed25519", storageKind: .imported, algorithmKind: .ed25519,
                     migrationState: .migrated, createdAt: Date(timeIntervalSince1970: 1_790_000_000 + age))
    }

    /// An Ed25519 key file the import reads the type of; nothing in it is a real key.
    private var keyFile: String {
        func field(_ bytes: [UInt8]) -> [UInt8] {
            let count = UInt32(bytes.count)
            return [UInt8(count >> 24), UInt8(count >> 16 & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)] + bytes
        }
        var bytes = Array("openssh-key-v1\0".utf8)
        for value in ["none", "none", ""] { bytes += field(Array(value.utf8)) }
        bytes += [0, 0, 0, 1]
        bytes += field(field(Array("ssh-ed25519".utf8)))
        let label = "PRIVATE" + " KEY"
        return ["-----BEGIN OPENSSH \(label)-----", Data(bytes).base64EncodedString(), "-----END OPENSSH \(label)-----"]
            .joined(separator: "\n")
    }

    @Test("a key another device imported keeps its record through this device's import, rename and delete")
    func othersKeysSurvive() async throws {
        let suite = "SSHKeyRecordsAcrossDevices.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = SharedRecords()
        let mine = key("mine", age: 0)
        shared.records[mine.id] = mine

        let mac = device(shared, defaults)
        #expect(mac.sshKeys.map(\.name) == ["mine"])
        // The phone imports a key after the Mac read its list; the Mac doesn't know it.
        let phones = key("phone's", age: 10)
        shared.records[phones.id] = phones

        try mac.renameSSHKeyOrThrow(mine.id, name: "mine, renamed")
        #expect(shared.records[phones.id] == phones, "a rename here leaves the phone's key alone")
        #expect(Set(mac.sshKeys.map(\.name)) == ["mine, renamed", "phone's"], "and this device sees it now")

        let added = try mac.addSSHKey(name: "added", privateKey: keyFile, passphrase: nil)
        #expect(shared.records[phones.id] == phones && shared.records[added.id] != nil)

        try await mac.deleteSSHKey(added.id)
        #expect(shared.records[phones.id] == phones && shared.records[added.id] == nil && shared.records[mine.id] != nil)
    }

    @Test("a key deleted on another device isn't brought back by a rename here")
    func deletedElsewhereStaysDeleted() throws {
        let suite = "SSHKeyRecordsAcrossDevices.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = SharedRecords()
        let old = key("old", age: 0)
        shared.records[old.id] = old
        let mac = device(shared, defaults)
        shared.records[old.id] = nil

        #expect(throws: SecretStoreError.self) { try mac.renameSSHKeyOrThrow(old.id, name: "back again") }
        #expect(shared.records.isEmpty)
        #expect(mac.sshKeys.isEmpty, "this device's list is brought up to date")
    }
}
