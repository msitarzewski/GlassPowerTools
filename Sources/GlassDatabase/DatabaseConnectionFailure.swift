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

enum DatabaseConnectionFailure {

    /// A message naming what could not be reached and the one thing likely to fix it.
    ///
    /// Only transport failures are rewritten. When the engine itself answers and refuses — a bad
    /// password, an unknown database — it said something specific, and specific is better than
    /// anything written here.
    static func message(for error: Error, config: DatabaseConnectionConfig) -> String {
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
        var message = "\(config.name) didn't answer at \(config.host):\(config.port)."
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
