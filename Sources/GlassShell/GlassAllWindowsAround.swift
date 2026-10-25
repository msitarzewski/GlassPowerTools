//
//  GlassAllWindowsAround.swift
//  Glass Power Tools — GlassShell
//
//  Show All Windows on Vision Pro, around the person as well as in a window (the owner, 2026-10-21:
//  "figure out if we can use gestures to create an expose like experience that does exactly the
//  Mac's thing but in vision pro", then "build both with the switch"):
//
//  - **In a Window** — All Windows' own window (`GlassAllWindowsWindow`).
//  - **Around You** — the app's own immersive space, where the room clears of other apps and the
//    same cards stand in an arc at arm's length, a group per machine, as the Mac's groups are.
//
//  The ⚡ held opens whichever Settings ▸ Appearance ▸ Show All Windows ▸ Opens names; the window's
//  Around You and the arc's In a Window switch between them, and in the arc a two-handed pinch out
//  steps back. **Not a two-handed pinch on a window:** it was the way in (the Mac's two-finger pinch,
//  visionOS's Zoom), but on the headset visionOS takes a two-handed pinch on a window as resizing it
//  (the owner, 2026-10-22: "two handed pinch resizes the window"). The arc is no window, so its pinch
//  out stays.
//
//  **What it can't do.** visionOS lets no app move its windows or know where they are, so the real
//  windows don't shrink into a grid and fly back: the cards are their live pictures, as the Mac's
//  Show All Windows draws them, and choosing one brings that window to you. Hand tracking itself,
//  for gestures of our own, runs only in a Full Space with the person's permission ("ARKit data is
//  available only when your app presents a Full Space and other apps are hidden"); the arc needs
//  none, and asks for none. Only one immersive space is open at a time: Focus Mode's steps aside for
//  the arc and comes back after.
//

import SwiftUI
import GlassLayers

/// A two-handed pinch, in steps: in, further in, and out, each answered once per gesture. The arc
/// steps back on out. Pure, so it is tested without a headset.
public struct GlassPinchSteps: Equatable {
    public enum Step: Hashable { case inward, deeper, outward }

    /// The pinch's scale against where it began: a deliberate pinch passes these in a moment, a
    /// hand that drifts doesn't.
    public static let inwardScale: CGFloat = 0.8
    public static let deeperScale: CGFloat = 0.55
    public static let outwardScale: CGFloat = 1.25

    private var reached: Set<Step> = []

    public init() {}

    /// The step `magnification` takes the gesture to, the first time it does.
    public mutating func track(_ magnification: CGFloat) -> Step? {
        guard magnification.isFinite, magnification > 0 else { return nil }
        if magnification <= Self.deeperScale, !reached.contains(.deeper) {
            reached.formUnion([.inward, .deeper])
            return .deeper
        }
        if magnification <= Self.inwardScale, !reached.contains(.inward) {
            reached.insert(.inward)
            return .inward
        }
        if magnification >= Self.outwardScale, !reached.contains(.outward) {
            reached.insert(.outward)
            return .outward
        }
        return nil
    }

    /// The gesture ended: the next one starts again.
    public mutating func reset() {
        reached = []
    }
}

#if os(visionOS)
import RealityKit

/// The arc, and the way into it and out of it.
@MainActor
public enum GlassAllWindowsAround {
    public static let spaceID = "all-windows-around"
    /// Settings ▸ Appearance ▸ Show All Windows ▸ Opens: Around You when true, for the ⚡ held. This
    /// device's choice.
    public static let opensAroundKey = "com.glasspowertools.showAllWindows.opensAround"

    /// The immersive space open now, as each says as it appears (`glassImmersiveSpacePresence`).
    static var openSpace: String?
    /// The one that stepped aside for the arc, to bring back after it.
    static var restoreSpace: String?

