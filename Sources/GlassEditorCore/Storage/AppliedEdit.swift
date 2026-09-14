import Foundation

/// The record of an edit after the buffer applied it: the edit itself plus the
/// text it replaced. This is everything undo needs — the inverse of an applied
/// edit is fully determined by it.
public struct AppliedEdit: Sendable, Hashable {
    public var edit: TextEdit
    /// The text that occupied `edit.replacementRange` before the edit.
    public var replacedText: String

    public init(edit: TextEdit, replacedText: String) {
        self.edit = edit
        self.replacedText = replacedText
    }

    /// The edit that exactly reverses this one, valid against the post-edit
    /// document state.
    public var inverse: TextEdit {
        let start = edit.replacementRange.lowerBound
        return TextEdit(
            replacementRange: start..<(start + edit.insertedLength),
            text: replacedText
        )
    }
}
