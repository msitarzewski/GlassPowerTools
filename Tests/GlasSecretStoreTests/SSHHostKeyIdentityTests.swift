import Foundation
import Testing
@testable import GlasSecretStore

/// Whether a saved machine is this one, by its host key (D72; shared with the editor).
@Suite("This machine's host keys")
struct SSHHostKeyIdentityTests {
    @Test("this machine's public host keys are read as pinned keys are kept; a shared key is proof")
    func identity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glass-hostkeys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 root@alpha\n".write(to: folder.appendingPathComponent("ssh_host_ed25519_key.pub"), atomically: true, encoding: .utf8)
        try "not a key".write(to: folder.appendingPathComponent("ssh_host_rsa_key.pub"), atomically: true, encoding: .utf8)
        try "private".write(to: folder.appendingPathComponent("ssh_host_ed25519_key"), atomically: true, encoding: .utf8)

        let local = SSHHostKeyIdentity.localHostKeys(directory: folder.path)
        #expect(local == ["AAAAC3NzaC1lZDI1NTE5"])
        #expect(SSHHostKeyIdentity.isThisMachine(pinnedKeys: ["AAAAC3NzaC1lZDI1NTE5", "AAAAother"], localKeys: local))
        #expect(!SSHHostKeyIdentity.isThisMachine(pinnedKeys: ["AAAAother"], localKeys: local))
        #expect(!SSHHostKeyIdentity.isThisMachine(pinnedKeys: [], localKeys: local), "nothing pinned is not proof")
        #expect(!SSHHostKeyIdentity.isThisMachine(pinnedKeys: ["AAAAC3NzaC1lZDI1NTE5"], localKeys: []), "no host keys here is not proof")
    }
}