    /// Every window where Settings ▸ Appearance ▸ Show All Windows ▸ Opens says: in its window, or
    /// around the person (`around`).
    public static func show(around: Bool, openWindow: OpenWindowAction, open: OpenImmersiveSpaceAction,
                            dismiss: DismissImmersiveSpaceAction) {
        if around {
            Task { await goAround(open: open, dismiss: dismiss) }
        } else {
            GlassShowAllWindows.presentOverview(openWindow: openWindow)
        }
    }

    /// The arc: whatever immersive space is open gives way to it, to come back afterwards.
    public static func goAround(open: OpenImmersiveSpaceAction, dismiss: DismissImmersiveSpaceAction) async {
        guard openSpace != spaceID else { return }
        if let other = openSpace {
            restoreSpace = other
            await dismiss()
        }
        _ = await open(id: spaceID)
    }

    /// Out of the arc: back to the window (`toWindow`), or to where the person was; and the space
    /// that gave way comes back.
    public static func leave(toWindow: Bool, openWindow: OpenWindowAction, open: OpenImmersiveSpaceAction,
                             dismiss: DismissImmersiveSpaceAction) async {
        // The window first: asked for once the space has gone, by the space's own action, it never
        // came (2026-10-21, the simulator).
        if toWindow { openWindow(id: GlassShowAllWindows.windowID) }
        if openSpace == spaceID { await dismiss() }
        if let restore = restoreSpace {
            restoreSpace = nil
            _ = await open(id: restore)
        }
    }
}

public extension View {
    /// Says which immersive space this is while it is open, so the arc knows what to step aside for
    /// and bring back. Apply to an `ImmersiveSpace`'s content.
    func glassImmersiveSpacePresence(_ id: String) -> some View {
        onAppear { GlassAllWindowsAround.openSpace = id }
            .onDisappear {
                if GlassAllWindowsAround.openSpace == id { GlassAllWindowsAround.openSpace = nil }
            }
    }
}


/// **Around You**: every session as a card, a group per machine, in an arc at arm's length where the
/// person looked as it opened, in the room with other apps' windows stepped away. A card's look and
/// pinch brings its window to the person; a pinch out with both hands, or In a Window, goes back to
/// the window; Done goes back to where the person was.
public struct GlassAllWindowsAroundView: View {
    private let model: GlassShellModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var steps = GlassPinchSteps()
    @State private var asking: GlassOpenSession?

    /// The arc's radius, and its rows' height against the person's eyes, in metres.
    static let radius: Float = 1.25
    static let drop: Float = -0.12
    /// Between one machine's group and the next, along the arc.
    static let gap: Float = 0.06

    public init(model: GlassShellModel) {
        self.model = model
    }

