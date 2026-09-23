//
//  GlassEditorViewerView.swift
//  Glass Power Tools — GlassEditor
//
//  What a viewer document shows. The Mac uses Quick Look's embeddable preview, which covers
//  images, PDF, video and audio with the system's own zoom, paging and transport in one control.
//  iPhone, iPad and Vision Pro offer Quick Look only as a full-screen presenter, which does not
//  sit in a tab, so they get a native viewer per kind. Anything else is "not text", with its size
//  and a way to open it as text anyway.
//

import SwiftUI
import GlassEditorCore
#if os(macOS)
import Quartz
#else
import PDFKit
import AVKit
#endif

struct GlassEditorViewerView: View {
    let viewer: GlassEditorViewer
    let openAsText: () -> Void

    var body: some View {
        Group {
            switch viewer.kind {
            case .binary, .text:
                notText
            case .image, .pdf, .video, .audio:
                #if os(macOS)
                GlassQuickLookView(url: viewer.fileURL)
                #else
                touchViewer
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("editor-viewer-\(viewer.kind.rawValue)")
    }

    private var notText: some View {
        ContentUnavailableView {
            Label("This File Isn't Text", systemImage: "doc.questionmark")
        } description: {
            Text("\(viewer.fileURL.lastPathComponent) is \(viewer.sizeDescription) of data the editor can't show as text or as a picture.")
        } actions: {
            Button("Open as Text", action: openAsText)
                .accessibilityIdentifier("editor-viewer-open-as-text")
        }
    }

    #if !os(macOS)
    @ViewBuilder private var touchViewer: some View {
        switch viewer.kind {
        case .image: GlassZoomableImage(url: viewer.fileURL)
        case .pdf: GlassPDFView(url: viewer.fileURL)
        case .video, .audio: VideoPlayer(player: AVPlayer(url: viewer.fileURL))
        default: notText
        }
    }
    #endif
}

/// The symbol a viewer's tab carries.
extension GlassEditorFileKind {
    var symbolName: String {
        switch self {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .video: "film"
        case .audio: "waveform"
        case .binary: "doc.questionmark"
        case .text: "doc.text"
        }
    }
}

#if os(macOS)
/// Quick Look in a view. The preview item is replaced when the URL changes; the view is closed
/// when it goes, so a playing video stops with its tab.
private struct GlassQuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
#else
/// An image fitted to the tab, with pinch to zoom and a double tap between fit and twice size.
private struct GlassZoomableImage: View {
    let url: URL
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * zoom * pinch,
                               height: proxy.size.height * zoom * pinch)
                }
                .gesture(MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { zoom = min(8, max(1, zoom * $0.magnification)) })
                .onTapGesture(count: 2) { withAnimation { zoom = zoom > 1 ? 1 : 2 } }
            }
            .accessibilityLabel(url.lastPathComponent)
        } else {
            ContentUnavailableView("Can't Show This Image", systemImage: "photo.badge.exclamationmark",
                                   description: Text("\(url.lastPathComponent) isn't an image format this device can draw."))
        }
    }
}

private struct GlassPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif
