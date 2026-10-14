//
//  GlassShowAllWindowsOverview.swift
//  Glass Power Tools — GlassShell
//
//  Show All Windows off the Mac (the owner, 2026-10-14: "everything other than Mac can still use
//  the lightning bolt hold pattern"; on iPhone and iPad a pinch too, "index and middle, with a
//  thumb"). Everything open, as cards by machine: Active's own list (`activeMachines`) with the
//  pictures the sessions can draw (`GlassOpenSession.snapshot`), and the sessions running on the
//  machines with no window here. The Mac keeps its own overlay (`MacTerminalExpose`).
//
//  A card opens its session the way the ⚡ goes to Active: the screen the overview was opened
//  from is left first (`dismissCurrent`), then the session is brought back.
//

import SwiftUI
import GlassConnectionKit

public extension GlassShowAllWindows {
    /// The library, for the overview off the Mac. Set by the composition root.
    static weak var model: GlassShellModel?
}

/// Everything open, by machine, as cards.
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
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(machine.sessions) { session in
                                    GlassSessionCard(session: session,
                                                     activate: { open(session.activate) },
                                                     close: { session.close() })
                                }
                                ForEach(machine.running.filter { !$0.isOpenHere }) { running in
                                    GlassRunningSessionCard(session: running) {
                                        open { [weak model] in model?.open(running) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("All Windows")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: "Machines and sessions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                        .accessibilityIdentifier("all-windows-done")
                }
            }
            .task { await model.refreshRunningSessionsIfDue() }
        }
        .accessibilityIdentifier("all-windows")
    }

    /// The machines with what matches `search` — a machine's name keeps all of it, a session's
    /// title or subtitle keeps that session — and machines left with nothing dropped.
    static func filtered(_ machines: [GlassActiveMachine], by search: String) -> [GlassActiveMachine] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let notOpenHere = machines.map { machine -> GlassActiveMachine in
            var machine = machine
            machine.running = machine.running.filter { !$0.isOpenHere }
            return machine
        }
        guard !query.isEmpty else {
            return notOpenHere.filter { !$0.sessions.isEmpty || !$0.running.isEmpty }
        }
        func matches(_ text: String?) -> Bool { text?.localizedCaseInsensitiveContains(query) == true }
        return notOpenHere.compactMap { machine in
            if matches(machine.name) { return machine.sessions.isEmpty && machine.running.isEmpty ? nil : machine }
            var kept = GlassActiveMachine(id: machine.id, name: machine.name,
                                          sessions: machine.sessions.filter { matches($0.title) || matches($0.subtitle) })
            kept.running = machine.running.filter { matches($0.title) || matches($0.subtitle) }
            return kept.sessions.isEmpty && kept.running.isEmpty ? nil : kept
        }
    }
}

/// A session running on its machine with no window here — a tmux session — as a card: no picture
/// to show, so its symbol, quieter than an open one's, and Attach as what a tap does.
struct GlassRunningSessionCard: View {
    let session: GlassRunningSession
    let attach: () -> Void

    var body: some View {
        Button(action: attach) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    Image(systemName: session.symbolName)
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                }
                .aspectRatio(GlassGalleryLayout.aspectRatio, contentMode: .fit)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(session.isAttachedElsewhere ? "Open elsewhere · Attach" : "Running · Attach")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("running-card-\(session.id)")
        .accessibilityLabel(session.title)
        .accessibilityHint("Attaches to this running session")
    }
}

#if os(iOS)
import UIKit

public extension GlassShowAllWindows {
    /// Opens the overview over whatever is on screen — the library, a terminal, a desktop, an
    /// editor. `dismissCurrent` leaves the screen it was opened from before a card opens another,
    /// as the ⚡'s own tap does; nil from the library, which nothing covers.
    static func presentOverview(dismissCurrent: (@MainActor () -> Void)?) {
        guard let model, presentedOverview == nil, let top = topViewController() else { return }
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.modalPresentationStyle = .fullScreen
        func close(then chosen: (@MainActor () -> Void)?) {
            host.dismiss(animated: true) {
                MainActor.assumeIsolated {
                    presentedOverview = nil
                    guard let chosen else { return }
                    dismissCurrent?()
                    chosen()
                }
            }
        }
        host.rootView = AnyView(GlassShowAllWindowsOverview(model: model, done: { close(then: nil) },
                                                            open: { close(then: $0) }))
        presentedOverview = host
        top.present(host, animated: true)
    }

    private static weak var presentedOverview: UIViewController?

    /// The view controller showing now, in the scene in front: what a presentation goes over.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}
#endif
