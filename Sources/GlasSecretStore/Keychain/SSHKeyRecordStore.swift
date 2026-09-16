//
//  SSHKeyRecordStore.swift
//  GlasSecretStore
//
//  A key's record — what it is called, what algorithm, how it is held — stored in the Keychain
//  beside its material.
//
//  **Why here and not in a store of its own.** D26 asked where key records should live so they
//  travel between devices. A second store would need its own merge rule, and could disagree with
//  the material it describes: a record for a key that is not there, or a key with no name. Beside
//  the material there is nothing to reconcile — the same routing decides both, so a record exists
//  exactly where its key does.
//
//  That routing is the other half: a Secure Enclave key's material cannot leave the device it was
//  minted on, so its record must not either, or the key would be listed as available somewhere it
//  is guaranteed to fail. Callers pass the configuration the material went to, and the record
//  follows it.
//

import Foundation

public enum SSHKeyRecordStore {

    public static func save(_ record: StoredSSHKey, config: SecretStoreConfiguration) throws {
        try KeychainOperations.saveData(
            try JSONEncoder().encode(record),
            account: record.id.uuidString,
            service: config.sshKeysRecordService,
            config: config
        )
    }

    /// Every record in this configuration, oldest first.
    ///
    /// A record this build cannot decode is **skipped, not fatal**, matching the rule everywhere
    /// else a stored shape is read back: one unreadable key must not take the whole library down
    /// with it, because the library is how a user would go and delete the bad one.
    public static func all(config: SecretStoreConfiguration) throws -> [StoredSSHKey] {
        let items = try KeychainOperations.allItems(service: config.sshKeysRecordService, config: config)
        return items.compactMap { attributes -> StoredSSHKey? in
            guard let account = attributes[kSecAttrAccount as String] as? String,
                  let data = try? KeychainOperations.retrieveData(
                    account: account, service: config.sshKeysRecordService, config: config) else {
                return nil
            }
            return try? JSONDecoder().decode(StoredSSHKey.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    public static func delete(_ keyID: UUID, config: SecretStoreConfiguration) throws {
        try KeychainOperations.deleteItem(
            account: keyID.uuidString,
            service: config.sshKeysRecordService,
            config: config
        )
    }
}
