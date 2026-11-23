import Foundation

/// Where a document's indentation came from (`GlassEditorConfiguration.indentationSource`).
public enum IndentationSource: String, Sendable, Hashable, Codable {
    /// Settings ▸ Editor's: the document's lines had no indentation when it opened.
    case settings
    /// The document's own lines (`Indentation.detect`).
    case file
    /// Chosen for this document, from its status bar.
    case chosen
}

/// How a document indents: with tabs, or with so many spaces a level (2026-11-22).
///
/// `width` is both the spaces typed for one level and how wide a tab is drawn, as in every editor that has the
/// setting. A document's own lines decide it when they say anything (`detect(in:defaultWidth:)`); Settings ▸ Editor
/// decides it for a new document and one whose lines are not indented.
public struct Indentation: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case tabs
        case spaces
    }

    public var kind: Kind
    /// Columns one level takes. 1 to 16.
    public var width: Int {
        didSet { width = Self.clampedWidth(width) }
    }

    public init(kind: Kind, width: Int) {
        self.kind = kind
        self.width = Self.clampedWidth(width)
    }

    /// Four spaces: Swift's, Python's and most code's.
    public static let standard = Indentation(kind: .spaces, width: 4)

    /// The widths offered in menus.
    public static let offeredWidths = [2, 3, 4, 8]

    /// One level, as typed.
    public var unit: String {
        kind == .tabs ? "\t" : String(repeating: " ", count: width)
    }

    /// "Spaces: 4" or "Tab Width: 4", as VS Code's status bar says it.
    public var statusName: String {
        kind == .tabs ? "Tab Width: \(width)" : "Spaces: \(width)"
    }

    private static func clampedWidth(_ width: Int) -> Int { min(max(width, 1), 16) }

    /// `self` under Settings ▸ Editor's `settings`, as `source` allows: all of it when the document has none of its own;
    /// a file's tabs drawn at the settings' width, since a tab's width is a reader's choice and no file says it; a
    /// file's spaces, and anything chosen for the document, as they are.
    public func following(_ settings: Indentation, from source: IndentationSource) -> Indentation {
        switch source {
        case .settings: return settings
        case .file where kind == .tabs: return Indentation(kind: .tabs, width: settings.width)
        case .file, .chosen: return self
        }
    }

    // MARK: Detection

    /// How the first lines of `text` are indented, or nil when none are.
    ///
    /// Lines led by a tab against lines led by two or more spaces decides tabs or spaces (one space leads a block
    /// comment's `*` too often to count). For spaces, the step most often seen from one line to a deeper next line
    /// (2, 3, 4 or 8) is the width; a tie goes to 4, then 2. Blank lines say nothing. Reads at most `lineLimit` lines,
    /// byte by byte, so a large file costs no more than its head.
    public static func detect(in text: String, defaultWidth: Int, lineLimit: Int = 2000) -> Indentation? {
        var tabLines = 0
        var spaceLines = 0
        var steps: [Int: Int] = [:]
        var previousSpaces: Int?

        var atLineStart = true
        var leadSpaces = 0
        var leadHasTab = false
        var leadStartsWithTab = false
        var leadLength = 0
        var lines = 0

        func endLine(blank: Bool) {
            defer {
                atLineStart = true; leadSpaces = 0; leadHasTab = false; leadStartsWithTab = false; leadLength = 0
            }
            guard !blank else { return }
            if leadStartsWithTab { tabLines += 1 } else if leadSpaces >= 2 { spaceLines += 1 }
            if leadHasTab {
                previousSpaces = nil
            } else {
                if let previous = previousSpaces, leadSpaces > previous, leadSpaces - previous <= 8 {
                    steps[leadSpaces - previous, default: 0] += 1
                }
                previousSpaces = leadSpaces
            }
        }

        var sawContent = false
        for byte in text.utf8 {
            if byte == 0x0A || byte == 0x0D {
                endLine(blank: !sawContent)
                sawContent = false
                lines += 1
                if lines >= lineLimit { break }
                continue
            }
            if atLineStart {
                if byte == 0x20 {
                    if leadLength == 0 { leadStartsWithTab = false }
                    leadSpaces += 1; leadLength += 1
                    continue
                }
                if byte == 0x09 {
                    if leadLength == 0 { leadStartsWithTab = true }
                    leadHasTab = true; leadLength += 1
                    continue
                }
                atLineStart = false
            }
            sawContent = true
        }
        if lines < lineLimit { endLine(blank: !sawContent) }

        guard tabLines > 0 || spaceLines > 0 else { return nil }
        if tabLines > spaceLines { return Indentation(kind: .tabs, width: defaultWidth) }
        let preference = [4, 2, 8, 3]
        let width = preference.max { a, b in
            let countA = steps[a, default: 0], countB = steps[b, default: 0]
            if countA != countB { return countA < countB }
            // Equal counts: the earlier in `preference` wins, so it must compare as the larger.
            return preference.firstIndex(of: a)! > preference.firstIndex(of: b)!
        }!
        return Indentation(kind: .spaces, width: steps[width, default: 0] > 0 ? width : defaultWidth)
    }
}
