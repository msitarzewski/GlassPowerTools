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
    /// What ending it is called here, and its symbol. "Close" unless the session goes on without
    /// this device — a terminal in tmux is detached, not closed (D44, 2026-10-02: *"It should
    /// recognise the connection type and present the correct action words, even if they do the
    /// same technical thing"*).
    public let closeTitle: String
    public let closeSymbolName: String
    /// What the session looks like right now, when the capability can cheaply draw it.
    ///
    /// **Optional by design, and genuinely optional in practice.** The terminal has rendered
    /// itself since glas.sh (`SwiftTermHostModel.previewImage(maxPixelWidth:)`); the editor and
    /// the database have nothing to photograph, and a card with a name and a symbol on it is
    /// useful where a card waiting for a screenshot would not be. Asked at draw time, never
    /// stored — a picture of a terminal is stale the moment it is taken.
    public let snapshot: (@MainActor () -> Image?)?
    /// What runs in it, as a mark over its picture: the AI agent a terminal is running (the
    /// owner, 2026-10-14: "the whole 9" — All Windows off the Mac marks them as the Mac does). A
    /// template image; nil for none.
    public let mark: (@MainActor () -> Image?)?
    /// The services this session is a connection through — a terminal's server, a database's
    /// connection. The library turns these into the machine the session belongs to, so a
    /// capability never has to know a host id. Several for a workgroup that spans machines.
    public let endpointIDs: [EndpointID]
    /// The machine, said directly, for a session that is not through a service: an editor with
    /// a project on this device (`GlassLocalHost.id`) or on another machine.
    public let hostID: HostID?
    /// The services this session is connected through right now — the library's green dot,
    /// like DBeaver's connected marker (2026-10-03). A session still connecting, reconnecting or
    /// failed is open but not connected; a workgroup is connected only through its live terminals.
    public let connectedEndpointIDs: [EndpointID]
    /// The window's tabs, each a card of its own in All Windows off the Mac, grouped by the machine
    /// each is on, as the Mac's Show All Windows draws a tile per tab (the owner, 2026-10-14:
    /// "Grouped by machine, but show each tab as a card"). Empty for a session that is one thing;
    /// Active still lists the window as one row.
    public let tabs: [GlassOpenSession]
    /// A tab of an open window that connects when it is shown — the iPhone opens a window's other
    /// tabs that way, and leaves them so after the app was away. Not connected, but live: All
    /// Windows shows it, and choosing it connects it (the owner, 2026-10-15: "in the expose it show
    /// one card for all tabs").
    public let waitsToBeShown: Bool
    /// What ending it would lose, said as a sentence — an editor's documents with changes not yet
    /// saved — asked as it is ended; nil when nothing is lost. Ending such a session from outside
    /// it asks first (`requestClose`, `glassAskingBeforeClosing`), as closing a document does
    /// (2026-10-17: Active and All Windows threw unsaved editor changes away without a word).
    public let unsavedChanges: (@MainActor () -> String?)?
    /// What the session's own window paints behind its picture where that window has an opaque page
    /// — a terminal's theme on iPhone and iPad — so its card is the same, nil where the picture
    /// stands on its own (2026-10-17, the owner, on All Windows in light mode: a dark theme's
    /// see-through picture was green text on the white sheet).
    public let backdrop: (@MainActor () -> GlassSessionBackdrop?)?
    /// When it was last in use (2026-10-20): a terminal's last input or output, a database's last
    /// query or browse, a desktop's last input or moment in front. The library counts a minute in use
    /// for its machine when this falls inside the minute. Nil for a session that doesn't say.
    public let lastActivity: (@MainActor () -> Date?)?

    public init(id: String, title: String, subtitle: String? = nil, symbolName: String,
                endpointIDs: [EndpointID] = [], hostID: HostID? = nil,
                activate: @escaping @MainActor @Sendable () -> Void,
                close: @escaping @MainActor @Sendable () -> Void,
                closeTitle: String = "Close", closeSymbolName: String = "xmark",
                isConnected: Bool = true, connectedEndpointIDs: [EndpointID]? = nil,
                snapshot: (@MainActor () -> Image?)? = nil, mark: (@MainActor () -> Image?)? = nil,
                tabs: [GlassOpenSession] = [], waitsToBeShown: Bool = false,
                unsavedChanges: (@MainActor () -> String?)? = nil,
                backdrop: (@MainActor () -> GlassSessionBackdrop?)? = nil,
                lastActivity: (@MainActor () -> Date?)? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.endpointIDs = endpointIDs
        self.hostID = hostID
        self.activate = activate
        self.close = close
        self.connectedEndpointIDs = connectedEndpointIDs ?? (isConnected ? endpointIDs : [])
        self.closeTitle = closeTitle
        self.closeSymbolName = closeSymbolName
        self.snapshot = snapshot
        self.mark = mark
        self.tabs = tabs
        self.waitsToBeShown = waitsToBeShown
        self.unsavedChanges = unsavedChanges
        self.backdrop = backdrop
        self.lastActivity = lastActivity
    }

    /// Ends it, or hands it to `ask` when ending it would lose something (`unsavedChanges`).
    @MainActor
    public func requestClose(asking ask: (GlassOpenSession) -> Void) {
        if unsavedChanges?() != nil { ask(self) } else { close() }
    }
}

