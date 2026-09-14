import Foundation
import Observation
import GlassEditorCore

/// The document session a consumer holds, and the single source of truth both
/// backends render.
///
/// **Why the model owns the text and the view does not.** `HighlightedTextEditor`
/// kept the document in a SwiftUI `@Binding` and let each platform wrapper mutate
/// its own text view, which is exactly how the two backends drifted
/// (INTEGRATION.md A3 lists nine behaviors present on AppKit and missing on
/// UIKit). Here the buffer, the undo stacks, the highlight runs and the surface
/// live in one `@MainActor` object; a backend is a renderer that forwards user
/// gestures into it. A fix lands once.
///
/// **Mutation path.** Every change goes through `apply(_:intent:)` or
/// `apply(_:intent:)` for batches, which is the `TextEdit`-only rule from
/// projectRules.md (Data Safety) enforced at the API surface. Backends never
/// write to storage.
///
/// **Undo authority.** `UndoCoordinator` is the only undo stack. The platform
/// text views' native undo is switched off in both backends; two stacks that
/// disagree about what a "unit" is produce user-visible corruption, not a
/// double-safety net.
@MainActor
@Observable
public final class GlassEditorModel {

    // MARK: - Stored state

    /// The document text. Maintained in step with `buffer` after every mutation
    /// so that `@Observable` sees the change — a reference-type buffer read
    /// through a computed property would never invalidate an observer.
    public private(set) var text: String

    /// Whether the buffer differs from the last known-clean content.
    ///
    /// Exact rather than sticky: undoing back to the opened content clears the
    /// flag. The comparison is guarded by a UTF-16 length check first, so the
    /// common typing case (length changed) costs `O(1)` and the equal-length case
    /// costs one string comparison at editor scale.
    public private(set) var isDirty: Bool = false

    /// Highlight runs for the current content, as supplied by a highlighter.
    /// Ranges are UTF-16 offsets and may be stale by a debounce interval — the
    /// backends clamp defensively (`AttributedAssembly.clampedRange`).
    public private(set) var highlightRuns: [HighlightRun] = []

    /// What the text is being drawn on. Never faked: a consumer with no ambient
    /// signal leaves `ambient` at `.unknown` (projectRules.md, Theming).
    public var surfaceCondition: SurfaceCondition

    /// The palette in force. Changing it re-resolves every run.
    public var theme: EditorTheme

    /// Behavior configuration, injected as a value (projectRules.md, API Design).
    public var configuration: GlassEditorConfiguration

    /// The facts established at open, carried so save can stay honest.
    public private(set) var snapshot: DocumentSnapshot

    /// The document's language, used for provider requests.
    public var language: LanguageID

    /// Current selection in UTF-16 code units; an empty range is a caret.
    public var selectedRange: Range<Int> = 0..<0

    /// The remote conflict decision, surfaced and never auto-resolved
    /// (projectRules.md, Data Safety). `indeterminate` stays `indeterminate`.
    public var conflictState: ConflictState = .noConflict

    /// Monotonic counter bumped on every content mutation. Backends use it to
    /// tell "the model changed underneath me" from "I am the one who changed it",
    /// without comparing whole documents.
    public private(set) var revision: Int = 0

    // MARK: Providers

    /// Consumer-supplied completion source. glassdb passes live schema
    /// identifiers through this; glas.sh passes nothing and the editor still
    /// works (INTEGRATION.md A5).
    public var completionProvider: (any CompletionProvider)?
    /// Consumer-supplied diagnostics (glassdb's SQL linter).
    public var diagnosticsProvider: (any DiagnosticsProvider)?
    /// Consumer-supplied statement boundaries. The *classification* of a
    /// statement never moves into this package (INTEGRATION.md A2).
    public var statementBoundaryProvider: (any StatementBoundaryProvider)?

    // MARK: Internals

