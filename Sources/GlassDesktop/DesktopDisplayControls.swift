//
//  DesktopDisplayControls.swift
//  Glass Power Tools — GlassDesktop
//
//  W30: a host's displays in windows of their own, and the connection's quality, where a person can
//  see and set them — in the desktop window's controls (the ornament on Vision Pro, the toolbar
//  elsewhere) and in Desktop Settings ▸ This Window.
//

import SwiftUI
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport
import GlassShell

// MARK: - The readout

/// What a link's statistics say, in words a person reads at a glance.
enum DesktopLinkReadout {
    /// "1.2 Mbit/s", "640 kbit/s".
    static func rate(bytesPerSecond: Double) -> String {
        let kilobits = max(0, bytesPerSecond) * 8 / 1000
        if kilobits >= 1000 { return String(format: "%.1f Mbit/s", kilobits / 1000) }
        return String(format: "%.0f kbit/s", kilobits)
    }

    /// "14 updates/s".
    static func updates(_ perSecond: Double) -> String {
        perSecond >= 10 || perSecond == 0 ? String(format: "%.0f updates/s", perSecond)
                                          : String(format: "%.1f updates/s", perSecond)
    }

    /// "24-bit color", "16-bit color", "256 colors".
    static func colour(_ bits: Int) -> String {
        bits <= 8 ? "256 colors" : "\(bits)-bit color"
    }

    /// The level in effect, and why: "Automatic: Data Saver", or the fixed level.
    static func level(_ statistics: GlassDesktopLinkStatistics) -> String {
        statistics.quality == .automatic ? "Automatic: \(statistics.level.title)" : statistics.level.title
    }

    /// The round trip, and the part of it spent waiting in the network when that is noticeable:
    /// "42 ms", "1.3 s, 1.2 s of it waiting in the network".
    static func roundTrip(_ seconds: Double, queued: Double?) -> String {
        func duration(_ value: Double) -> String {
            value < 1 ? "\(Int((value * 1000).rounded())) ms" : String(format: "%.1f s", value)
        }
        guard let queued, queued >= 0.05 else { return duration(seconds) }
        return "\(duration(seconds)), \(duration(queued)) of it waiting in the network"
    }

    /// What a High Performance session is doing, in a word or the Mac's reason.
    static func highPerformance(_ status: GlassDesktopHighPerformanceStatus) -> String {
        switch status {
        case .unavailable(let reason): "Not available: \(reason)"
        case .starting: "Starting…"
        case .streaming: "Streaming"
        case .restarting: "Restarting after a display change…"
        }
    }

    /// A Mac's picture size as a fraction of its own: "75%", "100%".
    static func scale(_ factor: Double) -> String {
        "\(Int((factor * 100).rounded()))%"
    }

    /// Pixels per point of the Mac's own, as a person says it (W38): "1x", "2x", "0.75x".
    static func density(_ perPoint: Double) -> String {
        let rounded = (perPoint * 100).rounded() / 100
        if rounded == rounded.rounded() { return "\(Int(rounded))x" }
        return String(format: "%gx", rounded)
    }

    /// One line for a status bar or a menu: "1.2 Mbit/s · 14 updates/s · 16-bit color · ZRLE", and
    /// "· 75% size" while a Mac sends a smaller picture.
    static func line(_ statistics: GlassDesktopLinkStatistics) -> String {
        guard !statistics.paused else { return "Paused: no display on screen" }
        var parts = [rate(bytesPerSecond: statistics.bytesPerSecond), updates(statistics.updatesPerSecond),
                     colour(statistics.colourDepth)]
        if let encoding = statistics.encoding { parts.append(encoding) }
        if let factor = statistics.serverScale, factor < 0.995 { parts.append("\(scale(factor)) size") }
        return parts.joined(separator: " · ")
    }
}


// MARK: - Desktop Settings ▸ Connection

/// Desktop Settings ▸ **Connection** (W30): what belongs to the desktop's connection rather than to
/// one window — Quality with what the link carries now, and Display Windows. Every window of the
/// desktop shows this same page. Offered for VNC, and for any host with several displays.
struct DesktopConnectionSettingsView: View {
    let session: DesktopSessionModel
    let defaults: DesktopDefaults

    static func isOffered(for session: DesktopSessionModel) -> Bool {
        session.connection.protocol == .vnc || session.screens.count > 1
    }

