//
//  GlassSpawn.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  How the app starts a program of its own with `posix_spawn` — tmux, mostly — rather than with
//  `Process`, which leaves the app's descriptors open in the child (a tmux server kept them for as
//  long as it ran).
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
}
#endif
