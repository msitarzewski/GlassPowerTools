#if canImport(SwiftUI)

import SwiftUI
import GlassEditorCore

/// The SwiftUI entry point: hand it a `GlassEditorModel`, get the native backend
/// for the platform.
///
/// macOS uses the AppKit backend — native `NSTextView`, not Mac Catalyst
/// (AGENTS.md, Project Context). iOS, iPadOS and visionOS use the UIKit one.
///
/// **The model is the API, not the view.** The view is deliberately thin: it
/// creates an engine, keeps it alive, and forwards configuration. Everything a
/// consumer wants to *do* — apply an edit, undo, find, set highlight runs, react
/// to a surface change — is on the model or the engine, both of which are
/// reachable without a view at all. That is what makes the read-only highlighting
/// path (glassdb's DDL display, `TableDetailView.swift:4985`) possible without an
/// editor, and what keeps the correctness-critical behavior testable headlessly.
public struct GlassEditorView: View {

    private let model: GlassEditorModel

    public init(model: GlassEditorModel) {
        self.model = model
    }

    public var body: some View {
        PlatformEditor(model: model)
    }
}

// MARK: - macOS

#if canImport(AppKit) && os(macOS)

private struct PlatformEditor: NSViewRepresentable {
    let model: GlassEditorModel

    func makeCoordinator() -> GlassEditorAppKitEngine {
        GlassEditorAppKitEngine(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        // The container, not the scroll view: the gutter is a sibling of the
        // scroll view inside it, so SwiftUI places both at once and the numbers
        // cannot occupy anything the text does not.
        context.coordinator.containerView
    }

    func updateNSView(_ containerView: NSView, context: Context) {
        // Nothing to push. The engine observes the model directly (see
        // GlassEditorAppKitEngine's model-observation block), so theme,
        // surface, configuration, highlights and content all reach the view the
        // instant the model changes — without routing through SwiftUI's update
        // cycle. A guard here comparing `engine.X != model.X` is tautologically
        // false anyway, because the engine's getters read straight from the
        // model; that dead code was a pen-suite finding.
    }
}

#elseif canImport(UIKit)

// MARK: - iOS / iPadOS / visionOS

private struct PlatformEditor: UIViewRepresentable {
    let model: GlassEditorModel

    func makeCoordinator() -> GlassEditorUIKitEngine {
        GlassEditorUIKitEngine(model: model)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.containerView
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Nothing to push — the engine observes the model directly. See the
        // matching note in `updateNSView`.
    }
}

#endif

#endif
