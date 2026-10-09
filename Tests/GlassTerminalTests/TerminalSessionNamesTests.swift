#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// W11 (2026-10-09), the owner: "Terminal names aren't persisted between devices. Maybe the tab
/// rename also renames the tmux session and we use that if available?" A Mac tab keeps the name
/// it is given on its tmux session (`@glass-name`, W6) and names itself by its program's title,
/// repository and folder; an iPhone, iPad or Vision Pro showed the server's name. A terminal there
/// now reads what its session says about itself and is named by the same rule, and renaming it
/// names the session.
@MainActor
@Suite("Terminal names on every device")
struct TerminalSessionNamesTests {
    /// A host's tmux, from memory: what a read of the session answers, and every command it ran.
    @MainActor private final class Host {
        var commands: [String] = []
        var reads = 0
        var readTimes: [ContinuousClock.Instant] = []
        var given = ""
        var title = "alpha.example.com"
        var directory = "/home/ann/src/app/Sources"
        var repository: (top: String, branch: String)? = ("/home/ann/src/app", "main")
        /// How long a read takes on the host.
        var delay: Duration = .zero

        func answer() -> String {
            let pane = [TerminalTmux.paneMarker, "/home/ann", directory, "alpha.example.com", "alpha", given, title]
                .joined(separator: "\t")
            guard let repository else { return pane + "\n" }
            return pane + "\n" + [TerminalRepository.remoteMarker, repository.top, "../.git", repository.branch, "/home/ann"]
                .joined(separator: "\n") + "\n"
        }
    }

    private static let read = TerminalTmux.paneStateCommand(session: "glass-5")!

    /// A terminal in tmux session `glass-5` on `alpha`, connected and attached, reading as the
    /// devices without the Mac's tabs do.
    private func terminal(_ host: Host, interval: Duration = .zero) async -> TerminalSession {
        var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        server.tmux = true
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        session.readsTmuxPane = true
        session.tmuxPaneReadInterval = interval
        session.outputSettleDelay = .milliseconds(30)
        session.tmuxSessionName = "glass-5"
        session.tmuxCommandRunner = { command in
            host.commands.append(command)
            guard command == Self.read else { return "" }
            host.reads += 1
            host.readTimes.append(.now)
            let answer = host.answer()
            if host.delay > .zero { try await Task.sleep(for: host.delay) }
            return answer
        }
        session.state = .connected
        await session.waitForTmuxAttach()
        return session
    }

    /// Waits up to two seconds for `condition`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Output that comes to rest.
    private func settle(_ session: TerminalSession) async {
        let before = session.outputSettledNonce
        session.feedTerminalData(Data("output\r\n".utf8))
        _ = await eventually { session.outputSettledNonce > before }
    }

    // MARK: The read

