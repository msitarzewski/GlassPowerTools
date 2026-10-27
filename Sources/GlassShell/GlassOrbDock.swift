//
//  GlassOrbDock.swift
//  Glass Power Tools — GlassShell
//
//  Orbs gathered in a dock, on Vision Pro (D88). The owner, 2026-10-25: "an invisible 'canvas'
//  where (when enabled) a user's windows (when the orb mode is clicked) would move automatically
//  into a 'dock' that itself can be moved around. I'd resize the connections orb to match, and
//  include it too."
//
//  visionOS moves no window an app has open; it opens a new one above, below or beside another
//  (`WindowPlacement.Position`). So a window docks by closing into its orb here, its sessions kept
//  running, and the dock is one window with no panel, moved by its bar. A pinch on an orb opens its
//  window again above the dock, at the size it had. Off (the default), a window shrinks into its
//  own orb where it is (D74).
//

#if os(visionOS)
import SwiftUI
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers
import os

public enum GlassOrbDock {
    public static let windowID = "orb-dock"
    /// Settings ▸ Appearance ▸ Orbs. This device's, as the sizes and places of its windows are.
    public static let settingKey = "com.glasspowertools.orbs.inDock"
    /// Connections was in the dock, for the next launch to put it back; this device's.
    public static let connectionsKey = "com.glasspowertools.orbs.connectionsInDock"
    /// The dock's own Opacity and Glass over Appearance (`GlassWindowOverrides`, as JSON), set in
    /// Settings ▸ Appearance ▸ Orbs: the owner, 2026-10-26, "its own, but start with Appearance".
    public static let lookKey = "com.glasspowertools.orbs.dockLook"
    /// The size the person gave the dock ("1200x320"), empty while it fits its orbs; this device's.
    public static let sizeKey = "com.glasspowertools.orbs.dockSize"

    /// The dock's look as stored; following Appearance in everything when there is none.
    public static func look(from data: Data) -> GlassWindowOverrides {
        (try? JSONDecoder().decode(GlassWindowOverrides.self, from: data)) ?? GlassWindowOverrides()
    }

    public static func data(of look: GlassWindowOverrides) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(look)) ?? Data()
    }
}

/// The windows waiting in the dock, by their open session (`GlassOpenSession.id`), and the size each
/// had. One for the app: the windows that dock and the dock's own window share it.
@MainActor
@Observable
public final class GlassOrbDockModel {
    public static let shared = GlassOrbDockModel()

    /// The docked windows, in the order they came.
    public private(set) var docked: [String] = []
    /// Connections closed into the dock rather than standing as an orb of its own. Kept, so a
    /// launch puts it back (the owner, 2026-10-26: "let's have windows respawn in their last used
    /// state"); the terminal's windows are kept in its own list (`TerminalWorkgroupsToReopen`).
    public var holdsConnections = false {
        didSet {
            guard holdsConnections != oldValue else { return }
            GlassUITestRun.settingsDefaults.set(holdsConnections, forKey: GlassOrbDock.connectionsKey)
        }
    }
    /// The last run left Connections in the dock, until the launch's Connections window takes it.
    @ObservationIgnored private var connectionsWereDocked: Bool
    /// The windows the last run left are back, each connected or said why not
    /// (`TerminalWorkgroupsToReopen`). Connections waits for it before going back into the dock: an
    /// answer they need — a password, a host key — is asked there.
    @ObservationIgnored public private(set) var lastRunIsBack = false
    @ObservationIgnored private var sizes: [String: CGSize] = [:]
    /// Windows standing as their own orb where they are (D74), and the size each grows back to.
    public private(set) var standing: [String: CGSize] = [:]
    /// Windows a launch reopens as their orb, until each appears and takes it; the size each grows
    /// back to, when known.
    @ObservationIgnored private var openingAsOrbs: [String: CGSize?] = [:]
    /// Windows asked for from the dock, until visionOS places them: above the dock, each at its size,
    /// in the order asked (a machine's orb asks for all of its windows at once).
    @ObservationIgnored private var returning: [(size: CGSize?, until: ContinuousClock.Instant)] = []
    /// Where each orb stands, as the owner set it by holding one and moving it; this device's.
    public private(set) var order = GlassOrbDockOrder(defaults: GlassUITestRun.settingsDefaults)
    /// The dock's window is on screen (set by the dock), or was asked for and is on its way.
    @ObservationIgnored var isShown = false {
        didSet { askedUntil = nil }
    }
    @ObservationIgnored private var askedUntil: ContinuousClock.Instant?

