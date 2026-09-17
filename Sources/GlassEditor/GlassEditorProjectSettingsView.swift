//
//  GlassEditorProjectSettingsView.swift
//  Glass Power Tools — GlassEditor
//
//  **This** project's settings, which are a different thing from the editor's.
//
//  The gear in the toolbar opens the app's settings, where line numbers and text size live because
//  they are true of every document. The gear at the foot of the sidebar opens this, because a name
//  and a folder and a machine are true of one project only. Two gears, two scopes, and the one in
//  the column belongs to the thing the column is showing.
//

import SwiftUI
import GlassConnectionUI

struct GlassEditorProjectSettingsView: View {
    let workspace: GlassEditorWorkspace
    let project: GlassEditorProject
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Name") {
                    TextField("Project Name", text: $name)
                        .accessibilityIdentifier("editor-project-name")
                }

                Section("Where") {
                    LabeledContent("Machine") {
                        if let reach = workspace.projectReach[project.id] {
                            Label(reach.badge, systemImage: reach.symbolName)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Text("Unknown")
                        }
                    }
                    LabeledContent("Folder") {
                        Text(project.path)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.head)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button("Refresh Files", systemImage: "arrow.clockwise") {
                        workspace.refreshProject(project.id)
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    // Said here because it is the one thing about a project that is not obvious:
                    // there is no Close Project, on purpose.
                    Text("Closing the editor window closes the project. Open documents stay open.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, minHeight: 320)
        .navigationTitle(project.displayName)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    workspace.rename(project.id, to: name)
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A sheet on this platform needs its own way out; the toolbar above is not drawn in a
            // sheet on every platform this builds for.
            HStack {
                Spacer(minLength: 0)
                Button("Done") {
                    workspace.rename(project.id, to: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .onAppear { name = project.displayName }
        .accessibilityIdentifier("editor-project-settings-sheet")
    }
}
