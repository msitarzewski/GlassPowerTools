import Testing
import Foundation
@testable import GlassEditorCore

/// Regression tests for the pen-sec findings fixed in code:
/// M-1 (setuid/setgid strip), M-3 (undo byte budget), M-4 (non-regular-file
/// rejection), M-7 (highlighting degradation above a ceiling). M-6 (bounded
/// `wordPrefix`) lives in `GlassEditorUITests` where the model is reachable.
@Suite("Pen fixes")
struct PenFixTests {

    // MARK: M-1 — save strips setuid/setgid

    @Test("saving a setgid file clears the setgid bit")
    func saveClearsSetgid() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("penfix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("script.sh")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        // setgid + rwxr-xr-x
        try FileManager.default.setAttributes([.posixPermissions: 0o2755], ofItemAtPath: file.path)
        // Set, or there is nothing to clear: chmod drops setgid quietly for a group the user isn't in.
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        try #require(before.uint16Value & 0o2000 != 0, "setgid didn't take, so the save can't show it goes")

        try AtomicSaver.save("edited", encoding: .utf8(hadBOM: false), to: file)

        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        #expect(mode.uint16Value & 0o2000 == 0, "setgid survived the save: \(String(mode.uint16Value, radix: 8))")
        #expect(mode.uint16Value & 0o0755 == 0o0755, "ordinary permission bits were not preserved")
        #expect(try String(contentsOf: file, encoding: .utf8) == "edited")
    }

    // MARK: M-4 — non-regular files are refused before any read

    @Test("loading a directory throws rather than reading unbounded")
    func loadRejectsNonRegularFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("penfix-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: EditorError.self) {
            _ = try DocumentLoader.load(from: dir, configuration: GlassEditorConfiguration())
        }
    }

    // MARK: M-3 — undo retains bounded memory

    @Test("undo byte budget evicts oldest large units but keeps the newest")
    func undoByteBudget() {
        // Budget of 100 code units; each replace-all retains ~200 (old + new).
        let coordinator = UndoCoordinator(
            clock: ContinuousUndoClock(),
            maximumUnitCount: 1000,
            maximumRetainedCodeUnits: 100
        )
        let big = String(repeating: "x", count: 80)
        for i in 0..<10 {
            let applied = AppliedEdit(
                edit: TextEdit(replacementRange: 0..<big.utf16.count, text: big),
                replacedText: "prev\(i)"
            )
            coordinator.record(applied, intent: .replaceAll)
        }
        // Each unit ~ 80 + ~5 code units > budget/… so only the newest survives.
        #expect(coordinator.undoDepth == 1, "byte budget did not evict; depth \(coordinator.undoDepth)")
        #expect(coordinator.canUndo, "the newest unit must always remain undoable")
    }

    @Test("a single oversized unit is still retained")
    func undoKeepsOversizedNewest() {
        let coordinator = UndoCoordinator(maximumRetainedCodeUnits: 10)
        let huge = String(repeating: "y", count: 1000)
        coordinator.record(
            AppliedEdit(edit: TextEdit.insert(huge, at: 0), replacedText: ""),
            intent: .paste
        )
        #expect(coordinator.undoDepth == 1)
        #expect(coordinator.canUndo)
    }
}

/// M-7 — highlighting degrades to plaintext above the ceiling.
@MainActor
@Suite("Pen fix: highlighting degradation (M-7)")
struct HighlightDegradationTests {
    @Test("a document above the highlighting ceiling renders as one plain run")
    func degradesAboveCeiling() throws {
        let parser = try DocumentParser(
            language: .sql,
            registry: GrammarRegistry(),
            highlightingCodeUnitCeiling: 50
        )
        let big = "SELECT " + String(repeating: "a", count: 200) + ";"
        parser.parseFull(big)
        #expect(parser.highlightingDegraded, "expected degradation above the ceiling")
        #expect(parser.highlights.count == 1, "degraded highlighting must be a single cover run")
        #expect(parser.highlights.first?.role == .plain)
        #expect(parser.highlights.first?.range == 0..<big.utf16.count)
    }

    @Test("a small document still highlights normally")
    func smallDocumentStillHighlights() throws {
        let parser = try DocumentParser(
            language: .sql,
            registry: GrammarRegistry(),
            highlightingCodeUnitCeiling: 50
        )
        parser.parseFull("SELECT 1;")
        #expect(!parser.highlightingDegraded)
        #expect(parser.highlights.contains { $0.role == .keyword })
    }
}
