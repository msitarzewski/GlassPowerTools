//
//  TerminalMachineReach.swift
//  GlassTerminal
//
//  When a machine can't be reached, it is the machine's failure, not each terminal's (the owner, 2026-11-10: "I
//  primarily use Glass Power tools with tmux sessions on my MacBook Pro … as a laptop, it goes into my bag, and is
//  unavailable to sessions from my iPhone or Vision OS … They try to connect, but time out, some show detached, as if
//  they could be reattached. Take a look at what happens when dozens (literally) of tmux sessions are unable to
//  resume").
//
//  What was there: every terminal found the machine down for itself, each waiting out a 30-second connect timeout. A
//  window's terminals connected one after another, so thirty took fifteen minutes; terminals reconnecting together
//  took turns two at a time. Now:
//  - the connect timeout is 15 s (`SSHTransport.connectTimeout`);
//  - terminals waiting for a turn to sign in take the sign-in's failure when the machine never answered
//    (`SSHTransportPool.lease`);
//  - a pass over a window's terminals stops dialling a machine at its first terminal that found it not answering, or
//    found Tailscale off here, and gives that machine's other terminals the same failure (`takeFailure(from:)`);
//  - a machine on a tailnet, with Tailscale off on this device, is said at once (`GlassTailscaleReach`).
//

import Foundation
import GlassShell
import GlassSSHTransport

/// Why a connection failed, as far as what happens next goes.
enum TerminalConnectFailure: Equatable {
    /// The machine is on a tailnet and Tailscale is off on this device.
    case needsTailscale
    /// The machine never answered: asleep, off the network, or no longer at that address.
    case notAnswering
    /// Anything else: the machine answered — a refused port, a rejected sign-in, a host key to confirm.
    case other

    init(_ error: Error) {
        if error is GlassTailscaleReach.Required {
            self = .needsTailscale
        } else if SSHTransportError.isMachineNotAnswering(error) {
            self = .notAnswering
        } else {
            self = .other
        }
    }

    /// The machine's failure rather than one terminal's: its other terminals would find the same.
    var isTheMachines: Bool { self != .other }
}

extension TerminalSession {
    /// Fails as `other` did, without dialling: the same words, and the same reason. For a terminal on a machine
    /// another of its terminals just found out of reach.
    func takeFailure(from other: TerminalSession) {
        guard case .error(let message) = other.state else { return }
        connectionProgress = nil
        lastConnectFailure = other.lastConnectFailure
        state = .error(message)
        appendLine(TerminalLine(text: "✗ \(message)", style: .error))
    }
}

extension SSHConnection {
    /// The words for a machine that never answered, or for Tailscale off here; nil for any other failure.
    static func unreachableMessage(for error: Error, server: ServerConfiguration) -> String? {
        if let tailscale = error as? GlassTailscaleReach.Required { return tailscale.errorDescription }
        guard SSHTransportError.isMachineNotAnswering(error) else { return nil }
        let address = "\(server.host):\(server.port)"
        let who = server.name == server.host || server.name.isEmpty ? address : "\(server.name) at \(address)"
        return "\(who) didn't answer. It may be asleep, or off the network."
    }
}