/// The colour a session's window paints behind it, and its light or dark — what is drawn over it
/// (a card's name, its close button) takes that, as the terminal's own controls do. Nil for a
/// colour scheme that follows the system.
public struct GlassSessionBackdrop: Equatable, Sendable {
    public let color: Color
    public let colorScheme: ColorScheme?

    public init(color: Color, colorScheme: ColorScheme?) {
        self.color = color
        self.colorScheme = colorScheme
    }
}

extension View {
    /// The question before ending a session that would lose something: the one closing a document
    /// in the editor asks, in the same words. `asking` is the session waiting on an answer
    /// (`GlassOpenSession.requestClose`); `didClose` runs once it has been ended.
    public func glassAskingBeforeClosing(_ asking: Binding<GlassOpenSession?>,
                                         didClose: @escaping @MainActor () -> Void = {}) -> some View {
        confirmationDialog("Close without saving?", isPresented: Binding(
            get: { asking.wrappedValue != nil }, set: { if !$0 { asking.wrappedValue = nil } }),
            titleVisibility: .visible, presenting: asking.wrappedValue) { session in
            Button("Discard Changes", role: .destructive) {
                asking.wrappedValue = nil
                session.close()
                didClose()
            }
            Button("Cancel", role: .cancel) { asking.wrappedValue = nil }
        } message: { session in
            Text(session.unsavedChanges?() ?? "")
        }
    }
}

/// D44: a session that lives on a host rather than in this app — a tmux session, today — which
/// this device is not showing. It may be detached, or open on another device. Active lists these
/// under their machine so work started anywhere can be picked up here.
public struct GlassRunningSession: Identifiable {
    /// Unique across capabilities; prefix it with the contributor, as `GlassOpenSession.id` is.
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbolName: String
    /// The service it runs through; the library turns it into the machine.
    public let endpointID: EndpointID
    /// Another client is attached right now — another device, or a terminal outside Glass.
    public let isAttachedElsewhere: Bool
    /// A window here already shows it, though the app lists it nowhere else — a Mac's local tab in
    /// tmux (W6). Open goes to that window rather than attaching again, and the row stays listed.
    public let isOpenHere: Bool
    /// Open it here. Alongside any other client; for a session open here, go to it.
    public let open: @MainActor () -> Void
    /// Open it here and detach every other client.
    public let takeOver: @MainActor () -> Void
    /// End it on the host. Whatever is running in it stops.
    public let end: @MainActor () async throws -> Void
    /// What to attach to when it opens with others in one new window (W13). Nil for a session its
    /// capability opens only one at a time.
    public let attachment: GlassRunningAttachment?

    public init(id: String, title: String, subtitle: String? = nil, symbolName: String,
                endpointID: EndpointID, isAttachedElsewhere: Bool, isOpenHere: Bool = false,
                open: @escaping @MainActor () -> Void, takeOver: @escaping @MainActor () -> Void,
                end: @escaping @MainActor () async throws -> Void,
                attachment: GlassRunningAttachment? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.symbolName = symbolName
        self.endpointID = endpointID; self.isAttachedElsewhere = isAttachedElsewhere; self.isOpenHere = isOpenHere
        self.open = open; self.takeOver = takeOver; self.end = end
        self.attachment = attachment
    }
}

/// A running session as something to attach to, so Active can open several in one new window
/// (W13, owner, 2026-10-09: "select multiple and open in a new window like the tab view"). Each
/// row's own `open` opens a window of its own, so it can't be called N times for this.
public struct GlassRunningAttachment: Hashable, Sendable {
    /// The capability that opens it (`GlassCapability.openRunningSessions`).
    public let kind: HostServiceKind
    /// The service it runs through.
    public let endpointID: EndpointID
    /// Its name there: a tmux session's, for a terminal.
    public let name: String

    public init(kind: HostServiceKind, endpointID: EndpointID, name: String) {
        self.kind = kind; self.endpointID = endpointID; self.name = name
    }
}

