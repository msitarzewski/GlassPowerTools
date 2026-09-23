//
//  FileKind.swift
//  Glass Power Tools — GlassEditorCore
//
//  What a file is, before anything tries to read it as text.
//
//  Until 2026-09-23 every file went through `EncodingDetector.decode`, whose Latin-1 fallback is
//  total — any byte sequence decodes — so a PNG opened as a page of garbage instead of failing or
//  showing the picture (*"when I click a png I get the image, not the binary?"*). This answers the
//  question first: by the name, then by the bytes, and the bytes win.
//

import Foundation
import UniformTypeIdentifiers

public enum GlassEditorFileKind: String, Sendable, Equatable, CaseIterable {
    case text, image, pdf, video, audio, binary

    /// Whether the editor's text engine is the right surface.
    public var isText: Bool { self == .text }

    /// How much of a file the byte check needs. Enough for every signature below and for the
    /// NUL scan that separates text from other binaries.
    public static let sniffLength = 8_192

    /// The kind, from the name and the first bytes.
    ///
    /// **The bytes win.** A PNG saved as `notes.txt` is an image; a file named `.png` holding text
    /// is text. The name is the tiebreak when the bytes say nothing specific.
    ///
    /// **SVG stays text.** It is XML someone edits, and its picture is Preview's job, not a
    /// viewer's — so is HTML, Markdown and CSV.
    public static func classify(name: String, prefix: Data) -> GlassEditorFileKind {
        if let signed = signature(prefix) { return signed }
        let byName = kind(forExtension: (name as NSString).pathExtension)
        if prefix.isEmpty { return byName ?? .text }
        if looksBinary(prefix) { return byName.flatMap { $0 == .text ? nil : $0 } ?? .binary }
        // Text bytes: a media extension on text content is a mislabelled text file.
        return .text
    }

    /// Kinds that are certain from a file's opening bytes.
    static func signature(_ data: Data) -> GlassEditorFileKind? {
        let b = [UInt8](data.prefix(16))
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .image }       // PNG
        if starts([0xFF, 0xD8, 0xFF]) { return .image }                                       // JPEG
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return .image }     // GIF
        if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { return .image }  // WebP
        if starts(Array("RIFF".utf8)) && starts(Array("WAVE".utf8), at: 8) { return .audio }  // WAV
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .image } // TIFF
        if starts(Array("BM".utf8)) && b.count >= 14 { return .image }                        // BMP
        if starts([0x00, 0x00, 0x01, 0x00]) { return .image }                                 // ICO
        if starts(Array("%PDF-".utf8)) { return .pdf }
        if starts(Array("ID3".utf8)) || starts([0xFF, 0xFB]) || starts([0xFF, 0xF3]) || starts([0xFF, 0xF2]) {
            return .audio                                                                     // MP3
        }
        if starts(Array("fLaC".utf8)) || starts(Array("OggS".utf8)) { return .audio }
        // ISO base media: a size, then "ftyp", then the brand that says what it holds.
        if starts(Array("ftyp".utf8), at: 4), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1", "avif": return .image
            case "M4A ", "M4B ", "M4P ": return .audio
            default: return .video                                                            // mp4, isom, qt, 3gp…
            }
        }
        if starts([0x1A, 0x45, 0xDF, 0xA3]) { return .video }                                 // Matroska/WebM
        return nil
    }

    /// The kind a file extension names, when it names a visual one.
    static func kind(forExtension ext: String) -> GlassEditorFileKind? {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext.lowercased()) else { return nil }
        if type.conforms(to: .svg) { return .text }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return .text }
        return nil
    }

    /// A NUL in the opening bytes is the classic, dependable sign of a non-text file; UTF-16
    /// with a byte-order mark is the exception, and is text.
    static func looksBinary(_ data: Data) -> Bool {
        let head = data.prefix(sniffLength)
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return false }
        return head.contains(0)
    }
}
