//
//  DatabaseConnectWatchTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  A connect always ends (2026-10-22). The owner pressed Connect on a MySQL service tunnelled
//  through its machine and saw nothing: the machine refused the tunnel, the tunnel closed the
//  local socket at once, and mysql-nio — which fails only queued commands when its channel goes,
//  never the handshake — waited for ever.
//

import Foundation
import os
import Testing
import NIOCore
import NIOPosix
import GlassDBKit
import GlassShell
@testable import GlassDatabase

/// A connection whose close is counted, so a late one can be seen to be closed.
private final class CountedConnection: DatabaseConnection, @unchecked Sendable {
    let closes = OSAllocatedUnfairLock(initialState: 0)

    var isConnected: Bool { get async { true } }
    var engineName: String { "Counted" }
    var capabilities: Set<DatabaseCapability> { [] }
    var identifierQuoteCharacter: Character { "`" }
    var dialect: DatabaseDialect { .mysql }

    func execute(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        QueryResult(query: query, columns: [], rows: [], executionTime: 0)
    }
    func cancelCurrentQuery() async throws {}
    func beginTransaction() async throws {}
    func commitTransaction() async throws {}
    func rollbackTransaction() async throws {}
    func close() async throws { closes.withLock { $0 += 1 } }
    func databases() async throws -> [String] { [] }
    func tables(in database: String) async throws -> [String] { [] }
    func columns(in table: String, database: String) async throws -> [ColumnInfo] { [] }
    func showCreateTable(_ table: String, database: String) async throws -> String { "" }
    func indexes(in table: String, database: String) async throws -> [IndexInfo] { [] }
    func foreignKeys(in table: String, database: String) async throws -> [ForeignKeyInfo] { [] }
    func tableStatus(in database: String) async throws -> [TableStatus] { [] }
    func tableStatusByNamespace() async throws -> [String: [TableStatus]] { [:] }
    func rowCount(table: String, database: String) async throws -> Int { 0 }
    func rowCount(table: String, database: String, timeout: Duration?) async throws -> Int { 0 }
    func serverVersion() async throws -> String { "0" }
    func explain(_ query: String, parameters: [DatabaseValue]) async throws -> QueryResult {
        QueryResult(query: query, columns: [], rows: [], executionTime: 0)
    }
}

/// A forward whose machine has refused, or not.
private final class RefusingForward: GlassHostPortForward, @unchecked Sendable {
    let localPort: Int
    let refusal: String?
    init(localPort: Int = 1, refusal: String?) {
        self.localPort = localPort
        self.refusal = refusal
    }
    func close() async {}
}

/// Accepts and hangs up at once, before any greeting: what a refused tunnel's local end does.
private func startHangUpServer() async throws -> any Channel {
    try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in channel.close() }
        .bind(host: "127.0.0.1", port: 0)
        .get()
}

@MainActor
@Suite("A database connect always ends")
struct DatabaseConnectWatchTests {

