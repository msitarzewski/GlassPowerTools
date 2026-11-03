#if os(macOS)
#if os(macOS)
import AppKit
import Observation
import GlassTerminalEmulator
import GlassShell
import GlassLayers
import SwiftUI

/// Discovery only: windows remain the sole owners of their sessions and tabs.
@MainActor @Observable
final class MacWorkspacePreviewRegistry {
    static let shared = MacWorkspacePreviewRegistry()
    private final class Entry {
        weak var controller: MacWorkspaceWindowController?
        /// Nil once it has closed: a closed window is never shown or brought forward again.
        var window: NSWindow? {
            guard let window = registered, !MacTerminalWindowReader.hasClosed(window) else { return nil }
            return window
        }
        private weak var registered: NSWindow?
        /// When the window was first found, for an order that does not change while it is open.
        let order: Int
        init(_ controller: MacWorkspaceWindowController, window: NSWindow, order: Int) {
            self.controller = controller
            self.registered = window
            self.order = order
        }
    }
    @ObservationIgnored private var nextOrder = 0
    private final class Built {
        weak var controller: MacWorkspaceWindowController?
        init(_ controller: MacWorkspaceWindowController) { self.controller = controller }
    }
    private var entries: [UUID: Entry] = [:]
    /// Every window controller made, by window id, held weakly. A window's view asks here before
    /// making one, because SwiftUI runs its init again (2026-10-08): a scene update handing it an
    /// equal request made a second controller, a twin of the window that restored its tabs, and a
    /// tab dragged out of the window was sometimes taken from the twin. Ignored by observation,
    /// since views read it while they are being made.
    @ObservationIgnored private var built: [UUID: [Built]] = [:]
    /// A window was found on screen or closed. The reopen list follows it, so it is current
    /// without a quit (`MacWindowsToReopen`, W12).
    @ObservationIgnored var windowsChanged: (() -> Void)?
    /// How each window adds a tab asked for from outside it, as "+" adds one (D72): set by the
    /// window's view, which starts the tab's shells.
    @ObservationIgnored private var tabAdders: [UUID: @MainActor (MacWorkspaceTabRequest) -> Bool] = [:]

    func setTabAdder(windowID: UUID, _ adder: @escaping @MainActor (MacWorkspaceTabRequest) -> Bool) {
        tabAdders[windowID] = adder
    }

    /// The terminal window in front — the first in the app's window order — and how to add a tab
    /// to it: "New Glass Power Tools Tab Here" in the Finder. Nil with none on screen.
    func frontTabAdder() -> (window: NSWindow, add: @MainActor (MacWorkspaceTabRequest) -> Bool)? {
        var byWindow: [ObjectIdentifier: (NSWindow, @MainActor (MacWorkspaceTabRequest) -> Bool)] = [:]
        for (id, entry) in entries {
            guard let window = entry.window, let adder = tabAdders[id] else { continue }
            byWindow[ObjectIdentifier(window)] = (window, adder)
        }
        for window in NSApp.orderedWindows where window.isVisible || window.isMiniaturized {
            if let found = byWindow[ObjectIdentifier(window)] { return (found.0, found.1) }
        }
        return nil
    }

    /// The window with this id, how to add a tab to it, and how many more it holds: Active's Open as
    /// Tab In (2026-10-15). Nil when it is not on screen.
    func tabAdder(windowID: UUID) -> (window: NSWindow, room: Int, add: @MainActor (MacWorkspaceTabRequest) -> Bool)? {
        guard let entry = entries[windowID], let window = entry.window, let controller = entry.controller,
              !controller.closesAfterLastTabLeft, let adder = tabAdders[windowID] else { return nil }
        return (window, max(0, MacWorkspaceWindowRestorationState.maximumTabCount - controller.tabs.count), adder)
    }

    /// How to add a tab to the window that holds `tab` now — tabs move between windows — for
    /// what a pane asks for beside it: Watch Log File (2026-10-14). Nil when it is in none on screen.
    func tabAdder(holding tab: MacWorkspaceController) -> (@MainActor (MacWorkspaceTabRequest) -> Bool)? {
        for (id, entry) in entries where entry.window != nil {
            guard entry.controller?.tabs.contains(where: { $0 === tab }) == true, let adder = tabAdders[id] else { continue }
            return adder
        }
        return nil
    }

    func register(_ controller: MacWorkspaceWindowController, window: NSWindow) {
        guard !MacTerminalWindowReader.hasClosed(window),
              entries[controller.windowID]?.window !== window else { return }
        entries[controller.windowID] = Entry(controller, window: window, order: nextOrder)
        nextOrder += 1
        windowsChanged?()
    }

