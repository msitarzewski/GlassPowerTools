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


// MARK: - Controls in the window's bar

/// Displays (W30): which display this window shows, and opening another in a window of its own.
/// Offered when the host publishes more than one display.
struct DesktopDisplaysMenu: View {
    let session: DesktopSessionModel
    @Bindable var viewport: DesktopViewport
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if session.screens.count > 1 {
            Menu("Displays", systemImage: "rectangle.on.rectangle") {
                Picker("Show", selection: $viewport.selectedScreenID) {
                    Text("All Displays").tag(UInt32?.none)
                    ForEach(session.screens) { screen in
                        Text(DesktopDisplayLayout.name(of: screen.id, in: session.screens)).tag(UInt32?.some(screen.id))
                    }
                }
                .pickerStyle(.inline)
                if GlassWindowPresentation.canOpenWindows {
                    Section("Open in a New Window") {
                        ForEach(session.screens) { screen in
                            Button(DesktopDisplayLayout.name(of: screen.id, in: session.screens)) {
                                openWindow(id: DesktopDisplayWindowValue.windowID,
                                           value: DesktopDisplayWindowValue(endpoint: session.connection.id.rawValue,
                                                                            display: screen.id))
                            }
                        }
                    }
                }
            }
            .help("Displays")
            .accessibilityIdentifier("session.displays")
        }
    }
}

/// Quality (W30), with what the link is doing as the menu's heading. VNC only: RDP negotiates its
/// own codecs with the server.
struct DesktopQualityMenu: View {
    let session: DesktopSessionModel
    private var allDesktops = DesktopAllDesktopsStorage()

    init(session: DesktopSessionModel) { self.session = session }

    var body: some View {
        if session.connection.protocol == .vnc {
            Menu("Quality", systemImage: "gauge.with.dots.needle.67percent") {
                Section(session.linkStatistics.map(DesktopLinkReadout.line) ?? "Measuring the connection…") {
                    Picker("Quality", selection: quality) {
                        ForEach(GlassDesktopStreamQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            .help("Quality")
            .accessibilityIdentifier("session.quality")
        }
    }

    /// The desktop's own window's Quality: one connection carries every window of the desktop.
    private var quality: Binding<GlassDesktopStreamQuality> {
        GlassWindowSettingBinding.value(DesktopWindowSettings.quality,
                                        in: Binding(get: { session.primaryViewport.windowSettings },
                                                    set: { session.primaryViewport.windowSettings = $0 }),
                                        over: allDesktops.defaults.quality)
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
                    LabeledContent("Fetching", value: statistics.paused ? "Nothing: no window on screen"
                                   : statistics.regionLimited ? "Only the displays on screen" : "The whole desktop")
                } else {
                    Text("Measuring the connection…").foregroundStyle(.secondary)
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("The figures are what the network carries now, updated every second. \(Self.qualityFooter) \(Self.retinaFooter)")
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
                Text("Each window's picture as it arrives: its size in pixels, and at what scale of the Mac's own points. A display window marked Own Connection fetches its display on a connection of its own.")
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
                Text("With a window for each display, connecting to this computer opens one window per display, and each moves, sizes and zooms on its own. Open or close a display's window at any time from Displays in the window's controls; closing one leaves the others connected.")
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

    static let retinaFooter = "Retina Displays is for a Mac. At 1x a Retina display arrives at one pixel per point, a quarter of its own pixels, and Quality's own reduction comes on top. A Retina display and a 1x display cannot share one scale, so when a Mac has both and a display has a window of its own, that window opens a connection of its own to the Mac with the same sign-in, and each arrives at 1x. Native 2x sends a Retina display's own pixels."

    static let qualityFooter = "Automatic measures the connection and moves between the levels as it changes. Best is lossless, full color. Balanced is full color, with JPEG for photos where the computer offers it. Data Saver sends thousands of colors at up to 15 updates a second; Lowest compresses hardest at up to 8, with 256 colors where the computer sends no JPEG. A Mac also sends a smaller picture at Data Saver (75% of its size) and Lowest (50%); Scale shows the size it is sending. Quality is the connection's, so it applies to every window of this desktop. Zooming or shrinking the picture here does not change what the network carries."
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