    @Test("A connect that finishes is passed through")
    func finishes() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        let connection = CountedConnection()
        let returned = try await manager.connectWatched(forward: RefusingForward(refusal: nil)) { connection }
        #expect(returned as AnyObject === connection)
        #expect(connection.closes.withLock { $0 } == 0)
    }

    @Test("The machine's refusal ends a connect the driver never ends, at once")
    func refusalEndsIt() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        manager.connectTimeout = .seconds(30)
        let started = ContinuousClock.now
        await #expect(throws: DatabaseConnectAbandoned.refused("Connection refused")) {
            _ = try await manager.connectWatched(forward: RefusingForward(refusal: "Connection refused")) {
                try await Task.sleep(for: .seconds(60))
                return CountedConnection()
            }
        }
        // Against the driver's 60: at once, with room for a run whose other tests share the main actor.
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test("A driver's own failure after a refusal gives the machine's reason")
    func refusalOverDriverError() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        await #expect(throws: DatabaseConnectAbandoned.refused("Connection refused")) {
            _ = try await manager.connectWatched(forward: RefusingForward(refusal: "Connection refused")) {
                throw ChannelError.eof
            }
        }
    }

    @Test("Nothing at all is given up at the deadline, and a connection arriving after it is closed")
    func deadline() async throws {
        let manager = DatabaseSessionManager(loadImmediately: false)
        manager.connectTimeout = .milliseconds(300)
        let late = CountedConnection()
        // The connection arrives once the deadline has been reported, whatever the main actor is
        // doing. A driver that slept a second raced the 300 ms deadline on a busy run, and won.
        let (released, release) = AsyncStream<Void>.makeStream()
        await #expect(throws: DatabaseConnectAbandoned.timedOut(.milliseconds(300))) {
            _ = try await manager.connectWatched(forward: nil) {
                for await _ in released { break }
                return late
            }
        }
        release.yield()
        release.finish()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while late.closes.withLock({ $0 }) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(late.closes.withLock { $0 } == 1, "closed, not leaked open")
    }

    /// The real driver against a server that hangs up before its greeting: without the watch this
    /// waits for ever, so it is watched from here.
    @Test("MySQL to a server that hangs up before its greeting ends at the deadline")
    func mysqlHangUp() async throws {
        let server = try await startHangUpServer()
        defer { server.close(promise: nil) }
        let port = try #require(server.localAddress?.port)
        let manager = DatabaseSessionManager(loadImmediately: false)
        manager.connectTimeout = .seconds(1)
        let config = DatabaseConnectionConfig(name: "Orders", engine: .mysql, host: "127.0.0.1", port: port,
                                              username: "reader")
        let result = OSAllocatedUnfairLock<String?>(initialState: nil)
        Task { @MainActor in
            do {
                _ = try await manager.connect(config: config, password: "x")
                result.withLock { $0 = "connected" }
            } catch {
                result.withLock { $0 = DatabaseConnectionFailure.message(for: error, config: config) }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while result.withLock({ $0 }) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let message = result.withLock { $0 } ?? "still waiting after 10 s"
        #expect(message == "Orders didn't finish connecting within 1 second. Check that the database is running at 127.0.0.1:\(port).")
    }
}

@Suite("What a given-up connect says")
struct DatabaseConnectAbandonedMessageTests {
    private func config(target: String? = nil, through: UUID? = nil, tunnel: Bool = true) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(name: "Orders", engine: .mysql, host: "203.0.113.5", port: 13306, username: "reader",
                                 usesHostTunnel: tunnel, tunnelServiceID: through, tunnelTargetHost: target)
    }

    @Test("Refused on the machine itself: nothing listening, and where to give another address")
    func refusedOnTheMachine() {
        let message = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.refused("Connection refused"),
                                                        config: config())
        #expect(message == "Orders didn't answer: nothing on the machine is listening on port 13306. Check that the database is running there. If it runs at another address the machine reaches, edit this database and enter that address as its Database address.")
    }

    @Test("Refused at an address the machine reaches: that address")
    func refusedElsewhere() {
        let message = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.refused("Connection refused"),
                                                        config: config(target: "10.0.0.7"))
        #expect(message.contains("found nothing listening at 10.0.0.7:13306"), "\(message)")
        let through = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.refused("Connection refused"),
                                                        config: config(through: UUID()))
        #expect(through.contains("found nothing listening at 203.0.113.5:13306"), "\(through)")
    }

    @Test("A forward the server's configuration forbids names the setting")
    func prohibited() {
        let message = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.refused("administratively prohibited"),
                                                        config: config())
        #expect(message.contains("AllowTcpForwarding"), "\(message)")
    }

    @Test("Other words from the server are quoted, never dropped")
    func otherWords() {
        let message = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.refused("resource shortage"),
                                                        config: config())
        #expect(message.contains("(it said \"resource shortage\")"), "\(message)")
    }

    @Test("Running out of time through a tunnel says the tunnel opened")
    func timedOutThroughATunnel() {
        let message = DatabaseConnectionFailure.message(for: DatabaseConnectAbandoned.timedOut(.seconds(30)),
                                                        config: config())
        #expect(message == "Orders didn't finish connecting within 30 seconds. The tunnel opened, but the database didn't answer through it. Check that it is running and listening on port 13306.")
    }
}
