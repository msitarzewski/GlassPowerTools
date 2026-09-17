//
//  GlassEditorDocument.swift
//  Glass Power Tools — GlassEditor
//
//  One open file.
//
//  The editing engine already exists and is in production behind the SQL editor, the record editor
//  and the SFTP remote editor: `GlassEditorModel` holds the text, the undo history, the tree-sitter
//  highlighting, the find engine and the conflict state, and `GlassEditorView` renders it on AppKit
//  and UIKit. **None of that is re-implemented here.** This is the part the engine deliberately does
//  not do — where a document came from, what it is called, whether it has been saved — because the
//  engine is a text editor and this is a file editor.
//
//  Reading and writing go through the engine's own helpers for the same reason: `EncodingDetection`
//  replays the bytes' encoding verbatim at save, `LineEndingDetector` keeps a CRLF file CRLF, and
//  `AtomicSaver` writes through a temporary file and renames. A file opened here and saved
//  unchanged is byte-identical, which is the promise an editor has to keep before any of the
//  interesting features matter.
//

import Foundation
import Observation
import GlassEditorCore
import GlassEditorUI

@MainActor @Observable
public final class GlassEditorDocument: Identifiable {
    public let id = UUID()
    public let model: GlassEditorModel
    /// Where it is saved, or nil for a document that has never been written.
    public private(set) var url: URL?
    /// The name a user gave an unsaved document, so it is not "Untitled" forever.
    private let untitledName: String

    public init(model: GlassEditorModel, url: URL?, untitledName: String = "Untitled") {
        self.model = model
        self.url = url
        self.untitledName = untitledName
    }

    // MARK: Opening

    /// Reads a file and prepares it for editing, keeping its encoding and line endings.
    public static func open(_ url: URL) throws -> GlassEditorDocument {
        let data = try Data(contentsOf: url)
        let decoded = try EncodingDetector.decode(data)
        let snapshot = DocumentSnapshot(content: decoded.content,
                                        encoding: decoded.encoding,
                                        lineEndings: LineEndingDetector.detect(in: decoded.content),
                                        origin: .local(url))
        // The language comes from the extension by way of the origin, which is why the origin is
        // set before the model is built rather than assigned after. When the name says nothing —
        // `Makefile`, `deploy`, a plist with no extension — the content is asked instead, which is
        // the difference between an editor that colours a developer's tree and one that colours the
        // half of it that happens to be named conveniently.
        let model = GlassEditorModel(snapshot: snapshot)
        if model.language == .plaintext {
            let sniffed = LanguageID.forContent(decoded.content)
            if sniffed != .plaintext { model.language = sniffed }
        }
        return GlassEditorDocument(model: model, url: url)
    }

    /// A new, empty document that exists only in memory until it is saved.
    public static func untitled(named name: String = "Untitled",
                                language: LanguageID = .plaintext) -> GlassEditorDocument {
        let snapshot = DocumentSnapshot(content: "",
                                        encoding: .utf8(hadBOM: false),
                                        lineEndings: LineEndingStyle.platformDefault,
                                        origin: .ephemeral(id: UUID()))
        let model = GlassEditorModel(snapshot: snapshot, language: language)
        return GlassEditorDocument(model: model, url: nil, untitledName: name)
    }

    // MARK: Identity

    public var displayName: String { url?.lastPathComponent ?? untitledName }

    /// The folder a user recognises, shown under the name. Nil while unsaved.
    public var locationDescription: String? {
        url?.deletingLastPathComponent().path(percentEncoded: false)
    }

    public var isDirty: Bool { model.isDirty }
    public var hasNeverBeenSaved: Bool { url == nil }

    /// Changing the language re-parses under the new grammar rather than waiting for the next edit.
    public func setLanguage(_ language: LanguageID) {
        guard model.language != language else { return }
        model.language = language
        model.startBuiltInHighlighting()
    }

    // MARK: Saving

    /// Writes the document where it already lives. Throws for one that has never been saved —
    /// choosing a location is the workspace's job, because it needs a file panel.
    public func save() throws {
        guard let url else { throw GlassEditorWorkspaceError.needsLocation }
        try write(to: url)
    }

    /// Writes to a new location and adopts it, so the document's name, language and future saves
    /// all follow the file the user chose.
    public func save(to newURL: URL) throws {
        try write(to: newURL)
        url = newURL
        setLanguage(LanguageID.forFileExtension(newURL.pathExtension))
    }

    private func write(to url: URL) throws {
        // The line endings the file arrived with, not this platform's: an editor that silently
        // rewrites every line terminator produces a diff of the whole file on the first save.
        let content = LineEndingDetector.normalize(model.text, to: model.snapshot.lineEndings)
        try AtomicSaver.save(content, encoding: model.snapshot.encoding, to: url)
        model.markClean()
    }
}

public enum GlassEditorWorkspaceError: LocalizedError, Equatable {
    case needsLocation
    case notAFile(String)

    public var errorDescription: String? {
        switch self {
        case .needsLocation: "This document has never been saved. Choose where to put it."
        case .notAFile(let name): "\(name) is a folder, not a file."
        }
    }
}

extension LineEndingStyle {
    /// What a new document uses. LF everywhere: every platform this app runs on is a Unix, and the
    /// machines it edits over SFTP overwhelmingly are too.
    static var platformDefault: LineEndingStyle { .lf }
}
