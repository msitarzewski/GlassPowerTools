import Foundation
import Testing
@testable import GlassTerminal

/// Files dropped on a terminal type their paths, escaped for the shell (2026-10-07).
@Suite("Dropped paths")
struct TerminalDroppedPathsTests {
    @Test("plain paths stand as they are; spaces and shell characters are escaped")
    func escaping() {
        #expect(TerminalDroppedPaths.escaped("/Users/ann/Pictures/photo-1.jpg") == "/Users/ann/Pictures/photo-1.jpg")
        #expect(TerminalDroppedPaths.escaped("/Users/ann/My Pictures/a (1).png") == #"/Users/ann/My\ Pictures/a\ \(1\).png"#)
        #expect(TerminalDroppedPaths.escaped("/tmp/it's $HOME & `x`;") == #"/tmp/it\'s\ \$HOME\ \&\ \`x\`\;"#)
        #expect(TerminalDroppedPaths.escaped("/tmp/café/日本.txt") == "/tmp/café/日本.txt")
        #expect(TerminalDroppedPaths.escaped("/tmp/two\nlines") == #"$'/tmp/two\nlines'"#)
    }

    @Test("several files: one line, space separated, a space after, never a newline")
    func several() {
        let urls = [URL(fileURLWithPath: "/tmp/a b.png"), URL(fileURLWithPath: "/tmp/c.txt"),
                    URL(string: "https://example.com/x")!]
        #expect(TerminalDroppedPaths.text(for: urls) == #"/tmp/a\ b.png /tmp/c.txt "#)
        #expect(TerminalDroppedPaths.text(for: [URL(string: "https://example.com")!]) == nil)
    }

    /// The escaping is only right if a shell reads it back as the same path.
    @Test("a shell reads every escaped path back unchanged")
    func shellRoundTrip() throws {
        for path in ["/tmp/My Pictures/a (1).png", "/tmp/it's $HOME & `x`;", "/tmp/[brackets]{x}*?#~!",
                     "/tmp/café/日本.txt", "/tmp/two\nlines\tand tab", "/tmp/back\\slash"] {
            for shell in ["/bin/zsh", "/bin/bash"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-c", "printf '%s' " + TerminalDroppedPaths.escaped(path)]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                process.waitUntilExit()
                let echoed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                #expect(echoed == path, "\(shell): \(path.debugDescription) came back \(echoed.debugDescription)")
            }
        }
    }
}
