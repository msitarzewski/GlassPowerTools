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
    /// The machine it is on, when that machine is not this one. Nil is the ordinary local case.
    public private(set) var machine: String?
    /// The name a user gave an unsaved document, so it is not "Untitled" forever.
    private let untitledName: String

    /// What *this file* says about the text, over whatever its project and the app say
    /// (`GlassEditorTextOverrides`). **Held while the document is open and not stored**: it is the
    /// answer to "this one file is different", and a file is different for as long as you are
    /// looking at it. The durable levels are the project's and the app's.
    public var textOverrides = GlassEditorTextOverrides()

    /// What the file looked like when it was read, and the baseline every save compares against.
    ///
    /// **Kept for a local file as well as a remote one.** A file on this disk changes underneath
    /// the editor too — a checkout, a build, another editor — and an editor that notices only when
    /// the file is on a server is an editor that quietly overwrote your rebase. The type is called
    /// `RemoteDocumentSession` because it was written for the SFTP editor; it holds a size, a
    /// modification time and a digest, which mean the same thing on both machines.
    public private(set) var session: RemoteDocumentSession?

    /// Set when the file is not text: an image, a PDF, a video, a sound, another binary. The text
    /// model is then empty and never dirty, so nothing that saves or searches reaches it.
    public let viewer: GlassEditorViewer?

    public init(model: GlassEditorModel, url: URL?, untitledName: String = "Untitled",
                machine: String? = nil, session: RemoteDocumentSession? = nil,
                viewer: GlassEditorViewer? = nil) {
        self.model = model
        self.viewer = viewer
        self.url = url
        self.untitledName = untitledName
        self.machine = machine
        self.session = session
    }

    // MARK: Opening

    /// Reads a file and prepares it for editing, keeping its encoding and line endings.
    ///
    /// **One path for both machines.** Where the bytes came from is the argument; everything after
    /// it — the encoding, the line endings, the language, the baseline a later save compares
    /// against — is the same work, and doing it twice would mean doing the second one worse.
    ///
    /// **Not every file is text** (2026-09-23). The bytes are classified before they are decoded,
    /// because decoding cannot fail — its Latin-1 fallback accepts anything — and a PNG decoded is
    /// a page of garbage. `asText` is the not-text screen's "Open as Text", on request only.
    /// `allowLargeRemote` is the answer to the question a large remote media file asks first.
    public static func open(path: String,
                            through access: any GlassEditorFileAccess,
                            machine: String? = nil,
                            asText: Bool = false,
                            allowLargeRemote: Bool = false) async throws -> GlassEditorDocument {
        let url = URL(filePath: path)
        let name = url.lastPathComponent
        if machine != nil, !asText, !allowLargeRemote,
           let size = (try? await access.stat(path))?.size, size > GlassEditorOpenError.remoteMediaLimit,
           GlassEditorFileKind.classify(name: name, prefix: Data()) != .text {
            throw GlassEditorOpenError.largeRemoteFile(name: name, bytes: size)
        }
        let data = try await access.read(path)
        let kind = asText ? .text : GlassEditorFileKind.classify(name: name, prefix: data.prefix(GlassEditorFileKind.sniffLength))
        if !kind.isText {
            let viewer = machine == nil
                ? GlassEditorViewer(kind: kind, fileURL: url, byteCount: data.count, temporaryDirectory: nil)
                : try GlassEditorViewer.copying(data, named: name, kind: kind)
            let snapshot = DocumentSnapshot(content: "", encoding: .utf8(hadBOM: false),
                                            lineEndings: LineEndingStyle.platformDefault, origin: .local(url))
            return GlassEditorDocument(model: GlassEditorModel(snapshot: snapshot, language: .plaintext),
                                       url: url, machine: machine, viewer: viewer)
        }
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
        let hasVeryLongLine = Self.hasLine(longerThan: veryLongLine, in: model)
        if model.language == .plaintext {
            let sniffed = LanguageID.forContent(decoded.content)
            if sniffed != .plaintext { model.language = sniffed }
        }
        // The digest is free here: the bytes are already in hand, and it is what makes the
        // conflict check exact rather than a guess about a coarse modification time.
        let session = RemoteDocumentSession(
            ref: RemoteDocumentRef(connectionID: UUID(), host: machine ?? "", path: path),
            openedStat: (try? await access.stat(path)) ?? RemoteStat(),
            openedDigest: access.digest(of: data)
        )
        let document = GlassEditorDocument(model: model, url: url, machine: machine, session: session)
        // **A line this long is laid out wrapped** (2026-09-23). Apple's text engine lays out a
        // paragraph at a time, and unwrapped a 14.6-million-character line is one enormous
        // fragment: 26 seconds on the main thread for the user's logo SVG, against about one
        // second wrapped. BBEdit gets away without it because it has its own engine. Set on this
        // file only, as the file's own override, so the gear can still turn it off.
        if hasVeryLongLine {
            document.textOverrides.wrapsLines = true
            document.hasVeryLongLine = true
        }
        return document
    }

    /// Characters on one line past which the file is laid out wrapped, and a phone opens it in
    /// Preview when there is one.
    public static let veryLongLine = 100_000

    /// Whether this file has a line longer than `veryLongLine`, found when it was opened.
    public private(set) var hasVeryLongLine = false

    /// A document shorter than the limit cannot have such a line, so most files cost one compare.
    static func hasLine(longerThan limit: Int, in model: GlassEditorModel) -> Bool {
        guard model.utf16Length > limit else { return false }
        return (0..<model.lineCount).contains { model.lineRange(ofLine: $0).count > limit }
    }

    /// The local convenience, unchanged for every caller that has a `URL` and means this device.
    public static func open(_ url: URL) async throws -> GlassEditorDocument {
        try await open(path: url.path(percentEncoded: false), through: GlassEditorLocalFileAccess())
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

    /// Where the file is on its machine, in the one spelling everything compares against.
    public var path: String? { url?.path(percentEncoded: false) }

    /// The folder a user recognises, shown under the name, with the machine when it is not this
    /// one — because `/srv/app` on two machines is two different files and the path alone does not
    /// say which you are editing. Nil while unsaved.
    public var locationDescription: String? {
        // Normalized, because `deletingLastPathComponent` leaves a trailing separator and
        // "/srv/app/" is not the same string as the project root it is meant to match — the
        // duplicate-project defect, in a different place.
        guard let raw = url?.deletingLastPathComponent().path(percentEncoded: false) else {
            return nil
        }
        let folder = GlassEditorProject.normalized(raw)
        guard let machine, !machine.isEmpty else { return folder }
        return "\(machine) · \(folder)"
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

    /// What the file on the machine looks like now, against what it looked like when it was
    /// opened. Asked before every save, on both machines.
    ///
    /// A failed stat returns `.indeterminate` rather than `.noConflict`: not having looked is not
    /// the same as having looked and seen no change, and `ConflictDetector` is built around
    /// exactly that distinction.
    public func conflictState(through access: any GlassEditorFileAccess) async -> ConflictState {
        await checkBeforeSaving(through: access).state
    }

    /// What the machine says about the file right now, **and what it looked like while saying it**.
    ///
    /// The second half is what the write then expects. Expecting the *opened* stat instead would
    /// refuse every save that followed a harmless change: a build touches the file, the digest
    /// proves nothing was altered, the user is not asked — and then the write refuses anyway,
    /// because the timestamp moved. The observation the decision was made against is the one the
    /// decision authorises.
    public func checkBeforeSaving(through access: any GlassEditorFileAccess) async -> GlassEditorSaveCheck {
        guard let session, let path = url?.path(percentEncoded: false) else {
            return GlassEditorSaveCheck(state: .noConflict, observed: nil)
        }
        let currentStat = try? await access.stat(path)
        let cheap = ConflictDetector.classify(session: session,
                                              currentStat: currentStat,
                                              currentDigest: nil,
                                              localDirty: model.isDirty)
        // Tier 1 said nothing has changed, which is the common case and the whole reason it is
        // asked first: saving does not cost a download.
        guard cheap != .noConflict else {
            return GlassEditorSaveCheck(state: .noConflict, observed: currentStat)
        }

        // It said something *might* have. Tier 2 is what turns that into an answer — and it has to
        // be asked, because with unsaved edits and no digest the detector reports `.indeterminate`
        // rather than guess, which would put a question in front of the user every time a build
        // touched a file it did not change.
        guard let currentDigest = (try? await access.read(path)).flatMap({ access.digest(of: $0) })
        else { return GlassEditorSaveCheck(state: cheap, observed: currentStat) }
        let settled = ConflictDetector.classify(session: session,
                                                currentStat: currentStat,
                                                currentDigest: currentDigest,
                                                localDirty: model.isDirty)
        return GlassEditorSaveCheck(state: settled, observed: currentStat)
    }

    /// Writes the document where it already lives. Throws for one that has never been saved —
    /// choosing a location is the workspace's job, because it needs a file panel.
    public func save(through access: any GlassEditorFileAccess,
                     expecting: RemoteStat? = nil) async throws {
        // A viewer is never edited, so there is nothing to write — and writing its empty text
        // model over a picture is the one thing this must never do.
        guard viewer == nil else { return }
        guard let url else { throw GlassEditorWorkspaceError.needsLocation }
        try await write(to: url, through: access, expecting: expecting)
    }

    /// Writes to a new location and adopts it, so the document's name, language and future saves
    /// all follow the file the user chose. Local by definition: the panel that chose it is this
    /// device's.
    /// Writes to a new location on any machine and adopts it — the remote twin of `save(to:)`,
    /// for a new document saved into a project on a server (2026-09-26). The access is the
    /// project's own, so the bytes go the way the project's files go.
    public func save(toPath path: String, through access: any GlassEditorFileAccess,
                     machine: String?) async throws {
        guard viewer == nil else { return }
        let newURL = URL(filePath: path)
        // A new location expects nothing: the caller checked the name was free.
        try await write(to: newURL, through: access, expecting: nil)
        url = newURL
        self.machine = machine
        setLanguage(LanguageID.forFileExtension(newURL.pathExtension))
    }

    public func save(to newURL: URL) async throws {
        guard viewer == nil else { return }
        let access = GlassEditorLocalFileAccess()
        // A new location expects nothing: whatever is there is being replaced deliberately.
        try await write(to: newURL, through: access, expecting: nil)
        url = newURL
        machine = nil
        setLanguage(LanguageID.forFileExtension(newURL.pathExtension))
    }

    private func write(to url: URL, through access: any GlassEditorFileAccess,
                       expecting: RemoteStat?) async throws {
        // The line endings the file arrived with, not this platform's: an editor that silently
        // rewrites every line terminator produces a diff of the whole file on the first save.
        let content = LineEndingDetector.normalize(model.text, to: model.snapshot.lineEndings)
        let data = try EncodingDetector.encode(content, as: model.snapshot.encoding)
        let path = url.path(percentEncoded: false)
        // What the file was when this document last looked, so the write refuses to land on a
        // version nobody has seen. A document with no session — a brand-new file — expects
        // nothing, which is exactly right.
        let committed = try await access.write(data, to: path, expecting: expecting)
        // The baseline becomes what was just written, as the machine described it. Without this
        // the very next check would compare against the pre-save identity and report our own
        // write as somebody else's.
        if let session {
            self.session = session.updatingAfterSave(
                stat: committed ?? RemoteStat(),
                digest: access.digest(of: data)
            )
        }
        model.markClean()
    }

    /// Throws away local edits and takes the file as it is on the machine now.
    public func reload(through access: any GlassEditorFileAccess) async throws {
        guard viewer == nil else { return }
        guard let url else { throw GlassEditorWorkspaceError.needsLocation }
        let fresh = try await Self.open(path: url.path(percentEncoded: false),
                                        through: access, machine: machine)
        // Into the model that is already on screen, so the window, its tab and its scroll
        // position all survive a reload — replacing the document would be a different tab.
        try model.replaceAllContent(with: fresh.model.text)
        session = fresh.session
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
