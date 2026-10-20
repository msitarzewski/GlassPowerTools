//
//  TerminalLooks.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal window's look beyond its glass (D84, the owner, 2026-10-20: "We look at these
//  terminals all day long, so I was hoping for some inspired ideas to keep them interesting"):
//  what it shows behind its text, a glow around its text, and a phosphor palette for the text
//  itself. Each is one of the window's settings (W22), so it is set in This Window, kept with the
//  window and its saved Workgroup, and reset with ↺.
//
//  Text first: everything here sits behind the text or around it, never over it, and a scrim
//  keeps the text readable over whatever is behind it (`TerminalReadability`).
//

import SwiftUI
import GlassLayers

// MARK: - The settings

/// What a window shows behind its terminals' text.
nonisolated enum TerminalBackdropStyle: String, CaseIterable, Identifiable, GlassWindowSettingValue {
    case none
    /// A picture the person chose, blurred, pixelated or toned as they like.
    case picture
    /// Falling columns of glyphs, quicker while the terminal prints.
    case rain
    /// A sunset over a grid that rolls toward you.
    case synthwave
    /// A phosphor screen: a glow in the text's colour, darker at the edges, with scanlines.
    case phosphor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .picture: "Picture"
        case .rain: "Digital Rain"
        case .synthwave: "Synthwave"
        case .phosphor: "Phosphor Screen"
        }
    }

    /// Moves, so it stops under Reduce Motion and in Low Power Mode.
    var isAnimated: Bool { self == .rain || self == .synthwave }
}

/// A colour for the text's glow: the text's own, or one of the classic phosphors and neons.
nonisolated enum TerminalGlowColor: String, CaseIterable, Identifiable, GlassWindowSettingValue {
    case text, green, amber, pink, cyan, purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text Color"
        case .green: "Green"
        case .amber: "Amber"
        case .pink: "Pink"
        case .cyan: "Cyan"
        case .purple: "Purple"
        }
    }

    /// The colour, given the text's.
    @MainActor func color(text: CodableColor) -> CodableColor {
        switch self {
        case .text: text
        case .green: TerminalPhosphor.green.primary
        case .amber: TerminalPhosphor.amber.primary
        case .pink: CodableColor(sRGBRed: 1, green: 0.443, blue: 0.808)
        case .cyan: CodableColor(sRGBRed: 0.004, green: 0.804, blue: 0.996)
        case .purple: CodableColor(sRGBRed: 0.725, green: 0.404, blue: 1)
        }
    }
}

nonisolated extension TerminalWindowSettings {
    static let backdrop = GlassWindowSetting<TerminalBackdropStyle>.choice("terminal.backdrop", title: "Background")
    /// The picture, by its name in this device's store (`TerminalBackgroundPictures`): never a
    /// path, since a saved Workgroup brings it from other devices.
    static let backdropPicture = GlassWindowSetting<String>("terminal.backdropPicture", title: "Picture") {
        TerminalBackgroundPictures.isName($0) ? $0 : nil
    }
    static let backdropIntensity = GlassWindowSetting<Double>.unit("terminal.backdropIntensity", title: "Intensity")
    static let backdropBlur = GlassWindowSetting<Double>.unit("terminal.backdropBlur", title: "Blur")
    static let backdropPixelate = GlassWindowSetting<Double>.unit("terminal.backdropPixelate", title: "Pixelate")
    static let backdropTone = GlassWindowSetting<Double>.unit("terminal.backdropTone", title: "Tone to Theme")
    static let backdropFollowsOutput = GlassWindowSetting<Bool>("terminal.backdropFollowsOutput",
                                                                title: "Quicken with Output")
    static let readability = GlassWindowSetting<Double>.unit("terminal.readability", title: "Readability")
    static let glow = GlassWindowSetting<Double>.unit("terminal.glow", title: "Text Glow")
    static let glowColor = GlassWindowSetting<TerminalGlowColor>.choice("terminal.glowColor", title: "Glow Color")
    static let phosphor = GlassWindowSetting<TerminalPhosphor>.choice("terminal.phosphor", title: "Text Palette")

    /// Every setting of a window's look (D84): what "Start from" replaces.
    static var lookStyleKeys: Set<String> {
        [backdrop.key, backdropPicture.key, backdropIntensity.key, backdropBlur.key, backdropPixelate.key,
         backdropTone.key, backdropFollowsOutput.key, readability.key, glow.key, glowColor.key, phosphor.key]
    }
}

// MARK: - A window's look, resolved

