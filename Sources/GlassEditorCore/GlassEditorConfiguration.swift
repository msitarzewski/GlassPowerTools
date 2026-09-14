import Foundation

/// Editor behavior configuration. A value type passed to every public entry
/// point — no singletons, no shared instances (projectRules.md, API Design).
public struct GlassEditorConfiguration: Sendable, Hashable {
    // Typography
    public var fontName: String?
    /// Point size before any `SurfaceCondition` weight compensation.
    public var fontSize: Double

    // Behavior
    public var showsLineNumbers: Bool
    public var wrapsLines: Bool
    public var isEditable: Bool
    /// Milliseconds to debounce rehighlighting after an edit. Matches the
    /// proven AppKit behavior in glassdb (75ms — INTEGRATION.md A3).
    public var highlightDebounceMilliseconds: Int

    // Limits
    /// Hard ceiling on the byte size a document may have to be opened at all:
    /// `DocumentLoader` throws `EditorError.fileTooLarge` above it, and refuses
    /// non-regular files outright. Separate from — and larger than — the
    /// highlighting-degradation threshold (`DocumentParser`'s
    /// `highlightingCodeUnitCeiling`), above which a file still opens but is
    /// shown as plaintext. The value is deliberately conservative until
    /// large-file behavior is characterized and published (M5).
    public var largeFileByteCeiling: UInt64

    // Contrast
    /// The floor the engine will never silently render below
    /// (projectRules.md, Theming). WCAG AA for normal text is 4.5.
    public var minimumContrastRatio: Double

    public init(
        fontName: String? = nil,
        fontSize: Double = 13,
        showsLineNumbers: Bool = true,
        wrapsLines: Bool = false,
        isEditable: Bool = true,
        highlightDebounceMilliseconds: Int = 75,
        largeFileByteCeiling: UInt64 = 8 * 1024 * 1024,
        minimumContrastRatio: Double = 4.5
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.showsLineNumbers = showsLineNumbers
        self.wrapsLines = wrapsLines
        self.isEditable = isEditable
        self.highlightDebounceMilliseconds = highlightDebounceMilliseconds
        self.largeFileByteCeiling = largeFileByteCeiling
        self.minimumContrastRatio = minimumContrastRatio
    }
}
