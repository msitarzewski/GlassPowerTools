//
//  GlassShowAllWindowsOverview.swift
//  Glass Power Tools — GlassShell
//
//  Show All Windows off the Mac (the owner, 2026-10-14: "everything other than Mac can still use
//  the lightning bolt hold pattern"; "drag down from an empty space in the toolbar … slide in like
//  a separate transparent pane"; "the card view should only show connected services, like Mac.
//  transparent previews, the whole 9"). What is open, as cards by machine — Active's own list
//  (`activeMachines`) — each drawn straight onto the pane's glass the way the Mac's tiles are:
//  the session's own picture where it can draw one (`GlassOpenSession.snapshot`), softened when
//  Settings ▸ Appearance ▸ Show All Windows ▸ Blur previews is on. Sessions running on a machine
//  with no window here are Active's, not this.
//
//  A card opens its session the way the ⚡ goes to Active: the screen the overview was opened
//  from is left first (`dismissCurrent`), then the session is brought back. On iPhone and iPad it
//  slides down from the top as a pane (`GlassAllWindowsPane`).
//

import SwiftUI
import GlassConnectionKit

public extension GlassShowAllWindows {
    /// The library, for the overview off the Mac. Set by the composition root.
    static weak var model: GlassShellModel?
}

/// What is open, by machine, as cards.
struct GlassShowAllWindowsOverview: View {
    let model: GlassShellModel
    let done: @MainActor () -> Void
    /// Closes the overview, leaves the screen it was opened from, then runs what was chosen.
    let open: @MainActor (_ chosen: @escaping @MainActor () -> Void) -> Void
    @State private var search = ""

    var body: some View {
        let machines = Self.filtered(model.activeMachines(), by: search)
        NavigationStack {
            ScrollView {
                if machines.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Nothing Is Open" : "No Matches",
                                           systemImage: search.isEmpty ? "bolt.slash" : "magnifyingglass",
                                           description: Text(search.isEmpty
                                                             ? "Connect to a machine and its session appears here."
                                                             : "Nothing open is called “\(search)”."))
                        .padding(.top, 60)
                }
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(machines) { machine in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(machine.name)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 16) {
                                ForEach(machine.sessions) { session in
                                    GlassAllWindowsCard(session: session,
                                                        activate: { open(session.activate) },
                                                        close: { session.close() })
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("All Windows")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            #endif
            .searchable(text: $search, prompt: "Machines and sessions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                        .accessibilityIdentifier("all-windows-done")
                }
            }
        }
        .accessibilityIdentifier("all-windows")
    }

    /// The machines with something open that matches `search` — a machine's name keeps all of it,
    /// a session's title or subtitle keeps that session — and machines left with nothing dropped.
    static func filtered(_ machines: [GlassActiveMachine], by search: String) -> [GlassActiveMachine] {
        let open = machines.filter { !$0.sessions.isEmpty }
            .map { GlassActiveMachine(id: $0.id, name: $0.name, sessions: $0.sessions) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return open }
        func matches(_ text: String?) -> Bool { text?.localizedCaseInsensitiveContains(query) == true }
        return open.compactMap { machine in
            if matches(machine.name) { return machine }
            let sessions = machine.sessions.filter { matches($0.title) || matches($0.subtitle) }
            return sessions.isEmpty ? nil : GlassActiveMachine(id: machine.id, name: machine.name, sessions: sessions)
        }
    }
}

/// One open session on the pane's glass, as the Mac's tiles are drawn: its own picture with no
/// plate behind it, so what is transparent in it stays transparent; its symbol, large and quiet,
/// where it has no picture; its name under it; and a way to close it.
struct GlassAllWindowsCard: View {
    let session: GlassOpenSession
    let activate: () -> Void
    let close: () -> Void
    @AppStorage(GlassShowAllWindows.blursPreviewsKey) private var blursPreviews = false

    var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
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
                .frame(maxWidth: .infinity)
                .aspectRatio(GlassGalleryLayout.aspectRatio, contentMode: .fit)
                .overlay { GlassAllWindowsMark(image: session.mark?()) }
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let subtitle = session.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
