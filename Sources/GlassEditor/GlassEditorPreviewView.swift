//
//  GlassEditorPreviewView.swift
//  Glass Power Tools — GlassEditor
//
//  The preview pane: a web page for Markdown, HTML and SVG, a native table for CSV and TSV.
//  Re-rendered from the editor's text — not the saved file — a moment after typing stops.
//  The pure half (the page, the policy, the resource rule, the CSV parse) is
//  `GlassEditorPreview.swift`; this is the half that needs a screen.
//

import SwiftUI
import WebKit
import GlassEditorCore

struct GlassEditorPreviewPane: View {
    let document: GlassEditorDocument
    let kind: GlassEditorPreviewKind
    let access: any GlassEditorFileAccess
    /// What the preview may read beside the file: its project, or its folder.
    let root: String

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage?
    @State private var table = GlassEditorDelimitedText.Parsed(rows: [], truncated: false)

    var body: some View {
        Group {
            if case .table = kind {
                GlassEditorTableView(parsed: table)
            } else if let page {
                // **None of the window's insets.** A web view whose edge lies on the safe area's edge
                // inherits the inset beyond it, and WebKit lays the page out inside its insets. On
                // the iPhone Duo, iOS keeps a column at the right of each display for the time and
                // the toolbar, so a preview beside it was laid out 83 points narrower than its pane:
                // the page clipped, the rest of the pane empty (2026-10-18, measured with the page's
                // `innerWidth`: 179 in a 262-point pane). Ignoring the safe area and padding back
                // brought the inset back with the edge; one point short of that edge, there is none
                // (`innerWidth` 262). The point is the window's glass, as the page's background is.
                GeometryReader { geometry in
                    WebView(page)
                        #if os(visionOS)
                        // The page asks for a transparent background so it sits on the window's own
                        // surface; on Vision Pro the web view painted an opaque black slab behind it
                        // anyway, a dark hole in a glass window (2026-10-09, simulator). This is the
                        // web view's own switch for that.
                        .webViewContentBackground(.hidden)
                        #endif
                        .padding(.leading, geometry.safeAreaInsets.leading > 0 ? 1 : 0)
                        .padding(.trailing, geometry.safeAreaInsets.trailing > 0 ? 1 : 0)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("editor-preview")
        // The text as it is now, a moment after the last keystroke: live, without re-rendering a
        // diagram on every character.
        .task(id: document.model.revision) {
            if page != nil || !table.rows.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            render()
        }
    }

    private func render() {
        let text = document.model.text
        if case .table(let delimiter) = kind {
            table = GlassEditorDelimitedText.parse(text, delimiter: delimiter)
            return
        }
        let current = page ?? makePage()
        page = current
        let base = GlassEditorPreviewPage.baseURL(forDocumentAt: document.path)
        _ = current.load(html: GlassEditorPreviewPage.page(for: kind, text: text), baseURL: base)
    }

    private func makePage() -> WebPage {
        var configuration = WebPage.Configuration()
        let fetch = access
        let handler = GlassEditorPreviewSchemeHandler(root: root) { path in try await fetch.read(path) }
        configuration.urlSchemeHandlers[URLScheme(GlassEditorPreviewPage.scheme)!] = handler
        // D35: Markdown runs the bundled Mermaid and nothing else (the page's policy names the
        // app's host); HTML and SVG run nothing at all.
        configuration.defaultNavigationPreferences.allowsContentJavaScript = (kind == .markdown)
        let open = openURL
        return WebPage(configuration: configuration,
                       navigationDecider: GlassEditorPreviewNavigation { open($0) })
    }
}

/// The preview never navigates away from its own page. A link to the web opens in the browser;
/// anything else is refused.
struct GlassEditorPreviewNavigation: WebPage.NavigationDeciding {
    let openExternally: @MainActor (URL) -> Void

    mutating func decidePolicy(for action: WebPage.NavigationAction,
                               preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == GlassEditorPreviewPage.scheme || url.scheme == "about" { return .allow }
        if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" { openExternally(url) }
        return .cancel
    }
}

/// Answers `glass-preview:` requests: the app's two scripts from the bundle, the file's
/// neighbours through the document's own access — the same SFTP connection for a file on a remote server.
struct GlassEditorPreviewSchemeHandler: URLSchemeHandler {
    let root: String
    let read: @MainActor (String) async throws -> Data

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        let root = root, read = read
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    guard let url = request.url,
                          let target = GlassEditorPreviewResources.resolve(url, root: root) else {
                        throw URLError(.noPermissionsToReadFile)
                    }
                    let data: Data
                    let mime: String
                    switch target {
                    case .bundled(let name):
                        let folder = name == "mermaid.min.js" ? "Mermaid" : "Preview"
                        guard let file = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: folder) else {
                            throw URLError(.fileDoesNotExist)
                        }
                        data = try Data(contentsOf: file)
                        mime = "text/javascript"
                    case .file(let path):
                        data = try await read(path)
                        mime = GlassEditorPreviewResources.mimeType(forPath: path)
                    }
                    continuation.yield(.response(URLResponse(url: url, mimeType: mime,
                                                             expectedContentLength: data.count,
                                                             textEncodingName: nil)))
                    continuation.yield(.data(data))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// CSV and TSV as a table: a header row when the first row reads as one, lettered columns when it
/// does not, sortable by clicking a header, and a line saying so when rows were left out.
struct GlassEditorTableView: View {
    let parsed: GlassEditorDelimitedText.Parsed
    @State private var sortColumn: Int?
    @State private var ascending = true

    private var hasHeader: Bool { GlassEditorDelimitedText.firstRowIsHeader(parsed.rows) }
    private var columnCount: Int { parsed.rows.map(\.count).max() ?? 0 }
    private var headers: [String] {
        let named = hasHeader ? parsed.rows.first ?? [] : []
        return (0..<columnCount).map { $0 < named.count ? named[$0] : Self.letters($0) }
    }
    private var body_rows: [[String]] {
        let rows = Array(parsed.rows.dropFirst(hasHeader ? 1 : 0))
        guard let column = sortColumn else { return rows }
        return rows.sorted {
            let a = column < $0.count ? $0[column] : "", b = column < $1.count ? $1[column] : ""
            let order: ComparisonResult = if let x = Double(a), let y = Double(b) {
                x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
            } else { a.localizedStandardCompare(b) }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    private var widths: [CGFloat] {
        (0..<columnCount).map { column in
            let longest = ([headers[column]] + parsed.rows.prefix(200).map { column < $0.count ? $0[column] : "" })
                .map { $0.count }.max() ?? 4
            return CGFloat(min(max(longest, 4), 40)) * 8 + 20
        }
    }

    var body: some View {
        if parsed.rows.isEmpty {
            ContentUnavailableView("No Rows", systemImage: "tablecells")
        } else {
            let widths = widths
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(body_rows.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 0) {
                                ForEach(0..<columnCount, id: \.self) { column in
                                    Text(column < row.count ? row[column] : "")
                                        .lineLimit(1)
                                        .frame(width: widths[column], alignment: .leading)
                                        .padding(.horizontal, 6)
                                }
                            }
                            .padding(.vertical, 3)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.08))
                            .textSelection(.enabled)
                        }
                        if parsed.truncated {
                            Text("Showing the first \(GlassEditorDelimitedText.displayRowLimit.formatted()) rows.")
                                .font(.caption).foregroundStyle(.secondary).padding(8)
                        }
                    } header: {
                        HStack(spacing: 0) {
                            ForEach(0..<columnCount, id: \.self) { column in
                                Button {
                                    if sortColumn == column { ascending.toggle() } else { sortColumn = column; ascending = true }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(headers[column]).bold().lineLimit(1)
                                        if sortColumn == column {
                                            Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.caption2)
                                        }
                                    }
                                    .frame(width: widths[column], alignment: .leading)
                                    .padding(.horizontal, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 5)
                        .background(.bar)
                    }
                }
                .font(.system(.callout, design: .monospaced))
            }
            .accessibilityIdentifier("editor-preview-table")
        }
    }

    /// A, B, … Z, AA, AB — a spreadsheet's column names.
    static func letters(_ index: Int) -> String {
        var n = index, name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + n % 26))) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }
}
