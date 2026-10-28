//
//  TerminalProfileReader.swift
//  Glass Power Tools — GlassTerminal
//
//  A macOS Terminal profile (`.terminal`, `com.apple.terminal.settings`) read on every device (the
//  owner, 2026-10-28, for a user with a folder of 148 color schemes: "Let's make these work, first
//  class style!"). A profile is a property list whose colours and font are keyed archives of
//  AppKit's `NSColor` and `NSFont`, which an iPhone or a Vision Pro doesn't have; so each archived
//  class is read here by a small class of this file's own (`NSKeyedUnarchiver.setClass`), with
//  secure coding, taking only the numbers it needs. Nothing else in a profile is read: not its
//  commands, its working folder, its shell or its window.
//
//  Colours come out in sRGB as the Mac shows them: calibrated RGB and white are Generic RGB and
//  Generic Gray, converted as AppKit converts them; device RGB and white are taken as they are, as
//  AppKit takes them; a colour with its own colour space (an ICC profile) is converted from it. A
//  macOS unit test holds this to `NSColor` for Apple's own profiles.
//

import Foundation
import CoreGraphics
import CoreText

/// Why a Terminal profile can't be read, in words that say what to do (`error-messages-say-the-fix`).
nonisolated enum TerminalThemeImportError: LocalizedError, Equatable {
    case emptyInput
    case inputTooLarge(maximumBytes: Int)
    case unsupportedFileExtension
    case invalidPropertyList
    case invalidRootObject
    case invalidValue(key: String)
    case invalidArchive(key: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "The Terminal profile is empty. Export it again from Terminal ▸ Settings ▸ Profiles."
        case .inputTooLarge(let maximumBytes):
            "The Terminal profile is larger than \(maximumBytes / 1024) KB, more than a profile ever is. Check that it's a .terminal file."
        case .unsupportedFileExtension:
            "Choose a Terminal profile: a file ending in .terminal."
        case .invalidPropertyList, .invalidRootObject:
            "This isn't a Terminal profile. Export it again from Terminal ▸ Settings ▸ Profiles."
        case .invalidValue(let key), .invalidArchive(let key):
            "The profile's \(TerminalProfile.Field.title(forKey: key)) can't be read. Export it again from Terminal ▸ Settings ▸ Profiles."
        }
    }
}

/// What a Terminal profile says about how text looks: its colours, sRGB, and its font.
nonisolated struct TerminalProfile: Equatable, Sendable {
    nonisolated struct Color: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    /// A colour a profile can name, by its key in the file.
    nonisolated enum Field: String, CaseIterable, Sendable {
        case text = "TextColor"
        case bold = "TextBoldColor"
        case cursor = "CursorColor"
        case selection = "SelectionColor"
        case background = "BackgroundColor"
        case black = "ANSIBlackColor", red = "ANSIRedColor", green = "ANSIGreenColor", yellow = "ANSIYellowColor"
        case blue = "ANSIBlueColor", magenta = "ANSIMagentaColor", cyan = "ANSICyanColor", white = "ANSIWhiteColor"
        case brightBlack = "ANSIBrightBlackColor", brightRed = "ANSIBrightRedColor"
        case brightGreen = "ANSIBrightGreenColor", brightYellow = "ANSIBrightYellowColor"
        case brightBlue = "ANSIBrightBlueColor", brightMagenta = "ANSIBrightMagentaColor"
        case brightCyan = "ANSIBrightCyanColor", brightWhite = "ANSIBrightWhiteColor"

        /// The sixteen in terminal order: normal 0…7, then bright 8…15.
        static let ansi: [Field] = [.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
                                    .brightBlack, .brightRed, .brightGreen, .brightYellow,
                                    .brightBlue, .brightMagenta, .brightCyan, .brightWhite]

        /// Other names a profile uses for one: iTerm2's exports say `BoldTextColor`.
        var aliases: [String] { self == .bold ? ["BoldTextColor"] : [] }

        /// "selection color", for a key named in an error.
        static func title(forKey key: String) -> String {
            if key == "Font" { return "font" }
            if key == "name" { return "name" }
            guard let field = allCases.first(where: { $0.rawValue == key || $0.aliases.contains(key) }) else { return "settings" }
            switch field {
            case .text: return "text color"
            case .bold: return "bold text color"
            case .cursor: return "cursor color"
            case .selection: return "selection color"
            case .background: return "background color"
            default:
                let words = field.rawValue.dropFirst("ANSI".count).dropLast("Color".count)
                    .replacingOccurrences(of: "Bright", with: "bright ")
                return "ANSI \(words.lowercased()) color"
            }
        }
    }

    var name: String?
    var colors: [Field: Color] = [:]
    /// Its font's PostScript name and size in points, as the profile says.
    var font: (name: String, size: Double)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.colors == rhs.colors && lhs.font?.name == rhs.font?.name && lhs.font?.size == rhs.font?.size
    }
}