    @ObservationIgnored private let buffer: TextStorageBuffer
    @ObservationIgnored private let undoCoordinator: UndoCoordinator
    @ObservationIgnored private var cleanText: String
    @ObservationIgnored private var cleanUTF16Length: Int
    /// The built-in tree-sitter highlighter, when enabled. Retained here so it
    /// lives as long as the model; `nil` when the consumer opted out (LSP /
    /// manual `setHighlights`) or the grammar failed to load.
    @ObservationIgnored private var highlightDriver: SyntaxHighlightDriver?

    // MARK: - Init

    /// - Parameters:
    ///   - snapshot: the document as opened — content, encoding, line endings,
    ///     origin, and the remote facts recorded at that instant.
    ///   - configuration: behavior configuration.
    ///   - theme: the palette.
    ///   - language: grammar to request highlighting and provider results for.
    ///     Defaults to the extension mapping for a `.local` origin, `.plaintext`
    ///     otherwise — an honest default, never a guessed grammar.
    ///   - surfaceCondition: what the text sits on. Defaults to `.opaque`, the
    ///     desktop-editor baseline.
    ///   - undoClock: injectable so coalescing is testable deterministically.
    ///   - builtInHighlighting: when `true` (the default), the model drives
    ///     tree-sitter highlighting from the package's own grammars — the editor
    ///     is coloured with no further wiring. Set `false` when you push
    ///     highlights yourself (an LSP client's semantic tokens via
    ///     `setHighlights`), so the two do not fight. A grammar that fails to
    ///     load silently leaves plain text rather than failing construction.
    ///   - grammarRegistry: the registry the built-in highlighter parses against.
    ///     Pass a shared registry when opening many editors to reuse loaded
    ///     grammars; omit for a per-model default.
    public init(
        snapshot: DocumentSnapshot,
        configuration: GlassEditorConfiguration = GlassEditorConfiguration(),
        theme: EditorTheme = .glassDark,
        language: LanguageID? = nil,
        surfaceCondition: SurfaceCondition = .opaque,
        undoClock: any UndoClock = ContinuousUndoClock(),
        builtInHighlighting: Bool = true,
        grammarRegistry: GrammarRegistry? = nil
    ) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.theme = theme
        self.surfaceCondition = surfaceCondition
        self.buffer = TextStorageBuffer(text: snapshot.content)
        self.undoCoordinator = UndoCoordinator(clock: undoClock)
        self.text = snapshot.content
        self.cleanText = snapshot.content
        self.cleanUTF16Length = snapshot.content.utf16.count
        self.language = language ?? GlassEditorModel.inferredLanguage(for: snapshot.origin)

