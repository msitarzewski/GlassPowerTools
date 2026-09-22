//
//  GlassOpenSession.swift
//  Glass Power Tools — GlassShell
//
//  One list of what is open, and the way back to it.
//
//  A phone shows one session at a time, and until now there was no way between them. Leaving a
//  terminal cleared `router.terminalWorkgroupID` and the session stayed live with nothing pointing
//  at it; the only route back was the Workgroups panel, which nobody would think to open. The
//  database and the editor had the same shape.
//
//  No capability can answer "what is open?" alone, and the shell must not learn four session
//  models. So it is contributed, through the seam `GlassLibraryPanel` and `registerSettingsPage`
//  already established: each capability says what it has open and how to go back to it, and the
//  shell owns the list and the control that shows it.
//

import SwiftUI
import GlassConnectionKit

/// One session a capability has open, and the two things anyone outside it can do with one.
///
/// Deliberately not a `HostServiceKind`: the editor contributes here and a file is not a service
/// on a machine. The symbol and the subtitle say what a row is; nothing needs to switch on it.
public struct GlassOpenSession: Identifiable {
    /// Unique across every capability, so a session's own chrome can exclude itself by id.
    /// Prefix it with the contributor ("terminal:", "database:", "editor:") — two capabilities
    /// numbering their sessions from the same UUID space is not something to rely on.
    public let id: String
    /// The machine, usually. What the user would name if asked where they were.
    public let title: String
    /// The service and its state — "PostgreSQL · connected", "3 documents".
    public let subtitle: String?
    public let symbolName: String
    /// Bring this session back to the screen.
    public let activate: @MainActor @Sendable () -> Void
    /// End it. The switcher's swipe action; never offered for the session being viewed.
    public let close: @MainActor @Sendable () -> Void
    /// What the session looks like right now, when the capability can cheaply draw it.
    ///
    /// **Optional by design, and genuinely optional in practice.** The terminal has rendered
    /// itself since glas.sh (`SwiftTermHostModel.previewImage(maxPixelWidth:)`); the editor and
    /// the database have nothing to photograph, and a card with a name and a symbol on it is
    /// useful where a card waiting for a screenshot would not be. Asked at draw time, never
    /// stored — a picture of a terminal is stale the moment it is taken.
    public let snapshot: (@MainActor () -> Image?)?
    /// The services this session is a connection through — a terminal's server, a database's
    /// connection. The library turns these into the machine the session belongs to, so a
    /// capability never has to know a host id. Several for a workgroup that spans machines.
    public let endpointIDs: [EndpointID]
    /// The machine, said directly, for a session that is not through a service: an editor with
    /// a project on this device (`GlassLocalHost.id`) or on another machine.
    public let hostID: HostID?

    public init(id: String, title: String, subtitle: String? = nil, symbolName: String,
                endpointIDs: [EndpointID] = [], hostID: HostID? = nil,
                activate: @escaping @MainActor @Sendable () -> Void,
                close: @escaping @MainActor @Sendable () -> Void,
                snapshot: (@MainActor () -> Image?)? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.endpointIDs = endpointIDs
        self.hostID = hostID
        self.activate = activate
        self.close = close
        self.snapshot = snapshot
    }
}

public extension GlassCapability {
    /// Sessions this capability has open, newest first. Default: none.
    ///
    /// **Answered from live state every time it is asked**, never from a stored list. It is read
    /// inside a view body so that reading the capability's own `@Observable` session store
    /// registers the dependency — the same rule `GlassLibraryPanel.count` learned the hard way
    /// when a stored count said five with four things in the list.
    func openSessions() -> [GlassOpenSession] { [] }
}

public extension GlassCapabilityRegistry {
    /// Every open session, capabilities in kind order and then the standalone providers.
    ///
    /// Call this **inside a view body**. See `openSessions()` above for why.
    func openSessions() -> [GlassOpenSession] {
        registered.flatMap { $0.openSessions() } + standaloneSessions()
    }

    /// The rows to offer from inside `currentSessionID`: everything open except the session
    /// doing the asking. Pure, so the exclusion is tested without a screen.
    ///
    /// A switcher that lists the session you are already looking at invites a tap that does
    /// nothing, which is the failure this whole feature exists to remove.
    func openSessions(excluding currentSessionID: String?) -> [GlassOpenSession] {
        guard let currentSessionID else { return openSessions() }
        return openSessions().filter { $0.id != currentSessionID }
    }
}

// The Sessions control and its switcher sheet lived here from 2026-09-21 morning to evening.
// They were a fifth surface bolted onto every session's chrome; the library already knew every
// machine and only lacked which ones were live. **Active** in the library and the ⚡ in every
// toolbar replaced them — see `GlassActiveConnections.swift`.
