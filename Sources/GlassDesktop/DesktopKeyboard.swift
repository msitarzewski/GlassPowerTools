import Foundation

public struct DesktopKey: Hashable, Sendable {
    public var scancode: UInt16
    public var extended: Bool
    public init(_ scancode: UInt16, extended: Bool = false) { self.scancode = scancode; self.extended = extended }
}

public enum DesktopKeyboard {
    /// USB HID usages supplied by UIKit hardware keyboard events, mapped to RDP set-1 scancodes.
    public static func key(hidUsage: Int) -> DesktopKey? {
        let letters: [UInt16] = [0x1e,0x30,0x2e,0x20,0x12,0x21,0x22,0x23,0x17,0x24,0x25,0x26,0x32,
                                 0x31,0x18,0x19,0x10,0x13,0x1f,0x14,0x16,0x2f,0x11,0x2d,0x15,0x2c]
        if (4...29).contains(hidUsage) { return .init(letters[hidUsage - 4]) }
        if (30...38).contains(hidUsage) { return .init(UInt16(hidUsage - 28)) }
        if (58...67).contains(hidUsage) { return .init(UInt16(hidUsage + 1)) }
        switch hidUsage {
        case 39: return .init(0x0b)
        case 40: return .init(0x1c)
        case 41: return .init(0x01)
        case 42: return .init(0x0e)
        case 43: return .init(0x0f)
        case 44: return .init(0x39)
        case 45: return .init(0x0c)
        case 46: return .init(0x0d)
        case 47: return .init(0x1a)
        case 48: return .init(0x1b)
        case 49: return .init(0x2b)
        case 50: return .init(0x2b)
        case 51: return .init(0x27)
        case 52: return .init(0x28)
        case 53: return .init(0x29)
        case 54: return .init(0x33)
        case 55: return .init(0x34)
        case 56: return .init(0x35)
        case 57: return .init(0x3a)
        case 68: return .init(0x57)
        case 69: return .init(0x58)
        case 73: return .init(0x52, extended: true)
        case 74: return .init(0x47, extended: true)
        case 75: return .init(0x49, extended: true)
        case 76: return .init(0x53, extended: true)
        case 77: return .init(0x4f, extended: true)
        case 78: return .init(0x51, extended: true)
        case 79: return .init(0x4d, extended: true)
        case 80: return .init(0x4b, extended: true)
        case 81: return .init(0x50, extended: true)
        case 82: return .init(0x48, extended: true)
        case 83: return .init(0x45)
        case 84: return .init(0x35, extended: true)
        case 85: return .init(0x37)
        case 86: return .init(0x4a)
        case 87: return .init(0x4e)
        case 88: return .init(0x1c, extended: true)
        case 89: return .init(0x4f)
        case 90: return .init(0x50)
        case 91: return .init(0x51)
        case 92: return .init(0x4b)
        case 93: return .init(0x4c)
        case 94: return .init(0x4d)
        case 95: return .init(0x47)
        case 96: return .init(0x48)
        case 97: return .init(0x49)
        case 98: return .init(0x52)
        case 99: return .init(0x53)
        case 100: return .init(0x56)
        case 101: return .init(0x5d, extended: true)
        case 224: return .init(0x1d)
        case 225: return .init(0x2a)
        case 226: return .init(0x38)
        case 227: return .init(0x5b, extended: true)
        case 228: return .init(0x1d, extended: true)
        case 229: return .init(0x36)
        case 230: return .init(0x38, extended: true)
        case 231: return .init(0x5c, extended: true)
        default: return nil
        }
    }
}

/// Aggregate UIKit modifier flags are reconciled before the associated key or text event.
public struct DesktopModifierState: Sendable {
    private var pressed: Set<DesktopKey> = []
    public init() {}
    public mutating func update(shift: Bool, control: Bool, alternate: Bool, command: Bool,
                                changedUsage: Int? = nil, isDown: Bool? = nil) -> [(DesktopKey, Bool)] {
        let modifiers: [([DesktopKey], Bool)] = [([.init(0x2a), .init(0x36)], shift),
            ([.init(0x1d), .init(0x1d, extended: true)], control),
            ([.init(0x38), .init(0x38, extended: true)], alternate),
            ([.init(0x5b, extended: true), .init(0x5c, extended: true)], command)]
        let changed = changedUsage.flatMap { (224...231).contains($0) ? DesktopKeyboard.key(hidUsage: $0) : nil }
        var changes: [(DesktopKey, Bool)] = []
        for (keys, flag) in modifiers {
            if let changed, keys.contains(changed), let isDown, pressed.contains(changed) != isDown {
                if isDown { pressed.insert(changed) } else { pressed.remove(changed) }
                changes.append((changed, isDown))
            }
            let explicitDown = changed.map { keys.contains($0) && isDown == true } ?? false
            if !flag && !explicitDown {
                for key in keys where pressed.contains(key) { pressed.remove(key); changes.append((key, false)) }
            } else if flag && !keys.contains(where: { pressed.contains($0) }),
                      !(changed.map { keys.contains($0) && isDown == false } ?? false), let key = keys.first {
                pressed.insert(key); changes.append((key, true))
            }
        }
        return changes
    }
    public mutating func reset() { pressed.removeAll() }
}
