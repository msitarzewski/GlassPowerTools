import Foundation
import Testing
@testable import GlassEditorCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Save is the one operation in this package that can destroy work that has
/// never existed anywhere else. These tests are the M5 "no truncated files,
/// ever" gate expressed headlessly.
@Suite("Atomic save")
struct AtomicSaverTests {

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassEditorKit-AtomicSaverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mode(of url: URL) throws -> mode_t {
        var info = stat()
        guard url.path.withCString({ stat($0, &info) }) == 0 else {
            throw AtomicSaverTestError.statFailed(url.path)
        }
        return info.st_mode & 0o7777
    }

    /// Everything in the directory except the file we expect to be there.
    private func strayFiles(in directory: URL, expecting expected: Set<String>) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !expected.contains($0) }
    }

    enum AtomicSaverTestError: Error {
        case statFailed(String)
    }

    // MARK: - Round trip

    @Test("Saving what was loaded reproduces the file byte-for-byte", arguments: Fixture.all)
    func untouchedSaveChangesNoBytes(_ expected: Fixture.Expectation) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = try Fixture.data(expected.name)
        let url = directory.appendingPathComponent(expected.name)
        try original.write(to: url)

        let snapshot = try DocumentLoader.load(from: url, configuration: GlassEditorConfiguration())
        try AtomicSaver.save(snapshot)

        #expect(try Data(contentsOf: url) == original, "open-then-save mutated \(expected.name)")
    }

    @Test("Edited content is written under the document's original encoding")
    func editedContentKeepsEncoding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("bom.txt")
        try Fixture.data("utf8-bom.txt").write(to: url)

        var snapshot = try DocumentLoader.load(from: url, configuration: GlassEditorConfiguration())
        snapshot.content += "appended line\n"
        try AtomicSaver.save(snapshot)

        let written = try Data(contentsOf: url)
        #expect(Array(written.prefix(3)) == [0xEF, 0xBB, 0xBF], "the BOM did not survive an edit")

        let reloaded = try DocumentLoader.load(from: url, configuration: GlassEditorConfiguration())
        #expect(reloaded.content == snapshot.content)
        #expect(reloaded.encoding == .utf8(hadBOM: true))
    }

    @Test("Saving creates a file that did not exist")
    func createsNewFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("new.txt")
        try AtomicSaver.save("fresh\n", encoding: .utf8(hadBOM: false), to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "fresh\n")
        #expect(try mode(of: url) == 0o644)
        #expect(try strayFiles(in: directory, expecting: ["new.txt"]).isEmpty)
    }

    @Test("Saving empty content produces an empty file, not a failure")
    func emptyContent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("empty.txt")
        try AtomicSaver.save("", encoding: .utf8(hadBOM: false), to: url)
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test("Saving a large buffer writes every byte, short writes included")
    func largeContentIsComplete() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("large.txt")
        let content = String(repeating: "the quick brown fox jumps over the lazy dog\n", count: 40_000)
        try AtomicSaver.save(content, encoding: .utf8(hadBOM: false), to: url)

        let written = try Data(contentsOf: url)
        #expect(written.count == content.utf8.count)
        #expect(try String(contentsOf: url, encoding: .utf8) == content)
    }

    // MARK: - Permissions

    @Test("An existing file's POSIX permissions survive the save")
    func preservesPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("secret.env")
        try Data("API_KEY=one\n".utf8).write(to: url)
        #expect(url.path.withCString { chmod($0, 0o600) } == 0)
        #expect(try mode(of: url) == 0o600)

        try AtomicSaver.save("API_KEY=two\n", encoding: .utf8(hadBOM: false), to: url)

        #expect(try mode(of: url) == 0o600, "an atomic save widened a private file's permissions")
        #expect(try String(contentsOf: url, encoding: .utf8) == "API_KEY=two\n")
    }

    @Test("Unusual modes are preserved exactly, not rounded to something sensible")
    func preservesUnusualMode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("script.sh")
        try Data("#!/bin/sh\necho one\n".utf8).write(to: url)
        #expect(url.path.withCString { chmod($0, 0o751) } == 0)

        try AtomicSaver.save("#!/bin/sh\necho two\n", encoding: .utf8(hadBOM: false), to: url)
        #expect(try mode(of: url) == 0o751, "the executable bit did not survive the save")
    }

    // MARK: - Failure paths

    @Test("A save that cannot start leaves no temp file and no damaged destination",
          .enabled(if: geteuid() != 0, "root bypasses directory permissions entirely"))
    func failedSaveIsInvisible() throws {

        let directory = try temporaryDirectory()
        defer {
            _ = directory.path.withCString { chmod($0, 0o700) }
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("precious.txt")
        let original = "work that exists nowhere else\n"
        try Data(original.utf8).write(to: url)

        // Read + execute, no write: the temp file cannot be created.
        #expect(directory.path.withCString { chmod($0, 0o500) } == 0)

        #expect(throws: EditorError.self) {
            try AtomicSaver.save("replacement\n", encoding: .utf8(hadBOM: false), to: url)
        }

        #expect(directory.path.withCString { chmod($0, 0o700) } == 0)
        #expect(try String(contentsOf: url, encoding: .utf8) == original, "a failed save damaged the destination")
        #expect(try strayFiles(in: directory, expecting: ["precious.txt"]).isEmpty, "a failed save left a temp file")
    }

    @Test("An unencodable edit fails before anything is written")
    func encodingFailureLeavesFileAlone() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("latin1.txt")
        let original = Data("caf\u{E9}\n".utf8)
        try original.write(to: url)

        #expect(throws: EditorError.self) {
            // An emoji pasted into a Latin-1 document: refused, never written as '?'.
            try AtomicSaver.save("caf\u{E9} 🙂\n", encoding: .latin1Fallback, to: url)
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try strayFiles(in: directory, expecting: ["latin1.txt"]).isEmpty)
    }

    @Test("Remote and ephemeral origins are refused, never half-saved locally")
    func refusesOriginsThePackageDoesNotOwn() {
        let remote = DocumentOrigin.remote(
            RemoteDocumentRef(connectionID: UUID(), host: "charlie.example.com", path: "/etc/hosts")
        )
        #expect(throws: EditorError.self) {
            try AtomicSaver.save("x", encoding: .utf8(hadBOM: false), to: remote)
        }
        #expect(throws: EditorError.self) {
            try AtomicSaver.save("x", encoding: .utf8(hadBOM: false), to: .ephemeral(id: UUID()))
        }

        let snapshot = DocumentLoader.make(content: "SELECT 1;", origin: .ephemeral(id: UUID()))
        #expect(throws: EditorError.self) { try AtomicSaver.save(snapshot) }
    }

    // MARK: - Symlinks

    @Test("A symlinked destination is written through to its target")
    func followsSymlinkToTarget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let realDirectory = directory.appendingPathComponent("repo", isDirectory: true)
        let linkDirectory = directory.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true)

        let target = realDirectory.appendingPathComponent("zshrc")
        try Data("export ONE=1\n".utf8).write(to: target)
        #expect(target.path.withCString { chmod($0, 0o640) } == 0)

        let link = linkDirectory.appendingPathComponent(".zshrc")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try AtomicSaver.save("export TWO=2\n", encoding: .utf8(hadBOM: false), to: link)

        // The link is still a link, and the file it points at got the content.
        let linkAttributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(linkAttributes[.type] as? FileAttributeType == .typeSymbolicLink,
                "the save replaced the symlink with a regular file")
        #expect(try String(contentsOf: target, encoding: .utf8) == "export TWO=2\n")
        #expect(try mode(of: target) == 0o640, "the target's permissions were not preserved")

        // The temp file lived beside the target, not beside the link.
        #expect(try strayFiles(in: realDirectory, expecting: ["zshrc"]).isEmpty)
        #expect(try strayFiles(in: linkDirectory, expecting: [".zshrc"]).isEmpty)
    }

    // MARK: - Concurrency

    @Test("Concurrent saves leave one complete version — never an interleaving")
    func concurrentSavesAreNeverInterleaved() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("contended.txt")

        // Distinct, large, self-consistent payloads: a partial or blended write
        // could not possibly equal any one of them.
        let candidates = (0..<12).map { index in
            String(repeating: "writer-\(index) line\n", count: 5_000)
        }

        await withTaskGroup(of: Void.self) { group in
            for content in candidates {
                group.addTask {
                    try? AtomicSaver.save(content, encoding: .utf8(hadBOM: false), to: url)
                }
            }
        }

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(candidates.contains(written), "the file is not any one writer's complete content")
        #expect(try strayFiles(in: directory, expecting: ["contended.txt"]).isEmpty,
                "concurrent saves left temp files behind")
    }

    @Test("A reader concurrent with repeated saves never observes a partial file")
    func readerNeverSeesTruncation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("watched.txt")
        let candidates = (0..<8).map { index in
            String(repeating: "version-\(index)\n", count: 8_000)
        }
        try AtomicSaver.save(candidates[0], encoding: .utf8(hadBOM: false), to: url)

        async let writes: Void = {
            for _ in 0..<6 {
                for content in candidates {
                    try? AtomicSaver.save(content, encoding: .utf8(hadBOM: false), to: url)
                }
            }
        }()

        var observations = 0
        var partials = 0
        for _ in 0..<400 {
            if let seen = try? String(contentsOf: url, encoding: .utf8) {
                observations += 1
                if !candidates.contains(seen) { partials += 1 }
            }
        }
        await writes

        #expect(observations > 0)
        #expect(partials == 0, "\(partials) of \(observations) reads saw a file mid-write")
    }
}