    var body: some View {
        Form {
            DesktopConnectionSettingsSections(session: session, defaults: defaults)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Quality and Display Windows, with the live readout. Both are the desktop's own window's settings —
/// one connection carries all its windows — so a display window shows and changes that one.
struct DesktopConnectionSettingsSections: View {
    let session: DesktopSessionModel
    @Bindable var primary: DesktopViewport
    let defaults: DesktopDefaults

    init(session: DesktopSessionModel, defaults: DesktopDefaults) {
        self.session = session
        self.primary = session.primaryViewport
        self.defaults = defaults
    }

    var body: some View {
        if session.connection.protocol == .vnc {
            // The level, and right under it what the link carries now: the reason to change it.
            Section {
                GlassWindowSettingRow(DesktopWindowSettings.quality, overrides: $primary.windowSettings,
                                      global: defaults.quality, inheritsFrom: DesktopWindowSettingsView.allDesktops) { value in
                    Picker("Quality", selection: value) {
                        ForEach(GlassDesktopStreamQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("desktop-window-quality")
                }
                // W38: a Mac's Retina displays at 1x, or at their own pixels.
                GlassWindowSettingRow(DesktopWindowSettings.retina, overrides: $primary.windowSettings,
                                      global: defaults.retina, inheritsFrom: DesktopWindowSettingsView.allDesktops) { value in
                    Picker(DesktopWindowSettings.retina.title, selection: value) {
                        ForEach(GlassDesktopRetinaDisplays.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("desktop-window-retina")
                }
                GlassWindowSettingRow(DesktopWindowSettings.macScreenSharing, overrides: $primary.windowSettings,
                                      global: defaults.macScreenSharing, inheritsFrom: DesktopWindowSettingsView.allDesktops) { value in
                    Picker(DesktopWindowSettings.macScreenSharing.title, selection: value) {
                        ForEach(GlassDesktopMacScreenSharing.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("desktop-window-mac-screen-sharing")
                }
                if let status = session.highPerformanceStatus {
                    LabeledContent("High Performance", value: DesktopLinkReadout.highPerformance(status))
                        .accessibilityIdentifier("desktop-window-high-performance")
                }
                if let statistics = session.linkStatistics {
                    LabeledContent("Receiving", value: DesktopLinkReadout.rate(bytesPerSecond: statistics.bytesPerSecond))
                    LabeledContent("Updates", value: DesktopLinkReadout.updates(statistics.updatesPerSecond))
                    LabeledContent("Level", value: DesktopLinkReadout.level(statistics))
                    LabeledContent("Color", value: DesktopLinkReadout.colour(statistics.colourDepth))
                    if let factor = statistics.serverScale {
                        LabeledContent("Scale", value: DesktopLinkReadout.scale(factor))
                            .accessibilityIdentifier("desktop-window-scale")
                    }
                    LabeledContent("Encoding", value: statistics.encoding ?? "—")
                    if let measured = statistics.measuredKilobitsPerSecond {
                        LabeledContent("Measured link", value: DesktopLinkReadout.rate(bytesPerSecond: measured * 1000 / 8))
                    }
                    if let roundTrip = statistics.roundTrip {
                        LabeledContent("Round trip", value: DesktopLinkReadout.roundTrip(roundTrip, queued: statistics.queued))
                            .accessibilityIdentifier("desktop-window-round-trip")
                    }
                    LabeledContent("Fetching", value: statistics.paused ? "Nothing: no window on screen"
                                   : statistics.regionLimited ? "Only the displays on screen" : "The whole desktop")
                } else {
                    Text("Measuring the connection…").foregroundStyle(.secondary)
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("The figures are what the network carries now, updated every second. \(Self.qualityFooter) \(Self.retinaFooter) \(Self.macScreenSharingFooter)")
            }
            .accessibilityIdentifier("desktop-window-readout")
            // W38: what each window of this desktop is being sent, and over which connection.
            Section {
                ForEach(session.viewports) { window in
                    LabeledContent(windowName(window), value: windowLine(window))
                        .accessibilityIdentifier("desktop-window-sending")
                }
                if let failure = session.displayConnectionFailure {
                    Text("A display's window could not open a connection of its own, so it shows its display from the desktop's connection at the display's own pixels. The Mac said: \(failure)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Windows")
            } footer: {
                Text("Each window's picture as it arrives: its size in pixels, and at what scale of the Mac's own points.")
            }
        }
        if session.screens.count > 1 {
            Section {
                GlassWindowSettingRow(DesktopWindowSettings.displays, overrides: $primary.windowSettings,
                                      global: defaults.resolvedDisplays,
                                      inheritsFrom: DesktopWindowSettingsView.allDesktops) { value in
                    Picker("Windows", selection: value) {
                        ForEach(DesktopDisplayWindows.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("desktop-window-displays")
                }
            } header: {
                Text("Display Windows")
            } footer: {
                Text("With a window for each display, connecting to this computer opens one window per display, and each moves, sizes and zooms on its own. Open a display's window at any time from This Window ▸ Displays, and close it as any window; closing one leaves the others connected.")
            }
        }
    }

    /// A window's name in the Windows list.
    private func windowName(_ window: DesktopViewport) -> String {
        let shown = window.selectedScreenID.map { DesktopDisplayLayout.name(of: $0, in: session.screens) } ?? "All Displays"
        return window.isPrimary ? "Desktop Window: \(shown)" : shown
    }

    /// "1728 × 1117 at 1x (50%) · Own Connection".
    private func windowLine(_ window: DesktopViewport) -> String {
        var line = session.sending(for: window) ?? "Waiting for a picture"
        if session.ownConnection(for: window) != nil { line += " · Own Connection" }
        else if session.displayConnections[window.id] != nil { line += " · Opening its own connection" }
        return line
    }

    static let macScreenSharingFooter = "High Performance is a Mac's own fast mode, as Apple's Screen Sharing offers it: the Mac moves its windows to a virtual display the size of this window and sends it as video with its sound, and stops playing sound itself meanwhile. It needs macOS 14 or later on Apple silicon, the Mac's own account, and UDP between this device and the Mac (ports 5900 and 5901). The Mac adapts the video between 20 and 60 Mbit/s; Data Saver holds it to 8 and Lowest to 3. It applies when the desktop next connects."
    static let retinaFooter = "Retina Displays is for a Mac. At 1x a Retina display arrives at one pixel per point, a quarter of its own pixels, and Quality's own reduction comes on top. A Mac sends one scale at a time, so while a Retina display and a 1x display are both on screen, each arrives at its own pixels, as Apple's Screen Sharing shows them. Native 2x always sends a Retina display's own pixels."

    static let qualityFooter = "Automatic measures the connection and moves between the levels as it changes: down when the link is slow, or when the picture arrives late — data waiting in the network, as on a phone's hotspot. Best is lossless, full color. Balanced is full color, with JPEG for photos where the computer offers it. Data Saver sends thousands of colors at up to 15 updates a second; Lowest compresses hardest at up to 8, with 256 colors where the computer sends no JPEG. A Mac sends its changes as they happen at every level, in thousands of colors at the least, and a smaller picture at Data Saver (75% of its size) and Lowest (50%); Scale shows the size it is sending. On a Mac, Best and Balanced are the same. Quality is the connection's, so it applies to every window of this desktop. Zooming or shrinking the picture here does not change what the network carries."
}

// MARK: - A display's own window

extension DesktopDisplayWindowValue {
    /// The scene's identifier (`GlassDesktopScenes`).
    public static let windowID = "desktop-display"
}

/// A display window (W30): the open session for its desktop, shown on its display. Joins the
/// connection the desktop's window opened; never opens one of its own.
struct DesktopDisplayWindowHost: View {
    let runtime: GlassDesktopRuntime
    let value: DesktopDisplayWindowValue?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var session: DesktopSessionModel?
    @State private var viewport: DesktopViewport?
    @State private var looked = false

    /// The ⚡ in this window, as in the desktop's own (`DesktopSessionHost`): the one Connections
    /// window forward, on Active. `openWindow(id: "main")` names no value, so on Vision Pro it
    /// opened a second Connections window, which then stayed beside the orb when the first shrank
    /// into it (W34).
    private var showActive: (@MainActor () -> Void)? {
        guard let show = runtime.showActiveConnections else { return nil }
        return { openWindow.openConnections(); show() }
    }

    var body: some View {
        Group {
            if let session, let viewport {
                DesktopSessionView(session: session, viewport: viewport, onClose: { dismiss() },
                                   showActiveConnections: showActive)
            } else if looked {
                ContentUnavailableView {
                    Label("Desktop Not Connected", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Connect to the desktop from the library, then open this display from Displays in its window.")
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desktopWindowBar()
        .onAppear(perform: resolve)
    }

    /// Once, when the window appears: the session must not change under an open window.
    private func resolve() {
        guard !looked else { return }
        looked = true
        guard let value else { return }
        let endpoint = EndpointID(rawValue: value.endpoint)
        var live = runtime.app.liveSession(for: endpoint)
        #if DEBUG
        if live == nil { live = runtime.demoSessions[endpoint] }
        #endif
        guard let live else { return }
        session = live
        viewport = live.displayViewport(for: value.display)
    }
}
