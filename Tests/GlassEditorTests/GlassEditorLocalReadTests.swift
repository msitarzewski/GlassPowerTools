import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditor

/// What the editor reads from this device's disk (2026-10-12): a regular file only, at most
/// `byteCeiling`, off the main actor. The editor kit's pen-test finding M-4, which the newer local
/// path had bypassed: any file was read whole on the main actor, and a pipe or a device was refused
/// only by Foundation, as a permission problem. Opened without blocking, so a pipe cannot hold the
/// read even where Foundation would not refuse it.
@Suite("The editor reads only files, and only so much")
struct GlassEditorLocalReadTests {
    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glass-local-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file of `bytes` that occupies no disk: sparse, all zeros.
    private func sparse(_ name: String, bytes: UInt64, in folder: URL, header: Data = Data()) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
        return url
    }

    /// What a read came to, in a form that crosses tasks.
    enum Outcome: Sendable, Equatable {
        case data(Data)
        case failed(GlassEditorReadRefusal?, CocoaError.Code?, String)
    }

    private actor Box {
        var outcome: Outcome?
        var started: ContinuousClock.Instant?
        func set(_ value: Outcome) { outcome = value }
        func start() { started = .now }
    }

    /// Asks from the main actor, as the editor does, and gives up `seconds` after the read begins: a
    /// read that blocks fails the test rather than hanging the run. Timed from the start of the read,
    /// not from the request, and nothing after the start waits for the main actor: the editor's suites
    /// share it, and waiting behind them is not the read blocking (six more of them pushed these past
    /// a deadline counted from the request).
    private func read(_ path: String, within seconds: Double = 3) async -> Outcome? {
        let box = Box()
        Task { @MainActor in await Self.read(path, into: box) }
        // The main actor is given a generous while to reach the read at all.
        let queued = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < queued {
            if let outcome = await box.outcome { return outcome }
            if let started = await box.started, ContinuousClock.now > started + .seconds(seconds) { return nil }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    private nonisolated static func read(_ path: String, into box: Box) async {
        await box.start()
        let outcome: Outcome
        do {
            outcome = .data(try await GlassEditorLocalFileAccess().read(path))
        } catch {
            outcome = .failed(error as? GlassEditorReadRefusal, (error as? CocoaError)?.code, error.localizedDescription)
        }
        await box.set(outcome)
    }

    @Test("a named pipe is refused at once, and the message says what it is")
    func namedPipe() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pipe = folder.appendingPathComponent("events")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        // Releases a reader that did block: a writer arriving and leaving ends its read.
        defer {
            let writer = open(pipe.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
        }
        let outcome = try #require(await read(pipe.path), "the read blocked on a pipe with no writer")
        #expect(outcome == .failed(.notAFile(name: "events", what: "a named pipe"), nil, "it is a named pipe, not a file."))
    }

    @Test("a link to a device is refused; a link to a file reads as the file")
    func links() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let zero = folder.appendingPathComponent("zeros")
        try FileManager.default.createSymbolicLink(atPath: zero.path, withDestinationPath: "/dev/zero")
        let outcome = try #require(await read(zero.path))
        #expect(outcome == .failed(.notAFile(name: "zeros", what: "a device"), nil, "it is a device, not a file."))

        let real = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: real)
        let alias = folder.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        #expect(await read(alias.path) == .data(Data("hello".utf8)))
    }

    @Test("a file larger than the ceiling is refused before it is read; a missing file errs as before")
    func ceilingAndMissing() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let limit = UInt64(GlassEditorLocalFileAccess.byteCeiling)
        let big = try sparse("server.log", bytes: limit + 1, in: folder)
        guard case .failed(let refusal?, nil, _) = try #require(await read(big.path)) else {
            Issue.record("a file past the ceiling was read"); return
        }
        #expect(refusal == .tooLarge(name: "server.log", bytes: limit + 1, limit: limit))
        let atLimit = try sparse("edge.log", bytes: limit, in: folder)
        guard case .data(let data) = try #require(await read(atLimit.path)) else {
            Issue.record("a file at the ceiling was refused"); return
        }
        #expect(data.count == Int(limit))

        guard case .failed(nil, let code?, _) = try #require(await read(folder.appendingPathComponent("gone.txt").path)) else {
            Issue.record("a missing file did not err as Data(contentsOf:) does"); return
        }
        #expect(code == .fileReadNoSuchFile)
    }

    @Test("a large local video opens in its viewer from the disk; a large text file says why it will not open")
    @MainActor
    func largeMediaAndText() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = UInt64(GlassEditorLocalFileAccess.byteCeiling) + 4096
        let video = try sparse("talk.mp4", bytes: size, in: folder)
        let document = try await GlassEditorDocument.open(path: video.path, through: GlassEditorLocalFileAccess())
        let viewer = try #require(document.viewer, "a large video was read as text, or refused")
        #expect(viewer.kind == .video && viewer.byteCount == Int(size))

        // Text through the part the kind is told from; a large file of zeros is binary, and shown.
        let lines = String(repeating: "2026-10-12 request served\n", count: 400)
        let log = try sparse("huge.log", bytes: size, in: folder, header: Data(lines.utf8))
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "glass-local-read-\(UUID().uuidString)")!)
        #expect(await workspace.open(log) == nil)
        #expect(workspace.message?.hasPrefix("huge.log could not be opened: at ") == true, "\(workspace.message ?? "")")
        #expect(workspace.message?.hasSuffix("the editor opens. Open it in another app.") == true)
        #expect(workspace.pendingLargeOpen == nil, "a refusal is not a question")
    }
}
