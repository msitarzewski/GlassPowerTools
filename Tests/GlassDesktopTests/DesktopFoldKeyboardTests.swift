import Foundation
import Testing
@testable import GlassDesktop

/// The desktop's own keyboard below an iPhone Duo's fold (D93, 2026-10-31): each key the scancode a
/// USB keyboard's key reaches (USB HID usage tables, through `DesktopKeyboard.key(hidUsage:)`, the
/// table a hardware keyboard already uses), fn's F-keys and navigation, and the shortcut buttons.
@Suite("Desktop keyboard below the fold")
struct DesktopFoldKeyboardTests {
    private func keys(_ events: [DesktopInput.Event]) -> [String] {
        events.map { event in
            guard case let .key(code, extended, down, _) = event else { return "other" }
            return String(format: "%@%02x%@", extended ? "e" : "", code, down ? "↓" : "↑")
        }
    }

    private var allKeys: [DesktopFoldKey] { DesktopFoldKeyboard.rows.flatMap { $0 } }
    private func key(_ id: String) -> DesktopFoldKey? { allKeys.first { $0.id == id } }

    /// Each key's USB HID usage (Keyboard/Keypad page 0x07), from the HID usage tables.
    private static let hidUsages: [String: Int] = {
        var usages: [String: Int] = [:]
        for (offset, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() { usages[String(letter)] = 4 + offset }
        for (offset, digit) in "123456789".enumerated() { usages[String(digit)] = 30 + offset }
        usages["0"] = 39
        let others: [String: Int] = ["return": 40, "delete": 42, "tab": 43, "space": 44, "-": 45, "=": 46,
                                     "[": 47, "]": 48, "\\": 49, ";": 51, "'": 52, "`": 53, ",": 54, ".": 55,
                                     "/": 56, "right": 79, "left": 80, "down": 81, "up": 82]
        return usages.merging(others) { $1 }
    }()

    @Test("every key sends the scancode a USB keyboard's same key does")
    func scancodes() throws {
        let sending = allKeys.filter { if case .key = $0.action { true } else { false } }
        #expect(sending.count == Self.hidUsages.count, "a key with no usage to check it against")
        for key in sending {
            let usage = try #require(Self.hidUsages[key.id], "no usage for \(key.id)")
            #expect(key.sent(fn: false) == DesktopKeyboard.key(hidUsage: usage), "\(key.id)")
        }
        // Set-1's own numbers for a few, read from the scancode table rather than the HID mapping.
        #expect(key("q")?.sent(fn: false) == DesktopKey(0x10) && key("a")?.sent(fn: false) == DesktopKey(0x1e))
        #expect(key("z")?.sent(fn: false) == DesktopKey(0x2c) && key("space")?.sent(fn: false) == DesktopKey(0x39))
    }

    @Test("with fn, the number row is F1–F12 and the arrows Home, Page Up, Page Down and End")
    func function() {
        let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
        #expect(numberRow.compactMap { key($0)?.sent(fn: true)?.scancode }
                == [0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58])
        #expect(key("left")?.sent(fn: true) == DesktopKey(0x47, extended: true))
        #expect(key("up")?.sent(fn: true) == DesktopKey(0x49, extended: true))
        #expect(key("down")?.sent(fn: true) == DesktopKey(0x51, extended: true))
        #expect(key("right")?.sent(fn: true) == DesktopKey(0x4f, extended: true))
        #expect(key("q")?.sent(fn: true) == DesktopKey(0x10), "fn leaves a letter alone")
        #expect(key("fn")?.sent(fn: false) == nil && key("control")?.sent(fn: false) == nil, "fn and the modifiers send nothing")
    }

    @Test("both Shift keys arm Shift; Control, Option and Command are the sticky modifiers")
    func modifiers() {
        #expect(key("shift")?.action == .modifier(.shift) && key("shift-right")?.action == .modifier(.shift))
        #expect(key("control")?.action == .modifier(.control) && key("option")?.action == .modifier(.option)
                && key("command")?.action == .modifier(.command))
        #expect(DesktopFoldKeyboard.label(.command, on: .rdp) == "win" && DesktopFoldKeyboard.label(.command, on: .vnc) == "⌘")
        #expect(DesktopFoldKeyboard.label(.option, on: .rdp) == "alt" && DesktopFoldKeyboard.label(.option, on: .vnc) == "opt")
    }

    @Test("each row is the same width, 14.5 keys")
    func rows() {
        for row in DesktopFoldKeyboard.rows { #expect(row.reduce(0) { $0 + $1.width } == 14.5) }
        #expect(Set(allKeys.map(\.id)).count == allKeys.count, "every key named once")
    }

    @Test("a shortcut goes as its modifiers, the key, and the modifiers up in reverse")
    func chords() {
        let copy = DesktopFoldChord([.control], DesktopKey(0x2e), label: "c")
        #expect(keys(copy.events) == ["1d↓", "2e↓", "2e↑", "1d↑"])
        #expect(copy.title(on: .rdp) == "Ctrl+C" && copy.title(on: .vnc) == "⌃C")
        let both = DesktopFoldChord([.command, .shift, .control], DesktopKey(0x14), label: "t")
        #expect(both.modifiers == [.control, .shift, .command], "named in a keyboard's order")
        #expect(both.title(on: .rdp) == "Ctrl+Shift+Win+T" && both.title(on: .vnc) == "⌃⇧⌘T")
        #expect(DesktopFoldChord([], DesktopKey(0x3c), label: "F2").title(on: .rdp) == "F2")
        #expect(DesktopFoldChord.defaults(for: .rdp).map { $0.title(on: .rdp) } == ["Ctrl+C", "Ctrl+Z", "Ctrl+A"])
        #expect(DesktopFoldChord.defaults(for: .vnc).map { $0.title(on: .vnc) } == ["⌘C", "⌘Z", "⌘A"])
    }

    @Test("recorded shortcuts are kept on this device, for PCs and Macs apart; anything else is the defaults")
    func shortcutStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "DesktopFoldKeyboardTests-\(UUID())"))
        #expect(DesktopFoldShortcuts.load(for: .rdp, from: defaults) == DesktopFoldChord.defaults(for: .rdp))
        var recorded = DesktopFoldChord.defaults(for: .rdp)
        recorded[1] = DesktopFoldChord([.control, .shift], DesktopKey(0x01), label: "esc")
        DesktopFoldShortcuts.save(recorded, for: .rdp, to: defaults)
        #expect(DesktopFoldShortcuts.load(for: .rdp, from: defaults) == recorded)
        #expect(DesktopFoldShortcuts.load(for: .vnc, from: defaults) == DesktopFoldChord.defaults(for: .vnc), "a Mac's are its own")
        DesktopFoldShortcuts.save(Array(recorded.prefix(2)), for: .rdp, to: defaults)
        #expect(DesktopFoldShortcuts.load(for: .rdp, from: defaults) == recorded, "two are never saved over three")
        defaults.set(Data("not json".utf8), forKey: DesktopFoldShortcuts.key(for: .vnc))
        #expect(DesktopFoldShortcuts.load(for: .vnc, from: defaults) == DesktopFoldChord.defaults(for: .vnc))
    }
}
