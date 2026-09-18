//
//  GlassEditorAdapters.swift
//  glassdb
//
//  glassdb's seam onto GlassEditorKit (M3 Phase 2): provider implementations
//  backed by the retained SQL policy engine (package decision D-008), and the
//  canonical SQL editing surface wrapping the package engine with glassdb's
//  binding, focus-token, and glass-canvas semantics.
//

import SwiftUI
import GlassEditorCore
import GlassEditorUI

extension EnvironmentValues {
    /// Identity of the SQL document whose editor should claim the keyboard
    /// once, so File > New SQL Document lands the caret in its editor instead
    /// of the sidebar filter.
    @Entry var sqlEditorFocusToken: UUID?
}

// MARK: - Providers

/// SQLHighlighter remains the semantic authority for completion; the package
/// owns only the role. Ranking order is SQLHighlighter's deterministic order,
/// passed through untouched.
struct SQLEditorCompletionProvider: CompletionProvider {
    let schemaIdentifiers: [String]

    func completions(
        for request: CompletionRequest,
        in snapshot: String
    ) async throws -> [CompletionItem] {
        guard request.language == .sql else { return [] }
        let caret = NSRange(
            location: min(request.position, (snapshot as NSString).length),
            length: 0
        )
        return SQLHighlighter.completions(
            in: snapshot,
            selectedRange: caret,
            schemaIdentifiers: schemaIdentifiers
        ).map { suggestion in
            CompletionItem(
                id: suggestion,
                label: suggestion,
                insertText: suggestion,
                kind: .other
            )
        }
    }
}

struct SQLEditorDiagnosticsProvider: DiagnosticsProvider {
    func diagnostics(
        for snapshot: String,
        language: LanguageID
    ) async throws -> [EditorDiagnostic] {
        guard language == .sql else { return [] }
        return SQLHighlighter.lint(snapshot).map { diagnostic in
            EditorDiagnostic(
                id: diagnostic.id.uuidString,
                range: snapshot.utf16OffsetRange(of: diagnostic.range),
                severity: .warning,
                message: diagnostic.message
            )
        }
    }
}

/// Statement ranges come from glassdb's parser; classification never leaves
/// glassdb (INTEGRATION.md A2, D-008).
struct SQLEditorStatementBoundaryProvider: StatementBoundaryProvider {
    func statements(
        in snapshot: String,
        language: LanguageID
    ) async throws -> [StatementSpan] {
        guard language == .sql else { return [] }
        return SQLHighlighter.statements(in: snapshot).map { statement in
            StatementSpan(
                id: statement.id,
                range: snapshot.utf16OffsetRange(of: statement.range)
            )
        }
    }
}

private extension String {
    func utf16OffsetRange(of range: Range<String.Index>) -> Range<Int> {
        let lower = range.lowerBound.utf16Offset(in: self)
        let upper = range.upperBound.utf16Offset(in: self)
        return lower..<max(lower, upper)
    }
}

// MARK: - Imperative editor handle

/// The single inbound path for external writes to the SQL editor. The editor
/// model is the source of truth for text and selection; SwiftUI state follows
/// it one-way through the outbound bridge. Anything that wants to REPLACE
/// editor content — completion insertion, Format, history/saved-query
/// insertion, AI drafts, Clear, document open, generated table queries —
/// calls this handle, never the bindings. Update passes apply no content
/// diffs at all, which eliminates the entire stale-binding race class.
@MainActor
final class SQLEditorController {
    fileprivate var applyText: ((String) -> Void)?
    fileprivate var applySelection: ((NSRange) -> Void)?
    private var pendingText: String?
    private var pendingSelection: NSRange?
    private var completionSpace: (text: String, offset: Int)?

    func markCompletionSpace(in text: String, at offset: Int?) {
        completionSpace = offset.map { (text, $0) }
    }

    /// Only the immediately preceding completion may authorize deleting a space.
    func completionPunctuationEdit(text: String, selection: NSRange) -> (text: String, selection: NSRange)? {
        guard let pending = completionSpace else { return nil }
        let caret = pending.offset + 1
        if text == pending.text && selection == NSRange(location: caret, length: 0) { return nil }
        completionSpace = nil
        let expected = (pending.text as NSString).replacingCharacters(
            in: NSRange(location: caret, length: 0), with: ".")
        guard text == expected, selection == NSRange(location: caret + 1, length: 0) else { return nil }
        return ((text as NSString).replacingCharacters(
            in: NSRange(location: pending.offset, length: 1), with: ""),
                NSRange(location: caret, length: 0))
    }

