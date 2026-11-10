//
//  TerminalConnectionNoticeTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A terminal without its connection says so in the window (the owner, 2026-11-10: "a disconnected terminal shows a
//  red text under the name in the tab, but the window itself still shows what looks like a connected window … Dim
//  the window, add a close or reconnect UI to the center of the window"). What must hold: live, or on its way to its
//  first connection, nothing is said; lost, failed or disconnected, the panel says which, with Reconnect; while
//  auto-reconnect works, its try and Cancel Reconnect; an `exit` says nothing, as its window closes it.
//

import Foundation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

@Suite("A terminal without its connection says so in the window")
@MainActor
struct TerminalConnectionNoticeTests {
    private func notice(_ state: SessionState, connected: Bool = false, failed: Bool = false,
                        shellEnded: Bool = false, userDisconnected: Bool = false,
                        attempt: Int? = nil) -> TerminalConnectionNotice? {
        TerminalConnectionNotice.make(state: state, hasConnected: connected, hasFailed: failed,
                                      shellEnded: shellEnded, userDisconnected: userDisconnected,
                                      autoReconnectAttempt: attempt, maxAttempts: 5, serverName: "alpha")
    }

    @Test("live, or not yet connected for the first time: nothing over the terminal")
    func liveOrFirstConnection() {
        #expect(notice(.connected, connected: true) == nil)
        #expect(notice(.connected, connected: true, failed: true) == nil, "back after a failure")
        #expect(notice(.disconnected) == nil, "an iPhone's tab that connects when it's shown")
        #expect(notice(.connecting) == nil, "the first connection shows where it always has")
    }

    @Test("its connection lost: Connection Lost, the reason, and Reconnect")
    func lost() throws {
        let dropped = try #require(notice(.error("The connection stopped answering"), connected: true, failed: true))
        #expect(dropped.kind == .down)
        #expect(dropped.title == "Connection Lost")
        #expect(dropped.message == "The connection stopped answering")
        #expect(!dropped.offersCancelReconnect)

        let ended = try #require(notice(.disconnected, connected: true))
        #expect(ended.title == "Connection Lost", "auto-reconnect off, or cancelled")
        #expect(ended.message == "The connection to alpha ended.")
        #expect(ended.kind == .down)

        let byHand = try #require(notice(.disconnected, connected: true, userDisconnected: true))
        #expect(byHand.title == "Disconnected")
        #expect(byHand.kind == .down)
    }

    @Test("its first connection failed: Couldn't Connect, the reason, and Reconnect")
    func firstConnectionFailed() throws {
        let failed = try #require(notice(.error("Connection refused by 192.0.2.10:22."), failed: true))
        #expect(failed.title == "Couldn't Connect")
        #expect(failed.message == "Connection refused by 192.0.2.10:22.")
        #expect(failed.kind == .down)
        #expect(notice(.error("  "), failed: true)?.message == nil, "no empty line under the title")
    }

    @Test("Reconnect chosen: a spinner while it connects again, not the terminal looking live")
    func reconnecting() throws {
        let again = try #require(notice(.connecting, connected: true, failed: true))
        #expect(again.kind == .reconnecting)
        #expect(again.title == "Reconnecting…")
        #expect(!again.offersCancelReconnect, "a Reconnect someone chose has no Cancel; Close Terminal still closes")

        let retry = try #require(notice(.connecting, failed: true))
        #expect(retry.title == "Connecting…", "never connected: trying again is connecting")
        #expect(notice(.reconnecting, connected: true)?.kind == .reconnecting)
    }

    @Test("auto-reconnect at work: its try of five and Cancel Reconnect, in whatever state it's in between tries")
    func autoReconnect() throws {
        for state in [SessionState.reconnecting, .connecting] {
            let trying = try #require(notice(state, connected: true, attempt: 2))
            #expect(trying.kind == .reconnecting)
            #expect(trying.title == "Reconnecting…")
            #expect(trying.message == "Attempt 2 of 5 to reach alpha.")
            #expect(trying.offersCancelReconnect)
        }
        #expect(notice(.reconnecting, connected: true, attempt: 0)?.message == nil, "before its first try")
        #expect(notice(.connected, connected: true, attempt: 3) == nil, "back: nothing, though its task is ending")
    }

    @Test("an exit on a connection that stood: nothing, as its window closes it")
    func shellEnded() {
        #expect(notice(.disconnected, connected: true, shellEnded: true) == nil)
    }

    /// The whole way through a session: the flags the notice is made from follow its states.
    @Test("a session: nothing until connected, Connection Lost when dropped, Reconnecting… as it comes back")
    func throughASession() throws {
        var server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        server.tmux = false
        let session = TerminalSession(server: server, terminalWriteSink: { _ in })
        session.tmuxCommandRunner = { _ in "" }
        #expect(session.connectionNotice == nil, "made, not yet connected")
        session.state = .connecting
        #expect(session.connectionNotice == nil, "its first connection")
        session.state = .connected
        #expect(session.connectionNotice == nil)

        session.reportError("The connection stopped answering")
        let lost = try #require(session.connectionNotice)
        #expect(lost.title == "Connection Lost")
        #expect(lost.message == "The connection stopped answering")

        session.state = .connecting
        #expect(session.connectionNotice?.title == "Reconnecting…")
        session.state = .connected
        #expect(session.connectionNotice == nil)
    }

    @Test("a session whose first connection failed: Couldn't Connect, then Connecting… when tried again")
    func firstFailureThroughASession() throws {
        let session = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"),
                                      terminalWriteSink: { _ in })
        session.state = .connecting
        session.state = .error("Connection refused by 192.0.2.10:22.")
        #expect(session.connectionNotice?.title == "Couldn't Connect")
        session.state = .connecting
        #expect(session.connectionNotice?.title == "Connecting…")
    }
}
