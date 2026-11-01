//
//  DesktopFoldKeyboard.swift
//  Glass Power Tools — GlassDesktop
//
//  A remote desktop's own keyboard below an iPhone Duo's fold (D93, 2026-10-31). Stood like a
//  laptop, the lower half holds a keyboard and a trackpad at once, with shortcut buttons beside the
//  trackpad (the owner chose "Keys + trackpad at once", after DuoScreen's). The iPhone's keyboard
//  types text, not chords: it has no Control, Alt or Windows key and no F-keys, and a remote desktop
//  wants all of them. Every key here goes as its RDP set-1 scancode, which every transport takes
//  (`DesktopAccessoryKeys`), inside the modifiers armed for it.
//

import SwiftUI
import GlassLayers

/// One key of the keyboard: what it sends, what it shows, and how wide it is.
struct DesktopFoldKey: Identifiable, Hashable {
    enum Action: Hashable {
        /// A key the remote computer is sent.
        case key(DesktopKey)
        /// Control, Option (Alt), Command (Windows) or Shift, armed for the next key.
        case modifier(DesktopStickyModifier)
        /// fn: the number row's F1–F12 and the arrows' Home, End, Page Up and Page Down, for the
        /// next key. Never sent.
        case fn
    }

    let id: String
    let label: String
    /// With Shift armed.
    let shifted: String?
    let action: Action
    /// With fn armed, instead.
    let fnKey: DesktopKey?
    let fnLabel: String?
    /// In key widths.
    let width: CGFloat
    /// Held, it repeats: Delete and the arrows.
    let repeats: Bool
    /// What VoiceOver says, where the label is a symbol.
    let spoken: String?

    init(_ id: String, _ label: String, shifted: String? = nil, _ action: Action, fn: (DesktopKey, String)? = nil,
         width: CGFloat = 1, repeats: Bool = false, spoken: String? = nil) {
        self.id = id
        self.label = label
        self.shifted = shifted
        self.action = action
        self.fnKey = fn?.0
        self.fnLabel = fn?.1
        self.width = width
        self.repeats = repeats
        self.spoken = spoken
    }

    /// What the key sends, with fn armed or not; nil for a modifier or fn itself.
    func sent(fn: Bool) -> DesktopKey? {
        guard case let .key(key) = action else { return nil }
        return fn ? (fnKey ?? key) : key
    }
}

/// The keyboard's rows, a US layout, five rows of 14.5 key widths each.
enum DesktopFoldKeyboard {
    private static func character(_ label: String, _ shifted: String?, _ code: UInt16,
                                  fn: (DesktopKey, String)? = nil) -> DesktopFoldKey {
        DesktopFoldKey(label, label, shifted: shifted, .key(DesktopKey(code)), fn: fn)
    }

    private static func letters(_ letters: String, from codes: [UInt16]) -> [DesktopFoldKey] {
        zip(letters, codes).map { letter, code in character(String(letter), String(letter).uppercased(), code) }
    }

    static let rows: [[DesktopFoldKey]] = {
        let digits: [(String, String, UInt16)] = [("1", "!", 0x02), ("2", "@", 0x03), ("3", "#", 0x04), ("4", "$", 0x05),
                                                  ("5", "%", 0x06), ("6", "^", 0x07), ("7", "&", 0x08), ("8", "*", 0x09),
                                                  ("9", "(", 0x0a), ("0", ")", 0x0b)]
        let numberRow: [DesktopFoldKey] =
            [character("`", "~", 0x29)]
            + digits.enumerated().map { index, digit in
                character(digit.0, digit.1, digit.2, fn: (DesktopAccessoryKeys.function(index + 1)!, "F\(index + 1)"))
            }
            + [character("-", "_", 0x0c, fn: (DesktopAccessoryKeys.function(11)!, "F11")),
               character("=", "+", 0x0d, fn: (DesktopAccessoryKeys.function(12)!, "F12")),
               DesktopFoldKey("delete", "⌫", .key(DesktopKey(0x0e)), width: 1.5, repeats: true, spoken: "Delete")]
        let topRow: [DesktopFoldKey] =
            [DesktopFoldKey("tab", "tab", .key(DesktopAccessoryKeys.tab), width: 1.5, spoken: "Tab")]
            + letters("qwertyuiop", from: [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19])
            + [character("[", "{", 0x1a), character("]", "}", 0x1b), character("\\", "|", 0x2b)]
        let homeRow: [DesktopFoldKey] =
            letters("asdfghjkl", from: [0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26])
            + [character(";", ":", 0x27), character("'", "\"", 0x28),
               DesktopFoldKey("return", "↵", .key(DesktopKey(0x1c)), width: 3.5, spoken: "Return")]
        let bottomRow: [DesktopFoldKey] =
            [DesktopFoldKey("shift", "⇧", .modifier(.shift), width: 2, spoken: "Shift")]
            + letters("zxcvbnm", from: [0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32])
            + [character(",", "<", 0x33), character(".", ">", 0x34), character("/", "?", 0x35),
               DesktopFoldKey("shift-right", "⇧", .modifier(.shift), width: 2.5, spoken: "Shift")]
        let spaceRow: [DesktopFoldKey] = [
            DesktopFoldKey("fn", "fn", .fn, width: 1.25, spoken: "Function"),
            DesktopFoldKey("control", "ctrl", .modifier(.control), width: 1.25, spoken: "Control"),
            DesktopFoldKey("option", "alt", .modifier(.option), width: 1.25, spoken: "Option"),
            DesktopFoldKey("command", "⌘", .modifier(.command), width: 1.5, spoken: "Command"),
            DesktopFoldKey("space", "", .key(DesktopKey(0x39)), width: 5.25, spoken: "Space"),
            DesktopFoldKey("left", "←", .key(DesktopAccessoryKeys.left), fn: (DesktopAccessoryKeys.home, "home"),
                           repeats: true, spoken: "Left Arrow"),
            DesktopFoldKey("up", "↑", .key(DesktopAccessoryKeys.up), fn: (DesktopAccessoryKeys.pageUp, "pg↑"),
                           repeats: true, spoken: "Up Arrow"),
            DesktopFoldKey("down", "↓", .key(DesktopAccessoryKeys.down), fn: (DesktopAccessoryKeys.pageDown, "pg↓"),
                           repeats: true, spoken: "Down Arrow"),
            DesktopFoldKey("right", "→", .key(DesktopAccessoryKeys.right), fn: (DesktopAccessoryKeys.end, "end"),
                           repeats: true, spoken: "Right Arrow"),
        ]
        return [numberRow, topRow, homeRow, bottomRow, spaceRow]
    }()

