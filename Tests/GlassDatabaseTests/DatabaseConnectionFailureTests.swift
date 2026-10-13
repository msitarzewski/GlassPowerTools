import Foundation
import Testing
import NIOCore
import GlassDBKit
@testable import GlassDatabase

/// What a database that will not connect says (2026-10-13). Measured against the test VM before
/// this: a PostgreSQL failure of any kind read "The operation couldn't be completed.
/// (PostgresNIO.PSQLError error 1.)", an unknown host from MySQL "(NIOCore.SocketAddressError.
/// UnknownHost error 1.)", and the system keeping the app off the local network — "No route to
/// host" — was told to turn on the tunnel. The failures here are the drivers' own.
@Suite("What a database that will not connect says")
struct DatabaseConnectionFailureTests {
    private func config(_ engine: DatabaseEngineType, host: String, port: Int,
                        tunnel: Bool = false) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(name: "Orders", engine: engine, host: host, port: port,
                                 username: "reader", usesHostTunnel: tunnel)
    }

    /// What the engine throws for `host:port`.
    private func failure(_ engine: DatabaseEngineType, host: String, port: Int) async -> (any Error)? {
        let driver: any DatabaseEngine = engine == .postgresql ? PostgreSQLEngine() : MySQLEngine()
        do {
            let connection = try await driver.connect(host: host, port: port, username: "reader", password: "x",
                                                      database: nil, tlsPolicy: .disabled)
            try? await connection.close()
            Issue.record("\(engine) connected to \(host):\(port)")
            return nil
        } catch {
            return error
        }
    }

    @Test("A name that resolves to nothing says so, from either engine",
          arguments: [DatabaseEngineType.mysql, .postgresql])
    func unknownHost(_ engine: DatabaseEngineType) async throws {
        let error = try #require(await failure(engine, host: "nowhere.invalid", port: 5432))
        let message = DatabaseConnectionFailure.message(for: error, config: config(engine, host: "nowhere.invalid", port: 5432))
        #expect(message == "No machine named nowhere.invalid could be found. Edit this database and check its host name.")
    }

    @Test("A refused port reads alike from either engine, and is not a Local Network matter",
          arguments: [DatabaseEngineType.mysql, .postgresql])
    func refusedPort(_ engine: DatabaseEngineType) async throws {
        let error = try #require(await failure(engine, host: "127.0.0.1", port: 1))
        let message = DatabaseConnectionFailure.message(for: error, config: config(engine, host: "127.0.0.1", port: 1))
        #expect(message.hasPrefix("Orders didn't answer at 127.0.0.1:1."), "\(message)")
        #expect(!message.contains("error 1"))
        #expect(!message.contains("Local Network"))
    }

    @Test("No route to a machine on the local network points at the Local Network setting, not the tunnel")
    func noRouteOnTheLocalNetwork() {
        // What both drivers threw, measured from a process without Local Network access.
        let noRoute = IOError(errnoCode: EHOSTUNREACH, reason: "connect(descriptor:addr:size:)")
        let local = DatabaseConnectionFailure.message(for: noRoute, config: config(.mysql, host: "192.168.1.20", port: 3306))
        #expect(local.contains("Privacy & Security > Local Network"))
        #expect(!local.contains("Terminal service"))

        // A machine elsewhere with no route is not the setting's doing.
        let remote = DatabaseConnectionFailure.message(for: noRoute, config: config(.mysql, host: "db.example.com", port: 3306))
        #expect(!remote.contains("Local Network"))
        #expect(remote.contains("Terminal service"))

        // Through a tunnel the database is on this device's loopback; the setting is not in the way.
        let tunnelled = DatabaseConnectionFailure.message(for: noRoute, config: config(.mysql, host: "192.168.1.20", port: 3306, tunnel: true))
        #expect(!tunnelled.contains("Local Network"))
    }

    @Test("A server's refusal is passed on in its own words")
    func serverRefusal() {
        let refusal = DatabaseError.server("password authentication failed for user \"reader\"")
        let message = DatabaseConnectionFailure.message(for: refusal, config: config(.postgresql, host: "192.168.1.20", port: 5432))
        #expect(message == "password authentication failed for user \"reader\"")
    }
}
