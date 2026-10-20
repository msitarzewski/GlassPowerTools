import Foundation
import Testing
@testable import GlassTerminal

/// Text a terminal program wrapped to fit its window, joined again before it is pasted (the owner,
/// 2026-10-19: copying from Claude "will 100% of the time break the text on new lines").
@Suite("A paste of wrapped text is joined again")
struct TerminalWrappedPasteTests {
    /// The owner's example, as copied: 134 columns, the second line padded to the margin.
    private let example = """
        • I found two separate routes: extracting and studying compiled CUDA kernels, and translating supported CUDA code to Metal. Both exist
          today. CuMetal still explicitly excludes the tensor-core instructions Nunchaku uses, so decompilation could help us understand a
          kernel, but making it fast on Apple hardware would still require a Metal implementation.
        """

    @Test("the owner's example becomes one line")
    func ownersExample() throws {
        let repair = try #require(TerminalWrappedPaste.repair(example))
        #expect(repair.text == "• I found two separate routes: extracting and studying compiled CUDA kernels, and translating supported CUDA code to Metal. Both exist today. CuMetal still explicitly excludes the tensor-core instructions Nunchaku uses, so decompilation could help us understand a kernel, but making it fast on Apple hardware would still require a Metal implementation.")
        #expect(repair.width == 134 && repair.originalLineCount == 3 && repair.lineCount == 1)
    }

    /// What a terminal program does: as many words as fit in `width` columns, then a new line under
    /// the first line's text.
    private func wrapped(_ paragraph: String, lead: String, width: Int) -> String {
        let hanging = String(repeating: " ", count: lead.count)
        var lines: [String] = []
        var line = lead
        for word in paragraph.split(separator: " ") {
            let start = line == lead || line == hanging
            if !start, line.count + 1 + word.count > width {
                lines.append(line)
                line = hanging + word
            } else {
                line += (start ? "" : " ") + word
            }
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }

    private let paragraph = """
        The terminal sends each line of a paste as if Return were pressed after it, so a reply copied \
        from a program that wraps its text to the window arrives as several commands, broken wherever \
        the window happened to end, and the shell or the prompt reads each one on its own.
        """

    @Test("any width and bullet: the paragraph comes back whole",
          arguments: [48, 72, 80, 134], ["• ", "⏺ ", "- ", "12. ", "  ", "  ⎿  "])
    func anyWidthAndBullet(width: Int, lead: String) throws {
        let text = wrapped(paragraph, lead: lead, width: width)
        let repair = try #require(TerminalWrappedPaste.repair(text))
        #expect(repair.text == lead + paragraph)
        #expect(repair.lineCount == 1)
    }

    @Test("paragraphs stay apart, and so does the blank line between them")
    func paragraphs() throws {
        let text = wrapped(paragraph, lead: "• ", width: 72) + "\n\n" + wrapped(paragraph, lead: "• ", width: 72)
        let repair = try #require(TerminalWrappedPaste.repair(text))
        #expect(repair.text == "• \(paragraph)\n\n• \(paragraph)")
    }

    @Test("each item of a list is joined, and the items stay apart")
    func listItems() throws {
        let text = wrapped(paragraph, lead: "- ", width: 80) + "\n" + wrapped(paragraph, lead: "- ", width: 80)
            + "\n" + "- A short item."
        let repair = try #require(TerminalWrappedPaste.repair(text))
        #expect(repair.text == "- \(paragraph)\n- \(paragraph)\n- A short item.")
    }

    @Test("a copy that began inside a paragraph, past its indent, is joined too")
    func beganInside() throws {
        let text = wrapped(paragraph, lead: "• ", width: 80)
        let inside = text.split(separator: "\n").dropFirst().joined(separator: "\n")
            .drop { $0 == " " }
        let repair = try #require(TerminalWrappedPaste.repair(String(inside)))
        #expect(repair.lineCount == 1)
    }

    @Test("lines that end short of the margin ended on purpose")
    func endedOnPurpose() {
        let text = """
            • A first line, well short of the margin.
              A second, also short.
              And a last line, much the longest, which sets the margin for every line of this paste.
            """
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("commands are never joined: no indent, no bullet")
    func commands() {
        let text = """
            docker run --rm -it -v "$PWD":/work -w /work ghcr.io/example/tool:latest build --release --verbose
            docker run --rm -it -v "$PWD":/work -w /work ghcr.io/example/tool:latest test --parallel --verbose
            """
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("a line ending in a backslash continues by the shell's rule, not ours")
    func backslash() {
        let text = """
            • swift build --configuration release --product glass-tool --arch arm64 --disable-keychain \\
              --verbose
            """
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("nothing inside a fenced code block is joined")
    func fencedCode() {
        let text = """
            • Run these two commands, one after the other, from the folder that holds the package:
              ```
              swift package resolve --disable-keychain --verbose --replace-scm-with-registry
              swift build --disable-keychain
              ```
            """
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("a table's rows are as wide as each other on purpose")
    func table() {
        let text = """
              │ Test                         │ iPhone, with │ iPhone, without │ iPad, with │
              │ Service row stacks           │ pass         │ fail            │ pass       │
              | Row unchanged at default     | pass         | pass            | pass       |
              | Filter and More one line     | pass         | fail            | skipped    |
            """
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("under 40 columns, nothing is joined")
    func narrow() {
        let text = wrapped(paragraph, lead: "• ", width: 36)
        #expect(TerminalWrappedPaste.repair(text) == nil)
    }

    @Test("a link broken at the margin is joined without a space")
    func link() throws {
        let link = "https://developer.apple.com/documentation/uikit/uifontmetrics/scaledvalue(for:compatiblewith:)"
        let first = "• See " + link.prefix(54)
        let text = first + "\n  " + link.dropFirst(54) + " for the scaling."
        let repair = try #require(TerminalWrappedPaste.repair(String(text)))
        #expect(repair.text == "• See \(link) for the scaling.")
    }

    @Test("wide characters take two columns")
    func wideCharacters() {
        #expect(TerminalWrappedPaste.cellWidth("abc") == 3)
        #expect(TerminalWrappedPaste.cellWidth("日本語") == 6)
        #expect(TerminalWrappedPaste.cellWidth("é") == 1)
        #expect(TerminalWrappedPaste.cellWidth("e\u{301}") == 1)
    }

    @Test("Windows line endings and a final newline are kept as lines")
    func lineEndings() throws {
        let text = wrapped(paragraph, lead: "• ", width: 72).replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        let repair = try #require(TerminalWrappedPaste.repair(text))
        #expect(repair.text == "• \(paragraph)\n")
    }
}
