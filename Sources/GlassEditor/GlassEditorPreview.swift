//
//  GlassEditorPreview.swift
//  Glass Power Tools — GlassEditor
//
//  Preview for text that has a picture: Markdown (with Mermaid), HTML, SVG, CSV. VS Code's
//  shape (2026-09-23: *"The things that are text and visual (markdown) should have a preview
//  button like VSCode and its offspring"*). Plan: tasks/2026-09/2026-09-23_viewers-and-preview.md.
//
//  Everything here is pure — the page a preview loads, the rule for what it may fetch, the CSV
//  parse — so it is tested without a web view. The safety rule is D35: a preview page runs no
//  script but the bundled Mermaid, reaches no network, and gets every resource through one URL
//  scheme the app answers itself, reading through the document's own file access.
//

import Foundation
import GlassEditorCore
import Markdown
import UniformTypeIdentifiers

/// Which kind of preview a document offers, if any.
public enum GlassEditorPreviewKind: Equatable, Sendable {
    case markdown, html, svg
    case table(delimiter: Character)

    public static func kind(language: LanguageID, fileName: String?) -> GlassEditorPreviewKind? {
        switch (fileName.map { ($0 as NSString).pathExtension.lowercased() } ?? "") {
        case "svg": return .svg
        case "csv": return .table(delimiter: ",")
        case "tsv", "tab": return .table(delimiter: "\t")
        default: break
        }
        switch language {
        case .markdown: return .markdown
        case .html: return .html
        default: return nil
        }
    }
}

/// How the detail shows a document that has a preview: VS Code's three states.
public enum GlassEditorPreviewMode: Equatable, Sendable {
    case text, beside, previewOnly

    /// One button, three presses: text → beside → preview alone → text. Where there is no room
    /// beside (a phone), it is a toggle.
    public func next(roomBeside: Bool) -> GlassEditorPreviewMode {
        switch self {
        case .text: roomBeside ? .beside : .previewOnly
        case .beside: .previewOnly
        case .previewOnly: .text
        }
    }
}

public enum GlassEditorPreviewPage {
    /// The scheme every preview resource travels through. `app` serves the bundled scripts;
    /// `file` serves the document's neighbours through its file access.
    public static let scheme = "glass-preview"
    static let appHost = "app"
    static let fileHost = "file"

    /// Where a document's relative references resolve: its own folder, on the preview scheme.
    public static func baseURL(forDocumentAt path: String?) -> URL {
        let folder = path.map { ($0 as NSString).deletingLastPathComponent } ?? "/"
        var components = URLComponents()
        components.scheme = scheme
        components.host = fileHost
        components.path = folder.hasSuffix("/") ? folder : folder + "/"
        return components.url ?? URL(string: "\(scheme)://\(fileHost)/")!
    }

    /// The page for a kind, from the editor's current text.
    public static func page(for kind: GlassEditorPreviewKind, text: String) -> String {
        switch kind {
        case .markdown: markdown(text)
        case .html: html(text)
        case .svg: svg(text)
        case .table: ""   // drawn natively, not as a page
        }
    }

    /// GitHub-flavoured Markdown, with ` ```mermaid ` fences drawn by the bundled Mermaid.
    /// Text is escaped as text (`GlassEditorMarkdownHTML`); raw HTML in the Markdown passes through,
    /// which is why the policy is what keeps its scripts from running: `script-src` names only the
    /// app's own.
    public static func markdown(_ text: String) -> String {
        let body = GlassEditorMarkdownHTML.format(text)
        let scripts = """
        <script src="\(scheme)://\(appHost)/mermaid.min.js"></script>
        <script src="\(scheme)://\(appHost)/glass-mermaid.js"></script>
        """
        return document(body: "<article class=\"markdown\">\(body)</article>\(scripts)",
                        scriptSource: "\(scheme)://\(appHost)/")
    }

