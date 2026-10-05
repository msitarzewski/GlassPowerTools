import Foundation
import Testing
import GlassShell
import GlassConnectionKit
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
        var config = draft.configuration(id: UUID(), address: "10.0.0.12", name: "Production")
        #expect(config.usesHostTunnel && config.tunnelServiceID == app.rawValue && config.host == "10.0.0.12")
        #expect(!draft.sendsInTheClear, "through a tunnel")

        draft.route = .thisMachine
        config = draft.configuration(id: UUID(), address: "10.0.0.12", name: "Production")
        #expect(config.usesHostTunnel && config.tunnelServiceID == nil)

        draft.route = .through(app.rawValue)
        draft.route = .direct
        config = draft.configuration(id: UUID(), address: "10.0.0.12", name: "Production")
        #expect(!config.usesHostTunnel && config.tunnelServiceID == nil)
    }

    @Test("the setting is saved, and an older record without it reads as this machine's own")
    func persistence() throws {
        let through = UUID()
        let config = DatabaseConnectionConfig(name: "Production", host: "10.0.0.12", port: 3306, username: "app",
                                              usesHostTunnel: true, tunnelServiceID: through)
        let decoded = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.tunnelServiceID == through && decoded.usesHostTunnel)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        json.removeValue(forKey: "tunnelServiceID")
        let older = try JSONDecoder().decode(DatabaseConnectionConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(older.usesHostTunnel && older.tunnelServiceID == nil)

        // A service to tunnel through means nothing without a tunnel.
        let direct = DatabaseConnectionConfig(name: "x", host: "10.0.0.12", usesHostTunnel: false, tunnelServiceID: through)
        #expect(direct.tunnelServiceID == nil)
    }

    @Test("through this machine: to the database address given, as the machine sees it, else to itself")
    func throughThisMachineToAnAddress() async throws {
        nonisolated(unsafe) var asked: [String] = []
        let access = GlassCapabilityHostAccess(address: "203.0.113.5", openForward: { host, _ in
            asked.append(host); throw GlassPortForwardError.unavailable
        })
        let behind = DatabaseConnectionConfig(name: "Production", host: "203.0.113.5", port: 13306, username: "app",
                                              usesHostTunnel: true, tunnelTargetHost: "10.0.0.12")
        let onItself = DatabaseConnectionConfig(name: "Local", host: "203.0.113.5", port: 3306, username: "app",
                                                usesHostTunnel: true)
        for config in [behind, onItself] {
            let provider = try #require(GlassDatabaseCapability.forwardProvider(for: config, hostAccess: access))
            await #expect(throws: GlassPortForwardError.self) { _ = try await provider("127.0.0.1", config.port) }
        }
        #expect(asked == ["10.0.0.12", "127.0.0.1"])

        // The draft writes it only for this route, and a blank field means the machine itself.
        let draft = DatabaseServiceDraft(connectionManager: manager())
        draft.engine = .mysql
        draft.route = .thisMachine
        draft.tunnelTargetHost = " 10.0.0.12 "
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == "10.0.0.12")
        draft.tunnelTargetHost = ""
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == nil)
        draft.tunnelTargetHost = "10.0.0.12"
        draft.route = .direct
        #expect(draft.configuration(id: UUID(), address: "203.0.113.5", name: "P").tunnelTargetHost == nil)
    }

    @Test("connecting goes through the chosen machine to the database's own address")
    func connectGoesThroughTheChosenMachine() async throws {
        let through = EndpointID()
        let config = DatabaseConnectionConfig(name: "Production", host: "10.0.0.12", port: 3306, username: "app",
                                              usesHostTunnel: true, tunnelServiceID: through.rawValue)
        nonisolated(unsafe) var asked: [(EndpointID, String, Int)] = []
        let access = GlassCapabilityHostAccess(address: "10.0.0.12", openForwardThrough: { service, host, port in
            asked.append((service, host, port))
            throw GlassPortForwardError.unavailable
        })
        let forward = GlassDatabaseCapability.forwardProvider(for: config, hostAccess: access)
        let provider = try #require(forward)
        await #expect(throws: GlassPortForwardError.self) { _ = try await provider("127.0.0.1", 3306) }
        #expect(asked.count == 1 && asked[0].0 == through && asked[0].1 == "10.0.0.12" && asked[0].2 == 3306)
    }
}