    @Test("one command reads what a session says about itself; the session is its argument, never part of the script")
    func readCommand() throws {
        #expect(TerminalTmux.paneStateCommand(session: "it's")
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; s=$1; tmux -u has-session -t "=$s" 2>/dev/null || exit 0; c=$(tmux -u display-message -p -t "=$s:" '\''#{pane_current_path}\#t#{host}\#t#{host_short}\#t#{@glass-name}\#t#{pane_title}'\'' 2>/dev/null) || exit 0; printf '\''__glass_pane__\t%s\t%s\n'\'' "$HOME" "$c"; set -- "$(tmux -u display-message -p -t "=$s:" '\''#{pane_current_path}'\'' 2>/dev/null)"; case $1 in /*) ;; *) exit 0;; esac; command -v git >/dev/null 2>&1 || exit 0; if [ -x /usr/bin/xcode-select ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then exit 0; fi; cd -- "$1" 2>/dev/null || exit 0; t=$(git rev-parse --show-toplevel --git-common-dir 2>/dev/null) || exit 0; b=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null); h=$(cd -- "$HOME" 2>/dev/null && pwd -P); printf '\''__glass_repo__\n%s\n%s\n%s\n'\'' "$t" "$b" "$h"' _ 'it'\''s'"#)
        #expect(TerminalTmux.paneStateCommand(session: "a:b") == nil, "a session name tmux would misread")

        let host = Host()
        host.given = "deploys"
        host.title = "✳ Claude\tCode"
        // A login script's chatter comes first.
        let state = try #require(TerminalTmux.parsePaneState("Welcome to alpha\n" + host.answer()))
        #expect(state == TerminalTmux.PaneState(givenName: "deploys", title: "✳ Claude\tCode", directory: "/home/ann/src/app/Sources",
                                                home: "/home/ann",
                                                repository: TerminalRepository(name: "app", branch: "main", root: "/home/ann/src/app")))
        host.given = ""
        host.title = "alpha"
        host.repository = nil
        #expect(TerminalTmux.parsePaneState(host.answer())
                == TerminalTmux.PaneState(directory: "/home/ann/src/app/Sources", home: "/home/ann"),
                "tmux's default title, the host name, is no title; outside a repository, none")
        #expect(TerminalTmux.parsePaneState("") == nil, "tmux said nothing: the session is gone")
    }

    /// Against a private tmux server, through a `tmux` on the PATH that names its socket, so the
    /// default server, which holds the owner's sessions, is never reached (rule 63).
    @Test("live: the read, run by sh against a private tmux server, in a repository git made",
          .enabled(if: TerminalTmuxTests.tmux != nil && TerminalRepositoryTests.hasGit))
    func readLive() throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let home = try #require(realpath(folder.path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        })
        let environment = ["PATH": "/usr/bin:/bin", "HOME": home, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        @discardableResult func run(_ arguments: [String]) -> Int32 {
            LiveProcess.run(tmux, ["-S", socket] + arguments, environment: environment).status
        }
        defer { run(["kill-server"]) }
        let app = home + "/src/app"
        try FileManager.default.createDirectory(atPath: app + "/Sources", withIntermediateDirectories: true)
        try #require(LiveProcess.run("/usr/bin/git", ["-C", app, "init", "-q", "-b", "feature/x"], environment: environment).status == 0)

        #expect(run(["-u", "-f", "/dev/null", "new-session", "-d", "-s", "glass-5", "-c", app + "/Sources", "-x", "80", "-y", "10",
                     "/bin/sleep", "600"]) == 0)
        #expect(run(["-u", "select-pane", "-t", "=glass-5:", "-T", "✳ Claude Code"]) == 0)
        #expect(run(try #require(TerminalTmux.givenNameArguments(session: "glass-5", name: "deploys"))) == 0)

        let bin = folder.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let shim = bin.appendingPathComponent("tmux")
        try Data("#!/bin/sh\nexec \(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) \"$@\"\n".utf8).write(to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        var throughShim = environment
        throughShim["PATH"] = "\(bin.path):/usr/bin:/bin"
        func read(_ session: String) -> TerminalTmux.PaneState? {
            let command = TerminalTmux.paneStateCommand(session: session)!
            return TerminalTmux.parsePaneState(LiveProcess.run("/bin/sh", ["-c", command], environment: throughShim).output)
        }
        let state = try #require(read("glass-5"))
        #expect(state.givenName == "deploys" && state.title == "✳ Claude Code")
        #expect(state.directory == app + "/Sources" && state.home == home)
        #expect(state.repository.map { [$0.name, $0.branch] } == ["app", "feature/x"])
        #expect(read("glass-6") == nil, "a session that is not running says nothing")
    }

    // MARK: The terminal

    @Test("a terminal in tmux reads its session once attached and when output settles: at most once an interval, never while quiet")
    func readsWhenSettled() async throws {
        let host = Host()
        host.title = "✳ Claude Code"
        // Held to what holds on a loaded machine too: how many settles fit in an interval depends
        // on the machine, but reads never come closer together than the interval, never outnumber
        // what asked for them, and stop when the terminal is quiet.
        let interval = Duration.milliseconds(600)
        let session = await terminal(host, interval: interval)
        #expect(await eventually { host.reads == 1 }, "once attached")
        #expect(session.terminalName == "✳ Claude Code" && session.repositoryLine == "app · main")
        try await Task.sleep(for: .milliseconds(800))
        #expect(host.reads == 1, "a quiet terminal is never asked")

        let settles = 4
        for _ in 0..<settles { await settle(session) }
        #expect(await eventually { host.reads >= 2 }, "output coming to rest is read")
        try await Task.sleep(for: interval * 3)
        let afterOutput = host.reads
        #expect(afterOutput <= 1 + settles, "never more reads than asked for them")
        let gaps = zip(host.readTimes.dropFirst(), host.readTimes).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 >= interval - .milliseconds(5) }, "reads at least an interval apart: \(gaps)")
        try await Task.sleep(for: .seconds(1))
        #expect(host.reads == afterOutput, "quiet again: no more reads")
        session.state = .disconnected
    }

    @Test("a name given on another device is picked up without reconnecting, and taking it away there shows the automatic name again")
    func nameFromElsewhere() async throws {
        let host = Host()
        let session = await terminal(host)
        #expect(await eventually { host.reads == 1 })
        #expect(session.terminalName == "app", "no title: the repository names it")
        host.given = "deploys"
        await settle(session)
        #expect(await eventually { session.terminalName == "deploys" })
        #expect(session.givenName == "deploys")
        host.given = ""
        host.title = "✳ Claude Code"
        await settle(session)
        #expect(await eventually { session.terminalName == "✳ Claude Code" })
        session.state = .disconnected
    }

    @Test("renaming here names the session for every device, shows at once, and a read begun before is not taken over it")
    func renaming() async throws {
        let host = Host()
        host.given = "old"
        let session = await terminal(host)
        #expect(await eventually { session.givenName == "old" })

        host.delay = .milliseconds(300)
        await settle(session)
        #expect(await eventually { host.reads == 2 }, "a read is on its way")
        session.rename(to: "  build; \"$HOME\"\n")
        #expect(session.terminalName == "build; \"$HOME\"", "shown at once, held to one line")
        let named = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: "build; \"$HOME\""))
        #expect(await eventually { host.commands.contains(named) }, "kept on the session as @glass-name")
        try await Task.sleep(for: .milliseconds(500))
        #expect(session.givenName == "build; \"$HOME\"", "the read begun before, which says \"old\", is not taken")

        host.delay = .zero
        host.given = "build; \"$HOME\""
        session.rename(to: nil)
        let unnamed = try #require(TerminalTmux.givenNameCommand(session: "glass-5", name: nil))
        #expect(await eventually { host.commands.contains(unnamed) }, "Use Automatic Name takes it away there")
        #expect(session.givenName == nil && session.terminalName == "app")
        session.state = .disconnected
    }

    @Test("the rule: a given name, the workgroup's label, the program's title, the repository, the folder; else nothing, and the switcher says the server")
    func rule() async throws {
        let host = Host()
        host.title = "✳ Claude Code"
        let session = await terminal(host)
        #expect(await eventually { session.terminalName == "✳ Claude Code" })
        session.workgroupLabel = "API"
        #expect(session.terminalName == "API", "a workgroup's label for the pane, as a Mac tab's configured label")
        #expect(TerminalWorkgroupOpening.slotTitle(session, position: 0) == "API")
        session.rename(to: "deploys")
        #expect(session.terminalName == "deploys", "a given name first")
        session.rename(to: nil)
        session.workgroupLabel = nil

        host.title = "alpha.example.com"
        host.repository = nil
        await settle(session)
        #expect(await eventually { session.terminalName == "Sources" }, "outside a repository, the folder")
        host.directory = "/home/ann"
        await settle(session)
        #expect(await eventually { session.terminalName == nil }, "home names nothing")
        #expect(TerminalWorkgroupOpening.slotTitle(session, position: 1) == "Terminal 2 · alpha")
        session.state = .disconnected
    }

    /// The owner, on the headset (0.4.318): "the tab names in the tab ornaments didn't keep the
    /// names, so neither did the grid or carousel views."
    @Test("the tab ornament, the grid and the carousel — every label on iPhone, iPad and Vision Pro — say the name kept on the session")
    func everySurface() async throws {
        let host = Host()
        host.given = "deploys"
        let session = await terminal(host)
        #expect(await eventually { session.givenName == "deploys" })
        func label(_ surface: TerminalWorkgroupOpening.LabelSurface) -> String {
            TerminalWorkgroupOpening.label(session, on: surface, position: 2)
        }
        #expect(label(.tabOrnament) == "deploys")
        #expect(label(.grid) == label(.tabOrnament) && label(.carousel) == label(.tabOrnament))
        #expect(TerminalWorkgroupOpening.LabelSurface.allCases.allSatisfy { label($0) == "deploys" },
                "the tab bar, the switcher and the connection ornament too")
        #expect(TerminalWorkgroupOpening.slotTitle(session, position: 2) == "deploys")

        // Nothing names it: the server, and in the switcher its slot.
        host.given = ""
        host.directory = "/home/ann"
        host.repository = nil
        await settle(session)
        #expect(await eventually { session.terminalName == nil })
        #expect([label(.tabOrnament), label(.grid), label(.carousel), label(.tabBar)] == Array(repeating: "alpha", count: 4))
        #expect(label(.switcher) == "Terminal 3 · alpha")
        session.state = .disconnected
    }

    @Test("a Mac's terminal does not read: its tabs ask tmux for themselves")
    func macDoesNotRead() async throws {
        var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        server.tmux = true
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        #expect(!session.readsTmuxPane)
    }
}
#endif