    init() {
        connectionsWereDocked = GlassUITestRun.settingsDefaults.bool(forKey: GlassOrbDock.connectionsKey)
    }

    /// Whether the last run left Connections in the dock: true once, for the window that puts it back.
    public func takeConnectionsWereDocked() -> Bool {
        defer { connectionsWereDocked = false }
        return connectionsWereDocked
    }

    public func lastRunCameBack() { lastRunIsBack = true }

    /// Opens the dock's window, or brings it forward. Asked for once until it is on screen: two
    /// windows docking together each asked, visionOS gave the app two scenes for the one window,
    /// and SwiftUI stopped the app ("Your app was given a scene with id 'orb-dock' but the matching
    /// Window in your app body is already connected", the simulator, 2026-10-25).
    public func open(with openWindow: OpenWindowAction) {
        if !isShown {
            if let askedUntil, ContinuousClock.now < askedUntil { return }
            askedUntil = .now + .seconds(5)
        }
        openWindow(id: GlassOrbDock.windowID)
    }

    /// `id` takes `target`'s place among the orbs `shown` (`GlassOrbDockOrder.move`), kept.
    func move(_ id: String, to target: String?, first: Bool = false, among shown: [String]) {
        order.move(id, to: target, first: first, among: shown)
        order.save(to: GlassUITestRun.settingsDefaults)
    }

    public func dock(_ id: String, size: CGSize?) {
        if !docked.contains(id) { docked.append(id) }
        sizes[id] = size
        standing[id] = nil
    }

    public func isDocked(_ id: String) -> Bool { docked.contains(id) }

    /// The size a docked window grows back to, when it had one.
    public func size(of id: String) -> CGSize? { sizes[id] }

    // MARK: Standing as its orb (D74)

    /// The size a window standing as its orb grows back to; nil while it is open or docked.
    public func standingSize(of id: String) -> CGSize? { standing[id] }

    func stands(_ id: String, growingBackTo size: CGSize) { standing[id] = size }

    func noLongerStands(_ id: String) { standing[id] = nil }

    /// A launch reopens the window as its orb, growing back to `size` when known: it stands as one
    /// from now, and takes it as it appears.
    public func opensAsOrb(_ id: String, growingBackTo size: CGSize?) {
        openingAsOrbs[id] = .some(size)
        standing[id] = GlassConnectionsWindowSize.returning(to: size)
    }

    /// Whether the window appearing now was reopened as its orb, and the size it grows back to.
    func takeOpeningAsOrb(_ id: String) -> (opens: Bool, size: CGSize?) {
        guard let size = openingAsOrbs.removeValue(forKey: id) else { return (false, nil) }
        return (true, size)
    }

    /// The window is on screen again, however it was asked for: out of the dock. Its size there,
    /// to grow back to; nil when it was not docked.
    public func windowAppeared(_ id: String) -> CGSize? {
        guard docked.contains(id) else { return nil }
        docked.removeAll { $0 == id }
        return sizes.removeValue(forKey: id)
    }

    /// Forgets windows whose sessions all ended while they waited.
    func keepOnly(_ open: Set<String>) {
        let ended = docked.filter { !open.contains($0) }
        guard !ended.isEmpty else { return }
        docked.removeAll { ended.contains($0) }
        for id in ended { sizes[id] = nil }
    }

    /// The next window visionOS opens comes back above the dock, at `id`'s size when it has one.
    func returning(_ id: String?) {
        returning.removeAll { $0.until <= .now }
        returning.append((id.flatMap { sizes[$0] }, .now + .seconds(5)))
    }

