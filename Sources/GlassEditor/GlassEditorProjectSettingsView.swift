//
//  GlassEditorProjectSettingsView.swift
//  Glass Power Tools — GlassEditor
//
//  **This** project's settings, which are a different thing from the file's and from the app's.
//
//  Three scopes, and each gear belongs to what it sits beside: the one at the foot of the file
//  list is this project's, the one in the toolbar is the open file's, and the app's defaults are
//  in Settings ▸ Editor at ⌘,. A project's text settings are here because a project is exactly the
//  kind of thing that disagrees — one repository at 11pt, one machine's logs unwrapped — and they
//  travel with the record, so the project reads the same on the phone.
//

import SwiftUI
import GlassConnectionUI
import GlassEditorCore

struct GlassEditorProjectSettingsView: View {
    let workspace: GlassEditorWorkspace
    let project: GlassEditorProject
    @Environment(\.dismiss) private var dismiss
    @Environment(GlassEditorRuntime.self) private var runtime: GlassEditorRuntime?
    @State private var name: String = ""

    /// The workspace's own copy, so an edit made here is reflected while the sheet is open — the
    /// `project` this sheet was handed is the value at the moment it opened.
    private var current: GlassEditorProject {
        workspace.projects.first { $0.id == project.id } ?? project
    }

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

                // The project's own text settings, over this window's (W23) and the app's defaults
                // and under the open file's. The same controls the toolbar's gear shows, at a
                // different level. Read here, in the body: a computed `Binding`'s getter is a
                // closure that does not run during body evaluation, so it would register no
                // dependency on the list it reads and the controls would not follow the value they set.
                let overrides = current.textOverrides ?? GlassEditorTextOverrides()
                GlassEditorTextSettingsView(
                    overrides: Binding(get: { overrides }, set: { set($0) }),
                    inherited: workspace.windowTextConfiguration,
                    inheritedFrom: GlassEditorInheritedName.forProject(in: workspace))

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
        // **One Done.** There were two: a toolbar item and the bar below, and a sheet on the Mac
        // draws both — one inside the scrolling form, one under it (photographed 2026-09-18). The
        // bar is the one that is drawn on every platform this builds for, so the bar is the one
        // that stays.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button("Done") { save() }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .onAppear { name = project.displayName }
        .accessibilityIdentifier("editor-project-settings-sheet")
    }

    /// Both copies, always: the window's, so the title changes now, and the library's, so the name
    /// is still there at the next launch and on the other devices. The sheet used to rename only
    /// the window's.
    private func save() {
        if let runtime {
            runtime.rename(project.id, to: name, in: workspace)
        } else {
            workspace.rename(project.id, to: name)
        }
        dismiss()
    }

    private func set(_ overrides: GlassEditorTextOverrides) {
        if let runtime {
            runtime.setTextOverrides(overrides, forProject: project.id, in: workspace)
        } else {
            workspace.setTextOverrides(overrides, forProject: project.id)
        }
    }
}
