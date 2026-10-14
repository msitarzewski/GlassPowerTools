//
//  GlassEditorMarkdownHTML.swift
//  Glass Power Tools — GlassEditor
//
//  Markdown to the preview's HTML, with everything that is text escaped as text.
//
//  The preview used swift-markdown's `HTMLFormatter`, which escapes nothing: inline code, code
//  blocks, plain text, headings and link and image attributes all went into the page as written.
//  A note that mentioned `<embed src=…>` in backticks became a real `<embed>`, which WebKit drew
//  as a grey "Blocked Plug-in" pill (the owner, 2026-10-14, previewing a project's notes); an
//  `&lt;object&gt;` in prose, decoded by the parser, became a tag the same way; a quote in a link
//  ended its `href`. Here text is text. Raw HTML — an `HTMLBlock`, `InlineHTML` — still passes
//  through as written, as Markdown means it to, and the page's policy (D35) is what keeps any
//  script in it from running.
//
//  Otherwise the output is `HTMLFormatter`'s (swift-markdown, Apache-2.0 with the Runtime Library
//  Exception, in THIRD-PARTY-NOTICES), element for element, and the walker follows its shape, so the
//  stylesheet and the Mermaid script (`pre > code.language-mermaid`, read with `textContent`) are
//  unchanged; headings keep their inline markup rather than flattening to plain text, and images
//  carry their alt text.
//

import Foundation
import Markdown

struct GlassEditorMarkdownHTML: MarkupWalker {
    private(set) var result = ""
    private var inTableHead = false
    private var tableColumnAlignments: [Table.ColumnAlignment?]?
    private var currentTableColumn = 0

    static func format(_ text: String) -> String {
        var walker = GlassEditorMarkdownHTML()
        walker.visit(Document(parsing: text))
        return walker.result
    }

    /// Text as text: `&`, `<` and `>` always; `"` too inside an attribute's quotes.
    static func escaped(_ text: String, attribute: Bool = false) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Blocks

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language.map { " class=\"language-\(Self.escaped($0, attribute: true))\"" } ?? ""
        result += "<pre><code\(language)>\(Self.escaped(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        result += "<h\(heading.level)>"
        descendInto(heading)
        result += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr />\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
    }

    mutating func visitListItem(_ listItem: ListItem) {
        result += "<li>"
        if let checkbox = listItem.checkbox {
            result += "<input type=\"checkbox\" disabled=\"\"\(checkbox == .checked ? " checked=\"\"" : "") /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        result += orderedList.startIndex != 1 ? "<ol start=\"\(orderedList.startIndex)\">\n" : "<ol>\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitTable(_ table: Table) {
        result += "<table>\n"
        tableColumnAlignments = table.columnAlignments
        descendInto(table)
        tableColumnAlignments = nil
        result += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        result += "<thead>\n<tr>\n"
        inTableHead = true
        currentTableColumn = 0
        descendInto(tableHead)
        inTableHead = false
        result += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard !tableBody.isEmpty else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        result += "<tr>\n"
        currentTableColumn = 0
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count,
              tableCell.colspan > 0, tableCell.rowspan > 0 else { return }
        let element = inTableHead ? "th" : "td"
        result += "<\(element)"
        if let alignment = alignments[currentTableColumn] { result += " align=\"\(alignment)\"" }
        currentTableColumn += 1
        if tableCell.rowspan > 1 { result += " rowspan=\"\(tableCell.rowspan)\"" }
        if tableCell.colspan > 1 { result += " colspan=\"\(tableCell.colspan)\"" }
        result += ">"
        descendInto(tableCell)
        result += "</\(element)>\n"
    }

    // MARK: Inlines

    private mutating func printInline(tag: String, _ content: Markup) {
        result += "<\(tag)>"
        descendInto(content)
        result += "</\(tag)>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(Self.escaped(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) { printInline(tag: "em", emphasis) }
    mutating func visitStrong(_ strong: Strong) { printInline(tag: "strong", strong) }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { printInline(tag: "del", strikethrough) }

    mutating func visitImage(_ image: Image) {
        result += "<img"
        if let source = image.source, !source.isEmpty { result += " src=\"\(Self.escaped(source, attribute: true))\"" }
        result += " alt=\"\(Self.escaped(image.plainText, attribute: true))\""
        if let title = image.title, !title.isEmpty { result += " title=\"\(Self.escaped(title, attribute: true))\"" }
        result += " />"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += inlineHTML.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br />\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += "\n" }

    mutating func visitLink(_ link: Link) {
        result += "<a"
        if let destination = link.destination { result += " href=\"\(Self.escaped(destination, attribute: true))\"" }
        if let title = link.title, !title.isEmpty { result += " title=\"\(Self.escaped(title, attribute: true))\"" }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitText(_ text: Text) {
        result += Self.escaped(text.string)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        if let destination = symbolLink.destination { result += "<code>\(Self.escaped(destination))</code>" }
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) {
        result += "<span data-attributes=\"\(Self.escaped(attributes.attributes, attribute: true))\">"
        descendInto(attributes)
        result += "</span>"
    }
}
