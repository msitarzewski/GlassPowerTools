//
//  DesktopAccessoryKeys.swift
//  Glass Power Tools — GlassDesktop
//
//  The keys a remote desktop needs that a headset's or a phone's keyboard lacks, as the terminal
//  offers them (the owner, 2026-10-11: "the full set of tools and function accessory keys for
//  VNC/desktop sessions too. Including the arrow nav"): Escape and Tab; Control, Option, Command and
//  Shift for the next key, since the software keyboard has none of them; the navigation keys; F1–F12;
//  and a pad that sends an arrow for each step it is dragged, as the terminal's cursor pad moves its
//  cursor. The same menu and pad sit in the desktop's toolbar and above the software keyboard.
//

import SwiftUI

/// The keys the menu sends, as RDP set-1 scancodes, which every transport takes.
enum DesktopAccessoryKeys {
    static let escape = DesktopKey(0x01)
    static let tab = DesktopKey(0x0f)
    static let up = DesktopKey(0x48, extended: true)
    static let down = DesktopKey(0x50, extended: true)
    static let left = DesktopKey(0x4b, extended: true)
    static let right = DesktopKey(0x4d, extended: true)
    static let home = DesktopKey(0x47, extended: true)
    static let end = DesktopKey(0x4f, extended: true)
    static let pageUp = DesktopKey(0x49, extended: true)
    static let pageDown = DesktopKey(0x51, extended: true)
    static let forwardDelete = DesktopKey(0x53, extended: true)

    /// A key pressed and released, the held modifiers down before it and up after it in reverse.
    static func tap(_ key: DesktopKey, holding held: [DesktopKey] = []) -> [DesktopInput.Event] {
        held.map { .key($0.scancode, $0.extended, true, false) }
            + [.key(key.scancode, key.extended, true, false), .key(key.scancode, key.extended, false, false)]
            + held.reversed().map { .key($0.scancode, $0.extended, false, false) }
    }

    /// F1–F12.
    static func function(_ number: Int) -> DesktopKey? {
        switch number {
        case 1...10: DesktopKey(UInt16(0x3a + number))
        case 11: DesktopKey(0x57)
        case 12: DesktopKey(0x58)
        default: nil
        }
    }
}

/// A modifier held for the next key: pressed before it and released after it.
public enum DesktopStickyModifier: String, CaseIterable, Sendable, Identifiable {
    case control, option, command, shift

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        }
    }

    var symbol: String { self == .command ? "command" : rawValue }

    /// Option is Alt, and Command the left Windows key, as a PC keyboard sends them; a Mac's VNC
    /// session sends Alt as Meta, which a Mac reads as Option (`GlassVNCSession`).
    var key: DesktopKey {
        switch self {
        case .control: DesktopKey(0x1d)
        case .option: DesktopKey(0x38)
        case .command: DesktopKey(0x5b, extended: true)
        case .shift: DesktopKey(0x2a)
        }
    }
}

// MARK: - The menu

/// Escape, Tab, the modifiers for the next key, navigation and function keys.
struct DesktopKeysMenu: View {
    let session: DesktopSessionModel
    /// Opens the sheet that types text, where the window has no software keyboard of its own to
    /// type with (Vision Pro and the Mac).
    var typeText: (() -> Void)?

    var body: some View {
        Menu {
            if let typeText {
                Button("Type Text…", systemImage: "character.cursor.ibeam") { typeText() }
                    .accessibilityIdentifier("session.type-text")
                Divider()
            }
            Button("Escape", systemImage: "escape") { session.sendAccessoryKey(DesktopAccessoryKeys.escape) }
            Button("Tab", systemImage: "arrow.right.to.line") { session.sendAccessoryKey(DesktopAccessoryKeys.tab) }
            Section("For the Next Key") {
                ForEach(DesktopStickyModifier.allCases) { modifier in
                    Toggle(isOn: Binding(get: { session.armedModifiers.contains(modifier) },
                                         set: { _ in session.toggleArmed(modifier) })) {
                        Label(modifier.title, systemImage: modifier.symbol)
                    }
                }
            }
            Menu("Navigation", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                Button("Up", systemImage: "arrow.up") { session.sendAccessoryKey(DesktopAccessoryKeys.up) }
                Button("Down", systemImage: "arrow.down") { session.sendAccessoryKey(DesktopAccessoryKeys.down) }
                Button("Left", systemImage: "arrow.left") { session.sendAccessoryKey(DesktopAccessoryKeys.left) }
                Button("Right", systemImage: "arrow.right") { session.sendAccessoryKey(DesktopAccessoryKeys.right) }
                Divider()
                Button("Home", systemImage: "arrow.up.to.line") { session.sendAccessoryKey(DesktopAccessoryKeys.home) }
                Button("End", systemImage: "arrow.down.to.line") { session.sendAccessoryKey(DesktopAccessoryKeys.end) }
                Button("Page Up", systemImage: "chevron.up.2") { session.sendAccessoryKey(DesktopAccessoryKeys.pageUp) }
                Button("Page Down", systemImage: "chevron.down.2") { session.sendAccessoryKey(DesktopAccessoryKeys.pageDown) }
                Button("Forward Delete", systemImage: "delete.right") { session.sendAccessoryKey(DesktopAccessoryKeys.forwardDelete) }
            }
            Menu("Function Keys", systemImage: "f.square") {
                ForEach(1...12, id: \.self) { number in
                    Button("F\(number)") { if let key = DesktopAccessoryKeys.function(number) { session.sendAccessoryKey(key) } }
                }
            }
        } label: {
            Label(session.armedModifiers.isEmpty ? "Keys" : "Keys: \(armedTitle)", systemImage: "keyboard.badge.ellipsis")
        }
        .disabled(!session.isConnected)
        .help("Keys")
        .accessibilityIdentifier("session.keys")
        .accessibilityHint("Type text, Escape, Tab, modifiers for the next key, navigation and function keys.")
    }

