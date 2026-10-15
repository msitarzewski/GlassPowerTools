import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassTerminal

/// The + of a terminal window off the Mac, held (the owner, 2026-10-15: "pinch and hold > servers >
/// terminals list to open in the current window").
@MainActor
@Suite("The + menu's servers and their terminals")
struct TerminalNewTabMenuTests {
    private func running(_ name: String, on server: ServerConfiguration?, kind: HostServiceKind = .ssh,
                         openHere: Bool = false) -> GlassRunningSession {
        let endpoint = server.map { EndpointID(rawValue: $0.id) } ?? EndpointID()
        return GlassRunningSession(id: "\(endpoint.rawValue):\(name)", title: name, symbolName: "terminal", endpointID: endpoint,
                                   isAttachedElsewhere: false, isOpenHere: openHere, open: {}, takeOver: {}, end: {},
                                   attachment: GlassRunningAttachment(kind: kind, endpointID: endpoint, name: name))
    }

    @Test("every saved server by name, each with its own running terminals; none open here, none of another kind")
    func serversAndTheirTerminals() {
        let bravo = ServerConfiguration(name: "Terminal on bravo", host: "bravo.example.com", username: "ann")
        let alpha = ServerConfiguration(name: "Terminal on alpha", host: "alpha.example.com", username: "ann")
        let alphaRoot = ServerConfiguration(name: "Terminal on alpha", host: "alpha.example.com", username: "root")
        let entries = TerminalNewTabMenuEntry.entries(
            servers: [bravo, alpha, alphaRoot],
            title: { GlassTerminalRuntime.machineTitle(serverName: $0.name, hostName: nil) },
            running: [running("glass-1", on: alpha), running("logs", on: bravo), running("glass-2", on: alpha, openHere: true),
                      running("orders", on: alpha, kind: .database), running("elsewhere", on: nil),
                      running("glass-3", on: alpha)])
        #expect(entries.map(\.title) == ["alpha (ann)", "alpha (root)", "bravo"], "by name; two on one machine told apart")
        #expect(entries[0].running.map(\.title) == ["glass-1", "glass-3"])
        #expect(entries[1].running.isEmpty)
        #expect(entries[2].running.map(\.title) == ["logs"])
    }
}
