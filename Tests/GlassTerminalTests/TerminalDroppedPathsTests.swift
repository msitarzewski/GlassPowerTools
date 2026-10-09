import Foundation
#if os(macOS)
import AppKit
#endif
import Testing
@testable import GlassTerminal

/// Files dropped on a terminal type their paths, escaped for the shell (2026-10-07).
@Suite("Dropped paths")
struct TerminalDroppedPathsTests {
    @Test("plain paths stand as they are; spaces and shell characters are escaped")
    func escaping() {
        #expect(TerminalDroppedPaths.escaped("/Users/ann/Pictures/photo-1.jpg") == "/Users/ann/Pictures/photo-1.jpg")
        #expect(TerminalDroppedPaths.escaped("/Users/ann/My Pictures/a (1).png") == #"/Users/ann/My\ Pictures/a\ \(1\).png"#)
        #expect(TerminalDroppedPaths.escaped("/tmp/it's $HOME & `x`;") == #"/tmp/it\'s\ \$HOME\ \&\ \`x\`\;"#)
        #expect(TerminalDroppedPaths.escaped("/tmp/café/日本.txt") == "/tmp/café/日本.txt")
        #expect(TerminalDroppedPaths.escaped("/tmp/two\nlines") == #"$'/tmp/two\nlines'"#)
    }

    @Test("several files: one line, space separated, a space after, never a newline")
    func several() {
        let urls = [URL(fileURLWithPath: "/tmp/a b.png"), URL(fileURLWithPath: "/tmp/c.txt"),
                    URL(string: "https://example.com/x")!]
        #expect(TerminalDroppedPaths.text(for: urls) == #"/tmp/a\ b.png /tmp/c.txt "#)
        #expect(TerminalDroppedPaths.text(for: [URL(string: "https://example.com")!]) == nil)
    }

    /// The escaping is only right if a shell reads it back as the same path.
    @Test("a shell reads every escaped path back unchanged")
    func shellRoundTrip() throws {
        for path in ["/tmp/My Pictures/a (1).png", "/tmp/it's $HOME & `x`;", "/tmp/[brackets]{x}*?#~!",
                     "/tmp/café/日本.txt", "/tmp/two\nlines\tand tab", "/tmp/back\\slash"] {
            for shell in ["/bin/zsh", "/bin/bash"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-c", "printf '%s' " + TerminalDroppedPaths.escaped(path)]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                process.waitUntilExit()
                let echoed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                #expect(echoed == path, "\(shell): \(path.debugDescription) came back \(echoed.debugDescription)")
            }
        }
    }

    // MARK: Files a drop has to write (2026-10-09)
    //
    // A screenshot dragged from its floating thumbnail is a file promise, and an image dragged
    // from a browser is bare data: neither is a file until the drop writes it. The path is typed
    // into the shell and read afterwards, so what the drop writes has to stay.

    @Test("the inbox is the app's own folder in the caches, and drops older than a week are cleared")
    func inbox() throws {
        let caches = FileManager.default.temporaryDirectory.appendingPathComponent("drop-caches-\(UUID())")
        defer { try? FileManager.default.removeItem(at: caches) }
        let now = Date()
        let inbox = try TerminalDroppedPaths.inbox(caches: caches, now: now)
        #expect(inbox.path.hasPrefix(caches.path) && inbox.lastPathComponent == TerminalDroppedPaths.inboxName)
        let old = inbox.appendingPathComponent("old"), fresh = inbox.appendingPathComponent("fresh")
        for folder in [old, fresh] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.creationDate: now.addingTimeInterval(-8 * 24 * 60 * 60)], ofItemAtPath: old.path)
        _ = try TerminalDroppedPaths.inbox(caches: caches, now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path), "a week old: cleared")
        #expect(FileManager.default.fileExists(atPath: fresh.path), "recent: kept")
    }

    @Test("a terminal's staging keeps its files; an upload's goes when it is released")
    func staging() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("drop-keep-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        var kept: SFTPDropStaging? = try SFTPDropStaging(keepingFilesIn: parent)
        let keptDirectory = try #require(kept?.directory)
        var temporary: SFTPDropStaging? = try SFTPDropStaging()
        let temporaryDirectory = try #require(temporary?.directory)
        kept = nil
        temporary = nil
        #expect(FileManager.default.fileExists(atPath: keptDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    #if os(macOS)
    @Test("an image dropped as bare data becomes a file that stays, and its path is what is typed")
    @MainActor func imageData() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("drop-image-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let provider = NSItemProvider()
        provider.suggestedName = "Screenshot"
        provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
            completion(png, nil)
            return nil
        }
        // A private pasteboard: nothing of the real drag pasteboard can stand in for this drop.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("drop-test-\(UUID())"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }
        let drop = try #require(SFTPIncomingDrop(providers: [provider], pasteboard: pasteboard))
        var staging: SFTPDropStaging? = try SFTPDropStaging(keepingFilesIn: parent)
        let urls = try await drop.materialize(into: try #require(staging)).urls
        staging = nil
        let url = try #require(urls.first)
        #expect(url.path.hasPrefix(parent.path))
        #expect(try Data(contentsOf: url) == png, "the file is still there after the drop")
        #expect(TerminalDroppedPaths.text(for: urls) == TerminalDroppedPaths.escaped(url.path) + " ")
    }

    @Test("a promised file arrives on AppKit's queue without stopping the app")
    func promiseReaderOffTheMainThread() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("drop-promise-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        let staging = try SFTPDropStaging(keepingFilesIn: parent)
        let file = staging.directory.appendingPathComponent("Screenshot.png")
        let (stream, continuation) = AsyncThrowingStream<URL, Error>.makeStream()
        let reader = SFTPIncomingDrop.promiseReader(staging: staging, continuation: continuation)
        // As NSFilePromiseReceiver does: on its operation queue, not the main thread.
        let queue = OperationQueue()
        queue.addOperation { reader(file, nil) }
        var received: [URL] = []
        for try await url in stream { received.append(url); break }
        #expect(received == [file])
    }

    @Test("a file that already exists types its own path, not a copy")
    @MainActor func existingFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-existing-\(UUID()).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("drop-test-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        defer { pasteboard.releaseGlobally() }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("drop-parent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        let drop = try #require(SFTPIncomingDrop(providers: [], pasteboard: pasteboard))
        let urls = try await drop.materialize(into: try SFTPDropStaging(keepingFilesIn: parent)).urls
        #expect(urls.map(\.standardizedFileURL) == [file.standardizedFileURL])
    }
    #endif
}
