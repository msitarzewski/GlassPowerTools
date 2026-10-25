//
//  GlassShowAllWindowsOverview.swift
//  Glass Power Tools — GlassShell
//
//  Show All Windows off the Mac (the owner, 2026-10-14: "everything other than Mac can still use
//  the lightning bolt hold pattern"; "drag down from an empty space in the toolbar … slide in like
//  a separate transparent pane"; "the card view should only show connected services, like Mac.
//  transparent previews, the whole 9"). What is open, as cards by machine — a card per window,
//  and per tab of a window that has them (`allWindowsMachines`) — laid out as the Mac lays out
//  its tiles (`GlassAllWindowsLayout`) and drawn straight onto the glass the way they are: the
//  session's own picture where it can draw one (`GlassOpenSession.snapshot`), taken again every
//  second, softened when Settings ▸ Appearance ▸ Show All Windows ▸ Blur previews is on. Sessions
//  running on a machine with no window here are Active's, not this.
//
//  A card opens its session the way the ⚡ goes to Active: the screen the overview was opened
//  from is left first (`dismissCurrent`), then the session is brought back. On iPhone and iPad it
//  slides down from the top as a pane (`GlassAllWindowsPane`); on Vision Pro it is a window of
//  its own (`GlassAllWindowsWindow`).
//

import SwiftUI
import GlassConnectionKit

public extension GlassShowAllWindows {
    /// The library, for the overview off the Mac. Set by the composition root.
    static weak var model: GlassShellModel?
}

/// What is open, by machine, as cards: laid out as the Mac's Show All Windows is
/// (`GlassAllWindowsLayout`), a group per machine and a card per tab, every card the same size
/// and as large as the space allows (the owner, 2026-10-14: "please mirror the Mac layout …
/// The view should adjust itself based on the number of sessions showing").
struct GlassShowAllWindowsOverview: View {
    let model: GlassShellModel
    let done: @MainActor () -> Void
    /// Closes the overview, leaves the screen it was opened from, then runs what was chosen.
    let open: @MainActor (_ chosen: @escaping @MainActor () -> Void) -> Void
    /// Vision Pro: the same cards around the person (`GlassAllWindowsAround`).
    var around: (@MainActor () -> Void)? = nil
    @State private var search = ""

    var body: some View {
        let machines = Self.filtered(model.allWindowsMachines(), by: search)
        NavigationStack {
            GeometryReader { proxy in
                if machines.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Nothing Is Open" : "No Matches",
                                           systemImage: search.isEmpty ? "bolt.slash" : "magnifyingglass",
                                           description: Text(search.isEmpty
                                                             ? "Connect to a machine and its session appears here."
                                                             : "Nothing open is called “\(search)”."))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    GlassAllWindowsArrangement(machines: machines, size: proxy.size, open: open)
                }
            }
            .padding(Self.margin)
            .navigationTitle("All Windows")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            #endif
            .searchable(text: $search, prompt: "Machines and sessions")
            .toolbar {
                if let around {
                    ToolbarItem(placement: .primaryAction) {
                        // Its words as well as its symbol: a toolbar shows a symbol alone.
                        Button(action: around) {
                            HStack(spacing: 6) {
                                Image(systemName: "pano")
                                Text("Around You")
                            }
                        }
                        .help("Show every window around you")
                            .accessibilityIdentifier("all-windows-around-you")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                        .accessibilityIdentifier("all-windows-done")
                }
            }
        }
        .accessibilityIdentifier("all-windows")
    }

    /// The space around the groups: the phone's side gutter, more in a window on the headset.
    #if os(visionOS)
    static let margin: CGFloat = 24
    #else
    static let margin: CGFloat = 16
    #endif

    /// The machines with something live that matches `search` — a machine's name keeps all of it,
    /// a session's title or subtitle keeps that session — and machines left with nothing dropped.
    /// Live only: All Windows is for going to what is working now (the owner, 2026-10-14: "Should
    /// only be connected as it's a shortcut to switching active/live sessions/services"). A session
    /// through services is live while it is connected through one; one through none — an editor's
    /// documents — is live while it is open; a tab waiting to connect when it is shown is live, as
    /// its window is (2026-10-15: the iPhone's window of tabs was one card).
    static func filtered(_ machines: [GlassActiveMachine], by search: String) -> [GlassActiveMachine] {
        let open = machines
            .map { GlassActiveMachine(id: $0.id, name: $0.name, sessions: $0.sessions.filter(isLive)) }
            .filter { !$0.sessions.isEmpty }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return open }
        func matches(_ text: String?) -> Bool { text?.localizedCaseInsensitiveContains(query) == true }
        return open.compactMap { machine in
            if matches(machine.name) { return machine }
            let sessions = machine.sessions.filter { matches($0.title) || matches($0.subtitle) }
            return sessions.isEmpty ? nil : GlassActiveMachine(id: machine.id, name: machine.name, sessions: sessions)
        }
    }

    static func isLive(_ session: GlassOpenSession) -> Bool {
        session.endpointIDs.isEmpty || !session.connectedEndpointIDs.isEmpty || session.waitsToBeShown
    }
}

/// The groups and their cards, placed where `GlassAllWindowsLayout` puts them — as the Mac places
/// its tiles (`MacTerminalExposeView`). It scrolls only when even the smallest cards cannot fit.
struct GlassAllWindowsArrangement: View {
    let machines: [GlassActiveMachine]
    let size: CGSize
    let open: @MainActor (_ chosen: @escaping @MainActor () -> Void) -> Void
    /// A session whose ending would lose something, waiting on the question.
    @State private var asking: GlassOpenSession?

