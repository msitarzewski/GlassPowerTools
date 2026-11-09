//
//  TerminalShellFolderTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Where a shell outside tmux is standing, for Open Folder Here (2026-11-09; the owner, on an SSH tab to an Ubuntu
//  server: "Where is my folder icon for this connection!?"). The button read only a bare path from OSC 7, which no
//  shell sends (they send `file://host/path`), and bash on a Linux server sends no OSC 7 at all: it names the folder
//  in the window title at every prompt. Both are read now, the title's folder kept while a program's title stands
//  in front of it.
//

import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

@Suite("A shell's folder, outside tmux")
@MainActor
struct TerminalShellFolderTests {
    private typealias Folder = TerminalShellTitle.Folder

    private func session(asked: @escaping @MainActor (String) -> Void = { _ in },
                         answer: String = "/home/ann\n") -> TerminalSession {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = false
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        session.tmuxCommandRunner = { asked($0); return answer }
        session.state = .connected
        return session
    }

    @Test("a prompt's title: Debian's and Ubuntu's `user@host: folder`, Fedora's and Arch's `user@host:folder`")
    func promptTitles() {
        #expect(TerminalShellTitle.folder(in: "ann@box: /var/www/shop") == Folder(user: "ann", path: "/var/www/shop"))
        #expect(TerminalShellTitle.folder(in: "ann@box:~/src") == Folder(user: "ann", path: "~/src"))
        #expect(TerminalShellTitle.folder(in: "ann@box: ~") == Folder(user: "ann", path: "~"))
        #expect(TerminalShellTitle.folder(in: "root@box.example.com:/etc") == Folder(user: "root", path: "/etc"))
        #expect(TerminalShellTitle.folder(in: "ann@box: /srv/my app") == Folder(user: "ann", path: "/srv/my app"))
    }

    @Test("anything else names no folder: a program's title, a chroot's, a shortened folder, a relative one")
    func otherTitles() {
        for title in [nil, "", "vim notes.txt", "✳ Fix the jobs worker", "codex", "ann@box", "ann@box: src",
                      "(jail)ann@box: /srv", "ann@box: ~/.../src", "ann@box: ~ann", "ann box: /srv", "ann@box - /srv"] {
            #expect(TerminalShellTitle.folder(in: title) == nil, "\(title ?? "nil")")
        }
    }

    @Test("the folder a shell reports over OSC 7 is a `file://` URL, read as its path")
    func reportedURL() async {
        let plain = session()
        #expect(await plain.workingDirectory(reported: "file://box/home/ann/my%20app") == "/home/ann/my app")
        #expect(await plain.workingDirectory(reported: "/home/ann") == "/home/ann")
        #expect(await plain.workingDirectory(reported: "http://box/home/ann") == nil, "not a folder")
    }

    @Test("with no report, the folder the prompt's title named; `~` is this account's home, asked of the host")
    func titleFolder() async {
        var asked: [String] = []
        let plain = session(asked: { asked.append($0) })
        #expect(await plain.shellFolder(reported: nil, title: Folder(user: "ann", path: "/var/www/app")) == "/var/www/app")
        #expect(asked.isEmpty, "an absolute folder needs no question")
        #expect(await plain.shellFolder(reported: nil, title: Folder(user: "ann", path: "~/src")) == "/home/ann/src")
        #expect(await plain.shellFolder(reported: nil, title: Folder(user: "ann", path: "~")) == "/home/ann")
        #expect(asked.last == "printf '%s' \"$HOME\"")
        #expect(await plain.shellFolder(reported: "file://box/srv", title: Folder(user: "ann", path: "/var")) == "/srv",
                "what the shell reported comes first")
        #expect(await plain.shellFolder(reported: nil, title: nil) == nil, "a shell that says nothing")
    }

    @Test("another account's `~` is a home this one doesn't know; a host that can't say its home gives none")
    func unknownHomes() async {
        var asked: [String] = []
        let plain = session(asked: { asked.append($0) })
        #expect(await plain.shellFolder(reported: nil, title: Folder(user: "root", path: "~")) == nil)
        #expect(await plain.shellFolder(reported: nil, title: Folder(user: "root", path: "/root")) == "/root")
        #expect(asked.isEmpty)
        let silent = session(answer: "sh: printf: not found\n")
        #expect(await silent.shellFolder(reported: nil, title: Folder(user: "ann", path: "~/src")) == nil)
        #expect(await silent.homeFolder() == nil)
    }

    #if os(macOS)
    /// Through the terminal itself: SwiftTerm reads the title (OSC 0 and 2), the model keeps the prompt's folder.
    @Test("the terminal keeps the last prompt's folder while a program's title stands in front of it")
    func keptThroughPrograms() async throws {
        let host = await TerminalFindTests.HostedTerminal()
        defer { host.close() }
        await host.feed("\u{1B}]0;ann@box: /srv/app\u{07}$ ")
        try await waitForTitle("ann@box: /srv/app", in: host.model)
        #expect(host.model.titleFolder == Folder(user: "ann", path: "/srv/app"))
        await host.feed("\u{1B}]2;codex\u{07}")
        try await waitForTitle("codex", in: host.model)
        #expect(host.model.titleFolder == Folder(user: "ann", path: "/srv/app"), "Codex's title is no folder")
        await host.feed("\u{1B}]0;ann@box:~/src\u{07}$ ")
        try await waitForTitle("ann@box:~/src", in: host.model)
        #expect(host.model.titleFolder == Folder(user: "ann", path: "~/src"))
    }

    private func waitForTitle(_ title: String, in model: SwiftTermHostModel) async throws {
        for _ in 0..<500 where model.terminalTitle != title {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.terminalTitle == title, "the terminal never took the title \(title)")
    }
    #endif
}
