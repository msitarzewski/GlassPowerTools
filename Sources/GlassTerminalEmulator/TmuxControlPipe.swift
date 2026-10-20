//
//  TmuxControlPipe.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A local pane's tmux as a control-mode client on pipes (`tmux -C`, D83), in place of SwiftTerm's
//  local process. SwiftTerm reads its PTY through GCD, and with tmux's way of writing — a large chunk
//  as a burst ends — it left the rest in the PTY until tmux wrote again (2026-10-19, measured: a
//  900-row burst stopped short in three runs of eight under load, and arrived the moment tmux wrote
//  anything; the same reader never stalled on a plain shell, and a `poll` reader never stalled on
//  tmux). A control client needs no terminal, so tmux gets pipes, and they are read here until they
//  are empty: nothing waits for a next write.
//

#if os(macOS)
import Foundation

@MainActor
final class TmuxControlPipe {
    private(set) var processID: pid_t = 0
    private(set) var isRunning = false
    /// What tmux wrote, in order, on the main queue.
    var onOutput: ((Data) -> Void)?
    /// tmux ended: its wait status, when it could be read.
    var onExit: ((Int32?) -> Void)?

    private let input: Int32
    private let output: Int32
    private let readQueue = DispatchQueue(label: "glass.tmux-control.read")
    private let writeQueue = DispatchQueue(label: "glass.tmux-control.write")
    private var source: DispatchSourceRead?
    private var inputClosed = false

    init?(executable: String, arguments: [String], environment: [String]?, currentDirectory: String?) {
        var toChild: [Int32] = [-1, -1], fromChild: [Int32] = [-1, -1]
        guard pipe(&toChild) == 0 else { return nil }
        guard pipe(&fromChild) == 0 else {
            close(toChild[0]); close(toChild[1])
            return nil
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, toChild[0], 0)
        posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        if let currentDirectory { posix_spawn_file_actions_addchdir_np(&actions, currentDirectory) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // None of the app's descriptors: a tmux server this starts keeps what its first client had.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = (environment ?? ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }).map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(toChild[0])
        close(fromChild[1])
        input = toChild[1]
        output = fromChild[0]
        guard spawned == 0 else {
            close(input); close(output)
            return nil
        }
        processID = pid
        isRunning = true
        _ = fcntl(output, F_SETFL, fcntl(output, F_GETFL) | O_NONBLOCK)
        // A pipe tmux has gone from must not end the app when a write finds it so.
        _ = fcntl(input, F_SETNOSIGPIPE, 1)
    }

    /// Starts reading; what arrives goes to `onOutput`.
    func start() {
        let source = Self.reader(output, queue: readQueue) { [weak self] chunk, ended in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !chunk.isEmpty { self.onOutput?(chunk) }
                    if ended { self.finished() }
                }
            }
        }
        self.source = source
        source.resume()
    }

    /// Commands for tmux, written in order off the main thread.
    func write(_ data: Data) {
        guard isRunning, !inputClosed, !data.isEmpty else { return }
        let input = input
        writeQueue.async { Self.writeAll(data, to: input) }
    }

    /// Ends the client: its input closes, which detaches it; tmux keeps the session.
    func terminate() {
        guard isRunning, !inputClosed else { return }
        inputClosed = true
        let input = input, pid = processID
        writeQueue.async { Self.closeAndEnd(input, pid) }
    }

    private func finished() {
        guard isRunning else { return }
        isRunning = false
        source?.cancel()
        source = nil
        if !inputClosed {
            inputClosed = true
            let input = input
            writeQueue.async { _ = close(input) }
        }
        let pid = processID
        // Reaped off the main thread: the client is ending, and may take a moment.
        DispatchQueue.global().async {
            let status = Self.reap(pid)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onExit?(status) }
            }
        }
    }

    // Off the main thread, so built where no actor is: a closure made in this class's methods would
    // be the main actor's, and Swift stops the app when GCD runs it elsewhere.

    /// Reads everything there is each time the pipe has something: none is left waiting.
    private nonisolated static func reader(_ output: Int32, queue: DispatchQueue,
                                           deliver: @escaping @Sendable (Data, Bool) -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: output, queue: queue)
        source.setEventHandler {
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var ended = false
            while true {
                let count = read(output, &buffer, buffer.count)
                if count > 0 {
                    collected.append(contentsOf: buffer[..<count])
                } else if count == 0 {
                    ended = true
                    break
                } else if errno == EINTR {
                    continue
                } else {
                    // EAGAIN: empty for now.
                    break
                }
            }
            deliver(collected, ended)
        }
        source.setCancelHandler { _ = close(output) }
        return source
    }

    private nonisolated static func writeAll(_ data: Data, to input: Int32) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(input, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private nonisolated static func closeAndEnd(_ input: Int32, _ pid: pid_t) {
        close(input)
        // A client that lingers is ended.
        usleep(200_000)
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == 0 { kill(pid, SIGTERM) }
    }

    private nonisolated static func reap(_ pid: pid_t) -> Int32? {
        var status: Int32 = 0
        var reaped: pid_t
        repeat { reaped = waitpid(pid, &status, 0) } while reaped == -1 && errno == EINTR
        return reaped == pid ? status : nil
    }
}
#endif
