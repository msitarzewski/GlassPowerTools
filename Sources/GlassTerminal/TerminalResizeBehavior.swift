//
//  TerminalResizeBehavior.swift
//  Glass Power Tools — GlassTerminal
//
//  D75 (the owner, 2026-10-16): "we need both a resize capability and a scale capability. For
//  example I may want a 120 x 40 terminal, but with a much smaller window." What resizing a
//  terminal's window does: its rows and columns follow it, as they always have, or they stay as
//  they were when Scale was chosen and the text grows and shrinks with the window
//  (`SwiftTermHostModel.setScaling`). A setting for every window, This Window for one, and a button
//  in the window's bar for this one ("Setting + bar button"). Vision Pro, the Mac and iPad windows
//  ("vision mac and ipad multi-window"); an iPhone's terminal fills its screen, so not there.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum TerminalResizeBehavior: String, CaseIterable, Sendable {
    /// The window's size sets the rows and columns.
    case changeGrid = "grid"
    /// The rows and columns stay; the text scales with the window.
    case scale

    var title: String {
        switch self {
        case .changeGrid: "Change Rows and Columns"
        case .scale: "Scale the Text"
        }
    }

    /// Where Scale is offered: every device but an iPhone.
    @MainActor static var isOffered: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        true
        #endif
    }
}

/// The window's bar's switch between the two, for this window (This Window's setting).
struct TerminalScaleToggle: View {
    @Binding var scales: Bool
    /// In the bar's overflow menu, where it is a checked item rather than a button.
    var inMenu = false

    var body: some View {
        if inMenu {
            toggle
        } else {
            // A button that stays pressed while the window scales.
            toggle.toggleStyle(.button).labelStyle(.iconOnly)
        }
    }

    private var toggle: some View {
        Toggle(isOn: $scales) {
            Label("Scale Text", systemImage: "aspectratio")
        }
        .accessibilityIdentifier("terminal-scale-text")
        .accessibilityValue(scales ? "Scaling" : "Off")
        .help(scales
              ? "Scale Text: the rows and columns stay as they are, and the text grows and shrinks with the window. Turn off to have resizing change the rows and columns."
              : "Scale Text: keep these rows and columns, and have the text grow and shrink with the window instead.")
    }
}
