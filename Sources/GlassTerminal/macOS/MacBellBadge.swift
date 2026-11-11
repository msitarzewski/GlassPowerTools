//
//  MacBellBadge.swift
//  GlassTerminal (macOS)
//
//  A terminal that rang its bell out of sight, said outside its window (the owner, 2026-11-10: "badges for the
//  number of terminals that need attention. We have the orange glow in the tab, the pulsing in the dock icon, etc.
//  but nothing in the dock if the user is on another virtual desktop or has windows covered"; then, asked how: "dock
//  count, notification, or both (in settings)", and the permission asked "at the next launch").
//
//  A terminal's bell is unseen (`TerminalBellNotice`) from when it rings while its tab isn't in front in a window on
//  screen until it is: a window on another desktop or covered by others isn't on screen (`MacWorkspaceView`, by the
//  window's occlusion state), nor is one shrunk into the orb dock.
//  - **Dock count** (`MacBellBadge`): how many such terminals, every window's tabs and panes, local and SSH, on the
//    app's icon; none, no badge. Followed by observation, so nothing polls.
//  - **Notification** (`MacBellNotifications`): one per terminal as its bell goes unseen, "bravo rang its bell", taken
//    back once it is seen; clicking it brings its tab forward. Silent: the terminal's own Bell setting is the sound.
//  macOS draws a Dock badge only for an app allowed notifications with badges (other developers report the same:
//  Electron's badge count, OpenJDK's taskbar badge), so both need the permission the app asks for at launch.
//

#if os(macOS)
import AppKit
import Observation
import os
import GlassConnectionUI
import GlassLayers
import GlassTerminalEmulator

/// What a bell rung out of sight does, beyond its tab's glow (Settings ▸ Connections, under Notifications).
enum MacBellOutOfSight: String, CaseIterable, Identifiable {
    case dockCount
    case notification
    case both

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dockCount: "Dock Count"
        case .notification: "Notification"
        case .both: "Both"
        }
    }
    var countsOnDock: Bool { self != .notification }
    var notifies: Bool { self != .dockCount }
}

/// The choice, kept on this Mac.
@MainActor
@Observable
final class MacBellOutOfSightSetting {
    static let shared = MacBellOutOfSightSetting(defaults: GlassUITestRun.settingsDefaults)
    static let key = "bellOutOfSight"

    @ObservationIgnored private let defaults: UserDefaults
    var choice: MacBellOutOfSight {
        didSet { defaults.set(choice.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        choice = defaults.string(forKey: Self.key).flatMap(MacBellOutOfSight.init(rawValue:)) ?? .dockCount
    }
}

@MainActor
enum MacBellBadge {
    private static var started = false
    private static let logger = Logger(subsystem: "com.glasspowertools", category: "BellBadge")

    /// Keeps the Dock icon's badge to the count from now on, while the setting asks for it. Once per launch.
    static func start(registry: MacWorkspacePreviewRegistry = .shared, setting: MacBellOutOfSightSetting = .shared) {
        guard !started else { return }
        started = true
        follow(registry, setting)
    }

    private static func follow(_ registry: MacWorkspacePreviewRegistry, _ setting: MacBellOutOfSightSetting) {
        let label = withObservationTracking {
            badge(count: unseen(in: registry.shownControllers), choice: setting.choice)
        } onChange: {
            Task { @MainActor in follow(registry, setting) }
        }
        if NSApp.dockTile.badgeLabel != label {
            NSApp.dockTile.badgeLabel = label
            logger.info("Dock badge now \(label ?? "none", privacy: .public)")
        }
    }

    /// The terminals, across these windows' tabs, whose bell rang out of sight and hasn't been seen.
    static func unseen(in windows: [MacWorkspaceWindowController]) -> Int {
        windows.reduce(0) { total, window in window.tabs.reduce(total) { $0 + $1.unseenBellCount } }
    }

    /// The badge for `count` terminals: the number, or none.
    static func badgeLabel(_ count: Int) -> String? {
        count > 0 ? String(count) : nil
    }

    /// The badge for `count` terminals under `choice`: none unless it counts on the Dock.
    static func badge(count: Int, choice: MacBellOutOfSight) -> String? {
        choice.countsOnDock ? badgeLabel(count) : nil
    }
}

@MainActor
enum MacBellNotifications {
    static let thread = "com.glasspowertools.terminal-bell"

    /// How a notification is posted and taken back. Tests replace them; nothing else should.
    static var post: @MainActor (_ title: String, _ body: String, _ identifier: String, _ info: [String: String]) -> Void = {
        title, body, identifier, info in
        Task {
            _ = try? await GlassSystemNotifications.post(title: title, body: body, threadIdentifier: thread,
                                                         identifier: identifier, userInfo: info, playsSound: false)
        }
    }
    static var remove: @MainActor ([String]) -> Void = { GlassSystemNotifications.remove(identifiers: $0) }
    /// Brings a window forward. Tests replace it, so nothing comes in front of the person running them.
    static var bringForward: @MainActor (NSWindow) -> Void = { window in
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Each notice posted for, and its notification's identifier, to take back when it is seen.
    private static var posted: [ObjectIdentifier: String] = [:]

    /// From now on, a bell gone unseen posts while the setting asks for it; a click brings its tab forward.
    static func start(registry: MacWorkspacePreviewRegistry = .shared, setting: MacBellOutOfSightSetting = .shared) {
        TerminalBellNotice.onUnseen = { notice in rang(notice, registry: registry, setting: setting) }
        TerminalBellNotice.onSeen = { notice in seen(notice) }
        GlassSystemNotifications.openHandlers[thread] = { info in open(info, registry: registry) }
    }

    static func rang(_ notice: TerminalBellNotice, registry: MacWorkspacePreviewRegistry, setting: MacBellOutOfSightSetting) {
        guard setting.choice.notifies, let found = locate(notice, in: registry) else { return }
        let servers = GlassTerminalRuntime.current?.sessionManager.serverManager.servers ?? []
        let identity = found.tab.windowIdentity(servers: servers)
        let identifier = "terminal-bell-\(found.paneID.uuidString)"
        posted[ObjectIdentifier(notice)] = identifier
        post("\(identity.title) rang its bell", identity.subtitle ?? "", identifier,
             ["workspaceID": found.tab.workspaceID.uuidString, "paneID": found.paneID.uuidString])
    }

    static func seen(_ notice: TerminalBellNotice) {
        guard let identifier = posted.removeValue(forKey: ObjectIdentifier(notice)) else { return }
        remove([identifier])
    }

    /// The tab holding the terminal comes forward, on that terminal.
    static func open(_ info: [String: String], registry: MacWorkspacePreviewRegistry) {
        guard let workspaceID = info["workspaceID"].flatMap(UUID.init(uuidString:)),
              let shown = registry.shownWindows.first(where: { $0.controller.tabs.contains { $0.workspaceID == workspaceID } })
        else { return }
        shown.controller.select(workspaceID)
        if let paneID = info["paneID"].flatMap(UUID.init(uuidString:)),
           let tab = shown.controller.tabs.first(where: { $0.workspaceID == workspaceID }) {
            tab.focus(paneID)
        }
        bringForward(shown.window)
    }

    /// The tab and pane whose terminal holds `notice`.
    static func locate(_ notice: TerminalBellNotice,
                       in registry: MacWorkspacePreviewRegistry) -> (tab: MacWorkspaceController, paneID: UUID)? {
        for window in registry.shownControllers {
            for tab in window.tabs {
                if let paneID = tab.paneID(holding: notice) { return (tab, paneID) }
            }
        }
        return nil
    }
}
#endif
