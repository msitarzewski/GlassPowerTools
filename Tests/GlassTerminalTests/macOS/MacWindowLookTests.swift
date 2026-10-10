#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassTerminal

/// W20 (owner, 2026-10-09, in a Mac terminal window): "I was testing to see if there was a way to
/// give a color/tint to the tab group." A Mac terminal window owns its look: set from any tab, its
/// local and SSH panes draw with it; a tab dragged in takes it; it is saved with the window's tabs,
/// so it comes back after a relaunch; a saved Workgroup opens with its look, and a window saved as
/// a Workgroup keeps it.
///
/// No tmux runs and nothing connects: panes are SSH intents that nothing connects, and the
/// windows' records go to a private defaults suite.
@MainActor
@Suite("A Mac terminal window owns its look", .serialized)
struct MacWindowLookTests {
    private let red = TerminalSessionOverride(windowOpacity: 0.4, glassTint: "#FF2D55")
    private let blue = TerminalSessionOverride(blurBackground: 0.2, glassTint: "#007AFF")
    private let server = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MacWindowLookTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// A window of SSH tabs, on screen once, so saved.
    private func window(_ defaults: UserDefaults, tabs: Int = 1,
                        transferBroker: MacWorkspaceTransferBroker = .shared) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(tabs: (0..<tabs).map { _ in
                MacWorkspaceTabRequest(initialPaneIntent: .ssh(serverID: server.id))
            }),
            transferBroker: transferBroker, defaults: defaults)
        window.windowDidOpen()
        return window
    }

    /// The same window at the next launch: made from its record alone.
    private func relaunched(_ id: UUID, _ defaults: UserDefaults) -> MacWorkspaceWindowController {
        MacWorkspaceWindowController(request: MacWorkspaceLaunchRequest(windowID: id, tabs: []), defaults: defaults)
    }

    private func recordKey(_ id: UUID) -> String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(id.uuidString.lowercased())"
    }

    private func show(_ controller: MacWorkspaceWindowController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        MacWorkspacePreviewRegistry.shared.register(controller, window: window)
        return window
    }

    @Test("set from a tab, the look is saved with the window and comes back with it after a relaunch")
    func savedWithTheWindow() throws {
        try withDefaults { defaults in
            let w = window(defaults, tabs: 2)
            w.setLook(red)
            #expect(w.look == red)
            let back = relaunched(w.windowID, defaults)
            #expect(back.look == red, "back with its look")
            #expect(back.tabs.map(\.workspaceID) == w.tabs.map(\.workspaceID))

            w.setLook(nil)
            #expect(relaunched(w.windowID, defaults).look == nil, "reset: back to the settings")
            w.setLook(TerminalSessionOverride())
            let saved = try #require(defaults.data(forKey: recordKey(w.windowID)))
            let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            #expect(object["look"] == nil, "a look that sets nothing is not saved")
        }
    }

    @Test("a window saved before W20 reads with no look; a look that can't be read costs only the look")
    func recordsReadLeniently() throws {
        try withDefaults { defaults in
            let w = window(defaults, tabs: 2)
            w.setLook(red)
            let key = recordKey(w.windowID)
            let saved = try #require(defaults.data(forKey: key))
            var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            #expect(object["look"] != nil)

            object.removeValue(forKey: "look")
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
            let old = relaunched(w.windowID, defaults)
            #expect(old.look == nil && old.tabs.count == 2 && old.restorationFailure == nil)

            object["look"] = ["glassTint": 12]
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
            let unreadable = relaunched(w.windowID, defaults)
            #expect(unreadable.look == nil && unreadable.tabs.count == 2 && unreadable.restorationFailure == nil,
                    "its tabs still come back")
        }
    }

    @Test("a saved Workgroup opens in a window with its look")
    func workgroupOpensWithItsLook() throws {
        try withDefaults { defaults in
            var preset = LayoutPreset(name: "Builds", sessionIntents: [.init(serverID: server.id), .init(serverID: server.id)])
            preset.look = blue
            let requests = try MacWorkgroupLauncher.launch(preset: preset, broker: MacStartupCommandBroker(),
                                                           openWindow: { _ in })
            let request = try #require(requests.first)
            #expect(request.look == blue)
            let opened = MacWorkspaceWindowController(request: request, defaults: defaults)
            #expect(opened.look == blue)
            opened.windowDidOpen()
            #expect(relaunched(opened.windowID, defaults).look == blue, "and keeps it after a relaunch")

            // The scene's value travels as JSON: the look goes with it.
            let decoded = try JSONDecoder().decode(MacWorkspaceLaunchRequest.self, from: JSONEncoder().encode(request))
            #expect(decoded.look == blue)
        }
    }

    @Test("a window saved as a Workgroup keeps its look")
    func captureKeepsTheLook() throws {
        try withDefaults { defaults in
            let w = window(defaults, tabs: 2)
            let plain = try w.capturePreset(name: "Desk", servers: [server])
            #expect(plain.look == nil)
            w.setLook(red)
            let tinted = try w.capturePreset(name: "Desk", servers: [server])
            #expect(tinted.look == red)
        }
    }

    @Test("a tab dragged into another window takes that window's look; neither window's look changes")
    func draggedInTakesTheLook() throws {
        try withDefaults { defaults in
            let source = window(defaults, tabs: 2), destination = window(defaults)
            source.setLook(red)
            destination.setLook(blue)
            let shownSource = show(source), shownDestination = show(destination)
            defer {
                MacWorkspacePreviewRegistry.shared.remove(source.windowID)
                MacWorkspacePreviewRegistry.shared.remove(destination.windowID)
            }
            let moving = source.tabs[1].workspaceID
            #expect(MacWorkspacePreviewRegistry.shared.look(ofWindowWithTab: moving) == red)
            #expect(destination.acceptDroppedTab(.init(windowID: source.windowID, workspaceID: moving), at: 0))
            #expect(MacWorkspacePreviewRegistry.shared.look(ofWindowWithTab: moving) == blue, "drawn with its new window's look")
            #expect(source.look == red && destination.look == blue)
            withExtendedLifetime((shownSource, shownDestination)) {}
        }
    }

    @Test("Move Tab to New Window: the new window looks like the one the tab left")
    func movedToNewWindowKeepsTheLook() throws {
        try withDefaults { defaults in
            let broker = MacWorkspaceTransferBroker()
            let source = window(defaults, tabs: 2, transferBroker: broker)
            source.setLook(red)
            source.select(source.tabs[1].workspaceID)
            let request = try #require(source.transferSelectedTab())
            #expect(request.look == red)
            let made = MacWorkspaceWindowController(request: request, transferBroker: broker, defaults: defaults)
            #expect(made.tabs.count == 1 && made.look == red)
            #expect(relaunched(made.windowID, defaults).look == red, "saved with it")
            #expect(source.look == red, "the window it left keeps its own")
        }
    }
}
#endif
