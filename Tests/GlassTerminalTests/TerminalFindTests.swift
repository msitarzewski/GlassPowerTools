//
//  TerminalFindTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  Find in a terminal (2026-10-08): SwiftTerm's buffer for a plain shell, tmux's own search for a
//  terminal kept in tmux. The live tests run a private tmux server on its own socket, named on
//  every command, and never touch the default server.
//

import Foundation
import Testing
import SwiftUI
import GlassTerminalEmulator
@testable import GlassTerminal
#if canImport(AppKit)
import AppKit
#endif

@Suite("Find in a terminal")
@MainActor
struct TerminalFindTests {
    // MARK: SwiftTerm's buffer

    #if os(macOS)
    /// A remote terminal's renderer in an offscreen window, fed the way a connection feeds it.
    /// The contextual menu's tests use it too (`MacTerminalContextMenuTests`).
    @MainActor
    final class HostedTerminal {
        let model = SwiftTermHostModel()
        private let window = NSWindow()
        private(set) var hosting: NSHostingView<SwiftTermHostView>?
        private var nonce: UInt64 = 0

        init(scrollback: Int = 500, height: CGFloat = 600) async {
            let hosting = NSHostingView(rootView: SwiftTermHostView(
                model: model,
                theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1),
                                      cursor: (1, 1, 1)),
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false,
                                                          scrollbackLines: scrollback),
                allowsFocusOwnership: false,
                onSendData: { _ in },
                onResize: { _, _ in }
            ))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: height))
            hosting.frame = NSRect(x: 0, y: 0, width: 800, height: height)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            self.hosting = hosting
            await Task.yield()
        }

        /// Fed, and drawn: up to 30 s for the renderer to take it, and a test that goes on without
        /// it is stopped there. It gave up after a second and returned as if fed, so a check that the
        /// output didn't disturb something passed without the output having arrived (2026-10-24).
        func feed(_ text: String) async {
            nonce += 1
            model.ingest(data: Data(text.utf8), nonce: nonce)
            for _ in 0..<3_000 where model.pendingRendererByteCount != 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.pendingRendererByteCount == 0, "the terminal never drew what it was fed")
        }

        func close() {
            window.contentView = nil
            hosting = nil
            model.releaseRenderer()
        }
    }

    private func bufferFind(_ model: SwiftTermHostModel) -> TerminalFindController {
        let find = TerminalFindController(sharedTerm: { nil }, publishTerm: { _ in })
        find.configure(model: model) { nil }
        return find
    }

    private func needles(filler: Int) -> String {
        "needle 1\r\n" + (1...filler).map { "filler \($0)\r\n" }.joined() + "needle 2\r\n"
    }

    @Test("a plain shell: the first find is the newest match, and the hit survives output")
    func plainShell() async {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed(needles(filler: 50))
        let find = bufferFind(host.model)
        find.query = "needle"

        find.step(.older)
        await find.waitUntilIdle()
        #expect(host.model.selectedFindLine == "needle 2", "Return finds the newest match first")
        #expect(find.outcome == .found(count: 2, index: 1))

        await host.feed("more output\r\n")
        #expect(host.model.selectedFindLine == "needle 2", "one chunk of output does not take the hit away")

        find.step(.older)
        await find.waitUntilIdle()
        #expect(host.model.selectedFindLine == "needle 1", "the next find goes on from the hit")
        #expect(find.outcome == .found(count: 2, index: 2))

        find.close()
        #expect(host.model.selectedFindLine == nil)
    }

    @Test("a spinner's synchronized frame does not take the hit away")
    func spinnerFrame() async {
        let host = await HostedTerminal()
        defer { host.close() }
        await host.feed(needles(filler: 50))
        let find = bufferFind(host.model)
        find.query = "needle"
        find.step(.older)
        await find.waitUntilIdle()
        #expect(host.model.selectedFindLine == "needle 2")

        await host.feed("\u{1B}[?2026h\r\u{1B}[2K⠋ Working\u{1B}[?2026l")
        await host.feed("\u{1B}[?2026h\r\u{1B}[2K⠙ Working\u{1B}[?2026l")
        #expect(host.model.selectedFindLine == "needle 2")
    }

    /// At the scrollback limit every row moves up as a line is trimmed: the hit follows its text,
    /// and goes when its line is trimmed away.
    @Test("at the scrollback limit the hit follows its line, and goes with it")
    func scrollbackLimit() async {
        // About twelve rows and 100 lines of scrollback: 118 lines trims a few, needle 1 among them.
        let host = await HostedTerminal(scrollback: 100, height: 200)
        defer { host.close() }
        await host.feed(needles(filler: 20))
        let find = bufferFind(host.model)
        find.query = "needle"
        find.step(.older)
        await find.waitUntilIdle()
        #expect(host.model.selectedFindLine == "needle 2")

        await host.feed((1...95).map { "more \($0)\r\n" }.joined())
        #expect(host.model.selectedFindLine == "needle 2", "still on its line after rows moved up")
        find.step(.older)
        await find.waitUntilIdle()
        #expect(find.outcome == .found(count: 1, index: 1), "needle 1 was trimmed, so lines did move")

        await host.feed((1...150).map { "later \($0)\r\n" }.joined())
        #expect(host.model.selectedFindLine == nil, "trimmed past: no hit pointing at another line")
        find.step(.older)
        await find.waitUntilIdle()
        #expect(find.outcome == .notFound)
    }
    #endif

    @Test("a terminal with no renderer yet says so, rather than No match")
    func notReady() async {
        let find = TerminalFindController(sharedTerm: { nil }, publishTerm: { _ in })
        find.configure(model: SwiftTermHostModel()) { nil }
        find.query = "needle"
        find.step(.older)
        await find.waitUntilIdle()
        #expect(find.outcome == .failed(SwiftTermFindSource.notReady))
    }

    // MARK: Builders

    private let format = "#{search_present} #{search_count} #{scroll_position} #{copy_cursor_y} #{copy_cursor_x}"

    #if os(macOS)
    @Test("the Mac's argv: -u first, the exact session, -- before the term, both directions")
    func argvBuilder() {
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .search("needle", .older))
                == ["-u", "copy-mode", "-t", "=glass-7:", ";",
                    "send-keys", "-t", "=glass-7:", "-X", "search-backward-text", "--", "needle", ";",
                    "display", "-p", "-t", "=glass-7:", format])
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .search("needle", .newer))[9]
                == "search-forward-text")
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .end)
                == ["-u", "send-keys", "-t", "=glass-7:", "-X", "cancel"])
        // A term that looks like an option stays a term, and only a trailing `;` is escaped.
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .search("-x;", .older))[11] == #"-x\;"#)
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .search("a;b", .older))[11] == "a;b")
        #expect(MacLocalTmux.findArguments(session: "glass-7", request: .search("it's", .older))[11] == "it's")
    }
    #endif

    @Test("the SSH command: sh -c, tmux -u, quoted target and term, both directions")
    func shellBuilder() {
        func expected(_ inner: String) -> String {
            "sh -c " + TerminalTmux.quoted(#"PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; "# + inner)
        }
        #expect(TerminalTmux.findCommand(name: "glass-7", request: .search("needle", .older)) == expected(
            "tmux -u copy-mode -t '=glass-7:' ';' send-keys -t '=glass-7:' -X search-backward-text -- 'needle' "
                + "';' display -p -t '=glass-7:' '\(format)'"))
        #expect(TerminalTmux.findCommand(name: "glass-7", request: .search("it's;", .newer)) == expected(
            #"tmux -u copy-mode -t '=glass-7:' ';' send-keys -t '=glass-7:' -X search-forward-text -- 'it'\''s\;' "#
                + "';' display -p -t '=glass-7:' '\(format)'"))
        #expect(TerminalTmux.findCommand(name: "glass-7", request: .end)
                == expected("tmux -u send-keys -t '=glass-7:' -X cancel"))
        #expect(TerminalTmuxFind.argument(";") == #"\;"#)
        #expect(TerminalTmuxFind.argument(#"a\;"#) == #"a\\;"#, "tmux reads that back as a\\;")
    }

    // MARK: tmux's reply

    @Test("the reply: found with a count, not found, and anything else")
    func replies() {
        #expect(TerminalTmuxFind.parse("1 3 36 8 0\n")
                == TerminalTmuxFindReply(present: true, count: 3, line: -28, column: 0))
        #expect(TerminalTmuxFind.parse("0  36 8 0\n")
                == TerminalTmuxFindReply(present: false, count: 0, line: -28, column: 0), "a miss leaves the count empty")
        #expect(TerminalTmuxFind.parse("0 0 0 9 0") == TerminalTmuxFindReply(present: false, count: 0, line: 9, column: 0))
        #expect(TerminalTmuxFind.parse("warning\n1 1 0 2 4\n")?.count == 1, "the last line is the reply")
        for malformed in ["", "\n", "garbage", "1 3 36 8", "1 x 36 8 0", "2 3 0 0 0", "1 3 -1 8 0",
                          "1\t3\t36\t8\t0", "no server running on /tmp/gpt-0/s"] {
            #expect(TerminalTmuxFind.parse(malformed) == nil, "\(malformed.debugDescription)")
        }
    }

    @Test("what the bar says")
    func labels() {
        #expect(TerminalFindOutcome.found(count: 14, index: 2).label == "2 of 14")
        #expect(TerminalFindOutcome.found(count: 3, index: nil).label == "3 matches")
        #expect(TerminalFindOutcome.found(count: 1, index: nil).label == "1 match")
        #expect(TerminalFindOutcome.notFound.label == "No match")
        #expect(TerminalFindOutcome.failed("Search again.").failure == "Search again.")
    }

    // MARK: Choosing the source

    @Test("tmux's search for a terminal kept in tmux, SwiftTerm's otherwise")
    func choosing() async {
        #expect(TerminalFindSourceChoice.choose(tmuxSession: nil, tmuxReachable: true) == .swiftTerm)
        #expect(TerminalFindSourceChoice.choose(tmuxSession: "glass-1", tmuxReachable: false) == .swiftTerm)
        #expect(TerminalFindSourceChoice.choose(tmuxSession: "", tmuxReachable: true) == .swiftTerm)
        #expect(TerminalFindSourceChoice.choose(tmuxSession: "glass-1", tmuxReachable: true) == .tmux(session: "glass-1"))

        #if os(macOS)
        #expect(MacLocalTmux.findTarget(session: "glass-3", tmux: "/opt/homebrew/bin/tmux")?.session == "glass-3")
        #expect(MacLocalTmux.findTarget(session: nil, tmux: "/opt/homebrew/bin/tmux") == nil, "a plain local shell")
        #expect(MacLocalTmux.findTarget(session: "glass-3", tmux: nil) == nil, "no tmux: the pane runs a plain shell")
        #endif

        // SSH: kept in tmux and connected, and the step goes over the session's own connection.
        // A session opened from Active, so its name is given rather than chosen.
        var asked: [String] = []
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        let inTmux = TerminalSession(server: server, terminalWriteSink: { _ in })
        inTmux.tmuxCommandRunner = { asked.append($0); return "" }
        inTmux.tmuxSessionName = "work"
        #expect(inTmux.tmuxFindTarget == nil, "not connected")
        inTmux.state = .connected
        await inTmux.waitForTmuxAttach()
        let target = inTmux.tmuxFindTarget
        #expect(target?.session == "work")
        asked.removeAll()
        _ = await target?.run(.search("needle", .older))
        #expect(asked == [TerminalTmux.findCommand(name: "work", request: .search("needle", .older))])
        inTmux.state = .reconnecting
        #expect(inTmux.tmuxFindTarget == nil, "while reconnecting the buffer is searched")

        server.tmux = false
        let plain = TerminalSession(server: server, terminalWriteSink: { _ in })
        plain.tmuxCommandRunner = { _ in "" }
        plain.state = .connected
        await plain.waitForTmuxAttach()
        #expect(plain.tmuxFindTarget == nil)
    }

    // MARK: The bar's state

    /// A tmux that answers from memory, and can hold a request until told to answer.
    @MainActor
    private final class FakeTmux {
        var requests: [TerminalTmuxFindRequest] = []
        var holdNext = false
        /// False: searches come back with nothing, as from a lost connection or an old tmux.
        var answers = true
        private var held: CheckedContinuation<Void, Never>?

        var target: TerminalTmuxFindTarget {
            TerminalTmuxFindTarget(session: "glass-1", failure: "tmux didn't answer.") { [self] request in
                await run(request)
            }
        }

        func run(_ request: TerminalTmuxFindRequest) async -> String? {
            requests.append(request)
            if holdNext {
                holdNext = false
                await withCheckedContinuation { held = $0 }
            }
            if case .search = request { return answers ? "1 2 0 3 0\n" : nil }
            return ""
        }

        func release() {
            held?.resume()
            held = nil
        }

        func waitForRequests(_ count: Int) async {
            for _ in 0..<200 where requests.count < count { await Task.yield() }
        }
    }

    private func tmuxFind(_ fake: FakeTmux, shared: String? = nil,
                          published: ((String) -> Void)? = nil) -> TerminalFindController {
        let find = TerminalFindController(sharedTerm: { shared }, publishTerm: { published?($0) })
        find.configure(model: SwiftTermHostModel()) { fake.target }
        return find
    }

    @Test("one step in flight; of the requests made meanwhile, only the latest follows")
    func latestWins() async {
        let fake = FakeTmux()
        let find = tmuxFind(fake)
        find.query = "needle"
        fake.holdNext = true
        find.step(.older)
        await fake.waitForRequests(1)
        find.step(.newer)
        find.step(.older)
        #expect(fake.requests.count == 1, "nothing more is sent while a step travels")
        fake.release()
        await find.waitUntilIdle()
        #expect(fake.requests == [.search("needle", .older), .search("needle", .older)])
        #expect(find.outcome == .found(count: 2, index: nil))
    }

    @Test("a step tmux does not answer says so plainly, and leaves copy mode at once")
    func unanswered() async {
        let fake = FakeTmux()
        fake.answers = false
        let find = tmuxFind(fake)
        find.query = "needle"
        find.step(.older)
        await find.waitUntilIdle()
        #expect(find.outcome == .failed("tmux didn't answer."))
        #expect(fake.requests == [.search("needle", .older), .end])
    }

    @Test("closing while a step travels leaves copy mode once the step lands")
    func closeWhileInFlight() async {
        let fake = FakeTmux()
        let find = tmuxFind(fake)
        find.query = "needle"
        fake.holdNext = true
        find.step(.older)
        await fake.waitForRequests(1)
        find.close()
        fake.release()
        await find.waitUntilIdle()
        await fake.waitForRequests(2)
        #expect(fake.requests == [.search("needle", .older), .end])
        #expect(find.outcome == nil, "the closed bar shows nothing from the late step")
    }

    @Test("⌘G with the bar closed: the last term, else the find pasteboard's, else it is ⌘F")
    func findAgain() async {
        var published: [String] = []
        let fake = FakeTmux()
        let find = tmuxFind(fake, shared: "from elsewhere", published: { published.append($0) })
        find.perform(.next)
        await find.waitUntilIdle()
        #expect(find.isPresented && find.query == "from elsewhere")
        #expect(fake.requests == [.search("from elsewhere", .older)])
        #expect(published == ["from elsewhere"])

        find.query = "mine"
        find.close()
        await fake.waitForRequests(2)
        #expect(fake.requests.last == .end, "closing leaves copy mode")
        find.perform(.previous)
        await find.waitUntilIdle()
        #expect(find.isPresented && fake.requests.last == .search("mine", .newer), "the bar's own term comes first")

        let empty = tmuxFind(FakeTmux())
        let focusBefore = empty.focusRequest
        empty.perform(.next)
        await empty.waitUntilIdle()
        #expect(empty.isPresented && empty.focusRequest != focusBefore && empty.outcome == nil,
                "no term anywhere: the bar opens to type one")
    }

    // MARK: Against a real tmux

    #if os(macOS)
    enum Form: String, CaseIterable, Sendable {
        /// The SSH command, through `sh -c` as an exec channel runs it.
        case sh
        /// The Mac's argv, through `MacLocalTmux.run`.
        case argv
    }

    /// A tmux server of its own: a short folder in /tmp (a socket path over about 104 characters
    /// fails), and `-S` on every command. The `tmux` the builders find on the PATH is a wrapper that
    /// adds the same `-S`, and refuses to run once the socket is gone. Its runs block, so the test asks
    /// it off the main actor (`offMainActor`): fifteen to twenty runs a case held it from every other
    /// test in the run (2026-10-24).
    private nonisolated final class PrivateTmux: @unchecked Sendable {
        let folder: String
        let socket: String
        let wrapper: String
        private let tmux: String

        init(tmux: String, modeKeys: String, seed: String) throws {
            self.tmux = tmux
            folder = "/tmp/gpt-" + UUID().uuidString.prefix(8).lowercased()
            socket = folder + "/s"
            wrapper = folder + "/bin/tmux"
            try FileManager.default.createDirectory(atPath: folder + "/bin", withIntermediateDirectories: true)
            let script = "#!/bin/sh\n[ -S '\(socket)' ] || { echo 'no private tmux socket' >&2; exit 97; }\n"
                + "exec '\(tmux)' -S '\(socket)' \"$@\"\n"
            try Data(script.utf8).write(to: URL(fileURLWithPath: wrapper))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)
            _ = raw(["-f", "/dev/null", "new-session", "-d", "-s", "glass-7", "-x", "80", "-y", "10", seed])
            _ = raw(["set-option", "-g", "mode-keys", modeKeys])
        }

        /// The real tmux, on this server's socket only.
        @discardableResult
        func raw(_ arguments: [String]) -> String {
            run(tmux, ["-S", socket] + arguments).output
        }

        /// The SSH form: what the exec channel's shell would run, finding the wrapper first.
        func sh(_ command: String) -> String? {
            let result = run("/bin/sh", ["-c", command], path: folder + "/bin:/usr/bin:/bin")
            return result.status == 0 ? result.output : nil
        }

        /// Up to 30 s for the seed's last line: off the main actor, a generous wait costs no one.
        func waitForSeed(_ marker: String) {
            for _ in 0..<600 where !raw(["capture-pane", "-p", "-t", "=glass-7:"]).contains(marker) {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        var cursorLine: String {
            raw(["display-message", "-p", "-t", "=glass-7:", "#{copy_cursor_line}"])
                .trimmingCharacters(in: .newlines)
        }

        var inMode: String {
            raw(["display-message", "-p", "-t", "=glass-7:", "#{pane_in_mode}"]).trimmingCharacters(in: .newlines)
        }

        func stop() {
            raw(["kill-server"])
            try? FileManager.default.removeItem(atPath: folder)
        }

        private func run(_ executable: String, _ arguments: [String], path: String = "/usr/bin:/bin")
            -> (output: String, status: Int32) {
            var environment = ProcessInfo.processInfo.environment
            environment["TMUX"] = nil
            environment["TMUX_PANE"] = nil
            environment["PATH"] = path
            return LiveProcess.run(executable, arguments, environment: environment)
        }
    }

    @Test("tmux's own search, live, in both mode-keys and both forms",
          .enabled(if: TerminalTmuxTests.tmux != nil),
          arguments: ["emacs", "vi"], Form.allCases)
    func liveTmux(modeKeys: String, form: Form) async throws {
        let seed = "printf 'needle 1\\n'; seq 1 30; printf 'needle 2\\n'; seq 31 60; printf \"it's a;b\\n\"; "
            + "printf 'needle 3\\n'; seq 61 65; sleep 60"
        let tmux = try PrivateTmux(tmux: TerminalTmuxTests.tmux!, modeKeys: modeKeys, seed: seed)
        defer { tmux.stop() }
        await offMainActor { tmux.waitForSeed("65") }
        let target = TerminalTmuxFindTarget(session: "glass-7", failure: "tmux didn't answer.") { request in
            switch form {
            case .sh:
                let command = TerminalTmux.findCommand(name: "glass-7", request: request)
                return await offMainActor { tmux.sh(command) }
            case .argv:
                let arguments = MacLocalTmux.findArguments(session: "glass-7", request: request)
                return await offMainActor { MacLocalTmux.run(tmux.wrapper, arguments) }
            }
        }
        let source = TmuxFindSource(target)

        var older: [String] = []
        for _ in 0..<3 {
            #expect(await source.step("needle", .older) == .found(count: 3, index: nil))
            older.append(await offMainActor { tmux.cursorLine })
        }
        #expect(older == ["needle 3", "needle 2", "needle 1"], "each match once, newest first")

        var newer: [String] = []
        for _ in 0..<2 {
            #expect(await source.step("needle", .newer) == .found(count: 3, index: nil))
            newer.append(await offMainActor { tmux.cursorLine })
        }
        #expect(newer == ["needle 2", "needle 3"], "turning round reaches a different match each step")

        #expect(await source.step(";", .older) == .found(count: 1, index: nil), "a lone ; is the term, not the end of the command")
        #expect(await source.step("it's", .older) == .found(count: 1, index: nil))

        #expect(await source.step("not-in-this-pane", .older) == .notFound)
        #expect(await offMainActor { tmux.inMode } == "0", "a miss leaves copy mode")

        #expect(await source.step("needle", .older) == .found(count: 3, index: nil))
        #expect(await offMainActor { tmux.inMode } == "1")
        source.end()
        // Closing leaves copy mode in a task of its own: up to 10 s for it.
        var mode = await offMainActor { tmux.inMode }
        for _ in 0..<200 where mode != "0" {
            try await Task.sleep(for: .milliseconds(50))
            mode = await offMainActor { tmux.inMode }
        }
        #expect(mode == "0", "closing the bar returns to the live prompt")
    }
    #endif
}
