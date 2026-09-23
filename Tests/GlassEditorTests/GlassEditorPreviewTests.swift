import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditor

/// Preview for text with a picture (2026-09-23). Pure parts: which files, the mode cycle, the page
/// and its policy (D35), what the page may fetch, and CSV.
@Suite("Preview")
struct GlassEditorPreviewTests {
    @Test("Markdown, HTML, SVG and CSV/TSV offer Preview; everything else does not")
    func kinds() {
        #expect(GlassEditorPreviewKind.kind(language: .markdown, fileName: "README.md") == .markdown)
        #expect(GlassEditorPreviewKind.kind(language: .html, fileName: "index.html") == .html)
        #expect(GlassEditorPreviewKind.kind(language: .xml, fileName: "icon.svg") == .svg)
        #expect(GlassEditorPreviewKind.kind(language: .plaintext, fileName: "data.csv") == .table(delimiter: ","))
        #expect(GlassEditorPreviewKind.kind(language: .plaintext, fileName: "data.tsv") == .table(delimiter: "\t"))
        #expect(GlassEditorPreviewKind.kind(language: .swift, fileName: "main.swift") == nil)
        #expect(GlassEditorPreviewKind.kind(language: .plaintext, fileName: nil) == nil)
    }

    @Test("One button: text, beside, alone, text — and a toggle where there is no room beside")
    func modes() {
        #expect(GlassEditorPreviewMode.text.next(roomBeside: true) == .beside)
        #expect(GlassEditorPreviewMode.beside.next(roomBeside: true) == .previewOnly)
        #expect(GlassEditorPreviewMode.previewOnly.next(roomBeside: true) == .text)
        #expect(GlassEditorPreviewMode.text.next(roomBeside: false) == .previewOnly)
        #expect(GlassEditorPreviewMode.previewOnly.next(roomBeside: false) == .text)
    }

    @Test("Markdown renders tables, task lists and Mermaid fences, and only the app's scripts may run")
    func markdownPage() {
        let page = GlassEditorPreviewPage.markdown("""
        # Title

        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done

        ```mermaid
        graph TD; A-->B
        ```

        <script>alert(1)</script>
        """)
        #expect(page.contains("<table>"))
        #expect(page.contains("type=\"checkbox\""))
        #expect(page.contains("class=\"language-mermaid\""))
        #expect(page.contains("glass-preview://app/mermaid.min.js"))
        #expect(page.contains("script-src glass-preview://app/"), "scripts only from the app's own host")
        #expect(page.contains("default-src 'none'"), "nothing from the network")
        #expect(!page.contains("script-src 'unsafe-inline'"), "the file's own <script> cannot run")
    }

    @Test("HTML and SVG previews allow no script at all")
    func htmlAndSVGHaveNoScripts() {
        let html = GlassEditorPreviewPage.html("<html><head><title>x</title></head><body>hi</body></html>")
        #expect(html.contains("<head><meta http-equiv=\"Content-Security-Policy\""), "the policy leads the head")
        #expect(html.contains("script-src 'none'"))
        #expect(GlassEditorPreviewPage.html("<p>fragment</p>").hasPrefix("<meta http-equiv=\"Content-Security-Policy\""))
        let svg = GlassEditorPreviewPage.svg("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>")
        #expect(svg.contains("data:image/svg+xml;base64,"), "drawn as an image, which never runs its scripts")
        #expect(svg.contains("script-src 'none'"))
    }

    @Test("A preview fetches only the app's two scripts and files under its root, and never code")
    func resources() {
        let root = "/srv/app"
        func resolve(_ string: String) -> GlassEditorPreviewResources.Target? {
            GlassEditorPreviewResources.resolve(URL(string: string)!, root: root)
        }
        #expect(resolve("glass-preview://app/mermaid.min.js") == .bundled("mermaid.min.js"))
        #expect(resolve("glass-preview://app/other.js") == nil)
        #expect(resolve("glass-preview://file/srv/app/docs/diagram.png") == .file("/srv/app/docs/diagram.png"))
        #expect(resolve("glass-preview://file/srv/app/docs/../img/a.png") == .file("/srv/app/img/a.png"))
        #expect(resolve("glass-preview://file/srv/app/../../etc/passwd") == nil, "escaping the root by ..")
        #expect(resolve("glass-preview://file/srv/application/a.png") == nil, "a sibling sharing the prefix")
        #expect(resolve("glass-preview://file/srv/app/evil.js") == nil, "a server's script cannot be run")
        #expect(resolve("glass-preview://file/srv/app/page.html") == nil)
        #expect(resolve("https://example.com/a.png") == nil)
        #expect(GlassEditorPreviewPage.baseURL(forDocumentAt: "/srv/app/docs/README.md").absoluteString
                == "glass-preview://file/srv/app/docs/")
    }

    @Test("CSV: quotes, doubled quotes, delimiters and newlines inside quotes, CRLF, blank lines, TSV")
    func csv() {
        let parsed = GlassEditorDelimitedText.parse("name,note\r\n\"Doe, Jane\",\"said \"\"hi\"\"\"\r\n\r\nBob,\"two\nlines\"\n")
        #expect(parsed.rows == [["name", "note"], ["Doe, Jane", "said \"hi\""], ["Bob", "two\nlines"]])
        #expect(!parsed.truncated)
        #expect(GlassEditorDelimitedText.parse("a\tb\n1\t2", delimiter: "\t").rows == [["a", "b"], ["1", "2"]])
        #expect(GlassEditorDelimitedText.parse("a,,c\n").rows == [["a", "", "c"]], "an empty field is a field")
        let long = GlassEditorDelimitedText.parse((0..<50).map(String.init).joined(separator: "\n"), rowLimit: 10)
        #expect(long.rows.count == 10 && long.truncated)
    }

    @Test("A first row of words is a header; one with numbers or gaps is data")
    func header() {
        #expect(GlassEditorDelimitedText.firstRowIsHeader([["name", "age"], ["Jane", "40"]]))
        #expect(!GlassEditorDelimitedText.firstRowIsHeader([["1", "2"], ["3", "4"]]))
        #expect(!GlassEditorDelimitedText.firstRowIsHeader([["name", ""], ["Jane", "40"]]))
    }
}
