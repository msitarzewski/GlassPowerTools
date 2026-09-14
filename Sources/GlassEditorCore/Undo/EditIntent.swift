import Foundation

/// Why a change happened. The engine tags every mutation with an intent; the
/// undo coordinator uses it to decide where one undoable unit ends and the next
/// begins. Intent is editorial, not structural — two identical `TextEdit`s can
/// carry different intents and coalesce differently.
public enum EditIntent: Sendable, Hashable {
    /// A character (or composed sequence) the user typed.
    case typing
    /// Backspace — deletion moving leftward from the caret.
    case deleteBackward
    /// Forward delete — deletion consuming text ahead of the caret.
    case deleteForward
    /// Pasteboard insertion. Always its own unit.
    case paste
    /// Drag-and-drop insertion.
    case drop
    /// A find/replace-all pass. Always one unit, however many edits it contains.
    case replaceAll
    /// Indent, outdent, or reindent applied to a selection.
    case indentation
    /// A completion accepted from a provider. Always its own unit.
    case completion
    /// A programmatic mutation with no direct user gesture behind it.
    case programmatic
    /// The document was reloaded from its remote origin. A barrier.
    case remoteReload

    /// Barriers are recorded and undoable — undoing a reload restores the
    /// pre-reload buffer, which is a data-safety guarantee, not a convenience —
    /// but nothing coalesces across them in either direction.
    public var isBarrier: Bool {
        self == .remoteReload
    }

    /// Intents that are always exactly one undo unit, never merged with a
    /// neighbour even when adjacent and same-intent.
    public var formsOwnUnit: Bool {
        switch self {
        case .typing, .deleteBackward:
            return false
        case .deleteForward, .paste, .drop, .replaceAll,
             .indentation, .completion, .programmatic, .remoteReload:
            return true
        }
    }
}
