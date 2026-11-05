//
//  GlassOrbLiquid.swift
//  Glass Power Tools — GlassShell
//
//  The orbs drawn as liquid (`GlassOrbJelly.swift` says why and how they move): each orb's rim is a drop's, the shape
//  Apple's glass takes, so the glass itself wobbles and goes on bending what lies behind it; the picture inside is
//  stretched with the rim and rippled by a Metal shader (`Resources/GlassOrbLiquid.metal`). Nothing is drawn again
//  while nothing moves. With Reduce Motion or Low Power Mode, the orbs stay round and a busy one glows instead.
//

#if os(visionOS) || os(macOS)
import SwiftUI

/// A drop's rim as a shape: round, or wobbling as `drop` says, about the middle of the rect. `radius` sets the round
/// drop's own, so a drop may bulge past a rect only as big as the round one.
struct GlassDropletShape: InsettableShape {
    var drop: GlassDropletDeformation
    var radius: CGFloat?
    var inset: CGFloat = 0

    /// Points around the rim: enough that a five-lobed wobble stays smooth at an orb's size.
    static let steps = 96

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let round = (radius ?? min(rect.width, rect.height) / 2) - inset
        guard round > 0 else { return Path() }
        guard !drop.isRound else {
            return Path(ellipseIn: CGRect(x: center.x - round, y: center.y - round, width: 2 * round, height: 2 * round))
        }
        let points = (0..<Self.steps).map { step -> CGPoint in
            let angle = 2 * Double.pi * Double(step) / Double(Self.steps)
            let reach = round * drop.radius(at: angle)
            return CGPoint(x: center.x + reach * cos(angle), y: center.y + reach * sin(angle))
        }
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        path.move(to: middle(points[points.count - 1], points[0]))
        for index in points.indices {
            path.addQuadCurve(to: middle(points[index], points[(index + 1) % points.count]), control: points[index])
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> GlassDropletShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// How the dock's orbs move about as the line changes.
enum GlassOrbJellyMotion {
    /// The orbs sliding over to make room or close a gap: quick, overshooting a little and settling, a snap.
    static let slide = Animation.spring(duration: 0.45, bounce: 0.32)
}

/// What moves an orb's drop now: the pushes it has had, and its session's drops of ripples.
struct GlassOrbLiquidState: Equatable {
    var kicks: [GlassJellyKick] = []
    var pulse = GlassOrbPulseClock()
    /// Reduce Motion or Low Power Mode: round and still.
    var still = false
    /// Something moves: the picture is drawn again with the display until it stops.
    var live = false
    /// The rim moves: a push, or a shiver. Only then are the rim, its light and Apple's glass drawn again with the
    /// display; a busy orb's ripples alone move only the picture.
    var rimLive = false
    /// Which way this orb's shivers go.
    var turn: Double = 0

    func drop(at now: Date) -> GlassDropletDeformation {
        still ? .round : GlassOrbJelly.deformation(at: now, kicks: kicks, rings: pulse.atRim(at: now), turn: turn)
    }
}

extension EnvironmentValues {
    /// The pushes the dock has given the orb drawn here (`GlassOrbJellyField`).
    @Entry var glassOrbKicks: [GlassJellyKick] = []
    /// The orb's drop, for the parts that draw it (`GlassOrbLiquidSource`).
    @Entry var glassOrbLiquid = GlassOrbLiquidState()
}

enum GlassOrbLiquid {
    /// Whether the glass takes the drop's own shape. On the Mac it does. On Vision Pro the system's glass, given any
    /// shape but its own, broke into white shards on the headset after a scroll, every orb, a row or a column (the
    /// owner's picture, 2026-11-05: "It's the same pattern on all previews"; the simulator drew them whole): there the
    /// glass stays the system's circle, the whole orb stretches to the drop's oval (`GlassOrbLiquidSquash`, a
    /// transform, as the landing's squash was on the headset from 0.4.512), and the ripples stay in the picture.
    #if os(macOS)
    static let shapesGlass = true
    #else
    static let shapesGlass = false
    #endif

    /// Room past a round orb's rim for its drop to bulge into, as a share of its diameter.
    static let margin: CGFloat = 0.12
    /// A wobble is three to twelve times a second: sixty frames show it on the Mac, where a display's 120 cost the dock
    /// twice as much for nothing seen (the macOS VM, 2026-11-05); the headset's own 90.
    #if os(macOS)
    static let frameInterval: Double = 1.0 / 60
    #else
    static let frameInterval: Double = 1.0 / 90
    #endif

    static var library: ShaderLibrary { ShaderLibrary.bundle(.module) }

    /// Reduce Motion, or the device saving power: no wobble, no ripples.
    static func isStill(reduceMotion: Bool) -> Bool {
        #if DEBUG
        if demoSolid { return true }
        #endif
        return reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// The shader for a drop of `diameter` centred in a layer `margin` larger all round.
    static func shader(diameter: CGFloat, margin: CGFloat, drop: GlassDropletDeformation, ages: [Double],
                       ripples: Bool) -> Shader {
        func four(_ values: [Double], _ missing: Float) -> SIMD4<Float> {
            SIMD4((0..<4).map { $0 < values.count ? Float(values[$0]) : missing })
        }
        let c = four(drop.cosines, 0), s = four(drop.sines, 0), a = four(ripples ? ages : [], -1)
        return library.glassOrbLiquid(
            .float2(CGPoint(x: diameter / 2 + margin, y: diameter / 2 + margin)),
            .float(diameter / 2),
            .float4(c.x, c.y, c.z, c.w),
            .float4(s.x, s.y, s.z, s.w),
            .float(Float(drop.mean)),
            .float4(a.x, a.y, a.z, a.w),
            .float(Float(GlassOrbRipple.reach)),
            .float(ripples ? 1 : 0))
    }

    #if DEBUG
    /// Measuring what the liquid costs: `--demo-orb-solid` draws the orbs as Reduce Motion does, and nothing else
    /// changes (Reduce Motion itself also stills the agents' marks).
    static let demoSolid = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        && ProcessInfo.processInfo.arguments.contains("--demo-orb-solid")

    /// UI tests and pictures: `--demo-orb-busy` has every session orb's drops falling, as a busy session's do.
    static var demoBusy: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--demo-orb-busy")
    }
    #endif
}

/// Where an orb's drop comes from: the dock's pushes, its own landing when it appears on its own, and its session's
/// drops while it is busy. Wraps the whole orb, so its parts draw the same drop.
struct GlassOrbLiquidSource: ViewModifier {
    var busy = false
    /// Lands as it appears: an orb shrunk from its window where it stands. The dock lands its own (`GlassOrbJellyField`).
    var landsOnAppear = false
    @Environment(\.glassOrbKicks) private var dockKicks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = GlassOrbPulseClock()
    @State private var ownKicks: [GlassJellyKick] = []
    @State private var live = false
    @State private var rimLive = false
    @State private var turn = Double.random(in: 0..<(2 * Double.pi))

    private struct Moving: Equatable {
        var kicks: [GlassJellyKick]
        var pulse: GlassOrbPulseClock
        var still: Bool
    }

    func body(content: Content) -> some View {
        let kicks = dockKicks + ownKicks
        let still = GlassOrbLiquid.isStill(reduceMotion: reduceMotion)
        content
            .environment(\.glassOrbLiquid, GlassOrbLiquidState(kicks: kicks, pulse: pulse, still: still, live: live && !still,
                                                     rimLive: rimLive && !still, turn: turn))
            .onChange(of: busy, initial: true) { _, busy in pulse.busy(busy, at: .now) }
            .onAppear {
                guard landsOnAppear else { return }
                ownKicks = [GlassJellyKick(start: .now.addingTimeInterval(GlassOrbJelly.landingDelay),
                                           size: GlassOrbJelly.landingSize, angle: Double.pi / 2,
                                           shares: GlassOrbJelly.landing)]
            }
            // Follows the display while anything moves, the rim only while it moves, and stops when the last of it has
            // died away.
            .task(id: Moving(kicks: kicks, pulse: pulse, still: still)) {
                while !Task.isCancelled {
                    let now = Date.now
                    let pushed = kicks.contains { $0.end > now }
                    live = !still && (pushed || pulse.isLive(at: now))
                    rimLive = !still && (pushed || (GlassOrbLiquid.shapesGlass && pulse.rimMoves(at: now)))
                    guard live else { return }
                    // The next time either changes: a push dying away, a shiver starting or ending, the last ring.
                    let shiver = GlassOrbLiquid.shapesGlass ? pulse.nextRimChange(after: now) : nil
                    let next = (kicks.map(\.end) + [shiver, pulse.quietAt].compactMap { $0 })
                        .filter { $0 > now }.min()
                    guard let next else { return }
                    try? await Task.sleep(for: .seconds(next.timeIntervalSince(now) + 0.01))
                }
            }
    }
}

/// The picture inside an orb, `diameter` across in the middle of this view, stretched with its drop and rippled while
/// its session is busy. The view laid out at `diameter`; it draws a little past it as the drop bulges.
struct GlassOrbLiquidWarp: ViewModifier {
    let diameter: CGFloat
    var ripples = true
    @Environment(\.glassOrbLiquid) private var liquid

    func body(content: Content) -> some View {
        let margin = (diameter * GlassOrbLiquid.margin).rounded(.up)
        TimelineView(.animation(minimumInterval: GlassOrbLiquid.frameInterval, paused: !liquid.live)) { context in
            // Where the glass keeps its circle, the picture does too: the whole orb stretches instead.
            let drop = GlassOrbLiquid.shapesGlass ? liquid.drop(at: context.date) : .round
            let ages = ripples && !liquid.still ? liquid.pulse.ages(at: context.date) : []
            content
                .padding(margin)
                .layerEffect(GlassOrbLiquid.shader(diameter: diameter, margin: margin, drop: drop, ages: ages,
                                                   ripples: !ages.isEmpty),
                             maxSampleOffset: CGSize(width: margin * 2, height: margin * 2),
                             isEnabled: !drop.isRound || !ages.isEmpty)
                .padding(-margin)
        }
    }
}

/// A drop's oval (its mode 2, the most of any push) as a stretch of the whole view: the system's own round glass, scaled,
/// for the Connections orb on Vision Pro. There its glass in a drop's shape broke into white shards on the headset,
/// after a scroll of a vertical dock (the owner's picture, 2026-11-05; the simulator drew it whole), likely as it is a
/// menu's label; a session orb's, a button's, drew whole beside it.
struct GlassOrbLiquidSquash: ViewModifier {
    @Environment(\.glassOrbLiquid) private var liquid

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: GlassOrbLiquid.frameInterval, paused: !liquid.rimLive)) { context in
            let oval = GlassOrbLiquid.oval(of: liquid.drop(at: context.date))
            content
                .rotationEffect(.radians(-oval.angle))
                .scaleEffect(x: 1 + oval.stretch, y: 1 - oval.stretch)
                .rotationEffect(.radians(oval.angle))
        }
    }
}

