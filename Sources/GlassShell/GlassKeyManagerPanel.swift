//
//  GlassKeyManagerPanel.swift
//  Glass Power Tools — GlassShell
//
//  The key manager: a library panel beside Collections, because a key belongs to the workspace and
//  not to one capability's settings page (D26).
//
//  A key outlives the connections that reference it. It can authenticate a terminal on one machine
//  and a database on another, so the question "what happens if I delete this?" has an answer only
//  something looking across the whole library can give. That is what this panel is for, and it is
//  why **Used By** is the section the rest of it exists to carry: `model.services(usingKey:)` walks
//  the catalog and asks each capability, deriving the answer rather than keeping a second copy of
//  it (D28).
//
//  **Designed on visionOS terms and adapted down**, per the magic directive: rows are gaze targets
//  and highlight when looked at, the detail is set at reading distance, and the action bar is the
//  family's shared one. On a Mac it is an ordinary two-column library panel, which is the point —
//  familiar to a Mac user, and native in a headset.
//
//  The panel is contributed exactly like the terminal's Workgroups (`GlassLibraryPanel`), with the
//  selection held outside both columns because they are two columns of one split view and a
//  `@State` in one cannot be read by the other.
//

import SwiftUI
import UniformTypeIdentifiers
import GlassConnectionKit
import GlassConnectionUI
import GlasSecretStore
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Selection and presentation for both columns of the key manager.
@MainActor @Observable
public final class GlassKeyManagerModel {
    var selection: UUID?
    var searchQuery: String = ""
    var showingImport = false
    var showingGenerate = false
    var renaming: StoredSSHKey?
    var pendingDeletion: StoredSSHKey?
    var exporting: GlassPublicKeyExport?
    var message: String?

    public init() {}
}

/// A public key on its way to a file the user chooses.
struct GlassPublicKeyExport: Identifiable {
    let id = UUID()
    let filename: String
    let document: GlassPublicKeyDocument
}

struct GlassPublicKeyDocument: FileDocument {
    // A public key is text. `.text` rather than a bespoke type so every app that opens text can
    // open it, and so the save panel does not fight the user over an extension.
    static let readableContentTypes: [UTType] = [.text]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

public struct GlassKeyManagerPanel: View {
    public enum Presentation { case results, detail }

    private let presentation: Presentation
    private let model: GlassShellModel
    @Bindable private var panel: GlassKeyManagerModel

    public init(presentation: Presentation, model: GlassShellModel, panel: GlassKeyManagerModel) {
        self.presentation = presentation
        self.model = model
        self.panel = panel
    }

    private var keyStore: (any GlassKeyStore)? { model.keyStore }

