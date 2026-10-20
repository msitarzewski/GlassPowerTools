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
        if style.drawsBackdrop {
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
        case .rain, .synthwave:
            TimelineView(.animation(minimumInterval: appearsActive ? 1.0 / 30 : 1.0 / 8, paused: isStill)) { context in
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
        }
    }

    private func shader(time: Double, size: CGSize) -> Shader {
        switch style.backdrop {
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
            .blur(radius: style.blur * 30 * scale, opaque: true)
            .layerEffect(Self.library.glassPixelate(.float(block)), maxSampleOffset: CGSize(width: block, height: block),
                         isEnabled: style.pixelate > 0)
            .colorEffect(Self.library.glassDuotone(.color(theme.canvasBackgroundColor.color), .color(glowColor.color),
                                                   .float(style.tone)),
                         isEnabled: style.tone > 0)
            .opacity(style.intensity)
    }

    // MARK: - Motion

    /// Still: under Reduce Motion, in Low Power Mode, or with the scene in the background.
    private var isStill: Bool { still || reduceMotion || lowPower || scenePhase == .background }

    /// Rows a second the rain falls at: quicker while the terminal prints, when the window asks.
    private var speed: Double {
        guard style.followsOutput, let activity, activity.isActive else { return 1 }
        return 3.5
    }

    // MARK: - Colours and readability

    private var textColor: CodableColor { style.phosphor.textColor(theme: theme) }

    private var glowColor: CodableColor { style.glowColor.color(text: textColor) }

    /// How bright what is behind the text is, before the scrim.
    private var backdropBrightness: Double {
        switch style.backdrop {
        case .none: 0
        case .picture: (picture?.brightness ?? 0) * style.intensity
        case .rain: 0.12 * style.intensity
        // Mostly dark sky and floor: the sun is bright, but small.
        case .synthwave: 0.12 * style.intensity
        case .phosphor: 0.04 * style.intensity
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
    private var speed = 1.0

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
    /// `scale`: a picture of the terminal drawn smaller, whose glow shrinks with it.
    @ViewBuilder
    func terminalTextLook(_ style: TerminalLookStyle, theme: TerminalTheme, scale: CGFloat = 1) -> some View {
        let text = style.phosphor.textColor(theme: theme)
        let strength = style.glow
        let glow = style.glowColor.color(text: text)
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
