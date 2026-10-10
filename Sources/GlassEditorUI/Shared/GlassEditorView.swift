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

    /// Holds the engine — which owns the text view — once it exists.
    func makeCoordinator() -> GlassEditorNextTurnBuild<GlassEditorUIKitEngine> {
        GlassEditorNextTurnBuild()
    }

    func makeUIView(context: Context) -> UIView {
        // **The text view is built after this update, never inside it** (rule 64). SwiftUI calls
        // this from inside its layout, and on Vision Pro a text view made here can bring up the
        // text-effects window and move focus while that layout still runs — the terminal's
        // headset crash. A plain host view goes in now; the engine and its `UITextView` a turn
        // later. The model is the API, so nothing is lost meanwhile: the engine reads the text,
        // runs, theme and configuration from it when it is built.
        let host = GlassEditorHostView()
        let model = model
        context.coordinator.schedule { [weak host] in
            guard let host else { return nil }
            let engine = GlassEditorUIKitEngine(model: model)
            host.install(engine.containerView)
            return engine
        }
        return host
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Nothing to push — the engine observes the model directly. See the
        // matching note in `updateNSView`.
    }
}

/// The view SwiftUI holds for an editor; the engine's container goes inside it, filling it, once
/// it has been built (`PlatformEditor.makeUIView`). The terminal's `TerminalRendererHostView`.
private final class GlassEditorHostView: UIView {
    init() {
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func install(_ view: UIView) {
        guard view.superview !== self else { return }
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }
}

#endif

#endif
