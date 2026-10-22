//
//  TerminalDiagrams.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Mermaid diagrams a terminal shows as text, found so each can carry a mark beside it that opens
//  it drawn (the owner, 2026-10-21: "an inline diagram icon would be amazing"). A program that can't
//  draw a diagram in a terminal prints its source — Claude Code says "This Mermaid diagram uses
//  features the terminal renderer doesn't support" and prints it — and the text stays the
//  program's: nothing here writes into the terminal, so a program redrawing its screen loses
//  nothing. What is on screen is read again as output settles and as the terminal scrolls.
//
//  A diagram is found by its first line, Mermaid's own: `flowchart LR`, `sequenceDiagram` and the
//  rest, or a fenced block that says `mermaid`. Its lines follow it while they are indented further
//  (as a program sets a diagram under a line of prose), or, at its own indentation, while they read
//  as Mermaid statements; a blank line inside one ends it unless what follows is indented further.
//  A long line the terminal wrapped is put back together first.
//

import CoreGraphics
import Foundation
import Observation

/// One row of what a terminal shows, top to bottom: its text, and whether it carries on the row
/// above (a line longer than the terminal is wide, wrapped).
public struct SwiftTermScreenRow: Equatable, Sendable {
    public let text: String
    public let continuesAbove: Bool

    public init(_ text: String, continuesAbove: Bool = false) {
        self.text = text
        self.continuesAbove = continuesAbove
    }
}

/// A Mermaid diagram on screen: its source, and where its mark goes — just after its first line.
public struct TerminalDiagram: Identifiable, Equatable, Sendable {
    public let source: String
    /// The screen rows it spans, top to bottom.
    public let rows: ClosedRange<Int>
    /// The column just after its first line's text, where its mark goes.
    public let markColumn: Int

    /// The same diagram at the same place keeps its mark, and an open preview with it.
    public var id: String { "\(rows.lowerBound):\(source.hashValue)" }
}

public enum TerminalDiagramFinder {
    /// The diagrams in `rows`, top to bottom, at most `limit` of them.
    public static func diagrams(in rows: [SwiftTermScreenRow], limit: Int = 12) -> [TerminalDiagram] {
        let lines = logicalLines(rows)
        var found: [TerminalDiagram] = []
        var index = 0
        while index < lines.count, found.count < limit {
            let headerIndex = index
            guard let header = Header(lines[headerIndex].text) else {
                index += 1
                continue
            }
            let (body, next) = header.fenced ? fencedBody(lines, after: headerIndex)
                : indentedBody(lines, after: headerIndex, header: header)
            index = next
            guard let lastBody = body.last else { continue }
            let sourceLines = (header.fenced ? [] : [header.text]) + body.map { strip(lines[$0].text, header.indent) }
            let firstRow = lines[headerIndex].firstRow
            // A fenced block ends on its closing fence.
            let lastRow = lines[header.fenced ? next - 1 : lastBody].lastRow
            found.append(TerminalDiagram(source: sourceLines.joined(separator: "\n"), rows: firstRow...lastRow,
                                         markColumn: lines[headerIndex].text.count + 1))
        }
        return found
    }

    // MARK: - Lines

    struct Line {
        let text: String
        let firstRow: Int
        let lastRow: Int
    }

    /// Rows put back together where the terminal wrapped one line over several.
    static func logicalLines(_ rows: [SwiftTermScreenRow]) -> [Line] {
        var lines: [Line] = []
        for (row, screenRow) in rows.enumerated() {
            if screenRow.continuesAbove, let last = lines.last {
                lines[lines.count - 1] = Line(text: last.text + screenRow.text, firstRow: last.firstRow, lastRow: row)
            } else {
                lines.append(Line(text: screenRow.text, firstRow: row, lastRow: row))
            }
        }
        return lines
    }

