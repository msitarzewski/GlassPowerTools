//
//  GlassFoldDeck.swift
//  Glass Power Tools — GlassConnectionUI
//
//  The deck below an iPhone Duo's fold (D93, 2026-10-31, the owner: "the top screen a remote
//  desktop, then the bottom a keyboard and a toggleable trackpad"). Stood like a small laptop, a
//  tool's work sits above the fold and this below it: a strip just under the fold, with the
//  keyboard switch and the tool's own keys, then the system keyboard or the tool's panel. Apple:
//  content above, controls below, and every control reachable in every pose (tech talks 111463,
//  111466). UTM ships the same for its virtual machines: a keyboard or a touchpad below the fold.
//
//  Flat, folded, held like a book, and on every other device, the work fills the view and nothing
//  here is drawn.
//

import SwiftUI

/// What the deck does with the keyboard as the phone folds and unfolds: the keyboard (or the
/// tool's panel) comes up on a fresh fold only; put away, it stays away until the next fold; and
/// unfolding puts it back as it was before the fold (UTM's rule). Pure, so it is tested alone.
public struct GlassFoldDeckPolicy: Equatable, Sendable {
    /// What comes up on a fresh fold.
    public enum Start: Equatable, Sendable {
        /// The keyboard: a terminal, the editor, a query.
        case keyboard
        /// The tool's panel, the keyboard put away: a remote desktop's trackpad.
        case panel
    }

    /// What the keyboard should do now.
    public enum Action: Equatable, Sendable {
        case show
        case hide
    }

    public let start: Start
    /// Whether the keyboard was up before the fold; nil while the phone isn't stood like a laptop.
    public private(set) var keyboardBeforeFold: Bool?

    public init(start: Start) {
        self.start = start
    }

    /// The phone was stood like a laptop (`laptop` true) or left that pose. Returns what the
    /// keyboard should do, if anything.
    public mutating func pose(laptop: Bool, keyboardShown: Bool) -> Action? {
        if laptop {
            guard keyboardBeforeFold == nil else { return nil }
            keyboardBeforeFold = keyboardShown
            switch start {
            case .keyboard: return keyboardShown ? nil : .show
            case .panel: return keyboardShown ? .hide : nil
            }
        }
        guard let before = keyboardBeforeFold else { return nil }
        keyboardBeforeFold = nil
        guard before != keyboardShown else { return nil }
        return before ? .show : .hide
    }
}

/// The keyboard as the tool drives it: its own first responder, so the deck asks rather than acts.
public struct GlassFoldDeckKeyboard {
    public var show: @MainActor () -> Void
    public var hide: @MainActor () -> Void

    public init(show: @escaping @MainActor () -> Void, hide: @escaping @MainActor () -> Void) {
        self.show = show
        self.hide = hide
    }
}

/// The tool's panel: what fills the lower half while the keyboard is put away, and what the
/// switch calls it.
public struct GlassFoldDeckPanel<Content: View> {
    public let title: String
    public let systemImage: String
    public let content: Content

    public init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }
}

#if os(iOS)
import UIKit

/// The work above the fold and the deck below it, for a phone stood like a small laptop. `fold`
/// is kept up to date for the tool too (a terminal lays its bar out around a book's fold).
public struct GlassFoldDeck<Work: View, Strip: View, Panel: View>: View {
    @Binding private var fold: GlassDeviceFold?
    private let keyboard: GlassFoldDeckKeyboard
    private let panel: GlassFoldDeckPanel<Panel>?
    private let work: Work
    private let strip: Strip
    /// The light or dark the deck's controls are drawn in: a dark terminal's, not the system's.
    private let controlsColorScheme: ColorScheme?
    /// Whether the tool wants its keyboard, where it knows: a remote desktop asks for it explicitly.
    /// Put away, the keyboard counts as away whatever frame the system still reports (on a Duo stood
    /// like a laptop, an empty keyboard reported the whole lower half, D93).
    private let keyboardWanted: Bool?
    /// The way back to the library, first in the strip, for a tool that puts its bar away while the
    /// phone is stood like a laptop (the desktop, D93): the bar's chevron, moved under the fold.
    private let back: (@MainActor () -> Void)?
    @State private var policy: GlassFoldDeckPolicy
    @State private var frame: CGRect = .zero
    @State private var keyboardShown = false
    /// The keyboard has been up since the fold: a request to show it took, so none is repeated.
    @State private var keyboardAppearedSinceFold = false
    @Environment(\.colorScheme) private var colorScheme

    /// The strip's height, under the fold, where the keyboard leaves room above its keys (about 60
    /// points without a prediction row; measured 2026-10-21).
    public static var stripHeight: CGFloat { 44 }

    public init(fold: Binding<GlassDeviceFold?>, start: GlassFoldDeckPolicy.Start = .keyboard,
                keyboard: GlassFoldDeckKeyboard, keyboardWanted: Bool? = nil, panel: GlassFoldDeckPanel<Panel>?,
                controlsColorScheme: ColorScheme? = nil, back: (@MainActor () -> Void)? = nil,
                @ViewBuilder work: () -> Work, @ViewBuilder strip: () -> Strip) {
        _fold = fold
        self.keyboard = keyboard
        self.keyboardWanted = keyboardWanted
        self.back = back
        self.panel = panel
        self.controlsColorScheme = controlsColorScheme
        self.work = work()
        self.strip = strip()
        _policy = State(initialValue: GlassFoldDeckPolicy(start: start))
    }

