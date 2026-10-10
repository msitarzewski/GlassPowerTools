//
//  GlassWindowOverrides.swift
//  Glass Power Tools — GlassLayers
//
//  W22 (owner, 2026-10-10, on the Vision Pro): "the original idea was that anything in the system
//  settings could be overridden per window." Asked which windows, he chose every kind now:
//  terminal, editor, database and remote desktop.
//
//  One mechanism for all of them. A window keeps a `GlassWindowOverrides`: only the settings it
//  sets, each under a stable key, each resolved as **the window's value, else the setting's**. A
//  capability declares the settings a window may override as `GlassWindowSetting` constants; the
//  window keeps its overrides in its own records (`GlassWindowOverrides` is `Codable`); its views
//  resolve each value with `overrides.value(of:over:)`; and its This Window page builds one
//  `GlassWindowSettingRow` per setting (`GlassWindowSettingRows.swift`).
//
//  Why here: GlassLayers is the one module the shell and every capability import, and it owns the
//  one setting every Glass window already shares — Appearance (`GlassLayerState`), which a window
//  overrides through the same keys (`GlassLayerSettings`). `GlassLayeredWindow` reads the window's
//  overrides from the environment (`glassWindowOverrides(_:)`), so a window's glass changes alone.
//

import SwiftUI

// MARK: - What one setting holds

/// What a window keeps for one setting, as it is stored: a switch, a number or a text. A
/// setting's own type (`GlassWindowSettingValue`) converts to and from it, so an overlay can hold
/// any capability's settings, be coded as one flat JSON object, and keep keys it doesn't know.
public enum GlassWindowOverrideValue: Hashable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
}

