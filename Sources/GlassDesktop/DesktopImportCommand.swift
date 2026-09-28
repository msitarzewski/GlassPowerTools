//
//  DesktopImportCommand.swift
//  Glass Power Tools — GlassDesktop
//
//  "Import RDP File…" in the library toolbar.
//
//  This is how people arrive from Windows, Remote Desktop Manager, or a pile of `.rdp` files a
//  sysadmin sent them, so it is an onboarding surface rather than a convenience. It is carried over
//  from glassDT (`../glassDT/Sources/GlassDesktopUI/DesktopLibraryView.swift:75-108`), whose only
//  caller lived in `DesktopLibraryView` — the one file the merge deleted, because the shell's
//  library replaced it. That is how the parser came to have no callers at all.
//
//  The shape that is worth keeping, and is kept exactly: **a parsed file opens a form, it never
//  saves a connection.** `.rdp` files carry passwords this importer deliberately drops, and they
//  can ask for things the app will not do — so the user sees the result, with those notices, before
//  it becomes a machine in their library.
//

import SwiftUI
import UniformTypeIdentifiers
import GlassConnectionKit
import GlassShell

/// The toolbar button and its file picker. A view of its own because the picker needs state, and
/// `libraryToolbarItems()` hands back a value rather than a place to keep one.
struct DesktopImportCommand: View {
    let runtime: GlassDesktopRuntime
    @State private var choosingFile = false
    @State private var reading = false
    @State private var importTask: Task<Void, Never>?
    @State private var failure: String?

    /// `UTType(filenameExtension:)` is nil on a system with nothing registered for `.rdp`, which is
    /// every Mac without a remote desktop client installed. Falling back to `.data` keeps the picker
    /// usable; `RDPFileImporter.read` re-checks the extension and refuses anything else.
    private var rdpType: UTType { UTType(filenameExtension: "rdp") ?? .data }

    var body: some View {
        Button {
            choosingFile = true
        } label: {
            Label("Import RDP File…", systemImage: "square.and.arrow.down")
        }
        .disabled(reading)
        .help("Create a machine from a Windows .rdp file")
        .accessibilityIdentifier("library-import-rdp")
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [rdpType]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: Binding(get: { failure != nil },
                                                     set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .onDisappear { importTask?.cancel() }
        #if os(macOS)
        .focusedSceneValue(\.desktopImportAction, reading ? nil : { choosingFile = true })
        #endif
    }

    private func read(_ url: URL) {
        reading = true
        importTask = Task { @MainActor in
            defer { reading = false }
            do {
                // Parsing reads a file and walks up to 8,192 lines; off the main actor, as glassDT
                // did, so a large or slow file never stalls the library.
                let imported = try await Task.detached(priority: .userInitiated) {
                    try RDPFileImporter.read(from: url)
                }.value
                try Task.checkCancellation()
                runtime.requestSetup?(prefill(from: imported))
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func prefill(from imported: RDPFileImport) -> GlassShellSetupPrefill {
        let connection = imported.connection
        // The file's own name becomes the machine's, and its address the machine's address: the
        // host is the thing being imported, and the service hangs off it (D27).
        return GlassShellSetupPrefill(
            kind: .rdp,
            hostName: connection.name,
            address: connection.host,
            configuration: (try? JSONEncoder().encode(connection)) ?? Data(),
            notices: imported.notices)
    }
}
