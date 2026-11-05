//
//  GlassBell.swift
//  Glass Power Tools — GlassShell
//
//  How a terminal's unseen bell looks wherever its tab is shown (the owner, 2026-11-03: "If the window is in the dock,
//  turn the icon for that tab a shade of orange. If the tab is visible in an open window, but not selected, show an
//  orange glow under the tab. You decide how to address expose and coverflow."). One colour and two marks:
//  - a tab's icon where the icon is all that stands for it — an orb's ring, in the dock or where the window shrank
//    — turns orange, with an orange glow behind it, since Claude Code's own mark is already an orange (#D97757);
//    a window alone on its orb, with no tab icons on its ring, takes an orange rim;
//  - a tab drawn whole — a window's sidebar or tab bar, Show All Windows' cards, a window's grid and its carousel —
//    glows orange beneath it.
//  The notice itself is `TerminalBellNotice`: kept with the terminal, cleared once it is in sight.
//

import SwiftUI

public enum GlassBell {
    /// The bell's colour, everywhere.
    public static let color = Color.orange
    /// Said after a tab's name by VoiceOver.
    public static let accessibilityWord = "Bell rang"
}

public extension View {
    /// An orange glow beneath a tab drawn whole, while its terminal's bell is unseen: a row's or a tab's (`spread`
    /// small), a card's or a tile's (large). `outside` keeps it off the shape itself, for a see-through one — a tile
    /// of a glass terminal, which the glow would otherwise fill (the visionOS simulator, 2026-11-03).
    func glassBellGlow(_ isOn: Bool, cornerRadius: CGFloat = 8, spread: CGFloat = 6, outside: Bool = false) -> some View {
        modifier(GlassBellGlow(isOn: isOn, cornerRadius: cornerRadius, spread: spread, outside: outside))
    }

    /// The bell on a tile's own edge — an orange rim, glowing inward — where nothing outside it is drawn: a carousel's
    /// tiles, which Vision Pro stands in real depth, each clipped to itself (the visionOS simulator, 2026-11-03).
    func glassBellEdge(_ isOn: Bool, cornerRadius: CGFloat = 10) -> some View {
        overlay {
            if isOn {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.strokeBorder(GlassBell.color, lineWidth: 12).blur(radius: 10).opacity(0.7)
                    shape.strokeBorder(GlassBell.color, lineWidth: 2.5)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// The orange glow behind a tab's icon while its terminal's bell is unseen (an orb's ring, a row's icon).
    func glassBellIconGlow(_ isOn: Bool) -> some View {
        background {
            if isOn {
                Circle()
                    .fill(GlassBell.color)
                    .scaleEffect(1.25)
                    .blur(radius: 5)
                    .opacity(0.75)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Light from under the shape, strongest along its foot: it reads as beneath the tab, not a frame around it.
private struct GlassBellGlow: ViewModifier {
    /// Behind a row's text: on the Mac's light sidebar the headset's strength read as a highlighter over the name
    /// (the macOS VM, 2026-11-03).
    #if os(macOS)
    static let rowOpacity = 0.42
    #else
    static let rowOpacity = 0.7
    #endif

    let isOn: Bool
    let cornerRadius: CGFloat
    let spread: CGFloat
    let outside: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(GlassBell.color)
                        .padding(.horizontal, outside ? 0 : spread * 0.5)
                        .offset(y: spread * 0.6)
                        .blur(radius: spread)
                        .opacity(outside ? 0.95 : Self.rowOpacity)
                        .mask {
                            if outside {
                                GlassBellOutside(cornerRadius: cornerRadius, reach: spread * 4)
                                    .fill(style: FillStyle(eoFill: true))
                            } else {
                                Rectangle().padding(-spread * 4)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isOn)
    }
}

/// Everything within `reach` around a rounded rectangle, but not the rectangle: where a see-through tile's glow shows.
private struct GlassBellOutside: Shape {
    let cornerRadius: CGFloat
    let reach: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -reach, dy: -reach))
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        return path
    }
}