    public var body: some View {
        let machines = GlassShowAllWindowsOverview.filtered(model.allWindowsMachines(), by: "")
        RealityView { content, attachments in
            // Where the person's head was as the arc opened, kept: the arc stays put as they look
            // along it.
            let head = AnchorEntity(.head, trackingMode: .once)
            head.name = Self.anchorName
            content.add(head)
            Self.arrange(machines.map(\.id), in: head, attachments)
        } update: { content, attachments in
            guard let head = content.entities.first(where: { $0.name == Self.anchorName }) else { return }
            Self.arrange(machines.map(\.id), in: head, attachments)
        } attachments: {
            ForEach(machines) { machine in
                Attachment(id: machine.id) {
                    GlassAllWindowsAroundGroup(machine: machine, open: go(to:), close: { session in
                        session.requestClose { asking = $0 }
                    })
                    .simultaneousGesture(pinch)
                }
            }
            Attachment(id: Self.controlsID) {
                controls(isEmpty: machines.isEmpty)
                    .simultaneousGesture(pinch)
                    .glassAskingBeforeClosing($asking)
            }
        }
        // The room dimmed around the cards, as the system's own immersive views dim it: our windows
        // stay in it (visionOS lets no app hide them), and the cards stand out in front.
        .preferredSurroundingsEffect(.systemDark)
        #if DEBUG
        // Screenshots only: `--demo-all-windows-around-back` in a `--ui-testing` run goes back to the
        // window a few seconds in, as In a Window does.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-testing"), arguments.contains("--demo-all-windows-around-back") else { return }
            try? await Task.sleep(for: .seconds(6))
            leave(toWindow: true)
        }
        #endif
        .glassImmersiveSpacePresence(GlassAllWindowsAround.spaceID)
        .accessibilityIdentifier("all-windows-around")
    }

    private static let anchorName = "all-windows-around"
    private static let controlsID = "all-windows-around-controls"

    /// The groups along the arc, each turned to face the person, centred on where they looked; the
    /// controls below the middle.
    private static func arrange(_ ids: [String], in head: Entity, _ attachments: RealityViewAttachments) {
        let groups = ids.compactMap { attachments.entity(for: $0) }
        let widths = groups.map { max(0.2, $0.visualBounds(relativeTo: $0).extents.x) }
        let total = widths.reduce(0, +) + gap * Float(max(0, widths.count - 1))
        var start = -(total / radius) / 2
        for (group, width) in zip(groups, widths) {
            let angle = start + (width / radius) / 2
            group.position = SIMD3(radius * sin(angle), drop, -radius * cos(angle))
            group.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            if group.parent !== head { head.addChild(group) }
            start += (width + gap) / radius
        }
        if let controls = attachments.entity(for: controlsID) {
            controls.position = SIMD3(0, drop - 0.42, -(radius - 0.15))
            if controls.parent !== head { head.addChild(controls) }
        }
    }

    private func controls(isEmpty: Bool) -> some View {
        VStack(spacing: 14) {
            if isEmpty {
                Text("Nothing Is Open")
                    .font(.title2.weight(.semibold))
                Text("Connect to a machine and its session appears here.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("In a Window", systemImage: "macwindow") { leave(toWindow: true) }
                    .accessibilityIdentifier("all-windows-around-window")
                Button("Done") { leave(toWindow: false) }
                    .accessibilityIdentifier("all-windows-around-done")
            }
            Text("Pinch out with both hands to go back to the window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .glassBackgroundEffect()
    }

    /// Out with both hands: back to the window.
    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.04)
            .onChanged { value in
                if steps.track(value.magnification) == .outward { leave(toWindow: true) }
            }
            .onEnded { _ in steps.reset() }
    }

    /// A card chosen: the room comes back, and its window comes to the person.
    private func go(to session: GlassOpenSession) {
        Task {
            await GlassAllWindowsAround.leave(toWindow: false, openWindow: openWindow, open: openImmersiveSpace,
                                              dismiss: dismissImmersiveSpace)
            session.activate()
        }
    }

    private func leave(toWindow: Bool) {
        Task {
            await GlassAllWindowsAround.leave(toWindow: toWindow, openWindow: openWindow, open: openImmersiveSpace,
                                              dismiss: dismissImmersiveSpace)
        }
    }
}

/// One machine in the arc: its name, and its sessions as the window's cards, on glass of its own.
private struct GlassAllWindowsAroundGroup: View {
    let machine: GlassActiveMachine
    let open: (GlassOpenSession) -> Void
    let close: (GlassOpenSession) -> Void

    static let cardSize = CGSize(width: 340, height: 214)

    var body: some View {
        let columns = max(1, min(3, machine.sessions.count))
        VStack(alignment: .leading, spacing: 16) {
            Label(machine.name, systemImage: "server.rack")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cardSize.width), spacing: 18), count: columns),
                      alignment: .leading, spacing: 18) {
                ForEach(machine.sessions, id: \.id) { session in
                    GlassAllWindowsCard(session: session, activate: { open(session) }, close: { close(session) },
                                        alwaysOnScreen: true)
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                }
            }
        }
        .padding(24)
        // As wide as its cards: an attachment offers any width, and the glass took all of it.
        .fixedSize()
        .glassBackgroundEffect()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(machine.name)
    }
}
#endif
