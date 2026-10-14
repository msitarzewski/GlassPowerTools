//
//  MacTerminalExpose.swift
//  Glass Power Tools — GlassTerminal
//
//  Show All Windows — Show All Terminals until 2026-10-13 (W9; the owner, 2026-10-08: "Mission
//  Control / Exposé for Terminal windows *and their tabs* like macOS does"). Every terminal window
//  becomes a group of live tiles, one per tab, on a dimmed, blurred screen above the app's windows.
//  Choosing a tile brings its window forward on that tab; dragging a tile onto another group moves
//  the tab there, still running. Since 2026-10-13 every other open window joins it, a group per
//  kind — Databases, Desktops, Editor — from the shell's list of open sessions (`GlassShowAllWindows`).
//
//  Opened by ⇧⌘\ (Safari's Show All Tabs), Window ▸ Show All Terminals, a toolbar button in
//  Connections and in every terminal window, and a two-finger pinch in on a terminal window. A
//  three-finger swipe was the owner's first idea; macOS takes those for Mission Control before any
//  app sees them, and the pinch is Safari's gesture for its own tab overview.
//
//  It shows images and moves tabs. It never types into a terminal and never resizes one.
//

#if os(macOS)
import AppKit
import Observation
import SwiftUI
import GlassShell

// MARK: What it shows

/// A tile: a tab of a terminal window, a tmux session on this Mac that no tab shows, or another
/// capability's open window — a desktop, a database, an editor — by its `GlassOpenSession` id.
enum MacTerminalExposeItemID: Hashable {
    case tab(UUID)
    case tmux(String)
    case session(String)
}

struct MacTerminalExposeTile: Identifiable, Equatable {
    let id: MacTerminalExposeItemID
    /// The tab's name, as its sidebar row says it; a session's, as Active says it.
    let title: String
    /// Where the tab's focused pane stands, as a person writes it.
    var folder: String?
    /// In a repository, its name, branch and the folder inside it, as the tab's second line says
    /// them (W11): what the caption shows in place of the folder. Typing either finds the tab.
    var repository: String? = nil
    /// What a tmux session is doing: detached, how many windows, when it was last used.
    var detail: String?
    /// Output arrived in the last moment: the tile carries the sidebar's activity wave.
    var isBusy = false
    /// The tmux session's own name, so "glass-3" finds "Terminal 3".
    var sessionName: String?
    /// Another capability's window: its symbol, where it has no picture.
    var symbolName: String?
    /// The AI agent the tab's focused pane, or the tmux session, is running: its logo sits in the
    /// middle of the tile (2026-10-14).
    var agent: TerminalAgent? = nil

    /// The line under the name: the repository's, else the folder.
    var location: String? { repository ?? folder }

    func matches(_ query: String) -> Bool {
        [title, repository, folder, sessionName].compactMap { $0 }.contains { $0.localizedStandardContains(query) }
    }
}

struct MacTerminalExposeGroup: Identifiable, Equatable {
    enum ID: Hashable {
        case window(UUID)
        case notInAWindow
        /// Another capability's windows, by the kind in their session ids ("desktop").
        case kind(String)
    }

    let id: ID
    let title: String
    var tiles: [MacTerminalExposeTile]
}

@MainActor
enum MacTerminalExposeModel {
    static let notInAWindowTitle = "Not in a window"

    /// One group per window, in the order given, each titled the way its window is: the
    /// workgroup's name, else the selected tab's.
    static func groups(windows: [MacWorkspaceWindowController], servers: [ServerConfiguration],
                       home: String? = NSHomeDirectory()) -> [MacTerminalExposeGroup] {
        windows.map { window in
            let selected = window.selectedTab
            return MacTerminalExposeGroup(
                id: .window(window.windowID),
                title: selected.workgroupName ?? selected.windowIdentity(servers: servers, home: home).title,
                tiles: window.tabs.map { tile(for: $0, servers: servers, home: home) })
        }
    }

