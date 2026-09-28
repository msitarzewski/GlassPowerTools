import Foundation
import Testing
import GlassConnectionKit
@testable import GlassTerminal

@Suite("Host address follows the shell's host")
struct HostAddressSyncTests {
    private func host(services: [HostServiceLink], address: String? = nil) throws -> HostProfile {
        try HostProfile(displayName: "golf", address: address, services: services)
    }

    @Test("Only the host's own SSH services follow, and only when they differ")
    func onlyOwnedSSHServersFollow() throws {
        let owned = EndpointID(), other = EndpointID(), desktop = EndpointID()
        let host = try host(services: [
            HostServiceLink(endpointID: owned, kind: .ssh, displayName: "Terminal"),
            HostServiceLink(endpointID: desktop, kind: .rdp, displayName: "Desktop"),
        ])
        let servers = [
            ServerConfiguration(id: owned.rawValue, name: "golf", host: "old.example", username: "casey"),
            ServerConfiguration(id: other.rawValue, name: "elsewhere", host: "old.example", username: "casey"),
            ServerConfiguration(id: desktop.rawValue, name: "desktop-shaped", host: "old.example", username: "casey"),
        ]
        let updated = GlassTerminalHostAddressSync.servers(servers, following: host, address: "192.0.2.6")
        #expect(updated.map(\.id) == [owned.rawValue])
        #expect(updated.first?.host == "192.0.2.6")
        #expect(updated.first?.username == "casey" && updated.first?.port == 22, "only the address changes")
        #expect(GlassTerminalHostAddressSync.servers(updated, following: host, address: "192.0.2.6").isEmpty, "already current: nothing to do")
    }

    @Test("Applying persists through the server manager; a cleared address changes nothing")
    @MainActor
    func applyPersistsAndClearedAddressIsIgnored() async throws {
        let suiteName = "sh.glas.test.host-address.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ServerManager(loadImmediately: false, defaults: defaults)
        manager.loadServersIfNeeded()
        let owned = EndpointID()
        let host = try host(services: [HostServiceLink(endpointID: owned, kind: .ssh, displayName: "Terminal")])
        try await manager.addServerOrThrow(ServerConfiguration(id: owned.rawValue, name: "golf", host: "old.example",
                                                         username: "casey", authMethod: .sshKey))

        #expect(await GlassTerminalHostAddressSync.apply(nil, to: host, in: manager).isEmpty)
        #expect(manager.server(for: owned.rawValue)?.host == "old.example")

        #expect(await GlassTerminalHostAddressSync.apply("192.0.2.6", to: host, in: manager) == [owned.rawValue])
        #expect(manager.server(for: owned.rawValue)?.host == "192.0.2.6")
        let persisted = try JSONDecoder().decode([ServerConfiguration].self, from: #require(defaults.data(forKey: UserDefaultsKeys.servers)))
        #expect(persisted.first?.host == "192.0.2.6", "the change is on disk, not only in memory")
    }
}