    private var armedTitle: String {
        DesktopStickyModifier.allCases.filter(session.armedModifiers.contains).map(\.title).joined(separator: " ")
    }
}

// MARK: - The arrow pad

/// Drag to send arrow keys: one for each step the finger travels, along the axis it first moves on,
/// as the terminal's cursor pad moves its cursor. Modifiers armed for the next key are held for the
/// whole drag, so Shift selects as it goes.
struct DesktopArrowPad: View {
    let session: DesktopSessionModel
    @State private var sent = (horizontal: 0, vertical: 0)
    @State private var axis: DesktopArrowAxis?

    var body: some View {
        Label("Arrows", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            #if os(visionOS)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            #else
            .labelStyle(.iconOnly)
            .padding(.horizontal, 10)
            #endif
            .frame(minHeight: 36)
            .background(.tint.opacity(0.18), in: .capsule)
            .contentShape(.capsule)
            .gesture(DragGesture(minimumDistance: 0).onChanged(changed).onEnded { _ in finish() })
            .opacity(session.isConnected ? 1 : 0.4)
            .allowsHitTesting(session.isConnected)
            .help("Drag to send arrow keys")
            .accessibilityLabel("Arrow keys")
            .accessibilityHint("Drag to send arrow keys, one a step.")
            .accessibilityAction(named: "Up") { session.sendAccessoryKey(DesktopAccessoryKeys.up) }
            .accessibilityAction(named: "Down") { session.sendAccessoryKey(DesktopAccessoryKeys.down) }
            .accessibilityAction(named: "Left") { session.sendAccessoryKey(DesktopAccessoryKeys.left) }
            .accessibilityAction(named: "Right") { session.sendAccessoryKey(DesktopAccessoryKeys.right) }
            .accessibilityIdentifier("session.arrow-pad")
    }

    private func changed(_ value: DragGesture.Value) {
        if axis == nil {
            axis = DesktopArrowSteps.axis(width: value.translation.width, height: value.translation.height)
            if axis != nil { session.beginArrowDrag() }
        }
        guard let axis else { return }
        let target = DesktopArrowSteps.steps(width: value.translation.width, height: value.translation.height, axis: axis)
        for key in DesktopArrowSteps.keys(from: sent, to: target) { session.sendArrowStep(key) }
        sent = target
    }

    private func finish() {
        if axis != nil { session.endArrowDrag() }
        axis = nil
        sent = (0, 0)
    }
}

enum DesktopArrowAxis { case horizontal, vertical }

/// Steps of a drag, in arrow keys.
enum DesktopArrowSteps {
    /// Points of travel per arrow key.
    static let step: Double = 14
    /// Travel before the drag chooses its axis.
    static let decision: Double = 6

    static func axis(width: Double, height: Double) -> DesktopArrowAxis? {
        guard max(abs(width), abs(height)) >= decision else { return nil }
        return abs(width) >= abs(height) ? .horizontal : .vertical
    }

    /// Whole steps along the chosen axis; none along the other.
    static func steps(width: Double, height: Double, axis: DesktopArrowAxis) -> (horizontal: Int, vertical: Int) {
        switch axis {
        case .horizontal: (Int((width / step).rounded(.towardZero)), 0)
        case .vertical: (0, Int((height / step).rounded(.towardZero)))
        }
    }

    /// The arrows that take the steps sent to the steps wanted.
    static func keys(from sent: (horizontal: Int, vertical: Int), to target: (horizontal: Int, vertical: Int)) -> [DesktopKey] {
        let horizontal = target.horizontal - sent.horizontal, vertical = target.vertical - sent.vertical
        return Array(repeating: horizontal > 0 ? DesktopAccessoryKeys.right : DesktopAccessoryKeys.left, count: abs(horizontal))
            + Array(repeating: vertical > 0 ? DesktopAccessoryKeys.down : DesktopAccessoryKeys.up, count: abs(vertical))
    }
}
