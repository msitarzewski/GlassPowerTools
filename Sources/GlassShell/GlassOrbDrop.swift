//
//  GlassOrbDrop.swift
//  Glass Power Tools — GlassShell
//
//  A window going into the orb dock as a drop of water (the owner, 2026-10-25: "We could create a
//  liquid 'Water drop' effect when they go to the dock!"). No window can be carried from one place
//  to another on visionOS, so the drop is told in two halves: the window gathers into a round drop
//  where it is and goes, and its orb lands in the dock as a drop does, stretched as it falls,
//  squashed as it lands, wobbling round again, with a ripple going out from it.
//

#if os(visionOS) || os(macOS)
import SwiftUI

enum GlassOrbDrop {
    /// How long the window takes to gather into its drop and go.
    static let departure: Duration = .milliseconds(520)
    /// When the orb lands in the dock: as the window finishes gathering.
    static let landing: Duration = .milliseconds(300)
}

/// The window's content gathering into a drop: a circle closing in on it from the window's corners
/// while it shrinks, with a spring's wobble, fading as it goes.
struct GlassOrbDropDeparture: ViewModifier {
    let departing: Bool
    /// The drop's diameter in the content's own points, before the content's shrinking.
    private static let drop: CGFloat = 340
    private static let shrunk: CGFloat = 0.33

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { space in
                    let whole = hypot(space.size.width, space.size.height)
                    Circle()
                        .frame(width: departing ? Self.drop : whole, height: departing ? Self.drop : whole)
                        .position(x: space.size.width / 2, y: space.size.height / 2)
                }
                .animation(.spring(duration: 0.42, bounce: 0.3), value: departing)
            }
            .scaleEffect(departing ? Self.shrunk : 1)
            .animation(.spring(duration: 0.48, bounce: 0.38), value: departing)
            .opacity(departing ? 0 : 1)
            .animation(.easeIn(duration: 0.2).delay(0.3), value: departing)
    }
}

/// An orb landing in the dock: falling in, stretched as a drop falls, and round again as it touches down, where its
/// drop takes the landing (`GlassOrbJellyField`): squashed, wobbling round as a drop of jelly does, the wobble going on
/// along the line. Until 2026-11-05 the whole cell squashed and wobbled by keyframes, with a white ring going out from
/// it (the owner: "not cheesy animations"). Played once, as it appears: by a trigger, since `repeating: false` does not
/// play the keyframes once but holds them at their start, which left every orb up in the air and clear (the visionOS
/// simulator, 2026-10-25). Nothing falls with Reduce Motion.
struct GlassOrbDropArrival: ViewModifier {
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the orb touches down in its cell: the bottom of the orb (the ring's layout sets the orb
    /// `GlassOrbMetrics.orbRaise` above the cell's middle).
    private static let contact = UnitPoint(x: 0.5, y: 0.61)

    /// The orb at rest, as it stays once landed; each track starts by jumping to where the fall
    /// begins.
    struct Landing {
        var y: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var opacity: Double = 1
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: Landing(), trigger: landed) { orb, landing in
                orb
                    .scaleEffect(x: landing.scaleX, y: landing.scaleY, anchor: Self.contact)
                    .offset(y: landing.y)
                    .opacity(landing.opacity)
            } keyframes: { _ in
                // The fall ends as the drop's landing begins (`GlassOrbJelly.landingDelay`).
                let fall = GlassOrbJelly.landingDelay
                KeyframeTrack(\.y) {
                    MoveKeyframe(-GlassOrbMetrics.fall)
                    CubicKeyframe(0, duration: fall)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.12)
                }
                KeyframeTrack(\.scaleY) {
                    MoveKeyframe(1.12)
                    LinearKeyframe(1.12, duration: fall - 0.05)
                    CubicKeyframe(1, duration: 0.05)
                }
                KeyframeTrack(\.scaleX) {
                    MoveKeyframe(0.9)
                    LinearKeyframe(0.9, duration: fall - 0.05)
                    CubicKeyframe(1, duration: 0.05)
                }
            }
            .onAppear { landed = true }
        }
    }
}
#endif
