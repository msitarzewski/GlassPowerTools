//
//  GlassEditorQuickPreview.swift
//  Glass Power Tools — GlassEditor
//
//  A file on this Mac, read-only, as the editor would preview it: the popover over a terminal when
//  its printed path is looked at (the owner, 2026-10-16: "display that image in a popover over the
//  terminal? or markdown, or any of the file types supported by our Editor"). Markdown (with its
//  Mermaid diagrams), HTML, SVG and delimited tables as the editor's own preview draws them
//  (`GlassEditorPreviewPane`); anything else as Quick Look shows it — pictures, PDFs, video, audio,
//  code and text — in the one Quick Look view the editor already keeps safe (`GlassQuickLookView`).
//

#if os(macOS)
import SwiftUI
import GlassEditorCore

public struct GlassEditorQuickPreview: View {
    let url: URL

    @State private var document: GlassEditorDocument?
    @State private var kind: GlassEditorPreviewKind?
    @State private var decided = false

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        Group {
            if let document, let kind {
                GlassEditorPreviewPane(document: document, kind: kind, access: GlassEditorLocalFileAccess(),
                                       root: url.deletingLastPathComponent().path)
            } else if decided {
                // One view for one file, as everywhere Quick Look is shown (`GlassQuickLookView`).
                GlassQuickLookView(url: url).id(url)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            let language = LanguageID.forFileExtension(url.pathExtension)
            if let previewKind = GlassEditorPreviewKind.kind(language: language, fileName: url.lastPathComponent),
               let opened = try? await GlassEditorDocument.open(path: url.path, through: GlassEditorLocalFileAccess(),
                                                                asText: true) {
                document = opened
                kind = previewKind
            }
            decided = true
        }
    }
}
#endif
