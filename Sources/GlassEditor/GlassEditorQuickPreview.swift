//
//  GlassEditorQuickPreview.swift
//  Glass Power Tools — GlassEditor
//
//  A file on this Mac, read-only, as the editor would preview it: the popover over a terminal when
//  its printed path is looked at (the owner, 2026-10-16: "display that image in a popover over the
//  terminal? or markdown, or any of the file types supported by our Editor").
//
//  **What it is comes from its bytes, not its name** (the owner, 2026-10-16: "We should check the
//  .output file type/mime types and allow edit, or preview where appropriate"). Quick Look goes by
//  the extension, and a log saved as `.output` came up as a blank document icon. The editor's own
//  check (`GlassEditorFileKind`, the bytes win) decides:
//  - Markdown (with its Mermaid diagrams), HTML, SVG and delimited tables: the editor's preview.
//  - Any other text, whatever it is called: in the editor's own text view, read-only, highlighted
//    as the editor highlights its language (the owner, 2026-10-16: "I just previewed a .swift file
//    and it was plain text, not formatted/highlighted"); plain only where the editor won't open it.
//  - Pictures, PDFs, video and audio: Quick Look, in the one view the editor keeps safe.
//  - Anything else: what it is, and its size; Open in Editor is beside it.
//

#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GlassEditorCore
import GlassEditorUI

public struct GlassEditorQuickPreview: View {
    let url: URL

    @State private var shown: Shown?
    @Environment(\.colorScheme) private var colorScheme

    public init(url: URL) {
        self.url = url
    }

    /// How much of a text file is shown: a long log's first pages, said to be its first.
    static let textLimit = 256 * 1024

    enum Shown {
        case preview(GlassEditorDocument, GlassEditorPreviewKind)
        /// Text in the editor's view, highlighted for its language, not to be changed here.
        case code(GlassEditorDocument)
        case text(String, size: UInt64)
        /// A picture whose name doesn't say so: Quick Look would go by the name.
        case image(NSImage)
        case quickLook
        case nothing(GlassEditorFileKind, size: UInt64)
    }

    public var body: some View {
        Group {
            switch shown {
            case .preview(let document, let kind):
                GlassEditorPreviewPane(document: document, kind: kind, access: GlassEditorLocalFileAccess(),
                                       root: url.deletingLastPathComponent().path)
            case .code(let document):
                GlassEditorView(model: document.model)
                    .onAppear { document.model.theme = Self.theme(for: colorScheme) }
                    .onChange(of: colorScheme) { _, scheme in document.model.theme = Self.theme(for: scheme) }
            case .text(let text, let size):
                textView(text, size: size)
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            case .quickLook:
                // One view for one file, as everywhere Quick Look is shown (`GlassQuickLookView`).
                GlassQuickLookView(url: url).id(url)
            case .nothing(let kind, let size):
                ContentUnavailableView {
                    Label("No Preview", systemImage: "doc")
                } description: {
                    Text("A \(kind == .binary ? "binary" : kind.rawValue) file, \(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)).")
                }
            case nil:
                ProgressView()
            }
        }
        .task(id: url) { shown = await Self.decide(url) }
    }

    private func textView(_ text: String, size: UInt64) -> some View {
        VStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            if size > UInt64(Self.textLimit) {
                Divider()
                Text("The first \(ByteCountFormatter.string(fromByteCount: Int64(Self.textLimit), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)). Open it in the editor for all of it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    /// The editor's palette for the appearance, as its windows follow it (`GlassEditorPreferences`).
    static func theme(for scheme: ColorScheme) -> EditorTheme {
        scheme == .dark ? .glassDark : .glassLight
    }

    /// What `url` is, read from its first bytes, and how to show it.
    static func decide(_ url: URL) async -> Shown {
        let name = url.lastPathComponent
        guard let head = try? await GlassEditorLocalFileAccess.head(atPath: url.path, length: textLimit) else {
            return .quickLook
        }
        let kind = GlassEditorFileKind.classify(name: name, prefix: head.head.prefix(GlassEditorFileKind.sniffLength))
        switch kind {
        case .text:
            if let document = try? await GlassEditorDocument.open(path: url.path, through: GlassEditorLocalFileAccess(),
                                                                  asText: true) {
                if let previewKind = GlassEditorPreviewKind.kind(language: LanguageID.forFileExtension(url.pathExtension),
                                                                 fileName: name) {
                    return .preview(document, previewKind)
                }
                // Looked at, not changed: Open in Editor is beside it for that.
                document.model.configuration.isEditable = false
                return .code(document)
            }
            // Cut short at a line's end, so a character cut in half can't turn the rest to Latin-1.
            var bytes = head.head
            if head.size > UInt64(bytes.count), let end = bytes.lastIndex(of: 0x0A) {
                bytes = bytes.prefix(through: end)
            }
            guard let decoded = try? EncodingDetector.decode(bytes) else { return .nothing(.binary, size: head.size) }
            return .text(decoded.content, size: head.size)
        case .image:
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) != true,
               let image = NSImage(contentsOf: url) {
                return .image(image)
            }
            return .quickLook
        case .pdf, .video, .audio:
            return .quickLook
        case .binary:
            return .nothing(.binary, size: head.size)
        }
    }
}
#endif
