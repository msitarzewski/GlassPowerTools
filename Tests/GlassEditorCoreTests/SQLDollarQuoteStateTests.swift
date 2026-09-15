//
//  SQLDollarQuoteStateTests.swift
//  Glass Power Tools — GlassEditorCoreTests
//
//  Pen finding M-5, which the existing scanner pen test does **not** reach.
//
//  Upstream's SQL scanner frees and nils `start_tag` inside `serialize()`. Serialization is meant to
//  snapshot state, not consume it, so after tree-sitter snapshots mid-parse the scanner no longer
//  knows which `$tag$` opened the string it is inside. `deserialize()` then overwrites the pointer
//  without freeing it and without checking the allocation.
//
//  None of that is a memory error on any ordinary path, which is why
//  `ScannerOverflowPenTests.sqlDollarQuotedReparse` passes with the bug present — even under
//  AddressSanitizer, verified 2026-09-15. What it is, is **state loss**: an incremental reparse of a
//  document with a dollar-quoted string can disagree with a full parse of the same text.
//
//  That is what this asserts, using the equivalence the grammar tests already rely on: whatever the
//  incremental path produces must equal a full reparse, for every edit.
//

import Testing
import Foundation
@testable import GlassEditorCore

@MainActor
@Suite("SQL dollar-quoted state survives serialization (M-5)")
struct SQLDollarQuoteStateTests {

    /// A function body in `$tag$…$tag$`, plus an anonymous `$$…$$`, so the scanner is carrying a
    /// tag across the edits below rather than starting fresh each time.
    private let document = """
    CREATE FUNCTION f() RETURNS text AS $tag$
      SELECT 'a body with $ signs and ; semicolons';
      SELECT 2;
    $tag$ LANGUAGE sql;
    SELECT $$anonymous dollar quote$$;
    """

    private func applying(_ edit: TextEdit, to source: String) -> String {
        var units = Array(source.utf16)
        units.replaceSubrange(edit.replacementRange, with: Array(edit.text.utf16))
        return String(decoding: units, as: UTF16.self)
    }

    @Test("An edit inside a dollar-quoted body reparses to the same highlights as a full parse")
    func editingInsideTheBodyKeepsTheTag() throws {
        let registry = GrammarRegistry()
        let incremental = try DocumentParser(language: .sql, registry: registry)
        var source = document
        incremental.parseFull(source)

        // Walk an edit through the body, one character at a time. Each `apply` forces tree-sitter
        // to snapshot and restore external-scanner state across the dollar-quoted region.
        let insideBody = try #require(source.range(of: "SELECT 2;"))
        var offset = source.utf16.distance(from: source.utf16.startIndex,
                                           to: insideBody.lowerBound.samePosition(in: source.utf16)!)

        for step in 0..<12 {
            let edit = TextEdit.insert("x", at: offset)
            source = applying(edit, to: source)
            incremental.apply(edit, newSnapshot: source)
            offset += 1

            // Without this the equivalence proves nothing: it would also hold if `apply` quietly
            // fell back to a full reparse, which is precisely the path that would never exercise
            // the scanner's serialize/deserialize at all.
            #expect(incremental.lastParseWasIncremental, "step \(step) was not an incremental parse")

            let reference = try DocumentParser(language: .sql, registry: registry)
            reference.parseFull(source)
            #expect(incremental.highlights == reference.highlights,
                    "incremental and full highlights diverged at step \(step)")
        }
    }

    @Test("Editing before the opening tag does not lose the body's string classification")
    func editingBeforeTheTagKeepsTheBodyAString() throws {
        let registry = GrammarRegistry()
        let incremental = try DocumentParser(language: .sql, registry: registry)
        var source = document
        incremental.parseFull(source)

        for step in 0..<12 {
            let edit = TextEdit.insert("-", at: 0)
            source = applying(edit, to: source)
            incremental.apply(edit, newSnapshot: source)

            // Without this the equivalence proves nothing: it would also hold if `apply` quietly
            // fell back to a full reparse, which is precisely the path that would never exercise
            // the scanner's serialize/deserialize at all.
            #expect(incremental.lastParseWasIncremental, "step \(step) was not an incremental parse")

            let reference = try DocumentParser(language: .sql, registry: registry)
            reference.parseFull(source)
            #expect(incremental.highlights == reference.highlights,
                    "incremental and full highlights diverged at step \(step)")
        }
    }
}
