import Foundation
import Observation

/// Owns the one persisted `GlassLayerState` and performs the one-time legacy migration.
@Observable
@MainActor
public final class GlassLayerStore {
    public static let stateKey = "glass.layers.state"
    public static let migrationKey = "glass.layers.migrationSource"
    /// Stamped once so the default-adoption below can never run twice — otherwise a user who
    /// deliberately picks "Light" would be moved off it again on the next launch.
    public static let defaultRevisionKey = "glass.layers.defaultRevision"
    static let currentDefaultRevision = 1

    private let defaults: UserDefaults
    private var storage: GlassLayerState
    /// Where the initial state came from. `none` after a fresh start or once the user has a
    /// stored state of their own. Shown on the About page and asserted by tests.
    public private(set) var migrationSource: GlassLayerMigrationSource

    /// The state as stored, read without migrating or writing anything, for a surface outside
    /// SwiftUI's environment (the command palette's panel). The default when nothing is stored.
    public static func storedState(in defaults: UserDefaults = GlassUITestRun.settingsDefaults) -> GlassLayerState {
        defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(GlassLayerState.self, from: $0) } ?? .default
    }

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
        if let data = defaults.data(forKey: Self.stateKey) {
            if let stored = try? JSONDecoder().decode(GlassLayerState.self, from: data) {
                migrationSource = defaults.string(forKey: Self.migrationKey)
                    .flatMap(GlassLayerMigrationSource.init(rawValue:)) ?? .none
                // A state that is byte-for-byte the old default was never chosen — it is what the
                // store wrote on first launch. Those users get the new default; anyone who moved a
                // control keeps exactly what they set, including a deliberate `ultraThin`.
                let stamped = defaults.integer(forKey: Self.defaultRevisionKey)
                if stamped < Self.currentDefaultRevision, stored == .ultraThinDefault {
                    storage = .default
                    persist()
                } else {
                    storage = stored
                }
            } else {
                // A stored value exists but is unreadable: the user had a state of their own, so
                // do not re-run the legacy migration over it. Start from the default.
                storage = .default
                migrationSource = .none
                persist()
            }
        } else {
            let (migrated, source) = GlassLayerLegacy.migrate(from: legacyDefaults)
            storage = migrated
            migrationSource = source
            persist()
        }
        // Unconditional, and after every read above: a store that only stamped when it changed
        // something would re-examine the state on every launch and could move a later, deliberate
        // `ultraThin` off itself.
        defaults.set(Self.currentDefaultRevision, forKey: Self.defaultRevisionKey)
    }

    /// The App Group suite, this application's standard domain, and on macOS the three source
    /// applications' bundle domains (best effort: empty under App Sandbox).
    public nonisolated static var defaultLegacySuites: [UserDefaults] {
        var suites: [UserDefaults] = [.standard]
        if let group = UserDefaults(suiteName: GlassLayerLegacy.appGroupSuite) { suites.append(group) }
        #if os(macOS)
        // Under App Sandbox these domains are unreadable and each attempt logs a violation, so
        // only look when the process is not sandboxed.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            for identifier in GlassLayerLegacy.legacyBundleIdentifiers {
                if let domain = UserDefaults(suiteName: identifier) { suites.append(domain) }
            }
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
