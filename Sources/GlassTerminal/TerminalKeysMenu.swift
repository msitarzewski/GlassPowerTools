//
//  TerminalKeysMenu.swift
//  Glass Power Tools — GlassTerminal
//
//  The keys a terminal needs that a software keyboard lacks — Escape, Tab, Control for the next key,
//  the arrows and F1–F12 — as a menu in the terminal window's own bar. On a phone and an iPad they
//  are the keyboard accessory's Terminal Keys; a Vision Pro shows no keyboard accessory to an app
//  built for it, so its terminal had no way to them without a paired keyboard (the owner,
//  2026-10-21: "the full key menu on terminal mode in visionPro").
//

import SwiftUI
import GlassTerminalEmulator

struct TerminalKeysMenu: View {
    let press: (SwiftTermAccessoryKey) -> Void

    var body: some View {
        Menu {
            Button("Escape", systemImage: "escape") { press(.escape) }
            Button("Tab", systemImage: "arrow.right.to.line.compact") { press(.tab) }
            Button("Control for Next Key", systemImage: "control") { press(.controlForNextKey) }
            Menu("Navigation", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                Button("Up", systemImage: "arrow.up") { press(.up) }
                Button("Down", systemImage: "arrow.down") { press(.down) }
                Button("Left", systemImage: "arrow.left") { press(.left) }
                Button("Right", systemImage: "arrow.right") { press(.right) }
            }
            Menu("Function Keys", systemImage: "f.square") {
                ForEach(1...12, id: \.self) { number in
                    Button("F\(number)") { press(.function(number)) }
                }
            }
        } label: {
            Label("Keys", systemImage: "keyboard.badge.ellipsis")
        }
        .accessibilityLabel("Terminal Keys")
        .accessibilityHint("Escape, Tab, Control for the next key, the arrows and function keys.")
        .accessibilityIdentifier("terminal-keys")
        .help("Keys")
    }
}

/// Drag to move the cursor: an arrow key for each step the finger travels, along the axis it first
/// moves on, as the keyboard accessory's cursor pad does. For a bar of the window's own, where the
/// accessory isn't shown: an iPhone Duo stood like a laptop (2026-10-21).
struct TerminalArrowPad: View {
    let press: (SwiftTermAccessoryKey) -> Void
    @State private var sent = (columns: 0, rows: 0)
    @State private var horizontal: Bool?

    /// Points dragged for one arrow: about a character across, a line down.
    static let columnStep: CGFloat = 12
    static let rowStep: CGFloat = 20

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .background(.tint.opacity(0.18), in: .circle)
            .contentShape(.circle)
            .gesture(DragGesture(minimumDistance: 0).onChanged(changed).onEnded { _ in
                horizontal = nil
                sent = (0, 0)
            })
            .accessibilityLabel("Drag to move cursor")
            .accessibilityHint("Drag to move by terminal character cells.")
            .accessibilityAction(named: "Move left") { press(.left) }
            .accessibilityAction(named: "Move right") { press(.right) }
            .accessibilityAction(named: "Move up") { press(.up) }
            .accessibilityAction(named: "Move down") { press(.down) }
            .accessibilityIdentifier("terminal-arrow-pad")
    }

    private func changed(_ value: DragGesture.Value) {
        let width = value.translation.width, height = value.translation.height
        if horizontal == nil, max(abs(width), abs(height)) >= 6 { horizontal = abs(width) >= abs(height) }
        guard let horizontal else { return }
        if horizontal {
            let target = Int((width / Self.columnStep).rounded(.towardZero))
            for _ in 0..<abs(target - sent.columns) { press(target > sent.columns ? .right : .left) }
            sent.columns = target
        } else {
            let target = Int((height / Self.rowStep).rounded(.towardZero))
            for _ in 0..<abs(target - sent.rows) { press(target > sent.rows ? .down : .up) }
            sent.rows = target
        }
    }
}