extension GlassOrbLiquid {
    /// A drop's oval: how far it stretches, and along which way (the rim at its farthest).
    static func oval(of drop: GlassDropletDeformation) -> (stretch: Double, angle: Double) {
        let c = drop.cosines[0], s = drop.sines[0]
        return ((c * c + s * s).squareRoot(), atan2(s, c) / 2)
    }
}

/// An orb's rim: its picture cut to its drop, and Apple's glass in the drop's shape around it, wobbling with it.
/// `diameter` is the glass's, `inner` the picture's within it (the Mac's orb has a rim of glass around its picture;
/// Vision Pro's glass lies behind it). `shading` lights the picture as a sphere is lit.
struct GlassOrbLiquidRim: ViewModifier {
    let diameter: CGFloat
    var inner: CGFloat? = nil
    var shading = true
    /// Cut to the drop: the picture inside. Connections' icon stands inside its glass uncut.
    var clips = true
    #if os(macOS)
    var glass: Glass = .regular
    #endif
    @Environment(\.glassOrbLiquid) private var liquid

    func body(content: Content) -> some View {
        #if os(macOS)
        let margin = (diameter * GlassOrbLiquid.margin).rounded(.up)
        let inner = inner ?? diameter
        TimelineView(.animation(minimumInterval: GlassOrbLiquid.frameInterval, paused: !liquid.rimLive)) { context in
            let drop = liquid.drop(at: context.date)
            let picture = GlassDropletShape(drop: drop, radius: inner / 2)
            let rim = GlassDropletShape(drop: drop, radius: diameter / 2)
            content
                .overlay { if shading { GlassOrbSphereShading(diameter: inner, drop: drop) } }
                .padding(margin)
                .clipShape(clips ? AnyShape(picture) : AnyShape(Rectangle()))
                .glassEffect(glass, in: rim)
                .padding(-margin)
        }
        #else
        // The system's own circle of glass, the whole orb stretched to the drop's oval (`GlassOrbLiquid.shapesGlass`).
        content
            .overlay { if shading { GlassOrbSphereShading(diameter: inner ?? diameter) } }
            .clipShape(.circle)
            .glassBackgroundEffect(in: .circle)
            .modifier(GlassOrbLiquidSquash())
        #endif
    }
}
#endif
