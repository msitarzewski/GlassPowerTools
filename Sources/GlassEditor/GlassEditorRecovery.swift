//
//  GlassEditorRecovery.swift
//  Glass Power Tools — GlassEditor
//
//  Unsaved editor text kept on this device (2026-11-22), so a crash, a forced quit or the system ending the app on
//  iPhone, iPad or Vision Pro loses a moment of typing, not the changes. The owner's word, after the editor's gaps were
//  surveyed: "autosave and recovery".
//
//  One file per document with unsaved changes, in Application Support, written when its text changes (at most every
//  couple of seconds, and at once when the app goes to the background); removed when the document is saved, closed
//  without saving, or brought back to what was saved. A deliberate discard — Quit Without Saving — removes them all.
//  At the next launch the runtime opens what is left (`GlassEditorRuntime.recoverUnsavedDocuments`).
//
//  The text stays on this device. It is the person's own document, held where the app keeps its other state, and on
//  iPhone, iPad and Vision Pro with the system's file protection.
//

import Foundation
import GlassEditorCore
import GlassLayers

@MainActor
public final class GlassEditorRecovery {
    /// One document's unsaved text and what is needed to put it back.
    public struct Record: Codable, Sendable, Equatable {
        public var documentID: UUID
        /// The window it was in, so documents that shared a window share one again.
        public var windowID: UUID
        public var name: String
        /// The file on this device it belongs to; nil for an untitled document.
        public var path: String?
        /// The machine it was on, when that was not this device: it comes back as an untitled copy, since reaching
        /// that machine again is a connection, not a file.
        public var machine: String?
        public var language: String
        public var text: String
        public var keptAt: Date
    }

    public let directory: URL
    /// The revision of each document as last written in this run. Only these are ever removed by a sweep: records
    /// from the last run wait for `recoverUnsavedDocuments` to read them.
    private var kept: [UUID: Int] = [:]

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    /// `Application Support/GlassPowerTools/EditorRecovery`, beside the shell's own state; a UI test run gets a folder
    /// of its own, so a test never recovers the person's documents or leaves its own behind for them.
    static var defaultDirectory: URL {
        let base = URL.applicationSupportDirectory
            .appendingPathComponent("GlassPowerTools", isDirectory: true)
            .appendingPathComponent("EditorRecovery", isDirectory: true)
        guard let run = GlassUITestRun.identifier else { return base }
        return base.appendingPathComponent("uitests-\(run.uuidString)", isDirectory: true)
    }

    private func file(for documentID: UUID) -> URL {
        directory.appendingPathComponent("\(documentID.uuidString).json")
    }

    // MARK: Keeping

    /// Writes every text document with unsaved changes whose text has moved on since its last copy, and removes the
    /// copy of every document this run wrote that is no longer unsaved or no longer open.
    func sweep(_ windows: [(windowID: UUID, workspace: GlassEditorWorkspace)]) {
        var open: Set<UUID> = []
        for (windowID, workspace) in windows {
            for document in workspace.documents where document.isText {
                open.insert(document.id)
                if document.isDirty {
                    keep(document, windowID: windowID)
                } else if kept[document.id] != nil {
                    forget(document.id)
                }
            }
        }
        for id in kept.keys where !open.contains(id) { forget(id) }
    }

    private func keep(_ document: GlassEditorDocument, windowID: UUID) {
        let revision = document.model.revision
        guard kept[document.id] != revision else { return }
        let record = Record(documentID: document.id, windowID: windowID, name: document.displayName,
                            path: document.machine == nil ? document.path : nil, machine: document.machine,
                            language: document.model.language.rawValue, text: document.model.text, keptAt: Date())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            #if os(macOS)
            try data.write(to: file(for: document.id), options: .atomic)
            #else
            try data.write(to: file(for: document.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #endif
            kept[document.id] = revision
        } catch {
            // Not kept this time; the next sweep tries again. Nothing to tell the person: their document is open.
        }
    }

    /// Removes a document's copy: saved, closed without saving, or recovered under a new identity.
    func forget(_ documentID: UUID) {
        kept[documentID] = nil
        try? FileManager.default.removeItem(at: file(for: documentID))
    }

    /// Removes every copy: Quit Without Saving.
    func forgetAll() {
        kept = [:]
        for record in records() { try? FileManager.default.removeItem(at: file(for: record.documentID)) }
    }

    // MARK: Reading

    /// The copies an earlier run left: every one but those this run wrote for documents it has open.
    public func recordsFromEarlierRuns() -> [Record] {
        records().filter { kept[$0.documentID] == nil }
    }

    /// Every copy in the folder, oldest first. A file that does not decode is not a document, and is left out.
    public func records() -> [Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Record.self, from: Data(contentsOf: $0)) }
            .sorted { $0.keptAt < $1.keptAt }
    }
}
