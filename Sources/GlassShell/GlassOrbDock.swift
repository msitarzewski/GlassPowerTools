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
//  running, and the dock is one window, moved by its bar. A pinch on an orb opens its window again
//  by the dock (above a wide one, beside a tall one), at the size it had. Off (the default), a
//  window shrinks into its own orb where it is (D74).
//

#if os(visionOS)
import SwiftUI
import UIKit
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
    /// The size the person gave the dock ("1200x320"), empty while it fits its orbs in a row; the
    /// dock snaps around its orbs within it. This device's.
    public static let sizeKey = "com.glasspowertools.orbs.dockSize"
    /// The side a window comes back on from a tall dock, outside Focus Mode (`GlassOrbDockSide`'s
    /// raw value; its right when unset). Settings ▸ Appearance ▸ Orbs; this device's.
    public static let tallSideKey = "com.glasspowertools.orbs.tallDockSide"

    /// The side chosen for windows from a tall dock.
    public static var tallSide: GlassOrbDockSide {
        GlassUITestRun.settingsDefaults.string(forKey: tallSideKey).flatMap(GlassOrbDockSide.init(rawValue:)) ?? .trailing
    }

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
    /// Windows asked for from the dock, until visionOS places them: above it or beside it, each at
    /// its size, in the order asked (a machine's orb asks for all of its windows at once).
    @ObservationIgnored private var returning: [(size: CGSize?, side: GlassOrbDockSide, until: ContinuousClock.Instant)] = []
    /// The dock is taller than wide: windows come back beside it rather than above (set by the dock).
    @ObservationIgnored var isTall = false
    /// Where the last window asked for from the dock was to come back; shown to UI tests, whose
    /// runner reads each window's frame in that window's own space.
    private(set) var lastSide: GlassOrbDockSide?
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
        forgetPicture(id)
        return sizes.removeValue(forKey: id)
    }

    /// Forgets windows whose sessions all ended while they waited.
    func keepOnly(_ open: Set<String>) {
        let ended = docked.filter { !open.contains($0) }
        guard !ended.isEmpty else { return }
        docked.removeAll { ended.contains($0) }
        for id in ended {
            sizes[id] = nil
            forgetPicture(id)
        }
    }

    // MARK: Pictures kept for a relaunch

    /// The picture a docked window had as it docked, kept on the device so its orb has one after a
    /// relaunch, before its window has drawn (the owner, 2026-10-26: "window previews didn't load in
    /// the dock on open. Just terminal icons"). In the app's own Caches, protected while the device
    /// is locked, and deleted when the window leaves the dock or its session ends.
    @ObservationIgnored private var pictures: [String: UIImage] = [:]
    @ObservationIgnored private var noPicture: Set<String> = []

    func keepPicture(_ image: UIImage?, for id: String) {
        guard let image, let data = image.pngData(), let file = Self.pictureFile(id) else { return }
        pictures[id] = image
        noPicture.remove(id)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
        } catch {
            GlassOrbDockView.logger.error("A docked window's picture couldn't be kept: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The picture kept for a docked window, if there is one.
    public func keptPicture(for id: String) -> Image? {
        if let image = pictures[id] { return Image(uiImage: image) }
        guard !noPicture.contains(id), let file = Self.pictureFile(id),
              let image = UIImage(contentsOfFile: file.path) else {
            noPicture.insert(id)
            return nil
        }
        pictures[id] = image
        return Image(uiImage: image)
    }

    private func forgetPicture(_ id: String) {
        pictures[id] = nil
        noPicture.insert(id)
        if let file = Self.pictureFile(id) { try? FileManager.default.removeItem(at: file) }
    }

    private static func pictureFile(_ id: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let name = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return caches.appendingPathComponent("Orb Pictures", isDirectory: true).appendingPathComponent(name + ".png")
    }

    /// The next window visionOS opens comes back by the dock, at `id`'s size when it has one: above a
    /// wide dock; beside a tall one (the owner, 2026-10-26: "it should appear to the left or right
    /// depending on dock position"), away from where the head turned to see it in Focus Mode, else on
    /// the side chosen in Settings (`GlassOrbDockSide`). visionOS tells an app nothing of where its
    /// windows stand, and which way the head is turned only in a Full Space (`GlassHeadTracker`).
    func returning(_ id: String?) {
        returning.removeAll { $0.until <= .now }
        let heading = isTall ? GlassHeadTracker.current?.heading() : nil
        let side = GlassOrbDockSide.returning(tall: isTall, headYaw: heading, otherwise: GlassOrbDock.tallSide)
        GlassOrbDockView.logger.info("returning \(id ?? "connections", privacy: .public) \(String(describing: side), privacy: .public) heading \(heading.map { Int($0 * 180 / .pi) }.map(String.init) ?? "unknown", privacy: .public)")
        returning.append((id.flatMap { sizes[$0] }, side, .now + .seconds(5)))
        lastSide = side
    }

    /// Where a window opens: by the dock when the dock asked for it, else wherever visionOS puts it.
    func placement(_ context: WindowPlacementContext) -> WindowPlacement {
        returning.removeAll { $0.until <= .now }
        guard !returning.isEmpty,
              let dock = context.windows.first(where: { $0.id == GlassOrbDock.windowID }) else {
            return WindowPlacement()
        }
        let next = returning.removeFirst()
        switch next.side {
        case .above: return WindowPlacement(.above(dock), size: next.size)
        case .leading: return WindowPlacement(.leading(dock), size: next.size)
        case .trailing: return WindowPlacement(.trailing(dock), size: next.size)
        }
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

    /// A window asked for from the dock comes back by it (D88): above a wide dock, beside a tall one.
    func glassComesBackByOrbDock() -> some Scene {
        defaultWindowPlacement { _, context in
            GlassOrbDockModel.shared.placement(context)
        }
    }
}

/// The dock: the Connections orb; an orb for each docked terminal window, its tabs on its ring with
/// what was opened from it; and one for each machine with a database, a desktop or an editor open,
/// docked or not, each of them a dot (D88, revised on the headset: "if I connect mysql on [a
/// machine], then we should show [its] orb with a single mysql tab"). Close together ("the spacing is
/// about 2x what it should be"); Connections first, larger and set apart, then the rest in the order
/// the owner set by holding an orb and carrying it ("so muscle memory can land").
///
/// The orbs flow into rows as the dock's shape allows (the owner, 2026-10-26: "respond like a
/// responsive flex with cards in it where the docked windows move to fit the shape of the dock"): a
/// tall, narrow dock is a column; past what fits, it scrolls. Until the person resizes it, it fits its
/// orbs in a row. Resized, it snaps around them once the hand lets go (2026-10-27: "let's make sure it
/// snaps to the shape of the visible icons"): to the widest row they make at that width, and to every
/// row or the whole rows nearest its height (`GlassOrbFlow.snapped`); the size given is kept on this
/// device, and the dock snaps within it again as orbs come and go. Its glass and Opacity are its own,
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
    /// The latest fit asked for: an earlier one finishing does not end it. Two windows docking
    /// together asked twice; the first finishing let the second's new size count as the person's,
    /// and the dock stopped fitting its orbs (seen in the simulator, 2026-10-26).
    @State private var fitAsked = 0
    /// Counts sizes the dock did not ask for: the person's hand on its corner.
    @State private var resizes = 0
    @AppStorage(GlassOrbDock.sizeKey, store: GlassUITestRun.settingsDefaults) private var keptSize = ""
    @AppStorage(GlassOrbDock.lookKey, store: GlassUITestRun.settingsDefaults) private var lookData = Data()
    /// The orb held to be carried, and how far it has gone; gone when the hold ends, however it ends.
    @State private var held: HeldOrb?
    /// When a held orb was let go: the pinch that let it go is not a pinch on it.
    @State private var letGo: ContinuousClock.Instant?
    /// Each orb's place in the dock as last laid out, Connections' too: where a carried orb lands,
    /// and which way its dots' names open.
    @State private var frames: [String: CGRect] = [:]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// An orb with a ring, and one without: the ring's width and a little.
    static let ringedWidth: CGFloat = 280
    static let plainWidth: CGFloat = 200
    static let height: CGFloat = 320
    /// About six orbs with rings; past it, a second row.
    static let widest: CGFloat = 1700
    /// Three rows; past them it scrolls.
    static let tallest: CGFloat = 3 * height
    /// The narrowest window visionOS makes.
    static let narrowest: CGFloat = GlassConnectionsWindowSize.narrowestWindow
    /// Between the dock's edge and its orbs.
    static let inset: CGFloat = 16
    /// Connections, a third larger than the others' circles, and set apart from them (the owner,
    /// 2026-10-26: "bring the connections orb to more prominence").
    static let connectionsScale: CGFloat = 4.0 / 3
    static let connectionsGap: CGFloat = 24
    static let connectionsID = "connections"
    /// How long an orb is held before it lifts to be carried.
    static let hold: Double = 0.5
    /// How long a resized dock waits, once visionOS says the hand has let go, before it snaps.
    static let settle: Double = 0.3

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
        let sizes = [Self.connectionsSize] + cells.map(Self.size(of:))
        let fit = Self.fit(sizes, within: GlassConnectionsWindowSize.stored(keptSize))
        ScrollView(.vertical) {
            GlassOrbFlowLayout(gapAfterFirst: Self.connectionsGap) {
                GlassConnectionsOrb(model: model, scale: Self.connectionsScale) {
                    comeBackToConnections()
                } menu: {
                    connectionsMenu
                }
                .frame(height: Self.height)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.row)) } action: {
                        frames[Self.connectionsID] = $0
                    }
                // Each orb a little in front of the ones after it, toward where names open: a later
                // orb's dots covered an open name (the owner, 2026-10-26: "I was looking at the one on
                // the left and the one to the right opened"). More than a ring's own depth apart.
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    movable(dockCell(cell), id: cell.id, among: cells)
                        .offset(z: CGFloat(cells.count - 1 - index) * (GlassOrbRingLayout.liftSpan + 1))
                }
            }
            // Clear of the dock's edge, now it may have a glass of its own.
            .padding(Self.inset)
            // Holding an orb carries it (`movable`).
            .background {
                GlassOrbCarryProbe(hold: Self.hold) { point in
                    cells.first { frames[$0.id]?.contains(point) == true }?.id
                } changed: { id, phase in
                    carry(id, phase, among: cells)
                }
                .accessibilityHidden(true)
            }
            .coordinateSpace(.named(Self.row))
        }
        // An orb carried, not the dock.
        .scrollDisabled(held != nil)
        .scrollIndicators(.hidden)
        .frame(minWidth: Self.narrowest, maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity,
               alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized(to: $0) }
        .background { GlassWindowSizerView(sizer: sizer).accessibilityHidden(true) }
        // Orbs come and go, or Settings fits it to them again.
        .onChange(of: fit, initial: true) { _, fit in fitToOrbs(fit) }
        // Resized: once the hand has let go, the size given is kept and the dock snaps within it.
        .task(id: resizes) {
            guard resizes > 0 else { return }
            repeat {
                try? await Task.sleep(for: .seconds(Self.settle))
            } while !Task.isCancelled && sizer.isInteractivelyResizing
            guard !Task.isCancelled else { return }
            let given = shape
            keptSize = GlassConnectionsWindowSize.stored(given)
            let snapped = Self.fit(sizes, within: given)
            Self.logger.info("dock sized \(Int(given.width))x\(Int(given.height)), snapped to \(Int(snapped.width))x\(Int(snapped.height))")
            fitToOrbs(snapped)
        }
        // A tall dock sends windows back beside it.
        .onChange(of: isTall, initial: true) { _, tall in dock.isTall = tall }
        #if DEBUG
        // UI tests: `--demo-dock-resize 420x1100` stands for the person resizing the dock a few
        // seconds after it opens: the simulator's runner can't drag a window's corner.
        .task {
            guard let size = GlassOrbDockDemo.resize else { return }
            try? await Task.sleep(for: .seconds(4))
            sizer.resize(to: size, event: "orb-dock-demo")
        }
        // `--demo-dock-carry`: the last orb held and carried onto the first, through what a hold
        // does (`carry`): the runner's hold reaches no UIKit recognizer, and came out as a pinch.
        .task(id: cells.count) {
            guard GlassOrbDockDemo.carries, cells.count >= 2 else { return }
            try? await Task.sleep(for: .seconds(6))
            let from = cells[cells.count - 1].id, to = cells[0].id
            guard let start = frames[from], let end = frames[to] else { return }
            carry(from, .lifted, among: cells)
            carry(from, .dropped(CGSize(width: end.midX - start.midX, height: end.midY - start.midY)), among: cells)
        }
        #endif
        // Its own glass and Opacity, over Appearance.
        .modifier(GlassOrbDockLook(look: GlassOrbDock.look(from: lookData)))
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if GlassOrbDockDemo.marksSides {
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("orb-dock-last-side")
                    .accessibilityValue(dock.lastSide.map { String(describing: $0) } ?? "none")
            }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orb-dock")
        .accessibilityValue(isTall ? "tall" : "wide")
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

    private func cell(_ face: GlassSessionOrbFace, id: String, ringed: Bool, grow: @escaping () -> Void) -> some View {
        GlassSessionOrbView(face: face, expandsDots: true, nameRoom: nameRoom(of: id), grow: grow)
            .frame(width: ringed ? Self.ringedWidth : Self.plainWidth, height: Self.height)
            // Lands as a drop of water (the owner, 2026-10-25).
            .modifier(GlassOrbDropArrival())
    }

    @ViewBuilder
    private func dockCell(_ cell: DockCell) -> some View {
        switch cell {
        case .terminal(let terminal):
            self.cell(terminal.face, id: cell.id, ringed: terminal.ringed, grow: pinched { reopen([terminal.session]) })
        case .machine(let machine):
            self.cell(face(of: machine), id: cell.id, ringed: true, grow: pinched { bringBack(machine.sessions) })
        }
    }

    static let row = "orb-dock-row"

    private struct HeldOrb: Equatable {
        var id: String
        var by: CGSize
    }

    /// Held (a pinch held, or a click), an orb lifts and follows the hand, in any direction; let go
    /// on another, it takes that one's place (the owner, 2026-10-25: "pinch/click and hold on a
    /// docked window to move its order so muscle memory can land"); over Connections it goes first,
    /// past the last, last. The one it is over steps back. A pinch that moves before the hold is done
    /// scrolls the dock (the owner, 2026-10-26: "make sure the a pinch and drag scrolls the dock 100%
    /// of the time"): the hold is UIKit's, which the scroll view's own drag wins from as soon as the
    /// pinch moves (`GlassOrbCarryProbe`). Carried within the dock: a drag and drop could leave the
    /// window, and a terminal takes whatever is dropped on it.
    private func movable(_ cell: some View, id: String, among cells: [DockCell]) -> some View {
        let lifted = held?.id == id
        let under = held.flatMap { landing(of: $0, among: cells) }.flatMap { landing -> String? in
            if case .on(let index) = landing, cells[index].id != held?.id { return cells[index].id }
            return nil
        } == id
        return cell
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.row)) } action: { frames[id] = $0 }
            .scaleEffect(lifted ? 1.08 : under ? 0.88 : 1)
            .opacity(under ? 0.6 : 1)
            .offset(lifted ? held?.by ?? .zero : .zero)
            .zIndex(lifted ? 1 : 0)
            .animation(.snappy(duration: 0.2), value: under)
            .animation(.snappy(duration: 0.2), value: lifted)
    }

    private func carry(_ id: String, _ phase: GlassOrbCarry, among cells: [DockCell]) {
        switch phase {
        case .lifted:
            held = HeldOrb(id: id, by: .zero)
        case .moved(let by):
            held = HeldOrb(id: id, by: by)
        case .dropped(let by):
            letGo = .now
            put(HeldOrb(id: id, by: by), among: cells)
            held = nil
        case .cancelled:
            held = nil
        }
    }

    private func landing(of orb: HeldOrb, among cells: [DockCell]) -> GlassOrbDockOrder.Landing? {
        guard let start = frames[orb.id] else { return nil }
        let point = CGPoint(x: start.midX + orb.by.width, y: start.midY + orb.by.height)
        return GlassOrbDockOrder.landing(at: point, frames: cells.map { frames[$0.id] ?? .null },
                                         before: frames[Self.connectionsID])
    }

    /// The room either side of an orb's middle within the dock, for its dots' names
    /// (`GlassOrbNameSide`); nil until it has been laid out.
    private func nameRoom(of id: String) -> GlassOrbNameRoom? {
        guard let frame = frames[id], shape.width > 0 else { return nil }
        return GlassOrbNameRoom(leading: frame.midX, trailing: shape.width - frame.midX)
    }

    // MARK: Its shape

    /// Taller than wide: windows come back beside it rather than above.
    private var isTall: Bool { shape.height > shape.width }

    static var connectionsSize: CGSize { CGSize(width: GlassConnectionsOrb.windowSide * connectionsScale, height: height) }

    private static func size(of cell: DockCell) -> CGSize {
        CGSize(width: cell.ringed ? ringedWidth : plainWidth, height: height)
    }

    /// The dock's size around these orbs within `given`, the size the person gave it; without one, in
    /// a row as wide as `widest` allows, wrapping up to `tallest`.
    static func fit(_ sizes: [CGSize], within given: CGSize?) -> CGSize {
        GlassOrbFlow.snapped(sizes, within: given ?? CGSize(width: widest, height: tallest + 2 * inset), inset: inset,
                             gapAfterFirst: connectionsGap, minimum: CGSize(width: narrowest, height: height))
    }

    /// The dock takes the size that fits its orbs.
    private func fitToOrbs(_ fit: CGSize) {
        fitting = fit
        fitAsked &+= 1
        let asked = fitAsked
        sizer.resize(to: fit, event: "orb-dock-fit") {
            guard asked == fitAsked else { return }
            fitting = nil
            fitted = shape
        }
    }

    /// The dock's size now. One the dock did not ask for is the person's, and the dock snaps around
    /// its orbs within it once the hand lets go.
    private func resized(to size: CGSize) {
        Self.logger.debug("dock shape \(Int(size.width))x\(Int(size.height)) fitting=\(fitting != nil) kept=\(keptSize, privacy: .public) resizing=\(sizer.isInteractivelyResizing)")
        shape = size
        guard fitting == nil, size.width > 0, size.height > 0 else { return }
        // Opening, before it has fitted itself: not the person's.
        guard let fitted else { return }
        if abs(fitted.width - size.width) < 2, abs(fitted.height - size.height) < 2 { return }
        resizes &+= 1
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
            Self.logger.info("moved \(orb.id, privacy: .public) by \(Int(orb.by.width), privacy: .public),\(Int(orb.by.height), privacy: .public)")
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

    // MARK: Connections' menu

    /// Pinch and hold on Connections (the owner, 2026-10-26: "give it functionality with pinch and hold
    /// actions"; he chose favorites and recents, and Settings): connect to a favorite machine or one
    /// used lately, its window coming out by the dock, or open the dock's settings.
    @ViewBuilder
    private var connectionsMenu: some View {
        let byID = Dictionary(model.hosts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let picked = GlassOrbDockMenu.machines(model.hosts.map(\.id), isFavorite: { model.isFavorite($0) },
                                               lastConnected: { model.lastConnected($0) },
                                               canOpen: { byID[$0].map { !services(of: $0).isEmpty } ?? false })
        let favorites = picked.favorites.compactMap { byID[$0] }
        let recents = picked.recents.compactMap { byID[$0] }
        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { host in connectItem(host) }
            }
        }
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents) { host in connectItem(host) }
            }
        }
        Section {
            Button("Dock Settings", systemImage: "gearshape") { openOrbSettings() }
                .accessibilityIdentifier("orb-dock-settings")
        }
    }

    /// The services Connect can open on a machine here.
    private func services(of host: GlassShellHost) -> [HostServiceLink] {
        let available = Set(model.registry.registeredKinds)
        return host.services.filter { available.contains($0.kind) }
    }

    /// A machine in the menu: its one service, or a menu of them.
    @ViewBuilder
    private func connectItem(_ host: GlassShellHost) -> some View {
        let services = services(of: host)
        if services.count == 1, let service = services.first {
            connectButton(GlassShellModel.paletteName(of: service, on: host), service: service, on: host)
        } else {
            Menu(host.displayName) {
                ForEach(services, id: \.endpointID) { service in
                    connectButton(GlassShellModel.paletteName(of: service, on: host), service: service, on: host)
                }
            }
        }
    }

    private func connectButton(_ title: String, service: HostServiceLink, on host: GlassShellHost) -> some View {
        Button {
            // Its window comes out by the dock, as one brought back does.
            dock.returning(nil)
            model.connect(hostID: host.id, endpointID: service.endpointID)
        } label: {
            Label { Text(title) } icon: { GlassServiceIcon(GlassServicePresentation.symbol(for: service.kind)) }
        }
    }

    /// Settings, on Appearance, where Orbs and the Dock's look are.
    private func openOrbSettings() {
        GlassUITestRun.settingsDefaults.set(GlassShellSettingsPage.appearance.rawValue, forKey: GlassShellSettingsView.paneKey)
        openWindow(id: "settings")
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
        ) { session.snapshot?() ?? GlassOrbDockModel.shared.keptPicture(for: session.id) }
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