    private var keys: [StoredSSHKey] {
        let all = keyStore?.keys ?? []
        let query = panel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedKey: StoredSSHKey? {
        guard let selection = panel.selection else { return nil }
        return keyStore?.keys.first { $0.id == selection }
    }

    public var body: some View {
        content
            // Sheets, the alert and the pruning of a selection whose key has gone are attached to
            // whichever instance owns the results — never to both columns, or the sheet presents
            // twice and the alert fights itself. Carried on a zero-size background, the way the
            // library and Workgroups carry theirs.
            .background { if presentation == .results { sharedPresentations } }
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .results: results
        case .detail: detail
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        List(selection: $panel.selection) {
            if keys.isEmpty {
                ContentUnavailableView {
                    Label(panel.searchQuery.isEmpty ? "No SSH Keys" : "No Matching Keys", systemImage: "key")
                } description: {
                    Text(panel.searchQuery.isEmpty
                         ? "A key can sign in to any number of machines, and stays here when a connection is deleted."
                         : "Try a different search.")
                } actions: {
                    if panel.searchQuery.isEmpty, keyStore != nil {
                        Button("Import a Key…") { panel.showingImport = true }
                            #if os(visionOS)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.extraLarge)
                            #endif
                    }
                }
            }
            ForEach(keys) { key in
                row(key)
                    .tag(key.id)
                    .glassSpatialListRow()
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { panel.renaming = key }
                        Button("Copy Public Key", systemImage: "doc.on.doc") { copyPublicKey(key) }
                        Button("Delete", systemImage: "trash", role: .destructive) { panel.pendingDeletion = key }
                    }
            }
        }
        .glassSpatialList()
        .scrollContentBackground(.hidden)
        .searchable(text: $panel.searchQuery, prompt: "Search Keys")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import a Key…", systemImage: "square.and.arrow.down") { panel.showingImport = true }
                    // Only where there is one: offered everywhere, it then failed on the devices
                    // without a Secure Enclave.
                    if SecureEnclave.isAvailable {
                        Button("Generate in the Secure Enclave…", systemImage: "lock.shield") { panel.showingGenerate = true }
                    }
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                .disabled(keyStore == nil)
                .accessibilityIdentifier("key-manager-add")
            }
        }
    }

    private func row(_ key: StoredSSHKey) -> some View {
        GlassLibraryConnectionRow(name: key.name, nameAccessibilityIdentifier: "key-row-\(key.name)") {
            // Under the name, tight to the leading edge, where a badge reads as a property of the
            // key rather than as a control: what it is, and where it can be used.
            HStack(spacing: 8) {
                Text(key.keyTypeBadge)
                Label(GlassKeyMobility(key).title, systemImage: GlassKeyMobility(key).symbolName)
                    .labelStyle(.titleAndIcon)
            }
            .font(GlassSpatialMetrics.rowSubtitleFont)
            .foregroundStyle(.secondary)
        } accessory: {
            usageBadge(for: key)
        }

        .accessibilityIdentifier("key-\(key.id.uuidString.lowercased())")
    }

    /// How many services use this key, in the row. Nothing at all when the answer is none: an
    /// empty badge would read as a count of zero, and "no services" is the detail's sentence to
    /// say, with the caveat about what this build could not read.
    @ViewBuilder
    private func usageBadge(for key: StoredSSHKey) -> some View {
        let usage = model.usageCount(ofKey: key.id)
        if usage.readable > 0 {
            Text("\(usage.readable)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Used by \(usage.readable) services")
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let key = selectedKey {
            GlassLibraryDetail(title: key.name, content: {
                Section("Key") {
                    LabeledContent("Algorithm", value: key.algorithmKind.badgeName)
                        .accessibilityIdentifier("key-detail-algorithm")
                    LabeledContent("Storage", value: key.storageKind.badgePrefix)
                    LabeledContent("Fingerprint") {
                        // Selectable and monospaced: this is the string a user compares against
                        // `ssh-keygen -lf` or against what a server reports, character by character.
                        Text(keyStore?.fingerprint(for: key.id) ?? "Unavailable")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityIdentifier("key-detail-fingerprint")
                    LabeledContent("Added") { Text(key.createdAt, style: .date) }
                }
                Section("Availability") {
                    let mobility = GlassKeyMobility(key)
                    Label(mobility.title, systemImage: mobility.symbolName)
                        .accessibilityIdentifier("key-detail-mobility")
                    Text(mobility.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                usedBySection(key)
            }, actions: {
                HStack(spacing: 12) {
                    Button("Delete", role: .destructive) { panel.pendingDeletion = key }
                        .accessibilityIdentifier("key-delete")
                    Spacer(minLength: 0)
                    Button("Copy Public Key") { copyPublicKey(key) }
                        .accessibilityIdentifier("key-copy-public")
                    Button("Export…") { exportPublicKey(key) }
                        .accessibilityIdentifier("key-export-public")
                    Button("Rename") { panel.renaming = key }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("key-rename")
                }
            })
        } else {
            ContentUnavailableView {
                Label("Select a Key", systemImage: "key")
            } description: {
                Text("Every key you can sign in with, what it is, and which services use it.")
            }
            #if os(visionOS)
            .font(.title3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }

    /// What this key authenticates, across every machine in the library.
    @ViewBuilder
    private func usedBySection(_ key: StoredSSHKey) -> some View {
        let uses = model.services(usingKey: key.id)
        let usage = model.usageCount(ofKey: key.id)
        Section("Used By") {
            if uses.isEmpty {
                Text("No service uses this key.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("key-detail-unused")
            }
            ForEach(uses, id: \.service.endpointID) { use in
                HStack(spacing: 10) {
                    GlassServiceIcon(GlassServicePresentation.symbol(for: use.service.kind))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(use.service.displayName).lineLimit(1)
                        Text(use.host.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .glassSpatialListRow()
                .accessibilityElement(children: .combine)
            }
            // Not decoration. A configuration written by a newer build is skipped rather than
            // fatal, so a key in genuine use can otherwise read as used by nothing — and then
            // somebody deletes it. A zero only ever proves where you looked.
            if usage.unreadable > 0 {
                Label("\(usage.unreadable) more service\(usage.unreadable == 1 ? "" : "s") could not be read by this build, and may also use this key.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("key-detail-unreadable")
            }
        }
    }

    // MARK: Sheets, alerts and the deletion the panel exists to make safe

    @ViewBuilder
    private var sharedPresentations: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sheet(isPresented: $panel.showingImport) { keyStore?.importKeySheet() }
            .sheet(isPresented: $panel.showingGenerate) { keyStore?.generateKeySheet() }
            .sheet(item: $panel.renaming) { key in keyStore?.renameSheet(for: key) }
            .fileExporter(isPresented: Binding(get: { panel.exporting != nil },
                                               set: { if !$0 { panel.exporting = nil } }),
                          document: panel.exporting?.document,
                          contentType: .text,
                          defaultFilename: panel.exporting?.filename) { result in
                if case .failure(let error) = result { panel.message = error.localizedDescription }
                panel.exporting = nil
            }
            .alert("SSH Keys", isPresented: Binding(get: { panel.message != nil },
                                                    set: { if !$0 { panel.message = nil } })) {
                Button("OK", role: .cancel) { panel.message = nil }
            } message: {
                Text(panel.message ?? "")
            }
            .confirmationDialog("Delete SSH Key?",
                                isPresented: Binding(get: { panel.pendingDeletion != nil },
                                                     set: { if !$0 { panel.pendingDeletion = nil } }),
                                titleVisibility: .visible,
                                presenting: panel.pendingDeletion) { key in
                Button("Delete \(key.name)", role: .destructive) { delete(key) }
                Button("Cancel", role: .cancel) { panel.pendingDeletion = nil }
            } message: { key in
                Text(deletionWarning(for: key))
            }
            .task { keyStore?.loadIfNeeded() }
            .onChange(of: keyStore?.keys.map(\.id) ?? []) { _, ids in
                if let selection = panel.selection, !ids.contains(selection) { panel.selection = nil }
            }
    }

    /// Internal, not private, so a test can drive the **join** — model to sentence — rather than
    /// only the sentence. Every part existing while nothing connects them is this project's most
    /// repeated defect.
    func deletionWarning(for key: StoredSSHKey) -> String {
        GlassKeyDeletionSummary.text(
            keyName: key.name,
            uses: model.services(usingKey: key.id).map { (host: $0.host.displayName, service: $0.service.displayName) },
            unreadable: model.usageCount(ofKey: key.id).unreadable)
    }

    private func delete(_ key: StoredSSHKey) {
        guard let keyStore else { return }
        Task { @MainActor in
            do {
                try await keyStore.delete(key.id)
                if panel.selection == key.id { panel.selection = nil }
            } catch {
                panel.message = "'\(key.name)' was not deleted because secure storage could not be updated: \(error.localizedDescription)"
            }
            panel.pendingDeletion = nil
        }
    }

    private func copyPublicKey(_ key: StoredSSHKey) {
        do {
            guard let keyStore else { return }
            let value = try keyStore.publicKey(for: key.id)
            Self.copyToClipboard(value)
            panel.message = "Copied the public key for '\(key.name)'."
        } catch {
            panel.message = "The public key for '\(key.name)' could not be derived: \(error.localizedDescription)"
        }
    }

    private func exportPublicKey(_ key: StoredSSHKey) {
        do {
            guard let keyStore else { return }
            let value = try keyStore.publicKey(for: key.id)
            panel.exporting = GlassPublicKeyExport(filename: Self.exportFilename(for: key),
                                                   document: GlassPublicKeyDocument(text: value + "\n"))
        } catch {
            panel.message = "The public key for '\(key.name)' could not be derived: \(error.localizedDescription)"
        }
    }

    /// `id_alpha_key.pub` — the name is the user's, reduced to what a file system will take.
    static func exportFilename(for key: StoredSSHKey) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let stem = key.name.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return (stem.isEmpty ? "ssh_key" : stem) + ".pub"
    }

    static func copyToClipboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

/// What deleting a key will unassign, said before it happens — the sentence the whole panel is for.
///
/// Pure, and tested as such: this string is the last thing between a user and an irreversible act,
/// and it must not be reachable only by building a window. It takes names rather than records for
/// the same reason — nothing here needs a catalog to be correct.
enum GlassKeyDeletionSummary {
    /// How many users to name before summarising the rest. Four fits a confirmation dialog on a
    /// phone; beyond that the list stops being readable and the count carries the weight.
    static let namedLimit = 4

    static func text(keyName: String, uses: [(host: String, service: String)], unreadable: Int) -> String {
        var lines = ["This removes '\(keyName)' from secure storage. It cannot be undone."]
        if uses.isEmpty {
            lines.append("No service uses it.")
        } else {
            let named = uses.prefix(namedLimit).map { "\($0.service) on \($0.host)" }
            let remainder = uses.count - named.count
            let list = named.joined(separator: ", ") + (remainder > 0 ? ", and \(remainder) more" : "")
            lines.append("\(uses.count) service\(uses.count == 1 ? "" : "s") will be left without a key: \(list).")
        }
        if unreadable > 0 {
            // Never omitted. A configuration this build cannot read is a service that may use the
            // key and cannot be listed; saying nothing would let the dialog claim a smaller
            // consequence than it can actually promise.
            lines.append("\(unreadable) service\(unreadable == 1 ? "" : "s") could not be read by this build and may also use it.")
        }
        return lines.joined(separator: " ")
    }
}

public extension GlassShellModel {
    /// The shell's own library panels, ahead of the capabilities'.
    ///
    /// Keys are the shell's, not a capability's: a key can authenticate services belonging to
    /// several of them, and the manager has to see across all of them to say what deleting one
    /// would unassign. The panel appears only when something is holding key material — with no
    /// key store attached there is nothing to manage, and an empty row in the sidebar would be a
    /// promise the build cannot keep.
    func libraryPanels() -> [GlassLibraryPanel] {
        guard keyStore != nil else { return [] }
        let model = self
        let panel = keyPanel
        return [
            GlassLibraryPanel(
                id: "ssh-keys",
                sectionTitle: "Keys",
                title: "SSH Keys",
                symbolName: "key",
                // `model`, not `self`: the count is asked for every time the row draws, so the
                // expression outlives this call (`GlassLibraryPanel.count`).
                count: model.keyStore?.keys.count,
                selection: { panel.selection },
                clearSelection: { panel.selection = nil },
                results: { GlassKeyManagerPanel(presentation: .results, model: model, panel: panel) },
                detail: { GlassKeyManagerPanel(presentation: .detail, model: model, panel: panel) })
        ]
    }
}