extension GlassWindowOverrideValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // JSON's true and false only: a number never reads as a switch, nor a switch as a number.
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self), number.isFinite {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else {
            throw DecodingError.typeMismatch(
                GlassWindowOverrideValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "A window setting is a switch, a number or a text."))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// A type a window setting can have. `Bool`, `Double`, `Int`, `String` and any `String`-backed
/// enum (`GlassLayerMaterial`, a capability's own choices) already are.
public protocol GlassWindowSettingValue: Equatable, Sendable {
    /// The stored value as this type, or nil when it is some other kind.
    init?(glassWindowValue: GlassWindowOverrideValue)
    var glassWindowValue: GlassWindowOverrideValue { get }
}

extension Bool: GlassWindowSettingValue {
    public init?(glassWindowValue: GlassWindowOverrideValue) {
        guard case .bool(let value) = glassWindowValue else { return nil }
        self = value
    }
    public var glassWindowValue: GlassWindowOverrideValue { .bool(self) }
}

extension Double: GlassWindowSettingValue {
    public init?(glassWindowValue: GlassWindowOverrideValue) {
        guard case .number(let value) = glassWindowValue, value.isFinite else { return nil }
        self = value
    }
    public var glassWindowValue: GlassWindowOverrideValue { .number(self) }
}

extension Int: GlassWindowSettingValue {
    public init?(glassWindowValue: GlassWindowOverrideValue) {
        guard case .number(let value) = glassWindowValue, let whole = Int(exactly: value.rounded()) else { return nil }
        self = whole
    }
    public var glassWindowValue: GlassWindowOverrideValue { .number(Double(self)) }
}

extension String: GlassWindowSettingValue {
    public init?(glassWindowValue: GlassWindowOverrideValue) {
        guard case .string(let value) = glassWindowValue else { return nil }
        self = value
    }
    public var glassWindowValue: GlassWindowOverrideValue { .string(self) }
}

public extension GlassWindowSettingValue where Self: RawRepresentable, RawValue == String {
    init?(glassWindowValue: GlassWindowOverrideValue) {
        guard case .string(let raw) = glassWindowValue else { return nil }
        self.init(rawValue: raw)
    }
    var glassWindowValue: GlassWindowOverrideValue { .string(rawValue) }
}

extension GlassLayerMaterial: GlassWindowSettingValue {}

// MARK: - Declaring a setting

/// One setting a window may override: the key it is stored under, its name, and the check every
/// value passes — on the way in and on the way out, since a record can come from another device.
///
/// A capability declares its settings as constants, once, and everything else is built from them:
///
/// ```swift
/// enum EditorWindowSettings {
///     static let fontSize = GlassWindowSetting<Double>("editor.fontSize", title: "Font Size") {
///         $0.isFinite ? min(36, max(8, $0.rounded())) : nil
///     }
/// }
/// ```
///
/// Keys are stable forever (they are stored, and they sync): `<capability>.<setting>`, or
/// `appearance.*` for the ones every window shares (`GlassLayerSettings`).
public struct GlassWindowSetting<Value: GlassWindowSettingValue>: Sendable {
    public let key: String
    public let title: String
    private let check: @Sendable (Value) -> Value?

    /// - Parameter check: the value to keep for `value`, or nil to keep none (out of the
    ///   setting's range and not clampable, or not one of its choices). Defaults to keeping it.
    public init(_ key: String, title: String, check: @escaping @Sendable (Value) -> Value? = { $0 }) {
        self.key = key
        self.title = title
        self.check = check
    }

    /// `value` as this setting keeps it, or nil when it keeps none.
    public func checked(_ value: Value) -> Value? { check(value) }
}

public extension GlassWindowSetting where Value == Double {
    /// A fraction, 0…1, clamped; not-a-number keeps nothing.
    static func unit(_ key: String, title: String) -> GlassWindowSetting<Double> {
        GlassWindowSetting(key, title: title) { $0.isFinite ? min(1, max(0, $0)) : nil }
    }
}

public extension GlassWindowSetting where Value: CaseIterable {
    /// One of the type's own cases, which is all its stored value can decode to anyway.
    static func choice(_ key: String, title: String) -> GlassWindowSetting<Value> {
        GlassWindowSetting(key, title: title)
    }
}

// MARK: - One window's overrides

/// One window's settings over the global ones: only those the window sets.
///
/// Each value resolves as the window's, else the setting's (`value(of:over:)`). An empty overlay is
/// the window following every setting, and is never stored (`encodeIfNotEmpty`). Coded as one flat
/// JSON object, read leniently: a record that holds something unreadable loses only that entry,
/// never the record; and keys this build doesn't know are kept, so a setting a newer build added
/// survives this one saving the record again.
public struct GlassWindowOverrides: Hashable, Sendable {
    /// More than any window sets. A longer record was not written by this app.
    public static let maximumCount = 64
    public static let maximumKeyLength = 64
    /// The longest text a window keeps for a setting: a theme's identifier, a font's name, a colour.
    public static let maximumTextLength = 256

    /// What the window sets, by key.
    public private(set) var values: [String: GlassWindowOverrideValue]

    public init() { values = [:] }

    /// Nothing set: the window follows every setting.
    public var isEmpty: Bool { values.isEmpty }
    public var keys: Set<String> { Set(values.keys) }

    /// The window's value for `setting`, or nil when it follows the setting. Set it to nil to
    /// follow the setting again; a value the setting's check refuses is the same as nil.
    public subscript<Value>(setting: GlassWindowSetting<Value>) -> Value? {
        get {
            values[setting.key].flatMap(Value.init(glassWindowValue:)).flatMap(setting.checked)
        }
        set {
            guard let newValue, let kept = setting.checked(newValue), Self.fits(setting.key, kept.glassWindowValue),
                  values[setting.key] != nil || values.count < Self.maximumCount else {
                values.removeValue(forKey: setting.key)
                return
            }
            values[setting.key] = kept.glassWindowValue
        }
    }

    /// The value a window uses: its own, else `global`.
    public func value<Value>(of setting: GlassWindowSetting<Value>, over global: Value) -> Value {
        self[setting] ?? global
    }

    /// Whether the window sets `setting` to a value it can use.
    public func sets<Value>(_ setting: GlassWindowSetting<Value>) -> Bool { self[setting] != nil }

    /// The window follows `key`'s setting again.
    public mutating func reset(_ key: String) { values.removeValue(forKey: key) }

    /// Only the entries under `keys`.
    public func restricted(to keys: some Sequence<String>) -> GlassWindowOverrides {
        let kept = Set(keys)
        var result = GlassWindowOverrides()
        result.values = values.filter { kept.contains($0.key) }
        return result
    }

    /// Every entry except those under `keys`.
    public func removing(_ keys: some Sequence<String>) -> GlassWindowOverrides {
        let dropped = Set(keys)
        var result = GlassWindowOverrides()
        result.values = values.filter { !dropped.contains($0.key) }
        return result
    }

    /// These entries with `other`'s over them, where both set one.
    public func merging(_ other: GlassWindowOverrides) -> GlassWindowOverrides {
        var result = self
        for (key, value) in other.values where result.values[key] != nil || result.values.count < Self.maximumCount {
            result.values[key] = value
        }
        return result
    }

    private static func fits(_ key: String, _ value: GlassWindowOverrideValue) -> Bool {
        guard !key.isEmpty, key.count <= maximumKeyLength else { return false }
        switch value {
        case .string(let text): return text.count <= maximumTextLength
        case .number(let number): return number.isFinite
        case .bool: return true
        }
    }
}

extension GlassWindowOverrides: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Never throws: anything that isn't an object is a window that sets nothing, an entry that
    /// isn't a switch, number or text is dropped, and the rest is kept, up to `maximumCount`.
    public init(from decoder: any Decoder) {
        self.init()
        guard let container = try? decoder.container(keyedBy: Key.self) else { return }
        for key in container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            guard values.count < Self.maximumCount,
                  let value = try? container.decode(GlassWindowOverrideValue.self, forKey: key),
                  Self.fits(key.stringValue, value) else { continue }
            values[key.stringValue] = value
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for key in values.keys.sorted() {
            try container.encode(values[key], forKey: Key(stringValue: key))
        }
    }

    /// A window's overrides from a record, leniently: absent, or unreadable, is a window that sets
    /// nothing — never a record that fails to read.
    public static func lenientlyDecoded<K: CodingKey>(from container: KeyedDecodingContainer<K>,
                                                      forKey key: K) -> GlassWindowOverrides {
        ((try? container.decodeIfPresent(GlassWindowOverrides.self, forKey: key)) ?? nil) ?? GlassWindowOverrides()
    }
}

