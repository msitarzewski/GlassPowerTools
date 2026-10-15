//
//  TerminalLinkTargetTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  What a link in the terminal points at, and what Watch Log File runs (the owner, 2026-10-14:
//  "Add context detectors … for URLs and local paths … right click > watch log file").
//

import Foundation
import Testing
@testable import GlassTerminal
@testable import GlassTerminalEmulator

@Suite("A link in the terminal, and watching a file")
struct TerminalLinkTargetTests {
    @Test("an address is an address; a path is a path, its line and column dropped")
    func classifies() {
        #expect(TerminalLinkTarget(link: "https://example.com/docs") == .url(URL(string: "https://example.com/docs")!))
        #expect(TerminalLinkTarget(link: "mailto:ops@example.com") == .url(URL(string: "mailto:ops@example.com")!))
        #expect(TerminalLinkTarget(link: "/var/log/app.log") == .path("/var/log/app.log"))
        #expect(TerminalLinkTarget(link: "/var/log/app.log:42:7") == .path("/var/log/app.log"))
        #expect(TerminalLinkTarget(link: "~/logs/build.log") == .path("~/logs/build.log"))
        #expect(TerminalLinkTarget(link: "./tmp/out.log:12") == .path("./tmp/out.log"))
        #expect(TerminalLinkTarget(link: "$HOME/logs/x.log") == .path("$HOME/logs/x.log"))
        #expect(TerminalLinkTarget(link: "file:///tmp/x.log") == .path("/tmp/x.log"))
        // A `scheme:` it is not: a file and its line.
        #expect(TerminalLinkTarget(link: "app.log:12") == nil)
        #expect(TerminalLinkTarget(link: "  ") == nil)
    }

    @Test("Apple's detector tells a domain from a relative path, which SwiftTerm's rules cannot")
    func domainOrRelativePath() {
        guard case .url(let url) = TerminalLinkTarget(link: "github.com/owner/repo") else {
            Issue.record("github.com/owner/repo is an address")
            return
        }
        #expect(url.host == "github.com" && url.path == "/owner/repo")
        #expect(TerminalLinkTarget(link: "src/main.rs") == .path("src/main.rs"))
        #expect(TerminalLinkTarget(link: "logs/app.log") == .path("logs/app.log"))
    }

    @Test("an address on a row SwiftTerm found nothing in, under the pointer only")
    func addressOnARow() {
        let line = "curl example.com now"
        #expect(TerminalLinkTarget.address(in: line, at: 7)?.host == "example.com")
        #expect(TerminalLinkTarget.address(in: line, at: 1) == nil)
        #expect(TerminalLinkTarget.address(in: line, at: 99) == nil)
    }

    @Test("Watch Log File runs tail -F on the file, escaped, with ~ and $VAR left to the shell")
    func watchCommand() {
        #expect(TerminalWatchFile.command(for: "/var/log/app.log", in: nil) == "tail -F /var/log/app.log")
        #expect(TerminalWatchFile.command(for: "/var/log/my app.log", in: nil) == #"tail -F /var/log/my\ app.log"#)
        #expect(TerminalWatchFile.command(for: "~/logs/a b.log", in: nil) == #"tail -F ~/logs/a\ b.log"#)
        #expect(TerminalWatchFile.command(for: "$HOME/x.log", in: nil) == "tail -F $HOME/x.log")
        #expect(TerminalWatchFile.command(for: "/var/log/$(reboot).log", in: nil) == #"tail -F /var/log/\$\(reboot\).log"#)
        // A relative path is the folder's its shell was in.
        #expect(TerminalWatchFile.command(for: "logs/a.log", in: "/srv/app") == "tail -F /srv/app/logs/a.log")
        #expect(TerminalWatchFile.command(for: "../shared/a.log", in: "/srv/app") == "tail -F /srv/shared/a.log")
        #expect(TerminalWatchFile.command(for: "logs/a.log", in: nil) == nil)
        #expect(TerminalWatchFile.command(for: "/var/log/", in: nil) == nil)
        #expect(TerminalWatchFile.tabLabel(for: "/var/log/app.log") == "app.log")
    }

    @Test("what Watch Log File types is what the shell reads back")
    func watchCommandThroughAShell() throws {
        let path = "/tmp/a dir/it's $(x) & `y`.log"
        let command = try #require(TerminalWatchFile.command(for: path, in: nil))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // The words the shell would hand tail, printed one per line instead.
        process.arguments = ["-f", "-c", "printf '%s\\n' " + command.dropFirst("tail -F ".count)]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let words = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(words == path + "\n")
    }

    /// The owner (2026-10-14): "open a path with a context menu".
    @Test("a path is made absolute on its machine: ~ against its home, a relative one against the shell's folder")
    func pathResolution() {
        #expect(TerminalPathResolution.absolute("/var/log/app.log", directory: nil, home: nil) == "/var/log/app.log")
        #expect(TerminalPathResolution.absolute("~/notes.md", directory: nil, home: "/home/ann") == "/home/ann/notes.md")
        #expect(TerminalPathResolution.absolute("~", directory: nil, home: "/home/ann") == "/home/ann")
        #expect(TerminalPathResolution.absolute("logs/a.log", directory: "/srv/app", home: nil) == "/srv/app/logs/a.log")
        #expect(TerminalPathResolution.absolute("../x", directory: "/srv/app", home: nil) == "/srv/x")
        #expect(TerminalPathResolution.absolute("~/x", directory: nil, home: nil) == nil, "no home known")
        #expect(TerminalPathResolution.absolute("logs/a.log", directory: nil, home: nil) == nil, "no folder known")
        #expect(TerminalPathResolution.absolute("$HOME/x", directory: "/a", home: "/b") == nil, "only a shell expands that")
        #expect(TerminalPathResolution.folder(of: "/srv/app/a.log", isDirectory: false) == "/srv/app")
        #expect(TerminalPathResolution.folder(of: "/srv/app", isDirectory: true) == "/srv/app")
    }
}