    static func tile(for tab: MacWorkspaceController, servers: [ServerConfiguration],
                     home: String? = NSHomeDirectory()) -> MacTerminalExposeTile {
        MacTerminalExposeTile(id: .tab(tab.workspaceID),
                              title: tab.windowIdentity(servers: servers, home: home).title,
                              folder: folder(of: tab, home: home),
                              repository: repositoryLocation(of: tab, home: home),
                              isBusy: tab.isProducingOutput,
                              agent: tab.focusedAgent)
    }

    /// The focused pane's folder. A local one under the home folder is written `~/…`; a remote
    /// one too when the host said its home (in tmux, W19), else as its shell reported it.
    static func folder(of tab: MacWorkspaceController, home: String?) -> String? {
        guard let pane = tab.focusedPane else { return nil }
        let context = tab.paneContextByPaneID[pane.id]
        let reported = context?.directory
        switch pane.intent.kind {
        case .local:
            return (reported ?? tab.localDirectory(for: pane.id)).map { MacWorkspaceTabNaming.abbreviated($0, home: home) }
        case .ssh:
            return reported.map { MacWorkspaceTabNaming.abbreviated($0, home: context?.home) }
        }
    }

    /// In a repository, where the focused pane is as the tab's second line says it:
    /// `app · main · Sources` (W11). Nil outside one.
    static func repositoryLocation(of tab: MacWorkspaceController, home: String?) -> String? {
        guard let pane = tab.focusedPane, let repository = tab.repositoryByPaneID[pane.id] else { return nil }
        let directory = pane.intent.kind == .local
            ? tab.paneContextByPaneID[pane.id]?.directory ?? tab.localDirectory(for: pane.id) : nil
        return TerminalSessionNaming.location(directory: directory, home: home, repository: repository)
    }

    /// This Mac's running tmux sessions that no tab shows: Active's This Mac list, less any a
    /// window is still opening (`MacLocalTmuxLaunchOffer.shownSessions`).
    static func notInAWindow(_ sessions: [TerminalTmux.Session], shown: Set<String>) -> [TerminalTmux.Session] {
        MacLocalTmux.listable(sessions).filter { !shown.contains($0.name) }
    }

    /// Nil when there is nothing to list, so the group is not drawn at all.
    static func notInAWindowGroup(_ sessions: [TerminalTmux.Session]) -> MacTerminalExposeGroup? {
        guard !sessions.isEmpty else { return nil }
        return MacTerminalExposeGroup(id: .notInAWindow, title: notInAWindowTitle, tiles: sessions.map { session in
            MacTerminalExposeTile(id: .tmux(session.name),
                                  title: MacWorkspaceTabNaming.tmuxDisplayName(session.name),
                                  detail: GlassTerminalCapability.runningDetails(session),
                                  sessionName: session.name,
                                  agent: TerminalAgent.identify(program: session.command, arguments: nil,
                                                                title: session.title))
        })
    }

    /// Every other open window, a group per kind — the terminal's Files browsers, then the setup's
    /// order: Databases, Desktops, then the editor's — each window a tile. The terminal's tabs are
    /// their windows' groups (`MacTerminalExpose.otherSessions` leaves them out).
    static func otherGroups(_ sessions: [GlassOpenSession]) -> [MacTerminalExposeGroup] {
        let kinds: [(prefix: String, title: String)] = [("terminal-session", "Files"), ("database", "Databases"),
                                                         ("desktop", "Desktops"), ("editor", "Editor")]
        let known = Set(kinds.map(\.prefix) + ["terminal"])
        let groups = kinds.compactMap { kind -> MacTerminalExposeGroup? in
            let tiles = sessions.filter { GlassShowAllWindows.kind(of: $0) == kind.prefix }.map(tile(for:))
            return tiles.isEmpty ? nil : MacTerminalExposeGroup(id: .kind(kind.prefix), title: kind.title, tiles: tiles)
        }
        // A kind added later still shows, under its sessions' own word, rather than going missing.
        let others = sessions.filter { !known.contains(GlassShowAllWindows.kind(of: $0) ?? "") }
        return others.isEmpty ? groups : groups + [MacTerminalExposeGroup(id: .kind("other"), title: "Other", tiles: others.map(tile(for:)))]
    }

