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

import Foundation
import OSLog
import NIOCore

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
        var message = "\(config.name) didn't answer at \(config.host):\(config.port)."
        if !config.usesHostTunnel {
            message += " Databases are usually set up to accept connections only from the machine "
                + "they run on. Edit this database and turn on \"Reach it through this machine's "
                + "Terminal service\" under Advanced."
        } else if config.tunnelServiceID != nil {
            message += " The tunnel reached the machine it goes through, so check that the database "
                + "is running at that address and accepts connections from that machine."
        } else {
            message += " The tunnel reached the machine, so check that the database is running "
                + "and listening on that port."
        }
        return message
    }

    /// Whether the failure happened below the database protocol — no route, no listener, no
    /// permission — rather than being the server's own refusal. `IOError` carries the kernel's
    /// answer and `ChannelError` the timeouts and resets above it; `NIOPosix`'s own connection
    /// error is not visible from this module and arrives wrapped in one of these two.
    private static func isTransportFailure(_ error: Error) -> Bool {
        error is IOError || error is ChannelError
    }
}
