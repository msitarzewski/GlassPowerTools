//
//  TerminalSessionOverride.swift
//  Glass Power Tools — GlassTerminal
//
//  The recovery manager is the shell's (GlassWindowRecoveryManager) since 2026-09-10; the
//  terminal keeps glas.sh's name and its appearance override here.
//
//  W20 (owner, 2026-10-09): "I was testing to see if there was a way to give a color/tint to the
//  tab group." The override was per live session, kept by session id, so it lasted only as long as
//  that connection, and each tab of a window could look different. It is now a terminal window's
//  look — a Mac terminal window, or a workgroup on Vision Pro, iPad and iPhone — shown by every tab
//  in the window, saved with the window and carried by a saved Workgroup (`LayoutPreset.look`).
//  The type keeps its name and its coding: the fields, their clamping and the legacy keys it reads
//  are what a window's look needs. Unset fields follow the terminal settings.
//
//  W22: a window keeps every setting it overrides as a `GlassWindowOverrides`; this type is now the
//  format of W20's five within it — what records keep under `look`, so a build from W20 on still
//  reads them (`TerminalWindowSettingsCoding`, `TerminalSessionOverride.windowSettings`).
//

import SwiftUI
import GlassShell

typealias WindowRecoveryManager = GlassWindowRecoveryManager

/// A terminal window's look (W20): each field set overrides the terminal setting of the same name,
/// and nil follows it. `nonisolated` so the records that carry it — a saved Workgroup's sync
/// record, a window's reopen record — can be coded off the main actor.
nonisolated struct TerminalSessionOverride: Codable, Hashable, Sendable {
    var glassFrost: String?
    var windowOpacity: Double?
    var blurBackground: Double?
    var interactiveGlass: Bool?
    var glassTint: String?

    /// Compatibility alias for payloads written by the short-lived
    /// backgroundFill schema.
    var backgroundFill: Double? {
        get { windowOpacity }
        set { windowOpacity = newValue }
    }

    init(
        glassFrost: String? = nil,
        windowOpacity: Double? = nil,
        blurBackground: Double? = nil,
        interactiveGlass: Bool? = nil,
        glassTint: String? = nil
    ) {
        self.glassFrost = glassFrost
        self.windowOpacity = Self.unitValue(windowOpacity)
        self.blurBackground = Self.unitValue(blurBackground)
        self.interactiveGlass = interactiveGlass
        self.glassTint = glassTint
    }

    private enum CodingKeys: String, CodingKey {
        case appearanceVersion
        case glassFrost
        case windowOpacity
        case blurBackground
        case interactiveGlass
        case glassTint
        case backgroundFill
        case interactiveGlassEffects
        case glassMaterialStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glassFrost = try container.decodeIfPresent(String.self, forKey: .glassFrost)
            ?? container.decodeIfPresent(String.self, forKey: .glassMaterialStyle)
        let opacityKey: CodingKeys? = container.contains(.windowOpacity)
            ? .windowOpacity
            : (container.contains(.backgroundFill) ? .backgroundFill : nil)
        if let opacityKey {
            if try container.decodeNil(forKey: opacityKey) {
                windowOpacity = nil
            } else if let value = try? container.decode(Double.self, forKey: opacityKey) {
                windowOpacity = Self.unitValue(value)
            } else {
                windowOpacity = 0
            }
        } else {
            windowOpacity = nil
        }

        if !container.contains(.blurBackground) {
            blurBackground = nil
        } else if try container.decodeNil(forKey: .blurBackground) {
            blurBackground = nil
        } else if let numericBlur = try? container.decode(Double.self, forKey: .blurBackground) {
            blurBackground = Self.unitValue(numericBlur)
        } else if let booleanBlur = try? container.decode(Bool.self, forKey: .blurBackground) {
            blurBackground = booleanBlur ? 1 : 0
        } else {
            blurBackground = 0
        }

        interactiveGlass = try container.decodeIfPresent(Bool.self, forKey: .interactiveGlass)
            ?? container.decodeIfPresent(Bool.self, forKey: .interactiveGlassEffects)
        glassTint = try container.decodeIfPresent(String.self, forKey: .glassTint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(2, forKey: .appearanceVersion)
        try container.encodeIfPresent(glassFrost, forKey: .glassFrost)
        try container.encodeIfPresent(Self.unitValue(windowOpacity), forKey: .windowOpacity)
        try container.encodeIfPresent(Self.unitValue(blurBackground), forKey: .blurBackground)
        try container.encodeIfPresent(interactiveGlass, forKey: .interactiveGlass)
        try container.encodeIfPresent(glassTint, forKey: .glassTint)
    }

    private static func unitValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    /// Nothing set: every field follows the terminal settings.
    var isEmpty: Bool { self == TerminalSessionOverride() }

    /// The look to keep: clamped, and nil when nothing is set, so a window whose look was reset
    /// keeps none and an empty look is never saved or synced.
    var normalized: TerminalSessionOverride? {
        var look = self
        look.canonicalizeAppearance()
        return look.isEmpty ? nil : look
    }

    /// A saved look, read leniently: one that can't be read costs its record the look, never the
    /// record itself — a window's tabs, a saved Workgroup from a newer build (W20).
    static func lenientlyDecoded<Key: CodingKey>(from container: KeyedDecodingContainer<Key>,
                                                 forKey key: Key) -> TerminalSessionOverride? {
        let decoded = try? container.decodeIfPresent(TerminalSessionOverride.self, forKey: key)
        return decoded?.normalized
    }

    mutating func canonicalizeAppearance() {
        if let windowOpacity {
            self.windowOpacity = windowOpacity.isFinite
                ? min(1, max(0, windowOpacity))
                : 0
        }
        if let blurBackground {
            self.blurBackground = blurBackground.isFinite
                ? min(1, max(0, blurBackground))
                : 0
        }
    }
}
