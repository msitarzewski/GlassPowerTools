//
//  DatabaseTransportPlanTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  Where the driver's socket goes, and which name TLS is checked against, once the tunnel is
//  the host's Terminal service rather than a per-connection SSH configuration (D7).
//

import Foundation
import Testing
import GlassDBKit
@testable import GlassDatabase

@Suite("Transport plan")
struct DatabaseTransportPlanTests {

    private func config(engine: DatabaseEngineType = .mysql,
                        tunnel: Bool = false,
                        tls: Bool = false) -> DatabaseConnectionConfig {
        DatabaseConnectionConfig(name: "Fixture", engine: engine, host: "db.example.test",
                                 port: 3306, username: "reader", usesHostTunnel: tunnel, useTLS: tls)
    }

    @Test("A direct connection goes to the host's own address and port")
    func directPlan() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config())
        #expect(plan.databaseHost == "db.example.test")
        #expect(plan.databasePort == 3306)
        #expect(plan.tunnelRemoteHost == nil)
        #expect(plan.tlsPolicy == .disabled)
    }

    @Test("Through a tunnel the socket goes to loopback on the forward's local port")
    func tunnelledPlan() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: 54_321)
        #expect(plan.databaseHost == "127.0.0.1")
        #expect(plan.databasePort == 54_321)
        #expect(plan.tunnelRemoteHost == "db.example.test")
        #expect(plan.tunnelRemotePort == 3306)
    }

    @Test("TLS through a tunnel is still checked against the machine's real name, never loopback")
    func tunnelledTLSChecksTheRealName() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tunnel: true, tls: true), tunnelLocalPort: 54_321)
        #expect(plan.databaseHost == "127.0.0.1")
        #expect(plan.tlsPolicy == .requiredSystemTrustForHost("db.example.test"))
    }

    @Test("A direct TLS connection uses plain system trust")
    func directTLS() throws {
        let plan = try DatabaseSessionManager.transportPlan(for: config(tls: true))
        #expect(plan.tlsPolicy == .requiredSystemTrust)
    }

    @Test("A tunnel with no local port is refused rather than connected somewhere arbitrary")
    func tunnelWithoutPortIsRefused() {
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: nil)
        }
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(tunnel: true), tunnelLocalPort: 0)
        }
    }

    @Test("SQLite is a local file: it refuses a tunnel and refuses TLS")
    func sqliteRefusesTransport() throws {
        let plain = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite))
        #expect(plain.databasePort == 0)
        #expect(plain.tlsPolicy == .disabled)

        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite, tunnel: true))
        }
        #expect(throws: DatabaseSessionManager.SessionError.self) {
            _ = try DatabaseSessionManager.transportPlan(for: config(engine: .sqlite, tls: true))
        }
    }

    @MainActor
    @Test("A service set to tunnel with no forward available fails saying so, and connects nowhere")
    func tunnelWithoutAProviderFailsHonestly() async {
        let manager = DatabaseSessionManager(loadImmediately: false)
        await #expect(throws: (any Error).self) {
            _ = try await manager.connect(config: config(tunnel: true), password: "", openForward: nil)
        }
        // The failed attempt leaves no session behind.
        #expect(manager.sessions.isEmpty)
    }
}
