//
//  MacTmuxHost.swift
//  Glass Power Tools — GlassTerminalHost
//
//  The background process that keeps this Mac's local terminals running (D66, 2026-10-12). The
//  launchd job (`MacTmuxService`) runs it; it starts tmux as its child and waits for it. A program
//  answers to the process that started its chain, and macOS asks for privacy permissions in that
//  one's name: under a tmux launchd ran itself, reading the Desktop from a pane asked "tmux would like
//  to access files in your Desktop folder". Under this host, panes answer to Glass Power Tools, whose
//  permissions they have always had, and the job keeps them out of reach of any app's Force Quit.
//
//  Since 2026-11-24 (D115) it is the whole of a small app inside Glass Power Tools,
//  `Glass Power Tools Terminal Host.app` (`TerminalHost/`): the app's bundle ID and signature, so macOS
//  knows it as Glass Power Tools and its permissions are the app's (measured in the macOS VM), and a few
//  hundred kilobytes where the app is 229 MB. It runs from a copy named `Glass Power Tools.app`
//  (`MacTmuxHostCopy`). Until then the app's own executable was the host, started with the same
//  arguments, and then a copy of the whole app (D114).
//
//  The host starts nothing but tmux: no window, no AppKit. It ends when tmux does. `tmux -D`, the
//  foreground mode launchd needs, turns `exit-empty` off, so the server would outlive its last session
//  (measured: an empty -D server stayed up); the host turns it back on once the first session is made,
//  and ends a server that is given none.
//

#if os(macOS)
import Darwin
import Foundation

public nonisolated enum MacTmuxHost {
    /// The argument that starts the host, followed by tmux's path and, for a test's private server only,
    /// the server's own arguments.
    public static let flag = "--tmux-host"
    /// How long a server the host started waits for its first session before it is ended.
    static let firstSessionWait: Duration = .seconds(60)

    /// The argument that only starts the program and ends it: a new copy run once (`MacTmuxHostCopy`), so
    /// macOS's first-run scan of it isn't paid while a terminal waits for its server.
    public static let readyFlag = "--tmux-host-ready"

    /// What the program does when started with `arguments`.
    enum Request: Equatable {
        case ready
        case host(tmux: String, serverArguments: [String])
    }

    /// The helper's whole program (`run`), ended with its status.
    public static func main(_ arguments: [String] = CommandLine.arguments) -> Never {
        exit(run(arguments))
    }

    /// The host when asked to be one, a start and end when asked to be ready, and nothing otherwise — opened from
    /// the Finder, say, it has nothing to do (64, a usage error). The status the program ends with.
    static func run(_ arguments: [String]) -> Int32 {
        switch request(arguments) {
        case .ready: 0
        case .host(let tmux, let serverArguments): serve(tmux: tmux, serverArguments: serverArguments)
        case nil: 64
        }
    }

    /// What `arguments` ask for; nil when they ask for nothing the host does. tmux by its full path only,
    /// never a name looked up.
    static func request(_ arguments: [String]) -> Request? {
        if arguments.count == 2, arguments[1] == readyFlag { return .ready }
        guard arguments.count >= 3, arguments[1] == flag, arguments[2].hasPrefix("/") else { return nil }
        return .host(tmux: arguments[2], serverArguments: Array(arguments.dropFirst(3)))
    }

    /// Starts tmux in the foreground as this process's child, sees that it ends with its last
    /// session, and waits for it. Its exit status; 1 when it could not start.
    static func serve(tmux: String, serverArguments: [String] = [], firstSessionWait: Duration = firstSessionWait,
                      poll: Duration = .milliseconds(200)) -> Int32 {
        let argv = ([tmux] + serverArguments + ["-u", "-D"]).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        // The server keeps whatever it inherits for as long as it runs: nothing but its standard
        // output and error, as `GlassSpawn.output` gives the tmux it runs.
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addinherit_np(&actions, STDOUT_FILENO)
        posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // The server's signals as a new process's, though the host serves from its main thread.
        GlassSpawn.prepare(&attributes)
        var pid: pid_t = 0
        guard posix_spawn(&pid, tmux, &actions, &attributes, argv, environ) == 0 else { return 1 }

        var waited: Duration = .zero
        while true {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid { return exitStatus(status) }
            if hasSessions(tmux: tmux, serverArguments: serverArguments) {
                _ = ask(tmux, serverArguments + ["set-option", "-g", "exit-empty", "on"])
                break
            }
            if waited >= firstSessionWait {
                _ = ask(tmux, serverArguments + ["kill-server"])
                break
            }
            Thread.sleep(forTimeInterval: Double(poll.components.seconds) + Double(poll.components.attoseconds) / 1e18)
            waited += poll
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        return exitStatus(status)
    }

    static func hasSessions(tmux: String, serverArguments: [String]) -> Bool {
        let names = ask(tmux, serverArguments + ["-N", "list-sessions", "-F", "#{session_name}"]) ?? ""
        return !names.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// tmux, asked something with the host's own environment, which is the job's.
    private static func ask(_ tmux: String, _ arguments: [String]) -> String? {
        GlassSpawn.output(of: tmux, arguments,
                          environment: ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" })
    }

    /// `WEXITSTATUS`, or 128 and the signal for a child a signal ended (Swift has neither macro).
    static func exitStatus(_ status: Int32) -> Int32 {
        status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }
}
#endif
