#if os(macOS)
#if os(macOS)
import AppKit
import Observation
import GlassTerminalEmulator
import GlassShell
import SwiftUI

/// Discovery only: windows remain the sole owners of their sessions and tabs.
@MainActor @Observable
final class MacWorkspacePreviewRegistry {
    static let shared = MacWorkspacePreviewRegistry()
    private final class Entry {
        weak var controller: MacWorkspaceWindowController?
        weak var window: NSWindow?
        init(_ controller: MacWorkspaceWindowController, window: NSWindow) {
            self.controller = controller
            self.window = window
        }
    }
    private var entries: [UUID: Entry] = [:]

    func register(_ controller: MacWorkspaceWindowController, window: NSWindow) {
        guard entries[controller.windowID]?.window !== window else { return }
        entries[controller.windowID] = Entry(controller, window: window)
    }

    func remove(_ id: UUID) { entries.removeValue(forKey: id) }

    func tabs(for workgroupID: UUID) -> [MacWorkspaceController] {
        entries.keys.sorted { $0.uuidString < $1.uuidString }
            .compactMap { entries[$0]?.controller }.flatMap(\.tabs)
            .filter { $0.workgroupID == workgroupID && !$0.isClosed }
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

    /// Brings the window holding the session forward, on its tab.
    @discardableResult
    func reveal(sessionID: UUID) -> Bool {
        guard let found = locate(sessionID: sessionID) else { return false }
        found.controller.select(found.tab.workspaceID)
        NSApp.activate()
        found.window.makeKeyAndOrderFront(nil)
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
    @State private var image: NSImage?
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TerminalCanvasBackground(color: settings.currentTheme.background,
                                     tint: TerminalGlassTint.color(for: settings.glassTint),
                                     opacity: settings.windowOpacity,
                                     blur: settings.blurBackground,
                                     appearance: settings.currentTheme.resolvedAppearance)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
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
}

struct MacWorkspacePreview: View {
    @Environment(SettingsManager.self) private var settings
    let controller: MacWorkspaceController
    var alwaysVisible = false

    var body: some View {
        GeometryReader { geometry in
            if let root = controller.state.root {
                let layout = MacWorkspaceLayout(root: root,
                    in: CGRect(origin: .zero, size: geometry.size))
                ZStack(alignment: .topLeading) {
                    ForEach(root.panes) { pane in
                        if let frame = layout.paneFrames[pane.id] {
                            MacTerminalPreview(model: controller.previewModel(for: pane.id),
                                               status: controller.previewStatus(for: pane.id),
                                               alwaysVisible: alwaysVisible)
                                .frame(width: max(1, frame.width - 2), height: max(1, frame.height - 2))
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
            } else {
                TerminalCanvasBackground(color: settings.currentTheme.background,
                                         tint: TerminalGlassTint.color(for: settings.glassTint),
                                         opacity: settings.windowOpacity,
                                         blur: settings.blurBackground,
                                         appearance: settings.currentTheme.resolvedAppearance).overlay {
                    Label("Empty tab", systemImage: "apple.terminal").foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

enum MacTerminalOverviewNavigation {
    /// Generic over the id because the overview now browses two kinds of thing — this window's
    /// tabs and sessions open elsewhere — in one row. Same arithmetic as before.
    static func moved<ID: Hashable>(_ selection: ID?, by offset: Int, in ids: [ID]) -> ID? {
        guard !ids.isEmpty else { return nil }
        let index = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        return ids[max(0, min(ids.count - 1, index + offset))]
    }
}

/// One thing the overview can show: a tab of this window, previewed live, or a session open
/// anywhere else in the app — another terminal window, a database, an editor.
///
/// The second kind is why the user, standing in this overview, asked where the database was.
/// It switched between one window's terminals; the product's idea is a machine's services side
/// by side, and the seam that lists them (`GlassOpenSession`) now exists.
enum MacOverviewItem: Identifiable {
    case tab(MacWorkspaceController)
    case session(GlassOpenSession)

    var id: MacOverviewItemID {
        switch self {
        case .tab(let tab): .tab(tab.workspaceID)
        case .session(let session): .session(session.id)
        }
    }
}

enum MacOverviewItemID: Hashable {
    case tab(UUID)
    case session(String)
}

enum MacOverviewSessions {
    /// Sessions open elsewhere: everything the app lists, minus the workgroups this window is
    /// already showing as live tabs — those would be the same terminal twice, once as a preview
    /// and once as a card.
    static func others(_ all: [GlassOpenSession], excludingWorkgroups ids: [UUID]) -> [GlassOpenSession] {
        let own = Set(ids.map { GlassTerminalCapability.sessionID(workgroupID: $0) })
        return all.filter { !own.contains($0.id) }
    }
}

/// The overview's layout is `GlassShell.GlassGalleryLayout` now — the same question the session
/// gallery asks, so there is one solver and one set of tests for it rather than two. Kept as a
/// name here because this file reads better with it and the call sites did not need churning.
typealias MacTerminalOverviewGrid = GlassGalleryLayout

/// Only fresh output can attract attention. Old output is baselined on enable;
/// manual browsing consumes activity during a short grace period.
struct MacTerminalActivitySelection {
    private var previous: [UUID: ContinuousClock.Instant] = [:]
    private var manualUntil: ContinuousClock.Instant?

    mutating func baseline(_ samples: [UUID: ContinuousClock.Instant]) { previous = samples }

    mutating func didNavigate(at now: ContinuousClock.Instant = .now) {
        manualUntil = now.advanced(by: .seconds(3))
    }

    mutating func candidate(in samples: [UUID: ContinuousClock.Instant],
                            now: ContinuousClock.Instant = .now) -> UUID? {
        defer { previous = samples }
        guard manualUntil.map({ now >= $0 }) ?? true else { return nil }
        return samples.filter { id, instant in previous[id].map { instant > $0 } ?? true }
            .max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.uuidString < rhs.key.uuidString : lhs.value < rhs.value
            }?.key
    }
}

struct MacTerminalOverview: View {
    let controller: MacWorkspaceWindowController
    let servers: [ServerConfiguration]
    @Binding var carousel: Bool
    @Binding var followsActivity: Bool
    @Binding var controlsVisible: Bool
    @Binding var preferredCardWidth: Double?
    let activate: (UUID) -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Optional: the workspace scene injects it; a preview or a test host may not.
    @Environment(GlassTerminalRuntime.self) private var runtime: GlassTerminalRuntime?
    @State private var selectedID: MacOverviewItemID?
    @State private var hoveredID: MacOverviewItemID?
    @State private var workgroupOnly = false
    @State private var activitySelection = MacTerminalActivitySelection()
    @FocusState private var navigationFocused: Bool

    private var tabs: [MacWorkspaceController] {
        guard workgroupOnly, let id = controller.selectedTab.workgroupID else { return controller.tabs }
        return controller.tabs.filter { $0.workgroupID == id }
    }

    /// Read in the body so the list follows every capability's own state (rule from the panel
    /// count of 2026-09-18: a stored answer to a live question goes stale).
    private var others: [GlassOpenSession] {
        guard !workgroupOnly else { return [] }
        return MacOverviewSessions.others(runtime?.openSessions?() ?? [],
                                          excludingWorkgroups: controller.tabs.compactMap(\.workgroupID))
    }

    private var items: [MacOverviewItem] {
        tabs.map(MacOverviewItem.tab) + others.map(MacOverviewItem.session)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Terminal Overview").font(.title2.bold())
                    Text(others.isEmpty
                         ? "\(tabs.count) tabs · Live, read-only previews"
                         : "\(tabs.count) tabs · \(others.count) open elsewhere · Live, read-only previews")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.selectedTab.workgroupID != nil {
                    Picker("Scope", selection: $workgroupOnly) {
                        Text("All tabs").tag(false)
                        Text("This workgroup").tag(true)
                    }.labelsHidden().frame(maxWidth: 170)
                }
                Picker("Presentation", selection: $carousel) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(false)
                    Label("Carousel", systemImage: "rectangle.stack").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .accessibilityHidden(!controlsVisible)
            GeometryReader { geometry in
                let grid = MacTerminalOverviewGrid(count: items.count, size: geometry.size, preferredWidth: preferredCardWidth)
                ScrollViewReader { scroll in
                    Group {
                        if carousel {
                            carouselCards(in: geometry.size)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(maximum: grid.cardWidth), spacing: 18), count: grid.columns), spacing: 18) {
                                    ForEach(items) { item in
                                        itemCard(item).id(item.id)
                                    }
                                }.padding(6)
                            }
                        }
                    }
                    .onChange(of: selectedID) { _, id in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            if !carousel, let id { scroll.scrollTo(id, anchor: .center) }
                        }
                    }
                    .task(id: carousel) {
                        await Task.yield()
                        if !carousel, let selectedID { scroll.scrollTo(selectedID, anchor: .center) }
                        navigationFocused = true
                    }
                    .focusable().focusEffectDisabled().focused($navigationFocused)
                    .onMoveCommand { direction in
                        let offset: Int
                        switch direction {
                        case .left: offset = -1
                        case .right: offset = 1
                        case .up: offset = carousel ? -1 : -grid.columns
                        case .down: offset = carousel ? 1 : grid.columns
                        @unknown default: return
                        }
                        navigate(by: offset)
                    }
                    .onKeyPress(.return) { activateSelected() ? .handled : .ignored }
                    .onKeyPress(.space) { activateSelected() ? .handled : .ignored }
                }
            }
            HStack {
                Toggle("Auto-focus on activity", isOn: $followsActivity)
                    .toggleStyle(.checkbox)
                    .help("Select the preview with new output. Never opens a tab or sends terminal input.")
                    .accessibilityIdentifier("terminal-overview-follow-activity")
                Spacer()
                if !carousel {
                    Toggle("Auto size", isOn: Binding(
                        get: { preferredCardWidth == nil },
                        set: { preferredCardWidth = $0 ? nil : 360 }))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("terminal-overview-auto-size")
                    Slider(value: Binding(get: { preferredCardWidth ?? 360 }, set: { preferredCardWidth = $0 }),
                           in: 220...720, step: 20) { Text("Card size") }
                        .frame(width: 140)
                        .accessibilityIdentifier("terminal-overview-card-size")
                    Text(preferredCardWidth.map { "\(Int($0)) pt" } ?? "Auto")
                        .font(.caption.monospacedDigit()).frame(width: 54)
                }
                if carousel {
                    Button("Previous", systemImage: "chevron.left") { navigate(by: -1) }
                        .disabled(selectedIndex == 0)
                    Text("\(items.isEmpty ? 0 : selectedIndex + 1) / \(items.count)").monospacedDigit()
                    Button("Next", systemImage: "chevron.right") { navigate(by: 1) }
                        .disabled(selectedIndex >= items.count - 1)
                }
            }
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .accessibilityHidden(!controlsVisible)
            Text("Arrows to browse · Space or click to open · Esc to return")
                .font(.caption).foregroundStyle(.secondary)
                .opacity(controlsVisible ? 1 : 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            MacOverviewActivityMonitor(canHide: navigationFocused) { visible in
                // A single transition for SwiftUI controls and native window chrome.
                controlsVisible = visible
            }
        }
        .onAppear {
            selectedID = .tab(controller.selectedTabID)
            navigationFocused = true
        }
        .onChange(of: followsActivity) { navigationFocused = true }
        .onChange(of: items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = ids.first }
            if selectedID == nil { selectedID = ids.first }
            activitySelection.baseline(activitySamples)
        }
        .task(id: followsActivity && scenePhase == .active) {
            activitySelection.baseline(activitySamples)
            guard followsActivity, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                if let id = activitySelection.candidate(in: activitySamples) { select(.tab(id)) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-overview")
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedID } ?? 0
    }

    /// Opens whatever is selected: a tab of this window in place, or a session elsewhere through
    /// its own capability, after which this overview has done its job and goes.
    @discardableResult
    private func activateSelected() -> Bool {
        guard let selected = items.first(where: { $0.id == selectedID }) else { return false }
        switch selected {
        case .tab(let tab): activate(tab.workspaceID)
        case .session(let session):
            session.activate()
            dismiss()
        }
        return true
    }

    private var activitySamples: [UUID: ContinuousClock.Instant] {
        Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in
            guard let latest = (tab.state.root?.panes ?? []).compactMap({ pane in
                tab.previewModel(for: pane.id)?.performanceDiagnostics.lastOutputInstant
            }).max() else { return nil }
            return (tab.workspaceID, latest)
        })
    }

    private func select(_ id: MacOverviewItemID?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selectedID = id }
    }

    private func navigate(by offset: Int) {
        activitySelection.didNavigate()
        select(MacTerminalOverviewNavigation.moved(selectedID, by: offset, in: items.map(\.id)))
        navigationFocused = true
    }

    private func carouselCards(in size: CGSize) -> some View {
        let width = max(160, min(680, size.width * 0.64, (size.height - 84) * 1.6))
        let center = selectedIndex
        let neighbors = items.enumerated().filter { abs($0.offset - center) <= 1 }
        return ZStack {
            ForEach(neighbors, id: \.element.id) { index, item in
                let distance = index - center
                itemCard(item)
                    .frame(width: width)
                    .scaleEffect(distance == 0 ? 1 : 0.84)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(distance) * -12), axis: (x: 0, y: 1, z: 0))
                    .offset(x: CGFloat(distance) * width * 0.72, y: distance == 0 ? 0 : 12)
                    .zIndex(distance == 0 ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func itemCard(_ item: MacOverviewItem) -> some View {
        switch item {
        case .tab(let tab): card(tab)
        case .session(let session): sessionCard(session)
        }
    }

    /// A session open elsewhere, as the shell's card — the same one the phone's gallery draws —
    /// with this overview's selection ring and hover on top so it browses like the tabs do.
    private func sessionCard(_ session: GlassOpenSession) -> some View {
        let id = MacOverviewItemID.session(session.id)
        return GlassSessionCard(session: session,
                                activate: { session.activate(); dismiss() },
                                close: { session.close() })
            .opacity(controlsVisible || selectedID == id || hoveredID == id ? 1 : 0.7)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedID == id ? Color.accentColor : .clear, lineWidth: 3)
            }
            .onHover { hovering in hoveredID = hovering ? id : nil }
            .accessibilityValue(selectedID == id ? "Selected" : "")
            .accessibilityIdentifier("terminal-overview-session-\(session.id)")
    }

    private func card(_ tab: MacWorkspaceController) -> some View {
        let title = tab.windowIdentity(servers: servers).title
        let statuses = (tab.state.root?.panes ?? []).map { tab.previewStatus(for: $0.id) }
        return Button { activate(tab.workspaceID) } label: {
            VStack(alignment: .leading, spacing: 8) {
                MacWorkspacePreview(controller: tab, alwaysVisible: carousel)
                Text(title).font(.headline).lineLimit(1)
                    .foregroundStyle(MacTerminalPreviewStatus.color(for: statuses))
                    .opacity(controlsVisible || selectedID == .tab(tab.workspaceID) || hoveredID == .tab(tab.workspaceID) ? 1 : 0.55)
            }
            .padding(10)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedID == .tab(tab.workspaceID) ? Color.accentColor : .clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredID = hovering ? .tab(tab.workspaceID) : nil }
        .accessibilityLabel("Activate \(title)")
        .accessibilityHint(statuses.joined(separator: " · "))
        .help(statuses.joined(separator: " · "))
        .accessibilityValue(selectedID == .tab(tab.workspaceID) ? "Selected" : "")
        .accessibilityIdentifier("terminal-overview-tab-\(tab.workspaceID.uuidString.lowercased())")
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
