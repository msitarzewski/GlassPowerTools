//
//  MacTerminalActivityShimmer.swift
//  Glass Power Tools — GlassTerminal
//
//  Under a sidebar tab whose terminal is printing. First a wave (2026-10-07: "If the tab has
//  motion, I'd like to see the progress wave under the tab background … left to right? wavy?");
//  then light (2026-10-12: "Let's make this shimmer light magic style instead of a water wave
//  look?", and of the three offered, the light sweep): a soft band of light in the tab's colour
//  glides left to right across the row, like light catching glass, over the faintest tint of the
//  same colour. Then softer, narrower and a little slower ("slow to a glisten, lighten it up",
//  lighter meaning subtler): a glint rather than a wash. Then a cloud ("more cloud like and less
//  clipped top and bottom"): two soft elliptical puffs that fade to nothing on every side, never
//  cut by the row's edges, over a tint that fades out above and below as well. It exists only
//  while output is arriving, so an idle window draws nothing; with Reduce Motion it is a still
//  tint.
//

import SwiftUI

struct MacTerminalActivityShimmer: View {
    var color: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds from one pass's start to the next: the sweep, then a short rest, so it reads as
    /// light passing rather than a loading bar.
    static let period: Double = 2.4
    /// The part of the period the band is crossing the row.
    static let sweep: Double = 1.8
    /// The band's width, as a share of the row's.
    static let bandShare: Double = 0.32

    var body: some View {
        Group {
            if reduceMotion {
                fade(color.opacity(0.14))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    GeometryReader { geometry in
                        let width = geometry.size.width, height = geometry.size.height
                        let band = width * Self.bandShare
                        ZStack {
                            Rectangle().fill(color.opacity(0.035))
                            if let center = Self.bandCenter(at: time, width: width, band: band) {
                                cloud(band: band, height: height)
                                    .position(x: center, y: height / 2)
                            }
                        }
                    }
                }
                .mask(fade(.white))
                .mask(verticalFade)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The light: a puff, brightest at its heart and gone at its edges, with a smaller, fainter
    /// one trailing a little below it, the two blurred together. Inside the row's height, so
    /// nothing is cut flat at the top or bottom.
    private func cloud(band: Double, height: Double) -> some View {
        ZStack {
            puff(core: color.mix(with: .white, by: 0.6).opacity(0.26), edge: color.opacity(0.08))
                .frame(width: band, height: height * 0.86)
            puff(core: color.mix(with: .white, by: 0.4).opacity(0.14), edge: color.opacity(0.04))
                .frame(width: band * 0.62, height: height * 0.62)
                .offset(x: -band * 0.24, y: height * 0.1)
        }
        .blur(radius: height * 0.1)
        .frame(width: band, height: height)
    }

    private func puff(core: Color, edge: Color) -> some View {
        Rectangle().fill(EllipticalGradient(stops: [
            .init(color: core, location: 0),
            .init(color: edge, location: 0.55),
            .init(color: edge.opacity(0), location: 1),
        ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
    }

    /// Soft above and below, as the ends are at the sides.
    private var verticalFade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.25),
                               .init(color: .white, location: 0.75), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Where the band's centre is at `time`, in points from the row's leading edge: from wholly
    /// before the row to wholly past it over `sweep` seconds of each `period`; nil while resting.
    static func bandCenter(at time: Double, width: Double, band: Double) -> Double? {
        let position = time.truncatingRemainder(dividingBy: period)
        guard position < sweep else { return nil }
        let progress = position / sweep
        // Eased, so the light gathers speed and settles rather than ticking along.
        let eased = progress * progress * (3 - 2 * progress)
        return -band / 2 + eased * (width + band)
    }

    private func fade(_ style: some ShapeStyle) -> some View {
        Rectangle().fill(style).mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.12),
                                   .init(color: .white, location: 0.88), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing))
    }
}
