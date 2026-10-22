import Testing
@testable import GlassTerminalEmulator

/// Mermaid diagrams a terminal shows as text (2026-10-21): found by their first line, followed while
/// their lines carry on, put back together where the terminal wrapped them.
@Suite("Diagrams in a terminal")
struct TerminalDiagramsTests {
    private func rows(_ lines: String...) -> [SwiftTermScreenRow] { lines.map { SwiftTermScreenRow($0) } }

    @Test("a diagram a program printed under its own line: its source, its rows, its mark after its first line")
    func printedUnderProse() {
        let screen = rows(
            "⏺ This Mermaid diagram uses features the terminal renderer doesn't support.",
            "  flowchart LR",
            "      A[Configured files<br/>and a ready sheet] --> B[Inspector]",
            "      B -->|Authorized API| C[Client]",
            "      C --> D[Shared builder]",
            "",
            "> ",
        )
        let found = TerminalDiagramFinder.diagrams(in: screen)
        #expect(found.count == 1)
        #expect(found.first?.source == """
            flowchart LR
                A[Configured files<br/>and a ready sheet] --> B[Inspector]
                B -->|Authorized API| C[Client]
                C --> D[Shared builder]
            """)
        #expect(found.first?.rows == 1...4)
        #expect(found.first?.markColumn == "  flowchart LR".count + 1)
    }

    @Test("a line the terminal wrapped is one line of the diagram again")
    func wrappedRows() {
        let screen = [
            SwiftTermScreenRow("graph TD"),
            SwiftTermScreenRow("  A[A long label that the terminal"),
            SwiftTermScreenRow(" wrapped] --> B", continuesAbove: true),
            SwiftTermScreenRow("$ "),
        ]
        let found = TerminalDiagramFinder.diagrams(in: screen)
        #expect(found.first?.source == "graph TD\n  A[A long label that the terminal wrapped] --> B")
        #expect(found.first?.rows == 0...2)
    }

    @Test("a fenced block is its lines between the fences")
    func fenced() {
        let found = TerminalDiagramFinder.diagrams(in: rows(
            "```mermaid", "sequenceDiagram", "  Alice->>Bob: Hello", "```", "done"))
        #expect(found.first?.source == "sequenceDiagram\n  Alice->>Bob: Hello")
        #expect(found.first?.rows == 0...3)
        #expect(TerminalDiagramFinder.diagrams(in: rows("```mermaid", "graph TD", "  A --> B")).isEmpty,
                "a fence that doesn't close on screen isn't a diagram yet")
    }

    @Test("at its own indentation it carries on while lines read as Mermaid, and stops at a prompt")
    func sameIndentation() {
        let found = TerminalDiagramFinder.diagrams(in: rows(
            "sequenceDiagram", "participant Alice", "Alice->>Bob: Hi", "Note over Bob: thinks", "ann@alpha:~$ ls"))
        #expect(found.first?.source == "sequenceDiagram\nparticipant Alice\nAlice->>Bob: Hi\nNote over Bob: thinks")
        #expect(found.first?.rows == 0...3)
    }

    @Test("a blank line inside carries on only into lines indented further")
    func blankLines() {
        let found = TerminalDiagramFinder.diagrams(in: rows("  flowchart TB", "    A --> B", "", "    B --> C", "", "  Next paragraph"))
        #expect(found.first?.source == "flowchart TB\n  A --> B\n  B --> C")
    }

    @Test("prose that mentions a graph, or a first line with nothing under it, isn't a diagram")
    func notDiagrams() {
        #expect(TerminalDiagramFinder.diagrams(in: rows("graph of the build times", "  is below")).isEmpty)
        #expect(TerminalDiagramFinder.diagrams(in: rows("flowchart LR", "$ ")).isEmpty)
        #expect(TerminalDiagramFinder.diagrams(in: rows("pie chart of results:", "nothing here")).isEmpty)
    }

    @Test("two diagrams are two marks, each where its own begins")
    func two() {
        let found = TerminalDiagramFinder.diagrams(in: rows("graph LR", "  A --> B", "text", "pie title Pets", "  \"Dogs\" : 3"))
        #expect(found.map(\.rows) == [0...1, 3...4])
        #expect(Set(found.map(\.id)).count == 2)
    }
}
