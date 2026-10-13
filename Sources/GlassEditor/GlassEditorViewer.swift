//
//  GlassEditorViewer.swift
//  Glass Power Tools — GlassEditor
//
//  A file that is not text, open in a tab as what it is (2026-09-23: *"when I click a png I get
//  the image, not the binary?"*). Plan: memory-bank/tasks/2026-09/2026-09-23_viewers-and-preview.md.
//
//  It rides on an ordinary `GlassEditorDocument`, so tabs, preview tabs, duplicate detection and
//  Active treat it like any other file; the document's text model is empty and never dirty, which
//  is what keeps save, find and the conflict machinery away from it without a check at each.
//

import Foundation
import GlassEditorCore

public final class GlassEditorViewer: Sendable {
    public let kind: GlassEditorFileKind
    /// A file the system viewers can open: the file itself on this device, a temporary copy of
    /// one on another machine (players, PDFKit and Quick Look all want a URL, not bytes).
    public let fileURL: URL
    public let byteCount: Int
    /// The folder a remote file was copied into, removed when the viewer goes. Nil for a local
    /// file, which is shown in place and never touched.
    private let temporaryDirectory: URL?

    init(kind: GlassEditorFileKind, fileURL: URL, byteCount: Int, temporaryDirectory: URL?) {
        self.kind = kind
        self.fileURL = fileURL
        self.byteCount = byteCount
        self.temporaryDirectory = temporaryDirectory
    }

    /// A viewer for bytes read from another machine: written under the caches directory, in a
    /// folder of its own so the file keeps its real name (players and Quick Look read the
    /// extension).
    static func copying(_ data: Data, named name: String, kind: GlassEditorFileKind,
                        root: URL = GlassEditorViewer.temporaryRoot) throws -> GlassEditorViewer {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = name.isEmpty ? "file" : name.replacingOccurrences(of: "/", with: "_")
        let url = folder.appendingPathComponent(safeName)
        try data.write(to: url, options: .atomic)
        return GlassEditorViewer(kind: kind, fileURL: url, byteCount: data.count, temporaryDirectory: folder)
    }

    static var temporaryRoot: URL {
        URL.cachesDirectory.appendingPathComponent("GlassEditorViewers", isDirectory: true)
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    /// "2.4 MB", for the not-text screen and the large-file question.
    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

/// Why an open stopped to ask rather than going ahead.
public enum GlassEditorOpenError: LocalizedError, Equatable {
    /// A media file on another machine big enough that downloading it deserves a yes first.
    case largeRemoteFile(name: String, bytes: UInt64)

    public var errorDescription: String? {
        switch self {
        case .largeRemoteFile(let name, let bytes):
            "\(name) is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)). Download it to view?"
        }
    }

    /// Above this, a remote media file is asked about before it is read. Reads are whole-file into
    /// memory; a large local media file is not read at all, because the system viewers map it from
    /// disk (`GlassEditorDocument.open`).
    public static let remoteMediaLimit: UInt64 = 64 * 1024 * 1024
}

/// Why a local file is not read at all (2026-10-12). Not a `GlassEditorOpenError`: those are
/// questions the window asks, and these are answers. Each reads after "… could not be opened:".
public enum GlassEditorReadRefusal: LocalizedError, Equatable {
    /// A named pipe, a device, a socket or a folder: reading one can wait forever or never end.
    case notAFile(name: String, what: String)
    /// Larger than the editor reads into memory (`GlassEditorLocalFileAccess.byteCeiling`).
    case tooLarge(name: String, bytes: UInt64, limit: UInt64)

    public var errorDescription: String? {
        switch self {
        case .notAFile(_, let what):
            "it is \(what), not a file."
        case .tooLarge(_, let bytes, let limit):
            "at \(Self.size(bytes)) it is larger than the \(Self.size(limit)) the editor opens. Open it in another app."
        }
    }

    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// What a file's type bits say it is, in words.
    static func describe(mode: mode_t) -> String {
        switch mode & S_IFMT {
        case S_IFIFO: "a named pipe"
        case S_IFCHR, S_IFBLK: "a device"
        case S_IFSOCK: "a socket"
        case S_IFDIR: "a folder"
        default: "something other than a file"
        }
    }
}