    func setText(_ text: String, selection: NSRange? = nil) {
        if completionSpace?.text != text { completionSpace = nil }
        if let applyText {
            applyText(text)
        } else {
            // The engine attaches when the surface first builds; a write that
            // races view creation (e.g. the table surface's generated query)
            // is buffered and flushed on attach.
            pendingText = text
        }
        if let selection { setSelection(selection) }
    }

    func setSelection(_ range: NSRange) {
        if let applySelection {
            applySelection(range)
        } else {
            pendingSelection = range
        }
    }

    fileprivate func attach(
        applyText: @escaping (String) -> Void,
        applySelection: @escaping (NSRange) -> Void
    ) {
        self.applyText = applyText
        self.applySelection = applySelection
        if let pendingText {
            self.pendingText = nil
            applyText(pendingText)
        }
        if let pendingSelection {
            self.pendingSelection = nil
            applySelection(pendingSelection)
        }
    }
}

// MARK: - SQL editing surface

/// The canonical SQL editor: a GlassEditorKit engine bridged to glassdb's
/// string/NSRange bindings. Replaces the TextKit 1 HighlightedTextEditor.
struct SQLEditorSurface: View {
    @Binding var text: String
    var fontSize: CGFloat
    var showLineNumbers: Bool
    var selection: Binding<NSRange>?
    var isActive: Bool = true
    var schemaIdentifiers: [String] = []
    var controller: SQLEditorController?
    /// Returns true when a completion was accepted; Tab falls through to
    /// normal indentation otherwise. macOS only today (hardware-keyboard
    /// Tab on iPad still indents — known gap).
    var onTabComplete: (() -> Bool)?
    /// Dimmed inline preview of what Tab would append at the caret.
    var ghostSuffix: String?
    /// Applied to the hosted text view itself, not the SwiftUI wrapper: a
    /// representable's accessibility modifiers do not reach the AppKit/UIKit
    /// element that actually carries the text as its value.
    var textViewIdentifier: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(SettingsManager.self) private var settingsManager

    @State private var model: GlassEditorModel

    init(
        text: Binding<String>,
        fontSize: CGFloat,
        showLineNumbers: Bool,
        selection: Binding<NSRange>? = nil,
        isActive: Bool = true,
        schemaIdentifiers: [String] = [],
        controller: SQLEditorController? = nil,
        onTabComplete: (() -> Bool)? = nil,
        ghostSuffix: String? = nil,
        textViewIdentifier: String? = nil
    ) {
        _text = text
        self.fontSize = fontSize
        self.showLineNumbers = showLineNumbers
        self.selection = selection
        self.isActive = isActive
        self.schemaIdentifiers = schemaIdentifiers
        self.controller = controller
        self.onTabComplete = onTabComplete
        self.ghostSuffix = ghostSuffix
        self.textViewIdentifier = textViewIdentifier

        let snapshot = DocumentSnapshot(
            content: text.wrappedValue,
            encoding: .utf8(hadBOM: false),
            lineEndings: .lf,
            origin: .ephemeral(id: UUID())
        )
        _model = State(initialValue: GlassEditorModel(
            snapshot: snapshot,
            configuration: GlassEditorConfiguration(
                fontSize: Double(fontSize),
                showsLineNumbers: showLineNumbers,
                isEditable: isActive
            ),
            language: .sql,
            surfaceCondition: .opaque
        ))
    }

