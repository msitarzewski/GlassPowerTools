import Foundation

// Provider protocols: semantic knowledge lives in the consumers, semantic
// roles live here (D-003). glassdb supplies schema-aware SQL completion and
// statement boundaries; glas.sh supplies none of these and the editor still
// works. All providers are Sendable with async requirements — consumers may
// hit a network or a database (projectRules.md, API Design).

// MARK: - Completion

public struct CompletionRequest: Sendable, Hashable {
    /// UTF-16 offset of the cursor.
    public var position: Int
    /// The word fragment being completed (may be empty).
    public var prefix: String
    /// Language of the document.
    public var language: LanguageID

    public init(position: Int, prefix: String, language: LanguageID) {
        self.position = position
        self.prefix = prefix
        self.language = language
    }
}

public struct CompletionItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case keyword, table, column, function, value, snippet, other
    }

    public var id: String
    /// What the list displays.
    public var label: String
    /// What insertion actually types.
    public var insertText: String
    public var kind: Kind
    /// Optional detail line (e.g. a column's type).
    public var detail: String?

    public init(id: String, label: String, insertText: String, kind: Kind, detail: String? = nil) {
        self.id = id
        self.label = label
        self.insertText = insertText
        self.kind = kind
        self.detail = detail
    }
}

public protocol CompletionProvider: Sendable {
    /// Return completions for the request, reading document text as needed via
    /// `snapshot`. Implementations may be slow (schema queries); the engine
    /// debounces and cancels stale requests.
    func completions(
        for request: CompletionRequest,
        in snapshot: String
    ) async throws -> [CompletionItem]
}

// MARK: - Diagnostics

public struct EditorDiagnostic: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Hashable, Codable {
        case error, warning, info, hint
    }

    public var id: String
    /// UTF-16 range the diagnostic covers.
    public var range: Range<Int>
    public var severity: Severity
    public var message: String

    public init(id: String, range: Range<Int>, severity: Severity, message: String) {
        self.id = id
        self.range = range
        self.severity = severity
        self.message = message
    }
}

public protocol DiagnosticsProvider: Sendable {
    func diagnostics(for snapshot: String, language: LanguageID) async throws -> [EditorDiagnostic]
}

// MARK: - Statement boundaries

/// A top-level statement span, e.g. one SQL statement in a multi-statement
/// buffer. glassdb uses these for execute-current-statement and the safety
/// badge. The *classification* of a statement stays in glassdb
/// (`safetyClassification` never moves — INTEGRATION.md A2).
public struct StatementSpan: Sendable, Hashable, Identifiable {
    public var id: Int
    /// UTF-16 range of the statement, excluding trailing terminator whitespace.
    public var range: Range<Int>

    public init(id: Int, range: Range<Int>) {
        self.id = id
        self.range = range
    }
}

public protocol StatementBoundaryProvider: Sendable {
    func statements(in snapshot: String, language: LanguageID) async throws -> [StatementSpan]
}