nonisolated enum TerminalProfileReader {
    static let maximumBytes = 1_048_576
    static let maximumNameLength = 128

    static func read(contentsOf url: URL) throws -> TerminalProfile {
        guard url.pathExtension.lowercased() == "terminal" else { throw TerminalThemeImportError.unsupportedFileExtension }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw TerminalThemeImportError.invalidPropertyList }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maximumBytes + 1)) ?? Data()
        return try read(data)
    }

    static func read(_ data: Data) throws -> TerminalProfile {
        guard !data.isEmpty else { throw TerminalThemeImportError.emptyInput }
        guard data.count <= maximumBytes else { throw TerminalThemeImportError.inputTooLarge(maximumBytes: maximumBytes) }
        let list: Any
        do {
            list = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw TerminalThemeImportError.invalidPropertyList
        }
        guard let settings = list as? [String: Any] else { throw TerminalThemeImportError.invalidRootObject }

        var profile = TerminalProfile()
        if let raw = settings["name"] {
            guard let name = raw as? String else { throw TerminalThemeImportError.invalidValue(key: "name") }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumNameLength,
                  !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw TerminalThemeImportError.invalidValue(key: "name")
            }
            profile.name = trimmed
        }
        for field in TerminalProfile.Field.allCases {
            guard let key = ([field.rawValue] + field.aliases).first(where: { settings[$0] != nil }) else { continue }
            guard let archive = settings[key] as? Data else { throw TerminalThemeImportError.invalidValue(key: key) }
            profile.colors[field] = try color(fromArchive: archive, key: key)
        }
        if let raw = settings["Font"] {
            guard let archive = raw as? Data else { throw TerminalThemeImportError.invalidValue(key: "Font") }
            profile.font = try font(fromArchive: archive)
        }
        // A file that names nothing of how text looks isn't a profile.
        guard profile.name != nil || !profile.colors.isEmpty else { throw TerminalThemeImportError.invalidRootObject }
        return profile
    }

    // MARK: - Colours

    static func color(fromArchive data: Data, key: String) throws -> TerminalProfile.Color {
        guard let archived = unarchive(data, as: ArchivedColor.self) else { throw TerminalThemeImportError.invalidArchive(key: key) }
        guard let color = archived.sRGB else { throw TerminalThemeImportError.invalidValue(key: key) }
        return color
    }

    static func font(fromArchive data: Data) throws -> (name: String, size: Double) {
        guard let archived = unarchive(data, as: ArchivedFont.self) else { throw TerminalThemeImportError.invalidArchive(key: "Font") }
        let name = archived.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= TerminalTheme.maximumFontNameLength,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              archived.size.isFinite, archived.size > 0, archived.size <= 512 else {
            throw TerminalThemeImportError.invalidValue(key: "Font")
        }
        return (name, archived.size)
    }

    /// The root of a keyed archive as one of this file's classes, AppKit's class names mapped to them.
    private static func unarchive<T: NSObject & NSSecureCoding>(_ data: Data, as type: T.Type) -> T? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(ArchivedColor.self, forClassName: "NSColor")
        unarchiver.setClass(ArchivedColorSpace.self, forClassName: "NSColorSpace")
        unarchiver.setClass(ArchivedFont.self, forClassName: "NSFont")
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(of: type, forKey: NSKeyedArchiveRootObjectKey)
    }

    /// Numbers written as AppKit writes them: ASCII, separated by spaces, perhaps ending in a NUL.
    static func numbers(_ bytes: Data?) -> [Double]? {
        guard let bytes, bytes.count <= 256,
              let text = String(data: bytes.prefix { $0 != 0 }, encoding: .ascii) else { return nil }
        let values = text.split(separator: " ").map { Double($0) }
        guard !values.isEmpty, values.count <= 5, values.allSatisfy({ $0?.isFinite == true }) else { return nil }
        return values.compactMap { $0 }
    }

    /// AppKit's calibrated RGB and white. Swift hides their names' constants (legacy spaces, Apple
    /// says), but every platform has them (iOS 9 on), by name.
    static let genericRGB = CGColorSpace(name: "kCGColorSpaceGenericRGB" as CFString)
    static let genericGray = CGColorSpace(name: "kCGColorSpaceGenericGray" as CFString)

    /// `components` (with alpha last) in `space`, as sRGB: nil if they don't fit it or can't be
    /// converted. A hair outside 0…1, as a converted colour can be, is brought in; more is refused.
    static func sRGB(_ components: [Double], in space: CGColorSpace?) -> TerminalProfile.Color? {
        // CoreGraphics would clamp numbers outside 0…1 without a word.
        guard let space, components.count == space.numberOfComponents + 1,
              components.allSatisfy({ (0...1).contains($0) }),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let values = components.map { CGFloat($0) }
        guard let color = CGColor(colorSpace: space, components: values),
              let converted = space.name == CGColorSpace.sRGB ? color : color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let out = converted.components, out.count == 4 else { return nil }
        let clamped = out.map { Double($0) }.map { $0 < 0 && $0 > -0.002 ? 0 : ($0 > 1 && $0 < 1.002 ? 1 : $0) }
        guard clamped.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return TerminalProfile.Color(red: clamped[0], green: clamped[1], blue: clamped[2], alpha: clamped[3])
    }
}