    /// The window has closed: neither it nor its controller is found again, so a window opened
    /// later with the same id starts from its saved tabs.
    func remove(_ id: UUID) {
        tabAdders.removeValue(forKey: id)
        let wasShown = entries.removeValue(forKey: id) != nil
        built.removeValue(forKey: id)
        if wasShown { windowsChanged?() }
    }

    /// A window controller was made. Only `MacWorkspaceWindowController.init` calls this.
    func noteBuilt(_ controller: MacWorkspaceWindowController) {
        built[controller.windowID, default: []].append(Built(controller))
    }

    /// Every controller alive for a window id. One, unless something made a second.
    func controllers(windowID: UUID) -> [MacWorkspaceWindowController] {
        let alive = built[windowID]?.filter { $0.controller != nil } ?? []
        built[windowID] = alive.isEmpty ? nil : alive
        return alive.compactMap(\.controller)
    }

    /// The controller for the window a request opens: the one already made for its id, or a new
    /// one. A window's view gets its controller only here.
    func windowController(for request: MacWorkspaceLaunchRequest) -> MacWorkspaceWindowController {
        controllers(windowID: request.windowID).first ?? MacWorkspaceWindowController(request: request)
    }

    /// The controller a window on screen shows — never a copy that no window shows.
    func shownController(windowID: UUID) -> MacWorkspaceWindowController? {
        guard let entry = entries[windowID], entry.window != nil else { return nil }
        return entry.controller
    }

    /// The controllers of the terminal windows on screen.
    var shownControllers: [MacWorkspaceWindowController] {
        entries.keys.sorted { $0.uuidString < $1.uuidString }.compactMap(shownController(windowID:))
    }

    /// A terminal window on screen and the controller it shows.
    struct ShownWindow {
        let controller: MacWorkspaceWindowController
        let window: NSWindow
    }

    /// The terminal windows on screen, oldest first: Show All Terminals' groups, in an order that
    /// stays put while windows come and go. A window whose last tab has left is closing, and is
    /// not one of them.
    var shownWindows: [ShownWindow] {
        entries.values.sorted { $0.order < $1.order }.compactMap { entry in
            guard let controller = entry.controller, let window = entry.window,
                  !controller.closesAfterLastTabLeft else { return nil }
            return ShownWindow(controller: controller, window: window)
        }
    }

    /// The ids of terminal windows open or opening: shown, or with a controller made for them
    /// whose window has not been found yet.
    var openWindowIDs: Set<UUID> {
        Set(shownControllers.map(\.windowID))
            .union(built.filter { $0.value.contains { $0.controller != nil } }.keys)
    }

    /// The settings of the window on screen holding this tab (W20, W22), for its pictures
    /// elsewhere — the overview, Show All Terminals, a Workgroup's running terminals.
    func windowSettings(ofWindowWithTab workspaceID: UUID) -> GlassWindowOverrides {
        shownControllers.first { $0.tabs.contains { $0.workspaceID == workspaceID } }?.windowSettings
            ?? GlassWindowOverrides()
    }

    /// The settings of the window on screen holding this live session (W20, W22).
    func windowSettings(ofWindowHolding sessionID: UUID) -> GlassWindowOverrides {
        locate(sessionID: sessionID)?.controller.windowSettings ?? GlassWindowOverrides()
    }

    func tabs(for workgroupID: UUID) -> [MacWorkspaceController] {
        entries.keys.sorted { $0.uuidString < $1.uuidString }
            .compactMap { entries[$0]?.controller }.flatMap(\.tabs)
            .filter { $0.workgroupID == workgroupID && !$0.isClosed }
    }

    /// Saved workgroups' Mac terminals open in this Mac's windows now are this Mac's: each workgroup
    /// records it (2026-10-29), once the library can say which of its machines this Mac is. Windows
    /// back after a relaunch start their tabs before the library has loaded, which say so then.
    func recordThisMacOnOpenWorkgroups(settingsManager: SettingsManager) {
        for preset in settingsManager.layoutPresets
        where preset.sessionIntents.contains(where: { $0.kind == .local && $0.macServerID == nil }) {
            for tab in tabs(for: preset.id) {
                for pane in tab.state.root?.panes ?? [] where pane.intent.kind == .local {
                    guard let index = pane.intent.sourceSessionIndex else { continue }
                    settingsManager.recordWorkgroupMac(workgroupID: preset.id, index: index, session: pane.intent.localTmuxSession)
                }
            }
        }
    }

