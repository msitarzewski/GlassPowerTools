//
//  GlassSpawn.swift
//  Glass Power Tools — GlassTerminalHost
//
//  How the app starts a program of its own with `posix_spawn` — tmux, mostly — rather than with
//  `Process`, which leaves the app's descriptors open in the child (a tmux server kept them for as
//  long as it ran). Here rather than in the terminal's modules since 2026-11-24, so the terminal host
//  (`MacTmuxHost`), a small program of its own, starts tmux by the same rules as the app.
//
//  2026-10-24, found by the test audit: a child inherits the blocked signals of the thread that
//  spawns it, and the threads Swift's concurrency and Dispatch run work on block most of them —
//  SIGHUP, SIGINT, SIGTERM and SIGCHLD among them (mask fbfee027; the main thread blocks none). A
//  tmux server started from one answered `kill-server` and ignored it, and SIGTERM too, since its
//  panes never got the hangup and it could not reap them; every pane it started would have begun
//  with Ctrl-C blocked. Foundation's `Process` starts its children with no signal blocked and every
//  one at its default, and a server it started from the same thread ended as asked. So does this.
//

#if os(macOS)
import Darwin
import Foundation

public nonisolated enum GlassSpawn {
    /// None of the app's descriptors (`POSIX_SPAWN_CLOEXEC_DEFAULT`), and signals as a new process
    /// has them, whatever thread spawns it: none blocked, each at its default. `flags` adds others
    /// (`POSIX_SPAWN_SETSID`, say).
    public static func prepare(_ attributes: inout posix_spawnattr_t?, flags: Int32 = 0) {
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        var defaults = sigset_t()
        sigfillset(&defaults)
        sigdelset(&defaults, SIGKILL)
        sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigmask(&attributes, &unblocked)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | flags))
    }

    /// Runs `executable` with `arguments` and `environment` (`NAME=value` each), started as `prepare` starts it, with
    /// nothing for input and its errors dropped, and returns what it printed; nil when it couldn't start or didn't end
    /// with status 0. `posix_spawn` and `waitpid` rather than `Process`: `waitUntilExit` spins the caller's run loop,
    /// and the app asks tmux this way on the main thread while a tab is set up. tmux answers in milliseconds.
    public static func output(of executable: String, _ arguments: [String], environment: [String]) -> String? {
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return nil }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&actions, output[0])
        posix_spawn_file_actions_addclose(&actions, output[1])
        // Nothing else of the caller's: a claim can start the tmux server, which keeps whatever its
        // first client inherited for as long as it runs — another run's pipe, or a pane's terminal,
        // or the signals the calling thread blocks. Reads and End run off the main thread.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        prepare(&attributes)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = environment.map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(output[1])
        let reader = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
        guard spawned == 0 else { return nil }
        let data = reader.readDataToEndOfFile()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        return status == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
#endif
