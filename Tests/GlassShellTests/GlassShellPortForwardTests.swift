import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

/// A forward that never touches the network: it reports a port and records that it was closed.
private final class FakeForward: GlassHostPortForward, @unchecked Sendable {
    let localPort: Int
    private(set) var closed = false
    init(localPort: Int) { self.localPort = localPort }
    func close() async { closed = true }
}

/// Stands in for the SSH capability. Records what the shell asked for so the test can prove the
/// broker passed the borrower's target through unchanged.
@MainActor
private final class ForwardingCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    var displayName: String { "Terminal" }
    var symbolName: String { "terminal" }
    var requests: [(host: String, remoteHost: String, port: Int)] = []
    var nextForward: FakeForward?
    var failure: (any Error)?

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}

    func openPortForward(host: HostProfile, toHost remoteHost: String,
                         port: Int) async throws -> any GlassHostPortForward {
        requests.append((host.displayName, remoteHost, port))
        if let failure { throw failure }
        return nextForward ?? FakeForward(localPort: 1)
    }
}

/// A capability that never adopted the hook, to prove the default is a refusal and not a stub.
@MainActor
private final class SilentCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    var displayName: String { "Terminal" }
    var symbolName: String { "terminal" }
    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
}

@MainActor
private func makeModel(registry: GlassCapabilityRegistry) throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellForward-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore.forTest(), registry: registry)
    return (model, root)
}

@Suite("Borrowing the host's SSH forward", .serialized)
@MainActor
struct GlassShellPortForwardTests {
    @Test("A host with an SSH service lends its forward, and the target passes through unchanged")
    func borrowsTheHostsForward() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        ssh.nextForward = FakeForward(localPort: 54_321)
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        let access = model.hostAccess(for: host.id)
        #expect(access.address == "198.51.100.9")
        #expect(access.canForwardPorts)