    var body: some View {
        SQLEditorRepresentable(
            model: model,
            isActive: isActive,
            controller: controller,
            onTabComplete: onTabComplete,
            ghostSuffix: ghostSuffix,
            textViewIdentifier: textViewIdentifier,
            onModelTextChange: { newText in
                if text != newText { text = newText }
            },
            onModelSelectionChange: { newRange in
                guard let selection else { return }
                if selection.wrappedValue != newRange {
                    selection.wrappedValue = newRange
                }
            }
        )
            .onAppear {
                applyEnvironment()
                model.completionProvider = SQLEditorCompletionProvider(
                    schemaIdentifiers: schemaIdentifiers
                )
                model.diagnosticsProvider = SQLEditorDiagnosticsProvider()
                model.statementBoundaryProvider = SQLEditorStatementBoundaryProvider()
            }
            .onChange(of: fontSize) { _, newSize in
                model.configuration.fontSize = Double(newSize)
            }
            .onChange(of: showLineNumbers) { _, newValue in
                model.configuration.showsLineNumbers = newValue
            }
            .onChange(of: isActive) { _, newValue in
                model.configuration.isEditable = newValue
            }
            .onChange(of: colorScheme) { applyEnvironment() }
            .onChange(of: settingsManager.windowOpacity) { applyEnvironment() }
            .onChange(of: settingsManager.blurBackground) { applyEnvironment() }
            .onChange(of: schemaIdentifiers) { _, identifiers in
                model.completionProvider = SQLEditorCompletionProvider(
                    schemaIdentifiers: identifiers
                )
            }
    }

    /// Theme follows the system appearance; the surface follows the same
    /// opacity + blur pair that drives the database canvas
    /// (INTEGRATION.md A7 — `DatabaseGlassAppearance` maps to
    /// `.blur(strength:)`, not a material weight).
    private func applyEnvironment() {
        model.theme = colorScheme == .dark ? .glassDark : .glassLight
        model.updateSurface(SurfaceCondition(
            windowOpacity: settingsManager.windowOpacity,
            backing: .blur(strength: settingsManager.blurBackground),
            ambient: .unknown
        ))
    }

}

// MARK: - Platform representables

#if os(macOS)

private struct SQLEditorRepresentable: NSViewRepresentable {
    let model: GlassEditorModel
    let isActive: Bool
    let controller: SQLEditorController?
    var onTabComplete: (() -> Bool)?
    var ghostSuffix: String?
    var textViewIdentifier: String?
    var onModelTextChange: (String) -> Void
    var onModelSelectionChange: (NSRange) -> Void
    @Environment(\.sqlEditorFocusToken) private var focusToken

    func makeCoordinator() -> SQLEditorBridgeCoordinator<GlassEditorAppKitEngine> {
        SQLEditorBridgeCoordinator(engine: GlassEditorAppKitEngine(model: model))
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.armObservation(of: model)
        if let controller {
            let engine = context.coordinator.engine
            context.coordinator.attach(
                controller: controller,
                model: model,
                syncViewNow: { engine.coordinator.syncTextViewFromModel(engine.textView) }
            ) { range in
                engine.selectedRange = range
            }
        }
        installTabCompleteMonitor(coordinator: context.coordinator)
        // The engine leaves the horizontal scroller off even in no-wrap
        // mode; long SQL lines would clip at the frame edge. Consumer-side
        // override until the package enables it for wrapsLines == false.
        let scrollView = context.coordinator.engine.scrollView
        let textView = context.coordinator.engine.textView
        scrollView.hasHorizontalScroller = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let textViewIdentifier {
            textView.setAccessibilityIdentifier(textViewIdentifier)
        }
        // The engine's container, which carries the line-number gutter beside
        // the scroll view; the SQL editor gets the same gutter the file editor
        // does, and both are placed by their SwiftUI parent.
        return context.coordinator.engine.containerView
    }

