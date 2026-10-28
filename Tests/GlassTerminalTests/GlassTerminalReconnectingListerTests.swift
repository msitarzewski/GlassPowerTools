import Foundation
import NIOCore
import Testing
import GlassShell
import GlassSSHTransport
@testable import GlassTerminal

/// An editor project's connection, opened again when it has gone (the owner's iPhone, 2026-10-12:
/// "could not be opened: ... (NIOCore.ChannelError error 5.)"). Fakes here; a real connection
/// killed under a project is in `LiveRemoteEditingTests`.
@Suite("An editor project's connection comes back")
struct GlassTerminalReconnectingListerTests {
    final class FakeLister: GlassHostDirectoryLister, @unchecked Sendable {
        let lock = NSLock()
        var failure: Error?
        private(set) var closed = false
        let contents: Data
        init(contents: Data, failure: Error? = nil) { self.contents = contents; self.failure = failure }

        private func answer<T>(_ value: T) throws -> T {
            try lock.withLock { if let failure { throw failure }; return value }
        }
        func list(_ path: String) async throws -> [GlassHostDirectoryEntry] { try answer([]) }
        func read(_ path: String) async throws -> Data {
            try await Task.sleep(for: .milliseconds(5))
            return try answer(contents)
        }
        func write(_ data: Data, to path: String, expecting: GlassHostFileStamp?) async throws -> GlassHostFileStamp? {
            try answer(GlassHostFileStamp(size: UInt64(data.count)))
        }
        func stat(_ path: String) async throws -> GlassHostFileStamp? { try answer(nil) }
        func realPath(_ path: String) async throws -> String { try answer(path) }
        func runCommand(_ command: String, timeLimit: Duration) async throws -> GlassHostCommandOutput {
            try answer(GlassHostCommandOutput(exitStatus: 0, standardOutput: contents))
        }
        func close() async { lock.withLock { closed = true } }
    }

    final class Opener: @unchecked Sendable {
        let lock = NSLock()
        private(set) var opened: [FakeLister] = []
        var failure: Error?
        func open() async throws -> any GlassHostDirectoryLister {
            try lock.withLock {
                if let failure { throw failure }
                let fresh = FakeLister(contents: Data("fresh".utf8))
                opened.append(fresh)
                return fresh
            }
        }
    }

    private func reconnecting(_ first: FakeLister, _ opener: Opener) -> GlassTerminalReconnectingLister {
        GlassTerminalReconnectingLister(machine: "alpha", first: first) { try await opener.open() }
    }

    @Test("a closed connection is opened again and the call made once more; the old one is closed")
    func reconnects() async throws {
        let dead = FakeLister(contents: Data("stale".utf8), failure: ChannelError.outputClosed)
        let opener = Opener()
        let lister = reconnecting(dead, opener)
        #expect(try await lister.read("/a") == Data("fresh".utf8))
        #expect(opener.opened.count == 1 && dead.closed)
        #expect(try await lister.read("/b") == Data("fresh".utf8))
        #expect(opener.opened.count == 1, "the new connection is kept")
    }

    /// The editor's `git` rides the same connection (2026-10-23): a command on one that has gone
    /// is made again on a new one, as a read is.
    @Test("a command on a connection that has gone is run again on a new one")
    func commandsReconnect() async throws {
        #expect(GlassTerminalReconnectingLister.connectionIsGone(SSHTransportError.notConnected))
        let dead = FakeLister(contents: Data("stale".utf8), failure: SSHTransportError.notConnected)
        let opener = Opener()
        let lister = reconnecting(dead, opener)
        let output = try await lister.runCommand("git status")
        #expect(output.standardOutput == Data("fresh".utf8) && output.exitStatus == 0)
        #expect(opener.opened.count == 1 && dead.closed)
    }

    @Test("every closed-connection error counts; a refusal does not, and is not retried")
    func whatCounts() async throws {
        for gone: Error in [ChannelError.outputClosed, ChannelError.ioOnClosedChannel, ChannelError.eof,
                            ChannelError.alreadyClosed, ChannelError.inputClosed, SFTPSessionError.closed,
                            IOError(errnoCode: ECONNRESET, reason: "read")] {
            #expect(GlassTerminalReconnectingLister.connectionIsGone(gone), "\(gone)")
        }
        let refused = SFTPSessionError.fileTooLarge(limit: 1)
        #expect(!GlassTerminalReconnectingLister.connectionIsGone(refused))
        let opener = Opener()
        let lister = reconnecting(FakeLister(contents: Data(), failure: refused), opener)
        await #expect(throws: SFTPSessionError.fileTooLarge(limit: 1)) { try await lister.read("/a") }
        #expect(opener.opened.isEmpty)
    }

    @Test("when the connection cannot be made again, the error says so in plain words")
    func plainWords() async throws {
        let opener = Opener()
        opener.failure = ChannelError.connectTimeout(.seconds(1))
        let lister = reconnecting(FakeLister(contents: Data(), failure: ChannelError.outputClosed), opener)
        do {
            _ = try await lister.read("/a")
            Issue.record("expected an error")
        } catch {
            #expect(!error.localizedDescription.contains("ChannelError"), "\(error.localizedDescription)")
        }

        opener.failure = ChannelError.alreadyClosed
        let again = reconnecting(FakeLister(contents: Data(), failure: ChannelError.outputClosed), opener)
        do {
            _ = try await again.read("/a")
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription.hasPrefix("The connection to alpha was lost"), "\(error.localizedDescription)")
        }
    }

    @Test("calls that find the connection gone together open one new one")
    func oneReconnectForMany() async throws {
        let opener = Opener()
        let lister = reconnecting(FakeLister(contents: Data(), failure: ChannelError.outputClosed), opener)
        try await withThrowingTaskGroup(of: Data.self) { group in
            for index in 0..<6 { group.addTask { try await lister.read("/\(index)") } }
            for try await data in group { #expect(data == Data("fresh".utf8)) }
        }
        #expect(opener.opened.count == 1)
    }

    @Test("a closed project stays closed: nothing is opened for it")
    func closedStaysClosed() async throws {
        let first = FakeLister(contents: Data("x".utf8))
        let opener = Opener()
        let lister = reconnecting(first, opener)
        await lister.close()
        #expect(first.closed)
        await #expect(throws: SFTPSessionError.closed) { try await lister.read("/a") }
        #expect(opener.opened.isEmpty)
    }
}
