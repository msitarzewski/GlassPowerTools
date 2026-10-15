//
//  GlassSessionOrb.swift
//  Glass Power Tools — GlassShell
//
//  A session window shrunk into an orb, on Vision Pro (the owner, 2026-10-15: "I'd also like a
//  persistent system level session/service icon that shrinks a window into a small preview. When
//  activity is enabled, the preview/orb should pulse"). His choices: an orb whose face is a tiny
//  live picture of the session ("with a live view of the activity"); the pulse switched by the
//  window's Auto-focus on activity; the control first in the bottom bar; every kind of session
//  window — terminal, desktop, database, editor.
//
//  As the Connections window becomes its own orb (W39, `glassConnectionsIdleShrink`): no second
//  window. The session window keeps its content, out of sight and out of reach, laid out at the
//  size it had, and asks visionOS for the orb's size; a pinch on the orb grows it back. Its
//  ornaments go with it.
//

#if os(visionOS)
import SwiftUI
import UIKit
import GlassConnectionUI

/// What a session window shows as its orb.
public struct GlassSessionOrbFace {
    /// The window's name, shown beneath the orb while it is looked at.
    public var title: String
    /// The kind's symbol, where there is no picture.
    public var symbolName: String
    /// The session's picture now, taken again every second while the orb is on screen.
    public var picture: @MainActor () -> Image?
    /// Pulsing: activity in the session, where the window's Auto-focus on activity is on.
    public var pulses: Bool

    public init(title: String, symbolName: String, pulses: Bool = false,
                picture: @escaping @MainActor () -> Image?) {
        self.title = title
        self.symbolName = symbolName
        self.pulses = pulses
        self.picture = picture
    }
}

/// The window's orb as its bar sees it: how to become one, and whether it is one.
public struct GlassSessionOrbControl {
    public let shrink: @MainActor () -> Void
    public let isOrb: Bool
}

public extension EnvironmentValues {
    /// Set by `glassSessionOrb` for everything in the window; nil in a window that has no orb.
    @Entry var glassSessionOrb: GlassSessionOrbControl? = nil
}

public extension View {
    /// Lets this session window become its orb. Attach to the window's whole content: what it wraps
    /// is what goes out of sight while the window is its orb. The window's bar shows
    /// `GlassSessionOrbButton` first.
    func glassSessionOrb(_ face: GlassSessionOrbFace) -> some View {
        modifier(GlassSessionOrbModifier(face: face))
    }
}

/// "Shrink to Orb", first in a session window's bottom bar; nothing in a window without an orb.
public struct GlassSessionOrbButton: View {
    @Environment(\.glassSessionOrb) private var orb

    public init() {}

    public var body: some View {
        if let orb, !orb.isOrb {
            Button("Shrink to Orb", systemImage: "arrow.down.right.and.arrow.up.left") { orb.shrink() }
                .help("Shrink this window to an orb. Pinch the orb to bring it back.")
                .accessibilityIdentifier("session-orb-shrink")
        }
    }
}

private struct GlassSessionOrbModifier: ViewModifier {
    let face: GlassSessionOrbFace
    /// The window's size while it is its orb, to grow back to; nil while it is the window.
    @State private var keptSize: CGSize?
    @State private var sizer = GlassWindowSizer()

    func body(content: Content) -> some View {
        let isOrb = keptSize != nil
        GlassConnectionsWindowLayout(library: keptSize) {
            content
                // First in the window's bottom bar, in every kind of session window.
                .toolbar {
                    ToolbarItem(placement: .bottomOrnament) { GlassSessionOrbButton() }
                }
                .environment(\.glassSessionOrb, GlassSessionOrbControl(shrink: shrink, isOrb: isOrb))
                .environment(\.glassWindowOutOfSight, isOrb)
                // Its ornaments go with it, as the library's do (`VisionTabOutOfSight`).
                .toolbarVisibility(isOrb ? .hidden : .automatic, for: .bottomOrnament, .tabBar)
                .animation(.easeInOut(duration: 0.2)) { $0.opacity(isOrb ? 0 : 1) }
                .allowsHitTesting(!isOrb)
                .accessibilityHidden(isOrb)
            if isOrb {
                GlassSessionOrbView(face: face, grow: grow)
            }
        }
        .background { GlassWindowSizerView(sizer: sizer).accessibilityHidden(true) }
    }

    private func shrink() {
        guard keptSize == nil else { return }
        keptSize = GlassConnectionsWindowSize.returning(to: sizer.windowSize)
        sizer.resize(to: GlassConnectionsWindowSize.orb, event: "session-orb", freeform: true)
    }

    private func grow() {
        guard let size = keptSize else { return }
        keptSize = nil
        sizer.resize(to: size, event: "session-window")
    }
}

/// The orb: the session's live picture in a glass circle, pulsing while its session is busy and
/// the window asked for it; the window's name beneath it while it is looked at.
private struct GlassSessionOrbView: View {
    let face: GlassSessionOrbFace
    let grow: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button(action: grow) {
            VStack(spacing: 10) {
                TimelineView(.animation(minimumInterval: 1, paused: scenePhase != .active)) { _ in
                    ZStack {
                        if let picture = face.picture() {
                            picture.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: face.symbolName)
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: GlassConnectionsOrb.diameter, height: GlassConnectionsOrb.diameter)
                .clipShape(.circle)
                .glassBackgroundEffect(in: .circle)
                .overlay { if face.pulses { GlassSessionOrbPulse() } }
                .contentShape(.hoverEffect, .circle)
                .hoverEffect(.highlight)
                .hoverEffect(GlassOrbGrowEffect())
                Text(face.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassBackgroundEffect(in: .capsule)
                    .hoverEffect(GlassOrbRevealEffect())
            }
            .hoverEffectGroup()
        }
        .buttonStyle(GlassOrbButtonStyle())
        .accessibilityActivationPoint(.center)
        .accessibilityLabel(face.title)
        .accessibilityHint("Brings the window back")
        .accessibilityIdentifier("session-orb")
    }
}

/// A ring going out from the orb's rim, again and again, while its session is busy.
private struct GlassSessionOrbPulse: View {
    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.75), lineWidth: 3)
            .phaseAnimator([0.0, 1.0]) { ring, phase in
                ring.scaleEffect(1 + 0.22 * phase).opacity(1 - phase)
            } animation: { phase in
                phase == 1 ? .easeOut(duration: 1.3) : .linear(duration: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
