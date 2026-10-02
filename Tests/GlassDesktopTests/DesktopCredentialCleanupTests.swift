import Foundation
import Testing
import GlassShell
import GlassConnectionKit
import GlasSecretStore
@testable import GlassDesktop

/// A desktop's password lives in the Keychain, synced; the record only points at it. Removing the
/// record, or replacing the password, used to leave the old credential behind on every device.
@Suite("Desktop credentials are cleaned up")
@MainActor
struct DesktopCredentialCleanupTests {
    private final class Keychain: @unchecked Sendable {
        var values: [UUID: RDPCredential] = [:]
        @MainActor var access: DesktopCredentialAccess {
            DesktopCredentialAccess(
                retrieve: { id, _, _ in
                    guard let value = self.values[id] else { throw SecretStoreError.notFound }
                    return value
                },
                save: { credential, id, _ in self.values[id] = credential },
                delete: { id, _ in self.values.removeValue(forKey: id) },
                availability: { id, _ in self.values[id] == nil ? .missing : .available },
                migrate: { _, _, _ in })
        }
    }

    private func model(_ keychain: Keychain) async -> DesktopAppModel {
        let app = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("desktop-credentials-\(UUID().uuidString)"), credentialAccess: keychain.access)
        await app.attach(store: GlassInMemoryServiceStore(defaultKind: .rdp))
        return app
    }

    @Test("removing a desktop removes its saved password")
    func removeDeletesCredential() async throws {
        let keychain = Keychain()
        let app = await model(keychain)
        try await app.save(DesktopConnection(name: "Desktop on alpha", host: "192.0.2.10", username: "ann"), password: "one")
        let saved = try #require(app.connections.first)
        #expect(keychain.values[saved.credentialID.rawValue] != nil)

        await app.delete(saved)

        #expect(app.connections.isEmpty)
        #expect(keychain.values.isEmpty, "no password left behind")
        #expect(app.errorMessage == nil)
    }

    @Test("removing a duplicate that shares the survivor's password leaves the password")
    func removingDuplicateKeepsSharedCredential() async throws {
        let keychain = Keychain()
        let app = await model(keychain)
        try await app.save(DesktopConnection(name: "Desktop on alpha", host: "192.0.2.10", username: "ann"), password: "one")
        let survivor = try #require(app.connections.first)
        var duplicate = survivor
        duplicate.id = EndpointID()
        try await app.save(duplicate, password: nil)
        #expect(app.connections.count == 2)

        await app.delete(try #require(app.connections.first { $0.id == duplicate.id }))

        #expect(app.connections.map(\.id) == [survivor.id])
        #expect(keychain.values[survivor.credentialID.rawValue] != nil, "the survivor can still connect")
        #expect(app.errorMessage == nil)
    }

    @Test("a new password replaces the old one under the same credential, so other devices still find it")
    func newPasswordKeepsCredential() async throws {
        let keychain = Keychain()
        let app = await model(keychain)
        try await app.save(DesktopConnection(name: "Desktop on alpha", host: "192.0.2.10", username: "ann"), password: "one")
        let first = try #require(app.connections.first)

        try await app.save(first, password: "two")

        let second = try #require(app.connections.first)
        #expect(second.credentialID == first.credentialID, "the synced record's pointer does not move")
        #expect(keychain.values.count == 1)
        #expect(keychain.values[second.credentialID.rawValue]?.password.toUTF8String() == "two")
    }
}
