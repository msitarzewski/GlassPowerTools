//
//  DesktopFoldKeysPanel.swift
//  Glass Power Tools — GlassDesktop
//
//  Below an iPhone Duo's fold, stood like a laptop (D93): the desktop's own keyboard
//  (`DesktopFoldKeyboard`), and under it three shortcut buttons, Escape and the trackpad, all on
//  screen at once. A shortcut button sends its keys; held, it records the next key typed on the
//  keyboard, with what is armed, in their place, on this device. The iPhone's keyboard, for text,
//  is the deck's switch.
//

#if os(iOS)
import SwiftUI

struct DesktopFoldKeysPanel: View {
    let session: DesktopSessionModel
    @State private var shortcuts: [DesktopFoldChord] = []
    /// The shortcut button being recorded: the next key typed becomes it.
    @State private var recording: Int?
    /// Felt on every key.
    @State private var presses = 0
    private static let spacing: CGFloat = 5
    private var remote: DesktopProtocol { session.connection.protocol }

    var body: some View {
        GeometryReader { geometry in
            let keysHeight = min(geometry.size.height * 0.6, 5 * 44 + 4 * Self.spacing)
            VStack(spacing: 8) {
                keyboard(width: geometry.size.width, height: keysHeight)
                HStack(spacing: Self.spacing) {
                    shortcutGrid
                        .frame(width: min(150, geometry.size.width * 0.26))
                    DesktopTrackpadPad(session: session, compact: true)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .disabled(!session.isConnected)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: presses)
        .onAppear { shortcuts = DesktopFoldShortcuts.load(for: remote) }
    }

    // MARK: - The keyboard

    private func keyboard(width: CGFloat, height: CGFloat) -> some View {
        let rowHeight = (height - 4 * Self.spacing) / 5
        return VStack(spacing: Self.spacing) {
            ForEach(Array(DesktopFoldKeyboard.rows.enumerated()), id: \.offset) { _, row in
                let unit = (width - CGFloat(row.count - 1) * Self.spacing) / row.reduce(0) { $0 + $1.width }
                HStack(spacing: Self.spacing) {
                    ForEach(row) { key in
                        keyButton(key)
                            .frame(width: unit * key.width, height: rowHeight)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("desktop-fold-keys")
    }

    private func keyButton(_ key: DesktopFoldKey) -> some View {
        Button { press(key) } label: {
            Text(title(of: key))
                .font(.system(size: title(of: key).count > 1 ? 13 : 17, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(DesktopFoldKeyStyle(lit: isLit(key)))
        .buttonRepeatBehavior(key.repeats ? .enabled : .disabled)
        .accessibilityLabel(spoken(key))
        .accessibilityAddTraits(isLit(key) ? .isSelected : [])
        .accessibilityIdentifier("desktop-fold-key-\(key.id)")
    }

    private func title(of key: DesktopFoldKey) -> String {
        switch key.action {
        case .modifier(let modifier): return DesktopFoldKeyboard.label(modifier, on: remote)
        case .fn: return key.label
        case .key:
            if session.fnArmed, let fn = key.fnLabel { return fn }
            if session.armedModifiers.contains(.shift), let shifted = key.shifted { return shifted }
            return key.label
        }
    }

    private func spoken(_ key: DesktopFoldKey) -> String {
        if case .modifier(let modifier) = key.action { return DesktopFoldKeyboard.spoken(modifier, on: remote) }
        if session.fnArmed, let fn = key.fnLabel { return fn }
        return key.spoken ?? key.label
    }

    private func isLit(_ key: DesktopFoldKey) -> Bool {
        switch key.action {
        case .modifier(let modifier): session.armedModifiers.contains(modifier)
        case .fn: session.fnArmed
        case .key: false
        }
    }

    private func press(_ key: DesktopFoldKey) {
        presses += 1
        // Recording a shortcut: the key, with what is armed, is kept instead of sent.
        if let index = recording, let sent = key.sent(fn: session.fnArmed) {
            let label = session.fnArmed ? (key.fnLabel ?? key.label) : key.label
            shortcuts[index] = DesktopFoldChord(session.takeArmedForRecording(), sent, label: label)
            DesktopFoldShortcuts.save(shortcuts, for: remote)
            recording = nil
            return
        }
        session.pressFoldKey(key)
    }

    // MARK: - Shortcuts and Escape

    private var shortcutGrid: some View {
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            GridRow {
                shortcutButton(0)
                shortcutButton(1)
            }
            GridRow {
                shortcutButton(2)
                Button {
                    presses += 1
                    session.sendAccessoryKey(DesktopAccessoryKeys.escape)
                } label: {
                    Text("esc").font(.system(size: 14))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(DesktopFoldKeyStyle(lit: false))
                .accessibilityLabel("Escape")
                .accessibilityIdentifier("desktop-fold-key-escape")
            }
        }
    }

    private func shortcutButton(_ index: Int) -> some View {
        let chord = shortcuts.indices.contains(index) ? shortcuts[index] : nil
        let isRecording = recording == index
        let title = isRecording ? "Type…" : chord?.title(on: remote) ?? ""
        return Text(title)
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isRecording ? Color.accentColor : Color.white.opacity(0.22),
                        in: .rect(cornerRadius: 9, style: .continuous))
            .foregroundStyle(.white)
            .contentShape(.rect)
            .onTapGesture { tapShortcut(index) }
            .onLongPressGesture(minimumDuration: 0.5) { startRecording(index) }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isRecording ? "Recording shortcut \(index + 1)" : title)
            .accessibilityHint("Touch and hold to record another shortcut here.")
            .accessibilityAction { tapShortcut(index) }
            .accessibilityAction(named: "Record Shortcut") { startRecording(index) }
            .accessibilityIdentifier("desktop-fold-shortcut-\(index)")
    }

    private func tapShortcut(_ index: Int) {
        presses += 1
        if recording == index { recording = nil; return }
        guard shortcuts.indices.contains(index) else { return }
        session.sendChord(shortcuts[index])
    }

    private func startRecording(_ index: Int) {
        presses += 1
        recording = index
    }
}

/// A key: dark, lit while its modifier is armed, lighter while pressed.
private struct DesktopFoldKeyStyle: ButtonStyle {
    var lit: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(fill(pressed: configuration.isPressed), in: .rect(cornerRadius: 7, style: .continuous))
    }

    private func fill(pressed: Bool) -> Color {
        if lit { return .accentColor }
        return .white.opacity(pressed ? 0.34 : 0.16)
    }
}
#endif
