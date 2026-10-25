#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// W11 (2026-10-09): a terminal's name says the repository and branch it is working in. The owner
/// runs many agents in tmux tabs; a tab said "✳ Claude Code" over a long folder path, which did
/// not say which repository, or which branch.
@MainActor
@Suite("Repository and branch in terminal names")
struct TerminalRepositoryTests {
    // MARK: Folders of the test's own

    /// A folder outside any home and any repository; the caller removes it.
    private func scratch() throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-repo-\(UUID().uuidString.prefix(8))").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @discardableResult
    private func folder(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func write(_ path: String, _ contents: String) throws {
        try folder((path as NSString).deletingLastPathComponent)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// A repository as far as the reader looks: a `.git` folder and its HEAD.
    @discardableResult
    private func repository(_ top: String, head: String = "ref: refs/heads/main") throws -> String {
        try write(top + "/.git/HEAD", head + "\n")
        return top
    }

    private func read(_ folder: String, home: String? = nil) -> TerminalRepository? {
        TerminalRepository.read(folder: folder, home: home)
    }

    /// Waits up to two seconds for `condition`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: Reading the files

    @Test("a repository on a branch is named by its top folder, and a folder inside it by the same")
    func onABranch() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/src/app")
        let sources = try folder(app + "/Sources/App")
        let expected = TerminalRepository(name: "app", branch: "main", root: app)
        #expect(read(app) == expected)
        #expect(read(sources) == expected, "a folder inside it")
        #expect(read(sources + "/") == expected, "written with a trailing slash")
    }

    @Test("a detached HEAD is its commit, seven characters")
    func detached() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/app", head: "0123ABCdef4567890123abcdef4567890123abcd")
        #expect(read(app)?.branch == "0123abc")
        #expect(TerminalRepository.branch(fromHead: "not a commit") == nil)
    }

