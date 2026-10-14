//
//  TerminalClearBlacks.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Black backgrounds show the glass (the owner, 2026-10-13: "btop's black is black and not
//  transparent. how can we ensure that the blacks are transparent? the other colors are fine at
//  100%").
//
//  SwiftTerm leaves a cell clear only when its background is the default one. A program that paints
//  black itself — btop's truecolor `48;2;0;0;0`, `40`, `48;5;16` — gets solid black blocks over the
//  window's glass, at any Opacity. kitty answers the same complaint with
//  `transparent_background_colors`; here it is the rule rather than a list: a background that
//  resolves to pure black (under a dark theme), or to the theme's own background colour, becomes the
//  default background (`49`) before SwiftTerm reads it, so the cell shows what an empty terminal
//  shows. Every other colour stays solid. Foregrounds are never touched, so black text stays black.
//
//  It works on the byte stream because SwiftTerm decides a cell's opacity inside its renderers
//  (CoreGraphics and Metal alike), which this package uses as released. Only SGR sequences
//  (`CSI … m` with no private marker or intermediate) are rewritten, and an unchanged sequence goes
//  through byte for byte. A sequence cut by the end of a chunk is held for the next one.
//

import Foundation

struct TerminalClearBlacks {
    struct RGB: Hashable {
        let red: UInt8, green: UInt8, blue: UInt8
        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red; self.green = green; self.blue = blue
        }
        init(red: Double, green: Double, blue: Double) {
            func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
            self.init(byte(red), byte(green), byte(blue))
        }
    }

    static let black = RGB(0, 0, 0)
    /// The longest escape sequence held across chunks; anything longer is not an SGR worth reading.
    static let pendingLimit = 256

    /// The first sixteen colours as the theme draws them. xterm's until a theme says otherwise.
    private(set) var palette: [RGB] = TerminalClearBlacks.xtermPalette
    /// Backgrounds that show the glass.
    private(set) var clearColors: Set<RGB> = [TerminalClearBlacks.black]
    private var pending: [UInt8] = []

    /// Follows the theme: its sixteen colours, and its background, which shows the glass too.
    ///
    /// **Black only under a dark theme.** On a light one the glass is light, and a program that
    /// paints black behind light text — btop does — would be left with light text on a light
    /// background. There only the theme's own background colour is cleared.
    mutating func configure(ansi: [(red: Double, green: Double, blue: Double)],
                            background: (red: Double, green: Double, blue: Double)) {
        palette = ansi.count == 16 ? ansi.map { RGB(red: $0.red, green: $0.green, blue: $0.blue) } : Self.xtermPalette
        let luminance = 0.2126 * background.red + 0.7152 * background.green + 0.0722 * background.blue
        clearColors = [RGB(red: background.red, green: background.green, blue: background.blue)]
        if luminance < 0.5 { clearColors.insert(Self.black) }
    }

    mutating func configure(_ theme: SwiftTermTheme) {
        configure(ansi: theme.ansiColors.map { ($0.red, $0.green, $0.blue) },
                  background: (theme.background.red, theme.background.green, theme.background.blue))
    }

    /// The bytes SwiftTerm should read. The input itself when nothing changed, which is nearly always.
    mutating func filter(_ input: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        let bytes: ArraySlice<UInt8>
        if pending.isEmpty {
            // The common case: no escape sequence at all.
            guard input.contains(0x1B) else { return input }
            bytes = input
        } else {
            bytes = ArraySlice(pending + input)
            pending.removeAll(keepingCapacity: true)
        }

        var output: [UInt8]?
        var copiedUpTo = bytes.startIndex
        var end = bytes.endIndex
        var index = bytes.startIndex
        scan: while index < end {
            guard let escape = bytes[index..<end].firstIndex(of: 0x1B) else { break }
            // ESC, then '['.
            guard escape + 1 < end else {
                hold(bytes[escape..<end], end: &end, at: escape)
                break scan
            }
            guard bytes[escape + 1] == 0x5B else { index = escape + 1; continue }
            var parameterEnd = escape + 2
            while parameterEnd < end, (0x30...0x3F).contains(bytes[parameterEnd]) { parameterEnd += 1 }
            var finalIndex = parameterEnd
            while finalIndex < end, (0x20...0x2F).contains(bytes[finalIndex]) { finalIndex += 1 }
            guard finalIndex < end else {
                // Cut by the end of the chunk: held, unless it is too long to be an SGR.
                if end - escape <= Self.pendingLimit { hold(bytes[escape..<end], end: &end, at: escape) }
                break scan
            }
            let final = bytes[finalIndex]
            guard (0x40...0x7E).contains(final) else { index = finalIndex; continue }
            index = finalIndex + 1
            let parameters = bytes[(escape + 2)..<parameterEnd]
            // SGR only: final 'm', no intermediates, no private marker ('<', '=', '>', '?').
            guard final == 0x6D, finalIndex == parameterEnd,
                  !(parameters.first.map { (0x3C...0x3F).contains($0) } ?? false),
                  let rewritten = rewrite(parameters) else { continue }
            if output == nil { output = []; output?.reserveCapacity(bytes.count) }
            output?.append(contentsOf: bytes[copiedUpTo..<(escape + 2)])
            output?.append(contentsOf: rewritten)
            copiedUpTo = parameterEnd
        }
        guard var output else { return bytes[bytes.startIndex..<end] }
        output.append(contentsOf: bytes[copiedUpTo..<end])
        return output[...]
    }

    private mutating func hold(_ tail: ArraySlice<UInt8>, end: inout ArraySlice<UInt8>.Index, at escape: Int) {
        pending = Array(tail)
        end = escape
    }

    /// The parameters with every clear background replaced by `49`, or nil when nothing changed.
    func rewrite(_ parameters: ArraySlice<UInt8>) -> [UInt8]? {
        let parts = parameters.split(separator: 0x3B, omittingEmptySubsequences: false)
        var result: [ArraySlice<UInt8>] = []
        result.reserveCapacity(parts.count)
        let defaultBackground: ArraySlice<UInt8> = [0x34, 0x39]  // "49"
        var changed = false
        var index = 0
        while index < parts.count {
            let part = parts[index]
            if part.contains(0x3A) {
                // The colon form carries its colour in one parameter: 48:5:n, 48:2:r:g:b, 48:2:cs:r:g:b.
                let sub = part.split(separator: 0x3A, omittingEmptySubsequences: false)
                if Self.number(sub[0]) == 48, let color = colonColor(Array(sub)), clearColors.contains(color) {
                    result.append(defaultBackground); changed = true
                } else {
                    result.append(part)
                }
                index += 1
                continue
            }
            switch Self.number(part) {
            case .some(let code) where (40...47).contains(code) || (100...107).contains(code):
                let paletteIndex = code < 100 ? code - 40 : code - 100 + 8
                if clearColors.contains(palette[paletteIndex]) {
                    result.append(defaultBackground); changed = true
                } else {
                    result.append(part)
                }
                index += 1
            case .some(let code) where code == 38 || code == 48 || code == 58:
                // An extended colour: 5;n or 2;r;g;b. A foreground's or underline's is copied whole,
                // so its numbers are never read as codes of their own (38;5;40 is not a background).
                let mode = index + 1 < parts.count ? Self.number(parts[index + 1]) : nil
                let length = mode == 5 ? 3 : mode == 2 ? 5 : 1
                guard index + length <= parts.count else {
                    result.append(contentsOf: parts[index...]); index = parts.count; continue
                }
                let span = parts[index..<(index + length)]
                if code == 48, let color = semicolonColor(Array(span)), clearColors.contains(color) {
                    result.append(defaultBackground); changed = true
                } else {
                    result.append(contentsOf: span)
                }
                index += length
            default:
                result.append(part)
                index += 1
            }
        }
        guard changed else { return nil }
        return Array(result.joined(separator: [0x3B]))
    }

    private func semicolonColor(_ span: [ArraySlice<UInt8>]) -> RGB? {
        switch span.count {
        case 3: return Self.number(span[2]).flatMap(color256)
        case 5:
            guard let red = Self.byte(span[2]), let green = Self.byte(span[3]), let blue = Self.byte(span[4])
            else { return nil }
            return RGB(red, green, blue)
        default: return nil
        }
    }

    private func colonColor(_ sub: [ArraySlice<UInt8>]) -> RGB? {
        guard sub.count >= 3 else { return nil }
        switch Self.number(sub[1]) {
        case 5: return Self.number(sub[2]).flatMap(color256)
        case 2:
            // With a colour space (ITU T.416, often empty) or without one (common practice).
            let first = sub.count >= 6 ? 3 : 2
            guard sub.count >= first + 3, let red = Self.byte(sub[first]), let green = Self.byte(sub[first + 1]),
                  let blue = Self.byte(sub[first + 2]) else { return nil }
            return RGB(red, green, blue)
        default: return nil
        }
    }

    /// One of the 256 colours: the theme's sixteen, xterm's 6×6×6 cube, then its grey ramp.
    func color256(_ index: Int) -> RGB? {
        switch index {
        case 0..<16: return palette[index]
        case 16..<232:
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            let value = index - 16
            return RGB(levels[value / 36], levels[(value / 6) % 6], levels[value % 6])
        case 232..<256:
            let grey = UInt8(8 + (index - 232) * 10)
            return RGB(grey, grey, grey)
        default: return nil
        }
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        guard !digits.isEmpty, digits.count <= 6 else { return digits.isEmpty ? 0 : nil }
        var value = 0
        for digit in digits {
            guard (0x30...0x39).contains(digit) else { return nil }
            value = value * 10 + Int(digit - 0x30)
        }
        return value
    }

    private static func byte(_ digits: ArraySlice<UInt8>) -> UInt8? {
        number(digits).flatMap { $0 <= 255 ? UInt8($0) : nil }
    }

    /// xterm's sixteen, for a theme that names none.
    static let xtermPalette: [RGB] = [
        RGB(0, 0, 0), RGB(205, 0, 0), RGB(0, 205, 0), RGB(205, 205, 0),
        RGB(0, 0, 238), RGB(205, 0, 205), RGB(0, 205, 205), RGB(229, 229, 229),
        RGB(127, 127, 127), RGB(255, 0, 0), RGB(0, 255, 0), RGB(255, 255, 0),
        RGB(92, 92, 255), RGB(255, 0, 255), RGB(0, 255, 255), RGB(255, 255, 255),
    ]
}
