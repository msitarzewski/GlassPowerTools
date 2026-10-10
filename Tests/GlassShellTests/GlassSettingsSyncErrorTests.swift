import Foundation
import OSLog
import Testing
@testable import GlassShell

/// W18 (2026-10-10): every launch logged "Failed to synchronize portable settings: Error
/// Domain=GlassShell.GlassSettingsSyncError Code=3" — a bridged NSError, which says neither the
/// case nor why. A sync failure is now logged as its case and detail, and what the person reads in
/// Settings says what happens and what to do.
@MainActor
@Suite("Settings sync errors")
struct GlassSettingsSyncErrorTests {
    @MainActor final class Store: GlassSettingsKeyValueStore {
        var values: [String: Data] = [:]
        var isAvailable: Bool { true }
        var isAccountAvailable: Bool { true }
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data, forKey key: String) { values[key] = data }
        func synchronize() async -> Bool { true }
        func observeExternalChanges(
            _ handler: @escaping @MainActor @Sendable (GlassSettingsStoreChange) -> Void
        ) -> NSObjectProtocol { NSObject() }
        func removeExternalChangeObserver(_ observer: NSObjectProtocol) {}
    }

    private static let every: [GlassSettingsSyncError] = [
        .disabled, .unavailable, .accountUnavailable, .quotaExceeded,
        .encodedValueTooLarge(actual: 400_000, maximum: 393_216),
        .unsupportedEnvelopeSchema(2), .unsupportedPayloadSchema(2),
        .invalidPayload("The synchronized library must contain one active built-in theme."),
        .revisionOverflow, .encodingFailed("x"), .decodingFailed("x"),
    ]

    /// Evidence for the log line, not a behaviour: Swift numbers the cases that carry a value
    /// first, in declaration order, so "Code=3" is `invalidPayload`, the fourth of those.
    @Test("the bridged code 3 is invalidPayload")
    func bridgedCodes() {
        let codes = Dictionary(uniqueKeysWithValues: Self.every.map { ($0.logDescription, ($0 as NSError).code) })
        #expect(codes["invalidPayload(\"The synchronized library must contain one active built-in theme.\")"] == 3)
        #expect(codes["encodedValueTooLarge(actual: 400000, maximum: 393216)"] == 0)
        #expect(codes["decodingFailed(\"x\")"] == 5)
        #expect(codes["disabled"] == 6)
        #expect(codes["revisionOverflow"] == 10)
    }

    @Test("the log names the case and its detail; another error only its domain and code")
    func logDescription() {
        #expect(GlassSettingsSyncError.logDescription(of: GlassSettingsSyncError.invalidPayload("Why."))
                == "invalidPayload(\"Why.\")")
        #expect(GlassSettingsSyncError.encodedValueTooLarge(actual: 2, maximum: 1).logDescription
                == "encodedValueTooLarge(actual: 2, maximum: 1)")
        let foreign = NSError(domain: "Elsewhere", code: 7, userInfo: [NSLocalizedDescriptionKey: "alpha's notes"])
        #expect(GlassSettingsSyncError.logDescription(of: foreign) == "Elsewhere 7")
    }

    @Test("what the person reads says what happens and what to do, without the jargon")
    func plainWords() throws {
        let jargon = ["payload", "schema", "envelope", "decod", "encod", "revision", "key-value", "quota", "bytes"]
        for error in Self.every where ![.disabled, .unavailable, .accountUnavailable].contains(error) {
            let text = try #require(error.errorDescription)
            for word in jargon {
                #expect(!text.localizedCaseInsensitiveContains(word), "\(error.logDescription): \(text)")
            }
            #expect(text.contains("this device"), "says where the settings are: \(text)")
            #expect(text.contains("Update") || text.contains("Removing"), "says what to do: \(text)")
        }
    }

    /// A stored value this build refuses, read at start and again before a push: both refusals
    /// reach the log, readably, under the store's key. Nothing was logged for the read before.
    @Test("a refused read and a refused send are logged as their case and detail")
    func refusalsAreLogged() async throws {
        let started = Date()
        let key = "w18-test-\(UUID().uuidString)"
        let store = Store()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        store.values[key] = try encoder.encode(GlassSettingsSyncEnvelope(
            revision: 0, writerID: UUID(), writtenAt: started, payload: GlassFavoritesPayload()))
        let service = GlassSettingsSyncService<GlassFavoritesPayload>(store: store, storeKey: key)

        await service.start(onMerge: { _ in })
        await #expect(throws: GlassSettingsSyncError.self) { try await service.push(GlassFavoritesPayload()) }

        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        var messages: [String] = []
        // A deadline, not a count: one read of the process's log takes about a second.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            messages = try logStore.getEntries(
                at: logStore.position(date: started),
                matching: NSPredicate(format: "subsystem == %@ AND category == %@", "com.glasspowertools", "settings"))
                .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
                .filter { $0.contains(key) }
            if messages.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let detail = "invalidPayload(\"Sync revisions must be greater than zero.\")"
        #expect(messages.contains("Failed to synchronize settings (\(key)) while reading: \(detail)"), "\(messages)")
        #expect(messages.contains("Failed to synchronize settings (\(key)) while sending: \(detail)"), "\(messages)")
    }
}
