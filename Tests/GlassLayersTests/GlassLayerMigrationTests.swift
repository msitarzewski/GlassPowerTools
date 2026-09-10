import Foundation
import Testing
@testable import GlassLayers

/// A throwaway UserDefaults suite, removed when the fixture goes away.
final class DefaultsFixture: @unchecked Sendable {
    let name: String
    let defaults: UserDefaults
    init() {
        name = "GlassLayersTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
    }
    deinit { defaults.removePersistentDomain(forName: name) }
}

@Suite("GlassLayer migration", .serialized)
@MainActor
struct GlassLayerMigrationTests {
    @Test("No legacy keys anywhere → decision D2 default, source none")
    func fresh() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state == .default)
        #expect(store.migrationSource == .none)
        #expect(own.defaults.data(forKey: GlassLayerStore.stateKey) != nil, "default is persisted so later launches do not re-migrate")
    }

    @Test("glas.sh: windowOpacity, Boolean blurBackground, glassFrost")
    func glasSH() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.4, forKey: "windowOpacity")
        legacy.defaults.set(true, forKey: "blurBackground")   // the original toggle
        legacy.defaults.set("regular", forKey: "glassFrost")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.migrationSource == .glasSH)
        #expect(store.state == GlassLayerState(opacity: 0.4, frost: 1, material: .regular, paintsTheme: true))
    }

    @Test("glas.sh: legacy backgroundFill alias and glassMaterialStyle are honoured when canonical keys are absent")
    func glasSHLegacyAliases() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.25, forKey: "backgroundFill")
        legacy.defaults.set(0.5, forKey: "blurBackground")
        legacy.defaults.set("thick", forKey: "glassMaterialStyle")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.migrationSource == .glasSH)
        #expect(store.state == GlassLayerState(opacity: 0.25, frost: 0.5, material: .thick, paintsTheme: true))
    }

    @Test("glas.sh: canonical windowOpacity wins over backgroundFill, as SettingsManager resolves it")
    func glasSHCanonicalWins() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.9, forKey: "windowOpacity")
        legacy.defaults.set(0.1, forKey: "backgroundFill")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state.opacity == 0.9)
    }

    @Test("glas.sh: its own defaults apply for keys it never wrote")
    func glasSHDefaults() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set("thin", forKey: "glassFrost")   // only the frost picker was touched
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state == GlassLayerState(opacity: 0, frost: 1, material: .thin, paintsTheme: false))
    }

    @Test("glassdb: prefixed keys, slider blur, no material")
    func glassdb() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.7, forKey: "glassdb.windowOpacity")
        legacy.defaults.set(0.3, forKey: "glassdb.blurBackground")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.migrationSource == .glassdb)
        #expect(store.state == GlassLayerState(opacity: 0.7, frost: 0.3, material: .ultraThin, paintsTheme: true))
    }

    @Test("glassdb: its 0.95 default applies when only blur was set")
    func glassdbDefaultOpacity() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(false, forKey: "glassdb.blurBackground")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state == GlassLayerState(opacity: 0.95, frost: 0, material: .ultraThin, paintsTheme: true))
    }

    @Test("glassDT: display.glass.opacity and the frost stored under display.glass.material")
    func glassDT() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.6, forKey: "display.glass.opacity")
        legacy.defaults.set(0.2, forKey: "display.glass.material")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.migrationSource == .glassDT)
        #expect(store.state == GlassLayerState(opacity: 0.6, frost: 0.2, material: .ultraThin, paintsTheme: true))
    }

    @Test("glassDT: its defaults 1.0 / 0.25 apply for unset keys")
    func glassDTDefaults() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.5, forKey: "display.glass.material")
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state == GlassLayerState(opacity: 1, frost: 0.5, material: .ultraThin, paintsTheme: true))
    }

    @Test("Priority: glas.sh beats glassdb beats glassDT, and sources are not blended")
    func priority() {
        let own = DefaultsFixture(), a = DefaultsFixture(), b = DefaultsFixture()
        b.defaults.set(0.1, forKey: "windowOpacity")           // glas.sh, in the later suite
        a.defaults.set(0.7, forKey: "glassdb.windowOpacity")   // glassdb, in the earlier suite
        a.defaults.set(0.6, forKey: "display.glass.opacity")   // glassDT
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [a.defaults, b.defaults])
        #expect(store.migrationSource == .glasSH)
        #expect(store.state.opacity == 0.1)
        #expect(store.state.frost == 1, "glas.sh's blur default, not glassdb's 0.3 or glassDT's 0.25")

        let own2 = DefaultsFixture(), c = DefaultsFixture()
        c.defaults.set(0.7, forKey: "glassdb.windowOpacity")
        c.defaults.set(0.6, forKey: "display.glass.opacity")
        let second = GlassLayerStore(defaults: own2.defaults, legacyDefaults: [c.defaults])
        #expect(second.migrationSource == .glassdb)
    }

    @Test("Migration happens once: a stored state is never overwritten by legacy keys")
    func idempotent() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        legacy.defaults.set(0.4, forKey: "windowOpacity")
        let first = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(first.migrationSource == .glasSH)
        first.state = GlassLayerState(opacity: 0.9, frost: 0.1, material: .thick, paintsTheme: true)

        legacy.defaults.set(0.2, forKey: "windowOpacity")   // the old app keeps changing
        let second = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(second.state == GlassLayerState(opacity: 0.9, frost: 0.1, material: .thick, paintsTheme: true))
        #expect(second.migrationSource == .glasSH, "provenance survives relaunch")
    }

    @Test("Persistence round trip through the store, and reset returns to default")
    func persistence() {
        let own = DefaultsFixture()
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [])
        let custom = GlassLayerState(opacity: 0.33, frost: 0.66, material: .thin, paintsTheme: true)
        store.state = custom
        #expect(GlassLayerStore(defaults: own.defaults, legacyDefaults: []).state == custom)

        store.reset()
        #expect(store.state == .default)
        #expect(store.migrationSource == .none)
        #expect(GlassLayerStore(defaults: own.defaults, legacyDefaults: []).state == .default)
    }

    @Test("Assigning an equal state does not rewrite defaults")
    func equalAssignmentIsNoop() {
        let own = DefaultsFixture()
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [])
        let before = own.defaults.data(forKey: GlassLayerStore.stateKey)
        own.defaults.removeObject(forKey: GlassLayerStore.stateKey)
        store.state = store.state
        #expect(own.defaults.data(forKey: GlassLayerStore.stateKey) == nil)
        _ = before
    }

    @Test("Legacy value decoding mirrors SettingsManager: Booleans, numbers, garbage")
    func legacyValueDecoding() {
        #expect(GlassLayerLegacy.blurValue(true) == 1)
        #expect(GlassLayerLegacy.blurValue(false) == 0)
        #expect(GlassLayerLegacy.blurValue(0.35) == 0.35)
        #expect(GlassLayerLegacy.blurValue(NSNumber(value: 9)) == 1)
        #expect(GlassLayerLegacy.blurValue("frosted") == 0)
        #expect(GlassLayerLegacy.numericUnit(true) == nil, "a Boolean is never an opacity")
        #expect(GlassLayerLegacy.numericUnit(-2.0) == 0)
    }
}

@Suite("GlassLayer corrupt state (F7)", .serialized)
@MainActor
struct GlassLayerCorruptStateTests {
    @Test("Corrupt stored state → default, source none, legacy migration not re-run")
    func corruptStoredStateDoesNotRemigrate() {
        let own = DefaultsFixture(), legacy = DefaultsFixture()
        own.defaults.set(Data("not json".utf8), forKey: GlassLayerStore.stateKey)
        own.defaults.set(GlassLayerMigrationSource.glasSH.rawValue, forKey: GlassLayerStore.migrationKey)
        legacy.defaults.set(0.4, forKey: "windowOpacity")    // would migrate if consulted
        let store = GlassLayerStore(defaults: own.defaults, legacyDefaults: [legacy.defaults])
        #expect(store.state == .default)
        #expect(store.migrationSource == .none)
        let persisted = own.defaults.data(forKey: GlassLayerStore.stateKey).flatMap { try? JSONDecoder().decode(GlassLayerState.self, from: $0) }
        #expect(persisted == .default, "the corrupt value is replaced by the default, once")
    }
}