    static func tile(for session: GlassOpenSession) -> MacTerminalExposeTile {
        MacTerminalExposeTile(id: .session(session.id), title: session.title, detail: session.subtitle,
                              symbolName: session.symbolName)
    }

    /// The selection, kept while its tile is shown; else the first tile shown. Typing or a window
    /// closing never leaves Return aimed at something hidden.
    static func selection(_ selection: MacTerminalExposeItemID?,
                          shown ids: [MacTerminalExposeItemID]) -> MacTerminalExposeItemID? {
        if let selection, ids.contains(selection) { return selection }
        return ids.first
    }

    /// Typing narrows the tiles to those whose name or folder contains what was typed, ignoring
    /// case and accents. A group with nothing left is not drawn.
    static func filtered(_ groups: [MacTerminalExposeGroup], by text: String) -> [MacTerminalExposeGroup] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            var narrowed = group
            narrowed.tiles = group.tiles.filter { $0.matches(query) }
            return narrowed.tiles.isEmpty ? nil : narrowed
        }
    }
}

// MARK: Layout

/// Packs the groups onto the screen the way Mission Control does: every tile the same size, as
/// large as fits, groups flowing left to right in the order given, rows centred. Only when even
/// the smallest tiles cannot fit does it fall back to scrolling. Pure arithmetic, so it is tested
/// without a screen.
struct MacTerminalExposeLayout: Equatable {
    struct Group: Equatable {
        /// The group's box, with its title and tiles inside it.
        let frame: CGRect
        let titleFrame: CGRect
        let tileFrames: [CGRect]
        /// Which row of groups it is in, counted from the top.
        let row: Int
    }

    private(set) var groups: [Group] = []
    /// The space the groups take: the size given, or taller when it scrolls.
    private(set) var contentSize: CGSize = .zero
    private(set) var scrolls = false
    private(set) var tileSize: CGSize = .zero

    /// A tab's tile has the in-window overview's proportions (`MacWorkspacePreview`).
    static let aspectRatio: CGFloat = 1.6
    static let padding: CGFloat = 14
    static let titleHeight: CGFloat = 30
    static let tileSpacing: CGFloat = 14
    static let groupSpacing: CGFloat = 26
    static let minimumTileWidth: CGFloat = 160
    static let maximumTileWidth: CGFloat = 600
    /// How wide a group leans: its columns are about √(tiles × bias). The widest tiles win.
    private static let biases: [Double] = [0.5, 1, 1.5, 2, 3, 4, 6, 9, 16]