    /// Where a window opens: above the dock when the dock asked for it, else wherever visionOS
    /// puts it.
    func placement(_ context: WindowPlacementContext) -> WindowPlacement {
        returning.removeAll { $0.until <= .now }
        guard !returning.isEmpty,
              let dock = context.windows.first(where: { $0.id == GlassOrbDock.windowID }) else {
            return WindowPlacement()
        }
        return WindowPlacement(.above(dock), size: returning.removeFirst().size)
    }
}

public extension Scene {
    /// The dock opens at the size the person gave it, wherever visionOS puts it; at its first
    /// otherwise, and fits its orbs (`GlassOrbDockView`).
    func glassOrbDockOpensAtItsSize() -> some Scene {
        defaultWindowPlacement { _, _ in
            WindowPlacement(size: GlassConnectionsWindowSize.stored(
                GlassUITestRun.settingsDefaults.string(forKey: GlassOrbDock.sizeKey) ?? ""))
        }
    }

    /// A window asked for from the dock comes back above it (D88).
    func glassReturnsAboveOrbDock() -> some Scene {
        defaultWindowPlacement { _, context in
            GlassOrbDockModel.shared.placement(context)
        }
    }
}

/// The dock: the Connections orb; an orb for each docked terminal window, its tabs on its ring with
/// what was opened from it; and one for each machine with a database, a desktop or an editor open,
/// docked or not, each of them a dot (D88, revised on the headset: "if I connect mysql on [a
/// machine], then we should show [its] orb with a single mysql tab"). In a row with no panel, close
/// together ("the spacing is about 2x what it should be"), scrolling sideways once it is wider than
/// `widest` ("maybe we need horizontal scroll?"). Connections first, then the rest in the order the
/// owner set by holding an orb and moving it ("so muscle memory can land").
///
/// Its shape decides its direction (the owner, 2026-10-26: "could we make it responsive? A user could
/// then make it vertical with simply resizing it so"): resized taller than wide, its orbs stand in a
/// column. Until the person resizes it, it fits its orbs in a row, as it did when it could not be
/// resized; their size is kept on this device, and it opens at it. Its glass and Opacity are its own,
/// following Appearance until set in Settings ▸ Appearance ▸ Orbs.
public struct GlassOrbDockView: View {
    let model: GlassShellModel
    @State private var dock = GlassOrbDockModel.shared
    /// The dock's size now, as its content fills it.
    @State private var shape: CGSize = .zero
    @State private var sizer = GlassWindowSizer()
    /// The size asked for to fit the orbs, until visionOS has given it; then what it gave.
    @State private var fitting: CGSize?
    @State private var fitted: CGSize?
    @AppStorage(GlassOrbDock.sizeKey, store: GlassUITestRun.settingsDefaults) private var keptSize = ""
    @AppStorage(GlassOrbDock.lookKey, store: GlassUITestRun.settingsDefaults) private var lookData = Data()
    /// The orb held to be moved, and how far it has been carried; gone when the hold ends, however
    /// it ends.
    @GestureState private var held: HeldOrb?
    /// When a held orb was let go: the pinch that let it go is not a pinch on it.
    @State private var letGo: ContinuousClock.Instant?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// An orb with a ring, and one without: the ring's width and a little, a dot's name going under
    /// the orb rather than beside its dot, where it would lie over the next orb.
    static let ringedWidth: CGFloat = 280
    static let plainWidth: CGFloat = 200
    static let height: CGFloat = 320
    /// About six orbs with rings; past it the row scrolls.
    static let widest: CGFloat = 1700
    /// The narrowest window visionOS makes, and the dock's: an orb with a ring, across.
    static let narrowest: CGFloat = GlassConnectionsWindowSize.narrowestWindow
    /// Between the dock's edge and its first orb.
    static let inset: CGFloat = 16
    /// Past the last orb, for its dots' names to open into: a dot opens toward the trailing side.
    static let nameRoom: CGFloat = GlassOrbRingLayout.nameWidth + 20
    /// How long an orb is held before it lifts to be carried.
    static let hold: Double = 0.5

    public init(model: GlassShellModel) { self.model = model }