// MARK: - The archived classes

/// An archived `NSColor`: its colour space's number, and its numbers in it.
@objc(GlassTerminalArchivedColor)
nonisolated private final class ArchivedColor: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    /// AppKit's colour space numbers: 1 calibrated RGB, 2 device RGB, 3 calibrated white, 4 device white.
    let space: Int
    let rgb: [Double]?
    let white: [Double]?
    let components: [Double]?
    let custom: ArchivedColorSpace?

    init?(coder: NSCoder) {
        space = coder.decodeInteger(forKey: "NSColorSpace")
        rgb = TerminalProfileReader.numbers(Self.bytes(coder, "NSRGB"))
        white = TerminalProfileReader.numbers(Self.bytes(coder, "NSWhite"))
        components = TerminalProfileReader.numbers(Self.bytes(coder, "NSComponents"))
        custom = coder.containsValue(forKey: "NSCustomColorSpace")
            ? coder.decodeObject(of: ArchivedColorSpace.self, forKey: "NSCustomColorSpace") : nil
        super.init()
    }

    func encode(with coder: NSCoder) {}

    private static func bytes(_ coder: NSCoder, _ key: String) -> Data? {
        guard coder.containsValue(forKey: key) else { return nil }
        var length = 0
        guard let pointer = coder.decodeBytes(forKey: key, returnedLength: &length), length > 0, length <= 256 else { return nil }
        return Data(bytes: pointer, count: length)
    }

    /// With alpha 1 where the archive leaves it out.
    private static func withAlpha(_ values: [Double], count: Int) -> [Double]? {
        if values.count == count + 1 { return values }
        if values.count == count { return values + [1] }
        return nil
    }

    var sRGB: TerminalProfile.Color? {
        // A colour space of its own, with the numbers in it, is what the colour is.
        if let components, let icc = custom?.icc, let space = CGColorSpace(iccData: icc as CFData),
           let color = TerminalProfileReader.sRGB(components, in: space) {
            return color
        }
        switch space {
        case 1:
            return rgb.flatMap { Self.withAlpha($0, count: 3) }
                .flatMap { TerminalProfileReader.sRGB($0, in: TerminalProfileReader.genericRGB) }
        case 2:
            return rgb.flatMap { Self.withAlpha($0, count: 3) }
                .flatMap { TerminalProfileReader.sRGB($0, in: CGColorSpace(name: CGColorSpace.sRGB)) }
        case 3:
            return white.flatMap { Self.withAlpha($0, count: 1) }
                .flatMap { TerminalProfileReader.sRGB($0, in: TerminalProfileReader.genericGray) }
        case 4:
            return white.flatMap { Self.withAlpha($0, count: 1) }
                .flatMap { TerminalProfileReader.sRGB([$0[0], $0[0], $0[0], $0[1]], in: CGColorSpace(name: CGColorSpace.sRGB)) }
        default:
            return nil
        }
    }
}

