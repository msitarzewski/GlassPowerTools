#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// Terminal profiles read on every device without AppKit (2026-10-28, a user's folder of 148 colour
/// schemes: "Let's make these work, first class style!"). AppKit is the known answer here, on the
/// Mac: what `NSColor` makes of each archived colour is what the reader must.
@Suite("Reading Terminal profiles as Terminal does")
struct TerminalProfileReaderTests {
    private static let appleProfiles = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings")

    private func archive(_ object: NSObject) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
    }

    private func profile(_ settings: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
    }

    /// AppKit's reading of an archived colour, in sRGB.
    private func appKit(_ data: Data) throws -> TerminalProfile.Color {
        let color = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)?.usingColorSpace(.sRGB))
        return TerminalProfile.Color(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
                                     alpha: color.alphaComponent)
    }

    private func close(_ a: TerminalProfile.Color, _ b: TerminalProfile.Color, within tolerance: Double = 1e-6) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance && abs(a.blue - b.blue) <= tolerance
            && abs(a.alpha - b.alpha) <= tolerance
    }

    @Test("Every colour in Apple's own profiles reads as AppKit reads it")
    func appleProfilesReadAsAppKitDoes() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.appleProfiles.path).filter { $0.hasSuffix(".terminal") }
        #expect(names.count >= 10, "Terminal's profiles: \(names)")
        var compared = 0
        for name in names {
            let data = try Data(contentsOf: Self.appleProfiles.appendingPathComponent(name))
            let read = try TerminalProfileReader.read(data)
            let settings = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            for field in TerminalProfile.Field.allCases {
                guard let archived = settings[field.rawValue] as? Data else { continue }
                let mine = try #require(read.colors[field], "\(name) \(field.rawValue)")
                #expect(close(mine, try appKit(archived)), "\(name) \(field.rawValue)")
                compared += 1
            }
        }
        // Calibrated and device RGB, calibrated white, and colours with their own ICC profile.
        #expect(compared >= 60, "\(compared) compared")
    }

    @Test("Each kind of archived colour: calibrated and device RGB and white, sRGB and Display P3, with and without alpha")
    func eachKindOfColour() throws {
        let colours: [NSColor] = [
            NSColor(calibratedRed: 0.8, green: 0, blue: 0, alpha: 1),
            NSColor(deviceRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5),
            NSColor(calibratedWhite: 0.5, alpha: 1),
            NSColor(deviceWhite: 0.25, alpha: 0.9),
            NSColor(srgbRed: 0.1, green: 0.7, blue: 0.3, alpha: 1),
            NSColor(displayP3Red: 1, green: 0.2, blue: 0.1, alpha: 1),
            NSColor(genericGamma22White: 0.57, alpha: 1),
        ]
        for colour in colours {
            let data = try archive(colour)
            let mine = try TerminalProfileReader.color(fromArchive: data, key: "TextColor")
            #expect(close(mine, try appKit(data), within: 1e-4), "\(colour): \(mine)")
        }
        // Calibrated is Generic RGB: Tango's red #CC0000, saved calibrated, is what Terminal shows.
        let tango = try TerminalProfileReader.color(fromArchive: try archive(NSColor(calibratedRed: 0.8, green: 0, blue: 0, alpha: 1)),
                                                    key: "ANSIRedColor")
        #expect(tango.red > 0.84 && tango.green > 0.1, "\(tango)")
    }

    @Test("A scheme comes in whole: its background, text, selection, cursor and sixteen colours; a missing cursor follows its text")
    func aSchemeComesInWhole() throws {
        let text = NSColor(deviceRed: 0.51, green: 0.58, blue: 0.59, alpha: 1)
        var settings: [String: Any] = [
            "name": "Solarized Dark",
            "type": "Window Settings",
            "BackgroundColor": try archive(NSColor(deviceRed: 0, green: 0.169, blue: 0.212, alpha: 1)),
            "TextColor": try archive(text),
            "SelectionColor": try archive(NSColor(deviceRed: 0.027, green: 0.212, blue: 0.259, alpha: 1)),
            "BoldTextColor": try archive(NSColor(deviceRed: 0.58, green: 0.63, blue: 0.63, alpha: 1)),
            "CommandString": "rm -rf ~ # never read",
        ]
        let ansi = TerminalProfile.Field.ansi
        for (index, field) in ansi.enumerated() {
            settings[field.rawValue] = try archive(NSColor(deviceRed: Double(index) / 16, green: 0.5, blue: 1 - Double(index) / 16, alpha: 1))
        }
        let read = try TerminalProfileReader.read(try profile(settings))
        #expect(read.name == "Solarized Dark")
        #expect(read.colors[.bold] != nil, "iTerm2's exports name the bold colour BoldTextColor")

        let theme = TerminalTheme(profile: read, fallback: .default, id: UUID(), withFont: false)
        #expect(abs(theme.background.blue - 0.212) < 1e-9 && abs(theme.background.green - 0.169) < 1e-9, "its own background")
        #expect(abs(theme.foreground.red - 0.51) < 1e-9)
        #expect(abs(theme.selection.green - 0.212) < 1e-9, "its highlight")
        #expect(theme.cursor == theme.foreground, "no cursor colour of its own: the text's")
        #expect(abs(theme.ansiColors[9].red - 9.0 / 16) < 1e-9, "bright red, in terminal order")
        #expect(theme.preferredAppearance == .dark)
        #expect(theme.fontName == TerminalTheme.default.fontName, "colours only: the font stays")
        #expect(theme.isValidForPersistence)

        let light = TerminalTheme(profile: TerminalProfile(name: "Day", colors: [.background: .init(red: 0.98, green: 0.96, blue: 0.9, alpha: 1)]),
                                  fallback: .default, id: UUID(), withFont: false)
        #expect(light.preferredAppearance == .light, "a light scheme isn't drawn on dark glass")
    }

    @Test("A profile without its sixteen colours has Terminal's default palette, Clear Dark's")
    func missingColoursAreTerminalsDefault() throws {
        var fallback = TerminalTheme.default
        fallback.red = CodableColor(sRGBRed: 1, green: 0, blue: 1)
        let theme = TerminalTheme(profile: TerminalProfile(name: "Bare", colors: [:]), fallback: fallback, id: UUID(), withFont: false)
        #expect(theme.ansiColors == TerminalTheme.appleClearDarkANSIColors)
    }

    @Test("Fonts: one this device has and monospaced is used; SF Mono Terminal is SF Mono; a proportional one isn't")
    func fonts() throws {
        #expect(TerminalTheme.monospacedFontName("Menlo-Regular") == "Menlo-Regular")
        #expect(TerminalTheme.monospacedFontName("SFMonoTerminal-Regular") == "SF Mono")
        #expect(TerminalTheme.monospacedFontName("Helvetica") == nil)
        #expect(TerminalTheme.monospacedFontName("No Such Font") == nil)
        let read = try TerminalProfileReader.read(try profile(["name": "Pro", "Font": try archive(NSFont(name: "Menlo", size: 17)!)]))
        let theme = TerminalTheme(profile: read, fallback: .default, id: UUID(), withFont: true)
        #expect(theme.fontName == "Menlo-Regular" && theme.fontSize == 17)
    }

    @Test("What isn't a profile is refused in words: not a property list, nothing of how text looks, a colour that isn't one")
    func refusals() throws {
        #expect(throws: TerminalThemeImportError.emptyInput) { try TerminalProfileReader.read(Data()) }
        #expect(throws: TerminalThemeImportError.invalidPropertyList) { try TerminalProfileReader.read(Data("not a plist".utf8)) }
        #expect(throws: TerminalThemeImportError.invalidRootObject) { try TerminalProfileReader.read(try profile(["rowCount": 24])) }
        #expect(throws: TerminalThemeImportError.invalidValue(key: "TextColor")) {
            try TerminalProfileReader.read(try profile(["name": "X", "TextColor": "red"]))
        }
        #expect(throws: TerminalThemeImportError.invalidArchive(key: "TextColor")) {
            try TerminalProfileReader.read(try profile(["name": "X", "TextColor": try archive("a string" as NSString)]))
        }
        #expect(throws: TerminalThemeImportError.invalidValue(key: "name")) {
            try TerminalProfileReader.read(try profile(["name": "two\nlines"]))
        }
        #expect(throws: TerminalThemeImportError.inputTooLarge(maximumBytes: TerminalProfileReader.maximumBytes)) {
            try TerminalProfileReader.read(Data(count: TerminalProfileReader.maximumBytes + 1))
        }
        // Numbers that aren't: a colour's text that isn't numbers, or isn't finite.
        #expect(TerminalProfileReader.numbers(Data("0.1 nan 0.3\0".utf8)) == nil)
        #expect(TerminalProfileReader.numbers(Data("red green blue\0".utf8)) == nil)
        #expect(TerminalProfileReader.numbers(Data("0.5 0.25 1\0".utf8)) == [0.5, 0.25, 1])
        #expect(TerminalProfileReader.sRGB([1.5, 0, 0, 1], in: CGColorSpace(name: CGColorSpace.sRGB)) == nil, "out of range")
        let message = TerminalThemeImportError.invalidArchive(key: "SelectionColor").errorDescription ?? ""
        #expect(message.contains("selection color") && message.contains("Export it again"), "\(message)")
    }
}
#endif