public extension KeyedEncodingContainer {
    /// A window's overrides into a record, only when it sets something: an empty overlay is never
    /// stored or synced.
    mutating func encodeIfNotEmpty(_ overrides: GlassWindowOverrides, forKey key: Key) throws {
        guard !overrides.isEmpty else { return }
        try encode(overrides, forKey: key)
    }
}

// MARK: - The window's overrides, for everything drawn in it

private struct GlassWindowOverridesKey: EnvironmentKey {
    static let defaultValue = GlassWindowOverrides()
}

public extension EnvironmentValues {
    /// The overrides of the window a view is in: set once at the window's root, read by
    /// `GlassLayeredWindow` and `GlassLayeredPanel` for its glass, and by a capability's views for
    /// their own settings. Empty outside a window that keeps any.
    var glassWindowOverrides: GlassWindowOverrides {
        get { self[GlassWindowOverridesKey.self] }
        set { self[GlassWindowOverridesKey.self] = newValue }
    }
}

public extension View {
    /// Draws this window's content with `overrides` over the settings: its glass (`GlassLayeredWindow`)
    /// and whatever its views resolve from `\.glassWindowOverrides`.
    func glassWindowOverrides(_ overrides: GlassWindowOverrides) -> some View {
        environment(\.glassWindowOverrides, overrides)
    }
}

// MARK: - Appearance, per window

/// Settings ▸ Appearance, as a window overrides it: the three dimensions of `GlassLayerState`.
/// Every kind of window shares these keys, so a window's glass reads the same however it was set.
public enum GlassLayerSettings {
    /// Theme paint behind content, 0…1 (Appearance ▸ Opacity).
    public static let opacity = GlassWindowSetting<Double>.unit("appearance.opacity", title: "Opacity")
    /// Strength of the frost material, 0…1 (Appearance ▸ Frost).
    public static let frost = GlassWindowSetting<Double>.unit("appearance.frost", title: "Frost")
    /// Which material the frost is (Appearance ▸ Material).
    public static let material = GlassWindowSetting<GlassLayerMaterial>.choice("appearance.material", title: "Material")

    public static var keys: Set<String> { [opacity.key, frost.key, material.key] }
}

public extension GlassLayerState {
    /// This state with a window's Appearance overrides over it, field by field.
    func overlaid(by overrides: GlassWindowOverrides) -> GlassLayerState {
        GlassLayerState(opacity: overrides.value(of: GlassLayerSettings.opacity, over: opacity),
                        frost: overrides.value(of: GlassLayerSettings.frost, over: frost),
                        material: overrides.value(of: GlassLayerSettings.material, over: material))
    }
}
