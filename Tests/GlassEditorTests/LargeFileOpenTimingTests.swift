import Testing
import Foundation
import GlassEditorCore
import GlassEditorUI
@testable import GlassEditor

/// Where the time goes opening a huge one-line file, without a window (2026-09-23). Runs only when
/// `GPT_LARGE_FILE` names a file; prints each stage's time.
@Suite("Opening a very large one-line file")
@MainActor
struct LargeFileOpenTimingTests {
    /// A measurement, printed, not a check: run with GPT_LARGE_FILE naming the file.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPT_LARGE_FILE"] != nil, "a timing probe: set GPT_LARGE_FILE"))
    func stages() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["GPT_LARGE_FILE"])
        let clock = ContinuousClock()
        var t = clock.now
        func lap(_ name: String) { let now = clock.now; print("STAGE \(name): \(now - t)"); t = now }
        let data = try Data(contentsOf: URL(filePath: path)); lap("read \(data.count) bytes")
        _ = GlassEditorFileKind.classify(name: path, prefix: data.prefix(8192)); lap("classify")
        let decoded = try EncodingDetector.decode(data); lap("decode")
        _ = LineEndingDetector.detect(in: decoded.content); lap("line endings")
        let snapshot = DocumentSnapshot(content: decoded.content, encoding: decoded.encoding,
                                        lineEndings: .lf, origin: .local(URL(filePath: path)))
        let plain = GlassEditorModel(snapshot: snapshot, language: .plaintext, builtInHighlighting: false); lap("model, no highlighting")
        _ = plain.lineCount
        let highlighted = GlassEditorModel(snapshot: snapshot); lap("model with highlighting (\(highlighted.language))")
        _ = LanguageID.forContent(decoded.content); lap("language sniff")
        let document = try await GlassEditorDocument.open(path: path, through: GlassEditorLocalFileAccess()); lap("GlassEditorDocument.open total")
        _ = document
    }
}
