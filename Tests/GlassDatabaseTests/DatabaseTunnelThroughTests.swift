import Foundation
import Testing
import GlassShell
import GlassConnectionKit
import NIOCore
@testable import GlassDatabase

/// A database on a private address, reached through another machine's Terminal service — an app
/// server in front of a production database (2026-10-05).
@MainActor
@Suite("Database tunnelled through another machine")
struct DatabaseTunnelThroughTests {
    private func manager() -> ConnectionManager {
        nonisolated(unsafe) var storage: Data?
        return ConnectionManager(loadImmediately: false,
                                 persistenceStore: ConnectionPersistenceStore(load: { storage }, save: { storage = $0 },
                                                                              restore: { storage = $0 }))
    }

    @Test("the picker's three routes write the record they say")
    func routes() {
        let app = EndpointID()
        let draft = DatabaseServiceDraft(connectionManager: manager(),
                                         tunnelChoices: [GlassTunnelChoice(serviceID: app, machineName: "App")])
        draft.engine = .mysql
        #expect(draft.route == .direct)

        draft.route = .through(app.rawValue)
        #expect(draft.usesHostTunnel && draft.tunnelServiceID == app.rawValue && draft.tunnelMachineName == "App")
        var config = draft.configuration(id: UUID(), address: "198.51.100.12", name: "Production")
        #expect(config.usesHostTunnel && config.tunnelServiceID == app.rawValue && config.host == "198.51.100.12")
        #expect(!draft.sendsInTheClear, "through a tunnel")

        draft.route = .thisMachine
        config = draft.configuration(id: UUID(), address: "198.51.100.12", name: "Production")
        #expect(config.usesHostTunnel && config.tunnelServiceID == nil)

        draft.route = .through(app.rawValue)
        draft.route = .direct
        config = draft.configuration(id: UUID(), address: "198.51.100.12", name: "Production")
        #expect(!config.usesHostTunnel && config.tunnelServiceID == nil)
    }

    @Test("the setting is saved, and an older record without it reads as this machine's own")
    func persistence() throws {
        let through = UUID()
        let config = DatabaseConnectionConfig(name: "Production", host: "198.51.100.12", port: 3306, username: "app",
                                              usesHostTunnel: true, tunnelServiceID: through)
        let decoded = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.tunnelServiceID == through && decoded.usesHostTunnel)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        json.removeValue(forKey: "tunnelServiceID")
        let older = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.usesHostTunnel && older.tunnelServiceID == nil)

        // A service to tunnel through means nothing without a tunnel.
        let direct = DatabaseConnectionConfig(name: "x", host: "198.51.100.12", usesHostTunnel: false, tunnelServiceID: through)
        #expect(direct.tunnelServiceID == nil)
    }

    @Test("through this machine: to the database address given, as the machine sees it, else to itself")
    func throughThisMachineToAnAddress() async throws {
        nonisolated(unsafe) var asked: [String] = []
        let access = GlassCapabilityHostAccess(address: "203.0.113.5", openForward: { host, _ in
            asked.append(host); throw GlassPortForwardError.unavailable
        })
        let behind = DatabaseConnectionConfig(name: "Production", host: "203.0.113.5", port: 13306, username: "app",
                                              usesHostTunnel: true, tunnelTargetHost: "198.51.100.12")
        let onItself = DatabaseConnectionConfig(name: "Local", host: "203.0.113.5", port: 3306, username: "app",
                                                usesHostTunnel: true)
        for config in [behind, onItself] {
            let provider = try #require(GlassDatabaseCapability.forwardProvider(for: config, hostAccess: access))
            await #expect(throws: GlassPortForwardError.self) { _ = try await provider("127.0.0.1", config.port) }
        }
        #expect(asked == ["198.51.100.12", "127.0.0.1"])

        // The draft writes it only for this route, and a blank field means the machine itself.
        let draft = DatabaseServiceDraft(connectionManager: manager())
        draft.engine = .mysql
        draft.route = .thisMachine
        draft.tunnelTargetHost = " 198.51.100.12 "
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == "198.51.100.12")
        draft.tunnelTargetHost = ""
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == nil)
        draft.tunnelTargetHost = "198.51.100.12"
        draft.route = .direct
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == nil)
    }

    /// The overview showed the machine's address for a database at a Database address behind it
    /// (2026-10-22), so a lost address could not be seen there.
    @Test("the Endpoint and a failure name where the connection ends, not the machine's address")
    func endpointIsWhereTheConnectionEnds() {
        let behind = DatabaseConnectionConfig(name: "Web", host: "203.0.113.5", port: 13306, username: "app",
                                              usesHostTunnel: true, tunnelTargetHost: "198.51.100.12")
        let onItself = DatabaseConnectionConfig(name: "Local", host: "203.0.113.5", port: 3306, username: "app",
                                                usesHostTunnel: true)
        let through = DatabaseConnectionConfig(name: "Production", host: "198.51.100.12", port: 3306, username: "app",
                                               usesHostTunnel: true, tunnelServiceID: UUID())
        let direct = DatabaseConnectionConfig(name: "Direct", host: "203.0.113.5", port: 5432, username: "app")
        #expect(behind.endpointDescription == "198.51.100.12:13306")
        #expect(onItself.endpointDescription == "Port 3306 on this machine")
        #expect(through.endpointDescription == "198.51.100.12:3306")
        #expect(direct.endpointDescription == "203.0.113.5:5432")

        let reset = IOError(errnoCode: ECONNRESET, reason: "read")
        let message = DatabaseConnectionFailure.message(for: reset, config: behind)
        #expect(message.hasPrefix("Web didn't answer at 198.51.100.12:13306."), "\(message)")
    }

    @Test("connecting goes through the chosen machine to the database's own address")
    func connectGoesThroughTheChosenMachine() async throws {
        let through = EndpointID()
        let config = DatabaseConnectionConfig(name: "Production", host: "198.51.100.12", port: 3306, username: "app",
                                              usesHostTunnel: true, tunnelServiceID: through.rawValue)
        nonisolated(unsafe) var asked: [(EndpointID, String, Int)] = []
        let access = GlassCapabilityHostAccess(address: "198.51.100.12", openForwardThrough: { service, host, port in
            asked.append((service, host, port))
            throw GlassPortForwardError.unavailable
        })
        let forward = GlassDatabaseCapability.forwardProvider(for: config, hostAccess: access)
        let provider = try #require(forward)
        await #expect(throws: GlassPortForwardError.self) { _ = try await provider("127.0.0.1", 3306) }
        #expect(asked.count == 1 && asked[0].0 == through && asked[0].1 == "198.51.100.12" && asked[0].2 == 3306)
    }
}