/// A window's look (D84) as its terminals draw it: its own settings over the defaults, which show
/// nothing new — a window that sets none looks as it always has.
nonisolated struct TerminalLookStyle: Equatable {
    var backdrop: TerminalBackdropStyle = .none
    var picture: String?
    var intensity: Double = 0.7
    var blur: Double = 0
    var pixelate: Double = 0
    var tone: Double = 0
    var followsOutput = true
    var readability: Double = 0.35
    var glow: Double = 0
    var glowColor: TerminalGlowColor = .text
    var phosphor: TerminalPhosphor = .none

    static func resolved(_ window: GlassWindowOverrides) -> TerminalLookStyle {
        var style = TerminalLookStyle()
        style.backdrop = window[TerminalWindowSettings.backdrop] ?? style.backdrop
        style.picture = window[TerminalWindowSettings.backdropPicture]
        style.intensity = window[TerminalWindowSettings.backdropIntensity] ?? style.intensity
        style.blur = window[TerminalWindowSettings.backdropBlur] ?? style.blur
        style.pixelate = window[TerminalWindowSettings.backdropPixelate] ?? style.pixelate
        style.tone = window[TerminalWindowSettings.backdropTone] ?? style.tone
        style.followsOutput = window[TerminalWindowSettings.backdropFollowsOutput] ?? style.followsOutput
        style.readability = window[TerminalWindowSettings.readability] ?? style.readability
        style.glow = window[TerminalWindowSettings.glow] ?? style.glow
        style.glowColor = window[TerminalWindowSettings.glowColor] ?? style.glowColor
        style.phosphor = window[TerminalWindowSettings.phosphor] ?? style.phosphor
        return style
    }

    /// Whether anything is drawn behind the text.
    var drawsBackdrop: Bool {
        switch backdrop {
        case .none: false
        case .picture: picture != nil && intensity > 0
        default: intensity > 0
        }
    }
}

// MARK: - Starting points

/// Looks to start from in This Window: each sets the whole look, which can then be changed.
nonisolated enum TerminalLookPreset: String, CaseIterable, Identifiable {
    case digitalRain, synthwave, amberPhosphor, greenPhosphor, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digitalRain: "Digital Rain"
        case .synthwave: "Synthwave"
        case .amberPhosphor: "Amber Phosphor"
        case .greenPhosphor: "Green Phosphor"
        case .clear: "None"
        }
    }

    /// `window` with this look in place of its own, every other setting kept. A picture the window
    /// shows stays chosen, so returning to Picture finds it.
    func applied(to window: GlassWindowOverrides) -> GlassWindowOverrides {
        var result = window.removing(TerminalWindowSettings.lookStyleKeys.subtracting([TerminalWindowSettings.backdropPicture.key]))
        switch self {
        case .digitalRain:
            result[TerminalWindowSettings.backdrop] = .rain
            result[TerminalWindowSettings.backdropIntensity] = 0.65
            result[TerminalWindowSettings.phosphor] = .matrix
            result[TerminalWindowSettings.glow] = 0.5
            result[TerminalWindowSettings.readability] = 0.3
        case .synthwave:
            result[TerminalWindowSettings.backdrop] = .synthwave
            result[TerminalWindowSettings.backdropIntensity] = 0.85
            result[TerminalWindowSettings.phosphor] = .vaporwave
            result[TerminalWindowSettings.glow] = 0.45
            result[TerminalWindowSettings.glowColor] = .pink
            result[TerminalWindowSettings.readability] = 0.2
        case .amberPhosphor:
            result[TerminalWindowSettings.backdrop] = .phosphor
            result[TerminalWindowSettings.phosphor] = .amber
            result[TerminalWindowSettings.glow] = 0.55
        case .greenPhosphor:
            result[TerminalWindowSettings.backdrop] = .phosphor
            result[TerminalWindowSettings.phosphor] = .green
            result[TerminalWindowSettings.glow] = 0.55
        case .clear:
            break
        }
        return result
    }
}

// MARK: - Phosphor palettes

