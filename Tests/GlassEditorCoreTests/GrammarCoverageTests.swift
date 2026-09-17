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

    /// The two added 2026-09-17, and the files a developer on this platform actually opens.
    @Test func swiftAndXMLClaimTheExtensionsTheyShould() {
        #expect(LanguageID.forFileExtension("swift") == .swift)
        #expect(LanguageID.forFileExtension("xml") == .xml)
        #expect(LanguageID.forFileExtension("plist") == .xml)
        #expect(LanguageID.forFileExtension("entitlements") == .xml)
        #expect(LanguageID.forFileExtension("xcscheme") == .xml)
        #expect(LanguageID.forFileExtension("svg") == .xml)
    }

    /// A file whose name says nothing. `Makefile`, `deploy`, a plist with no extension — half a
    /// developer's tree — and the editor called all of it plain text.
    @Test func contentNamesTheLanguageWhenTheFileNameDoesNot() {
        #expect(LanguageID.forContent("#!/usr/bin/env python3\nprint(1)\n") == .python)
        #expect(LanguageID.forContent("#!/bin/bash\necho hi\n") == .bash)
        #expect(LanguageID.forContent("#!/usr/bin/env node\nconsole.log(1)\n") == .javascript)
        #expect(LanguageID.forContent("<?xml version=\"1.0\"?><plist/>") == .xml)
        #expect(LanguageID.forContent("{\"a\": 1}") == .json)

        // An interpreter with no grammar here is still a script, and the shell grammar reads it
        // better than nothing does.
        #expect(LanguageID.forContent("#!/usr/bin/env ruby\nputs 1\n") == .bash)
    }

    /// **Nothing conclusive means plaintext.** A wrong grammar colours worse than none, and the
    /// tempting guesses — a leading brace, a word that looks like a keyword — are exactly the ones
    /// that are wrong on somebody's file.
    @Test func ambiguousContentStaysPlaintext() {
        #expect(LanguageID.forContent("just some words\nand more of them") == .plaintext)
        // A brace that is not JSON: a Swift dictionary literal, a CSS rule, a Go struct.
        #expect(LanguageID.forContent("{ this is not json }") == .plaintext)
        #expect(LanguageID.forContent("") == .plaintext)
        // A `#` comment is not a shebang.
        #expect(LanguageID.forContent("# a heading\n\nsome prose") == .plaintext)
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
