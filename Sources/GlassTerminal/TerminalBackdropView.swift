//
//  TerminalBackdropView.swift
//  Glass Power Tools — GlassTerminal
//
//  What a terminal window shows behind its text (D84), drawn between the window's canvas (its glass,
//  theme colour and tint) and the terminal, which is transparent. Every tab and pane in the window
//  draws the window's look. The text's glow is here too (`terminalGlow`).
//
//  Text first: a scrim in the theme's background colour sits over the backdrop, as dark as the
//  window's Readability asks and darker where the text would fall below 4.5:1 against it.
//  Motion: the animated backdrops stop under Reduce Motion, in Low Power Mode and while the window's
//  scene is in the background; an unfocused window's slows to a few frames a second.
//

import SwiftUI
import GlassTerminalEmulator

struct TerminalBackdropView: View {
    let style: TerminalLookStyle
    /// The window's theme, in its phosphor palette.
    let theme: TerminalTheme
    /// The terminal's output, which quickens the rain while it arrives; nil where none is followed.
    var activity: SwiftTermOutputActivity?
    /// The coding agent the terminal runs, for the Coding Agent look and its colour; nil for none.
    /// As its window knew it when it last drew, and asked again here (`findAgent`) whenever the
    /// terminal starts or stops printing: a title, which names Claude Code outside tmux, redraws
    /// nothing by itself, and a backdrop that found no agent read nothing that would draw it
    /// again (2026-10-21: the first pictures had no mark).
    var agent: TerminalAgent? = nil
    var findAgent: (() -> TerminalAgent?)? = nil
    /// Drawn smaller than the terminal, as a preview is: what is measured in points scales by this.
    var scale: CGFloat = 1
    /// A picture of the terminal (Show All Windows, the overview): never animated.
    var still = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appearsActive) private var appearsActive
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var clock = TerminalBackdropClock()
    @State private var picture: TerminalBackdropPicture?

    var body: some View {
        // Read first, so this is drawn again as output starts and stops, whatever it draws.
        let _ = activity?.isActive
        if style.drawsBackdrop(agent: shownAgent) {
            GeometryReader { geometry in
                ZStack {
                    // Its bright parts no brighter than the text can be read over, dim text too.
                    backdrop(size: geometry.size)
                        .colorEffect(Self.library.glassCeiling(.float(ceiling ?? 1)), isEnabled: ceiling != nil)
                    Rectangle()
                        .fill(theme.canvasBackgroundColor.color)
                        .opacity(scrimOpacity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .task(id: style.backdrop == .picture ? style.picture : nil) {
                guard style.backdrop == .picture, let name = style.picture else { picture = nil; return }
                picture = await TerminalBackdropPicture.load(name)
            }
        }
    }

    // MARK: - Backdrops

    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        switch style.backdrop {
        case .none:
            EmptyView()
        case .picture:
            if let picture {
                pictureBackdrop(picture.image, size: size)
            }
        case .agent:
            if let agent = shownAgent {
                TerminalAgentBackdrop(agent: agent, color: (agent.accent ?? textColor).color,
                                      working: activity?.isActive == true, still: isStill,
                                      frameInterval: frameInterval, intensity: style.intensity, scale: scale)
            }
        case .rain, .synthwave, .aurora, .starfield:
            TimelineView(.animation(minimumInterval: frameInterval, paused: isStill)) { context in
                let time = clock.time(at: context.date, speed: speed)
                Rectangle()
                    .fill(.black)
                    .colorEffect(shader(time: time, size: size))
            }
        case .phosphor:
            Rectangle()
                .fill(.black)
                .colorEffect(Self.library.glassPhosphorScreen(
                    .float2(size), .color(textColor.color), .float(max(1, 3 * scale)), .float(style.intensity)))
        case .blueprint:
            Rectangle()
                .fill(.black)
                .colorEffect(Self.library.glassBlueprint(
                    .float2(size), .float(12 * scale), .color(Self.blueprintPaper.color), .color(Self.blueprintInk),
                    .float(style.intensity)))
        }
    }

    /// The drafting sheet's paper, deep blue, and its lines.
    static let blueprintPaper = CodableColor(sRGBRed: 0.05, green: 0.19, blue: 0.43)
    private static let blueprintInk = Color(red: 0.62, green: 0.80, blue: 1)

    /// Thirty frames a second, or a few in a window not in front.
    private var frameInterval: Double { appearsActive ? 1.0 / 30 : 1.0 / 8 }

    private func shader(time: Double, size: CGSize) -> Shader {
        switch style.backdrop {
        case .aurora:
            Self.library.glassAurora(
                .float2(size), .float(time), .color(Color(red: 0.16, green: 1, blue: 0.58)),
                .color(Color(red: 0.58, green: 0.32, blue: 1)), .float(style.intensity))
        case .starfield:
            // Streaks as the clock runs faster than its resting speed: as much as the terminal prints.
            Self.library.glassStarfield(
                .float2(size), .float(time), .float(min(1, max(0, (clock.speed - 1) / (Self.quickSpeed - 1)))),
                .color(textColor.color), .float(style.intensity))
        case .synthwave:
            Self.library.glassSynthwave(
                .float2(size), .float(time),
                .color(Color(red: 0.10, green: 0.02, blue: 0.22)), .color(Color(red: 0.62, green: 0.16, blue: 0.47)),
                .color(Color(red: 1, green: 0.90, blue: 0.43)), .color(Color(red: 1, green: 0.24, blue: 0.67)),
                .color(Color(red: 0, green: 0.94, blue: 1)), .float(style.intensity))
        default:
            Self.library.glassRain(
                .float2(size), .float(time), .float(max(10, Double(theme.fontSize)) * scale), .float(1),
                .color(glowColor.color), .float(style.intensity))
        }
    }

    private func pictureBackdrop(_ image: CGImage, size: CGSize) -> some View {
        let block = max(1, (2 + style.pixelate * 30) * scale)
        return Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .blur(radius: Self.pictureBlurRadius(style.blur) * scale, opaque: true)
            .layerEffect(Self.library.glassPixelate(.float(block)), maxSampleOffset: CGSize(width: block, height: block),
                         isEnabled: style.pixelate > 0)
            .colorEffect(Self.library.glassDuotone(.color(theme.canvasBackgroundColor.color), .color(glowColor.color),
                                                   .float(style.tone)),
                         isEnabled: style.tone > 0)
            .opacity(style.intensity)
    }

    /// The picture's blur in points for Blur's 0…1: slow at first, to 30 at Soft. It was 30 times
    /// Blur, which smeared a picture past knowing at a tenth and left the rest of the slider doing
    /// nothing (the owner, 2026-10-21: "It doesn't blur so much as well... i dunno"). Cubed, a
    /// quarter softens, half blurs and still shows the picture, and the end is as soft as before.
    static func pictureBlurRadius(_ blur: Double) -> Double {
        30 * pow(min(1, max(0, blur)), 3)
    }

    // MARK: - Motion

    /// Still: under Reduce Motion, in Low Power Mode, or with the scene in the background.
    private var isStill: Bool { still || reduceMotion || lowPower || scenePhase == .background }

    /// How fast the backdrop's time runs: quicker while the terminal prints, when the window asks.
    /// For the rain, rows a second.
    private var speed: Double {
        guard style.backdrop.quickensWithOutput, style.followsOutput, let activity, activity.isActive else { return 1 }
        return Self.quickSpeed
    }

    static let quickSpeed = 3.5

    // MARK: - Colours and readability

    private var textColor: CodableColor { style.phosphor.textColor(theme: theme) }

    /// The agent the look shows, asked again now.
    private var shownAgent: TerminalAgent? {
        guard style.usesAgent else { return nil }
        return findAgent?() ?? agent
    }

    private var glowColor: CodableColor { style.glowColor.color(text: textColor, agent: shownAgent) }

    /// How bright what is behind the text is, before the scrim.
    private var backdropBrightness: Double {
        switch style.backdrop {
        case .none: 0
        case .picture: (picture?.brightness ?? 0) * style.intensity
        // A smoke of the agent's colour, never more than about half covering.
        case .agent: TerminalReadability.luminance(shownAgent?.accent ?? textColor) * 0.35 * style.intensity
        case .rain: 0.12 * style.intensity
        // Mostly dark sky and floor: the sun is bright, but small.
        case .synthwave: 0.12 * style.intensity
        // Bright curtains, but over a small part, with the glass between.
        case .aurora: 0.12 * style.intensity
        case .starfield: 0.03 * style.intensity
        case .phosphor: 0.04 * style.intensity
        case .blueprint: TerminalReadability.luminance(Self.blueprintPaper) * 1.2 * style.intensity
        }
    }

    /// Under light text, the brightest the backdrop may be: what is brighter is darkened to it,
    /// pixel by pixel, so a bright patch is tamed where it is rather than dimming everything.
    private var ceiling: Double? {
        TerminalReadability.ceiling(
            text: TerminalReadability.luminance(textColor),
            dim: TerminalReadability.dimLuminance(of: textColor),
            scrim: TerminalReadability.luminance(theme.canvasBackgroundColor),
            opacity: style.readability)
    }

    /// The window's Readability; under dark text, raised over the whole backdrop as its bright
    /// parts need, since no ceiling helps there.
    private var scrimOpacity: Double {
        guard ceiling == nil else { return style.readability }
        return TerminalReadability.scrimOpacity(
            background: backdropBrightness,
            text: TerminalReadability.luminance(textColor),
            scrim: TerminalReadability.luminance(theme.canvasBackgroundColor),
            minimum: style.readability)
    }

    private static let library = ShaderLibrary.bundle(shaderBundle)
    /// Where the shaders are compiled to (`Resources/TerminalBackdrops.metal`).
    static var shaderBundle: Bundle { .module }
}

/// A picture, decoded off the main thread, with how bright its brighter parts are.
struct TerminalBackdropPicture: Sendable {
    let image: CGImage
    let brightness: Double

    static func load(_ name: String) async -> TerminalBackdropPicture? {
        await Task.detached(priority: .userInitiated) {
            guard let image = TerminalBackgroundPictures.image(named: name) else { return nil }
            return TerminalBackdropPicture(image: image, brightness: TerminalBackgroundPictures.brightness(of: image))
        }.value
    }
}

/// The backdrop's own time, which runs at the rain's speed: changing speed eases into the new one
/// rather than jumping the rain to where the new speed would have put it.
@MainActor
final class TerminalBackdropClock {
    private var last: Date?
    private var elapsed = 0.0
    /// Where the speed has eased to.
    private(set) var speed = 1.0

    func time(at date: Date, speed target: Double) -> Double {
        if let last {
            // A long gap (paused, asleep) doesn't fast-forward.
            let step = min(0.25, max(0, date.timeIntervalSince(last)))
            speed += (target - speed) * min(1, step * 2.5)
            elapsed += step * speed
        }
        last = date
        return elapsed
    }
}

// MARK: - The text's phosphor and glow

extension View {
    /// The text's look (D84): a monochrome phosphor's colour over everything drawn — the colour
    /// filters Core Animation applies to the terminal's own layer, which a SwiftUI shader can't
    /// reach — then a glow around it: a shadow in the glow's colour, which follows the glyphs,
    /// since the terminal's own background is clear.
    ///
    /// The filters are there only while a phosphor is: an identity filter could still cost every
    /// terminal an offscreen pass. Choosing or clearing a phosphor rebuilds the terminal's view
    /// once, as moving a tab between windows does; the glow is always applied, clear when off.
    ///
    /// `agent`: the coding agent the terminal runs, whose colour a glow can take.
    /// `scale`: a picture of the terminal drawn smaller, whose glow shrinks with it.
    @ViewBuilder
    func terminalTextLook(_ style: TerminalLookStyle, theme: TerminalTheme, agent: TerminalAgent? = nil,
                          scale: CGFloat = 1) -> some View {
        let text = style.phosphor.textColor(theme: theme)
        let strength = style.glow
        let glow = style.glowColor.color(text: text, agent: agent)
        let shadowColor = strength > 0 ? glow.color.opacity(0.45 + 0.5 * strength) : Color.clear
        let shadowRadius = strength > 0 ? (1.5 + 7 * strength) * scale : 0
        if style.phosphor.isMonochrome {
            saturation(TerminalPhosphor.keptHue)
                .colorMultiply(text.color)
                .shadow(color: shadowColor, radius: shadowRadius)
        } else {
            shadow(color: shadowColor, radius: shadowRadius)
        }
    }
}

// MARK: - The coding agent

/// The Coding Agent look (D84): the agent's mark, large and faint in the middle, and a smoke of its
/// colour. While the agent works — the terminal printing — the smoke drifts and the mark breathes
/// and ripples, as AutoPaper's picture does while it paints a new one (the owner's project,
/// 2026-10-21). When it stops, waiting for you, the smoke thins and stops, and the mark holds still
/// and glows: the terminal that wants you is the one that has gone quiet and bright.
struct TerminalAgentBackdrop: View {
    let agent: TerminalAgent
    let color: Color
    let working: Bool
    /// No motion: Reduce Motion, Low Power Mode, a hidden scene, or a picture.
    let still: Bool
    let frameInterval: Double
    let intensity: Double
    var scale: CGFloat = 1

    @State private var clock = TerminalBackdropClock()

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) * 0.42
            // Nothing moves while the agent waits, so nothing is drawn again until it works.
            TimelineView(.animation(minimumInterval: frameInterval, paused: still || !working)) { context in
                let time = clock.time(at: context.date, speed: 1)
                ZStack {
                    smoke(time: time)
                    mark(side: side, time: time)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: working)
    }

    // MARK: Smoke

    /// Drifting light in the agent's colour: a 3 × 3 mesh whose inner points wander, blurred
    /// (AutoPaper's `Smoke`).
    private func smoke(time: Double) -> some View {
        MeshGradient(width: 3, height: 3, points: Self.points(at: time),
                     colors: Self.shades.map { color.opacity($0) })
            .blur(radius: 28 * scale)
            .opacity((working ? 0.85 : 0.3) * intensity)
    }

    /// How much of the colour each of the mesh's nine points has: the middle the most.
    private static let shades: [Double] = [0.35, 0.7, 0.3, 0.6, 1, 0.55, 0.25, 0.65, 0.4]

    /// Corners and edges stay put; the centre and the edges' midpoints drift on their own circles.
    static func points(at time: Double) -> [SIMD2<Float>] {
        func drift(_ x: Float, _ y: Float, _ phase: Double, _ reach: Float) -> SIMD2<Float> {
            SIMD2(x + reach * Float(sin(time * 0.45 + phase)), y + reach * Float(cos(time * 0.38 + phase * 1.3)))
        }
        return [
            [0, 0], drift(0.5, 0, 0.0, 0.18) * [1, 0], [1, 0],
            drift(0, 0.5, 1.1, 0.18) * [0, 1], drift(0.5, 0.5, 2.3, 0.24), drift(1, 0.5, 3.7, 0.18) * [0, 1] + [1, 0],
            [0, 1], drift(0.5, 1, 4.9, 0.18) * [1, 0] + [0, 1], [1, 1],
        ]
    }

    // MARK: The mark

    private func mark(side: CGFloat, time: Double) -> some View {
        let moving = working && !still
        // Breathing while it works; steady, and brighter, while it waits. Strong enough to reach
        // the readability ceiling, which holds it under the text: fainter, and the ceiling and the
        // scrim together left nothing to see (2026-10-21, the first pictures).
        let breath = moving ? 0.5 + 0.5 * sin(time * 2) : 0
        let opacity = (working ? 0.35 + 0.15 * breath : 0.7) * intensity
        return agent.markImage
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .foregroundStyle(color)
            .distortionEffect(Self.library.glassWorkingRipple(.float(time), .float2(CGSize(width: side, height: side)),
                                                              .float(2.5 * scale)),
                              maxSampleOffset: CGSize(width: 4 * scale, height: 4 * scale), isEnabled: moving)
            .opacity(opacity)
            .shadow(color: color.opacity(working ? 0.3 : 0.8 * intensity), radius: (working ? 10 : 26) * scale)
            .accessibilityHidden(true)
    }

    private static let library = ShaderLibrary.bundle(TerminalBackdropView.shaderBundle)
}