    init(tileCounts: [Int], in size: CGSize) {
        let counts = tileCounts.map { max(1, $0) }
        guard !counts.isEmpty, size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return }
        var best: (width: CGFloat, columns: [Int])?
        for bias in Self.biases {
            let columns = counts.map { Self.columns(for: $0, bias: bias) }
            guard let width = Self.largestWidth(counts: counts, columns: columns, in: size) else { continue }
            if best.map({ width > $0.width + 0.5 }) ?? true { best = (width, columns) }
        }
        if let best {
            place(counts: counts, columns: best.columns, tileWidth: best.width, in: size, scrolls: false)
            return
        }
        // Too many for one screen: the smallest tiles, groups as wide as the screen allows, and
        // the whole arrangement scrolls.
        let usable = size.width - 2 * Self.padding
        let tileWidth = max(1, min(Self.minimumTileWidth, usable))
        let fitting = max(1, Int((usable + Self.tileSpacing) / (tileWidth + Self.tileSpacing)))
        place(counts: counts, columns: counts.map { min($0, fitting) }, tileWidth: tileWidth, in: size, scrolls: true)
    }

    static func columns(for count: Int, bias: Double) -> Int {
        min(count, max(1, Int(ceil(sqrt(Double(count) * bias)))))
    }

    static func groupSize(count: Int, columns: Int, tileWidth: CGFloat) -> CGSize {
        let rows = Int(ceil(Double(count) / Double(columns)))
        let tileHeight = tileWidth / aspectRatio
        return CGSize(width: 2 * padding + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * tileSpacing,
                      height: 2 * padding + titleHeight + CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing)
    }

    /// Groups in rows, in order: a group starts a new row when it would not fit beside the last.
    private static func rows(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if let last = rows.indices.last, used + groupSpacing + size.width <= width {
                rows[last].append(index)
                used += groupSpacing + size.width
            } else {
                rows.append([index])
                used = size.width
            }
        }
        return rows
    }

    private static func height(of rows: [[Int]], _ sizes: [CGSize]) -> CGFloat {
        rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * groupSpacing
    }

    private static func fits(counts: [Int], columns: [Int], tileWidth: CGFloat, in size: CGSize) -> Bool {
        let sizes = zip(counts, columns).map { groupSize(count: $0, columns: $1, tileWidth: tileWidth) }
        guard sizes.allSatisfy({ $0.width <= size.width }) else { return false }
        return height(of: rows(sizes, width: size.width), sizes) <= size.height
    }

    /// The widest tile, between the minimum and the maximum, at which these columns fit.
    private static func largestWidth(counts: [Int], columns: [Int], in size: CGSize) -> CGFloat? {
        guard fits(counts: counts, columns: columns, tileWidth: minimumTileWidth, in: size) else { return nil }
        if fits(counts: counts, columns: columns, tileWidth: maximumTileWidth, in: size) { return maximumTileWidth }
        var low = minimumTileWidth, high = maximumTileWidth
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if fits(counts: counts, columns: columns, tileWidth: middle, in: size) { low = middle } else { high = middle }
        }
        return low
    }

    private mutating func place(counts: [Int], columns: [Int], tileWidth: CGFloat, in size: CGSize, scrolls: Bool) {
        let tileHeight = tileWidth / Self.aspectRatio
        let sizes = zip(counts, columns).map { Self.groupSize(count: $0, columns: $1, tileWidth: tileWidth) }
        let rows = Self.rows(sizes, width: size.width)
        let total = Self.height(of: rows, sizes)
        var frames = [CGRect](repeating: .zero, count: counts.count)
        var rowOf = [Int](repeating: 0, count: counts.count)
        var y = scrolls ? 0 : max(0, (size.height - total) / 2)
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.map { sizes[$0].width }.reduce(0, +) + CGFloat(row.count - 1) * Self.groupSpacing
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = max(0, (size.width - rowWidth) / 2)
            for index in row {
                frames[index] = CGRect(x: x, y: y + (rowHeight - sizes[index].height) / 2,
                                       width: sizes[index].width, height: sizes[index].height)
                rowOf[index] = rowIndex
                x += sizes[index].width + Self.groupSpacing
            }
            y += rowHeight + Self.groupSpacing
        }
        groups = frames.indices.map { index in
            let frame = frames[index]
            let tiles = (0..<counts[index]).map { tile in
                CGRect(x: frame.minX + Self.padding + CGFloat(tile % columns[index]) * (tileWidth + Self.tileSpacing),
                       y: frame.minY + Self.padding + Self.titleHeight + CGFloat(tile / columns[index]) * (tileHeight + Self.tileSpacing),
                       width: tileWidth, height: tileHeight)
            }
            return Group(frame: frame,
                         titleFrame: CGRect(x: frame.minX + Self.padding, y: frame.minY + Self.padding,
                                            width: frame.width - 2 * Self.padding, height: Self.titleHeight - 8),
                         tileFrames: tiles, row: rowOf[index])
        }
        contentSize = CGSize(width: size.width, height: scrolls ? max(size.height, total) : size.height)
        self.scrolls = scrolls
        tileSize = CGSize(width: tileWidth, height: tileHeight)
    }
}

// MARK: Keyboard

enum MacTerminalExposeNavigation {
    enum Direction { case left, right, up, down }