    private static func indentation(_ text: String) -> Int {
        text.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func strip(_ text: String, _ indent: Int) -> String {
        String(text.dropFirst(min(indent, indentation(text))))
    }

    // MARK: - First lines

    /// Mermaid's diagram types, as a diagram's first word names them.
    static let diagramTypes: Set<String> = [
        "flowchart", "graph", "sequenceDiagram", "classDiagram", "classDiagram-v2", "stateDiagram",
        "stateDiagram-v2", "erDiagram", "journey", "gantt", "pie", "quadrantChart", "requirementDiagram",
        "gitGraph", "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment", "mindmap",
        "timeline", "zenuml", "sankey-beta", "xychart-beta", "block-beta", "packet-beta", "kanban",
        "architecture-beta", "radar-beta", "treemap-beta",
    ]
    static let directions: Set<String> = ["TB", "TD", "BT", "RL", "LR"]

    struct Header {
        let text: String
        let indent: Int
        let fenced: Bool

        init?(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            indent = TerminalDiagramFinder.indentation(line)
            if ["```mermaid", "~~~mermaid"].contains(trimmed.lowercased()) {
                text = trimmed
                fenced = true
                return
            }
            let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let first = words.first?.trimmingCharacters(in: CharacterSet(charactersIn: ";")),
                  TerminalDiagramFinder.diagramTypes.contains(first) else { return nil }
            // A flowchart's first line is its type and, at most, its direction: "graph" in a sentence
            // isn't one.
            if first == "graph" || first == "flowchart" {
                guard words.count == 1 || (words.count == 2
                    && TerminalDiagramFinder.directions.contains(words[1].trimmingCharacters(in: CharacterSet(charactersIn: ";")))) else {
                    return nil
                }
            }
            text = trimmed
            fenced = false
        }
    }

    // MARK: - Bodies

    /// A fenced block's lines, up to its closing fence; nothing when it never closes on screen.
    private static func fencedBody(_ lines: [Line], after header: Int) -> ([Int], Int) {
        var index = header + 1
        var body: [Int] = []
        while index < lines.count {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            if trimmed == "```" || trimmed == "~~~" { return (body, index + 1) }
            body.append(index)
            index += 1
        }
        return ([], index)
    }

    /// The lines after a diagram's first: indented further, or at its own indentation and reading
    /// as a statement. A blank line ends it unless the next is indented further still.
    private static func indentedBody(_ lines: [Line], after header: Int, header first: Header) -> ([Int], Int) {
        var body: [Int] = []
        var index = header + 1
        while index < lines.count {
            let text = lines[index].text
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let next = lines[(index + 1)...].first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
                      indentation(next.text) > first.indent, !body.isEmpty else { break }
                index += 1
                continue
            }
            let indent = indentation(text)
            if indent > first.indent || (indent == first.indent && readsAsStatement(text)) {
                body.append(index)
                index += 1
            } else {
                break
            }
        }
        // `index` may stand on a blank line skipped inside: the next search starts after the body.
        return (body, (body.last ?? header) + 1)
    }

    /// A line that reads as a Mermaid statement rather than prose or a prompt.
    static func readsAsStatement(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let arrows = ["-->", "---", "-.->", "==>", "->>", "-->>", "--x", "--o", "<--", "<|--", "*--", "o--", "..>", "-)", "||--", "}|", "|{"]
        if arrows.contains(where: trimmed.contains) { return true }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let keywords: Set<String> = ["subgraph", "end", "style", "classDef", "class", "click", "linkStyle", "participant",
                                     "actor", "note", "Note", "loop", "alt", "else", "opt", "par", "and", "rect",
                                     "critical", "break", "section", "title", "dateFormat", "axisFormat", "state",
                                     "direction", "accTitle:", "accDescr:"]
        return keywords.contains(first)
    }
}

/// The diagrams a terminal shows now, for the marks beside them: read again by the view that shows
/// the marks, so a change redraws those marks and nothing else.
@MainActor
@Observable
public final class SwiftTermDiagrams {
    public private(set) var found: [TerminalDiagram] = []
    /// One cell at the terminal's font, in points, to place the marks; zero before it is measured.
    public private(set) var cellSize: CGSize = .zero

    public init() {}

    func update(rows: [SwiftTermScreenRow], cellSize: CGSize?) {
        let diagrams = TerminalDiagramFinder.diagrams(in: rows)
        if diagrams != found { found = diagrams }
        let size = cellSize ?? .zero
        if size != self.cellSize { self.cellSize = size }
    }
}
