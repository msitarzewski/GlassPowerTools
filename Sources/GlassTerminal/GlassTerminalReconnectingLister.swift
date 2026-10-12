//
//  GlassTerminalReconnectingLister.swift
//  Glass Power Tools — GlassTerminal
//
//  An editor project's connection to another machine, opened again when it has gone. A project
//  holds one SFTP session for as long as it is open, and a session ends under it: a phone locks, a
//  network changes, the machine drops it. Every call on the old one then failed — the owner's
//  iPhone, 2026-10-12: "default.profraw could not be opened: The operation couldn't be completed.
//  (NIOCore.ChannelError error 5.)", a closed channel (`outputClosed`), on a file that reads
//  perfectly on a live session (`LiveRemoteEditingTests`).
//
//  A call that fails because the connection is closed is made once more, on a new one. A closed
//  connection sent nothing, so trying again is safe; a save that had gone part way is still guarded
//  by the verified commit, which refuses a destination that is not what the editor last saw. When
//  the new connection cannot be made, or fails the same way, the error says so in plain words.
//

import Foundation
import NIOCore
import os
import GlassShell
import GlassSSHTransport

nonisolated final class GlassTerminalReconnectingLister: GlassHostDirectoryLister {
    private static let logger = Logger(subsystem: "sh.glas", category: "editor-remote")
    /// The machine, for what an error says.
    private let machine: String
    private let open: @Sendable () async throws -> any GlassHostDirectoryLister
    private let state: State

    private actor State {
        var current: (any GlassHostDirectoryLister)?
        var closed = false
        /// The new connection being made, which every call that finds the old one gone waits for.
        var reopening: Task<any GlassHostDirectoryLister, Error>?

        init(_ first: any GlassHostDirectoryLister) { current = first }

        func lister() -> (any GlassHostDirectoryLister)? { closed ? nil : current }

        /// The connection to use after `failed` lost its own: a new one, unless another call has
        /// already made it.
        func replacing(_ failed: any GlassHostDirectoryLister,
                       open: @escaping @Sendable () async throws -> any GlassHostDirectoryLister)
            async throws -> any GlassHostDirectoryLister {
            guard !closed else { throw SFTPSessionError.closed }
            if let current, current !== failed { return current }
            if let reopening { return try await reopening.value }
            let task = Task<any GlassHostDirectoryLister, Error> {
                await failed.close()
                return try await open()
            }
            reopening = task
            defer { reopening = nil }
            let fresh = try await task.value
            guard !closed else {
                await fresh.close()
                throw SFTPSessionError.closed
            }
            current = fresh
            return fresh
        }

        func close() async {
            closed = true
            let last = current
            current = nil
            await last?.close()
        }
    }

    init(machine: String, first: any GlassHostDirectoryLister,
         open: @escaping @Sendable () async throws -> any GlassHostDirectoryLister) {
        self.machine = machine
        self.open = open
        self.state = State(first)
    }

    /// Whether `error` means the connection is gone, rather than that the machine refused the
    /// request: a closed channel, a reset connection, an SFTP session that has ended.
    static func connectionIsGone(_ error: Error) -> Bool {
        // The closed cases `SSHConnection.isChannelClosedError` names, and I/O on a closed channel.
        if let channel = error as? ChannelError {
            switch channel {
            case .eof, .alreadyClosed, .inputClosed, .outputClosed, .ioOnClosedChannel: return true
            default: return false
            }
        }
        if let sftp = error as? SFTPSessionError, sftp == .closed { return true }
        if let io = error as? IOError, [ECONNRESET, EPIPE, ECONNABORTED, ENOTCONN].contains(io.errnoCode) { return true }
        // Citadel's and swift-nio-ssh's own "closed" errors, which this module does not name.
        let described = String(describing: error)
        return String(describing: type(of: error)) == "Disconnected"
            || described == "connectionClosed" || described.hasSuffix(".connectionClosed")
    }

    /// What a call that could not get a connection says.
    struct ConnectionLost: LocalizedError {
        let machine: String
        var errorDescription: String? {
            "The connection to \(machine) was lost and could not be made again. Check that \(machine) is on and reachable, then try again."
        }
    }

    private func run<T>(_ body: (any GlassHostDirectoryLister) async throws -> T) async throws -> T {
        guard let first = await state.lister() else { throw SFTPSessionError.closed }
        do {
            return try await body(first)
        } catch where Self.connectionIsGone(error) {
            let fresh: any GlassHostDirectoryLister
            do {
                fresh = try await state.replacing(first, open: open)
            } catch {
                // Plain words, unless the failure has its own (a host key to trust, a sign-in);
                // the library's own text goes to the log, not to the person.
                Self.logger.error("Reconnecting to \(self.machine, privacy: .private) failed: \(String(describing: error), privacy: .public)")
                if error is SFTPSessionError { throw error }
                throw (error as? LocalizedError)?.errorDescription == nil ? ConnectionLost(machine: machine) : error
            }
            do {
                return try await body(fresh)
            } catch where Self.connectionIsGone(error) {
                Self.logger.error("The new connection to \(self.machine, privacy: .private) failed too: \(String(describing: error), privacy: .public)")
                throw ConnectionLost(machine: machine)
            }
        }
    }

    func list(_ path: String) async throws -> [GlassHostDirectoryEntry] {
        try await run { try await $0.list(path) }
    }

    func read(_ path: String) async throws -> Data {
        try await run { try await $0.read(path) }
    }

    @discardableResult
    func write(_ data: Data, to path: String, expecting: GlassHostFileStamp?) async throws -> GlassHostFileStamp? {
        try await run { try await $0.write(data, to: path, expecting: expecting) }
    }

    func stat(_ path: String) async throws -> GlassHostFileStamp? {
        try await run { try await $0.stat(path) }
    }

    func realPath(_ path: String) async throws -> String {
        try await run { try await $0.realPath(path) }
    }

    func close() async {
        await state.close()
    }
}