    /// An HTML file as written, with scripts off: the page's own policy says none, and the web
    /// view's preferences say none again.
    public static func html(_ text: String) -> String {
        let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy(scriptSource: nil))\">"
        if let head = text.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            var page = text
            page.insert(contentsOf: policy, at: head.upperBound)
            return page
        }
        return policy + text
    }

    /// An SVG shown as an image: an `<img>` never runs the drawing's own scripts.
    public static func svg(_ text: String) -> String {
        let encoded = Data(text.utf8).base64EncodedString()
        return document(body: "<div class=\"svg\"><img alt=\"\" src=\"data:image/svg+xml;base64,\(encoded)\"></div>",
                        scriptSource: nil)
    }

    /// D35 as a header: nothing from the network, images and fonts from the preview scheme or
    /// inline, styles inline, and scripts only from `scriptSource` when one is named.
    static func contentSecurityPolicy(scriptSource: String?) -> String {
        [
            "default-src 'none'",
            "img-src \(scheme): data:",
            "media-src \(scheme):",
            "font-src \(scheme): data:",
            "style-src 'unsafe-inline'",
            "script-src \(scriptSource ?? "'none'")",
        ].joined(separator: "; ")
    }

    private static func document(body: String, scriptSource: String?) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy(scriptSource: scriptSource))">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(stylesheet)</style>
        </head><body>\(body)</body></html>
        """
    }

    /// One stylesheet, light and dark, sized like the rest of the app.
    static let stylesheet = """
    :root { color-scheme: light dark; --fg: #1d1d1f; --muted: #6e6e73; --rule: #d2d2d7; --code: #f5f5f7; --link: #0a64d6; }
    @media (prefers-color-scheme: dark) { :root { --fg: #f5f5f7; --muted: #a1a1a6; --rule: #3a3a3c; --code: #1c1c1e; --link: #4aa3ff; } }
    html { font: -apple-system-body; }
    body { margin: 0; padding: 24px 32px 48px; color: var(--fg); background: transparent; font-family: -apple-system, system-ui, sans-serif; line-height: 1.55; }
    article { max-width: 860px; margin: 0 auto; }
    h1, h2 { border-bottom: 1px solid var(--rule); padding-bottom: .3em; }
    a { color: var(--link); }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .92em; }
    code { background: var(--code); padding: .1em .35em; border-radius: 5px; }
    pre { background: var(--code); padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0; padding: 0 1em; color: var(--muted); border-left: 3px solid var(--rule); }
    table { border-collapse: collapse; margin: 1em 0; display: block; overflow-x: auto; }
    th, td { border: 1px solid var(--rule); padding: 6px 12px; }
    th { background: var(--code); }
    img { max-width: 100%; }
    li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.3em; }
    li > input[type=checkbox] { margin: 0 .45em 0 0; vertical-align: middle; }
    li > input[type=checkbox] + p { display: inline; margin: 0; }
    .mermaid { text-align: center; margin: 1em 0; }
    .mermaid-error { color: #d70015; font-size: .9em; }
    .svg { display: flex; justify-content: center; align-items: center; min-height: 80vh; }
    .svg img { max-width: 100%; max-height: 90vh; }
    """
}

/// What a preview may fetch through its scheme, and from where.
public enum GlassEditorPreviewResources {
    /// The bundled files the `app` host serves, by name.
    static let bundled: Set<String> = ["mermaid.min.js", "glass-mermaid.js"]

    /// Where a request goes: a bundled file, a path on the document's machine, or nowhere.
    public enum Target: Equatable {
        case bundled(String)
        case file(String)
    }

    /// Resolves a preview request. Refused: another scheme or host; a bundled name that is not
    /// one of ours; a file outside `root` (the project, or the document's folder when there is
    /// none), including by `..`; and anything a browser would run — a Markdown file must not be
    /// able to name a `.js` on the server and have it executed.
    public static func resolve(_ url: URL, root: String) -> Target? {
        guard url.scheme == GlassEditorPreviewPage.scheme else { return nil }
        switch url.host() {
        case GlassEditorPreviewPage.appHost:
            let name = url.lastPathComponent
            return bundled.contains(name) ? .bundled(name) : nil
        case GlassEditorPreviewPage.fileHost:
            let raw = url.path(percentEncoded: false)
            let normalized = (raw as NSString).standardizingPath
            let base = root.hasSuffix("/") ? String(root.dropLast()) : root
            guard normalized == base || normalized.hasPrefix(base + "/") else { return nil }
            let ext = (normalized as NSString).pathExtension.lowercased()
            guard !["js", "mjs", "cjs", "html", "htm", "xhtml", "wasm"].contains(ext) else { return nil }
            return .file(normalized)
        default:
            return nil
        }
    }

    /// The MIME type a served file declares, from its extension.
    public static func mimeType(forPath path: String) -> String {
        UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// RFC 4180 CSV (and TSV): quoted fields, doubled quotes, delimiters and newlines inside quotes,
/// CRLF or LF. Rows are capped for display so a million-line log does not become a million views.
public enum GlassEditorDelimitedText {
    public static let displayRowLimit = 10_000

    public struct Parsed: Equatable, Sendable {
        public var rows: [[String]]
        /// True when the file had more rows than were kept.
        public var truncated: Bool
    }

    public static func parse(_ text: String, delimiter: Character = ",",
                             rowLimit: Int = displayRowLimit) -> Parsed {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        func endRow() {
            row.append(field); field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }
        while let c = next() {
            if rows.count >= rowLimit { return Parsed(rows: rows, truncated: true) }
            if inQuotes {
                if c == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { inQuotes = false; pending = following }
                    } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                endRow()
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return Parsed(rows: rows, truncated: false)
    }

    /// Whether the first row reads as a header: every cell filled and none of them a number.
    /// Otherwise the columns are lettered like a spreadsheet's and the first row is data.
    public static func firstRowIsHeader(_ rows: [[String]]) -> Bool {
        guard let first = rows.first, !first.isEmpty else { return false }
        return first.allSatisfy {
            let cell = $0.trimmingCharacters(in: .whitespaces)
            return !cell.isEmpty && Double(cell) == nil
        }
    }
}