    public var body: some View {
        let open = model.registry.openSessions()
        let docked = dock.docked.compactMap { id in open.first { $0.id == id } }
        let terminals = docked.filter { Self.kind(of: $0) == .ssh }
        // An editor opened from a terminal in the dock is on that terminal's ring (`orbServiceDots`);
        // any other database, desktop or editor open is on its machine's orb.
        let dockedTerminals = Set(terminals.map(\.id))
        let machines = machines(of: open.filter {
            Self.kind(of: $0) != .ssh && $0.openedFrom.map(dockedTerminals.contains) != true
        })
        let cells = dock.order.arranged(terminals.map { DockCell.terminal(face(of: $0, open: open)) }
                                            + machines.map(DockCell.machine), id: \.id)
        let shown = cells.map(\.id)
        let width = GlassConnectionsOrb.windowSide
            + cells.reduce(0) { $0 + ($1.ringed ? Self.ringedWidth : Self.plainWidth) } + Self.nameRoom
        let fit = CGSize(width: max(min(width + 2 * Self.inset, Self.widest), Self.narrowest), height: Self.height)
        let column = isColumn
        let layout = column ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        // In a column every orb is a ringed one's width, so they stand on one line, the dots' names
        // opening into the room beside them.
        ScrollView(column ? .vertical : .horizontal) {
            layout {
                GlassConnectionsOrb(model: model) { comeBackToConnections() }
                    .frame(width: column ? Self.ringedWidth : nil)
                // Each orb a little in front of the ones after it, toward where names open: a later
                // orb's dots covered an open name (the owner, 2026-10-26: "I was looking at the one on
                // the left and the one to the right opened"). More than a ring's own depth apart.
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    movable(dockCell(cell), id: cell.id, among: cells)
                        .offset(z: CGFloat(cells.count - 1 - index) * (GlassOrbRingLayout.liftSpan + 1))
                }
            }
            // Clear of the dock's edge now it may have a glass of its own, and across its middle.
            .padding(column ? .vertical : .horizontal, Self.inset)
            .padding(.leading, column ? Self.inset : 0)
            .frame(maxWidth: column ? .infinity : nil, maxHeight: column ? nil : .infinity,
                   alignment: column ? .leading : .center)
            .coordinateSpace(.named(Self.row))
        }
        // An orb carried, not the row.
        .scrollDisabled(held != nil)
        .scrollIndicators(.hidden)
        // In a row, past the last orb for its dots' names; in a column they open beside it.
        .contentMargins(.trailing, column ? 0 : Self.nameRoom, for: .scrollContent)
        .frame(minWidth: Self.narrowest, maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity,
               alignment: column ? .topLeading : .leading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized(to: $0) }
        .background { GlassWindowSizerView(sizer: sizer).accessibilityHidden(true) }
        .onChange(of: fit, initial: true) { _, fit in fitToOrbs(fit) }
        // "Fit Dock to Its Orbs" in Settings.
        .onChange(of: keptSize) { _, kept in if kept.isEmpty { fitToOrbs(fit) } }
        .animation(.snappy, value: column)
        #if DEBUG
        // UI tests: `--demo-dock-resize 420x1100` stands for the person resizing the dock a few
        // seconds after it opens: the simulator's runner can't drag a window's corner.
        .task {
            guard let size = GlassOrbDockDemo.resize else { return }
            try? await Task.sleep(for: .seconds(4))
            sizer.resize(to: size, event: "orb-dock-demo")
        }
        #endif
        // Its own glass and Opacity, over Appearance.
        .modifier(GlassOrbDockLook(look: GlassOrbDock.look(from: lookData)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orb-dock")
        .accessibilityValue(column ? "column" : "row")
        .onAppear { dock.isShown = true }
        .onDisappear { dock.isShown = false }
        .onChange(of: open.map(\.id), initial: true) { _, ids in dock.keepOnly(Set(ids)) }
        .onChange(of: dock.docked, initial: true) { _, ids in
            Self.logger.info("dock holds \(ids.joined(separator: ","), privacy: .public); open \(open.map(\.id).joined(separator: ","), privacy: .public); orbs \(terminals.count + machines.count, privacy: .public)")
        }
        // Nothing left in it but Connections, which is open: the dock goes.
        .onChange(of: docked.isEmpty && !dock.holdsConnections) { _, empty in
            if empty { dismissWindow() }
        }
    }

    private func cell(_ face: GlassSessionOrbFace, ringed: Bool, grow: @escaping () -> Void) -> some View {
        GlassSessionOrbView(face: face, expandsDots: true, grow: grow)
            .frame(width: ringed || isColumn ? Self.ringedWidth : Self.plainWidth, height: Self.height)
            // Lands as a drop of water (the owner, 2026-10-25).
            .modifier(GlassOrbDropArrival())
    }

    @ViewBuilder
    private func dockCell(_ cell: DockCell) -> some View {
        switch cell {
        case .terminal(let terminal):
            self.cell(terminal.face, ringed: terminal.ringed, grow: pinched { reopen([terminal.session]) })
        case .machine(let machine):
            self.cell(face(of: machine), ringed: true, grow: pinched { bringBack(machine.sessions) })
        }
    }

    private static let row = "orb-dock-row"

    private struct HeldOrb: Equatable {
        var id: String
        var by: CGFloat
    }

    /// Held (a pinch held, or a click), an orb lifts and follows the hand along the row; let go on
    /// another, it takes that one's place (the owner, 2026-10-25: "pinch/click and hold on a docked
    /// window to move its order so muscle memory can land"), as a row of a window's sidebar does;
    /// over Connections it goes first, past the last, last. The one it is over steps back. Carried
    /// within the dock, by a gesture of its own: a drag and drop could leave the window, and a
    /// terminal takes whatever is dropped on it.
    private func movable(_ cell: some View, id: String, among cells: [DockCell]) -> some View {
        let lifted = held?.id == id
        let under = held.flatMap { landing(of: $0, among: cells) }.flatMap { landing -> String? in
            if case .on(let index) = landing, cells[index].id != held?.id { return cells[index].id }
            return nil
        } == id
        let carried = lifted ? held?.by ?? 0 : 0
        return cell
            .scaleEffect(lifted ? 1.08 : under ? 0.88 : 1)
            .opacity(under ? 0.6 : 1)
            .offset(x: isColumn ? 0 : carried, y: isColumn ? carried : 0)
            .zIndex(lifted ? 1 : 0)
            .animation(.snappy(duration: 0.2), value: under)
            .animation(.snappy(duration: 0.2), value: lifted)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.hold)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.row)))
                    .updating($held) { [column = isColumn] value, held, _ in
                        guard case .second(true, let drag) = value else { return }
                        held = HeldOrb(id: id, by: Self.along(drag?.translation, column: column))
                    }
                    .onEnded { value in
                        guard case .second(true, let drag) = value else { return }
                        letGo = .now
                        put(HeldOrb(id: id, by: Self.along(drag?.translation, column: isColumn)), among: cells)
                    })
    }

    private func landing(of orb: HeldOrb, among cells: [DockCell]) -> GlassOrbDockOrder.Landing? {
        guard let index = cells.firstIndex(where: { $0.id == orb.id }) else { return nil }
        return GlassOrbDockOrder.landing(of: index, carried: orb.by,
                                         widths: cells.map { isColumn ? Self.height : $0.ringed ? Self.ringedWidth : Self.plainWidth })
    }

    /// How far a drag went along the dock.
    private static func along(_ translation: CGSize?, column: Bool) -> CGFloat {
        guard let translation else { return 0 }
        return column ? translation.height : translation.width
    }

    // MARK: Its shape

    /// Taller than wide: a column.
    private var isColumn: Bool { shape.height > shape.width }

    /// Until the person sizes the dock, it fits its orbs in a row.
    private func fitToOrbs(_ fit: CGSize) {
        guard keptSize.isEmpty else { return }
        fitting = fit
        sizer.resize(to: fit, event: "orb-dock-fit") {
            fitting = nil
            fitted = shape
        }
    }

    /// The dock's size now. One the dock did not ask for is the person's: kept, and from then on the
    /// dock keeps it, until Settings fits it to its orbs again.
    private func resized(to size: CGSize) {
        Self.logger.debug("dock shape \(Int(size.width))x\(Int(size.height)) fitting=\(fitting != nil) kept=\(keptSize, privacy: .public)")
        shape = size
        guard fitting == nil, size.width > 0, size.height > 0 else { return }
        // Opening, before it has fitted itself: not the person's.
        if keptSize.isEmpty && fitted == nil { return }
        if let fitted, abs(fitted.width - size.width) < 2, abs(fitted.height - size.height) < 2 { return }
        let kept = GlassConnectionsWindowSize.stored(size)
        guard kept != keptSize else { return }
        Self.logger.info("dock sized \(kept, privacy: .public)")
        keptSize = kept
    }

    private func put(_ orb: HeldOrb, among cells: [DockCell]) {
        let shown = cells.map(\.id)
        withAnimation(.snappy) {
            switch landing(of: orb, among: cells) {
            case .on(let index) where cells[index].id != orb.id:
                dock.move(orb.id, to: cells[index].id, among: shown)
            case .first:
                dock.move(orb.id, to: nil, first: true, among: shown)
            case .last:
                dock.move(orb.id, to: nil, among: shown)
            default:
                return
            }
            Self.logger.info("moved \(orb.id, privacy: .public) by \(Int(orb.by), privacy: .public)")
        }
    }

    /// What a pinch on an orb or its dot does, unless the pinch let go of an orb carried there.
    private func pinched(_ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        {
            if held != nil { return }
            if let letGo, ContinuousClock.now - letGo < .seconds(1) { return }
            action()
        }
    }

    private struct TerminalOrb {
        let session: GlassOpenSession
        let face: GlassSessionOrbFace
        let ringed: Bool
    }

    /// An orb in the row after Connections, by the id its place is kept under.
    private enum DockCell: Identifiable {
        case terminal(TerminalOrb)
        case machine(DockedMachine)

        var id: String {
            switch self {
            case .terminal(let terminal): terminal.session.id
            case .machine(let machine): "machine-" + machine.id
            }
        }

        var ringed: Bool {
            switch self {
            case .terminal(let terminal): terminal.ringed
            case .machine: true
            }
        }
    }

    /// A docked terminal window's orb, drawn from what its capability says of it: its picture, and
    /// its tabs with their agents' marks in colour. Its machine's services are on the machine's orb.
    private func face(of session: GlassOpenSession, open: [GlassOpenSession]) -> TerminalOrb {
        let face = GlassSessionOrbFace(
            title: session.title, symbolName: session.symbolName,
            tabs: session.tabs.map { tab in
                dot(for: tab, select: pinched { reopen([session], by: tab.activate) })
            },
            showsButton: false, dockID: session.id, kind: Self.kind(of: session)
        ) { session.snapshot?() }
        let ringed = !face.ringTabs.isEmpty || open.contains { $0.openedFrom == session.id }
        return TerminalOrb(session: session, face: face, ringed: ringed)
    }

    /// A machine's orb: each database, desktop and editor open on it a dot; its desktop's picture,
    /// if one is open.
    private func face(of machine: DockedMachine) -> GlassSessionOrbFace {
        let desktop = machine.sessions.first { Self.kind(of: $0) == .rdp }
        return GlassSessionOrbFace(
            title: machine.name, symbolName: "server.rack",
            tabs: machine.sessions.map { session in dot(for: session, select: pinched { bringBack([session]) }) },
            showsButton: false, showsSingleTab: true
        ) { desktop?.snapshot?() }
    }

    private func dot(for session: GlassOpenSession, select: @escaping @MainActor () -> Void) -> GlassSessionOrbTab {
        GlassSessionOrbTab(
            id: session.id, title: session.title, symbolName: session.symbolName,
            tint: session.connectedEndpointIDs.isEmpty && !session.endpointIDs.isEmpty ? .secondary : .primary,
            icon: session.icon.map { draw in draw(GlassSessionOrbTab.iconSize) }
                ?? session.mark?().map { mark in
                    AnyView(mark.resizable().scaledToFit()
                        .frame(width: GlassSessionOrbTab.iconSize, height: GlassSessionOrbTab.iconSize))
                },
            growsWindow: false,
            picture: { session.snapshot?() },
            select: select)
    }

    /// Opens windows waiting in the dock again, above it: each session's own, or what `action` asks
    /// for (a tab, which brings its window back on that tab).
    private func reopen(_ sessions: [GlassOpenSession], by action: (@MainActor () -> Void)? = nil) {
        for session in sessions {
            dock.returning(session.id)
            (action ?? session.activate)()
        }
    }

    /// Each one forward, or back from the dock above it.
    private func bringBack(_ sessions: [GlassOpenSession]) {
        for session in sessions { GlassShellModel.bringBack(session) }
    }

    private func comeBackToConnections() {
        dock.holdsConnections = false
        dock.returning(nil)
        openWindow.openConnections()
    }

    /// Sessions by the machine each is on, machines in the order their first came: Active's grouping
    /// (`GlassActiveConnections`).
    private func machines(of sessions: [GlassOpenSession]) -> [DockedMachine] {
        var order: [DockedMachine] = []
        for session in sessions {
            let host = session.endpointIDs.lazy.compactMap { model.host(owningEndpoint: $0) }.first
                ?? session.hostID.flatMap { model.host($0) }
            let id = host?.id.rawValue.uuidString ?? "elsewhere"
            if let index = order.firstIndex(where: { $0.id == id }) {
                order[index].sessions.append(session)
            } else {
                order.append(DockedMachine(id: id, name: host?.displayName ?? "Elsewhere", sessions: [session]))
            }
        }
        return order
    }

    static let logger = Logger(subsystem: "com.glasspowertools", category: "orb-dock")

    /// The service a session is, from its id's prefix (`GlassOpenSession.id`); nil for an editor,
    /// which is no service.
    static func kind(of session: GlassOpenSession) -> HostServiceKind? {
        switch GlassShowAllWindows.kind(of: session) {
        case "terminal": .ssh
        case "database": .database
        case "desktop": .rdp
        default: nil
        }
    }
}

