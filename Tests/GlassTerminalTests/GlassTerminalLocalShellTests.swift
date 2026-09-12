import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassTerminal

/// The terminal's contribution to the device's own host (D8): the Mac's shell, built in, with no
/// configuration behind it and an outcome that is reported by the process rather than the window.
@Suite("The built-in local shell", .serialized)
@MainActor
struct GlassTerminalLocalShellTests {
    @Test("The Mac offers a local shell; iPhone, iPad and Vision Pro offer none rather than a dead row")
    func builtInServiceIsPlatformHonest() {
        let capability = GlassTerminalCapability(runtime: GlassTerminalRuntime())
        let services = capability.builtInLocalServices()
        #if os(macOS)
        #expect(services.map(\.endpointID) == [GlassTerminalCapability.localShellEndpointID])
        #expect(services.map(\.kind) == [.ssh])
        #expect(services.first?.displayName == "Local Shell")
        #else
        #expect(services.isEmpty, "there is no local shell to open off the Mac")
        #endif
        #expect(!capability.supportsLocalSetup,
                "its local service is the built-in shell; a second way to make one would be a worse one")
    }

    @Test("The endpoint id is a constant, because nothing is stored for a built-in service")
    func endpointIDIsStable() {
        let first = GlassTerminalCapability(runtime: GlassTerminalRuntime()).builtInLocalServices()
        let second = GlassTerminalCapability(runtime: GlassTerminalRuntime()).builtInLocalServices()
        #expect(first.map(\.endpointID) == second.map(\.endpointID))
    }

    #if os(macOS)
    @Test("Connecting it asks for a local terminal and waits for the process before reporting")
    func openAsksForALocalTerminal() throws {
        let runtime = GlassTerminalRuntime()
        let capability = GlassTerminalCapability(runtime: runtime)
        let host = try HostProfile(id: GlassLocalHost.id, displayName: GlassLocalHost.displayName)
        let service = try #require(capability.builtInLocalServices().first)

        var outcomes: [GlassCapabilityOutcome] = []
        capability.open(service: service, host: host,
                        hostAccess: GlassCapabilityHostAccess(address: nil)) { outcomes.append($0) }

        let requests = runtime.takeRequests()
        #expect(requests.count == 1)
        if case .localTerminal = requests[0] {} else { Issue.record("expected a local terminal request") }
        #expect(outcomes.isEmpty, "opening a window is not a session, so nothing is claimed yet")

        // The pane that actually starts a shell answers.
        runtime.reportLocalShell(.connected)
        #expect(outcomes == [.connected])
    }

    @Test("Each click asks for another shell, and the answers are matched to the requests in order")
    func everyClickOpensAnother() throws {
        let runtime = GlassTerminalRuntime()
        let capability = GlassTerminalCapability(runtime: runtime)
        let host = try HostProfile(id: GlassLocalHost.id, displayName: GlassLocalHost.displayName)
        let service = try #require(capability.builtInLocalServices().first)

        var first: [GlassCapabilityOutcome] = []
        var second: [GlassCapabilityOutcome] = []
        let access = GlassCapabilityHostAccess(address: nil)
        capability.open(service: service, host: host, hostAccess: access) { first.append($0) }
        capability.open(service: service, host: host, hostAccess: access) { second.append($0) }
        #expect(runtime.takeRequests().count == 2, "three clicks would be three windows")

        runtime.reportLocalShell(.connected)
        runtime.reportLocalShell(.failed("The shell could not be started."))
        #expect(first == [.connected])
        #expect(second == [.failed("The shell could not be started.")])
    }

    @Test("A shell nobody asked for reports to nobody")
    func unrequestedShellReportsNothing() {
        let runtime = GlassTerminalRuntime()
        // The toolbar's own Local Terminal button, and a pane split inside the workspace, both
        // arrive here with no request outstanding. Nothing must be popped, and nothing crashes.
        runtime.reportLocalShell(.connected)
        runtime.reportLocalShell(.connected)

        var outcomes: [GlassCapabilityOutcome] = []
        runtime.expectLocalShell { outcomes.append($0) }
        runtime.reportLocalShell(.connected)
        #expect(outcomes == [.connected], "the next real request is still answered exactly once")
        runtime.reportLocalShell(.connected)
        #expect(outcomes == [.connected])
    }
    #endif
}
