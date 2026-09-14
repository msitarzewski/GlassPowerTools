import Foundation

/// The unified error type for all public GlassEditorCore operations
/// (projectRules.md, Naming). Prefer `throws` of this over optional returns.
public enum EditorError: Error, Sendable, Hashable {
    // Storage
    case rangeOutOfBounds(requested: Range<Int>, documentLength: Int)
    case overlappingBatchEdits
    /// A UTF-16 offset landed between the two halves of a surrogate pair. A
    /// well-behaved text system never produces one; repairing it silently would
    /// hide the bug that did.
    case splitsSurrogatePair(offset: Int)

    // Document / encoding
    case unreadableData(reason: String)
    case undecodableContent(triedEncoding: String)
    case fileTooLarge(bytes: UInt64, ceiling: UInt64)

    // Save
    case saveFailed(reason: String)
    case atomicRenameFailed(reason: String)
    case notSaveable(origin: String)

    // Remote / conflict
    case unresolvedConflict(state: ConflictState)

    // Grammar
    case grammarUnavailable(language: LanguageID)
    case queryCompilationFailed(language: LanguageID, reason: String)

    // Find
    case invalidPattern(reason: String)
}