    /// The keyboard is up: on screen, and wanted where the tool says.
    private var keyboardUp: Bool { keyboardShown && (keyboardWanted ?? true) }

    /// The fold across the view: the phone stood like a laptop.
    private var laptopFold: GlassDeviceFold? {
        fold.flatMap { $0.isAcross ? $0 : nil }
    }

    public var body: some View {
        VStack(spacing: 0) {
            work
                // Down to the fold. With the keyboard up its top is the fold, so this is all the
                // room there is; with it away, the deck has the rest.
                .frame(height: laptopFold.map { max(0, min(frame.height, $0.globalFrame.minY - frame.minY)) })
            if laptopFold != nil { Spacer(minLength: 0) }
        }
        .glassGlobalFrame($frame)
        // Placed on the screen rather than in the stack: with the keyboard up the stack ends at the
        // fold, and the strip goes in the keyboard's room above its keys.
        .overlay(alignment: .top) {
            if let fold = laptopFold {
                deck(below: fold)
                    .environment(\.colorScheme, controlsColorScheme ?? colorScheme)
                    .offset(y: fold.globalFrame.maxY - frame.minY + 4)
            }
        }
        // The fold, read from the window, which nothing shortens.
        .glassDeviceFold($fold)
        .background {
            GlassKeyboardPresence { keyboardShown = $0 }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: laptopFold != nil, initial: true) { _, laptop in
            keyboardAppearedSinceFold = false
            apply(policy.pose(laptop: laptop, keyboardShown: keyboardUp), retry: laptop)
        }
        .onChange(of: keyboardUp) { _, up in
            if up { keyboardAppearedSinceFold = true }
        }
    }

    private func deck(below fold: GlassDeviceFold) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if let back { backButton(back) }
                keyboardSwitch
                strip
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.stripHeight)
            if !keyboardUp, let panel {
                panel.content
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, frame.maxY - fold.globalFrame.maxY - 4 - Self.stripHeight - 8))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("glass-fold-deck-panel")
            }
        }
    }

    /// The keyboard, or the tool's panel. With no panel, the keyboard alone, shown and put away.
    private var keyboardSwitch: some View {
        Button {
            if keyboardUp { keyboard.hide() } else { keyboard.show() }
        } label: {
            if keyboardUp {
                Label(panel?.title ?? "Dismiss Keyboard", systemImage: panel?.systemImage ?? "keyboard.chevron.compact.down")
            } else {
                Label("Show Keyboard", systemImage: "keyboard")
            }
        }
        .labelStyle(.iconOnly)
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityIdentifier("glass-fold-deck-keyboard")
    }

    private func backButton(_ back: @escaping @MainActor () -> Void) -> some View {
        Button("Connections", systemImage: "chevron.backward") { back() }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityIdentifier("glass-fold-deck-back")
    }

    /// A fresh fold's keyboard is asked for again a moment later: the first request can arrive
    /// before the pose settles and be lost (UTM asks at 0.8 s and 2.5 s).
    private func apply(_ action: GlassFoldDeckPolicy.Action?, retry: Bool) {
        guard let action else { return }
        switch action {
        case .show:
            keyboard.show()
            guard retry else { return }
            Task { @MainActor in
                for delay in [800, 1_700] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    // Once it has come up, putting it away is the person's choice: never undone.
                    guard laptopFold != nil, !keyboardAppearedSinceFold else { return }
                    keyboard.show()
                }
            }
        case .hide:
            keyboard.hide()
        }
    }
}

extension GlassFoldDeck where Panel == EmptyView {
    /// A deck with no panel: the switch shows and puts away the keyboard.
    public init(fold: Binding<GlassDeviceFold?>, start: GlassFoldDeckPolicy.Start = .keyboard,
                keyboard: GlassFoldDeckKeyboard, controlsColorScheme: ColorScheme? = nil,
                @ViewBuilder work: () -> Work, @ViewBuilder strip: () -> Strip) {
        self.init(fold: fold, start: start, keyboard: keyboard, panel: nil,
                  controlsColorScheme: controlsColorScheme, work: work, strip: strip)
    }
}

/// Whether the software keyboard covers part of this view's window: the keyboard's frame, from
/// the screen's coordinates into the window's. A hardware keyboard leaves only a bar of
/// suggestions, which doesn't count.
private struct GlassKeyboardPresence: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> PresenceView { PresenceView(onChange: onChange) }

    func updateUIView(_ view: PresenceView, context: Context) { view.onChange = onChange }

    final class PresenceView: UIView {
        var onChange: (Bool) -> Void

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(changed(_:)),
                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            center.addObserver(self, selector: #selector(hidden(_:)),
                               name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        required init?(coder: NSCoder) { nil }

        @objc private func changed(_ note: Notification) {
            guard let window, let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let inWindow = window.convert(end, from: window.screen.coordinateSpace)
            onChange(window.bounds.intersection(inWindow).height > 120)
        }

        @objc private func hidden(_ note: Notification) {
            onChange(false)
        }
    }
}
#endif