    /// Where an arrow key goes: to the nearest tile that way on screen, across groups. Left and
    /// right at the end of a row go on through the reading order, so every tile can be reached
    /// with them alone. `items` are in reading order; nothing selected selects the first.
    static func moved<ID: Hashable>(_ selection: ID?, _ direction: Direction,
                                    in items: [(id: ID, frame: CGRect)]) -> ID? {
        guard let first = items.first else { return nil }
        guard let selection, let index = items.firstIndex(where: { $0.id == selection }) else { return first.id }
        let current = items[index].frame
        switch direction {
        case .left, .right:
            let forward = direction == .right
            let row = items.filter { item in
                item.id != selection && item.frame.midY >= current.minY && item.frame.midY <= current.maxY
                    && (forward ? item.frame.midX > current.midX : item.frame.midX < current.midX)
            }
            if let next = row.min(by: { abs($0.frame.midX - current.midX) < abs($1.frame.midX - current.midX) }) {
                return next.id
            }
            let target = index + (forward ? 1 : -1)
            return items.indices.contains(target) ? items[target].id : selection
        case .up, .down:
            let candidates = items.filter { item in
                direction == .down ? item.frame.minY >= current.maxY - 0.5 : item.frame.maxY <= current.minY + 0.5
            }
            guard let nearest = candidates.map(\.frame.midY)
                .min(by: { abs($0 - current.midY) < abs($1 - current.midY) }) else { return selection }
            return candidates.filter { abs($0.frame.midY - nearest) < current.height / 2 }
                .min { abs($0.frame.midX - current.midX) < abs($1.frame.midX - current.midX) }?.id ?? selection
        }
    }
}

// MARK: Pinch

/// The pinch and its window monitor moved to the shell with Show All Windows (2026-10-13), so a
/// desktop's window opens the overview the same way (`GlassWindowPinch`). The terminal's names stay.
typealias MacTerminalExposePinch = GlassWindowPinch
typealias MacTerminalExposePinchMonitor = GlassWindowPinchMonitor

// MARK: ⇧⌘\

/// ⇧⌘\ has one owner: Window ▸ Show All Terminals (`TerminalLibraryCommands`).
///
/// AppKit can add a View ▸ Show All Tabs of its own on the same key, for windows that allow native
/// tabs (TextEdit's carries ⇧⌘\). The terminal's windows disallow them; the app's others may not.
/// Whether it appears in this app's menu bar was not seen when this was written — read the running
/// app's menu bar (rule 34). Two items on one key do not give the focused window a choice (rule 39),
/// so if it is there it is found by what it does, as `GlassCloseCommandRouter` finds Close, and
/// loses the key; it stays in the menu to be chosen.
@MainActor
enum MacTerminalExposeShortcut {
    static let key = "\\"
    static let modifiers: NSEvent.ModifierFlags = [.command, .shift]

    /// Takes ⇧⌘\ off the item if it is AppKit's Show All Tabs. True when it did.
    @discardableResult
    static func release(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(NSWindow.toggleTabOverview(_:)), item.keyEquivalent == key,
              item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers else { return false }
        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
        return true
    }

    /// Every such item in `menu` and its submenus; how many lost the key.
    @discardableResult
    static func release(in menu: NSMenu?) -> Int {
        guard let menu else { return 0 }
        return menu.items.reduce(0) { count, item in count + (release(item) ? 1 : 0) + release(in: item.submenu) }
    }

    private static var observers: [any NSObjectProtocol] = []

    /// AppKit adds its tab items when it chooses to, so the menu bar is looked at again whenever
    /// an item is added or changed, and as the app becomes active. A few hundred items, read.
    static func install() {
        guard observers.isEmpty else { return }
        let look: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { _ = release(in: NSApp?.mainMenu) }
        }
        observers = [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                     NSApplication.didBecomeActiveNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: look)
        }
        release(in: NSApp?.mainMenu)
    }
}

// MARK: The overlay

/// The overlay's own window: a borderless panel made and owned here, never a SwiftUI window
/// (rule 62). It can be key, so typing and arrows reach it, and never main.
final class MacTerminalExposePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor @Observable
final class MacTerminalExpose {
    static let shared: MacTerminalExpose = {
        MacTerminalExposeShortcut.install()
        return MacTerminalExpose()
    }()

    /// What the overlay draws with, from whichever window or menu opened it.
    struct Context {
        let sessionManager: SessionManager
        let settingsManager: SettingsManager
        /// Opens a terminal window: Reopen's, for a tmux session no tab shows.
        let openTerminalWindow: (MacWorkspaceLaunchRequest) -> Void

