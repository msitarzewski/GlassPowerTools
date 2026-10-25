//
//  DatabaseConnectionFailure.swift
//  Glass Power Tools — GlassDatabase
//
//  What to say when a database will not connect.
//
//  SwiftNIO's transport errors reach the user as their own descriptions, written for a networking
//  library rather than for a person: a MySQL server bound to `127.0.0.1` on the far machine — the
//  default on every distribution — arrived as **"The operation couldn't be completed.
//  (NIOCore.IOError error 1.)"**
//
//  The replacement says what did not answer, where, and what to do about it. **No error numbers and
//  no errno names**: the user's words on seeing a first draft that still translated them were
//  *"The error should suggest that, not be so … technical"*. Which code the kernel returned does
//  not change the advice — a database that only listens on its own machine is the ordinary case,
//  and the tunnel is the answer for every one of them. The raw error goes to the log, where
//  somebody debugging can have it.
//
//  Two failures have their own words (2026-10-13, measured against the test VM): a name that does
//  not resolve, and "No route to host" to a machine on the local network, which is what the system
//  keeping the app off the local network looks like (`GlassLocalNetworkAccess`). Both used to get
//  the tunnel advice, or PostgreSQL's "PSQLError error 1".
//

import Foundation
import OSLog
import NIOCore
import GlassShell

/// A connect the session manager gave up on (2026-10-22): the driver had said nothing.
enum DatabaseConnectAbandoned: Error, Equatable {
    /// The tunnel's machine would not connect on to the database, in the SSH server's words.
    case refused(String)
    /// Nothing failed and nothing finished.
    case timedOut(Duration)
}

enum DatabaseConnectionFailure {

    /// A message naming what could not be reached and the one thing likely to fix it.
    ///
    /// Only transport failures are rewritten. When the engine itself answers and refuses — a bad
    /// password, an unknown database — it said something specific, and specific is better than
    /// anything written here.
    static func message(for error: Error, config: DatabaseConnectionConfig) -> String {
        if let abandoned = error as? DatabaseConnectAbandoned {
            Logger.connections.error(
                "\(config.engine.rawValue, privacy: .public) connect given up: \(String(describing: abandoned), privacy: .public)"
            )
            return message(for: abandoned, config: config)
        }
        guard config.engine != .sqlite, isTransportFailure(error) else {
            return error.localizedDescription
        }
        Logger.connections.error(
            "\(config.engine.rawValue, privacy: .public) transport failure: \(String(describing: error), privacy: .private)"
        )
        // Without a tunnel the app reaches the database's host itself, so the name and the network
        // are this device's to resolve; through one, the database is on this device's loopback.
        if !config.usesHostTunnel, isUnknownHost(error) {
            return "No machine named \(config.host) could be found. Edit this database and check its host name."
        }
        var message = "\(config.name) didn't answer at \(config.reachedHost ?? config.host):\(config.port)."
        if !config.usesHostTunnel, GlassLocalNetworkAccess.mayBeDenial(error),
           GlassLocalNetworkAccess.isLikelyLocalHost(config.host) {
            message += " " + GlassLocalNetworkAccess.advice
        } else if !config.usesHostTunnel {
            message += " Databases are usually set up to accept connections only from the machine "
                + "they run on. Edit this database and turn on \"Reach it through this machine's "
                + "Terminal service\" under Advanced."
        } else if config.tunnelServiceID != nil || config.tunnelTargetHost != nil {
            message += " The tunnel reached the machine it goes through, so check that the database "
                + "is running at that address and accepts connections from that machine."
        } else {
            message += " The tunnel reached the machine, so check that the database is running "
                + "and listening on that port."
        }
        return message
    }

    /// A refusal the tunnel's machine gave, or the clock running out. The machine's words are the
    /// SSH server's — "Connection refused" is the kernel's — so the usual ones are said plainly.
    private static func message(for abandoned: DatabaseConnectAbandoned, config: DatabaseConnectionConfig) -> String {
        // Where the tunnel ends (`DatabaseConnectionConfig.reachedHost`); nil is the machine itself.
        let reached = config.reachedHost
        let onTheMachine = reached == nil
        let target = reached.map { "\($0):\(config.port)" } ?? "port \(config.port)"
        switch abandoned {
        case .refused(let reason):
            let words = reason.lowercased()
            if words.contains("prohibited") {
                return "\(config.name) didn't answer: the machine's SSH server doesn't allow tunnels to \(target). "
                    + "Allow them with AllowTcpForwarding in its sshd_config, or connect directly."
            }
            if words.contains("refused") {
                if onTheMachine {
                    return "\(config.name) didn't answer: nothing on the machine is listening on port \(config.port). "
                        + "Check that the database is running there. If it runs at another address the machine "
                        + "reaches, edit this database and enter that address as its Database address."
                }
                return "\(config.name) didn't answer: the machine the tunnel goes through found nothing listening at "
                    + "\(target). Check that the database is running at that address and accepts connections from that machine."
            }
            if words.contains("timed out") || words.contains("unreachable") || words.contains("no route") {
                return "\(config.name) didn't answer: the machine the tunnel goes through couldn't reach \(target). "
                    + "Check the database's address, and that the machine can reach it."
            }
            return "\(config.name) didn't answer: the machine the tunnel goes through couldn't connect on to \(target) "
                + "(it said \"\(reason)\"). Check that the database is running there."
        case .timedOut(let limit):
            let seconds = limit.components.seconds
            let within = seconds == 1 ? "1 second" : "\(seconds) seconds"
            if config.usesHostTunnel {
                return "\(config.name) didn't finish connecting within \(within). The tunnel opened, but the "
                    + "database didn't answer through it. Check that it is running and listening on \(target)."
            }
            return "\(config.name) didn't finish connecting within \(within). Check that the database is "
                + "running at \(config.host):\(config.port)."
        }
    }

    /// Whether the failure happened below the database protocol — no name, no route, no
    /// listener, no permission — rather than being the server's own refusal. `IOError` carries the
    /// kernel's answer, `ChannelError` the timeouts and resets above it, and `SocketAddressError`
    /// a name that did not resolve; `NIOPosix`'s own connection error is not visible from this
    /// module and reaches it unwrapped to one of these (`PostgreSQLEngine.connectFailure`).
    private static func isTransportFailure(_ error: Error) -> Bool {
        error is IOError || error is ChannelError || error is SocketAddressError
            || error is SocketAddressError.UnknownHost
    }

    /// A host name that resolved to nothing, as both drivers throw it (measured).
    private static func isUnknownHost(_ error: Error) -> Bool {
        error is SocketAddressError.UnknownHost
    }
}