/// The orbs in rows that wrap, as `GlassOrbFlow` lays them out.
struct GlassOrbFlowLayout: Layout {
    var gapAfterFirst: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let used = GlassOrbFlow.size(of: frames(subviews, width: width))
        return CGSize(width: width.isFinite ? width : used.width, height: used.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        GlassOrbFlow.frames(of: subviews.map { $0.sizeThatFits(.unspecified) }, width: width, gapAfterFirst: gapAfterFirst)
    }
}

/// What a hold on an orb does as it goes.
enum GlassOrbCarry {
    case lifted
    case moved(CGSize)
    case dropped(CGSize)
    case cancelled
}

/// A hold, then a carry, as UIKit's long press on the dock's window: a pinch that moves before the
/// hold is done fails it, and the scroll view the orbs are in takes the drag. SwiftUI's hold-then-drag
/// it replaces took some quick drags for itself, and the dock scrolled only now and then (the owner,
/// 2026-10-26: "Right now it's a crap shoot"); visionOS offers no way to put a UIKit recognizer on a
/// SwiftUI view, so this view, laid out behind the orbs and scrolling with them, puts one on the
/// window and reads where it is in the orbs' own space. A hold begins only on an orb (`orb`), so a
/// hold on Connections opens its menu (`GlassConnectionsOrb`).
struct GlassOrbCarryProbe: UIViewRepresentable {
    let hold: Double
    /// The orb at a point among the orbs, if one is there.
    let orb: @MainActor (CGPoint) -> String?
    let changed: @MainActor (String, GlassOrbCarry) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.orb = orb
        context.coordinator.changed = changed
        context.coordinator.recognizer.minimumPressDuration = hold
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window, probe: self)
        }
    }

    /// Says what reaches it, for the log.
    final class Recognizer: UILongPressGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            GlassOrbDockView.logger.debug("carry touch began: \(touches.map { String(describing: $0.type.rawValue) }.joined(separator: ","), privacy: .public)")
            super.touchesBegan(touches, with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let recognizer = Recognizer()
        var orb: (@MainActor (CGPoint) -> String?)?
        var changed: (@MainActor (String, GlassOrbCarry) -> Void)?
        private weak var probe: UIView?
        private var carrying: (id: String, start: CGPoint)?

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(handle(_:)))
            recognizer.delegate = self
        }

        func attach(to window: UIWindow?, probe: UIView) {
            self.probe = probe
            guard recognizer.view !== window else { return }
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
            GlassOrbDockView.logger.debug("carry recognizer \(window == nil ? "detached" : "on the dock's window", privacy: .public)")
        }

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        /// Held still long enough: a carry, if the hold is on an orb.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let probe else { return false }
            let location = gestureRecognizer.location(in: probe)
            let id = orb?(location)
            GlassOrbDockView.logger.debug("hold at \(Int(location.x)),\(Int(location.y)) on \(id ?? "no orb", privacy: .public)")
            return id != nil
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let probe else { return }
            let location = recognizer.location(in: probe)
            switch recognizer.state {
            case .began:
                guard let id = orb?(location) else { return }
                carrying = (id, location)
                changed?(id, .lifted)
            case .changed:
                guard let carrying else { return }
                changed?(carrying.id, .moved(CGSize(width: location.x - carrying.start.x, height: location.y - carrying.start.y)))
            case .ended:
                guard let carrying else { return }
                self.carrying = nil
                changed?(carrying.id, .dropped(CGSize(width: location.x - carrying.start.x, height: location.y - carrying.start.y)))
            case .cancelled, .failed:
                guard let carrying else { return }
                self.carrying = nil
                changed?(carrying.id, .cancelled)
            default:
                break
            }
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
    /// Every `--ui-testing` run marks the side the dock last sent a window to (`orb-dock-last-side`).
    static var marksSides: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    static var carries: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--demo-dock-carry")
    }

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

    /// Forward, or back from the dock, where it comes back by the dock.
    static func bringBack(_ session: GlassOpenSession) {
        if GlassOrbDockModel.shared.isDocked(session.id) { GlassOrbDockModel.shared.returning(session.id) }
        session.activate()
    }
}
#endif
