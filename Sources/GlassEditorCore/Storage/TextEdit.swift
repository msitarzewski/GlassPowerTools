import Foundation

/// The single mutation type. Every change to a document — a keystroke, a paste,
/// a replace-all, a remote reload — flows through `TextEdit`. Views never edit
/// storage directly (projectRules.md, Data Safety).
///
/// `replacementRange` is in UTF-16 code units, consistent with `HighlightRun`.
/// An insertion is an empty range; a deletion is an empty `text`.
public struct TextEdit: Sendable, Hashable {
    public var replacementRange: Range<Int>
    public var text: String

    public init(replacementRange: Range<Int>, text: String) {
        self.replacementRange = replacementRange
        self.text = text
    }

    public static func insert(_ text: String, at offset: Int) -> TextEdit {
        TextEdit(replacementRange: offset..<offset, text: text)
    }

    public static func delete(_ range: Range<Int>) -> TextEdit {
        TextEdit(replacementRange: range, text: "")
    }

    /// UTF-16 length of the inserted text.
    public var insertedLength: Int { text.utf16.count }

    /// Signed change in document length, in UTF-16 code units.
    public var lengthDelta: Int { insertedLength - replacementRange.count }
}

/// Several edits applied as one undoable unit — a replace-all, a multi-cursor
/// commit, a formatting pass. Ranges are interpreted against the document state
/// *before* the batch; `TextStorageBuffer` applies them back-to-front so earlier
/// ranges stay valid.
public struct TextEditBatch: Sendable, Hashable {
    public var edits: [TextEdit]

    public init(edits: [TextEdit]) {
        self.edits = edits
    }
}
