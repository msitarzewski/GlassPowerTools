//
//  GlassTextChecking.swift
//  Glass Power Tools — GlassEditorUI
//
//  Spelling and substitutions in the editor, switched as TextEdit switches them (the owner, 2026-11-03: "all of the
//  expected text editor functions ... like say TextEdit"): Edit ▸ Spelling and Grammar ▸ Check Spelling While Typing,
//  Edit ▸ Substitutions ▸ Smart Quotes, and the rest. Like TextEdit's they are the app's, not one document's, and
//  remembered. They start off: this is a code editor, where a straight quote is syntax and a red underline under
//  every identifier is noise (`GlassTextView` and `GlassTextViewIOS` have always set them off). Turned on, every
//  editor text view follows at once.
//

import Foundation
import Observation

@MainActor
@Observable
public final class GlassTextChecking {
    public static let shared = GlassTextChecking()

    public var checksSpellingWhileTyping: Bool { didSet { save(checksSpellingWhileTyping, Key.spelling) } }
    public var checksGrammarWithSpelling: Bool { didSet { save(checksGrammarWithSpelling, Key.grammar) } }
    public var correctsSpellingAutomatically: Bool { didSet { save(correctsSpellingAutomatically, Key.correction) } }
    public var smartCopyPaste: Bool { didSet { save(smartCopyPaste, Key.smartCopyPaste) } }
    public var smartQuotes: Bool { didSet { save(smartQuotes, Key.quotes) } }
    public var smartDashes: Bool { didSet { save(smartDashes, Key.dashes) } }
    public var smartLinks: Bool { didSet { save(smartLinks, Key.links) } }
    public var dataDetectors: Bool { didSet { save(dataDetectors, Key.dataDetectors) } }
    public var textReplacement: Bool { didSet { save(textReplacement, Key.textReplacement) } }

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let spelling = "editor.checksSpellingWhileTyping"
        static let grammar = "editor.checksGrammarWithSpelling"
        static let correction = "editor.correctsSpellingAutomatically"
        static let smartCopyPaste = "editor.smartCopyPaste"
        static let quotes = "editor.smartQuotes"
        static let dashes = "editor.smartDashes"
        static let links = "editor.smartLinks"
        static let dataDetectors = "editor.dataDetectors"
        static let textReplacement = "editor.textReplacement"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        checksSpellingWhileTyping = defaults.bool(forKey: Key.spelling)
        checksGrammarWithSpelling = defaults.bool(forKey: Key.grammar)
        correctsSpellingAutomatically = defaults.bool(forKey: Key.correction)
        smartCopyPaste = defaults.bool(forKey: Key.smartCopyPaste)
        smartQuotes = defaults.bool(forKey: Key.quotes)
        smartDashes = defaults.bool(forKey: Key.dashes)
        smartLinks = defaults.bool(forKey: Key.links)
        dataDetectors = defaults.bool(forKey: Key.dataDetectors)
        textReplacement = defaults.bool(forKey: Key.textReplacement)
    }

    private func save(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }

    /// Every switch read, so a caller observing this follows any of them.
    var all: [Bool] {
        [checksSpellingWhileTyping, checksGrammarWithSpelling, correctsSpellingAutomatically, smartCopyPaste,
         smartQuotes, smartDashes, smartLinks, dataDetectors, textReplacement]
    }
}

#if canImport(AppKit) && os(macOS)
import AppKit

extension GlassTextChecking {
    /// Sets a text view's checking to these switches.
    func apply(to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = checksSpellingWhileTyping
        textView.isGrammarCheckingEnabled = checksGrammarWithSpelling
        textView.isAutomaticSpellingCorrectionEnabled = correctsSpellingAutomatically
        textView.smartInsertDeleteEnabled = smartCopyPaste
        textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = smartDashes
        textView.isAutomaticLinkDetectionEnabled = smartLinks
        textView.isAutomaticDataDetectionEnabled = dataDetectors
        textView.isAutomaticTextReplacementEnabled = textReplacement
    }
}
#elseif canImport(UIKit)
import UIKit

extension GlassTextChecking {
    /// Sets a text view's checking to these switches, as far as UIKit has them: spelling, autocorrection, smart quotes,
    /// dashes and insert/delete. A change shows after the keyboard next appears, as UIKit applies its traits then.
    func apply(to textView: UITextView) {
        textView.spellCheckingType = checksSpellingWhileTyping ? .yes : .no
        textView.autocorrectionType = correctsSpellingAutomatically ? .yes : .no
        textView.smartQuotesType = smartQuotes ? .yes : .no
        textView.smartDashesType = smartDashes ? .yes : .no
        textView.smartInsertDeleteType = smartCopyPaste ? .yes : .no
        textView.dataDetectorTypes = dataDetectors || smartLinks ? (smartLinks ? [.link] : []) : []
    }
}
#endif
