//
//  TerminalServerLimitsTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  W21 (2026-10-10): when a server's own limits stop a terminal — sessions per connection
//  (MaxSessions) or connections signing in at once (MaxStartups) — the terminal says so in plain
//  words and names the setting, rather than "Could not connect".
//

import Foundation
import Testing
import GlassSSHTransport
@testable import GlassTerminal

@Suite("A server's limits, in plain words (W21)")
@MainActor
struct TerminalServerLimitsTests {
    private let server = ServerConfiguration(name: "alpha", host: "alpha.example.com", port: 22, username: "ann")

    @Test func aRefusedSessionNamesMaxSessions() {
        let message = SSHConnection.userFacingMessage(for: SSHTransportError.sessionLimitReached, server: server)
        #expect(message.contains("MaxSessions"))
        #expect(message.contains("alpha.example.com:22"))
        #expect(message.contains("Close a terminal"))
        #expect(!message.localizedCaseInsensitiveContains("could not connect"))
    }

    @Test func aBusyServerNamesMaxStartups() {
        let message = SSHConnection.userFacingMessage(for: SSHTransportError.serverBusy, server: server)
        #expect(message.contains("MaxStartups"))
        #expect(message.contains("alpha.example.com:22"))
        #expect(message.contains("reconnect"))
        #expect(!message.localizedCaseInsensitiveContains("could not connect"))
    }
}