        let forward = try await access.forwardPort(port: 5_432)
        #expect(forward.localPort == 54_321)
        // The database capability asked for loopback-on-the-host; that is what the SSH capability saw.
        #expect(ssh.requests.count == 1)
        #expect(ssh.requests[0].remoteHost == "127.0.0.1")
        #expect(ssh.requests[0].port == 5_432)
        #expect(ssh.requests[0].host == "Box")
    }

    @Test("Through another machine: the choices are other machines with a Terminal, and the forward ends at the given address from there")
    func forwardsThroughAnotherMachine() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = try await model.addHost(displayName: "App", address: "203.0.113.5")
        let appTerminal = try await model.addService(kind: .ssh, displayName: "Terminal", to: app.id)
        let db = try await model.addHost(displayName: "Production DB", address: "198.51.100.12")
        _ = try await model.addService(kind: .database, displayName: "MySQL", to: db.id)
        _ = try await model.addHost(displayName: "No terminal", address: "198.51.100.13")

        let access = model.hostAccess(for: db.id)
        #expect(!access.canForwardPorts, "the database server has no Terminal of its own")
        #expect(access.tunnelChoices.map(\.machineName) == ["App"])
        #expect(access.tunnelChoices.first?.serviceID == appTerminal.endpointID)
        #expect(model.hostAccess(for: app.id).tunnelChoices.isEmpty, "a machine is not offered as its own way through")

        _ = try await access.forwardPort(through: appTerminal.endpointID, toHost: "198.51.100.12", port: 3_306)
        #expect(ssh.requests.count == 1)
        #expect(ssh.requests[0].host == "App" && ssh.requests[0].remoteHost == "198.51.100.12" && ssh.requests[0].port == 3_306)

        // A Terminal service that has gone is said plainly, not tunnelled somewhere else.
        await #expect(throws: GlassPortForwardError.self) {
            _ = try await access.forwardPort(through: EndpointID(), toHost: "198.51.100.12", port: 3_306)
        }
        #expect(ssh.requests.count == 1)
    }

    @Test("A host with no SSH service cannot forward, and says so instead of failing late")
    func noSSHServiceMeansNoForward() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(ForwardingCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = try await model.addHost(displayName: "DBOnly", address: "198.51.100.10")
        _ = try await model.addService(kind: .database, displayName: "Postgres", to: host.id)

        let access = model.hostAccess(for: host.id)
        #expect(!access.canForwardPorts)
        await #expect(throws: GlassPortForwardError.self) { try await access.forwardPort(port: 5_432) }
    }

    @Test("With no capability registered for SSH there is nothing to borrow")
    func noCapabilityMeansNoForward() async throws {
        let (model, root) = try makeModel(registry: GlassCapabilityRegistry())
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)
        #expect(!model.hostAccess(for: host.id).canForwardPorts)
    }

    @Test("A capability that never adopted the hook refuses rather than pretending")
    func defaultImplementationRefuses() async throws {
        let registry = GlassCapabilityRegistry()
        registry.register(SilentCapability())
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        let access = model.hostAccess(for: host.id)
        // The host looks forwardable — it has the service and a capability owns it — so the
        // refusal has to come from the call, which is exactly what the default does.
        #expect(access.canForwardPorts)
        await #expect(throws: GlassPortForwardError.self) { try await access.forwardPort(port: 5_432) }
    }

    @Test("An out-of-range port is rejected before the SSH capability is troubled")
    func portIsValidatedFirst() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        let access = model.hostAccess(for: host.id)
        await #expect(throws: GlassPortForwardError.self) { try await access.forwardPort(port: 0) }
        await #expect(throws: GlassPortForwardError.self) { try await access.forwardPort(port: 70_000) }
        #expect(ssh.requests.isEmpty)
    }

    @Test("The borrower's error reaches it intact, so it can explain the real cause")
    func failuresPropagate() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        ssh.failure = GlassPortForwardError.hostNotTrusted(name: "198.51.100.9")
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        do {
            _ = try await model.hostAccess(for: host.id).forwardPort(port: 5_432)
            Issue.record("the forward should not have opened")
        } catch let error as GlassPortForwardError {
            guard case .hostNotTrusted(let name) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(name == "198.51.100.9")
            // The message sends the user somewhere real rather than saying "failed".
            #expect(error.errorDescription?.contains("Terminal service") == true)
        }
    }

    @Test("The device's own host never lends a forward, even though it carries a Terminal service")
    func theLocalHostNeverForwards() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        await model.load()

        // The trap D8 names: the local host has an `.ssh` service — the Mac's own shell — so the
        // plain "does this host have a Terminal?" test says yes, and the database capability
        // would tunnel to loopback through loopback to reach a server already listening on it.
        let local = try #require(model.localHost)
        _ = try await model.addService(kind: .ssh, displayName: "Local Shell", to: GlassLocalHost.id)
        #expect(model.localHost?.services.contains { $0.kind == .ssh } == true)

        let access = model.hostAccess(for: local.id)
        #expect(access.address == nil, "it has no address to connect to either")
        #expect(!access.canForwardPorts, "so the setup sheet never offers the tunnel here")
        await #expect(throws: GlassPortForwardError.self) { try await access.forwardPort(port: 5_432) }
        #expect(ssh.requests.isEmpty, "and the SSH capability is never troubled")
        #expect(await access.resolveHostTrust() == .unavailable,
                "there is no host key to settle for this device (D14 has nothing to ask about)")
    }

    @Test("Closing the forward closes the tunnel")
    func closingIsPassedThrough() async throws {
        let registry = GlassCapabilityRegistry()
        let ssh = ForwardingCapability()
        let fake = FakeForward(localPort: 6_000)
        ssh.nextForward = fake
        registry.register(ssh)
        let (model, root) = try makeModel(registry: registry)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = try await model.addHost(displayName: "Box", address: "198.51.100.9")
        _ = try await model.addService(kind: .ssh, displayName: "Terminal", to: host.id)

        let forward = try await model.hostAccess(for: host.id).forwardPort(port: 3_306)
        #expect(!fake.closed)
        await forward.close()
        #expect(fake.closed)
    }
}
