import Foundation

/// Which of the three source applications a migrated layer state came from, if any.
public enum GlassLayerMigrationSource: String, Codable, Sendable, CaseIterable {
    case glasSH = "glas.sh"
    case glassdb = "glassdb"
    case glassDT = "glassDT"
    case none = "none"
}

/// Read-side migration of the three applications' layer preferences.
///
/// Keys and defaults were read from the source applications on 2026-09-10:
/// - glas.sh: `windowOpacity` (default 0.0), legacy alias `backgroundFill`, `blurBackground`
///   (default 1.0, may be a Boolean from the original toggle), `glassFrost` (default `ultraThin`),
///   older key `glassMaterialStyle`. `../glas.sh/glas.sh/Constants.swift:25-31,53`,
///   `SettingsManager.swift:167-171,279-294,427-436`.
/// - glassdb: `glassdb.windowOpacity` (default 0.95), `glassdb.blurBackground` (default 1.0, may
///   be Boolean). `../glassdb/glassdb/Constants.swift:27-28`, `SettingsManager.swift:112-113,183-196`.
/// - glassDT: `display.glass.opacity` (default 1.0) and, under the key `display.glass.material`,
///   the frost amount (default 0.25). `../glassDT/Sources/GlassDesktopUI/DesktopSettingsView.swift:5-8,43-44`.
///
/// Priority is glas.sh, then glassdb, then glassDT: glas.sh is the application the user works in
/// most and its look is the one decision D2 adopts. The key sets do not collide, so the first
/// source with any of its keys present wins whole; sources are not blended.
enum GlassLayerLegacy {
    enum GlasSH {
        static let windowOpacity = "windowOpacity"
        static let backgroundFill = "backgroundFill"
        static let blurBackground = "blurBackground"
        static let glassFrost = "glassFrost"
        static let glassMaterialStyle = "glassMaterialStyle"
        static let keys = [windowOpacity, backgroundFill, blurBackground, glassFrost, glassMaterialStyle]
    }
    enum Glassdb {
        static let windowOpacity = "glassdb.windowOpacity"
        static let blurBackground = "glassdb.blurBackground"
        static let keys = [windowOpacity, blurBackground]
    }
    enum GlassDT {
        static let opacity = "display.glass.opacity"
        static let frost = "display.glass.material"
        static let keys = [opacity, frost]
    }

    /// Bundle identifiers whose standard domains are read best-effort on macOS. Under App Sandbox
    /// these reads come back empty; the App Group suite is the only guaranteed shared store.
    static let legacyBundleIdentifiers = ["sh.glas.app", "app.glassdb", "app.glassdt"]
    static let appGroupSuite = GlassAppIdentity.appGroup

    static func migrate(from suites: [UserDefaults]) -> (GlassLayerState, GlassLayerMigrationSource) {
        for suite in suites {
            if let state = glasSH(in: suite) { return (state, .glasSH) }
        }
        for suite in suites {
            if let state = glassdb(in: suite) { return (state, .glassdb) }
        }
        for suite in suites {
            if let state = glassDT(in: suite) { return (state, .glassDT) }
        }
        return (.default, .none)
    }

    static func glasSH(in suite: UserDefaults) -> GlassLayerState? {
        guard GlasSH.keys.contains(where: { suite.object(forKey: $0) != nil }) else { return nil }
        let canonical = suite.object(forKey: GlasSH.windowOpacity)
        let legacy = suite.object(forKey: GlasSH.backgroundFill)
        let opacity = (canonical ?? legacy).flatMap(numericUnit) ?? 0
        let frost = suite.object(forKey: GlasSH.blurBackground).map(blurValue) ?? 1
        let materialRaw = suite.string(forKey: GlasSH.glassFrost) ?? suite.string(forKey: GlasSH.glassMaterialStyle)
        // An absent material key is not a user choice, so it takes our default — the same rule
        // `GlassLayerState`'s decoder uses. Only the sliders below carry an explicit choice across.
        let material = materialRaw.flatMap(GlassLayerMaterial.init(rawValue:)) ?? GlassLayerState.default.material
        return GlassLayerState(opacity: opacity, frost: frost, material: material)
    }

    static func glassdb(in suite: UserDefaults) -> GlassLayerState? {
        guard Glassdb.keys.contains(where: { suite.object(forKey: $0) != nil }) else { return nil }
        let opacity = suite.object(forKey: Glassdb.windowOpacity).flatMap(numericUnit) ?? 0.95
        let frost = suite.object(forKey: Glassdb.blurBackground).map(blurValue) ?? 1
        // glassdb had no material control, so there is no choice to preserve.
        return GlassLayerState(opacity: opacity, frost: frost, material: GlassLayerState.default.material)
    }

    static func glassDT(in suite: UserDefaults) -> GlassLayerState? {
        guard GlassDT.keys.contains(where: { suite.object(forKey: $0) != nil }) else { return nil }
        let opacity = suite.object(forKey: GlassDT.opacity).flatMap(numericUnit) ?? 1
        let frost = suite.object(forKey: GlassDT.frost).flatMap(numericUnit) ?? 0.25
        // glassDT likewise had no material control.
        return GlassLayerState(opacity: opacity, frost: frost, material: GlassLayerState.default.material)
    }

    /// The original blur setting was a Boolean toggle; later builds store a slider value.
    /// Mirrors `SettingsManager.resolvedBlurBackground` in both glas.sh and glassdb.
    static func blurValue(_ value: Any) -> Double {
        if isBoolean(value) { return (value as? Bool) == true ? 1 : 0 }
        return numericUnit(value) ?? 0
    }

    static func numericUnit(_ value: Any) -> Double? {
        guard !isBoolean(value), let number = value as? NSNumber else { return nil }
        return GlassLayerState.unit(number.doubleValue)
    }

    static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
