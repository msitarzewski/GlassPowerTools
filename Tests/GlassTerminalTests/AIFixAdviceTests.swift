import Testing
@testable import GlassTerminal

/// A suggested fix is offered to run only when it is a command; prose is advice (2026-10-04).
@Suite("AI fixes: command or advice")
struct AIFixAdviceTests {
    @Test("commands are runnable", arguments: [
        "sudo apt install lxterminal", "ls -rd", "cd ..", "cd .", "export PATH=$PATH:/usr/local/bin",
        "grep -R \"needle\" .", "R --version",
    ])
    func commands(_ fix: String) { #expect(AIResponseParser.isRunnableCommand(fix)) }

    @Test("sentences are advice", arguments: [
        "Install the LX Terminal package or use the correct command for your terminal environment.",
        "Check that the file exists.",
        "Use ls instead",
        "sudo apt update\nsudo apt install lxterminal",
        "",
    ])
    func advice(_ fix: String) { #expect(!AIResponseParser.isRunnableCommand(fix)) }
}
