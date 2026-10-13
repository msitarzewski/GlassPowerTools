#if os(macOS)
import AppKit
import Foundation
import Testing
import GlassShell
@testable import GlassTerminal

/// Show All Terminals (W9, 2026-10-08): every terminal window as a group of live tiles, one per
/// tab, packed onto the screen; arrows, typing, choosing and dragging; the tmux sessions no tab
/// shows; and the pinch that opens it.
extension LocalTmuxServerSuites {
@MainActor
@Suite("Show All Terminals")
struct MacTerminalExposeTests {
    // MARK: Windows on screen, as the tab-drag tests make them

    private func window(_ defaults: UserDefaults, tabs: Int,
                        request: MacWorkspaceLaunchRequest = MacWorkspaceLaunchRequest()) -> MacWorkspaceWindowController {
        let window = MacWorkspaceWindowController(request: request, defaults: defaults)
        for _ in 1..<max(1, tabs) { window.addTab() }
        return window
    }

    /// Registered as a window on screen, never ordered in: nothing appears on the screen.
    private func show(_ controller: MacWorkspaceWindowController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        MacWorkspacePreviewRegistry.shared.register(controller, window: window)
        return window
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MacTerminalExposeTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    // MARK: Layout

    nonisolated private static let screens: [CGSize] = [
        CGSize(width: 1440, height: 760), CGSize(width: 1280, height: 640),
        CGSize(width: 2460, height: 1300), CGSize(width: 1000, height: 560),
    ]

    private func check(_ layout: MacTerminalExposeLayout, counts: [Int], size: CGSize,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let context = "\(counts) in \(Int(size.width))×\(Int(size.height))"
        #expect(layout.groups.map(\.tileFrames.count) == counts, "\(context)", sourceLocation: sourceLocation)
        let bounds = CGRect(origin: .zero, size: layout.scrolls ? layout.contentSize : size).insetBy(dx: -0.01, dy: -0.01)
        #expect(layout.contentSize.width <= size.width + 0.01, "\(context)", sourceLocation: sourceLocation)
        let tiles = layout.groups.flatMap(\.tileFrames)
        for group in layout.groups {
            #expect(bounds.contains(group.frame), "group outside the screen, \(context)", sourceLocation: sourceLocation)
            for tile in group.tileFrames {
                #expect(group.frame.insetBy(dx: -0.01, dy: -0.01).contains(tile), "tile outside its group, \(context)",
                        sourceLocation: sourceLocation)
                #expect(tile.size == layout.tileSize, "\(context)", sourceLocation: sourceLocation)
            }
        }
        func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
            let shared = a.intersection(b)
            return !shared.isNull && shared.width > 0.01 && shared.height > 0.01
        }
        for i in tiles.indices { for j in tiles.indices where j > i {
            #expect(!overlap(tiles[i], tiles[j]), "tiles overlap, \(context)", sourceLocation: sourceLocation)
        } }
        let groups = layout.groups
        for i in groups.indices { for j in groups.indices where j > i {
            #expect(!overlap(groups[i].frame, groups[j].frame), "groups overlap, \(context)", sourceLocation: sourceLocation)
        } }
        // Reading order: down the rows, left to right within one.
        for (a, b) in zip(groups, groups.dropFirst()) {
            #expect(a.row < b.row || (a.row == b.row && a.frame.maxX <= b.frame.minX + 0.01),
                    "groups out of order, \(context)", sourceLocation: sourceLocation)
        }
    }

    @Test("N windows of M tabs: every tile on the screen, none overlapping, groups in order",
          arguments: screens)
    func layoutFits(_ size: CGSize) {
        for windows in 1...8 {
            for tabs in 1...12 {
                let counts = Array(repeating: tabs, count: windows)
                check(MacTerminalExposeLayout(tileCounts: counts, in: size), counts: counts, size: size)
            }
        }
        for counts in [[1, 7, 2, 12, 3], [12, 1, 1, 1], [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5], [32, 32, 32]] {
            check(MacTerminalExposeLayout(tileCounts: counts, in: size), counts: counts, size: size)
        }
    }

    @Test("a typical count fits without scrolling, as large as the screen allows; a crowd scrolls")
    func layoutScrollsOnlyWhenItMust() {
        let screen = CGSize(width: 1280, height: 640)
        for windows in 1...4 {
            for tabs in 1...6 {
                let layout = MacTerminalExposeLayout(tileCounts: Array(repeating: tabs, count: windows), in: screen)
                #expect(!layout.scrolls, "\(windows) windows of \(tabs) tabs")
                #expect(layout.tileSize.width >= MacTerminalExposeLayout.minimumTileWidth)
            }
        }
        let one = MacTerminalExposeLayout(tileCounts: [1], in: CGSize(width: 1440, height: 760))
        #expect(one.tileSize.width == MacTerminalExposeLayout.maximumTileWidth, "one tab is shown large")
        let crowd = MacTerminalExposeLayout(tileCounts: Array(repeating: 32, count: 6), in: screen)
        #expect(crowd.scrolls && crowd.contentSize.height > screen.height)
        #expect(crowd.contentSize.width <= screen.width)
    }

    @Test("the same windows lay out the same way, every time")
    func layoutIsStable() {
        let size = CGSize(width: 1440, height: 760)
        let counts = [3, 1, 6, 2]
        #expect(MacTerminalExposeLayout(tileCounts: counts, in: size) == MacTerminalExposeLayout(tileCounts: counts, in: size))
        #expect(MacTerminalExposeLayout(tileCounts: [], in: size).groups.isEmpty)
        #expect(MacTerminalExposeLayout(tileCounts: [2], in: .zero).groups.isEmpty, "no space yet, nothing laid out")
    }

    @Test("groups follow the order the windows first appeared, whatever their ids")
    func groupsKeepWindowOrder() async throws {
        try await withDefaults { defaults in
            // Ids chosen so that sorting them would reverse the order the windows appeared in.
            let late = window(defaults, tabs: 1, request: MacWorkspaceLaunchRequest(
                workspaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
            let early = window(defaults, tabs: 2, request: MacWorkspaceLaunchRequest(
                workspaceID: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!))
            let shownEarly = show(early), shownLate = show(late)
            defer {
                MacWorkspacePreviewRegistry.shared.remove(early.windowID)
                MacWorkspacePreviewRegistry.shared.remove(late.windowID)
            }
            let ours = MacWorkspacePreviewRegistry.shared.shownWindows.map(\.controller.windowID)
                .filter { [early.windowID, late.windowID].contains($0) }
            #expect(ours == [early.windowID, late.windowID])
            let groups = MacTerminalExposeModel.groups(windows: [early, late], servers: [], home: "/home/alpha")
            #expect(groups.map(\.id) == [.window(early.windowID), .window(late.windowID)])
            #expect(groups[0].tiles.map(\.id) == early.tabs.map { .tab($0.workspaceID) }, "a tile per tab, in tab order")
            withExtendedLifetime((shownEarly, shownLate)) {}
        }
    }

    // MARK: Keyboard

    @Test("arrows move between tiles across groups, on screen")
    func navigatingAcrossGroups() {
        // Two groups of two by two side by side, a third below.
        func frame(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 100, height: 60) }
        let items: [(id: String, frame: CGRect)] = [
            ("a1", frame(0, 0)), ("a2", frame(110, 0)), ("a3", frame(0, 70)), ("a4", frame(110, 70)),
            ("b1", frame(300, 0)), ("b2", frame(410, 0)), ("b3", frame(300, 70)), ("b4", frame(410, 70)),
            ("c1", frame(0, 200)), ("c2", frame(110, 200)),
        ]
        func move(_ from: String?, _ direction: MacTerminalExposeNavigation.Direction) -> String? {
            MacTerminalExposeNavigation.moved(from, direction, in: items)
        }
        #expect(move("a2", .right) == "b1", "out of one window's group into the next")
        #expect(move("b1", .left) == "a2")
        #expect(move("a4", .right) == "b3")
        #expect(move("a3", .down) == "c1", "down into the row of groups below")
        #expect(move("c2", .up) == "a4", "up to the nearest tile above")
        #expect(move("b4", .down) == "c2", "the nearest in the row below")
        #expect(move("b4", .right) == "c1", "past the end of a row, on in reading order")
        #expect(move("c1", .left) == "b4")
        #expect(move("a1", .left) == "a1" && move("a1", .up) == "a1" && move("c2", .right) == "c2", "edges stay")
        #expect(move(nil, .right) == "a1" && move("gone", .down) == "a1", "nothing selected starts at the first")
        #expect(MacTerminalExposeNavigation.moved(String?.none, .left, in: [(id: String, frame: CGRect)]()) == nil)
    }

    @Test("right arrow reaches the next window's tiles in a real layout")
    func navigatingTheLaidOutScreen() {
        let counts = [2, 2]
        let layout = MacTerminalExposeLayout(tileCounts: counts, in: CGSize(width: 1440, height: 760))
        let ids = [["a1", "a2"], ["b1", "b2"]]
        let items = zip(ids, layout.groups).flatMap { names, group in zip(names, group.tileFrames).map { (id: $0, frame: $1) } }
        #expect(layout.groups[0].row == layout.groups[1].row, "two small windows share a row")
        #expect(MacTerminalExposeNavigation.moved("a1", .right, in: items) == "b1")
        #expect(MacTerminalExposeNavigation.moved("b1", .left, in: items) == "a1")
    }

    // MARK: Filtering

    @Test("typing narrows the tiles by name or folder, ignoring case and accents")
    func filtering() {
        let groups = [
            MacTerminalExposeGroup(id: .window(UUID()), title: "Work", tiles: [
                MacTerminalExposeTile(id: .tab(UUID()), title: "build", folder: "~/src/app"),
                MacTerminalExposeTile(id: .tab(UUID()), title: "Claude Code", folder: "~/notes"),
            ]),
            MacTerminalExposeGroup(id: .window(UUID()), title: "Café", tiles: [
                MacTerminalExposeTile(id: .tab(UUID()), title: "café menu", folder: "/srv/www"),
            ]),
            MacTerminalExposeModel.notInAWindowGroup([TerminalTmux.Session(name: "glass-3", attachedClients: 0, windows: 1)])!,
        ]
        func titles(_ text: String) -> [String] {
            MacTerminalExposeModel.filtered(groups, by: text).flatMap(\.tiles).map(\.title)
        }
        #expect(titles("").count == 4 && titles("   ").count == 4, "nothing typed hides nothing")
        #expect(titles("app") == ["build"], "by folder")
        #expect(titles("NOTES") == ["Claude Code"], "by folder, any case")
        #expect(titles("claude") == ["Claude Code"], "by name")
        #expect(titles("cafe") == ["café menu"], "accents ignored")
        #expect(titles("www") == ["café menu"])
        #expect(titles("glass-3") == [MacWorkspaceTabNaming.tmuxDisplayName("glass-3")], "a session by its own name too")
        #expect(MacTerminalExposeModel.filtered(groups, by: "app").map(\.title) == ["Work"], "groups with nothing left go")
        #expect(MacTerminalExposeModel.filtered(groups, by: "zzz").isEmpty)

        // Return is never aimed at a tile the filter hid.
        let claude = groups[0].tiles[1].id
        let shown = MacTerminalExposeModel.filtered(groups, by: "app").flatMap(\.tiles).map(\.id)
        #expect(MacTerminalExposeModel.selection(claude, shown: shown) == groups[0].tiles[0].id)
        #expect(MacTerminalExposeModel.selection(claude, shown: groups.flatMap(\.tiles).map(\.id)) == claude, "kept while shown")
        #expect(MacTerminalExposeModel.selection(claude, shown: []) == nil)
    }

    @Test("a tab's tile is named as its sidebar row is, with the folder its pane is in")
    func tabTiles() async throws {
        try await withDefaults { defaults in
            let tab = MacWorkspaceController(request: MacWorkspaceTabRequest(startsEmpty: false, initialPaneIntent: .local),
                                             defaults: defaults)
            tab.paneContextInterval = .zero
            let pane = try #require(tab.focusedPaneID)
            tab.updatePaneContext(title: nil, directory: "/home/alpha/src/app", for: pane)
            let tile = MacTerminalExposeModel.tile(for: tab, servers: [], home: "/home/alpha")
            #expect(tile.title == tab.windowIdentity(servers: [], home: "/home/alpha").title)
            #expect(tile.title == "app")
            #expect(tile.folder == "~/src/app")
            #expect(tile.matches("src") && !tile.isBusy)
        }
    }

    // MARK: Acting

    @Test("choosing a tile selects that tab and brings its window forward")
    func choosing() async throws {
        try await withDefaults { defaults in
            let first = window(defaults, tabs: 1), second = window(defaults, tabs: 3)
            let shownFirst = show(first), shownSecond = show(second)
            defer {
                MacWorkspacePreviewRegistry.shared.remove(first.windowID)
                MacWorkspacePreviewRegistry.shared.remove(second.windowID)
            }
            let expose = MacTerminalExpose()
            var brought: [NSWindow] = []
            expose.bringForward = { brought.append($0) }
            let target = second.tabs[0].workspaceID
            let firstSelection = first.selectedTabID
            #expect(second.selectedTabID != target)

            expose.choose(.tab(target))
            #expect(second.selectedTabID == target, "that tab is the window's selected tab")
            #expect(brought.count == 1 && brought.first === shownSecond, "and its window, only, is asked forward")
            #expect(first.selectedTabID == firstSelection)

            expose.choose(.tab(UUID()))
            #expect(brought.count == 1, "a tab no window holds brings nothing forward")
            withExtendedLifetime((shownFirst, shownSecond)) {}
        }
    }

    /// No real tmux runs here: names come from the fake server, and runtimes are made without
    /// starting (rule 63).
    @Test("dropping a tile on another window's group moves the tab: same tab, same terminal, same session")
    func dropping() async throws {
        try await withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            defaults.set(true, forKey: UserDefaultsKeys.localTmux)
            let sessionManager = SessionManager(loadImmediately: false)

            let source = window(defaults, tabs: 2), destination = window(defaults, tabs: 1)
            let shownSource = show(source), shownDestination = show(destination)
            defer {
                MacWorkspacePreviewRegistry.shared.remove(source.windowID)
                MacWorkspacePreviewRegistry.shared.remove(destination.windowID)
                for controller in [source, destination] { controller.closeAllSessions(sessionManager: sessionManager) }
            }
            let tab = source.tabs[1]
            let pane = try #require(tab.focusedPaneID)
            let name = try #require(tab.localTmuxSession(for: pane))
            let runtime = try #require(tab.localRuntime(for: pane))
            let shownBefore = MacLocalTmux.shownHere[name, default: 0]

            let expose = MacTerminalExpose()
            let drag = MacWorkspaceTabDrag(windowID: source.windowID, workspaceID: tab.workspaceID)
            #expect(!expose.drop(drag, onto: source.windowID), "on its own group, nothing moves")
            #expect(source.tabs.map(\.workspaceID).last == tab.workspaceID)

            #expect(expose.drop(drag, onto: destination.windowID))
            #expect(!source.tabs.contains { $0.workspaceID == tab.workspaceID }, "gone from the window it left")
            #expect(destination.tabs.last === tab, "the very tab")
            #expect(destination.tabs.last?.localRuntime(for: pane) === runtime, "its terminal, still running, not a new one")
            #expect(destination.tabs.last?.localTmuxSession(for: pane) == name, "its session")
            #expect(MacLocalTmux.shownHere[name, default: 0] == shownBefore, "no second client")
            #expect(expose.selection == .tab(tab.workspaceID), "the selection follows the tile")
            #expect(!expose.drop(drag, onto: UUID()), "a window that is gone takes nothing")
            withExtendedLifetime((shownSource, shownDestination)) {}
        }
    }

    @Test("Not in a window lists exactly the running tmux sessions no tab shows")
    func notInAWindow() async throws {
        try await withDefaults { defaults in
            let fake = MacLocalTmuxTests.FakeServer()
            let previous = MacLocalTmux.server
            MacLocalTmux.server = fake.server
            defer { MacLocalTmux.server = previous }
            fake.running = ["w9-shown", "w9-detached", "w9-elsewhere", "glass-907"]

            var intent = MacWorkspacePaneIntent.local
            intent.localTmuxSession = "w9-shown"
            let shown = window(defaults, tabs: 1, request: MacWorkspaceLaunchRequest(initialPaneIntent: intent))
            let shownWindow = show(shown)
            defer { MacWorkspacePreviewRegistry.shared.remove(shown.windowID) }

            let expose = MacTerminalExpose()
            await expose.refreshUnshownSessions()
            #expect(expose.unshownSessions.map(\.name) == ["glass-907", "w9-detached", "w9-elsewhere"],
                    "Glass's own first, as Active lists them; the one a tab shows is left out")
            let group = try #require(MacTerminalExposeModel.notInAWindowGroup(expose.unshownSessions))
            #expect(group.title == "Not in a window")
            #expect(group.tiles.map(\.id) == [.tmux("glass-907"), .tmux("w9-detached"), .tmux("w9-elsewhere")])
            #expect(group.tiles[0].title == MacWorkspaceTabNaming.tmuxDisplayName("glass-907"))

            fake.running = ["w9-shown"]
            await expose.refreshUnshownSessions()
            #expect(expose.unshownSessions.isEmpty)
            #expect(MacTerminalExposeModel.notInAWindowGroup(expose.unshownSessions) == nil, "no sessions, no group")
            withExtendedLifetime(shownWindow) {}
        }
    }

    @Test("Reopen opens the session as Active's This Mac does: a window, a tab, attached to it")
    func reopening() {
        let expose = MacTerminalExpose()
        var opened: [MacWorkspaceLaunchRequest] = []
        expose.context = .init(sessionManager: SessionManager(loadImmediately: false),
                               settingsManager: SettingsManager(loadImmediately: false,
                                                                settingsDefaults: UserDefaults.forTest(suiteName: "MacTerminalExposeTests.\(UUID())"),
                                                                sshKeyDefaults: UserDefaults.forTest(suiteName: "MacTerminalExposeTests.\(UUID())"))) {
            opened.append($0)
        }
        expose.choose(.tmux("glass-4"))
        #expect(opened.count == 1)
        #expect(opened.first?.tabs.count == 1)
        let intent = opened.first?.tabs.first?.initialPaneIntent
        #expect(intent?.kind == .local && intent?.localTmuxSession == "glass-4", "attached to that session, on this Mac")
        #expect(intent == MacLocalTmuxLaunchOffer.launchRequests(for: ["glass-4"]).first?.tabs.first?.initialPaneIntent,
                "the tab the launch offer and Active open, not one of its own")
        #expect(!expose.isShown)
    }

    // MARK: Opening it

    @Test("a small pinch does not open it; a deliberate one does, once per gesture")
    func pinchThreshold() {
        var pinch = MacTerminalExposePinch()
        #expect(pinch.track(-0.05, phase: .began) == nil)
        for _ in 0..<4 { #expect(pinch.track(-0.05, phase: .changed) == nil) }
        #expect(pinch.track(-0.02, phase: .ended) == nil, "a quarter of the way is ordinary use")

        #expect(pinch.track(-0.04, phase: .began) == nil, "a new gesture starts from nothing")
        for _ in 0..<3 { #expect(pinch.track(0.05, phase: .changed) == nil) }
        for _ in 0..<3 { #expect(pinch.track(-0.05, phase: .changed) == nil) }
        #expect(pinch.track(0, phase: .ended) == nil, "a wobble in and out adds up to nothing")

        #expect(pinch.track(-0.1, phase: .began) == nil)
        #expect(pinch.track(-0.1, phase: .changed) == nil)
        #expect(pinch.track(-0.15, phase: .changed) == .pinchedIn)
        #expect(pinch.track(-0.3, phase: .changed) == nil, "one answer per gesture")
        #expect(pinch.track(0, phase: .ended) == nil)

        #expect(pinch.track(0.2, phase: .began) == nil)
        #expect(pinch.track(0.15, phase: .changed) == .pinchedOut)
        #expect(pinch.track(.nan, phase: .changed) == nil)
    }

    /// AppKit's View ▸ Show All Tabs carries ⇧⌘\ for windows that allow native tabs; the menu
    /// item that owns it here must keep it (rule 39).
    @Test("AppKit's Show All Tabs gives up ⇧⌘\\, and only it")
    func appKitTabOverviewLetsGoOfTheKey() {
        let main = NSMenu(title: "Main")
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            for item in items { menu.addItem(item) }
            main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        let appKit = item("Show All Tabs", #selector(NSWindow.toggleTabOverview(_:)), "\\", [.command, .shift])
        let tabBar = item("Show Tab Bar", #selector(NSWindow.toggleTabBar(_:)), "", [])
        let ours = item("Show All Terminals", #selector(NSApplication.arrangeInFront(_:)), "\\", [.command, .shift])
        let otherKey = item("Show All Tabs", #selector(NSWindow.toggleTabOverview(_:)), "t", [.command, .option])
        menu("View", [tabBar, appKit])
        menu("Window", [ours, otherKey])

        #expect(MacTerminalExposeShortcut.release(in: main) == 1)
        #expect(appKit.keyEquivalent.isEmpty && appKit.keyEquivalentModifierMask.isEmpty, "AppKit's item lets go")
        #expect(ours.keyEquivalent == "\\" && ours.keyEquivalentModifierMask == [.command, .shift], "ours keeps it")
        #expect(otherKey.keyEquivalent == "t", "only ⇧⌘\\ is taken")
        #expect(MacTerminalExposeShortcut.release(in: main) == 0)
    }
}
}
#endif