        if builtInHighlighting {
            startBuiltInHighlighting(registry: grammarRegistry ?? GrammarRegistry())
        }
    }

    /// Starts (or restarts) the built-in tree-sitter highlighter for the model's
    /// current `language`. Called automatically by `init` unless
    /// `builtInHighlighting: false`. Call it again after changing `language` to
    /// re-parse under the new grammar.
    ///
    /// - Returns: `true` if the highlighter started; `false` if the grammar
    ///   failed to load (the editor stays plain text).
    @discardableResult
    public func startBuiltInHighlighting(registry: GrammarRegistry = GrammarRegistry()) -> Bool {
        highlightDriver = try? SyntaxHighlightDriver(model: self, registry: registry)
        return highlightDriver != nil
    }

    /// Whether the built-in highlighter is currently degrading a large document
    /// to plaintext (see `DocumentParser.highlightingCodeUnitCeiling`). `false`
    /// when highlighting is off or within the ceiling.
    public var isHighlightingDegradedToPlaintext: Bool {
        highlightDriver?.isDegradedToPlaintext ?? false
    }

    private static func inferredLanguage(for origin: DocumentOrigin) -> LanguageID {
        guard case .local(let url) = origin else { return .plaintext }
        return LanguageID.forFileExtension(url.pathExtension)
    }

    // MARK: - Content

    /// Document length in UTF-16 code units — the coordinate system every range
    /// in this package uses.
    public var utf16Length: Int { buffer.utf16Length }

    /// Number of lines, on the buffer's convention: a trailing terminator opens a
    /// final empty line, so `"a\n"` is two lines.
    public var lineCount: Int { buffer.lineCount }

    /// Index of the line containing a UTF-16 offset, `O(log n)`. This is what the
    /// gutters call per layout fragment — the binary-search behavior
    /// INTEGRATION.md A4 requires in place of the TextKit 1 `prefix.reduce` scan.
    public func lineIndex(forUTF16Offset offset: Int) -> Int {
        buffer.lineIndex(forUTF16Offset: offset)
    }

    /// The UTF-16 range of a line including its terminator.
    public func lineRange(ofLine line: Int) -> Range<Int> {
        buffer.lineRange(ofLine: line)
    }

    /// The text in `range`.
    /// - Throws: `EditorError.rangeOutOfBounds`, `EditorError.splitsSurrogatePair`.
    public func substring(in range: Range<Int>) throws -> String {
        try buffer.substring(in: range)
    }

    // MARK: - Mutation

    /// Applies one edit and records it for undo under `intent`.
    ///
    /// - Throws: whatever `TextStorageBuffer.apply(_:)` throws. A throw leaves
    ///   the document, the undo stack, and the dirty flag untouched.
    @discardableResult
    public func apply(_ edit: TextEdit, intent: EditIntent = .programmatic) throws -> AppliedEdit {
        let applied = try buffer.apply(edit)
        undoCoordinator.record(applied, intent: intent)
        didMutate()
        return applied
    }

    /// Applies a batch as **one** undoable unit — a replace-all, a multi-cursor
    /// commit, a reindent.
    ///
    /// `TextStorageBuffer.apply(_:)` returns the applied edits in *application*
    /// order, which for a batch is back-to-front (highest offset first). That is
    /// exactly the order `UndoCoordinator.record(_:intent:)` requires, so the
    /// array is passed straight through: reordering it to the batch's declaration
    /// order would produce inverses that drift.
    @discardableResult
    public func apply(_ batch: TextEditBatch, intent: EditIntent = .programmatic) throws -> [AppliedEdit] {
        guard !batch.edits.isEmpty else { return [] }
        let applied = try buffer.apply(batch)
        undoCoordinator.record(applied, intent: intent)
        didMutate()
        return applied
    }

    /// Replaces the whole document as a single edit under `intent`.
    public func replaceAllContent(with newText: String, intent: EditIntent = .programmatic) throws {
        try apply(
            TextEdit(replacementRange: 0..<buffer.utf16Length, text: newText),
            intent: intent
        )
    }

    // MARK: - Undo / redo

    public var canUndo: Bool { undoCoordinator.canUndo }
    public var canRedo: Bool { undoCoordinator.canRedo }
    /// The intent of the newest undoable unit — for menu titles ("Undo Paste").
    public var newestUndoIntent: EditIntent? { undoCoordinator.newestIntent }

    /// Reverses the newest undo unit.
    ///
    /// An `UndoStep`'s edits are applied **sequentially, front to back**: each
    /// range is valid against the state the previous edit produced. This is the
    /// opposite of `TextEditBatch`, whose ranges are all pre-batch — the two are
    /// different types precisely so this cannot be confused.
    ///
    /// The re-application is not itself recorded; the coordinator has already
    /// moved the unit to the redo stack.
    ///
    /// - Returns: `true` when something was undone.
    @discardableResult
    public func undo() -> Bool {
        guard let step = undoCoordinator.undoUnit() else { return false }
        applySequentially(step)
        return true
    }

    /// Re-applies the newest undone unit. Same sequential semantics as `undo()`.
    /// - Returns: `true` when something was redone.
    @discardableResult
    public func redo() -> Bool {
        guard let step = undoCoordinator.redoUnit() else { return false }
        applySequentially(step)
        return true
    }

    /// Drops both undo stacks — used when the document's identity changes
    /// underneath the editor and no recorded inverse would be meaningful.
    public func resetUndoHistory() {
        undoCoordinator.reset()
    }

    private func applySequentially(_ step: UndoStep) {
        for edit in step.edits {
            // An inverse produced by the coordinator is valid by construction
            // against the state its predecessor left. A throw here would mean the
            // buffer and the undo stack had already diverged, which no recorded
            // path can produce — so it is reported through the buffer's own error
            // rather than swallowed, and the remaining edits are abandoned so the
            // document is not left half-reversed.
            do {
                try buffer.apply(edit)
            } catch {
                assertionFailure("Undo step diverged from the buffer: \(error)")
                break
            }
        }
        didMutate()
    }

    // MARK: - Highlighting and surface

    /// Replaces the highlight runs for the current content.
    ///
    /// Runs may describe a slightly older document — highlighting is
    /// asynchronous — and are clamped at render time rather than rejected here,
    /// so a highlighter is never required to win a race with the typist.
    public func setHighlights(_ runs: [HighlightRun]) {
        highlightRuns = runs
    }

    /// Updates what the text is drawn on, which re-resolves every color through
    /// `ContrastAdapter` on the next render.
    public func updateSurface(_ surface: SurfaceCondition) {
        surfaceCondition = surface
    }

    // MARK: - Dirty tracking

    /// Marks the current content clean — call after a successful save.
    ///
    /// Also refreshes `snapshot.content` so a later conflict decision compares
    /// against what was actually written, not what was opened.
    public func markClean() {
        cleanText = text
        cleanUTF16Length = buffer.utf16Length
        snapshot.content = cleanText
        isDirty = false
    }

    /// Adopts new content wholesale — a remote reload.
    ///
    /// Recorded as `.remoteReload`, which is a coalescing barrier and *is*
    /// undoable: undoing a reload restores the pre-reload buffer, which is a
    /// data-safety guarantee rather than a convenience (`EditIntent.isBarrier`).
    public func adoptReloadedContent(_ newSnapshot: DocumentSnapshot) throws {
        try apply(
            TextEdit(replacementRange: 0..<buffer.utf16Length, text: newSnapshot.content),
            intent: .remoteReload
        )
        snapshot = newSnapshot
        markClean()
        conflictState = .noConflict
    }

    private func didMutate() {
        text = buffer.text
        revision &+= 1
        refreshDirty()
    }

    private func refreshDirty() {
        if buffer.utf16Length != cleanUTF16Length {
            isDirty = true
        } else {
            isDirty = text != cleanText
        }
    }

    // MARK: - Find and replace

    /// All matches of `query` in the current content, as UTF-16 ranges.
    ///
    /// Literal case-insensitive matching applies canonical equivalence, so a
    /// match's length can differ from the pattern's (`STRASSE` matching `Straße`).
    /// Always use the returned ranges; never `pattern.utf16.count`.
    ///
    /// - Throws: `EditorError.invalidPattern` for an uncompilable regex.
    public func matches(of query: FindQuery) throws -> [Range<Int>] {
        try FindEngine.matches(of: query, in: text)
    }

    /// The first match at or after `offset` — find-next.
    public func nextMatch(
        of query: FindQuery,
        after offset: Int? = nil,
        wrapping: Bool = true
    ) throws -> Range<Int>? {
        try FindEngine.nextMatch(
            of: query, in: text, after: offset ?? selectedRange.upperBound, wrapping: wrapping
        )
    }

    /// The last match ending at or before `offset` — find-previous.
    public func previousMatch(
        of query: FindQuery,
        before offset: Int? = nil,
        wrapping: Bool = true
    ) throws -> Range<Int>? {
        try FindEngine.previousMatch(
            of: query, in: text, before: offset ?? selectedRange.lowerBound, wrapping: wrapping
        )
    }

    /// Replaces every match in **one** undo unit (`EditIntent.replaceAll`).
    ///
    /// The plan's ranges are all measured against the pre-replace snapshot, which
    /// is the `TextEditBatch` contract; the buffer applies them back-to-front and
    /// hands back the applied edits in that same order for the undo stack.
    ///
    /// - Returns: how many matches were replaced.
    /// - Throws: `EditorError.invalidPattern` for an uncompilable regex.
    @discardableResult
    public func replaceAll(of query: FindQuery, with replacement: String) throws -> Int {
        let plan = try FindEngine.replacePlan(for: query, replacement: replacement, in: text)
        guard !plan.edits.isEmpty else { return 0 }
        try apply(plan, intent: .replaceAll)
        return plan.edits.count
    }

    /// Replaces the first match at or after `offset`.
    /// - Returns: the range the replacement now occupies, or `nil` if nothing matched.
    @discardableResult
    public func replaceNext(
        of query: FindQuery,
        with replacement: String,
        after offset: Int? = nil,
        wrapping: Bool = true
    ) throws -> Range<Int>? {
        let start = offset ?? selectedRange.lowerBound
        guard let edit = try FindEngine.replaceNext(
            of: query, replacement: replacement, in: text, after: start, wrapping: wrapping
        ) else { return nil }
        try apply(edit, intent: .replaceAll)
        let lower = edit.replacementRange.lowerBound
        return lower..<(lower + edit.insertedLength)
    }

    // MARK: - Providers

    /// Statement spans from the consumer's provider, or `[]` when none is
    /// supplied. The package never invents statement boundaries.
    public func statementSpans() async throws -> [StatementSpan] {
        guard let provider = statementBoundaryProvider else { return [] }
        return try await provider.statements(in: text, language: language)
    }

    /// Completions for the caret, ranked by the provider. Ordering is the
    /// provider's to decide — glassdb's is user-visible and must not be resorted
    /// here (INTEGRATION.md A5).
    public func completions(at position: Int? = nil) async throws -> [CompletionItem] {
        guard let provider = completionProvider else { return [] }
        let caret = min(max(position ?? selectedRange.upperBound, 0), buffer.utf16Length)
        let request = CompletionRequest(
            position: caret,
            prefix: wordPrefix(before: caret),
            language: language
        )
        return try await provider.completions(for: request, in: text)
    }

    /// Diagnostics from the consumer's provider, or `[]` when none is supplied.
    public func diagnostics() async throws -> [EditorDiagnostic] {
        guard let provider = diagnosticsProvider else { return [] }
        return try await provider.diagnostics(for: text, language: language)
    }

    /// The word fragment immediately before `caret`, using the same
    /// word-character rule find uses (`FindEngine.isWordCharacter`) so
    /// "what counts as a word" has one definition in the package.
    ///
    /// Reads a **bounded window** before the caret rather than the whole line,
    /// and scans it without front-insertion. The previous version materialised
    /// the entire line prefix and did an `O(n)` `insert(at: startIndex)` per
    /// character — quadratic, and an 8 MB allocation for a caret at the end of a
    /// single-line minified/base64 document, on the main actor (pen finding
    /// M-6). A completion prefix longer than the window is not a real word, so
    /// the cap costs nothing.
    func wordPrefix(before caret: Int) -> String {
        guard caret > 0 else { return "" }
        let line = buffer.lineIndex(forUTF16Offset: caret)
        let lineStart = buffer.lineRange(ofLine: line).lowerBound
        let windowFloor = max(lineStart, caret - Self.wordPrefixWindow)

        // Find the lowest valid window start at or after the floor — nudging up
        // by one if the floor split a surrogate pair (at most one step).
        var windowStart = windowFloor
        var window: String?
        while windowStart < caret {
            if let text = try? buffer.substring(in: windowStart..<caret) {
                window = text
                break
            }
            windowStart += 1
        }
        guard let window else { return "" }

        var start = window.endIndex
        while start > window.startIndex {
            let prev = window.index(before: start)
            guard FindEngine.isWordCharacter(window[prev]) else { break }
            start = prev
        }
        return String(window[start...])
    }

    /// UTF-16 window `wordPrefix` scans before the caret. Words longer than this
    /// are not completed; 256 is far past any real identifier.
    private static let wordPrefixWindow = 256
}
