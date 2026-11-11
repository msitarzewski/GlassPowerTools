//
//  MacBellBadgeTests.swift
//  Glass Power Tools — GlassTerminalTests (macOS)
//
//  The Dock icon counts the terminals whose bell rang out of sight (the owner, 2026-11-10: "nothing in the dock if
//  the user is on another virtual desktop or has windows covered"). What must hold: each such terminal counts once,
//  across windows and tabs; one seen drops out; the count is followed by observation, so the badge changes as a
//  bell rings and as it is seen; no count is no badge.
//

#if os(macOS)
import AppKit
import Foundation
import Observation
import Testing
import GlassTerminalEmulator
@testable import GlassTerminal

@MainActor
@Suite("The Dock icon counts the terminals whose bell rang out of sight", .serialized)
struct MacBellBadgeTests {
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MacBellBadgeTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    /// A window of `tabs` tabs of one local pane each, every tab out of sight (another desktop, or covered).
    private func window(_ defaults: UserDefaults, tabs: Int) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(), defaults: defaults)
        for _ in 1..<max(1, tabs) { window.addTab() }
        for tab in window.tabs { tab.setInSight(false) }
        return window
    }

    private func ring(_ tab: MacWorkspaceController) throws {
        let pane = try #require(tab.focusedPaneID)
        try #require(tab.localRuntime(for: pane)).model.bellNotice.ring()
    }

    @Test("each terminal that rang out of sight counts once, across windows; one seen drops out")
    func counts() async throws {
        try await withDefaults { defaults in
            let first = window(defaults, tabs: 3), second = window(defaults, tabs: 2)
            #expect(MacBellBadge.unseen(in: [first, second]) == 0)
            try ring(first.tabs[0])
            try ring(first.tabs[2])
            try ring(second.tabs[1])
            try ring(second.tabs[1])
            #expect(MacBellBadge.unseen(in: [first, second]) == 3, "a terminal that rang twice is one terminal")

            first.tabs[2].setInSight(true)
            #expect(MacBellBadge.unseen(in: [first, second]) == 2, "brought to the front: seen")
            first.tabs[2].setInSight(false)
            #expect(MacBellBadge.unseen(in: [first, second]) == 2, "out of sight again, nothing new rang")
        }
    }

    @Test("a terminal in front in a window on screen hears its bell as it rings: no count")
    func inSightRingsSeen() async throws {
        try await withDefaults { defaults in
            let shown = window(defaults, tabs: 1)
            shown.tabs[0].setInSight(true)
            try ring(shown.tabs[0])
            #expect(MacBellBadge.unseen(in: [shown]) == 0)
        }
    }

    @Test("the count is followed: a bell rung, and one seen, each change it")
    func followedByObservation() async throws {
        try await withDefaults { defaults in
            let window = window(defaults, tabs: 2)
            final class Changes: @unchecked Sendable { var count = 0 }
            let changes = Changes()
            func track() {
                _ = withObservationTracking { MainActor.assumeIsolated { MacBellBadge.unseen(in: [window]) } }
                    onChange: { changes.count += 1 }
            }
            track()
            try ring(window.tabs[1])
            #expect(changes.count == 1, "a bell rung out of sight")
            track()
            window.tabs[1].setInSight(true)
            #expect(changes.count == 2, "the terminal seen")
            track()
            window.addTab()
            #expect(changes.count == 3, "a tab added")
        }
    }

    @Test("the choice is kept on this Mac, the Dock count unless chosen otherwise; a notification alone has no badge")
    func setting() async throws {
        try await withDefaults { defaults in
            let setting = MacBellOutOfSightSetting(defaults: defaults)
            #expect(setting.choice == .dockCount)
            setting.choice = .both
            #expect(MacBellOutOfSightSetting(defaults: defaults).choice == .both, "kept")
            #expect(MacBellBadge.badge(count: 2, choice: .both) == "2")
            #expect(MacBellBadge.badge(count: 2, choice: .dockCount) == "2")
            #expect(MacBellBadge.badge(count: 2, choice: .notification) == nil)
            #expect(MacBellBadge.badge(count: 0, choice: .both) == nil)
        }
    }

    @Test("a notice says when it goes unseen and when it is seen, once each")
    func noticeSays() {
        let (unseen, seen) = (TerminalBellNotice.onUnseen, TerminalBellNotice.onSeen)
        defer { TerminalBellNotice.onUnseen = unseen; TerminalBellNotice.onSeen = seen }
        var said: [String] = []
        TerminalBellNotice.onUnseen = { _ in said.append("unseen") }
        TerminalBellNotice.onSeen = { _ in said.append("seen") }
        let notice = TerminalBellNotice()
        notice.ring()
        notice.ring()
        notice.isInSight = true
        notice.clear()
        notice.ring()
        #expect(said == ["unseen", "seen"], "rung twice is one; rung in sight is none")
    }

    @Test("notification chosen: a bell gone unseen posts one, taken back when seen; a click brings its tab forward")
    func notifications() async throws {
        try await withDefaults { defaults in
            let setting = MacBellOutOfSightSetting(defaults: defaults)
            setting.choice = .notification
            let window = window(defaults, tabs: 2)
            // Registered as a window on screen, never ordered in: nothing appears on the screen.
            let shown = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                                 backing: .buffered, defer: false)
            shown.isReleasedWhenClosed = false
            MacWorkspacePreviewRegistry.shared.register(window, window: shown)
            let saved = (MacBellNotifications.post, MacBellNotifications.remove, MacBellNotifications.bringForward,
                         TerminalBellNotice.onUnseen, TerminalBellNotice.onSeen)
            defer {
                MacWorkspacePreviewRegistry.shared.remove(window.windowID)
                (MacBellNotifications.post, MacBellNotifications.remove, MacBellNotifications.bringForward,
                 TerminalBellNotice.onUnseen, TerminalBellNotice.onSeen) = saved
            }
            var posts: [(title: String, identifier: String, info: [String: String])] = []
            var removed: [String] = []
            var broughtForward: [NSWindow] = []
            MacBellNotifications.post = { title, _, identifier, info in posts.append((title, identifier, info)) }
            MacBellNotifications.remove = { removed += $0 }
            MacBellNotifications.bringForward = { broughtForward.append($0) }
            MacBellNotifications.start(registry: .shared, setting: setting)

            try ring(window.tabs[1])
            #expect(posts.count == 1)
            let post = try #require(posts.first)
            #expect(post.title.hasSuffix(" rang its bell"), "\(post.title)")
            let pane = try #require(window.tabs[1].focusedPaneID)
            #expect(post.identifier == "terminal-bell-\(pane.uuidString)")
            #expect(post.info["workspaceID"] == window.tabs[1].workspaceID.uuidString)

            window.select(window.tabs[0].workspaceID)
            MacBellNotifications.open(post.info, registry: .shared)
            #expect(window.selectedTabID == window.tabs[1].workspaceID, "the tab that rang, chosen")
            #expect(broughtForward == [shown], "and its window brought forward")

            window.tabs[1].setInSight(true)
            #expect(removed == [post.identifier], "seen: the notification taken back")

            setting.choice = .dockCount
            window.tabs[1].setInSight(false)
            try ring(window.tabs[1])
            #expect(posts.count == 1, "the Dock count alone posts nothing")
        }
    }

    @Test("the badge: the number, or none at all")
    func label() {
        #expect(MacBellBadge.badgeLabel(0) == nil)
        #expect(MacBellBadge.badgeLabel(1) == "1")
        #expect(MacBellBadge.badgeLabel(27) == "27")
    }
}
#endif
