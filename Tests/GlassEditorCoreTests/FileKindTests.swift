import Foundation
import Testing
@testable import GlassEditorCore

/// What a file is before anything reads it as text (2026-09-23: a PNG opened as decoded bytes).
@Suite("What kind of file this is")
struct FileKindTests {
    private func bytes(_ values: [UInt8], padTo count: Int = 32) -> Data {
        Data(values + Array(repeating: 0x20, count: max(0, count - values.count)))
    }
    private func ftyp(_ brand: String) -> Data {
        Data([0, 0, 0, 0x18] + Array("ftyp".utf8) + Array(brand.utf8) + Array(repeating: 0, count: 12))
    }

    @Test("Signatures decide, whatever the name says")
    func signaturesWin() {
        let png = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(GlassEditorFileKind.classify(name: "logo.png", prefix: png) == .image)
        #expect(GlassEditorFileKind.classify(name: "notes.txt", prefix: png) == .image, "a PNG named .txt")
        #expect(GlassEditorFileKind.classify(name: "a.jpg", prefix: bytes([0xFF, 0xD8, 0xFF, 0xE0])) == .image)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: Data("GIF89a".utf8)) == .image)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)) == .image)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: Data("%PDF-1.7\n".utf8)) == .pdf)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: Data("ID3\u{4}".utf8)) == .audio)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: Data("RIFF\u{0}\u{0}\u{0}\u{0}WAVEfmt ".utf8)) == .audio)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: ftyp("isom")) == .video)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: ftyp("qt  ")) == .video)
        #expect(GlassEditorFileKind.classify(name: "a", prefix: ftyp("heic")) == .image, "HEIC is an image in an MP4 box")
        #expect(GlassEditorFileKind.classify(name: "a", prefix: ftyp("M4A ")) == .audio)
    }

    @Test("Text stays text, even named like media; SVG, HTML, Markdown and CSV are text")
    func textIsText() {
        let text = Data("# Title\n\nHello, oscar.\n".utf8)
        #expect(GlassEditorFileKind.classify(name: "README.md", prefix: text) == .text)
        #expect(GlassEditorFileKind.classify(name: "fake.png", prefix: text) == .text, "text bytes behind a media name")
        #expect(GlassEditorFileKind.classify(name: "icon.svg", prefix: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)) == .text)
        #expect(GlassEditorFileKind.classify(name: "data.csv", prefix: Data("a,b\n1,2\n".utf8)) == .text)
        #expect(GlassEditorFileKind.classify(name: "empty.txt", prefix: Data()) == .text)
        #expect(GlassEditorFileKind.classify(name: "utf16.txt", prefix: Data([0xFF, 0xFE, 0x41, 0x00])) == .text,
                "UTF-16 with a byte-order mark has NULs and is text")
    }

    @Test("NULs without a signature are a binary, or the named media kind")
    func otherBinaries() {
        let blob = Data([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x00, 0x00])   // an ELF executable
        #expect(GlassEditorFileKind.classify(name: "server", prefix: blob) == .binary)
        #expect(GlassEditorFileKind.classify(name: "clip.avi", prefix: blob) == .video,
                "no signature this build knows, but binary bytes and a video name")
        #expect(GlassEditorFileKind.classify(name: "empty.png", prefix: Data()) == .image, "an empty file takes its name")
    }
}