    /// The window, tab and pane holding a live session — Active's way to a terminal that is in
    /// no workgroup.
    private func locate(sessionID: UUID) -> (window: NSWindow, controller: MacWorkspaceWindowController,
                                             tab: MacWorkspaceController, paneID: UUID)? {
        for id in entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let entry = entries[id], let controller = entry.controller, let window = entry.window else { continue }
            for tab in controller.tabs where !tab.isClosed {
                if let paneID = tab.sessionsByPaneID.first(where: { $0.value.id == sessionID })?.key {
                    return (window, controller, tab, paneID)
                }
            }
        }
        return nil
    }

    /// W4b: brings forward the window showing a workgroup, on its tab, so opening it again never
    /// attaches a second window to its sessions: the window opened from it, else one showing a
    /// tmux session it saved — a window saved as the workgroup, or tabs reopened after a quit.
    @discardableResult
    func reveal(workgroup preset: LayoutPreset) -> Bool {
        guard let found = locate(workgroup: preset) else { return false }
        found.controller.select(found.tab.workspaceID)
        NSApp.activate()
        found.window.makeKeyAndOrderFront(nil)
        return true
    }

    /// The window and tab `reveal(workgroup:)` brings forward, if any.
    func locate(workgroup preset: LayoutPreset,
                thisMac: UUID? = GlassTerminalRuntime.current?.thisMacServerID?()) -> (window: NSWindow, controller: MacWorkspaceWindowController,
                                                    tab: MacWorkspaceController)? {
        // By machine (`SessionIntent.machine`): a local tab and an SSH pane to this Mac's own record
        // show one session, as do a Mac terminal and an SSH pane to its Mac (2026-10-29).
        let saved = Set(preset.sessionIntents.compactMap { intent in
            intent.tmuxSession.map { TerminalWorkgroupSession(serverID: intent.machine(thisMac: thisMac), name: $0) }
        })
        func holdsSaved(_ tab: MacWorkspaceController) -> Bool {
            (tab.state.root?.panes ?? []).contains { pane in
                let machine = pane.intent.serverID == thisMac ? nil : pane.intent.serverID
                return pane.intent.tmuxSession.map { saved.contains(TerminalWorkgroupSession(serverID: machine, name: $0)) } == true
            }
        }
        let shown = entries.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { id -> (NSWindow, MacWorkspaceWindowController)? in
            guard let entry = entries[id], let window = entry.window, let controller = entry.controller else { return nil }
            return (window, controller)
        }
        let matchers: [(MacWorkspaceController) -> Bool] = [{ $0.workgroupID == preset.id }, holdsSaved]
        for match in matchers {
            for (window, controller) in shown {
                if let tab = controller.tabs.first(where: { !$0.isClosed && match($0) }) { return (window, controller, tab) }
            }
        }
        return nil
    }

    private struct TerminalWorkgroupSession: Hashable {
        let serverID: UUID?
        let name: String
    }

    /// What the tab showing a live session is called, as its sidebar row says it (W19): Active's
    /// row for the terminal says the same. Nil when no window on screen shows it.
    func tabTitle(sessionID: UUID, servers: [ServerConfiguration]) -> String? {
        locate(sessionID: sessionID)?.tab.windowIdentity(servers: servers).title
    }

    /// Whether a window on screen shows this session in one of its tabs.
    func shows(sessionID: UUID) -> Bool { locate(sessionID: sessionID) != nil }

    /// Brings the window holding the session forward, on its tab.
    @discardableResult
    func reveal(sessionID: UUID) -> Bool {
        guard let found = locate(sessionID: sessionID) else { return false }
        found.controller.select(found.tab.workspaceID)
        NSApp.activate()
        found.window.makeKeyAndOrderFront(nil)
        return true
    }

    /// The window, tab and pane showing this Mac's tmux session `name` (W6): one whose terminal
    /// is running, else one that names it.
    func locate(localTmuxSession name: String) -> (window: NSWindow, controller: MacWorkspaceWindowController,
                                                   tab: MacWorkspaceController, paneID: UUID)? {
        var named: (window: NSWindow, controller: MacWorkspaceWindowController, tab: MacWorkspaceController, paneID: UUID)?
        for id in entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let entry = entries[id], let controller = entry.controller, let window = entry.window else { continue }
            for tab in controller.tabs where !tab.isClosed {
                for pane in tab.state.root?.panes ?? [] where pane.intent.localTmuxSession == name {
                    if tab.localRuntimesByPaneID[pane.id] != nil { return (window, controller, tab, pane.id) }
                    named = named ?? (window, controller, tab, pane.id)
                }
            }
        }
        return named
    }

    /// Brings forward the tab showing `server`'s tmux session `name`, on its pane — a terminal
    /// continued from another device (Handoff, D72), which attaching again would mirror. False when
    /// no tab here shows it.
    @discardableResult
    func reveal(server: UUID, sshTmuxSession name: String,
                present: (NSWindow) -> Void = { NSApp.activate(); $0.makeKeyAndOrderFront(nil) }) -> Bool {
        for id in entries.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let entry = entries[id], let controller = entry.controller, let window = entry.window else { continue }
            for tab in controller.tabs where !tab.isClosed {
                guard let paneID = tab.pane(showingServer: server, sshTmuxSession: name) else { continue }
                controller.select(tab.workspaceID)
                tab.focus(paneID)
                if window.isMiniaturized { window.deminiaturize(nil) }
                present(window)
                return true
            }
        }
        return false
    }

    /// Brings forward the tab showing this Mac's tmux session `name`, on its pane: Active's Open
    /// for a session open here, which attaching again would mirror (W6).
    @discardableResult
    func reveal(localTmuxSession name: String,
                present: (NSWindow) -> Void = { NSApp.activate(); $0.makeKeyAndOrderFront(nil) }) -> Bool {
        guard let found = locate(localTmuxSession: name) else { return false }
        found.controller.select(found.tab.workspaceID)
        found.tab.focus(found.paneID)
        present(found.window)
        return true
    }

    /// Removes the session's pane, closing the session with it, and the window if that was its
    /// last pane. False when no window holds the session, so the caller can close it directly.
    @discardableResult
    func close(sessionID: UUID, sessionManager: SessionManager) -> Bool {
        guard let found = locate(sessionID: sessionID) else { return false }
        found.tab.removePane(found.paneID, sessionManager: sessionManager)
        if found.controller.isEmpty { found.window.close() }
        return true
    }
}

