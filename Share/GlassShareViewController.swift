//
//  GlassShareViewController.swift
//  Glass Power Tools — Share ▸ Send to a Machine (the Mac)
//
//  Files shared from any app on the Mac to a folder on a machine in the library (D72, 2026-10-13;
//  the owner chose the Mac only). The panel picks the machine and, optionally, a folder under its
//  home folder. The files are copied into the App Group, and the app — opened by the extension —
//  sends them with the Files browser's verified upload, nothing on the machine replaced, and says
//  what happened. The extension holds no credential and makes no connection: that stays the app's.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GlassWidgetData

final class GlassShareViewController: NSViewController {
    override func loadView() {
        let machines = (GlassWidgetStore.read()?.machines(limit: .max) ?? [])
            .filter { machine in machine.services.contains { $0.kind == .terminal } }
        let panel = GlassSharePanel(machines: machines,
                                    send: { [weak self] machine, folder in self?.send(to: machine, folder: folder) },
                                    cancel: { [weak self] in self?.cancel() })
        let host = NSHostingView(rootView: panel)
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 300)
        view = host
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func send(to machine: UUID, folder: String) {
        guard let context = extensionContext else { return }
        let providers = (context.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        Task { @MainActor in
            do {
                let staged = try await Self.stage(providers)
                try GlassExternalRequests.send(.sendFiles(staged, machine: machine,
                                                          folder: folder.trimmingCharacters(in: .whitespaces).isEmpty ? nil : folder))
                context.completeRequest(returningItems: nil)
            } catch {
                context.cancelRequest(withError: error)
            }
        }
    }

    /// Each shared file, copied into a folder of its own in the App Group, for the app to send.
    @MainActor
    static func stage(_ providers: [NSItemProvider]) async throws -> [URL] {
        guard let root = GlassExternalRequests.stagingFolder() else { throw CocoaError(.fileNoSuchFile) }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var staged: [URL] = []
        for provider in providers {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
            let source = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let source, source.isFileURL else { continue }
            let copy = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: copy)
            staged.append(copy)
        }
        guard !staged.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        return staged
    }
}

/// The panel: a machine, an optional folder, Send.
struct GlassSharePanel: View {
    let machines: [GlassWidgetSnapshot.Machine]
    let send: (UUID, String) -> Void
    let cancel: () -> Void
    @State private var chosen: UUID?
    @State private var folder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to a Machine").font(.headline)
            if machines.isEmpty {
                Text("No machine in your library has a Terminal service to send through. Add one in Glass Power Tools.")
                    .foregroundStyle(.secondary)
            } else {
                List(machines, selection: $chosen) { machine in
                    Label(machine.name, systemImage: "server.rack").tag(machine.id)
                }
                .frame(minHeight: 140)
                TextField("Folder (empty for the home folder)", text: $folder)
                    .textFieldStyle(.roundedBorder)
                Text("Nothing on the machine is replaced: a name already taken gets a number.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Send") { if let chosen { send(chosen, folder) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { chosen = chosen ?? machines.first?.id }
    }
}
