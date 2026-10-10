//
//  GlassSettingTitle.swift
//  Glass Power Tools — GlassConnectionUI
//
//  A setting's name, as every settings row draws it — and, on a This Window page, the way back.
//  The owner, on the Vision Pro (2026-10-10): the tab already says "This Window", so a caption
//  saying "This window only" under each row was redundant; the way back is a tiny icon beside the
//  setting's name, with a tooltip — "Opacity ↺". A row the window does not set shows its name
//  alone.
//
//  The name is drawn by whichever control owns it (a slider's `LabeledContent`, a stepper row, the
//  tint picker), so the reset reaches it through the environment: GlassLayers'
//  `GlassWindowSettingRow` sets `glassSettingReset` for its control while the window sets the
//  value, and the control draws its name with `GlassSettingTitle`. Everywhere else the
//  environment is empty and the name is plain text.
//

import SwiftUI

/// The way back for one setting a window sets for itself: what `GlassSettingTitle` offers beside
/// the setting's name.
public struct GlassSettingReset {
    /// The setting's name, for VoiceOver: "Opacity".
    public let settingTitle: String
    /// Where the setting lives for every window, as the person knows it: "All Terminals",
    /// "Appearance".
    public let source: String
    /// Stable, for UI tests: `window-setting-reset.<key>`.
    public let identifier: String
    public let action: @MainActor () -> Void

    public init(settingTitle: String, source: String, identifier: String, action: @escaping @MainActor () -> Void) {
        self.settingTitle = settingTitle
        self.source = source
        self.identifier = identifier
        self.action = action
    }

    /// The tooltip: on gaze on Vision Pro, on hover with a pointer on iPad and the Mac.
    public var help: String { "Reset to \(source)" }

    /// What VoiceOver says for the button.
    public var accessibilityLabel: String { "Reset \(settingTitle) to \(source)" }
}

extension EnvironmentValues {
    /// The reset `GlassSettingTitle` offers beside a setting's name; nil when there is nothing to
    /// return to (the setting follows its source, or the page is not a window's).
    @Entry public var glassSettingReset: GlassSettingReset? = nil
}

/// A setting's name, with the tiny reset button beside it when the environment carries one.
///
/// Draw a control's name with it wherever the control would draw its own. For a system control,
/// whose own label may not pass a tap through to a button inside it, put the control in a
/// `LabeledContent` and hide its label:
///
/// ```swift
/// LabeledContent {
///     Picker("Material", selection: $material) { … }.labelsHidden()
/// } label: {
///     GlassSettingTitle("Material")
/// }
/// ```
///
/// `GlassSettingLabeled` is that shape, ready made.
public struct GlassSettingTitle: View {
    private let title: String
    @Environment(\.glassSettingReset) private var reset

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 2) {
            Text(title)
            if let reset {
                GlassSettingResetButton(reset: reset)
            }
        }
    }
}

/// A system control under a `GlassSettingTitle`: the control keeps its own name for VoiceOver and
/// hides it on screen, so the title (and its reset) is the only name drawn.
public struct GlassSettingLabeled<Control: View>: View {
    private let title: String
    private let control: Control

    public init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    public var body: some View {
        LabeledContent {
            control
                .labelsHidden()
                // A toggle here is still a form row's switch, as it is when it draws its own name.
                .toggleStyle(.switch)
        } label: {
            GlassSettingTitle(title)
        }
    }
}

/// The tiny ↺ beside a setting's name. It looks small and stays easy to reach: the hit area, and
/// the gaze highlight on Vision Pro, are larger than the glyph.
struct GlassSettingResetButton: View {
    let reset: GlassSettingReset

    var body: some View {
        Button(action: reset.action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                // Room for the gaze highlight on Vision Pro, close enough to read as the name's.
                .padding(Self.padding)
                .contentShape(.interaction, Rectangle().inset(by: -Self.reach))
                #if !os(macOS)
                .contentShape(.hoverEffect, Circle())
                #endif
        }
        // Borderless, so the Form row does not become one big button.
        .buttonStyle(.borderless)
        .help(reset.help)
        .accessibilityLabel(reset.accessibilityLabel)
        .accessibilityIdentifier(reset.identifier)
    }

    /// Around the glyph, inside the drawn button.
    private static var padding: CGFloat {
        #if os(visionOS)
        5
        #else
        2
        #endif
    }

    /// How far beyond the drawn button a tap still lands on it.
    private static var reach: CGFloat {
        #if os(visionOS)
        10
        #else
        4
        #endif
    }
}
