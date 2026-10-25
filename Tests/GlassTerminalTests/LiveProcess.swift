import Foundation
import GlassTerminalEmulator

/// Runs a program for a live test: what it printed, and how it exited.
///
/// `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT`, not `Process`: `Process` leaves the test
/// process's other descriptors open in the child, and a tmux server started there keeps them for
/// as long as it runs. Another test's pipe was among them, so that test's read waited for this
/// server's sessions to end, holding the main actor for most of a minute and every test queued
/// behind it (2026-10-08). The app's own `MacLocalTmux.run` spawns the same way.
enum LiveProcess {
    nonisolated static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                                includingErrors: Bool = false) -> (output: String, status: Int32) {
        var output: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return ("", -1) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        if includingErrors {
            posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO)
        } else {
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // As the app's own spawns: none of the test process's descriptors, and signals unblocked
        // whatever thread runs this (`GlassSpawn`) — `runDetached` runs it off the main one.
        GlassSpawn.prepare(&attributes)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(output[1])
        let reader = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
        guard spawned == 0 else { return ("", -1) }
        let data = reader.readDataToEndOfFile()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        // WIFEXITED / WEXITSTATUS, which Swift does not import.
        let exitStatus = status & 0x7f == 0 ? (status >> 8) & 0xff : -1
        return (String(decoding: data, as: UTF8.self), exitStatus)
    }

    /// The same, waited for off the caller's actor. This target's tests are on the main actor by
    /// default, and a test waiting there for a program held it from every other test in the run:
    /// a full run's main thread was held 14.7 s at a stretch, and tests polling to a deadline failed
    /// inside it (2026-10-24).
    nonisolated static func runDetached(_ executable: String, _ arguments: [String], environment: [String: String],
                                        includingErrors: Bool = false) async -> (output: String, status: Int32) {
        await offMainActor { run(executable, arguments, environment: environment, includingErrors: includingErrors) }
    }
}

/// Blocking work — a program run, a wait on something outside the process — done off the caller's
/// actor, for the same reason as `LiveProcess.runDetached`. On a Dispatch queue, not in a detached
/// task: blocking work holds a thread for as long as it waits, and Swift's concurrency has only a
/// few, which every other async test in the run shares; Dispatch adds threads as its threads block.
nonisolated func offMainActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
    }
}