    var body: some View {
        let layout = GlassAllWindowsLayout(tileCounts: machines.map(\.sessions.count), in: size)
        Group {
            if layout.scrolls {
                ScrollView {
                    canvas(layout)
                        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                }
            } else {
                canvas(layout)
            }
        }
        .glassAskingBeforeClosing($asking)
    }

    private func canvas(_ layout: GlassAllWindowsLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(machines, layout.groups)), id: \.0.id) { machine, frames in
                group(machine, frames: frames, tileSize: layout.tileSize, allOnScreen: !layout.scrolls)
                    .frame(width: frames.frame.width, height: frames.frame.height)
                    .position(x: frames.frame.midX, y: frames.frame.midY)
            }
        }
    }

    /// A machine: its name, and a card for each window or tab open on it, on glass of its own as
    /// the Mac's groups are.
    private func group(_ machine: GlassActiveMachine, frames: GlassAllWindowsLayout.Group, tileSize: CGSize,
                       allOnScreen: Bool) -> some View {
        let origin = frames.frame.origin
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
            Label(machine.name, systemImage: "server.rack")
                .font(.headline)
                .lineLimit(1)
                .frame(width: frames.titleFrame.width, height: frames.titleFrame.height, alignment: .leading)
                .offset(x: frames.titleFrame.minX - origin.x, y: frames.titleFrame.minY - origin.y)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(zip(machine.sessions, frames.tileFrames)), id: \.0.id) { session, frame in
                GlassAllWindowsCard(session: session, activate: { open(session.activate) },
                                    close: { session.requestClose { asking = $0 } },
                                    alwaysOnScreen: allOnScreen)
                    .frame(width: tileSize.width, height: tileSize.height)
                    .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(machine.name)
    }
}

/// One open session or tab, as the Mac's tiles are drawn: its own picture with no plate behind it,
/// so what is transparent in it stays transparent; its symbol, large and quiet, where it has no
/// picture; its name over the bottom of it; and a way to close it.
///
/// **Live.** The picture is taken again every second while the card is on screen and the window
/// is in front, as the Mac's tiles are (`MacTerminalOverview`). A terminal draws itself while it
/// is on screen somewhere — any window on the headset; on an iPhone only the one under the pane —
/// and gives the last picture it drew otherwise.
struct GlassAllWindowsCard: View {
    let session: GlassOpenSession
    let activate: () -> Void
    let close: () -> Void
    /// Every card fits without scrolling, so every card is on screen.
    var alwaysOnScreen = false
    @AppStorage(GlassShowAllWindows.blursPreviewsKey) private var blursPreviews = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrolledOnScreen = false

    /// What the session's window paints behind it, where a window has an opaque page: iPhone and
    /// iPad. A Vision Pro window is glass, and its card stays as clear as the window is.
    private var backdrop: GlassSessionBackdrop? {
        #if os(iOS)
        session.backdrop?()
        #else
        nil
        #endif
    }

    var body: some View {
        let backdrop = backdrop
        Button(action: activate) {
            ZStack {
                if let backdrop { backdrop.color }
                TimelineView(.animation(minimumInterval: 1, paused: !refreshes)) { _ in
                    if let snapshot = session.snapshot?() {
                        // The card's width filled, its newest part kept: a phone's terminal is
                        // tall, and fitted whole it was a sliver (2026-10-14, the simulator).
                        Color.clear.overlay(alignment: .bottom) {
                            snapshot
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: blursPreviews ? GlassShowAllWindows.previewBlurRadius : 0)
                        }
                    } else {
                        Image(systemName: session.symbolName)
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { GlassAllWindowsMark(image: session.mark?()) }
            // Always shown, where the Mac shows it on hover: nothing here hovers but a look.
            .overlay(alignment: .bottom) {
                GlassAllWindowsCaption(title: session.title, detail: session.subtitle)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10, style: .continuous))
        .hoverEffect()
        #endif
        .accessibilityIdentifier("all-windows-card-\(session.id)")
        .accessibilityLabel(session.title)
        .accessibilityValue(session.subtitle ?? "")
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive, action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("\(session.closeTitle) \(session.title)")
        }
        .onScrollVisibilityChange(threshold: 0.01) { scrolledOnScreen = $0 }
        // Its name, its close button and its mark in the backdrop's own light or dark, as the
        // terminal's controls are over its theme (ce2dbf6), whatever the sheet around it is.
        .environment(\.colorScheme, backdrop?.colorScheme ?? colorScheme)
    }

    /// Whether the picture is being taken again each second: on screen, in a window in front.
    private var refreshes: Bool {
        (alwaysOnScreen || scrolledOnScreen) && scenePhase == .active
    }
}

/// A card's name and state over the bottom of its picture, legible over whatever the picture shows
/// (the Mac's tile caption, `MacTerminalExposeCaption`).
struct GlassAllWindowsCaption: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The AI agent's mark over a card's picture, as the Mac draws it over a tile
/// (`MacTerminalExposeAgentMark`): a suggestion, not a statement — 18% of the picture's width
/// within 18 to 52 points, white at 40%, lightening what is under it, nothing behind it.
struct GlassAllWindowsMark: View {
    let image: Image?

    var body: some View {
        if let image {
            GeometryReader { proxy in
                let side = min(52, max(18, proxy.size.width * 0.18))
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .foregroundStyle(.white.opacity(0.4))
                    .blendMode(.plusLighter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
