import Foundation
import Observation
import GlassEditorCore

/// Drives tree-sitter highlighting for a `GlassEditorModel` from the package's
/// own vended grammars — the batteries-included path.
///
/// **Why this exists.** `GlassEditorModel` only *holds* highlight runs
/// (`setHighlights`); it does not produce them, because the runs might come from
/// tree-sitter, from an LSP's semantic tokens, or from nothing (D-003). That
/// separation is correct, but it made highlighting a silent footgun: a consumer
/// that just built a model and showed a `GlassEditorView` got a working editor
/// with **no colours**, and nothing said so. This driver closes that gap for the
/// common case: it owns a `DocumentParser` for the model's language, does an
/// initial parse, and re-parses (debounced) whenever the document changes,
/// pushing the result through `setHighlights`.
///
/// It runs on the main actor and re-parses the whole document per debounce beat —
/// the same shape the demo used, kept cheap by the debounce plus
/// `DocumentParser.highlightingCodeUnitCeiling` (which degrades a very large file
/// to a single plain run). Incremental extraction is a future optimization; this
/// is correct and smooth for ordinary files today.
///
/// A consumer that drives highlights itself (an LSP client pushing semantic
/// tokens) should **not** use this — construct the model with
/// `builtInHighlighting: false` so the two do not fight over `setHighlights`.
@MainActor
public final class SyntaxHighlightDriver {

    // Weak so the model can own the driver without a retain cycle: the model
    // outlives it, and when the model deallocs the driver's observation stops.
    private weak var model: GlassEditorModel?
    private let parser: DocumentParser
    private let debounce: Duration
    private var pending: Task<Void, Never>?

    /// - Throws: whatever `DocumentParser(language:registry:)` throws when the
    ///   model's language has a grammar that fails to load. `plaintext` does not
    ///   throw — it produces a single plain cover run.
    public init(
        model: GlassEditorModel,
        registry: GrammarRegistry = GrammarRegistry()
    ) throws {
        self.model = model
        self.parser = try DocumentParser(language: model.language, registry: registry)
        self.debounce = .milliseconds(max(0, model.configuration.highlightDebounceMilliseconds))

        parser.parseFull(model.text)
        model.setHighlights(parser.highlights)
        observe()
    }

    /// Re-registers observation of the model's revision counter. `withObservationTracking`
    /// fires once; the handler re-arms it, mirroring the engine's own pattern.
    private func observe() {
        withObservationTracking { [weak self] in
            _ = self?.model?.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReparse()
                self?.observe()
            }
        }
    }

    private func scheduleReparse() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.debounce > .zero {
                try? await Task.sleep(for: self.debounce)
            }
            if Task.isCancelled { return }
            guard let model = self.model else { return }
            self.parser.parseFull(model.text)
            model.setHighlights(self.parser.highlights)
        }
    }

    /// Whether the current document is above the highlighting ceiling and so
    /// shown as plaintext. Surfaced for a consumer that wants to say "syntax
    /// highlighting off (large file)".
    public var isDegradedToPlaintext: Bool { parser.highlightingDegraded }
}