    @Test("a branch with slashes is read whole")
    func slashes() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/app", head: "ref: refs/heads/feature/x")
        #expect(read(app)?.branch == "feature/x")
    }

    @Test("a worktree is named by its repository; a submodule by its own folder")
    func worktree() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/app")
        try write(app + "/.git/worktrees/app-fix/HEAD", "ref: refs/heads/fix/login\n")
        try write(app + "/.git/worktrees/app-fix/commondir", "../..\n")
        let worktree = try folder(root + "/app-fix")
        try folder(worktree + "/Sources")
        // Relative, as `git worktree add --relative-paths` writes it.
        try write(worktree + "/.git", "gitdir: ../app/.git/worktrees/app-fix\n")
        let expected = TerminalRepository(name: "app", branch: "fix/login", root: worktree)
        #expect(read(worktree + "/Sources") == expected, "a worktree of app is app, not app-fix")
        // Absolute, as git writes it by default.
        try write(worktree + "/.git", "gitdir: \(app)/.git/worktrees/app-fix\n")
        #expect(read(worktree) == expected)

        // A submodule's `.git` file points into its superproject, which keeps no common folder for it.
        try write(app + "/.git/modules/kit/HEAD", "ref: refs/heads/main\n")
        let kit = try folder(app + "/vendor/kit")
        try write(kit + "/.git", "gitdir: ../../.git/modules/kit\n")
        #expect(read(kit) == TerminalRepository(name: "kit", branch: "main", root: kit))
    }

    @Test("outside a repository, nothing; a `.git` without a HEAD is not one, and the walk goes on")
    func noRepository() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(read(try folder(root + "/notes")) == nil)
        #expect(read("relative/path") == nil)
        let outer = try repository(root + "/outer")
        let inner = try folder(outer + "/inner")
        try folder(inner + "/.git")
        #expect(read(inner)?.name == "outer")
        try FileManager.default.removeItem(atPath: inner + "/.git")
        try write(inner + "/.git", "not a pointer\n")
        #expect(read(inner)?.name == "outer")
    }

    @Test("the walk stops at the home folder: a dotfiles repository there claims nothing")
    func homeIsTheBoundary() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = try repository(root + "/home")
        let notes = try folder(home + "/src/notes")
        #expect(read(notes, home: home) == nil)
        #expect(read(notes, home: nil)?.name == "home", "without the boundary the dotfiles would claim it")
        #expect(read(home, home: home) == nil)
        let app = try repository(home + "/src/app")
        #expect(read(try folder(app + "/Sources"), home: home)?.name == "app", "a repository below home is found")
    }

    @Test("the walk stops at its volume's root, and never reads a volume that is not local")
    func volumes() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let outer = try repository(root + "/outer")
        let volume = try folder(outer + "/Volume")
        let inside = try folder(volume + "/notes")
        let startup = TerminalRepository.Volume(path: "/", isLocal: true)
        let local = [startup, TerminalRepository.Volume(path: volume, isLocal: true)]
        #expect(TerminalRepository.read(folder: inside, home: nil, volumes: local) == nil, "the walk stops at the volume's root")
        #expect(TerminalRepository.read(folder: inside, home: nil, volumes: [startup])?.name == "outer")
        let app = try repository(volume + "/app")
        #expect(TerminalRepository.read(folder: app, home: nil, volumes: local)?.name == "app")
        let network = [startup, TerminalRepository.Volume(path: volume, isLocal: false)]
        #expect(TerminalRepository.read(folder: app, home: nil, volumes: network) == nil, "a network volume is never read")
        #expect(TerminalRepository.volume(of: root, in: TerminalRepository.mountedVolumes())?.isLocal == true,
                "the system's own table says where the test's folder is")
    }

    // MARK: The cache

    @Test("the cache reads a folder again after a branch change, once the interval has passed")
    func cache() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/app")
        final class Clock { var now = ContinuousClock.now }
        let clock = Clock()
        let cache = TerminalRepositoryCache(now: { clock.now })
        let key = TerminalRepositoryCache.Key(host: nil, folder: app)
        func ask() async -> TerminalRepositoryAnswer {
            await cache.answer(for: key, maximumAge: .seconds(5)) {
                await TerminalRepository.readOffMain(folder: app, home: nil)
            }
        }
        #expect(await ask().repository?.branch == "main")
        try write(app + "/.git/HEAD", "ref: refs/heads/feature/x\n")
        #expect(await ask().repository?.branch == "main", "within the interval the answer is kept")
        clock.now = clock.now.advanced(by: .seconds(5))
        #expect(await ask().repository?.branch == "feature/x", "after it the folder is read again")

        // No answer is not kept: the next ask tries again.
        @MainActor final class Count { var reads = 0 }
        let count = Count()
        let host = TerminalRepositoryCache.Key(host: UUID(), folder: "/srv/app")
        for _ in 0..<2 {
            _ = await cache.answer(for: host, maximumAge: .seconds(5)) {
                count.reads += 1
                return .unknown
            }
        }
        #expect(count.reads == 2)
    }

    // MARK: The naming rule

    @Test("the name and the line under it: a program's title still wins, else the repository; outside one, the folder")
    func naming() {
        let home = "/Users/ann"
        let app = TerminalRepository(name: "app", branch: "main", root: "/Users/ann/src/app")
        let sources = "/Users/ann/src/app/Sources/App"
        func name(given: String? = nil, title: String? = nil, directory: String?, repository: TerminalRepository?) -> String {
            TerminalSessionNaming.name(given: given, title: title, directory: directory, home: home, session: "glass-1",
                                       repository: repository)
        }
        // A program's title, in a repository.
        #expect(name(title: "✳ Claude Code", directory: sources, repository: app) == "✳ Claude Code")
        #expect(TerminalSessionNaming.location(directory: sources, home: home, repository: app) == "app · main · Sources/App")
        // No title: the repository stands in for the folder.
        #expect(name(directory: sources, repository: app) == "app", "not \"App\", the folder")
        #expect(TerminalSessionNaming.location(directory: app.root, home: home, repository: app) == "app · main",
                "at the top there is no folder to add")
        #expect(name(given: "deploys", directory: sources, repository: app) == "deploys", "a given name still wins")
        // Outside a repository, as before.
        #expect(name(directory: "/Users/ann/notes", repository: nil) == "notes")
        #expect(TerminalSessionNaming.location(directory: "/Users/ann/notes", home: home, repository: nil) == "~/notes")
        #expect(TerminalSessionNaming.location(directory: nil, home: home, repository: nil) == nil)
        // A branch not known says the repository alone.
        #expect(TerminalSessionNaming.location(directory: nil, home: nil, repository: TerminalRepository(name: "app")) == "app")
        // The tab's rule is this one.
        #expect(MacWorkspaceTabNaming.automaticTitle(MacWorkspacePaneContext(title: nil, directory: sources), repository: app, home: home) == "app")
        #expect(MacWorkspaceTabNaming.automaticTitle(nil, repository: app, home: home) == "app")
    }

    @Test("a long branch loses its middle, so its start and end both still read")
    func longBranch() {
        let long = "feature/billing-export-with-a-very-long-name-retry"
        let shown = TerminalSessionNaming.shortenedBranch(long)
        #expect(shown == "feature/billing…ong-name-retry")
        #expect(shown.count == TerminalSessionNaming.maximumBranchLength)
        #expect(TerminalSessionNaming.shortenedBranch("main") == "main")
        let line = TerminalSessionNaming.location(directory: nil, home: nil, repository: TerminalRepository(name: "app", branch: long))
        #expect(line == "app · feature/billing…ong-name-retry")
    }

    // MARK: A Mac tab

    @Test("a Mac tab in a repository: its name and the line under it, read from its folder; a checkout shows; outside, as before")
    func macTab() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = try repository(root + "/src/app")
        let sources = try folder(app + "/Sources")
        let notes = try folder(root + "/notes")
        let suite = "TerminalRepositoryTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tab = MacWorkspaceController(workspaceID: UUID(), defaults: defaults)
        tab.paneContextInterval = .zero
        tab.localRepositoryInterval = .zero
        tab.repositoryCache = TerminalRepositoryCache()
        let pane = try #require(tab.focusedPaneID)
        func identity() -> MacWorkspaceWindowIdentity {
            tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
        }

        tab.updatePaneContext(title: nil, directory: sources, for: pane)
        #expect(await eventually { identity() == MacWorkspaceWindowIdentity(title: "app", subtitle: "app · main · Sources") })
        tab.updatePaneContext(title: "✳ Claude Code", directory: sources, for: pane)
        #expect(identity() == MacWorkspaceWindowIdentity(title: "✳ Claude Code", subtitle: "app · main · Sources"))
        // Show All Terminals says the same, and typing the branch or the folder finds it.
        let tile = MacTerminalExposeModel.tile(for: tab, servers: [], home: "/Users/ann")
        #expect(tile.title == "✳ Claude Code" && tile.location == "app · main · Sources")
        #expect(tile.folder == sources && tile.matches("main") && tile.matches("src/app"))

        try write(app + "/.git/HEAD", "ref: refs/heads/feature/x\n")
        tab.refreshRepositories()
        #expect(await eventually { identity().subtitle == "app · feature/x · Sources" }, "a checkout shows at the next look")

        tab.updatePaneContext(title: nil, directory: notes, for: pane)
        #expect(await eventually { identity() == MacWorkspaceWindowIdentity(title: "notes", subtitle: notes) })
        tab.closeAllSessions(sessionManager: SessionManager(loadImmediately: false))
    }

    // MARK: Asking a host

    @Test("a host is asked with one command: the folder is quoted as its argument, never part of the script")
    func remoteCommand() {
        let folder = "/home/ann/it's a \"repo\" $HOME"
        #expect(TerminalRepository.remoteCommand(folder: folder)
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; case $1 in /*) ;; *) exit 0;; esac; command -v git >/dev/null 2>&1 || exit 0; if [ -x /usr/bin/xcode-select ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then exit 0; fi; cd -- "$1" 2>/dev/null || exit 0; t=$(git rev-parse --show-toplevel --git-common-dir 2>/dev/null) || exit 0; b=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null); h=$(cd -- "$HOME" 2>/dev/null && pwd -P); printf '\''__glass_repo__\n%s\n%s\n%s\n'\'' "$t" "$b" "$h"' _ '/home/ann/it'\''s a "repo" $HOME'"#)
    }

    @Test("a host's answer: the top folder, git's common folder, the branch and home, after the marker")
    func remoteAnswer() {
        func answer(_ lines: [String]) -> TerminalRepositoryAnswer {
            // A login script's chatter comes first.
            TerminalRepository.parseRemote((["Welcome to alpha", TerminalRepository.remoteMarker] + lines).joined(separator: "\n") + "\n")
        }
        #expect(answer(["/home/ann/src/app", "../../.git", "main", "/home/ann"])
                == .repository(TerminalRepository(name: "app", branch: "main", root: "/home/ann/src/app")))
        #expect(answer(["/home/ann/src/app-fix", "/home/ann/src/app/.git", "fix/login", "/home/ann"])
                == .repository(TerminalRepository(name: "app", branch: "fix/login", root: "/home/ann/src/app-fix")),
                "a worktree is its repository's")
        #expect(answer(["/srv/app", ".git", "0123abc", "/home/ann"]).repository?.branch == "0123abc")
        #expect(answer(["/srv/app", ".git", "", "/home/ann"]) == .repository(TerminalRepository(name: "app", root: "/srv/app")))
        #expect(answer(["/home/ann", ".git", "main", "/home/ann"]) == .none, "a repository at home holds dotfiles")
        #expect(answer(["/home", ".git", "main", "/home/ann"]) == .none, "and one above it")
        #expect(TerminalRepository.parseRemote("") == .none, "no git, or no repository: nothing")
        #expect(TerminalRepository.parseRemote("__glass_repo__\nrelative\n.git\nmain\n") == .none)
        #expect(TerminalRepository.path(fromReported: "file://alpha/home/ann/my%20app") == "/home/ann/my app")
        #expect(TerminalRepository.path(fromReported: "/srv/app") == "/srv/app")
        #expect(TerminalRepository.path(fromReported: "alpha:/srv") == nil)
    }

    /// A Mac's `/usr/bin/git` works only with its developer tools; without them it offers to
    /// install them, and the host's command does not run it.
    nonisolated static let hasGit = LiveProcess.run("/usr/bin/xcode-select", ["-p"], environment: ["PATH": "/usr/bin:/bin"]).status == 0

    /// Repositories git made, asked through `sh` as a host would be. Git's own configuration is
    /// left out — no system or global files — so the owner's settings never apply.
    @Test("live: the host's command, run by sh in repositories git made", .enabled(if: TerminalRepositoryTests.hasGit))
    func remoteLive() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = try folder(root + "/home")
        let environment = ["PATH": "/usr/bin:/bin", "HOME": home, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        // Each run off the main actor (`LiveProcess.runDetached`).
        @discardableResult func git(_ arguments: [String], in folder: String) async -> (output: String, status: Int32) {
            await LiveProcess.runDetached("/usr/bin/git", ["-C", folder, "-c", "user.name=ann", "-c", "user.email=ann@example.com"] + arguments,
                                          environment: environment)
        }
        func ask(_ folder: String) async -> TerminalRepositoryAnswer {
            let command = TerminalRepository.remoteCommand(folder: folder)
            return TerminalRepository.parseRemote(await LiveProcess.runDetached("/bin/sh", ["-c", command], environment: environment).output)
        }
        let name = "it's a \"repo\""
        let app = try folder(root + "/src/" + name)
        try #require(await git(["init", "-q", "-b", "main"], in: app).status == 0)
        try #require(await git(["commit", "-q", "--allow-empty", "-m", "one"], in: app).status == 0)
        let sources = try folder(app + "/Sources")

        #expect(await ask(app).repository.map { [$0.name, $0.branch] } == [name, "main"])
        #expect(await ask(sources).repository.map { [$0.name, $0.branch] } == [name, "main"], "a folder inside it")
        try #require(await git(["worktree", "add", "-q", "../app-fix", "-b", "feature/x"], in: app).status == 0)
        #expect(await ask(root + "/src/app-fix").repository.map { [$0.name, $0.branch] } == [name, "feature/x"],
                "a worktree is its repository's, with its own branch")
        try #require(await git(["checkout", "-q", "--detach"], in: app).status == 0)
        let commit = await git(["rev-parse", "--short=7", "HEAD"], in: app).output.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(await ask(app).repository?.branch == commit && commit.count == 7)
        let notes = try folder(root + "/notes")
        #expect(await ask(notes) == .none, "outside a repository")
        #expect(await ask(root + "/gone") == .none, "a folder that is gone")
        #expect(await ask("") == .none, "no folder is not where the shell started")
        #expect(await ask("Sources") == .none, "nor is a folder that isn't a full path")
        try #require(await git(["init", "-q", "-b", "main"], in: home).status == 0)
        let homeNotes = try folder(home + "/notes")
        #expect(await ask(homeNotes) == .none, "a repository at home holds dotfiles")
    }

    // MARK: Active, on every device

    @Test("the listing carries a session's repository and branch, and Active names and places it by them")
    func listing() throws {
        func line(directory: String, repository: String, branch: String, title: String = "alpha.example.com") -> String {
            ["glass-2", "0", "1", "", "4242", "1790000000", "/private/tmp/tmux-501/default", "zsh",
             "alpha.example.com", "alpha", "", directory, repository, branch, title].joined(separator: "\t")
        }
        let output = [line(directory: "/home/ann/src/app/Sources", repository: "app", branch: "feature/x"),
                      line(directory: "/home/ann/src/app", repository: "app", branch: "main", title: "✳ Claude Code"),
                      line(directory: "/home/ann/notes", repository: "", branch: ""),
                      "__glass_home__\t/home/ann"].joined(separator: "\n") + "\n"
        guard case .sessions(let sessions) = TerminalTmux.parse(output) else {
            Issue.record("not read as a list")
            return
        }
        try #require(sessions.count == 3)
        #expect(sessions[0].repository == TerminalRepository(name: "app", branch: "feature/x"))
        #expect(sessions[0].displayName == "app", "no program titled it: the repository names it")
        #expect(GlassTerminalCapability.runningDetails(sessions[0]) == "app · feature/x · Detached")
        #expect(sessions[1].displayName == "✳ Claude Code")
        #expect(GlassTerminalCapability.runningDetails(sessions[1]) == "app · main · Detached")
        #expect(sessions[2].repository == nil && sessions[2].displayName == "notes")
        #expect(GlassTerminalCapability.runningDetails(sessions[2]) == "~/notes · Detached", "outside a repository, as before")
    }

    @Test("the command keeping a repository on a session quotes every word, escapes a trailing ;, and with none unsets both")
    func repositoryCommand() {
        let target = "=glass-1:"
        #expect(TerminalTmux.repositoryArguments(session: "glass-1", repository: TerminalRepository(name: "app", branch: "fix;"))
                == ["-u", "set-option", "-t", target, "@glass-repo", "app", ";", "set-option", "-t", target, "@glass-branch", "fix\\;"])
        #expect(TerminalTmux.repositoryArguments(session: "glass-1", repository: TerminalRepository(name: "app"))
                == ["-u", "set-option", "-t", target, "@glass-repo", "app", ";", "set-option", "-u", "-t", target, "@glass-branch"])
        #expect(TerminalTmux.repositoryArguments(session: "glass-1", repository: nil)
                == ["-u", "set-option", "-u", "-t", target, "@glass-repo", ";", "set-option", "-u", "-t", target, "@glass-branch"])
        #expect(TerminalTmux.repositoryCommand(session: "glass-1", repository: TerminalRepository(name: "app", branch: "feature/x"))
                == #"sh -c 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"; tmux '\''-u'\'' '\''set-option'\'' '\''-t'\'' '\''=glass-1:'\'' '\''@glass-repo'\'' '\''app'\'' '\'';'\'' '\''set-option'\'' '\''-t'\'' '\''=glass-1:'\'' '\''@glass-branch'\'' '\''feature/x'\'''"#)
        #expect(TerminalTmux.repositoryCommand(session: "a:b", repository: nil) == nil, "a session name tmux would misread")
    }

    /// Against a private tmux server: every run names its socket — through `-S`, the listing's
    /// server arguments, or a `tmux` on the PATH that adds it — so the default server, which holds
    /// the owner's sessions, is never reached (rule 63).
    @Test("live: a repository kept on a session through each builder reads back in the listing",
          .enabled(if: TerminalTmuxTests.tmux != nil))
    func listingLive() async throws {
        let tmux = try #require(TerminalTmuxTests.tmux)
        let folder = URL(fileURLWithPath: "/tmp/gpt-\(UUID().uuidString.prefix(8).lowercased())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appendingPathComponent("s").path
        let environment = ["PATH": "/usr/bin:/bin", "HOME": folder.path]
        // Each run off the main actor (`LiveProcess.runDetached`).
        @discardableResult func run(_ arguments: [String]) async -> (output: String, status: Int32) {
            await LiveProcess.runDetached(tmux, ["-S", socket] + arguments, environment: environment)
        }
        defer { _ = LiveProcess.run(tmux, ["-S", socket, "kill-server"], environment: environment) }
        func listed() async -> TerminalTmux.Session? {
            let script = TerminalTmux.listScript(tmux: TerminalTmux.quoted(tmux), serverArguments: ["-S", socket])
            let output = await LiveProcess.runDetached("/bin/sh", ["-c", script], environment: environment).output
            guard case .sessions(let sessions) = TerminalTmux.parse(output) else { return nil }
            return sessions.first { $0.name == "glass-1" }
        }
        #expect(await run(["-u", "-f", "/dev/null", "new-session", "-d", "-s", "glass-1", "-c", folder.path, "-x", "80", "-y", "10",
                     "/bin/sleep", "600"]).status == 0)
        let first = await listed()
        #expect(first != nil && first?.repository == nil)

        // As a local tab keeps it: argv.
        let odd = TerminalRepository(name: "it's \"app\" $HOME", branch: "fix;")
        #expect(await run(try #require(TerminalTmux.repositoryArguments(session: "glass-1", repository: odd))).status == 0)
        #expect(await listed()?.repository == odd)

        // As an SSH tab does: the exact command, through sh, with a tmux on the PATH that names the socket.
        let bin = folder.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let shim = bin.appendingPathComponent("tmux")
        try Data("#!/bin/sh\nexec \(TerminalTmux.quoted(tmux)) -S \(TerminalTmux.quoted(socket)) \"$@\"\n".utf8).write(to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let throughShim = ["PATH": "\(bin.path):/usr/bin:/bin", "HOME": folder.path]
        let app = TerminalRepository(name: "app", branch: "feature/x")
        let command = try #require(TerminalTmux.repositoryCommand(session: "glass-1", repository: app))
        #expect(await LiveProcess.runDetached("/bin/sh", ["-c", command], environment: throughShim).status == 0)
        #expect(await listed()?.repository == app)

        #expect(await run(try #require(TerminalTmux.repositoryArguments(session: "glass-1", repository: nil))).status == 0)
        #expect(await listed()?.repository == nil, "nothing found takes them away")
    }

    // MARK: An SSH tab

    @MainActor private final class Commands {
        var all: [String] = []
        var branch = "main"
        var inRepository = true
    }

    /// W19: the tab asks in its session's one read (W11's `paneStateCommand`), which says the
    /// folder and the repository together, where it asked twice before.
    @Test("an SSH tab in tmux asks its host where the shell is and which repository that is, and keeps it on the session")
    func sshTab() async throws {
        let suite = "TerminalRepositoryTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")
        server.tmux = true
        let folder = "/home/ann/src/app/Sources"
        let read = try #require(TerminalTmux.paneStateCommand(session: "glass-5"))
        let commands = Commands()
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        session.tmuxSessionName = "glass-5"
        session.tmuxPaneReadInterval = .zero
        session.tmuxCommandRunner = { command in
            commands.all.append(command)
            guard command == read else { return "" }
            // No program's title: tmux's own is the host's name.
            let pane = [TerminalTmux.paneMarker, "/home/ann", folder, "alpha.example.com", "alpha", "", "", "", "alpha.example.com"]
                .joined(separator: "\t") + "\n"
            return commands.inRepository
                ? pane + "__glass_repo__\n/home/ann/src/app\n../.git\n\(commands.branch)\n/home/ann\n" : pane
        }
        session.state = .connected
        await session.waitForTmuxAttach()
        let broker = MacLiveSessionBroker()
        let manager = SessionManager(loadImmediately: false)
        let request = MacLiveSessionWorkspaceRouter.launchRequest(for: session, sessionManager: manager, broker: broker)
        let tab = MacWorkspaceController(request: request, liveSessionBroker: broker, defaults: defaults)
        tab.remoteRepositoryInterval = .zero
        tab.repositoryCache = TerminalRepositoryCache()
        func identity() -> MacWorkspaceWindowIdentity { tab.windowIdentity(servers: [server]) }

        tab.refreshRepositories()
        #expect(await eventually {
            identity() == MacWorkspaceWindowIdentity(title: "app", subtitle: "app · main · ann@alpha.example.com:22")
        })
        let kept = try #require(TerminalTmux.repositoryCommand(session: "glass-5", repository: TerminalRepository(name: "app", branch: "main")))
        #expect(await eventually { commands.all.contains(kept) }, "kept on the host's session, for Active elsewhere")

        commands.branch = "feature/x"
        tab.refreshRepositories()
        #expect(await eventually { identity().subtitle == "app · feature/x · ann@alpha.example.com:22" })

        commands.inRepository = false
        tab.refreshRepositories()
        #expect(await eventually { identity() == MacWorkspaceWindowIdentity(title: "Sources", subtitle: "ann@alpha.example.com:22") },
                "outside a repository, its folder, as Active names the session (W19: the host says where the shell is)")
        let cleared = try #require(TerminalTmux.repositoryCommand(session: "glass-5", repository: nil))
        #expect(await eventually { commands.all.contains(cleared) })
        #expect(commands.all.filter { $0 == kept }.count == 1, "only a change is sent")
        tab.closeAllSessions(sessionManager: manager)
    }
}
#endif
