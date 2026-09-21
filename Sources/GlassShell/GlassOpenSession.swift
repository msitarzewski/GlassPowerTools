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

    public init(id: String, title: String, subtitle: String? = nil, symbolName: String,
                activate: @escaping @MainActor @Sendable () -> Void,
                close: @escaping @MainActor @Sendable () -> Void,
                snapshot: (@MainActor () -> Image?)? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
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

// MARK: - The control, and the list behind it

/// Puts a **Sessions** control in a session's own chrome, with the switcher behind it.
///
/// Only where there is no second window to do this job: on macOS, visionOS and iPad the windows
/// *are* the switcher, and a button that duplicates them is clutter. The gate is
/// `GlassWindowPresentation.canOpenWindows` rather than `#if os(iOS)` — the difference is an
/// iPhone against an iPad and both compile as `os(iOS)`, and an iPhone Duo will answer it for
/// itself when it arrives.
///
/// `dismissCurrent` is for a session presented as a cover rather than in place: the editor's and
/// the desktop's sessions sit *above* the library, so activating a terminal underneath one would
/// switch a screen nobody can see. A session that swaps the root passes nil.
public struct GlassSessionsToolbarModifier: ViewModifier {
    /// Optional so every session's chrome can attach this unconditionally. A view rendered
    /// outside the app — a preview, a unit test's host — has no registry, and the alternative
    /// was an `if let` repeated at all four call sites.
    private let registry: GlassCapabilityRegistry?
    private let currentSessionID: String?
    private let dismissCurrent: (@MainActor () -> Void)?
    @State private var isPresented = false

    public init(registry: GlassCapabilityRegistry?, currentSessionID: String?,
                dismissCurrent: (@MainActor () -> Void)? = nil) {
        self.registry = registry
        self.currentSessionID = currentSessionID
        self.dismissCurrent = dismissCurrent
    }

    public func body(content: Content) -> some View {
        // Read in the body, so the count follows the capabilities' own state.
        let others = GlassWindowPresentation.canOpenWindows
            ? []
            : (registry?.openSessions(excluding: currentSessionID) ?? [])
        content
            .toolbar {
                // Nothing open elsewhere means no control at all. A Sessions button that opens an
                // empty sheet is worse than no button: it promises somewhere to go.
                if !others.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isPresented = true
                        } label: {
                            Label("\(others.count) other sessions", systemImage: "square.stack")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("sessions-switcher")
                        .accessibilityLabel("Sessions")
                        .accessibilityValue("\(others.count) open elsewhere")
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                if let registry {
                    GlassSessionSwitcher(registry: registry, currentSessionID: currentSessionID) { session in
                        isPresented = false
                        dismissCurrent?()
                        session.activate()
                    }
                    // A peek, not a place. Switching is a glance at a short list and a tap, and
                    // a sheet that covers the session you are leaving makes it feel like one.
                    .presentationDetents([.medium, .large])
                }
            }
    }
}

public extension View {
    /// See `GlassSessionsToolbarModifier`.
    func glassSessionsToolbar(registry: GlassCapabilityRegistry?,
                              currentSessionID: String?,
                              dismissCurrent: (@MainActor () -> Void)? = nil) -> some View {
        modifier(GlassSessionsToolbarModifier(registry: registry,
                                              currentSessionID: currentSessionID,
                                              dismissCurrent: dismissCurrent))
    }
}

/// Stage 1 of D3: a list that works. One row per open session, swipe to close.
///
/// Flat rather than grouped. A phone holds a handful of sessions, each row already carries the
/// capability's symbol and says what its service is, and sections over three rows are furniture.
/// The carousel is stage 2 and replaces this view, not the seam beneath it.
public struct GlassSessionSwitcher: View {
    private let registry: GlassCapabilityRegistry
    private let currentSessionID: String?
    private let activate: (GlassOpenSession) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(registry: GlassCapabilityRegistry, currentSessionID: String?,
                activate: @escaping (GlassOpenSession) -> Void) {
        self.registry = registry
        self.currentSessionID = currentSessionID
        self.activate = activate
    }

    /// Cards or rows, remembered. The product already has this choice for a workgroup's
    /// terminals (`LayoutPreset.OpeningView`), so the switcher offers the same one rather than
    /// inventing a third vocabulary — and defaults to the gallery, because seeing which terminal
    /// is which is the reason to have it.
    @AppStorage("com.glasspowertools.sessions.gallery") private var showsGallery = true

    public var body: some View {
        let sessions = registry.openSessions(excluding: currentSessionID)
        NavigationStack {
            Group {
                if showsGallery, !sessions.isEmpty {
                    GlassSessionGallery(sessions: sessions, activate: activate)
                } else {
                    list(sessions)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("Presentation", selection: $showsGallery) {
                        Label("Gallery", systemImage: "square.grid.2x2").tag(true)
                        Label("List", systemImage: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("sessions-presentation")
                }
            }
        }
    }

    private func list(_ sessions: [GlassOpenSession]) -> some View {
            List {
                ForEach(sessions) { session in
                    Button {
                        activate(session)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: session.symbolName)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                if let subtitle = session.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    // A row, not a link. The default button tint painted the machine's name blue,
                    // which reads as "tap this word" rather than "you are somewhere else".
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session-row-\(session.id)")
                    .swipeActions(edge: .trailing) {
                        Button("Close", systemImage: "xmark", role: .destructive) {
                            session.close()
                        }
                    }
                }
                if sessions.isEmpty {
                    // Reachable only if the last other session ended while the sheet was open.
                    ContentUnavailableView("Nothing else is open",
                                           systemImage: "square.stack",
                                           description: Text("Connections you open stay here until you close them."))
                }
            }
    }
}
