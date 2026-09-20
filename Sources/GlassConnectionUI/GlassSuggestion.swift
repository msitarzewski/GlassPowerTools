//
//  GlassSuggestion.swift
//  Glass Power Tools — GlassConnectionUI
//
//  "You could keep this." A control for something the app has *noticed* rather than something the
//  user asked for.
//
//  The first case: a folder opened in an editor window that is not in the Projects list, so it is
//  a project you can work in and cannot find again. The app could add it silently — and should
//  not: the list is the user's, it syncs to their other devices, and something appearing there
//  because they opened a folder once is the kind of tidiness nobody asked for.
//
//  A lightbulb, because it is an idea and not a warning. Deliberately a shared component rather
//  than a button in one toolbar: the same shape is wanted for "this host has a service you have
//  not set up", "this key is not on that machine yet" and every other thing the app can see and
//  the user has not got to.
//

import SwiftUI

/// A noticed offer, in a toolbar or beside a list.
public struct GlassSuggestionButton: View {
    private let title: String
    private let help: String?
    private let action: () -> Void

    /// - Parameters:
    ///   - title: what accepting it does, as a verb — "Save as Project", not "Project".
    ///   - help: the fuller sentence, for the tooltip and for the accessibility hint.
    public init(_ title: String, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: GlassSuggestion.symbolName)
        }
        .help(help ?? title)
        .accessibilityHint(help ?? "")
        .accessibilityIdentifier("glass-suggestion")
    }
}

/// The vocabulary, so every surface that offers something uses the same glyph and wording.
public enum GlassSuggestion {
    /// The lightbulb. An offer, not a problem: `exclamationmark` shapes are for things that are
    /// wrong, and nothing here is wrong.
    public static let symbolName = "lightbulb"
}
