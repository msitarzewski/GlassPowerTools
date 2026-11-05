//
//  TerminalTabMark.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal tab's icon wherever tabs are listed: the Mac window's sidebar and Vision Pro's (the
//  owner, 2026-10-21: "instead of a generic terminal icon, we replace it with the running agent and
//  color it as required... then pulse it as work is happening"). The coding agent running in the
//  tab, in the agent's own colour, else a terminal in the window's; pulsing while a terminal in the
//  tab prints. It replaces the wave the Mac drew under a busy row, so both platforms say it the same
//  way. Show All Windows keeps its wave: a card is not a row.
//
//  The agents' marks are template pictures, not SF Symbols, so Apple's symbol effects can't move
//  them: the pulse is the mark's own opacity, the same for a mark and a symbol.
//

import SwiftUI
import GlassShell
import GlassTerminalEmulator

struct TerminalTabMark: View {
    /// The agent running in the tab, if any.
    let agent: TerminalAgent?
    /// The colour with no agent, or with an agent whose mark has no colour of its own (Cursor's,
    /// Kimi's are black): the window's tint or its workgroup's.
    let color: Color
    /// A terminal in the tab printed in the last moment.
    let working: Bool
    /// Its side in points; nil is a list's symbol at the row's text size.
    var size: CGFloat? = nil
    /// Its terminal rang the bell out of sight (`TerminalBellNotice`): orange, glowing (`GlassBell`).
    var rang: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The mark's side, as a list's symbol is drawn at the row's text size.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 16

    var body: some View {
        let mark = icon
            .foregroundStyle(rang ? GlassBell.color : agent?.accent?.color ?? color)
            .glassBellIconGlow(rang)
        Group {
            // Breathing as an animation between its two ends, which SwiftUI runs at the display's own rate without
            // drawing the mark again. It was the mark drawn again up to 30 times a second, stepping, and standing
            // still whenever the app was busy: likely part of what the owner saw in the orb dock (2026-11-02:
            // "low framerate … what looks like a 4 bit color animation").
            if working && !reduceMotion {
                mark.phaseAnimator([Self.full, Self.faint]) { mark, opacity in
                    mark.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: Self.breath / 2)
                }
            } else {
                mark
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let agent {
            agent.markImage
                .resizable()
                .scaledToFit()
                .frame(width: size ?? side, height: size ?? side)
        } else if let size {
            Image(systemName: "apple.terminal")
                .font(.system(size: size * 0.85, weight: .semibold))
        } else {
            Image(systemName: "apple.terminal")
        }
    }

    /// A breath every 1.4 seconds, between full and a third: seen at a glance, and never gone.
    static let breath: Double = 1.4
    static let full: Double = 1
    static let faint: Double = 0.3
}

/// A terminal session's mark, kept current by itself: its agent as its title or its tmux pane names it,
/// pulsing while it prints; orange where its bell rang out of sight, when `showsBell` (an orb's ring, in the dock or
/// where the window shrank: the owner, 2026-11-03). Vision Pro's sidebar rows and the window's orb draw it, so both say the
/// same of each terminal (the owner, 2026-10-21: "make sure they represent the llm cli like the
/// sidebar does").
struct TerminalSessionMark: View {
    let session: TerminalSession
    let color: Color
    var size: CGFloat? = nil
    /// Where the mark alone stands for the tab, so its bell shows on it; a sidebar row glows beneath instead.
    var showsBell = false

    var body: some View {
        // Read first: drawn again as output starts and stops, by then with the title an agent set.
        let working = session.terminalHostModel.outputActivity.isActive
        let rang = showsBell && session.terminalHostModel.bellNotice.isUnseen
        TerminalTabMark(agent: GlassTerminalCapability.agent(of: session), color: color, working: working, size: size,
                        rang: rang)
    }
}
