//
//  TerminalHostTrustBrokerTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  D14: the second source the terminal's trust prompt can be driven from. These cover what a
//  session-less caller depends on — that it is never left suspended, and that strict mode is
//  honoured without a prompt ever appearing.
//

import Foundation
import Testing
import GlassSSHTransport
@testable import GlassTerminal

@MainActor
@Suite("Host trust broker")
struct TerminalHostTrustBrokerTests {

    private func challenge(host: String = "10.0.0.9",
                           reason: SSHHostTrustReason = .unknown) -> SSHHostTrustChallenge {
        SSHHostTrustChallenge(host: host, port: 22, algorithm: "ssh-ed25519",
                              fingerprintSHA256: "AAAA", keyDataBase64: "AAAA", reason: reason)
    }

    @Test("Accepting pins and retries: the decision reaches the caller as trust-and-remember")
    func acceptingIsRemembered() async {
        let broker = TerminalHostTrustBroker { true }
        async let decision = broker.ask(challenge())
        while broker.pending == nil { await Task.yield() }
        broker.answer(.trust(remember: true))
        #expect(await decision == .trust(remember: true))
        #expect(broker.pending == nil)
    }

    @Test("Declining reaches the caller as a rejection, not as a hang")
    func decliningReturns() async {
        let broker = TerminalHostTrustBroker { true }
        async let decision = broker.ask(challenge())
        while broker.pending == nil { await Task.yield() }
        broker.answer(.reject)
        #expect(await decision == .reject)
    }

    @Test("Strict host-key verification refuses without ever presenting a prompt")
    func strictModeNeverPrompts() async {
        let broker = TerminalHostTrustBroker { false }
        let decision = await broker.ask(challenge())
        #expect(decision == .reject)
        #expect(broker.pending == nil, "nothing was ever staged for the prompt")
    }

    @Test("Two callers are shown one at a time, in arrival order")
    func requestsQueue() async {
        let broker = TerminalHostTrustBroker { true }
        async let first = broker.ask(challenge(host: "first"))
        while broker.pending == nil { await Task.yield() }
        #expect(broker.pending?.challenge.host == "first")

        async let second = broker.ask(challenge(host: "second"))
        // The second must not displace the first on screen.
        await Task.yield()
        #expect(broker.pending?.challenge.host == "first")

        broker.answer(.trust(remember: true))
        while broker.pending?.challenge.host != "second" { await Task.yield() }
        broker.answer(.reject)

        #expect(await first == .trust(remember: true))
        #expect(await second == .reject)
        #expect(broker.pending == nil)
    }

    @Test("A changed key is carried through as changed, so the prompt can style it destructively")
    func changedReasonSurvives() async {
        let broker = TerminalHostTrustBroker { true }
        async let decision = broker.ask(challenge(reason: .changed))
        while broker.pending == nil { await Task.yield() }
        #expect(broker.pending?.challenge.reason == .changed)
        broker.answer(.reject)
        _ = await decision
    }

    @Test("Cancelling everything resumes every waiting caller rather than stranding them")
    func cancelAllResumesEveryone() async {
        let broker = TerminalHostTrustBroker { true }
        async let first = broker.ask(challenge(host: "first"))
        while broker.pending == nil { await Task.yield() }
        async let second = broker.ask(challenge(host: "second"))
        await Task.yield()

        broker.cancelAll()
        #expect(await first == .reject)
        #expect(await second == .reject)
        #expect(broker.pending == nil)
    }
}
