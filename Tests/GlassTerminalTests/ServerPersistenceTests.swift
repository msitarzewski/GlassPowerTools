//
//  ServerPersistenceTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D26 stage 1 moves the terminal's saved servers out of `UserDefaultsKeys.servers` and onto the
//  service link. `persistServerMutation` is the contract that move must not change, and it is
//  subtle enough to be worth pinning before the seam underneath it is replaced rather than after:
//
//    - a failed write leaves `servers` and the stored catalog exactly as they were, and rethrows
//      the *original* failure, not the rollback's,
//    - a failed write whose rollback also fails is reported as `rollbackFailed`, because at that
//      point the stored catalog genuinely is unknown and saying so is the only honest answer.
//
//  Both are written against the pre-D26 implementation deliberately: they are the evidence that
//  the refactor preserved behaviour rather than merely compiled.
//
//  One thing these tests had to be corrected to respect, because the first draft asserted the
//  opposite and was wrong: **a write that lands nowhere rolls back successfully.** The rollback
//  re-persists the original catalog and verifies it by readback, and if the failing writer simply
//  dropped the bytes then the stored catalog is still the original — so the verification passes and
//  the original error is rethrown. Reaching `rollbackFailed` requires the store to end up holding
//  something genuinely different, which is what `landing` below exists to arrange.
//

import Testing
import Foundation
@testable import GlassTerminal

@Suite(.serialized)
struct ServerPersistenceTests {

    private func server(named name: String, id: UUID = UUID()) -> ServerConfiguration {
        ServerConfiguration(id: id, name: name, host: "\(name).example.com", username: "operator")
    }

    /// A counter the escaping writer and the test can both see.
    private final class Writes: @unchecked Sendable { var count = 0 }

    /// A defaults suite holding `existing`, and a writer whose every call the test decides.
    ///
    /// `landing` receives the 1-based write number and the bytes the manager asked to store, and
    /// returns what actually reaches the store — the same bytes for a normal write, different bytes
    /// for a store that lies, or nil for a write that lands nowhere.
    private func fixture(
        existing: [ServerConfiguration],
        landing: @escaping @Sendable (Int, Data) -> Data?
    ) async throws -> (manager: ServerManager, defaults: UserDefaults, suite: String, writes: Writes) {
        let suite = "sh.glas.test.server-persistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(try JSONEncoder().encode(existing), forKey: UserDefaultsKeys.servers)

        let writes = Writes()
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            serverDataWriter: { data in
                writes.count += 1
                guard let landed = landing(writes.count, data) else { return }
                defaults.set(landed, forKey: UserDefaultsKeys.servers)
            }
        )
        // Assigned rather than loaded: `loadServers` runs the credential and host-trust
        // migrations, which reach the real Keychain and are not what this test is about.
        manager.servers = existing
        return (manager, defaults, suite, writes)
    }

    @Test @MainActor func aFailedWriteRollsBackAndRethrowsTheOriginalFailure() async throws {
        let existing = server(named: "alpha")
        let (manager, defaults, suite, writes) = try await fixture(existing: [existing]) { attempt, data in
            attempt == 1 ? nil : data
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        await #expect(throws: ServerManagerError.persistenceReadbackMismatch) {
            try await manager.addServerOrThrow(server(named: "bravo"))
        }

        // Two writes: the candidate catalog, then the rollback to the original.
        #expect(writes.count == 2)
        #expect(manager.servers == [existing])
        let stored = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: stored) == [existing])
    }

    @Test @MainActor func aFailedRollbackIsReportedAsSuchRatherThanAsTheOriginalFailure() async throws {
        let existing = server(named: "alpha")
        let empty = try JSONEncoder().encode([ServerConfiguration]())
        // The candidate write lands nowhere; the rollback lands an empty catalog instead of the
        // original, so its readback disagrees and the rollback is the failure that gets reported.
        let (manager, defaults, suite, writes) = try await fixture(existing: [existing]) { attempt, _ in
            attempt == 1 ? nil : empty
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        await #expect(throws: ServerManagerError.rollbackFailed) {
            try await manager.addServerOrThrow(server(named: "bravo"))
        }
        #expect(writes.count == 2)
        // The in-memory list is still the truth the user last saw, even though the store is not.
        #expect(manager.servers == [existing])
    }

    @Test @MainActor func aSuccessfulWriteCommitsBothTheCatalogAndTheInMemoryList() async throws {
        let existing = server(named: "alpha")
        let added = server(named: "bravo")
        let (manager, defaults, suite, writes) = try await fixture(existing: [existing]) { _, data in data }
        defer { defaults.removePersistentDomain(forName: suite) }

        try await manager.addServerOrThrow(added)

        #expect(writes.count == 1)
        #expect(manager.servers == [existing, added])
        let stored = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: stored) == [existing, added])
    }
}