extension MacWorkspaceController {
    func previewModel(for paneID: UUID) -> SwiftTermHostModel? {
        localRuntimesByPaneID[paneID]?.model ?? sessionsByPaneID[paneID]?.terminalHostModel
    }

    /// The tab's terminal in front, as a picture for its window's orb in the dock (D95).
    func orbPicture() -> Image? {
        guard let paneID = focusedPaneID ?? state.root?.panes.first?.id,
              let image = previewModel(for: paneID)?.previewImage() else { return nil }
        return Image(nsImage: image)
    }

    func previewStatus(for paneID: UUID) -> String {
        if errorsByPaneID[paneID] != nil { return "Failed" }
        if loadingPaneIDs.contains(paneID) { return "Connecting" }
        if let session = sessionsByPaneID[paneID] { return session.state.displayName }
        if let runtime = localRuntimesByPaneID[paneID] {
            return runtime.processState.isRunning ? "Running" : "Exited"
        }
        return "Not running"
    }
}

/// The only preview renderer. Images never receive mouse, keyboard, or scroll
/// events; activation belongs to the enclosing overview card, not the terminal.
struct MacTerminalPreview: View {
    @Environment(SettingsManager.self) private var settings
    let model: SwiftTermHostModel?
    let status: String
    var alwaysVisible = false
    /// Its window's settings (W20, W22), so the picture looks like the tab.
    var windowSettings = GlassWindowOverrides()
    @State private var image: NSImage?
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let resolved = TerminalWindowProfile.resolved(windowSettings, settings: settings)
        // The picture is drawn smaller than the terminal: its look (D84) — backdrop, phosphor and
        // glow, which surround the terminal rather than being part of what it draws — at that scale.
        let source = model?.previewSourceSize
        ZStack {
            TerminalCanvasBackground(color: resolved.theme.background,
                                     tint: resolved.look.tintColor,
                                     opacity: resolved.look.opacity,
                                     blur: resolved.look.blur,
                                     appearance: resolved.theme.resolvedAppearance)
            GeometryReader { geometry in
                TerminalBackdropView(style: resolved.lookStyle, theme: resolved.theme,
                                     scale: Self.scale(of: source, in: geometry.size), still: true)
            }
            if let image {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFit()
                        .terminalTextLook(resolved.lookStyle, theme: resolved.theme,
                                          scale: Self.scale(of: source, in: geometry.size))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "apple.terminal")
                    Text(model == nil ? status : "Waiting for terminal preview…")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal preview, \(status)")
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .task(id: RefreshKey(model: model.map(ObjectIdentifier.init), visible: visible || alwaysVisible,
                             active: scenePhase == .active)) {
            image = nil
            guard visible || alwaysVisible, scenePhase == .active else { return }
            while !Task.isCancelled {
                image = model?.previewImage()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    private struct RefreshKey: Equatable {
        let model: ObjectIdentifier?
        let visible: Bool
        let active: Bool
    }

    /// How much smaller the picture is drawn than the terminal it shows, fitted as the image is.
    static func scale(of source: CGSize?, in shown: CGSize) -> CGFloat {
        guard let source, source.width > 0, source.height > 0 else { return 1 }
        return min(1, min(shown.width / source.width, shown.height / source.height))
    }
}

struct MacWorkspacePreview: View {
    @Environment(SettingsManager.self) private var settings
    let controller: MacWorkspaceController
    var alwaysVisible = false

    var body: some View {
        // The tab's window's settings (W20, W22): pictures here show in the overview, Show All
        // Terminals and a Workgroup's running terminals, each of them a tab of some window.
        let window = MacWorkspacePreviewRegistry.shared.windowSettings(ofWindowWithTab: controller.workspaceID)
        let resolved = TerminalWindowProfile.resolved(window, settings: settings)
        GeometryReader { geometry in
            if let root = controller.state.root {
                let layout = MacWorkspaceLayout(root: root,
                    in: CGRect(origin: .zero, size: geometry.size))
                ZStack(alignment: .topLeading) {
                    ForEach(root.panes) { pane in
                        if let frame = layout.paneFrames[pane.id] {
                            MacTerminalPreview(model: controller.previewModel(for: pane.id),
                                               status: controller.previewStatus(for: pane.id),
                                               alwaysVisible: alwaysVisible,
                                               windowSettings: window)
                                .frame(width: max(1, frame.width - 2), height: max(1, frame.height - 2))
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
            } else {
                TerminalCanvasBackground(color: resolved.theme.background,
                                         tint: resolved.look.tintColor,
                                         opacity: resolved.look.opacity,
                                         blur: resolved.look.blur,
                                         appearance: resolved.theme.resolvedAppearance).overlay {
                    Label("Empty tab", systemImage: "apple.terminal").foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Only fresh output can attract attention. Old output is baselined on enable;
/// manual browsing consumes activity during a short grace period.
struct MacTerminalActivitySelection {
    private var previous: [UUID: ContinuousClock.Instant] = [:]
    private var manualUntil: ContinuousClock.Instant?
    private var chosenAt: ContinuousClock.Instant?

    /// How long the carousel keeps a tab in front before the next one printing takes its place: with several
    /// agents at work, following each the moment it printed swung the whole row back and forth every half
    /// second (the VM, 2026-11-02). Output meanwhile is passed over, so the next is one printing after.
    static let carouselHold: Duration = .seconds(3)

    mutating func baseline(_ samples: [UUID: ContinuousClock.Instant]) { previous = samples }

    mutating func didNavigate(at now: ContinuousClock.Instant = .now) {
        manualUntil = now.advanced(by: .seconds(3))
    }

    mutating func candidate(in samples: [UUID: ContinuousClock.Instant],
                            now: ContinuousClock.Instant = .now, holding hold: Duration = .zero) -> UUID? {
        defer { previous = samples }
        guard manualUntil.map({ now >= $0 }) ?? true else { return nil }
        guard chosenAt.map({ $0.duration(to: now) >= hold }) ?? true else { return nil }
        let chosen = samples.filter { id, instant in previous[id].map { instant > $0 } ?? true }
            .max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.uuidString < rhs.key.uuidString : lhs.value < rhs.value
            }?.key
        if chosen != nil { chosenAt = now }
        return chosen
    }
}

/// A terminal window's overview (⌥⌘G, Terminal Overview): its tabs as Show All Windows draws them, inside the
/// window (D96; the owner, 2026-11-02: "let's give the window's expose view the same UI as the app's version. It
/// was the first draft, really."). Show All Windows' tiles — the live picture, the coding agent's mark, the
/// activity wave, the caption on hover or selection — its type-to-find, arrows, Return and Esc. It lists this
/// window's tabs, or its workgroup's, and stays until a tab is chosen, so with Auto-focus on activity it stands as
/// a live wall, its controls fading while nothing moves. Its carousel, card-size slider and the cards of sessions
/// open elsewhere went with the first draft; Show All Windows is everything.
struct MacTerminalOverview: View {
    let controller: MacWorkspaceWindowController
    let servers: [ServerConfiguration]
    @Binding var followsActivity: Bool
    @Binding var controlsVisible: Bool
    let activate: (UUID) -> Void
    let dismiss: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    /// Show All Windows' Blur previews: the same pictures, for the same screenshots.
    @AppStorage(GlassShowAllWindows.blursPreviewsKey, store: GlassUITestRun.settingsDefaults) private var blursPreviews = false
    /// Grid or carousel: this Mac's last choice, for every window.
    @AppStorage(MacTerminalOverviewStyle.key, store: GlassUITestRun.settingsDefaults) private var style = MacTerminalOverviewStyle.grid
    @State private var selection: MacTerminalExposeItemID?
    @State private var hovered: MacTerminalExposeItemID?
    @State private var filter = ""
    @State private var workgroupOnly = false
    @State private var activitySelection = MacTerminalActivitySelection()
    /// The space the tiles are laid out in, kept for the arrow keys.
    @State private var area: CGSize = .zero
    @FocusState private var focused: Bool

    static let hint = "Arrows to move · Return to open · Esc to go back"
    static let carouselHint = "Arrows, a swipe or a drag to move · Return or a click to open · Esc to go back"

    private var tabs: [MacWorkspaceController] {
        guard workgroupOnly, let id = controller.selectedTab.workgroupID else { return controller.tabs }
        return controller.tabs.filter { $0.workgroupID == id }
    }

    /// The window as Show All Windows groups it — its name, a tile per tab — narrowed by what was typed.
    private var groups: [MacTerminalExposeGroup] {
        let shown = Set(tabs.map(\.workspaceID))
        let windows = MacTerminalExposeModel.groups(windows: [controller], servers: servers).map { group in
            var group = group
            group.tiles = group.tiles.filter { if case .tab(let id) = $0.id { shown.contains(id) } else { false } }
            return group
        }
        return MacTerminalExposeModel.filtered(windows, by: filter)
    }

    var body: some View {
        let groups = self.groups
        ZStack {
            // Around the tiles: back to the tab in front, as a click beside Show All Windows' groups closes it.
            MacTerminalExposeBackdrop(close: dismiss)
            VStack(spacing: 14) {
                MacTerminalExposeHeader(filter: filter, matches: groups.reduce(0) { $0 + $1.tiles.count },
                                        hint: style == .carousel ? Self.carouselHint : Self.hint)
                    .opacity(controlsVisible ? 1 : 0)
                GeometryReader { proxy in
                    arrangement(groups, in: proxy.size)
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { area = $0 }
                controls
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .accessibilityHidden(!controlsVisible)
            }
            .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press, groups: groups) ? .handled : .ignored
        }
        // ⌫ arrives as the system's Delete command, as in Show All Windows.
        .onDeleteCommand { if !filter.isEmpty { filter.removeLast() } }
        .background {
            MacOverviewActivityMonitor(canHide: focused) { visible in
                // A single transition for SwiftUI controls and native window chrome.
                controlsVisible = visible
            }
        }
        // From the start too, on the tab in front: a selection typing or a closed tab hid moves to a tile shown.
        .onChange(of: groups.flatMap { $0.tiles.map(\.id) }, initial: true) { _, ids in
            let kept = MacTerminalExposeModel.selection(selection ?? .tab(controller.selectedTabID), shown: ids)
            if kept != selection { selection = kept }
            activitySelection.baseline(activitySamples)
        }
        .onAppear { focused = true }
        .onChange(of: followsActivity) { focused = true }
        .task(id: followsActivity && scenePhase == .active) {
            activitySelection.baseline(activitySamples)
            guard followsActivity, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                let hold = style == .carousel ? MacTerminalActivitySelection.carouselHold : .zero
                if let id = activitySelection.candidate(in: activitySamples, holding: hold),
                   groups.contains(where: { $0.tiles.contains { $0.id == .tab(id) } }) {
                    withAnimation(.easeInOut(duration: 0.22)) { selection = .tab(id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Terminal Overview")
        .accessibilityIdentifier("terminal-overview")
    }

    /// The workgroup's tabs or all of them, and Auto-focus on activity: the window's own, under its tiles.
    private var controls: some View {
        HStack(spacing: 16) {
            Picker("View", selection: $style.animation(.easeInOut(duration: 0.25))) {
                ForEach(MacTerminalOverviewStyle.allCases, id: \.self) { style in
                    Label(style.title, systemImage: style.symbolName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show the tabs as a grid, or in a carousel that flows past the one in front")
            .accessibilityIdentifier("terminal-overview-style")
            if controller.selectedTab.workgroupID != nil {
                Picker("Scope", selection: $workgroupOnly) {
                    Text("All tabs").tag(false)
                    Text("This workgroup").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("terminal-overview-scope")
            }
            Toggle("Auto-focus on activity", isOn: $followsActivity)
                .toggleStyle(.checkbox)
                .help("Select the terminal with new output. Never opens a tab or sends terminal input.")
                .accessibilityIdentifier("terminal-overview-follow-activity")
        }
        .font(.callout)
    }

    // MARK: Arrangement

    @ViewBuilder
    private func arrangement(_ groups: [MacTerminalExposeGroup], in size: CGSize) -> some View {
        let layout = MacTerminalExposeLayout(tileCounts: groups.map(\.tiles.count), in: size)
        if groups.isEmpty {
            MacTerminalExposeEmpty(filter: filter)
                .frame(width: size.width, height: size.height)
        } else if style == .carousel {
            MacTerminalCarousel(tiles: groups.flatMap(\.tiles),
                                tabs: Dictionary(controller.tabs.map { ($0.workspaceID, $0) }, uniquingKeysWith: { first, _ in first }),
                                selection: $selection, blurred: blursPreviews, activate: activate)
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        } else if layout.scrolls {
            ScrollViewReader { scroll in
                ScrollView {
                    canvas(groups, layout)
                        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                }
                .scrollIndicators(.automatic)
                // The selection kept in sight as the arrows or new output move it.
                .onChange(of: selection) { _, id in
                    if let id { withAnimation(.easeInOut(duration: 0.18)) { scroll.scrollTo(id, anchor: .center) } }
                }
            }
        } else {
            canvas(groups, layout)
        }
    }

    private func canvas(_ groups: [MacTerminalExposeGroup], _ layout: MacTerminalExposeLayout) -> some View {
        let byID = Dictionary(controller.tabs.map { ($0.workspaceID, $0) }, uniquingKeysWith: { first, _ in first })
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(groups, layout.groups)), id: \.0.id) { group, frames in
                let origin = frames.frame.origin
                MacTerminalExposeGroupCard(title: group.title, symbolName: "macwindow", frames: frames) {
                    dismiss()
                } tiles: {
                    ForEach(Array(zip(group.tiles, frames.tileFrames)), id: \.0.id) { tile, frame in
                        if case .tab(let id) = tile.id, let tab = byID[id] {
                            tileView(tile, tab: tab, size: layout.tileSize, alwaysVisible: !layout.scrolls)
                                .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                                .id(tile.id)
                        }
                    }
                }
                .frame(width: frames.frame.width, height: frames.frame.height)
                .position(x: frames.frame.midX, y: frames.frame.midY)
            }
        }
    }

    private func tileView(_ tile: MacTerminalExposeTile, tab: MacWorkspaceController, size: CGSize,
                          alwaysVisible: Bool) -> some View {
        let selected = selection == tile.id
        let hovering = hovered == tile.id
        return MacTerminalExposeTabTile(tab: tab, tile: tile, selected: selected, hovering: hovering,
                                        alwaysVisible: alwaysVisible, blurred: blursPreviews)
            .modifier(MacTerminalExposeTileChrome(
                tile: tile, selected: selected, hovering: hovering, size: size,
                identifier: "terminal-overview-tab-\(tab.workspaceID.uuidString.lowercased())"
            ) { inside in
                if inside { hovered = tile.id } else if hovered == tile.id { hovered = nil }
            } choose: {
                activate(tab.workspaceID)
            })
    }

    // MARK: Keys

    /// Show All Windows' keys: arrows move, Return opens, Escape goes back, Delete and typing edit what is
    /// found. Anything with ⌘ or ⌃ is left for the menu bar, so ⌥⌘G and ⌘1 to ⌘9 still work.
    private func handle(_ press: KeyPress, groups: [MacTerminalExposeGroup]) -> Bool {
        guard press.modifiers.isDisjoint(with: [.command, .control]) else { return false }
        switch press.key {
        case .escape:
            dismiss()
        case .return:
            if case .tab(let id) = selection, groups.contains(where: { $0.tiles.contains { $0.id == .tab(id) } }) {
                activate(id)
            }
        case .leftArrow where style == .carousel: step(-1, groups)
        case .rightArrow where style == .carousel: step(1, groups)
        case .upArrow where style == .carousel, .downArrow where style == .carousel: return true
        case .leftArrow: navigate(.left, groups)
        case .rightArrow: navigate(.right, groups)
        case .upArrow: navigate(.up, groups)
        case .downArrow: navigate(.down, groups)
        case .delete, .deleteForward:
            if !filter.isEmpty { filter.removeLast() }
        default:
            let typed = press.characters.filter { character in
                character.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
                    && !(0xF700...0xF8FF).contains(character.unicodeScalars.first?.value ?? 0)
            }
            guard !typed.isEmpty else { return false }
            filter += typed
        }
        return true
    }

    /// The carousel's arrows: along the row, stopping at its ends.
    private func step(_ by: Int, _ groups: [MacTerminalExposeGroup]) {
        activitySelection.didNavigate()
        let ids = groups.flatMap { $0.tiles.map(\.id) }
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        selection = ids[max(0, min(ids.count - 1, index + by))]
    }

    private func navigate(_ direction: MacTerminalExposeNavigation.Direction, _ groups: [MacTerminalExposeGroup]) {
        activitySelection.didNavigate()
        let layout = MacTerminalExposeLayout(tileCounts: groups.map(\.tiles.count), in: area)
        let items = zip(groups, layout.groups).flatMap { group, frames in
            zip(group.tiles, frames.tileFrames).map { (id: $0.id, frame: $1) }
        }
        selection = MacTerminalExposeNavigation.moved(selection, direction, in: items)
    }

    private var activitySamples: [UUID: ContinuousClock.Instant] {
        Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in
            guard let latest = (tab.state.root?.panes ?? []).compactMap({ pane in
                tab.previewModel(for: pane.id)?.performanceDiagnostics.lastOutputInstant
            }).max() else { return nil }
            return (tab.workspaceID, latest)
        })
    }
}

struct MacOverviewIdlePolicy {
    private(set) var lastInteraction: ContinuousClock.Instant = .now
    mutating func interact(at now: ContinuousClock.Instant = .now) { lastInteraction = now }
    func shouldHide(at now: ContinuousClock.Instant = .now, canHide: Bool) -> Bool {
        canHide && lastInteraction.duration(to: now) >= .seconds(3)
    }
}

/// Observes this window only. Events always continue to their original target;
/// revealing chrome never consumes a click or sends input to a terminal.
private struct MacOverviewActivityMonitor: NSViewRepresentable {
    let canHide: Bool
    let visibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.canHide = canHide
        view.visibilityChanged = visibilityChanged
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var canHide = false
        var visibilityChanged: ((Bool) -> Void)?
        private var monitor: Any?
        private var ticker: Task<Void, Never>?
        private var policy = MacOverviewIdlePolicy()
        private var visible = true
        private weak var observedWindow: NSWindow?
        private var previouslyAcceptedMouseMoved = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            observedWindow = window
            previouslyAcceptedMouseMoved = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
            policy.interact()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
                guard let self, event.window === self.observedWindow else { return event }
                self.policy.interact()
                self.setVisible(true)
                return event
            }
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self else { return }
                    let safe = self.canHide && self.observedWindow?.isKeyWindow == true
                        && self.observedWindow?.attachedSheet == nil && NSEvent.pressedMouseButtons == 0
                        && RunLoop.current.currentMode != .eventTracking
                        && !self.pointerIsAtEdge
                    if !safe { self.policy.interact() }
                    self.setVisible(!self.policy.shouldHide(canHide: safe))
                }
            }
        }
        private func setVisible(_ value: Bool) {
            guard visible != value else { return }
            visible = value
            visibilityChanged?(value)
        }
        private var pointerIsAtEdge: Bool {
            guard let window = observedWindow else { return false }
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let size = window.frame.size
            guard CGRect(origin: .zero, size: size).contains(point) else { return false }
            return point.x < 60 || point.x > size.width - 60 || point.y < 100 || point.y > size.height - 110
        }
        func stop() {
            ticker?.cancel()
            ticker = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            observedWindow?.acceptsMouseMovedEvents = previouslyAcceptedMouseMoved
            observedWindow = nil
        }
    }
}

enum MacTerminalPreviewStatus {
    static func color(for statuses: [String]) -> Color {
        if statuses.contains(where: { $0 == "Failed" || $0.hasPrefix("Error:") }) { return .red }
        if statuses.contains(where: { $0.hasPrefix("Connecting") || $0.hasPrefix("Reconnecting") || $0.hasPrefix("Authenticating") }) { return .orange }
        if statuses.contains(where: { ["Running", "Connected"].contains($0) }) { return .green }
        return .secondary
    }
}
#endif

#endif
