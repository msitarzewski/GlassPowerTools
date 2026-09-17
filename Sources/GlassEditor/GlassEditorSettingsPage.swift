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
import GlassConnectionUI

struct GlassEditorSettingsView: View {
    @Bindable private var preferences: GlassEditorPreferences

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

            Section("Size") {
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
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("editor-settings-page")
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