/// An archived `NSColorSpace`: the ICC profile it carries, when it carries one.
@objc(GlassTerminalArchivedColorSpace)
nonisolated private final class ArchivedColorSpace: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let icc: Data?

    init?(coder: NSCoder) {
        let data = coder.containsValue(forKey: "NSICC") ? coder.decodeObject(of: NSData.self, forKey: "NSICC") as Data? : nil
        icc = data.flatMap { $0.count <= 65_536 ? $0 : nil }
        super.init()
    }

    func encode(with coder: NSCoder) {}
}

/// An archived `NSFont`: its PostScript name and size.
@objc(GlassTerminalArchivedFont)
nonisolated private final class ArchivedFont: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let name: String
    let size: Double

    init?(coder: NSCoder) {
        guard let name = coder.decodeObject(of: NSString.self, forKey: "NSName") as String? else { return nil }
        self.name = name
        size = coder.decodeDouble(forKey: "NSSize")
        super.init()
    }

    func encode(with coder: NSCoder) {}
}

// MARK: - As a theme

extension TerminalTheme {
    /// `fallback` in a Terminal profile's colours, its background included (the window's opacity
    /// still says how much of it shows), and, `withFont`, its font where this device has it and it
    /// is monospaced. A profile that leaves its sixteen colours out (Apple's Homebrew) has macOS
    /// Terminal's default palette, Clear Dark's, as Terminal gives it; a cursor it leaves out
    /// follows its text. Its bold colour isn't drawn: SwiftTerm draws bold text in the text's
    /// colour, or bright for one of the sixteen.
    init(profile: TerminalProfile, fallback: TerminalTheme, id: UUID, withFont: Bool) {
        var theme = fallback.reidentified(id: id, name: profile.name ?? fallback.name)
        theme.applyAppleClearDarkColors()
        func set(_ field: TerminalProfile.Field, _ keyPath: WritableKeyPath<TerminalTheme, CodableColor>) {
            guard let color = profile.colors[field] else { return }
            theme[keyPath: keyPath] = CodableColor(sRGBRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }
        set(.text, \.foreground)
        if profile.colors[.cursor] == nil, profile.colors[.text] != nil { theme.cursor = theme.foreground }
        set(.cursor, \.cursor)
        set(.selection, \.selection)
        set(.background, \.background)
        let ansi: [WritableKeyPath<TerminalTheme, CodableColor>] = [
            \.black, \.red, \.green, \.yellow, \.blue, \.magenta, \.cyan, \.white,
            \.brightBlack, \.brightRed, \.brightGreen, \.brightYellow, \.brightBlue, \.brightMagenta, \.brightCyan, \.brightWhite,
        ]
        for (field, keyPath) in zip(TerminalProfile.Field.ansi, ansi) { set(field, keyPath) }
        if profile.colors[.background] != nil {
            // Its canvas follows its background, so a light scheme isn't drawn on dark glass.
            theme.preferredAppearance = nil
            theme.preferredAppearance = theme.resolvedAppearance
        }
        if withFont, let font = profile.font, let name = Self.monospacedFontName(font.name) {
            theme.fontName = name
            theme.fontSize = min(Self.maximumFontSize, max(Self.minimumFontSize, CGFloat(font.size.rounded())))
        }
        self = theme
    }

    /// The font's name if this device has it and it is monospaced. Apple's own profiles name SF
    /// Mono Terminal, Terminal's own copy of SF Mono, which is SF Mono here; and some name
    /// `.AppleSystemUIFont`, Terminal's way of saying its default, which is proportional.
    nonisolated static func monospacedFontName(_ name: String) -> String? {
        if name.hasPrefix("SFMonoTerminal") { return "SF Mono" }
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        guard CTFontCopyPostScriptName(font) as String == name,
              CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) else { return nil }
        return name
    }
}