    /// Option and Command as the remote computer names them: a PC's Alt and Windows key over RDP,
    /// a Mac's Option and Command over VNC (Apple's Screen Sharing among them).
    static func label(_ modifier: DesktopStickyModifier, on remote: DesktopProtocol) -> String {
        switch (modifier, remote) {
        case (.control, _): "ctrl"
        case (.option, .rdp): "alt"
        case (.option, .vnc): "opt"
        case (.command, .rdp): "win"
        case (.command, .vnc): "⌘"
        case (.shift, _): "⇧"
        }
    }

    /// The same, spoken.
    static func spoken(_ modifier: DesktopStickyModifier, on remote: DesktopProtocol) -> String {
        switch (modifier, remote) {
        case (.option, .rdp): "Alt"
        case (.command, .rdp): "Windows"
        default: modifier.title
        }
    }
}

/// A key with its modifiers, as a shortcut button sends it.
struct DesktopFoldChord: Codable, Hashable, Sendable {
    var modifiers: [DesktopStickyModifier]
    var scancode: UInt16
    var extended: Bool
    /// The key's own label, as the keyboard shows it.
    var keyLabel: String

    init(_ modifiers: [DesktopStickyModifier], _ key: DesktopKey, label: String) {
        // In the order a keyboard's are named: Control, Option, Shift, Command.
        let order: [DesktopStickyModifier] = [.control, .option, .shift, .command]
        self.modifiers = order.filter(modifiers.contains)
        self.scancode = key.scancode
        self.extended = key.extended
        self.keyLabel = label
    }

    var key: DesktopKey { DesktopKey(scancode, extended: extended) }

    /// The modifiers down, the key tapped, the modifiers up in reverse.
    var events: [DesktopInput.Event] { DesktopAccessoryKeys.tap(key, holding: modifiers.map(\.key)) }

    /// "Ctrl+C" for a PC, "⌘C" for a Mac.
    func title(on remote: DesktopProtocol) -> String {
        let key = keyLabel.count == 1 ? keyLabel.uppercased() : keyLabel
        switch remote {
        case .rdp:
            let names: [DesktopStickyModifier: String] = [.control: "Ctrl", .option: "Alt", .shift: "Shift", .command: "Win"]
            return (modifiers.compactMap { names[$0] } + [key]).joined(separator: "+")
        case .vnc:
            let symbols: [DesktopStickyModifier: String] = [.control: "⌃", .option: "⌥", .shift: "⇧", .command: "⌘"]
            return modifiers.compactMap { symbols[$0] }.joined() + key
        }
    }

    /// Copy, Undo and Select All: Control on a PC, Command on a Mac.
    static func defaults(for remote: DesktopProtocol) -> [DesktopFoldChord] {
        let modifier: DesktopStickyModifier = remote == .rdp ? .control : .command
        return [DesktopFoldChord([modifier], DesktopKey(0x2e), label: "c"),
                DesktopFoldChord([modifier], DesktopKey(0x2c), label: "z"),
                DesktopFoldChord([modifier], DesktopKey(0x1e), label: "a")]
    }
}

extension DesktopStickyModifier: Codable {}

/// The three shortcut buttons, as recorded on this device, for PCs and Macs apart; a UI test run
/// keeps its own (`GlassUITestRun`).
enum DesktopFoldShortcuts {
    static func key(for remote: DesktopProtocol) -> String { "desktop.foldShortcuts.\(remote.rawValue)" }

    static func load(for remote: DesktopProtocol, from defaults: UserDefaults = GlassUITestRun.settingsDefaults) -> [DesktopFoldChord] {
        guard let data = defaults.data(forKey: key(for: remote)),
              let chords = try? JSONDecoder().decode([DesktopFoldChord].self, from: data), chords.count == 3
        else { return DesktopFoldChord.defaults(for: remote) }
        return chords
    }

    static func save(_ chords: [DesktopFoldChord], for remote: DesktopProtocol, to defaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        guard chords.count == 3, let data = try? JSONEncoder().encode(chords) else { return }
        defaults.set(data, forKey: key(for: remote))
    }
}
