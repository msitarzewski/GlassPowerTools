//
//  GlassEditorDiagramView.swift
//  Glass Power Tools — GlassEditor
//
//  One Mermaid diagram, drawn as the Markdown preview draws one (D35: the bundled Mermaid, at its
//  strict security level, and nothing else runs): for a diagram a terminal shows as text, opened from
//  the mark beside it (the owner, 2026-10-21: "an inline diagram icon would be amazing"). The page is
//  the preview's own, with the diagram as its only fenced block, so a diagram looks the same here as
//  in a Markdown file, and one Mermaid can't read says why, as the preview does. It reads nothing
//  beside it: a terminal's diagram has no folder.
//

import SwiftUI
import WebKit

public struct GlassEditorDiagramView: View {
    let source: String

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage?

    public init(source: String) {
        self.source = source
    }

    public var body: some View {
        Group {
            if let page {
                WebView(page)
                    #if os(visionOS)
                    // The page's own transparent background, not WebKit's black slab (as the preview).
                    .webViewContentBackground(.hidden)
                    #endif
            } else {
                ProgressView()
            }
        }
        .accessibilityLabel("Diagram")
        .accessibilityIdentifier("terminal-diagram")
        .task(id: source) { render() }
    }

    /// The Markdown a diagram is, alone: its source in a ` ```mermaid ` fence.
    static func markdown(for source: String) -> String {
        "```mermaid\n\(source)\n```\n"
    }

    /// The preview's page for that Markdown, with the diagram centred and as large as the view
    /// allows: Mermaid draws at its own size, a small drawing at the top of a large page.
    static func page(for source: String) -> String {
        let page = GlassEditorPreviewPage.page(for: .markdown, text: markdown(for: source))
        let fit = """
        <style>
        html, body { height: 100%; margin: 0; }
        article.markdown { box-sizing: border-box; min-height: 100%; max-width: none; margin: 0; padding: 20px;
          display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .mermaid { width: 100%; display: flex; justify-content: center; }
        .mermaid svg { width: 100% !important; max-width: 100% !important; height: auto; max-height: calc(100vh - 40px); }
        </style>
        """
        guard let head = page.range(of: "</head>") else { return page }
        var fitted = page
        fitted.insert(contentsOf: fit, at: head.lowerBound)
        return fitted
    }

    private func render() {
        let current = page ?? makePage()
        page = current
        _ = current.load(html: Self.page(for: source), baseURL: GlassEditorPreviewPage.baseURL(forDocumentAt: nil))
    }

    private func makePage() -> WebPage {
        var configuration = WebPage.Configuration()
        // The app's two scripts from the bundle; nothing beside the page to read.
        let handler = GlassEditorPreviewSchemeHandler(root: "/") { _ in throw URLError(.fileDoesNotExist) }
        configuration.urlSchemeHandlers[URLScheme(GlassEditorPreviewPage.scheme)!] = handler
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        let open = openURL
        return WebPage(configuration: configuration, navigationDecider: GlassEditorPreviewNavigation { open($0) })
    }
}