    /// Tab accepts the top completion when the editor has focus and the
    /// consumer reports a suggestion; every other Tab (modifiers, other
    /// windows, no suggestions) passes through untouched. The package's
    /// text view has no doCommandBy hook today, so this is the consumer-side
    /// seam; replace with an engine hook if GlassEditorKit grows one.
    private func installTabCompleteMonitor(
        coordinator: SQLEditorBridgeCoordinator<GlassEditorAppKitEngine>
    ) {
        guard coordinator.tabKeyMonitor == nil else { return }
        let textView = coordinator.engine.textView
        coordinator.tabKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 48,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            // Only Sendable values cross into the isolated check; the
            // monitor runs on the main thread, so assumeIsolated holds.
            let eventWindowID = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let window = textView.window,
                      eventWindowID == ObjectIdentifier(window),
                      window.firstResponder === textView
                else { return false }
                return coordinator.onTabComplete?() == true
            }
            return handled ? nil : event
        }
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: SQLEditorBridgeCoordinator<GlassEditorAppKitEngine>
    ) {
        if let monitor = coordinator.tabKeyMonitor {
            NSEvent.removeMonitor(monitor)
            coordinator.tabKeyMonitor = nil
        }
    }

    // Update passes refresh closures, focus, and editability ONLY — never
    // content. Inbound content flows exclusively through SQLEditorController.
    func updateNSView(_ containerView: NSView, context: Context) {
        context.coordinator.onTextChange = onModelTextChange
        context.coordinator.onSelectionChange = onModelSelectionChange
        context.coordinator.onTabComplete = onTabComplete
        context.coordinator.updateGhost(
            suffix: ghostSuffix,
            fontSize: CGFloat(model.configuration.fontSize)
        )

        let textView = context.coordinator.engine.textView
        if !isActive, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
        // A newly shown SQL document takes the keyboard once, so
        // File > New SQL Document lands the caret in its editor.
        if isActive,
           let focusToken,
           context.coordinator.claimedFocusToken != focusToken,
           let window = textView.window {
            context.coordinator.claimedFocusToken = focusToken
            window.makeFirstResponder(textView)
        }
    }
}

#else

private struct SQLEditorRepresentable: UIViewRepresentable {
    let model: GlassEditorModel
    let isActive: Bool
    let controller: SQLEditorController?
    // Accepted for call-site parity; hardware-keyboard Tab-complete and
    // ghost preview on iPad are known gaps until the package exposes hooks.
    var onTabComplete: (() -> Bool)?
    var ghostSuffix: String?
    var textViewIdentifier: String?
    var onModelTextChange: (String) -> Void
    var onModelSelectionChange: (NSRange) -> Void
    @Environment(\.sqlEditorFocusToken) private var focusToken

    func makeCoordinator() -> SQLEditorBridgeCoordinator<GlassEditorUIKitEngine> {
        SQLEditorBridgeCoordinator(engine: GlassEditorUIKitEngine(model: model))
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.armObservation(of: model)
        if let controller {
            let engine = context.coordinator.engine
            context.coordinator.attach(
                controller: controller,
                model: model,
                syncViewNow: { engine.coordinator.syncTextViewFromModel(engine.textView) }
            ) { range in
                engine.selectedRange = range
            }
        }
        if let textViewIdentifier {
            context.coordinator.engine.textView.accessibilityIdentifier = textViewIdentifier
        }
        return context.coordinator.engine.containerView
    }

    // Update passes refresh closures, focus, and editability ONLY — never
    // content. Inbound content flows exclusively through SQLEditorController.
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTextChange = onModelTextChange
        context.coordinator.onSelectionChange = onModelSelectionChange

        let textView = context.coordinator.engine.textView
        if !isActive, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        if isActive,
           let focusToken,
           context.coordinator.claimedFocusToken != focusToken,
           textView.window != nil {
            context.coordinator.claimedFocusToken = focusToken
            textView.becomeFirstResponder()
        }
    }
}

#endif

#if os(macOS)
extension SQLEditorBridgeCoordinator where Engine == GlassEditorAppKitEngine {
    /// Positions a dimmed CATextLayer at the caret showing what Tab would
    /// append. Consumer-side because the package's view exposes no inline
    /// suggestion surface; sublayer of the text view so it scrolls with
    /// content. Hidden whenever there is no suffix, a non-empty selection,
    /// or the editor lacks focus.
    func updateGhost(suffix: String?, fontSize: CGFloat) {
        let textView = engine.textView
        let caret = textView.selectedRange()
        guard let suffix, !suffix.isEmpty,
              caret.length == 0,
              let window = textView.window,
              window.firstResponder === textView else {
            ghostLayer?.isHidden = true
            return
        }
        let screenRect = textView.firstRect(forCharacterRange: caret, actualRange: nil)
        guard screenRect.height > 0 else {
            ghostLayer?.isHidden = true
            return
        }
        let windowRect = window.convertFromScreen(screenRect)
        let viewRect = textView.convert(windowRect, from: nil)

        let layer: CATextLayer
        if let existing = ghostLayer {
            layer = existing
        } else {
            layer = CATextLayer()
            layer.zPosition = 10
            textView.wantsLayer = true
            textView.layer?.addSublayer(layer)
            ghostLayer = layer
        }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        var resolved = NSColor.tertiaryLabelColor.cgColor
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.tertiaryLabelColor.cgColor
        }
        let size = (suffix as NSString).size(withAttributes: [.font: font])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.font = font
        layer.fontSize = fontSize
        layer.string = suffix
        layer.contentsScale = window.backingScaleFactor
        layer.foregroundColor = resolved
        layer.frame = CGRect(
            x: viewRect.origin.x,
            y: viewRect.origin.y,
            width: ceil(size.width),
            height: viewRect.height
        )
        layer.isHidden = false
        CATransaction.commit()
    }
}
#endif

