//
//  GlassEditorPreferences.swift
//  Glass Power Tools — GlassEditor
//
//  What is true of the editor rather than of one window.
//
//  Text size, line numbers, wrapping and the recents list belong to the app: setting the text
//  larger in one window and finding the other unchanged would be a bug, and a file opened anywhere
//  is recent everywhere. Documents, projects, the selection and the find state are the opposite —
//  they are what a *window* is — and they live on `GlassEditorWorkspace`, one per window.
//
//  A window can keep its own text size, line numbers and wrapping over these (W23,
//  `GlassEditorWindowSettings`), deliberately, from its This Window; one that keeps none follows
//  these, and changes with them.
//
//  The split exists because a second editor window used to be a second view of the same documents.
//

import Foundation
import GlassLayers
import Observation
import GlassEditorCore

@MainActor @Observable
public final class GlassEditorPreferences {
    public var showsLineNumbers: Bool { didSet { persist() } }
    public var wrapsLines: Bool { didSet { persist() } }
    public var fontSize: Double { didSet { persist() } }
    /// Light or dark, following the system. **Not** persisted: it is the system's answer, not a
    /// preference of this app's, and a stored copy would be wrong the moment the Mac switched at
    /// sunset.
    public var prefersDarkTheme = true

    /// Files opened before, newest first. Survives launches, shared by every window.
    public private(set) var recents: [URL] = []

    /// Bounded because an unbounded list is a slow leak nobody notices until it is a thousand
    /// entries long — the defect this project already found in its preferences once.
    static let recentsLimit = 20
    static let recentsDefaultsKey = "com.glasspowertools.editor.recents"
    static let appearanceDefaultsKey = "com.glasspowertools.editor.appearance"

    /// The bounds text size moves between. Wider than the terminal's because a file can be read at
    /// arm's length in a headset and edited at a desk.
    public static let fontSizeRange: ClosedRange<Double> = 8...32

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.appearanceDefaultsKey) ?? [:]
        let fallback = GlassEditorConfiguration()
        showsLineNumbers = stored["showsLineNumbers"] as? Bool ?? fallback.showsLineNumbers
        wrapsLines = stored["wrapsLines"] as? Bool ?? fallback.wrapsLines
        fontSize = stored["fontSize"] as? Double ?? fallback.fontSize
        recents = Self.loadRecents(from: defaults)
    }

    public func increaseFontSize() { fontSize = min(fontSize + 1, Self.fontSizeRange.upperBound) }
    public func decreaseFontSize() { fontSize = max(fontSize - 1, Self.fontSizeRange.lowerBound) }
    public func resetFontSize() { fontSize = GlassEditorConfiguration().fontSize }

    /// The configuration a document is opened with, and re-applied to every open document when one
    /// of these changes.
    public func configuration(basedOn existing: GlassEditorConfiguration) -> GlassEditorConfiguration {
        var configuration = existing
        configuration.showsLineNumbers = showsLineNumbers
        configuration.wrapsLines = wrapsLines
        configuration.fontSize = fontSize
        return configuration
    }

    public var theme: EditorTheme { prefersDarkTheme ? .glassDark : .glassLight }

    // MARK: Recents

    func noteRecent(_ url: URL) {
        let standardized = url.standardizedFileURL
        recents.removeAll { $0.standardizedFileURL == standardized }
        recents.insert(standardized, at: 0)
        if recents.count > Self.recentsLimit { recents.removeLast(recents.count - Self.recentsLimit) }
        defaults.set(recents.map(\.absoluteString), forKey: Self.recentsDefaultsKey)
    }

    public func clearRecents() {
        recents = []
        defaults.removeObject(forKey: Self.recentsDefaultsKey)
    }

    private func persist() {
        defaults.set(["showsLineNumbers": showsLineNumbers,
                      "wrapsLines": wrapsLines,
                      "fontSize": fontSize], forKey: Self.appearanceDefaultsKey)
    }

    private static func loadRecents(from defaults: UserDefaults) -> [URL] {
        let stored = defaults.stringArray(forKey: recentsDefaultsKey) ?? []
        // A file since deleted or moved is dropped on read rather than offered and then failing —
        // a recents list that lies is worse than a short one.
        return stored.compactMap(URL.init(string:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
