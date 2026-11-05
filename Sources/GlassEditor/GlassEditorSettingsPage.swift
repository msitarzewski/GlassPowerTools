//
//  GlassEditorSettingsPage.swift
//  Glass Power Tools — GlassEditor
//
//  The editor's preferences, in the app's one settings surface.
//
//  They were a menu hanging off a gear in the toolbar, which is two mistakes: a gear in a toolbar
//  means "settings" and should go where the settings are, and a preference that lives in one
//  window's menu is invisible from every other window. `GlassCapabilitySettingsPage` is how the
//  terminal, database and desktop contribute theirs; the editor is not a capability — a file is not
//  a service on a machine — so it registers the page directly with the registry from the
//  composition root.
//

import SwiftUI
import GlassShell
import GlassEditorCore
import GlassEditorUI
import GlassConnectionUI

struct GlassEditorSettingsView: View {
    @Bindable private var preferences: GlassEditorPreferences
    /// Spelling and substitutions, app-wide: on the Mac also Edit ▸ Spelling and Grammar and Edit ▸ Substitutions.
    @Bindable private var checking = GlassTextChecking.shared

    public init(preferences: GlassEditorPreferences) {
        self.preferences = preferences
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Show Line Numbers", isOn: $preferences.showsLineNumbers)
                Toggle("Wrap Long Lines", isOn: $preferences.wrapsLines)
            } header: {
                Text("Text")
            } footer: {
                Text("Applies to every open document, and to documents opened later.")
            }

            Section {
                // The same range the terminal's font control uses, and the same two keys reach it
                // from an editor window: ⌘+ and ⌘−.
                LabeledContent("Text Size") {
                    HStack(spacing: 12) {
                        Button("Smaller", systemImage: "textformat.size.smaller") {
                            preferences.decreaseFontSize()
                        }
                        .labelStyle(.iconOnly)
                        Text("\(Int(preferences.fontSize)) pt")
                            .font(.callout.monospacedDigit())
                            .frame(minWidth: 44)
                        Button("Larger", systemImage: "textformat.size.larger") {
                            preferences.increaseFontSize()
                        }
                        .labelStyle(.iconOnly)
                        Button("Actual Size") { preferences.resetFontSize() }
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Size")
            } footer: {
                SizeFooter()
            }

            // TextEdit's switches, where iPad and Vision Pro can reach them (2026-11-03); the Mac has them in its Edit
            // menu too. The ones UIKit has a text view do, there.
            Section {
                Toggle("Check Spelling While Typing", isOn: $checking.checksSpellingWhileTyping)
                Toggle("Correct Spelling Automatically", isOn: $checking.correctsSpellingAutomatically)
                #if os(macOS)
                Toggle("Check Grammar With Spelling", isOn: $checking.checksGrammarWithSpelling)
                #endif
                Toggle("Smart Quotes", isOn: $checking.smartQuotes)
                Toggle("Smart Dashes", isOn: $checking.smartDashes)
                Toggle("Smart Copy/Paste", isOn: $checking.smartCopyPaste)
                #if os(macOS)
                Toggle("Smart Links", isOn: $checking.smartLinks)
                Toggle("Data Detectors", isOn: $checking.dataDetectors)
                Toggle("Text Replacement", isOn: $checking.textReplacement)
                #endif
            } header: {
                Text("Spelling and Substitutions")
            } footer: {
                Text("Off until you turn them on: in code, a straight quote is part of the language and most words aren't English. They apply to every Editor window, and never to a database's SQL.")
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("editor-settings-page")
    }
}

/// The Size section's footer, which says where one window's own size is set.
private struct SizeFooter: View {
    var body: some View {
        // W23: these are every window's, and a window can keep its own — where there are windows: a phone has none,
        // and no This Window either.
        if GlassWindowPresentation.canOpenWindows {
            Text("These change every editor window. To change one window — its glass, text size, line numbers or wrapping — choose Settings (the gear) in its toolbar, then This Window.")
        }
    }
}

public extension GlassEditorRuntime {
    /// The page this runtime contributes to the settings surface. Registered by the composition
    /// root, which is the only place that knows about both the shell and the editor.
    var settingsPage: GlassCapabilitySettingsPage {
        let preferences = self.preferences
        return GlassCapabilitySettingsPage(id: "editor", title: "Editor", systemImage: "text.page") {
            AnyView(GlassEditorSettingsView(preferences: preferences))
        }
    }
}
