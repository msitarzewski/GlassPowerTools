//
//  TerminalHostTrustBroker.swift
//  Glass Power Tools — GlassTerminal
//
//  D14: opening a database is a foreground action, so a tunnel that meets an unknown host key
//  asks the user rather than refusing. A tunnel has no `TerminalSession` behind it, and the
//  terminal's trust prompt is session-shaped, so this is the second source that same prompt can
//  be driven from — not a second prompt.
//
//  The prompt itself, its wording and its destructive styling for a changed key stay exactly
//  where they were, in `TerminalConnectFlow`.
//

import Foundation
import GlassSSHTransport

/// Carries a challenge from a session-less caller (a port forward, or a setup-time trust
/// resolution) to the terminal's prompt, and the user's answer back.
///
/// One request is presented at a time: two fingerprint comparisons on screen at once is worse
/// than making the second wait. Requests queue in arrival order.
@MainActor
@Observable
final class TerminalHostTrustBroker {
    struct Request: Identifiable, Sendable {
        let id = UUID()
        let challenge: HostKeyTrustChallenge
    }

    private struct Waiting {
        let request: Request
        let continuation: CheckedContinuation<SSHHostTrustDecision, Never>
    }

    /// The request the prompt should be showing, if any. Observed by `TerminalConnectFlow`.
    private(set) var pending: Request?
    private var queue: [Waiting] = []

    /// Whether the user's host-key setting permits an interactive prompt at all. Strict mode
    /// means never ask — so a session-less caller is refused rather than left waiting on a
    /// prompt that will never appear.
    private let isInteractiveTrustAllowed: @MainActor () -> Bool

    init(isInteractiveTrustAllowed: @escaping @MainActor () -> Bool) {
        self.isInteractiveTrustAllowed = isInteractiveTrustAllowed
    }

    /// Presents `challenge` and waits for the user. Returns `.reject` without presenting
    /// anything when the user has host-key verification set to strict.
    func ask(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision {
        guard isInteractiveTrustAllowed() else { return .reject }
        let request = Request(challenge: HostKeyTrustChallenge(challenge))
        return await withCheckedContinuation { continuation in
            queue.append(Waiting(request: request, continuation: continuation))
            if pending == nil { promoteNext() }
        }
    }

    /// The prompt's answer for whatever is currently pending. `remember` is true for a real
    /// decision: the transport pins the key and retries, so trusting a machine here trusts it
    /// for every later connection to it, which is the whole point of keying trust by
    /// `host:port` in the transport rather than per capability.
    func answer(_ decision: SSHHostTrustDecision) {
        guard let current = queue.first else { return }
        queue.removeFirst()
        pending = nil
        current.continuation.resume(returning: decision)
        promoteNext()
    }

    /// Refuses everything still waiting — used when the prompt can no longer be shown, so no
    /// caller is left suspended forever.
    func cancelAll() {
        let waiting = queue
        queue.removeAll()
        pending = nil
        for item in waiting { item.continuation.resume(returning: .reject) }
    }

    private func promoteNext() {
        pending = queue.first?.request
    }
}

/// Routes the engine's challenge to the terminal's prompt. The counterpart of
/// `TerminalHostTrustDecider`, which captures and rejects so the *session* layer can prompt and
/// retry; this one waits for the answer inline, because its caller has no session to retry.
struct BrokeredHostTrustDecider: SSHHostTrustDecider {
    let broker: TerminalHostTrustBroker

    func decide(_ challenge: SSHHostTrustChallenge) async -> SSHHostTrustDecision {
        await broker.ask(challenge)
    }
}
