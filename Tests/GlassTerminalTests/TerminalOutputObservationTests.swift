import Foundation
import Observation
import Testing
@testable import GlassTerminal

/// W10 (2026-10-08): a busy program writes up to 125 chunks a second, and the terminal window
/// observed each one, so every chunk rebuilt the whole window — on Vision Pro its ornaments and
/// focused values with it. Output now reaches views only once it has come to rest.
@Suite("Output and observation")
@MainActor
struct TerminalOutputObservationTests {
    /// Set from observation's `onChange`, which is `@Sendable`; read after the awaits.
    private nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var fired = false
    }

    private func makeSession() -> TerminalSession {
        TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"),
                        terminalWriteSink: { _ in }, terminalResizeSink: { _, _ in })
    }

    @Test("chunks of output change nothing a view observes")
    func chunksAreNotObserved() async throws {
        let session = makeSession()
        session.outputSettleDelay = .seconds(60)
        let flag = Flag()
        withObservationTracking {
            // What the terminal window reads that output could change.
            _ = session.terminalInputNonce
            _ = session.outputSettledNonce
            _ = session.output
            _ = session.state
        } onChange: {
            flag.fired = true
        }
        for index in 0..<20 {
            session.feedTerminalData(Data("line \(index)\r\n".utf8))
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<50 where session.terminalInputNonce < 5 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.terminalInputNonce >= 5)
        #expect(!flag.fired)
    }

    @Test("output coming to rest is announced once per burst")
    func settledOncePerBurst() async throws {
        let session = makeSession()
        session.outputSettleDelay = .milliseconds(400)
        for index in 0..<10 {
            session.feedTerminalData(Data("line \(index)\r\n".utf8))
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.outputSettledNonce == 0)
        for _ in 0..<200 where session.outputSettledNonce == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.outputSettledNonce == 1)
        try await Task.sleep(for: .milliseconds(800))
        #expect(session.outputSettledNonce == 1)

        session.feedTerminalData(Data("again\r\n".utf8))
        for _ in 0..<200 where session.outputSettledNonce == 1 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.outputSettledNonce == 2)
    }
}
