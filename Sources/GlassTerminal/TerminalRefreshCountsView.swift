//
//  TerminalRefreshCountsView.swift
//  Glass Power Tools — GlassTerminal
//
//  What a Vision Pro draws each second, over each terminal window, while Settings ▸ Terminal ▸ Show
//  Refresh Counts is on (the owner, 2026-10-29: "Should we add an FPS/debug window? I can see the
//  screen flicker."). The counts are `TerminalRefreshCounts`; the same go to the diagnostics file
//  whether shown or not. Drawn once a second, by itself: the window it sits on isn't drawn for it.
//

#if os(visionOS)
import SwiftUI
import GlassTerminalEmulator

struct TerminalRefreshCountsView: View {
    static let shownKey = "terminal.showsRefreshCounts"

    private let counts = TerminalRefreshCounts.shared

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(TerminalRefreshCounts.Source.allCases, id: \.self) { source in
                GridRow {
                    Text(source.rawValue)
                    Text("\(counts.second[source] ?? 0) a second")
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
            GridRow {
                Text("Output")
                Text(Int64(counts.outputBytes).formatted(.byteCount(style: .memory)) + " a second")
                    .monospacedDigit()
            }
            GridRow {
                Text("Key to next output")
                Text(counts.echo.map { "\($0.average) ms, longest \($0.longest) ms" } ?? "no keys")
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(16)
        .glassBackgroundEffect()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("terminal-refresh-counts")
    }
}

/// The switches, in Settings ▸ Terminal.
struct TerminalRefreshCountsSection: View {
    @AppStorage(TerminalRefreshCountsView.shownKey) private var shown = false
    @AppStorage(SwiftTermRendererPreference.visionMetalKey) private var drawsWithMetal = false
    @AppStorage("terminal.repaintsChangedRows") private var repaintsChangedRows = true

    var body: some View {
        Section {
            Toggle("Show Refresh Counts", isOn: $shown)
            Toggle("Draw with Metal", isOn: $drawsWithMetal)
                .onChange(of: drawsWithMetal) { _, _ in
                    NotificationCenter.default.post(name: SwiftTermRendererPreference.changedNotification, object: nil)
                }
            Toggle("Repaint Changed Lines Only", isOn: $repaintsChangedRows)
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Show Refresh Counts: over each terminal window, how often windows, terminals and their bars are drawn each second, the frames Metal shows, how much output arrives, how often the app is kept waiting, and how soon a typed key's answer comes back. Draw with Metal: terminals drawn by the graphics processor instead of Core Graphics. Repaint Changed Lines Only: Core Graphics repaints the lines that changed, not the whole terminal for every change. Each applies to open terminals at once.")
        }
    }
}
#endif
