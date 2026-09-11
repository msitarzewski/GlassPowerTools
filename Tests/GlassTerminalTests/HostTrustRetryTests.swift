//
//  HostTrustRetryTests.swift
//  GlassTerminalTests
//
//  The post-trust reconnect defect: after "Trust and Connect" the retry threw
//  `sessionNotRegistered`. The alert's Confirm action runs first, then SwiftUI sets the alert's
//  `isPresented` binding to false and its setter performs the Cancel cleanup; with the session
//  still in the prompt state, that cleanup closed and unregistered it before the retry task
//  reached `reconnect`. The fix takes the session out of the prompt state synchronously.
//

import Testing
import Foundation
@testable import GlassTerminal

@Suite("Host trust retry")
struct HostTrustRetryTests {
    private func makeSession() -> TerminalSession {
        TerminalSession(server: ServerConfiguration(
            name: "trust fixture", host: "example.invalid", port: 22, username: "test"
        ))
    }

    private func challenge() -> HostKeyTrustChallenge {
        HostKeyTrustChallenge(host: "example.invalid", port: 22, algorithm: "ssh-ed25519",
                              fingerprintSHA256: "SHA256:fixture", keyDataBase64: "AAAA", reason: .unknown)
    }

    /// The dismissal cleanup that follows the Confirm action, as the flow's binding setter runs it.
    @MainActor
    private func dismissalCleanup(_ manager: SessionManager, pending: TerminalSession?) {
        if let pending { manager.closePendingHostTrustSession(pending) }
    }

    @Test("Taking the session for the retry leaves the prompt empty, so the dismissal closes nothing")
    @MainActor
    func takeClearsPromptAndKeepsSessionRegistered() throws {
        let manager = SessionManager(loadImmediately: false)
        let session = makeSession()
        manager.registerSession(session)
        var pendingSession: TerminalSession? = session
        var pendingChallenge: HostKeyTrustChallenge? = challenge()

        let taken = TerminalConnectFlow.takePendingTrustSession(&pendingSession, challenge: &pendingChallenge)
        #expect(taken === session)
        #expect(pendingSession == nil)
        #expect(pendingChallenge == nil)

        dismissalCleanup(manager, pending: pendingSession)
        // What `reconnect` resolves first: the session must still be registered with its origin.
        _ = try manager.reconnectContext(for: session)
        #expect(manager.sessions.contains { $0.id == session.id })
    }

    @Test("The former order — retry reads the prompt inside its task, after the dismissal — is the defect")
    @MainActor
    func dismissalBeforeRetryUnregistersTheSession() {
        let manager = SessionManager(loadImmediately: false)
        let session = makeSession()
        manager.registerSession(session)
        let pendingSession: TerminalSession? = session

        dismissalCleanup(manager, pending: pendingSession)
        #expect(throws: SessionOpenError.self) { _ = try manager.reconnectContext(for: session) }
        #expect(!manager.sessions.contains { $0.id == session.id })
    }
}