        init(sessionManager: SessionManager, settingsManager: SettingsManager,
             openTerminalWindow: @escaping (MacWorkspaceLaunchRequest) -> Void) {
            self.sessionManager = sessionManager
            self.settingsManager = settingsManager
            self.openTerminalWindow = openTerminalWindow
        }

        init(sessionManager: SessionManager, settingsManager: SettingsManager, openWindow: OpenWindowAction) {
            self.init(sessionManager: sessionManager, settingsManager: settingsManager) {
                openWindow(id: "workspace", value: $0)
            }
        }

        init(runtime: GlassTerminalRuntime, openWindow: OpenWindowAction) {
            self.init(sessionManager: runtime.sessionManager, settingsManager: runtime.settingsManager,
                      openWindow: openWindow)
        }
    }

    let registry: MacWorkspacePreviewRegistry
    private(set) var isShown = false
    /// Set as it goes, so the view zooms and fades out before the panel leaves.
    private(set) var isClosing = false
    /// What has been typed. Tiles whose name or folder do not contain it are hidden.
    var filter = ""
    var selection: MacTerminalExposeItemID?
    /// This Mac's tmux sessions that no tab shows, read as the overlay opens.
    private(set) var unshownSessions: [TerminalTmux.Session] = []

    /// Brings a window forward. Tests replace it; nothing else should.
    @ObservationIgnored var bringForward: @MainActor (NSWindow) -> Void = { window in
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    @ObservationIgnored private var panel: MacTerminalExposePanel?
    /// The opener's, kept while it is shown. Tests set it directly.
    @ObservationIgnored var context: Context?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(registry: MacWorkspacePreviewRegistry = .shared) {
        self.registry = registry
    }

    /// Something to show: a window, or the overlay itself to close.
    var isAvailable: Bool { isShown || !registry.shownWindows.isEmpty || !otherSessions.isEmpty }

    /// Every open window that is not already a tab here (`GlassShowAllWindows.openSessions`), read
    /// when asked. A terminal shows as its window's tab: a workgroup ("terminal:") always, and a
    /// terminal in no workgroup ("terminal-session:") when a window's tab shows it — listed again
    /// under Other it was a pale copy of the tab (the owner, 2026-10-13: "why isn't this window in
    /// the workgroup, and why is it that color?"). One no tab shows is a Files browser, a window of
    /// its own.
    var otherSessions: [GlassOpenSession] {
        (GlassShowAllWindows.openSessions?() ?? []).filter { session in
            switch GlassShowAllWindows.kind(of: session) {
            case "terminal":
                return false
            case "terminal-session":
                let id = session.id.split(separator: ":", maxSplits: 1).last.flatMap { UUID(uuidString: String($0)) }
                return id.map { !registry.shows(sessionID: $0) } ?? false
            default:
                return true
            }
        }
    }

    func toggle(_ context: Context) {
        isShown ? close() : show(context)
    }

    /// Over the key window's screen, above the app's windows.
    func show(_ context: Context) {
        if isShown {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow
        guard let screen = keyWindow?.screen ?? NSScreen.main else { return }
        self.context = context
        filter = ""
        selection = initialSelection(keyWindow: keyWindow)
        isClosing = false
        isShown = true
        let panel = makePanel(on: screen, context: context)
        self.panel = panel
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = Self.duration
            panel.animator().alphaValue = 1
        }
        observe(panel)
        Task { await refreshUnshownSessions() }
    }

    func close(animated: Bool = true) {
        guard isShown else { return }
        isShown = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        withAnimation(.easeIn(duration: Self.duration)) { isClosing = true }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = Self.duration
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.duration))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// A tab: its window comes forward on it. A session no tab shows: it is reopened.
    func choose(_ id: MacTerminalExposeItemID) {
        switch id {
        case .tab(let workspaceID):
            guard let shown = registry.shownWindows.first(where: { shown in
                shown.controller.tabs.contains { $0.workspaceID == workspaceID }
            }) else { return }
            shown.controller.select(workspaceID)
            close()
            bringForward(shown.window)
        case .tmux(let name):
            reopen(name)
        case .session(let id):
            guard let session = otherSessions.first(where: { $0.id == id }) else { return }
            close()
            session.activate()
        }
    }

