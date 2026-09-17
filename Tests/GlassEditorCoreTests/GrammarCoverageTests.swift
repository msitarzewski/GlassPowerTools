//
//  GrammarCoverageTests.swift
//  Glass Power Tools — GlassEditorCoreTests
//
//  Every language the editor offers must actually parse and actually colour.
//
//  This is the failure mode worth a test: a grammar whose highlight query does not compile against
//  it does **not** crash and does not report anything — `GrammarRegistry` throws,
//  `startBuiltInHighlighting` returns false, and the editor quietly shows grey text. A user would
//  report it as "highlighting doesn't work for Go", months later, if ever.
//
//  Five languages were added on 2026-09-16 (Python, JavaScript, Go, Rust, C) by vendoring each
//  grammar's own `queries/highlights.scm` from its pinned checkout. Upstream query files are written
//  for nvim and move between releases, and a pin is a commit rather than a promise. So: load every
//  grammar and compile every query here, and prove each one *colours real code* in
//  `GrammarModuleTests`, which already owns that contract for the original six.
//

import Foundation
import Testing
@testable import GlassEditorCore

@MainActor
@Suite("Grammar coverage")
struct GrammarCoverageTests {

    /// Every `LanguageID` except plaintext has a grammar and a query that compiles against it.
    @Test(arguments: LanguageID.allCases.filter { $0 != .plaintext })
    func everyLanguageLoadsAGrammarAndACompiledQuery(_ language: LanguageID) throws {
        let registry = GrammarRegistry()
        let loaded = try registry.grammar(for: language)
        #expect(loaded.isParsable, "\(language.rawValue) has no grammar")
        #expect(loaded.highlightQuery != nil, "\(language.rawValue) has no compiled highlight query")
    }

    /// plaintext stays what it is: a real language with no grammar, and not an error.
    @Test func plaintextIsDeliberatelyGrammarless() throws {
        let loaded = try GrammarRegistry().grammar(for: .plaintext)
        #expect(!loaded.isParsable)
        #expect(loaded.highlightQuery == nil)
    }

    /// The extensions that decide which grammar a file opens under. Getting `.go` or `.rs` wrong
    /// means a correct grammar that is never chosen.
    @Test func fileExtensionsMapToTheLanguagesTheyName() {
        #expect(LanguageID.forFileExtension("py") == .python)
        #expect(LanguageID.forFileExtension("PY") == .python)
        #expect(LanguageID.forFileExtension("go") == .go)
        #expect(LanguageID.forFileExtension("rs") == .rust)
        #expect(LanguageID.forFileExtension("c") == .c)
        #expect(LanguageID.forFileExtension("h") == .c)
        #expect(LanguageID.forFileExtension("js") == .javascript)
        #expect(LanguageID.forFileExtension("ts") == .javascript)
        #expect(LanguageID.forFileExtension("tsx") == .javascript)
        // An extension nobody claimed is plaintext, never a guess.
        #expect(LanguageID.forFileExtension("xyz") == .plaintext)
        #expect(LanguageID.forFileExtension("") == .plaintext)
    }

}