/// Engine-side bridge: pushes the model's text and selection into glassdb's
/// bindings via Observation directly, independent of SwiftUI body evaluation.
/// The completion bar reads those bindings, so its inputs must update on every
/// keystroke even when SwiftUI coalesces or skips view updates (the workspace
/// keeps inactive editors alive in a ZStack, where `onChange` delivery is not
/// a dependable per-keystroke signal).
@MainActor
final class SQLEditorBridgeCoordinator<Engine> {
    let engine: Engine
    var claimedFocusToken: UUID?
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?
    #if os(macOS)
    // Tab-to-complete: consumer hook + the NSEvent monitor that drives it.
    // Lives here (not on the value-type representable) so dismantle can
    // remove exactly the monitor that make installed.
    var onTabComplete: (() -> Bool)?
    var tabKeyMonitor: Any?
    private var ghostLayer: CATextLayer?
    #endif
    private var lastText: String?
    private var lastSelection: NSRange?
    private weak var controller: SQLEditorController?

    init(engine: Engine) {
        self.engine = engine
    }

    /// One-shot Observation registration, re-armed after every delivery.
    func armObservation(of model: GlassEditorModel) {
        withObservationTracking {
            _ = model.text
            _ = model.selectedRange
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deliver(from: model)
                self.armObservation(of: model)
            }
        }
    }

    private func deliver(from model: GlassEditorModel) {
        let currentSelection = NSRange(location: model.selectedRange.lowerBound, length: model.selectedRange.count)
        if let edit = controller?.completionPunctuationEdit(text: model.text, selection: currentSelection) {
            controller?.setText(edit.text, selection: edit.selection)
            onTextChange?(edit.text)
            onSelectionChange?(edit.selection)
            return
        }
        let text = model.text
        if text != lastText {
            lastText = text
            onTextChange?(text)
        }
        let selection = NSRange(
            location: model.selectedRange.lowerBound,
            length: model.selectedRange.count
        )
        if selection != lastSelection {
            lastSelection = selection
            onSelectionChange?(selection)
        }
    }

    /// Installs the imperative inbound path: external writers replace content
    /// through SQLEditorController, applied here directly to the model and
    /// engine. Equality guards make the outbound echo (state write → computed
    /// setter → controller) a no-op, so the two directions can never fight.
    func attach(
        controller: SQLEditorController,
        model: GlassEditorModel,
        syncViewNow: @escaping () -> Void,
        applySelection: @escaping (Range<Int>) -> Void
    ) {
        self.controller = controller
        controller.attach(
            applyText: { [weak self] newText in
                guard newText != model.text else { return }
                try? model.replaceAllContent(with: newText)
                // The engine's own model-revision handler syncs the view a
                // runloop turn later and restores the PRE-replace caret;
                // syncing here makes that pass a no-op so a selection applied
                // next clamps against the fresh content and sticks.
                syncViewNow()
                self?.lastText = newText
            },
            applySelection: { [weak self] requested in
                let location = min(max(0, requested.location), model.utf16Length)
                let length = min(max(0, requested.length), model.utf16Length - location)
                let range = location..<(location + length)
                guard range != model.selectedRange else { return }
                applySelection(range)
                self?.lastSelection = NSRange(location: location, length: length)
            }
        )
    }
}
