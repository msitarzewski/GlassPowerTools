import Foundation
import Observation

/// Owns the one persisted `GlassLayerState` and performs the one-time legacy migration.
@Observable
@MainActor
public final class GlassLayerStore {
    public static let stateKey = "glass.layers.state"
    public static let migrationKey = "glass.layers.migrationSource"

    private let defaults: UserDefaults
    private var storage: GlassLayerState
    /// Where the initial state came from. `none` after a fresh start or once the user has a
    /// stored state of their own. Shown on the About page and asserted by tests.
    public private(set) var migrationSource: GlassLayerMigrationSource

    public var state: GlassLayerState {
        get { storage }
        set {
            guard newValue != storage else { return }
            storage = newValue
            persist()
        }
    }

    /// - Parameters:
    ///   - defaults: where this application persists its own state.
    ///   - legacyDefaults: suites searched, in order, when no stored state exists yet.
    public init(defaults: UserDefaults = .standard, legacyDefaults: [UserDefaults] = GlassLayerStore.defaultLegacySuites) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.stateKey),
           let stored = try? JSONDecoder().decode(GlassLayerState.self, from: data) {
            storage = stored
            migrationSource = defaults.string(forKey: Self.migrationKey)
                .flatMap(GlassLayerMigrationSource.init(rawValue:)) ?? .none
        } else {
            let (migrated, source) = GlassLayerLegacy.migrate(from: legacyDefaults)
            storage = migrated
            migrationSource = source
            persist()
        }
    }

    /// The App Group suite, this application's standard domain, and on macOS the three source
    /// applications' bundle domains (best effort: empty under App Sandbox).
    public nonisolated static var defaultLegacySuites: [UserDefaults] {
        var suites: [UserDefaults] = [.standard]
        if let group = UserDefaults(suiteName: GlassLayerLegacy.appGroupSuite) { suites.append(group) }
        #if os(macOS)
        for identifier in GlassLayerLegacy.legacyBundleIdentifiers {
            if let domain = UserDefaults(suiteName: identifier) { suites.append(domain) }
        }
        #endif
        return suites
    }

    /// Return to decision D2's default and forget the migration provenance.
    public func reset() {
        storage = .default
        migrationSource = .none
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(storage) {
            defaults.set(data, forKey: Self.stateKey)
        }
        defaults.set(migrationSource.rawValue, forKey: Self.migrationKey)
    }
}
