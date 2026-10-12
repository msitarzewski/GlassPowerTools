//
//  MacTerminalActivityWave.swift
//  Glass Power Tools — GlassTerminal
//
//  Under a sidebar tab whose terminal is printing (2026-10-07: "If the tab has motion, I'd like to
//  see the progress wave under the tab background … left to right? wavy?"). A soft band of the
//  tab's colour, its top edge a slow wave travelling left to right, faded at both ends so it reads
//  as movement rather than as a bar. It exists only while output is arriving, so an idle window
//  draws nothing; with Reduce Motion it is a still tint.
//

import SwiftUI

struct MacTerminalActivityWave: View {
    var color: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per second the wave travels, and its length and height.
    private static let speed: Double = 48
    private static let wavelength: Double = 56
    private static let amplitude: Double = 2.5

    var body: some View {
        Group {
            if reduceMotion {
                fade(color.opacity(0.14))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate * Self.speed
                    Canvas { canvas, size in
                        canvas.fill(Self.wave(in: size, phase: phase), with: .color(color.opacity(0.22)))
                    }
                }
                .mask(fade(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The band: the lower part of the row under a sine wave whose crests move rightwards.
    static func wave(in size: CGSize, phase: Double) -> Path {
        let crest = size.height * 0.55
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x = 0.0
        while x <= size.width {
            let y = crest + sin((x - phase) / wavelength * 2 * .pi) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func fade(_ style: some ShapeStyle) -> some View {
        Rectangle().fill(style).mask(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.2),
                                   .init(color: .white, location: 0.8), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing))
    }
}