    /// A tile dropped on another window's group: the tab moves there with its terminals running,
    /// by the sidebar's own move (`acceptDroppedTab`). Dropped on its own window, nothing happens.
    @discardableResult
    func drop(_ drag: MacWorkspaceTabDrag, onto windowID: UUID) -> Bool {
        guard drag.windowID != windowID, let destination = registry.shownController(windowID: windowID),
              destination.acceptDroppedTab(drag, at: destination.tabs.count) else { return false }
        selection = .tab(drag.workspaceID)
        return true
    }

    /// Several tabs dragged together move together, all or none, in the order they were dragged,
    /// as a drop on a window's own tab list takes them.
    @discardableResult
    func drop(_ drags: [MacWorkspaceTabDrag], onto windowID: UUID) -> Bool {
        let moving = drags.filter { $0.windowID != windowID }
        guard let first = moving.first, let destination = registry.shownController(windowID: windowID),
              destination.acceptDroppedTabs(moving, at: destination.tabs.count) else { return false }
        selection = .tab(first.workspaceID)
        return true
    }

    /// A tab attached to the session, in a window of its own, as Active's This Mac opens one.
    func reopen(_ name: String) {
        guard let context, let request = MacLocalTmuxLaunchOffer.launchRequests(for: [name]).first else { return }
        close()
        context.openTerminalWindow(request)
    }

    /// Asks tmux off the main thread; an unreadable answer lists nothing.
    func refreshUnshownSessions() async {
        let server = MacLocalTmux.server
        guard let tmux = server.executablePath() else {
            unshownSessions = []
            return
        }
        let output = await Task.detached(priority: .userInitiated) { server.listSessions(tmux) }.value
        // Each with the repository its folder is in, read here, as Active lists them (W11).
        let listed = MacLocalTmux.sessions(from: output)
        let home = NSHomeDirectory()
        let sessions = await Task.detached(priority: .userInitiated) {
            MacLocalTmux.readingRepositories(listed, home: home, read: server.readRepository)
        }.value
        unshownSessions = MacTerminalExposeModel.notInAWindow(
            sessions, shown: MacLocalTmuxLaunchOffer.shownSessions(registry: registry))
    }

    /// The tab the window underneath was showing, so Return goes straight back to it.
    private func initialSelection(keyWindow: NSWindow?) -> MacTerminalExposeItemID? {
        let windows = registry.shownWindows
        let under = windows.first { $0.window === keyWindow } ?? windows.first
        return under.map { .tab($0.controller.selectedTabID) }
    }

    private static var duration: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.2
    }

    private func makePanel(on screen: NSScreen, context: Context) -> MacTerminalExposePanel {
        let panel = MacTerminalExposePanel(contentRect: screen.frame, styleMask: [.borderless],
                                           backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.onCancel = { [weak self] in self?.close() }
        // Clear of the menu bar and the Dock, which stay above it.
        let frame = screen.frame, visible = screen.visibleFrame
        let insets = EdgeInsets(top: frame.maxY - visible.maxY, leading: visible.minX - frame.minX,
                                bottom: visible.minY - frame.minY, trailing: frame.maxX - visible.maxX)
        let host = NSHostingView(rootView: MacTerminalExposeView(expose: self, insets: insets)
            .environment(context.settingsManager)
            .environment(context.sessionManager)
            // Not inside a scene: the previews refresh only while the scene is active.
            .environment(\.scenePhase, .active))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    /// Gone when the app is left, or when another of its windows takes the keyboard.
    private func observe(_ panel: MacTerminalExposePanel) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(animated: false) }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                // Once the new key window is known: a drag or a menu takes it for nobody.
                Task { @MainActor in
                    guard let key = NSApp.keyWindow, key !== panel else { return }
                    self?.close()
                }
            },
        ]
    }
}
#endif
