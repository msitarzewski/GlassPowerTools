import Foundation
import Testing
@testable import GlassDesktop
import VNCKit

/// A desktop's accessory keys (2026-10-11): the Keys menu's keys, the modifiers held for the next key,
/// and the arrow pad's steps.
@Suite("Desktop accessory keys")
struct DesktopAccessoryKeysTests {
    private func keys(_ events: [DesktopInput.Event]) -> [String] {
        events.map { event in
            guard case let .key(code, extended, down, _) = event else { return "other" }
            return String(format: "%@%02x%@", extended ? "e" : "", code, down ? "↓" : "↑")
        }
    }

    @Test("a key taps alone, or inside the modifiers held for it, released in reverse")
    func taps() {
        #expect(keys(DesktopAccessoryKeys.tap(DesktopAccessoryKeys.escape)) == ["01↓", "01↑"])
        let held = [DesktopStickyModifier.command.key, DesktopStickyModifier.shift.key]
        #expect(keys(DesktopAccessoryKeys.tap(DesktopAccessoryKeys.left, holding: held))
                == ["e5b↓", "2a↓", "e4b↓", "e4b↑", "2a↑", "e5b↑"])
    }

    @Test("F1–F12 are set-1's function keys; Control, Option, Command and Shift the left ones")
    func keyCodes() {
        #expect((1...12).compactMap { DesktopAccessoryKeys.function($0)?.scancode }
                == [0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58])
        #expect(DesktopAccessoryKeys.function(0) == nil && DesktopAccessoryKeys.function(13) == nil)
        #expect(DesktopStickyModifier.allCases.map(\.key) == [DesktopKey(0x1d), DesktopKey(0x38), DesktopKey(0x5b, extended: true), DesktopKey(0x2a)])
        // Each reaches a VNC server as the keysym it should, and Option a Mac as Option (Meta).
        let keysyms = [DesktopAccessoryKeys.home, .init(0x5b, extended: true), DesktopAccessoryKeys.forwardDelete, DesktopKey(0x58)]
            .compactMap { RFBKeysym.keysym(scancode: $0.scancode, extended: $0.extended) }
        #expect(keysyms == [0xFF50, 0xFFEB, 0xFFFF, 0xFFC9])
        #expect(RFBKeysym.forMac(RFBKeysym.altLeft) == RFBKeysym.metaLeft && RFBKeysym.forMac(RFBKeysym.altRight) == RFBKeysym.metaRight)
        #expect(RFBKeysym.forMac(RFBKeysym.superLeft) == RFBKeysym.superLeft && RFBKeysym.forMac(0x61) == 0x61)
    }

    @Test("a letter or digit typed with a modifier armed goes as its key")
    func characters() {
        #expect(DesktopKeyboard.key(character: "c") == DesktopKey(0x2e) && DesktopKeyboard.key(character: "C") == DesktopKey(0x2e))
        #expect(DesktopKeyboard.key(character: "1") == DesktopKey(0x02) && DesktopKeyboard.key(character: "0") == DesktopKey(0x0b))
        #expect(DesktopKeyboard.key(character: "é") == nil && DesktopKeyboard.key(character: "ab") == nil && DesktopKeyboard.key(character: "/") == nil)
    }

    @Test("the arrow pad takes the axis it first moves on, a key a step, back as well as forward")
    func arrowSteps() {
        #expect(DesktopArrowSteps.axis(width: 3, height: 2) == nil, "not yet decided")
        #expect(DesktopArrowSteps.axis(width: 10, height: 4) == .horizontal)
        #expect(DesktopArrowSteps.axis(width: 2, height: -9) == .vertical)
        let three = DesktopArrowSteps.steps(width: 45, height: 30, axis: .horizontal)
        #expect(three.horizontal == 3 && three.vertical == 0, "the other axis is ignored")
        #expect(DesktopArrowSteps.keys(from: (0, 0), to: three) == Array(repeating: DesktopAccessoryKeys.right, count: 3))
        let back = DesktopArrowSteps.steps(width: -15, height: 0, axis: .horizontal)
        #expect(DesktopArrowSteps.keys(from: three, to: back) == Array(repeating: DesktopAccessoryKeys.left, count: 4))
        #expect(DesktopArrowSteps.keys(from: (0, 1), to: DesktopArrowSteps.steps(width: 0, height: -29, axis: .vertical))
                == Array(repeating: DesktopAccessoryKeys.up, count: 3))
    }
}