/// A window here that a running session can join as one more tab (the owner, 2026-10-15: "The
/// context menu for active but detached terminals should show existing tab groups. So I can open a
/// new session into a group"). Each capability lists its own (`GlassCapability.tabGroups`).
public struct GlassTabGroup: Identifiable, Hashable, Sendable {
    /// The capability's own id for the window.
    public let id: String
    /// What the window is called, as Active calls it.
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A machine Active could not ask what runs there, and why, in plain words (W6) — "Not checked:
/// signing in would need your password." Without it, a machine that was skipped looked like one
/// with nothing running.
public struct GlassUncheckedMachine: Identifiable {
    /// The service it would have been asked through; the library turns it into the machine.
    public let endpointID: EndpointID
    public let reason: String
    public var id: EndpointID { endpointID }

    public init(endpointID: EndpointID, reason: String) {
        self.endpointID = endpointID
        self.reason = reason
    }
}

/// What asking the machines came to: what runs there, and the machines that could not be asked.
public struct GlassRunningReport {
    public var sessions: [GlassRunningSession]
    public var unchecked: [GlassUncheckedMachine]

    public init(sessions: [GlassRunningSession] = [], unchecked: [GlassUncheckedMachine] = []) {
        self.sessions = sessions
        self.unchecked = unchecked
    }
}

/// Something open that isn't an open session, and when it last had input or output, for the
/// library's time in use (2026-10-20): a Mac terminal tab's local shells, which Active lists as This
/// Mac's running tmux sessions rather than as open sessions.
public struct GlassUsageActivity: Sendable, Equatable {
    /// The service it is through.
    public var endpointID: EndpointID
    public var lastActivity: Date?

    public init(endpointID: EndpointID, lastActivity: Date?) {
        self.endpointID = endpointID
        self.lastActivity = lastActivity
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

    /// Sessions running on hosts that this device is not showing (D44). Default: none. Asked when
    /// Active appears or is refreshed — it may reach out to hosts, so never from a view body.
    func runningSessions() async -> [GlassRunningSession] { [] }

    /// Activity outside open sessions. Default: none.
    func usageActivity() -> [GlassUsageActivity] { [] }

    /// The same, with the machines that could not be asked and why (W6). Default: the running
    /// sessions, and no machine left unasked.
    func runningReport() async -> GlassRunningReport { GlassRunningReport(sessions: await runningSessions()) }

    /// Opens running sessions together, in one new window, in the order given (W13). Default:
    /// nothing, for a capability whose rows carry no attachment.
    func openRunningSessions(_ attachments: [GlassRunningAttachment]) {}

    /// The windows a running session can join as a tab. Default: none.
    func tabGroups() -> [GlassTabGroup] { [] }

    /// Opens running sessions as more tabs of a window. Default: nothing.
    func openRunningSessions(_ attachments: [GlassRunningAttachment], inTabGroup group: GlassTabGroup.ID) {}
}

public extension GlassCapabilityRegistry {
    /// Every open session, capabilities in kind order and then the standalone providers.
    ///
    /// Call this **inside a view body**. See `openSessions()` above for why.
    func openSessions() -> [GlassOpenSession] {
        registered.flatMap { $0.openSessions() } + standaloneSessions()
    }

    /// Every capability's activity outside its open sessions (2026-10-20).
    func usageActivity() -> [GlassUsageActivity] {
        registered.flatMap { $0.usageActivity() }
    }

    /// Every capability's running sessions (D44). Each capability asks its own hosts together.
    func runningSessions() async -> [GlassRunningSession] {
        await runningReport().sessions
    }

    /// Every capability's running sessions and the machines it could not ask (W6).
    func runningReport() async -> GlassRunningReport {
        var all = GlassRunningReport()
        for capability in registered {
            let report = await capability.runningReport()
            all.sessions += report.sessions
            all.unchecked += report.unchecked
        }
        return all
    }

    /// Opens running sessions together (W13): each capability's own in one new window of its
    /// own, in the order given. Today only the terminal's rows carry an attachment.
    func openRunningSessions(_ attachments: [GlassRunningAttachment]) {
        var kinds: [HostServiceKind] = []
        for attachment in attachments where !kinds.contains(attachment.kind) { kinds.append(attachment.kind) }
        for kind in kinds {
            capability(for: kind)?.openRunningSessions(attachments.filter { $0.kind == kind })
        }
    }

    /// The windows here that a running session of `kind` can join as a tab (Open as Tab In).
    func tabGroups(for kind: HostServiceKind) -> [GlassTabGroup] {
        capability(for: kind)?.tabGroups() ?? []
    }

    /// Opens running sessions as more tabs of `group`, a window their capability listed.
    func openRunningSessions(_ attachments: [GlassRunningAttachment], inTabGroup group: GlassTabGroup.ID) {
        guard let kind = attachments.first?.kind else { return }
        capability(for: kind)?.openRunningSessions(attachments.filter { $0.kind == kind }, inTabGroup: group)
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