/// The text in one phosphor's colours (D84): every colour a program draws becomes a shade of the
/// phosphor by its brightness, keeping a little of its own hue so red still reads as different from
/// blue; or, for Vaporwave, the sixteen colours in a neon palette.
nonisolated enum TerminalPhosphor: String, CaseIterable, Identifiable, GlassWindowSettingValue {
    case none, green, amber, matrix, vaporwave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Theme's Own"
        case .green: "Green Phosphor"
        case .amber: "Amber Phosphor"
        case .matrix: "Digital Green"
        case .vaporwave: "Vaporwave"
        }
    }

    @MainActor var primary: CodableColor {
        switch self {
        case .none: CodableColor(sRGBRed: 1, green: 1, blue: 1)
        case .green: CodableColor(sRGBRed: 0.2, green: 1, blue: 0.4)
        case .amber: CodableColor(sRGBRed: 1, green: 0.69, blue: 0)
        case .matrix: CodableColor(sRGBRed: 0, green: 1, blue: 0.255)
        case .vaporwave: CodableColor(sRGBRed: 1, green: 0.545, blue: 0.878)
        }
    }

    /// How much of a colour's own saturation a monochrome phosphor keeps, so red still reads as
    /// different from blue.
    static let keptHue = 0.15

    /// One colour for all the text: green, amber and digital green. A filter over the drawn text
    /// makes every colour a shade of it (`terminalPhosphor`) — the sixteen a theme names and the
    /// 24-bit colours programs such as btop draw with, which no palette reaches.
    var isMonochrome: Bool { self == .green || self == .amber || self == .matrix }

    /// `theme` in this palette; its background, which the window's glass shows through, is kept.
    /// Vaporwave's neon is a palette; a monochrome phosphor leaves the theme to its filter.
    @MainActor func applied(to theme: TerminalTheme) -> TerminalTheme {
        guard self == .vaporwave else { return theme }
        var result = theme
        result.foreground = primary
        result.cursor = primary
        result.selection = CodableColor(sRGBRed: primary.red, green: primary.green, blue: primary.blue, alpha: 0.3)
        result.setANSIColors(Self.vaporwaveANSI)
        return result
    }

    /// The colour the text shows in: the phosphor's, or the theme's own.
    @MainActor func textColor(theme: TerminalTheme) -> CodableColor {
        isMonochrome ? primary : theme.foreground
    }

    /// Black, red, green, yellow, blue, magenta, cyan, white, then their bright forms, in neon.
    @MainActor static let vaporwaveANSI: [CodableColor] = [
        (0.141, 0.090, 0.204), (1, 0.361, 0.541), (0.020, 1, 0.631), (1, 0.984, 0.588),
        (0.482, 0.549, 1), (1, 0.443, 0.808), (0.004, 0.804, 0.996), (0.910, 0.878, 1),
        (0.420, 0.357, 0.549), (1, 0.545, 0.678), (0.396, 1, 0.765), (1, 0.992, 0.765),
        (0.639, 0.686, 1), (1, 0.631, 0.890), (0.459, 0.886, 1), (1, 1, 1),
    ].map { CodableColor(sRGBRed: $0.0, green: $0.1, blue: $0.2) }
}

extension TerminalTheme {
    /// Sets the sixteen ANSI colours, in `ansiColors`' order.
    mutating func setANSIColors(_ colors: [CodableColor]) {
        guard colors.count == 16 else { return }
        black = colors[0]; red = colors[1]; green = colors[2]; yellow = colors[3]
        blue = colors[4]; magenta = colors[5]; cyan = colors[6]; white = colors[7]
        brightBlack = colors[8]; brightRed = colors[9]; brightGreen = colors[10]; brightYellow = colors[11]
        brightBlue = colors[12]; brightMagenta = colors[13]; brightCyan = colors[14]; brightWhite = colors[15]
    }
}

// MARK: - Readability

/// How much scrim keeps text readable over what is behind it (D84): enough that the text's
/// contrast against the background reaches WCAG's 4.5:1 for body text, and never less than the
/// window's own Readability.
nonisolated enum TerminalReadability {
    static let minimumContrast = 4.5

    /// Relative luminance (WCAG 2), from sRGB.
    @MainActor static func luminance(_ color: CodableColor) -> Double {
        luminance(red: color.red, green: color.green, blue: color.blue)
    }

    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Dim text — SGR 2, the faint lines agents print — reads at about this share of the text's own
    /// colour; it needs less contrast than body text, but some.
    static let dimShare = 0.55
    static let minimumDimContrast = 2.5

    /// The luminance of dim text in a theme whose text is `text`.
    @MainActor static func dimLuminance(of text: CodableColor) -> Double {
        luminance(red: text.red * dimShare, green: text.green * dimShare, blue: text.blue * dimShare)
    }

    /// The brightest a backdrop may be under light text (relative luminance), before a scrim of
    /// luminance `scrim` at `opacity`: text of luminance `text` keeps 4.5:1 over it and dim text of
    /// luminance `dim` 2.5:1. Nil for dark text over a light scrim, which a ceiling can't help.
    static func ceiling(text: Double, dim: Double, scrim: Double, opacity: Double) -> Double? {
        guard text > scrim else { return nil }
        let body = (text + 0.05) / minimumContrast - 0.05
        let faint = (dim + 0.05) / minimumDimContrast - 0.05
        let shown = max(0, min(body, faint))
        let covered = min(1, max(0, opacity))
        guard covered < 1 else { return 1 }
        return min(1, max(0.005, (shown - scrim * covered) / (1 - covered)))
    }

    /// The scrim's opacity: the window's `minimum`, raised until text of luminance `text` reaches
    /// the minimum contrast over a background of luminance `background` under a scrim of luminance
    /// `scrim`. 1 when even a full scrim falls short.
    static func scrimOpacity(background: Double, text: Double, scrim: Double, minimum: Double) -> Double {
        let floor = min(1, max(0, minimum))
        func shown(_ opacity: Double) -> Double { background * (1 - opacity) + scrim * opacity }
        guard contrast(text, shown(floor)) < minimumContrast else { return floor }
        // The contrast grows as the scrim moves the background away from the text: solve for the
        // background luminance that reaches it, then for the opacity that gives that.
        let lightText = text > scrim
        let target = lightText
            ? (text + 0.05) / minimumContrast - 0.05
            : minimumContrast * (text + 0.05) - 0.05
        guard abs(background - scrim) > 0.0001 else { return 1 }
        let needed = (background - target) / (background - scrim)
        return min(1, max(floor, needed))
    }
}
