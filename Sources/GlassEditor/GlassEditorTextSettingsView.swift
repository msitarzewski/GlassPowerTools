//
//  GlassEditorTextSettingsView.swift
//  Glass Power Tools — GlassEditor
//
//  One control set for the text, used at whichever level is being edited.
//
//  The gear at the foot of the file list is the **project's**; the gear in the toolbar is **this
//  file's**; Settings ▸ Editor (⌘,) holds the app's defaults. Three scopes, one view, so a size
//  chosen for a file and a size chosen for a project cannot end up with two different controls
//  that behave differently.
//
//  Every row can say "Default", and the default names the value it would take *and where it comes
//  from*. A toggle cannot express three states, which is why line numbers and wrapping are
//  three-way pickers rather than switches: "off" and "not overridden" are different answers, and a
//  switch that shows the inherited value silently becomes an override the moment it is touched.
//

import SwiftUI
import GlassEditorCore

struct GlassEditorTextSettingsView: View {
    @Binding var overrides: GlassEditorTextOverrides
    /// What this level inherits when it says nothing — the project's answer for a file, the app's
    /// for a project.
    let inherited: GlassEditorConfiguration
    /// Where that inherited answer comes from, named for the footer.
    let inheritedFrom: String

    var body: some View {
        Section {
            Picker("Line Numbers", selection: threeWay(\.showsLineNumbers,
                                                       inherited: inherited.showsLineNumbers)) {
                Text("Default").tag(GlassEditorOverrideChoice.inherited)
                Text("Show").tag(GlassEditorOverrideChoice.on)
                Text("Hide").tag(GlassEditorOverrideChoice.off)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editor-override-line-numbers")

            Picker("Wrap Long Lines", selection: threeWay(\.wrapsLines,
                                                          inherited: inherited.wrapsLines)) {
                Text("Default").tag(GlassEditorOverrideChoice.inherited)
                Text("Wrap").tag(GlassEditorOverrideChoice.on)
                Text("Don't Wrap").tag(GlassEditorOverrideChoice.off)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("editor-override-wrap")

            LabeledContent("Text Size") {
                HStack(spacing: 12) {
                    Button("Smaller", systemImage: "textformat.size.smaller") {
                        setSize(currentSize - 1)
                    }
                    .labelStyle(.iconOnly)
                    Text("\(Int(currentSize)) pt")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(overrides.fontSize == nil ? .secondary : .primary)
                        .frame(minWidth: 44)
                    Button("Larger", systemImage: "textformat.size.larger") {
                        setSize(currentSize + 1)
                    }
                    .labelStyle(.iconOnly)
                    Button("Default") { overrides.fontSize = nil }
                        .font(.callout)
                        .disabled(overrides.fontSize == nil)
                }
                .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("editor-override-size")
        } header: {
            Text("Text")
        } footer: {
            Text(footer)
        }
    }

    private var currentSize: Double { overrides.fontSize ?? inherited.fontSize }

    private var footer: String {
        overrides.isEmpty
        ? "Following \(inheritedFrom)."
        : "Overriding \(inheritedFrom). Anything left on Default follows it."
    }

    private func setSize(_ size: Double) {
        overrides.fontSize = min(max(size, GlassEditorTextOverrides.fontSizeRange.lowerBound),
                                 GlassEditorTextOverrides.fontSizeRange.upperBound)
    }

    /// A three-way binding over one optional flag: the two explicit answers, and the absence that
    /// means "ask the level above".
    private func threeWay(_ key: WritableKeyPath<GlassEditorTextOverrides, Bool?>,
                          inherited value: Bool) -> Binding<GlassEditorOverrideChoice> {
        Binding(
            get: {
                switch overrides[keyPath: key] {
                case .none: .inherited
                case .some(true): .on
                case .some(false): .off
                }
            },
            set: { choice in
                switch choice {
                case .inherited: overrides[keyPath: key] = nil
                case .on: overrides[keyPath: key] = true
                case .off: overrides[keyPath: key] = false
                }
            }
        )
    }
}

enum GlassEditorOverrideChoice: Hashable {
    case inherited, on, off
}

/// The toolbar gear's sheet: the front document's text settings, or the project's when no document
/// is open, so the control always leads somewhere.
struct GlassEditorFileSettingsSheet: View {
    let workspace: GlassEditorWorkspace
    @Binding var isPresented: Bool
    @Environment(GlassEditorRuntime.self) private var runtime: GlassEditorRuntime?

    var body: some View {
        NavigationStack {
            Form {
                if let document = workspace.selectedDocument {
                    // **Read here, in the body.** A computed `Binding`'s getter is a closure that
                    // does not run while the body is being evaluated, so binding straight to the
                    // document would register no dependency and the controls would not follow the
                    // value they set (the trap this project met on 2026-09-17).
                    let current = document.textOverrides
                    GlassEditorTextSettingsView(
                        overrides: Binding(get: { current },
                                           set: { workspace.setTextOverrides($0, for: document) }),
                        inherited: workspace.inheritedConfiguration(for: document),
                        inheritedFrom: inheritedName(for: document))
                } else if let project = workspace.projects.first {
                    let current = project.textOverrides ?? GlassEditorTextOverrides()
                    GlassEditorTextSettingsView(
                        overrides: Binding(get: { current },
                                           set: { setProject($0, for: project) }),
                        inherited: workspace.preferences.configuration(basedOn: GlassEditorConfiguration()),
                        inheritedFrom: "the editor's defaults")
                } else {
                    Section {
                        Text("Open a file to set how it is shown. The editor's defaults are in Settings ▸ Editor.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .accessibilityIdentifier("editor-file-settings-sheet")
    }

    private var title: String {
        workspace.selectedDocument?.displayName ?? workspace.projects.first?.displayName ?? "Text"
    }

    /// What the file follows when it says nothing: its project, if it has one, and the app's
    /// defaults otherwise. Named rather than implied, because "Default" is useless without it.
    private func inheritedName(for document: GlassEditorDocument) -> String {
        guard let path = document.path, let project = workspace.project(owning: path),
              project.textOverrides != nil else {
            return "the editor's defaults"
        }
        return "\(project.displayName)'s settings"
    }

    private func setProject(_ overrides: GlassEditorTextOverrides, for project: GlassEditorProject) {
        if let runtime {
            runtime.setTextOverrides(overrides, forProject: project.id, in: workspace)
        } else {
            workspace.setTextOverrides(overrides, forProject: project.id)
        }
    }
}
