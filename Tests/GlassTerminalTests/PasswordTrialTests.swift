import Foundation
import Testing
import GlasSecretStore
@testable import GlassTerminal

/// A password typed at a prompt is kept only if it signs in (help audit, 2026-09-27: a mistyped
/// password replaced a working one before sign-in was even tried).
@Suite("Password typed at a prompt", .serialized)
@MainActor
struct PasswordTrialTests {
    final class Passwords: @unchecked Sendable { var values: [UUID: String] = [:] }

    private func manager() throws -> (ServerManager, Passwords, ServerConfiguration, String) {
        let suite = "sh.glas.test.trial.\(UUID().uuidString)"
        let passwords = Passwords()
        let store = ServerPasswordStore(
            retrieve: { server in
                guard let value = passwords.values[server.id] else { throw SecretStoreError.notFound }
                return value
            },
            save: { value, server in passwords.values[server.id] = value },
            delete: { id in passwords.values[id] = nil })
        let servers = ServerManager(loadImmediately: false, defaults: UserDefaults.forTest(suiteName: suite)!,
                                    passwordStore: store)
        servers.loadServersIfNeeded()
        let server = ServerConfiguration(name: "alpha", host: "alpha.example", username: "ann")
        return (servers, passwords, server, suite)
    }

    @Test("a password that fails to sign in gives back the one that was there")
    func failedTrialRestores() async throws {
        let (servers, passwords, server, suite) = try manager()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try await servers.addServerOrThrow(server, password: "working")

        try await servers.tryPassword("typo", for: server)
        #expect(passwords.values[server.id] == "typo", "on trial, it is where the connection reads it")
        try await servers.tryPassword("typo again", for: server)
        servers.settlePasswordTrial(for: server.id, succeeded: false)
        #expect(passwords.values[server.id] == "working", "the password from before any typing")
    }

    @Test("a password that signs in is kept, and a later failure does not undo it")
    func successfulTrialKeeps() async throws {
        let (servers, passwords, server, suite) = try manager()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try await servers.addServerOrThrow(server, password: "old")

        try await servers.tryPassword("new", for: server)
        servers.settlePasswordTrial(for: server.id, succeeded: true)
        servers.settlePasswordTrial(for: server.id, succeeded: false)
        #expect(passwords.values[server.id] == "new")
    }

    @Test("with nothing saved before, a failed try leaves nothing saved")
    func failedTrialWithNothingBefore() async throws {
        let (servers, passwords, server, suite) = try manager()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try await servers.addServerOrThrow(server)

        try await servers.tryPassword("guess", for: server)
        servers.settlePasswordTrial(for: server.id, succeeded: false)
        #expect(passwords.values[server.id] == nil)
    }
}
