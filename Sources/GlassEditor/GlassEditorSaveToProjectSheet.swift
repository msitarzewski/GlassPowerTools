//
//  GlassEditorSaveToProjectSheet.swift
//  Glass Power Tools — GlassEditor
//
//  Where a new document is first saved, when its window has a project open: a name and a folder
//  in the project — on this device or on a server — with the platform's own save panel one press
//  away. Before this the only destination was the local disk, so a new file could not be saved
//  to a server at all (2026-09-26).
//

import SwiftUI

/// A never-saved document on its way to its first location.
struct GlassEditorFirstSave: Identifiable {
    let document: GlassEditorDocument
    /// Set when the save was asked for by closing the document: it closes once saved.
    let closesAfterSaving: Bool
    var id: GlassEditorDocument.ID { document.id }
}

struct GlassEditorSaveToProjectSheet: View {
    let workspace: GlassEditorWorkspace
    let request: GlassEditorFirstSave
    /// The platform's own save panel, for a location outside the projects.
    let saveElsewhere: () -> Void
    let dismiss: () -> Void

    @State private var name: String
    @State private var folder: String
    @State private var problem: String?
    @State private var isSaving = false

    init(workspace: GlassEditorWorkspace, request: GlassEditorFirstSave,
         saveElsewhere: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.workspace = workspace
        self.request = request
        self.saveElsewhere = saveElsewhere
        self.dismiss = dismiss
        _name = State(initialValue: request.document.displayName)
        _folder = State(initialValue: workspace.saveDestinations.first?.path ?? "/")
    }

    private var elsewhereTitle: String {
        #if os(macOS)
        "On This Mac…"
        #else
        "On This Device…"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("editor-save-name")
                Picker("Folder", selection: $folder) {
                    ForEach(workspace.saveDestinations, id: \.path) { destination in
                        Text(label(for: destination)).tag(destination.path)
                    }
                }
                .accessibilityIdentifier("editor-save-folder")
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                // Hands over to the panel without dismissing as a cancel: the save continues there.
                Button(elsewhereTitle) { saveElsewhere() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("editor-save-confirm")
            }
            .padding()
        }
        .frame(minWidth: 420)
        .navigationTitle("Save")
    }

    /// The project's name and the folder below it, with the machine when it is not this one.
    private func label(for destination: (project: GlassEditorProject, path: String)) -> String {
        let root = GlassEditorProject.normalized(destination.project.path)
        let relative = destination.path == root ? "" : String(destination.path.dropFirst(root.count))
        let place = destination.project.displayName + relative
        if let machine = workspace.machineName(of: destination.project.id) {
            return "\(place) — \(machine)"
        }
        return place
    }

    private func save() {
        isSaving = true
        problem = nil
        Task {
            do {
                try await workspace.saveNewDocument(request.document.id, named: name, inFolder: folder)
                if request.closesAfterSaving { workspace.close(request.document.id) }
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
            isSaving = false
        }
    }
}
