import Foundation
import Testing
@testable import GlassDatabase

/// Query history is kept on disk, and a literal can be a password. Redaction is on unless the
/// person turned it off, and the setting and the history writer read that the same way.
@MainActor
@Suite("Query history redaction")
struct QueryHistoryRedactionTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "query-history-redaction.\(UUID().uuidString)")!
    }

    @Test("an install that never chose redacts")
    func onByDefault() {
        let store = defaults()
        #expect(QueryHistoryRedaction.isOn(in: store))
        #expect(SettingsManager(defaults: store).redactQueryHistoryLiterals)
    }

    @Test("a choice to keep literals is honoured by both readers")
    func offWhenChosen() {
        let store = defaults()
        store.set(false, forKey: UserDefaultsKeys.redactQueryHistoryLiterals)
        #expect(!QueryHistoryRedaction.isOn(in: store))
        #expect(!SettingsManager(defaults: store).redactQueryHistoryLiterals)
    }
}
