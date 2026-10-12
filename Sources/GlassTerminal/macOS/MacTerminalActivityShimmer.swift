//
//  MacTerminalActivityShimmer.swift
//  Glass Power Tools — GlassTerminal
//
//  Under a sidebar tab whose terminal is printing. First a wave (2026-10-07: "If the tab has
//  motion, I'd like to see the progress wave under the tab background … left to right? wavy?");
//  then light (2026-10-12: "Let's make this shimmer light magic style instead of a water wave
//  look?", and of the three offered, the light sweep): a soft band of light in the tab's colour
//  glides left to right across the row, like light catching glass, over the faintest tint of the
//  same colour. It exists only while output is arriving, so an idle window draws nothing; with
//  Reduce Motion it is a still tint.
//

import SwiftUI

struct MacTerminalActivityShimmer: View {
    var color: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds from one pass's start to the next: the sweep, then a short rest, so it reads as
    /// light passing rather than a loading bar.
    static let period: Double = 1.6
    /// The part of the period the band is crossing the row.
    static let sweep: Double = 1.2
    /// The band's width, as a share of the row's.
    static let bandShare: Double = 0.45

    var body: some View {
        Group {
            if reduceMotion {
                fade(color.opacity(0.14))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let band = width * Self.bandShare
                        ZStack(alignment: .leading) {
                            Rectangle().fill(color.opacity(0.06))
                            if let center = Self.bandCenter(at: time, width: width, band: band) {
                                Rectangle()
                                    .fill(LinearGradient(stops: [
                                        .init(color: color.opacity(0), location: 0),
                                        .init(color: color.opacity(0.16), location: 0.3),
                                        .init(color: color.mix(with: .white, by: 0.55).opacity(0.42), location: 0.5),
                                        .init(color: color.opacity(0.16), location: 0.7),
                                        .init(color: color.opacity(0), location: 1),
                                    ], startPoint: UnitPoint(x: 0, y: 0.35), endPoint: UnitPoint(x: 1, y: 0.65)))
                                    .frame(width: band)
                                    .offset(x: center - band / 2)
                            }
                        }
                    }
                }
                .mask(fade(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