/// The dock's own glass and Opacity over Appearance, painted as every window's are: the theme colour
/// at Opacity in the window's shape, over the window's glass. Clear at 0% of both.
private struct GlassOrbDockLook: ViewModifier {
    let look: GlassWindowOverrides

    func body(content: Content) -> some View {
        GlassLayeredWindow(paintsTheme: true) { content }
            .glassSpatialWindowGlass()
            .glassWindowOverrides(look)
    }
}

#if DEBUG
enum GlassOrbDockDemo {
    static var resize: CGSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"), let index = arguments.firstIndex(of: "--demo-dock-resize"),
              arguments.indices.contains(index + 1) else { return nil }
        return GlassConnectionsWindowSize.stored(arguments[index + 1])
    }
}
#endif

/// A machine with a database, a desktop or an editor open.
private struct DockedMachine: Identifiable {
    let id: String
    let name: String
    var sessions: [GlassOpenSession]
}

extension GlassShellModel {
    /// The machine's open services as dots for an orb's ring (D88; which ones is `orbServices`), a
    /// pinch bringing one forward; then what was opened from the window `from`, an editor from a
    /// terminal's folder button.
    public func orbServiceDots(for endpointIDs: [EndpointID], excluding own: HostServiceKind?,
                               openedFrom from: String? = nil) -> [GlassSessionOrbTab] {
        let open = registry.openSessions()
        let services = orbServices(for: endpointIDs, excluding: own, open: open).compactMap { service -> GlassSessionOrbTab? in
            guard let session = open.first(where: { $0.id == service.openSessionID }) else { return nil }
            return GlassSessionOrbTab(
                id: "service-\(service.endpointID.rawValue.uuidString)",
                title: service.title, symbolName: service.symbolName, tint: .primary, growsWindow: false,
                picture: { session.snapshot?() }, select: { Self.bringBack(session) })
        }
        let opened = from.map { from in open.filter { $0.openedFrom == from } } ?? []
        return services + opened.map { session in
            GlassSessionOrbTab(
                id: "opened-\(session.id)", title: session.title, symbolName: session.symbolName, tint: .primary,
                growsWindow: false, picture: { session.snapshot?() }, select: { Self.bringBack(session) })
        }
    }

    /// Forward, or back from the dock, where it comes back above the dock.
    static func bringBack(_ session: GlassOpenSession) {
        if GlassOrbDockModel.shared.isDocked(session.id) { GlassOrbDockModel.shared.returning(session.id) }
        session.activate()
    }
}
#endif
