//
//  GlassMacOrbDock.swift
//  Glass Power Tools — GlassShell
//
//  The orb dock on the Mac (D95). The owner, 2026-11-02: "We should consider a dock on Mac, exactly
//  like visionOS for the same reason!" — Vision Pro's dock (D88): a window put away without being
//  closed, its sessions running, and every one in sight at once, each with its coding agents in their
//  colours and pulsing while they print, back with one click. The Mac's own Dock puts windows away
//  too (⌘M, which stays the Mac's), but among every other app's, as still pictures.
//
//  His choices: the orb button docks a window, in its toolbar beside Show All Windows; where the dock
//  floats is a setting (above this app's windows, or above every window); Connections is in the dock.
//
//  One thing is the Mac's own. visionOS cannot hide or move a window, so there a window docks by
//  closing and comes back as a new scene. A Mac window is hidden (`orderOut`) and shown again: nothing
//  is closed, opened again or reconnected. The dock is a panel made and owned here (rule 62), above
//  the app's windows, which it never changes but to hide and show them.
//

#if os(macOS)
import AppKit
import SwiftUI
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers
import os

public enum GlassOrbDock {
    /// Connections in the dock, as the app quit, for the next launch to put back; this Mac's.
    public static let connectionsKey = "com.glasspowertools.orbs.connectionsInDock"
    /// The windows in the dock as the app quit, by their dock ids: terminal windows come back there
    /// (databases, desktops and editors are not reopened at launch). This Mac's.
    public static let dockedKey = "com.glasspowertools.orbs.dockedWindows"
    /// The dock's own Opacity and Glass over Appearance (`GlassWindowOverrides`, as JSON), as on
    /// Vision Pro ("its own, but start with Appearance").
    public static let lookKey = "com.glasspowertools.orbs.dockLook"
    /// The size the person gave the dock ("640x180"), empty while it fits its orbs in a row.
    public static let sizeKey = "com.glasspowertools.orbs.dockSize"
    /// Where Connections' middle stands on the screen ("x,y"), the point the dock grows from. This Mac's.
    public static let rootKey = "com.glasspowertools.orbs.dockRoot"
    /// Where 0.4.577–0.4.579 kept the dock: the middle of its bottom edge ("x,y"). Read for the first
    /// root only, and gone once one is kept.
    public static let placeKey = "com.glasspowertools.orbs.dockPlace"
    /// Where it floats (`GlassOrbDockFloat`). The owner's choice of setting (D95).
    public static let floatKey = "com.glasspowertools.orbs.dockFloats"
    /// The dock id Connections docks under.
    public static let connectionsID = "connections"

    public static func look(from data: Data) -> GlassWindowOverrides {
        (try? JSONDecoder().decode(GlassWindowOverrides.self, from: data)) ?? GlassWindowOverrides()
    }

    public static func data(of look: GlassWindowOverrides) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(look)) ?? Data()
    }

    static let logger = Logger(subsystem: "com.glasspowertools", category: "orb-dock")
}

/// Where the dock floats (D95, the owner: "user choice").
public enum GlassOrbDockFloat: String, CaseIterable, Sendable {
    /// Over this app's windows, and out of sight while another app is in front. The default.
    case aboveThisApp
    /// Over every window, whichever app is in front, on every desktop.
    case aboveAll

    public static var current: GlassOrbDockFloat {
        GlassUITestRun.settingsDefaults.string(forKey: GlassOrbDock.floatKey).flatMap(Self.init(rawValue:)) ?? .aboveThisApp
    }

    public var title: String {
        switch self {
        case .aboveThisApp: "Above This App’s Windows"
        case .aboveAll: "Above All Windows"
        }
    }
}

// MARK: The windows it holds

/// A window the dock can hold: an `NSWindow`, or a stand-in in a test.
@MainActor
protocol GlassDockableWindow: AnyObject {
    /// On screen now: shown, and not in the Mac's Dock.
    var isOnScreen: Bool { get }
    /// Out of sight, fading as it goes when `animated`; `done` once it is gone.
    func putAway(animated: Bool, done: @escaping @MainActor () -> Void)
    /// On screen again, in front, with the keyboard.
    func bringForward()
    /// The window as it looks now, for an orb whose window has no picture of its own.
    func picture() -> Image?
}

extension NSWindow: GlassDockableWindow {
    var isOnScreen: Bool { isVisible && !isMiniaturized }

    func putAway(animated: Bool, done: @escaping @MainActor () -> Void) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            orderOut(nil)
            done()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.orderOut(nil)
                self?.alphaValue = 1
                done()
            }
        }
    }

    func bringForward() {
        alphaValue = 1
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    func picture() -> Image? {
        guard let view = contentView, view.bounds.width > 0, view.bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return Image(nsImage: image)
    }
}

/// The face a window shows in the dock, kept current by the window as it draws.
@MainActor
final class GlassOrbFaceSource {
    var face: GlassSessionOrbFace

    init(_ face: GlassSessionOrbFace) { self.face = face }

    /// Keeps the window's face as it is now; returns nothing, so a body can call it.
    func keep(_ face: GlassSessionOrbFace) { self.face = face }
}

/// The windows waiting in the dock, by their dock ids (`GlassSessionOrbFace.dockID`: a database's,
/// desktop's or editor's open session id; a terminal window's own), and Connections. One for the
/// app.
@MainActor
@Observable
public final class GlassOrbDockModel {
    public static let shared = GlassOrbDockModel(defaults: GlassUITestRun.settingsDefaults)

    /// The docked windows, in the order they came. Connections is not one: its orb is always there.
    public private(set) var docked: [String] = []
    /// Connections is in the dock.
    public private(set) var holdsConnections = false
    /// Where each orb stands, as the person set it by carrying one; this Mac's.
    public private(set) var order: GlassOrbDockOrder

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var windows: [String: WeakDockable] = [:]
    @ObservationIgnored private var faces: [String: GlassOrbFaceSource] = [:]
    /// Pictures taken as windows docked, for those that have none of their own.
    @ObservationIgnored private var pictures: [String: Image] = [:]
    @ObservationIgnored private var connections: WeakDockable?
    /// Going into the dock now, fading: shown, but not coming back.
    @ObservationIgnored private var departing: Set<String> = []
    /// What the last run left in the dock, until each window appears and takes its place there.
    @ObservationIgnored private var lastRun: Set<String>
    @ObservationIgnored private var connectionsLastRun: Bool
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// Shows or hides the dock's panel (`GlassOrbDockPanel`); nothing in a test.
    @ObservationIgnored var presence: (@MainActor (_ shown: Bool) -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        order = GlassOrbDockOrder(defaults: defaults)
        lastRun = Set(defaults.stringArray(forKey: GlassOrbDock.dockedKey) ?? [])
        connectionsLastRun = defaults.bool(forKey: GlassOrbDock.connectionsKey)
    }

    /// Nothing to show: no window in it, and Connections out.
    public var isEmpty: Bool { docked.isEmpty && !holdsConnections }

    public func isDocked(_ id: String) -> Bool { docked.contains(id) }

    /// The face of a docked window, with the picture it had as it docked where it has none now.
    func face(of id: String) -> GlassSessionOrbFace? {
        guard var face = faces[id]?.face else { return nil }
        let own = face.picture, kept = pictures[id]
        face.picture = { own() ?? kept }
        return face
    }

    /// Puts `window` into the dock under `id`: its orb lands as the window fades and goes. A
    /// second ask while it is in the dock does nothing.
    func dock(_ id: String, window: any GlassDockableWindow, face: GlassOrbFaceSource?, animated: Bool = true) {
        watchWindows()
        if id == GlassOrbDock.connectionsID {
            guard !holdsConnections else { return }
            connections = WeakDockable(window)
            departing.insert(id)
            holdsConnections = true
            defaults.set(true, forKey: GlassOrbDock.connectionsKey)
        } else {
            guard !docked.contains(id) else { return }
            windows[id] = WeakDockable(window)
            if let face {
                faces[id] = face
                if face.face.picture() == nil { pictures[id] = window.picture() }
            }
            departing.insert(id)
            docked.append(id)
            save()
        }
        GlassOrbDock.logger.info("docking \(id, privacy: .public)")
        presence?(true)
        window.putAway(animated: animated) { [weak self] in self?.departing.remove(id) }
    }

    /// Brings a docked window back, after `first` (choosing its tab). False when it is not in the
    /// dock or its window has gone.
    @discardableResult
    func bringBack(_ id: String, first: (@MainActor () -> Void)? = nil) -> Bool {
        if id == GlassOrbDock.connectionsID { return bringBackConnections() }
        guard docked.contains(id) else { return false }
        let window = windows[id]?.window
        leave(id)
        guard let window else { return false }
        first?()
        window.bringForward()
        return true
    }

    /// Brings Connections back from the dock; false when it is not there.
    @discardableResult
    public func bringBackConnections() -> Bool {
        guard holdsConnections, let window = connections?.window else {
            if holdsConnections { leaveConnections() }
            return false
        }
        leaveConnections()
        window.bringForward()
        return true
    }

    /// Whether `window` is the Connections window waiting in the dock.
    public func holds(connectionsWindow window: NSWindow) -> Bool {
        holdsConnections && connections?.window === window
    }

    /// Was the window with this dock id in the dock as the last run quit? True once, for the
    /// window that puts itself back.
    func takeLastRun(_ id: String) -> Bool {
        if id == GlassOrbDock.connectionsID {
            defer { connectionsLastRun = false }
            return connectionsLastRun
        }
        return lastRun.remove(id) != nil
    }

    /// `id` takes `target`'s place among the orbs `shown`, kept.
    func move(_ id: String, to target: String?, first: Bool = false, among shown: [String]) {
        order.move(id, to: target, first: first, among: shown)
        order.save(to: defaults)
    }

    /// The windows came and went: one on screen again — Active, Show All Windows, the Window menu —
    /// is out of the dock; one closed or gone is forgotten.
    func windowsChanged() {
        for id in docked where !departing.contains(id) {
            guard let window = windows[id]?.window else {
                forget(id)
                continue
            }
            if window.isOnScreen { leave(id) }
        }
        if holdsConnections, !departing.contains(GlassOrbDock.connectionsID) {
            if let window = connections?.window {
                if window.isOnScreen { leaveConnections() }
            } else {
                leaveConnections()
            }
        }
    }

    /// The window closed while in the dock: its orb goes. Kept in what the next launch puts back
    /// until something else changes it, since the app's own windows close as it quits.
    func closed(_ window: any GlassDockableWindow) {
        for id in docked where windows[id]?.window === window { forget(id, saving: false) }
        if connections?.window === window { leaveConnections(saving: false) }
    }

    private func leave(_ id: String) {
        GlassOrbDock.logger.info("out of the dock: \(id, privacy: .public)")
        docked.removeAll { $0 == id }
        windows[id] = nil
        faces[id] = nil
        pictures[id] = nil
        save()
        if isEmpty { presence?(false) }
    }

    private func forget(_ id: String, saving: Bool = true) {
        GlassOrbDock.logger.info("forgotten: \(id, privacy: .public)")
        docked.removeAll { $0 == id }
        windows[id] = nil
        faces[id] = nil
        pictures[id] = nil
        if saving { save() }
        if isEmpty { presence?(false) }
    }

    private func leaveConnections(saving: Bool = true) {
        holdsConnections = false
        connections = nil
        if saving { defaults.set(false, forKey: GlassOrbDock.connectionsKey) }
        if isEmpty { presence?(false) }
    }

    /// What the next launch puts back: the windows docked now, and those of the last run still on
    /// their way back.
    private func save() {
        defaults.set(docked + lastRun.sorted(), forKey: GlassOrbDock.dockedKey)
    }

    /// The app's windows, watched from the first time one docks.
    private func watchWindows() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.windowsChanged() }
        }
        observers = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didDeminiaturizeNotification].map {
            center.addObserver(forName: $0, object: nil, queue: .main, using: changed)
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let window { self?.closed(window) }
            }
        })
    }

    #if DEBUG
    /// Tests: what the last run left, as a launch reads it.
    func reloadLastRun() {
        lastRun = Set(defaults.stringArray(forKey: GlassOrbDock.dockedKey) ?? [])
        connectionsLastRun = defaults.bool(forKey: GlassOrbDock.connectionsKey)
    }
    #endif
}

/// A docked window, held weakly: the window is its scene's or its controller's, never the dock's.
@MainActor
private final class WeakDockable {
    weak var window: (any GlassDockableWindow)?
    init(_ window: any GlassDockableWindow) { self.window = window }
}

// MARK: A window's orb button

public extension View {
    /// Lets this window go into the orb dock (D95): its bar's Shrink to Orb (`GlassSessionOrbButton`)
    /// puts it there. Attach to the window's whole content, outside its toolbar. A face with no dock
    /// id has no button: a desktop's second screen's window, which goes with its desktop.
    func glassSessionOrb(_ face: GlassSessionOrbFace) -> some View {
        modifier(GlassMacSessionOrbModifier(face: face))
    }
}

private struct GlassMacSessionOrbModifier: ViewModifier {
    let face: GlassSessionOrbFace
    @State private var source: GlassOrbFaceSource?
    @State private var window = GlassOrbWindowBox()
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        // The dock draws a docked window's face as the window last drew it: its tabs and their names.
        let _ = source?.keep(face)
        content
            .environment(\.glassSessionOrb, face.dockID == nil ? nil
                         : GlassSessionOrbControl(shrink: shrink, isOrb: false, isWindow: true))
            .background {
                GlassOrbWindowReader { found in
                    window.window = found
                    putBackIfDockedLastRun(found)
                }
                .accessibilityHidden(true)
            }
            .onAppear {
                if source == nil { source = GlassOrbFaceSource(face) }
                // So the dock can open Connections, and a window, from outside any window.
                GlassWindowOpener.shared.register(openWindow)
            }
    }

    private func shrink() {
        guard let id = face.dockID, let found = window.window else { return }
        let source = source ?? GlassOrbFaceSource(face)
        self.source = source
        source.keep(face)
        GlassOrbDockModel.shared.dock(id, window: found, face: source)
    }

    /// A window the last run left in the dock goes back there as it appears, once it is on screen:
    /// hidden before then, it would be shown again by the scene opening it.
    private func putBackIfDockedLastRun(_ found: NSWindow) {
        guard let id = face.dockID, GlassOrbDockModel.shared.takeLastRun(id) else { return }
        let source = source ?? GlassOrbFaceSource(face)
        self.source = source
        Task { @MainActor in
            for _ in 0..<40 where !found.isVisible {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard found.isVisible else { return }
            GlassOrbDockModel.shared.dock(id, window: found, face: source, animated: false)
        }
    }
}

@MainActor
private final class GlassOrbWindowBox {
    weak var window: NSWindow?
}

/// Zero-size and out of reach: says which window the view is in.
private struct GlassOrbWindowReader: NSViewRepresentable {
    let found: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) { view.found = found }

    final class ReaderView: NSView {
        var found: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found?(window) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: The panel

/// The dock's window: a panel made and owned here (rule 62), never key unless something in it needs
/// the keyboard, so a click on an orb leaves typing where it was.
final class GlassOrbDockWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows and hides the dock, and sizes it to its orbs.
@MainActor
public final class GlassOrbDockPanel: NSObject, NSWindowDelegate {
    public static let shared = GlassOrbDockPanel()

    private var panel: GlassOrbDockWindow?
    /// The size the dock last asked for, with its orbs' cells, Connections first: its first ask comes as its
    /// view is made, before its panel is.
    private var wanted: (size: CGSize, orbs: [CGSize])?
    /// The orbs' cells as the dock last laid them out, Connections first: where Connections is in it.
    private var shown: [CGSize] = [GlassMacOrbDockView.connectionsSize]
    /// Where Connections' middle stands on the screen. The dock grows from it and shrinks back to it (the
    /// owner, 2026-11-02: "Let's tweak the Mac dock to grow from the Active orb out... it should act as
    /// the root position"): to its right as orbs come, rows below it, evenly above and below it as a
    /// ring makes its row taller. Where the person moves it; the screen's edge only holds the dock back.
    private var root: CGPoint?
    /// The dock is moving itself, by this many moves still going: what it moves isn't the person's.
    private var placings = 0
    private var placing: Bool { placings > 0 }
    /// The frame the dock last gave itself. AppKit tells an animated frame change as a live resize, and
    /// one that ends here is the dock's own, not the person's: taken as theirs, a dock fitted to
    /// Connections alone kept that width, and the next orb wrapped out of sight (the VM, 2026-11-02).
    private var fitted: CGRect?
    private var model: GlassShellModel?
    private var layers: GlassLayerStore?
    /// A row or a column, as Settings says now.
    private var orientation: GlassOrbDockOrientation { .current(in: GlassUITestRun.settingsDefaults) }

    /// Called once by the composition root, which holds the library and the layers.
    public func configure(model: GlassShellModel, layers: GlassLayerStore) {
        self.model = model
        self.layers = layers
        GlassOrbDockModel.shared.presence = { [weak self] shown in shown ? self?.show() : self?.hide() }
    }

    /// Whether the dock is on screen.
    public var isShown: Bool { panel?.isVisible == true }

    func show() {
        let panel = self.panel ?? makePanel()
        guard let panel else { return }
        // Drawn afresh each time it comes back: a dock hidden while empty and shown again kept
        // drawing what it held as it went (the VM, 2026-11-02: a window docked, the dock showed
        // Connections alone). As Show All Windows' panel does.
        if panel.contentView == nil, let host = makeHost() {
            panel.contentView = host
        }
        applyFloat()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        hideName()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: Names

    private var nameTag: NSPanel?

    /// `title` just above the dock, over `point` (the middle of what it names, from the dock's top left), as
    /// the Mac's Dock names an icon; below the dock when there is no room above. A vertical dock names beside
    /// it, level with the orb, as the Mac's Dock does on a side of the screen.
    func showName(_ title: String, at point: CGPoint) {
        guard let panel, panel.isVisible else { return }
        let host = NSHostingView(rootView: GlassOrbDockNameTag(title: title))
        let size = host.fittingSize
        let dock = panel.frame
        let room = (panel.screen ?? NSScreen.main)?.visibleFrame ?? dock.insetBy(dx: -2000, dy: -2000)
        var frame = CGRect(origin: .zero, size: size)
        if orientation == .vertical {
            frame.origin.y = dock.maxY - point.y - size.height / 2
            frame.origin.x = dock.maxX + size.width <= room.maxX ? dock.maxX : dock.minX - size.width
        } else {
            frame.origin.x = dock.minX + point.x - size.width / 2
            frame.origin.y = dock.maxY + size.height <= room.maxY ? dock.maxY : dock.minY - size.height
        }
        frame = Self.inside(frame, on: panel.screen ?? NSScreen.main)
        let tag = nameTag ?? makeNameTag()
        tag.contentView = host
        tag.setFrame(frame, display: true)
        tag.level = panel.level
        tag.hidesOnDeactivate = panel.hidesOnDeactivate
        tag.collectionBehavior = panel.collectionBehavior
        if tag.parent == nil { panel.addChildWindow(tag, ordered: .above) }
        tag.orderFront(nil)
    }

    func hideName() {
        guard let tag = nameTag, tag.isVisible else { return }
        tag.parent?.removeChildWindow(tag)
        tag.orderOut(nil)
    }

    private func makeNameTag() -> NSPanel {
        let tag = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        tag.isOpaque = false
        tag.backgroundColor = .clear
        tag.hasShadow = false
        tag.ignoresMouseEvents = true
        tag.isReleasedWhenClosed = false
        tag.animationBehavior = .none
        nameTag = tag
        return tag
    }

    /// Where it floats, as the setting says now: Settings calls this when it changes.
    public func applyFloat() {
        guard let panel else { return }
        switch GlassOrbDockFloat.current {
        case .aboveThisApp:
            panel.hidesOnDeactivate = true
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        case .aboveAll:
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
        panel.level = .floating
    }

    /// The dock takes `size` around `orbs` (their cells, Connections first), with Connections where it
    /// stands (`root`), inside the screen's room. Asked from the dock's own view as it updates, so done
    /// just after: a frame set inside the update was put back (the VM, 2026-11-02: asked for 251 × 194,
    /// it stayed 400 × 156).
    func fit(to size: CGSize, orbs: [CGSize]) {
        guard size.width > 0, size.height > 0, !orbs.isEmpty else { return }
        wanted = (size, orbs)
        DispatchQueue.main.async { [weak self] in self?.applyWanted() }
    }

    private func applyWanted() {
        guard let panel, let wanted else { return }
        let size = panel.frameRect(forContentRect: CGRect(origin: .zero, size: wanted.size)).size
        let offset = GlassMacOrbDockView.root(of: wanted.orbs, orientation: orientation)
        let root = self.root ?? startingRoot(size: size, offset: offset)
        self.root = root
        let frame = Self.inside(Self.frame(of: size, placing: offset, at: root), on: Self.screen(at: root) ?? panel.screen)
        shown = wanted.orbs
        guard frame.integral != panel.frame.integral else { return }
        GlassOrbDock.logger.info("dock fitted \(Int(size.width))x\(Int(size.height)), Connections at \(Int(root.x)),\(Int(root.y))")
        fitted = frame
        placings += 1
        guard panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            placings -= 1
            return
        }
        // A spring, stepped with the display: the glass overshoots its new size a little and settles, as jelly does
        // (the owner, 2026-11-05: "Like a snap to wobble jelly feel?"); until then an ease of 0.28 seconds. Alongside
        // the orbs' own animations, not before them: set with `animate`, the frame held everything else until it had
        // finished, so an orb landing in the dock as it grew stood still, then jumped (the owner, 2026-11-02: "The
        // animations seem pretty low framerate"). Its moves along the way are the dock's until it has finished.
        spring(panel, to: size, placing: offset, at: root)
    }

    /// The dock growing or shrinking to its orbs: quick, past its new size a little and back.
    static let fitSpring = Spring(duration: 0.5, bounce: 0.45)
    /// How long the dock takes to grow or shrink to its orbs: by then within a fifth of a point of still (SwiftUI's own
    /// settling waits 1.3 seconds for less than any screen shows, and the dock's moves aren't the person's till then).
    static let fitDuration: TimeInterval = 0.9

    /// The dock's size `elapsed` into springing from `from` to `to`.
    static func springSize(from: CGSize, to: CGSize, elapsed: TimeInterval) -> CGSize {
        guard elapsed < fitDuration else { return to }
        let width = fitSpring.value(target: Double(to.width - from.width), time: elapsed)
        let height = fitSpring.value(target: Double(to.height - from.height), time: elapsed)
        return CGSize(width: (from.width + width).rounded(), height: (from.height + height).rounded())
    }

    /// The spring under way: from what size to what, Connections where, and since when.
    private var springing: (from: CGSize, to: CGSize, offset: CGPoint, root: CGPoint, start: CFTimeInterval)?
    private var springLink: CADisplayLink?

    private func spring(_ panel: NSPanel, to size: CGSize, placing offset: CGPoint, at root: CGPoint) {
        // A spring under way gives way to this one, from where it has got to.
        if springLink != nil { placings -= 1 }
        springLink?.invalidate()
        springing = (panel.frame.size, size, offset, root, CACurrentMediaTime())
        guard let link = panel.contentView?.displayLink(target: self, selector: #selector(stepSpring(_:))) else {
            springing = nil
            springLink = nil
            panel.setFrame(Self.inside(Self.frame(of: size, placing: offset, at: root), on: Self.screen(at: root) ?? panel.screen),
                           display: true)
            placings -= 1
            return
        }
        springLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func stepSpring(_ link: CADisplayLink) {
        guard let panel, let springing else {
            link.invalidate()
            return
        }
        let elapsed = CACurrentMediaTime() - springing.start
        let size = Self.springSize(from: springing.from, to: springing.to, elapsed: elapsed)
        let frame = Self.inside(Self.frame(of: size, placing: springing.offset, at: springing.root),
                                on: Self.screen(at: springing.root) ?? panel.screen)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        guard elapsed >= Self.fitDuration else { return }
        link.invalidate()
        springLink = nil
        self.springing = nil
        placings -= 1
    }

    /// The dock's frame of `size` with Connections' middle, `offset` from its top left, at `root`.
    static func frame(of size: CGSize, placing offset: CGPoint, at root: CGPoint) -> CGRect {
        CGRect(x: root.x - offset.x, y: root.y + offset.y - size.height, width: size.width, height: size.height)
    }

    /// Where Connections' middle is on the screen now, as the dock shows it.
    private func connectionsPoint(of panel: NSPanel) -> CGPoint {
        let offset = GlassMacOrbDockView.root(of: shown, orientation: orientation)
        return CGPoint(x: panel.frame.minX + offset.x, y: panel.frame.maxY - offset.y)
    }

    /// Connections where the person put it: the dock grows from there from now on, on this Mac.
    private func keepRoot(_ point: CGPoint) {
        root = point
        let defaults = GlassUITestRun.settingsDefaults
        defaults.set("\(Int(point.x.rounded())),\(Int(point.y.rounded()))", forKey: GlassOrbDock.rootKey)
        defaults.removeObject(forKey: GlassOrbDock.placeKey)
    }

    /// Where Connections stands the first time: where the person left it; else with the dock where
    /// 0.4.577–0.4.579 left it, by the middle of its bottom edge; else with the dock low in the middle
    /// of the main screen, above the Mac's Dock.
    private func startingRoot(size: CGSize, offset: CGPoint) -> CGPoint {
        let defaults = GlassUITestRun.settingsDefaults
        if let kept = Self.point(defaults.string(forKey: GlassOrbDock.rootKey)) { return kept }
        let bottom = Self.point(defaults.string(forKey: GlassOrbDock.placeKey))
            ?? NSScreen.main.map { CGPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.minY + 12) } ?? .zero
        return CGPoint(x: bottom.x - size.width / 2 + offset.x, y: bottom.y + size.height - offset.y)
    }

    static func point(_ text: String?) -> CGPoint? {
        let parts = text?.split(separator: ",").compactMap { Double($0) } ?? []
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }

    private static func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    // MARK: NSWindowDelegate

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, !placing else { return }
        if let fitted, abs(panel.frame.width - fitted.width) < 2, abs(panel.frame.height - fitted.height) < 2 { return }
        // An edge dragged: Connections where it shows now; the length dragged to along the line is the dock's longest
        // from now on, to the nearest whole orb (the owner, 2026-11-05: "if it will fit one more and i rezize to ftt,
        // that should be the new max width"); its thickness goes back to one orb's. The whole size dragged to was
        // once kept, and a window docked again wrapped onto a new row. Asked again even when the same as before:
        // dragged taller than its orbs, nothing would change and it would stay as dragged (2026-11-02).
        keepRoot(connectionsPoint(of: panel))
        fitted = nil
        let content = panel.contentRect(forFrameRect: panel.frame).size
        let room = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? content
        let longest = GlassOrbDockLongest.fromHand(
            orientation == .horizontal ? content.width : content.height, sizes: shown, orientation,
            inset: GlassMacOrbDockView.inset, gapAfterFirst: GlassMacOrbDockView.connectionsGap,
            largest: orientation == .horizontal ? room.width : room.height)
        GlassOrbDockLongest.keep(longest, orientation, in: GlassUITestRun.settingsDefaults)
        GlassOrbDock.logger.info("dock dragged to \(Int(content.width))x\(Int(content.height)): longest \(Int(longest))")
        wanted = (GlassMacOrbDockView.fit(shown, orientation: orientation, tallest: tallest, longest: longest), shown)
        DispatchQueue.main.async { [weak self] in self?.applyWanted() }
    }

    /// The most height the dock can take: its screen's room.
    var tallest: CGFloat {
        (panel?.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
    }

    public func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        GlassOrbDock.logger.debug("dock moved to \(Int(panel.frame.minX)),\(Int(panel.frame.minY)) \(Int(panel.frame.width))x\(Int(panel.frame.height)), placing \(self.placings), rows \(self.shown.count)")
        guard !placing else { return }
        keepRoot(connectionsPoint(of: panel))
    }

    // MARK: Making it

    private func makePanel() -> GlassOrbDockWindow? {
        guard let model, let layers else {
            GlassOrbDock.logger.error("The dock was asked for before the app set it up")
            return nil
        }
        let panel = GlassOrbDockWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: GlassMacOrbDockView.lowest),
                                       styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                                       backing: .buffered, defer: false)
        panel.title = "Orbs"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        // Moved by its empty parts alone (`GlassOrbDockMover`): moved by its whole background, a drag on an
        // orb moved the dock rather than the orb (the VM, 2026-11-02).
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass casts its own: the window's drew a dark outline around the glass (D98).
        panel.hasShadow = false
        panel.animationBehavior = .utilityWindow
        panel.contentMinSize = CGSize(width: GlassMacOrbDockView.narrowest, height: GlassMacOrbDockView.lowest)
        panel.delegate = self
        panel.contentView = makeHost()
        panel.setAccessibilityIdentifier("orb-dock-window")
        place(panel)
        self.panel = panel
        applyWanted()
        return panel
    }

    private func makeHost() -> NSView? {
        guard let model, let layers else { return nil }
        let host = NSHostingView(rootView: GlassMacOrbDockView(model: model)
            .glassLayers(layers)
            .environment(model.registry)
            // Not inside a scene: pictures refresh only while the scene is active.
            .environment(\.scenePhase, .active))
        host.sizingOptions = []
        return host
    }

    /// Until the dock's first fit: Connections where it stood last.
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        let offset = GlassMacOrbDockView.root(of: shown, orientation: orientation)
        let root = self.root ?? startingRoot(size: size, offset: offset)
        placings += 1
        panel.setFrame(Self.inside(Self.frame(of: size, placing: offset, at: root), on: Self.screen(at: root) ?? NSScreen.main),
                       display: false)
        placings -= 1
    }

    /// `frame` moved inside the screen's room, where it can be.
    static func inside(_ frame: CGRect, on screen: NSScreen?) -> CGRect {
        guard let room = screen?.visibleFrame else { return frame }
        var moved = frame
        moved.origin.x = min(max(moved.minX, room.minX), max(room.maxX - moved.width, room.minX))
        moved.origin.y = min(max(moved.minY, room.minY), max(room.maxY - moved.height, room.minY))
        return moved
    }

    /// Settings ▸ Appearance, where the dock's settings are: the app menu's own Settings item, as
    /// nothing outside a scene can open the Settings scene.
    static func openSettings() {
        GlassUITestRun.settingsDefaults.set(GlassShellSettingsPage.appearance.rawValue, forKey: GlassShellSettingsView.paneKey)
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: {
                  $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command
              }) else { return }
        NSApp.activate()
        menu.performActionForItem(at: index)
    }
}

// MARK: The dock

/// The dock: Connections, larger and set apart; an orb for each docked terminal window, its tabs on its
/// ring; and one for each machine with a database, a desktop or an editor open, docked or not, each a
/// dot — as on Vision Pro (D88). Drag an orb onto another to take its place; its place is kept. The
/// orbs flow into rows as the dock's shape allows, and the dock fits them in a row until resized,
/// then snaps around them within the size given.
struct GlassMacOrbDockView: View {
    let model: GlassShellModel
    @State private var dock = GlassOrbDockModel.shared
    @State private var shape: CGSize = .zero
    /// The orb being carried, and how far.
    @State private var held: HeldOrb?
    @State private var letGo: ContinuousClock.Instant?
    @State private var frames: [String: CGRect] = [:]
    /// The orb or dot under the pointer, named above the dock as the Mac's Dock names its icons.
    @State private var pointed: Pointed?
    /// Where the dock is scrolled to, and what lies above and below what it shows: an arrow at that
    /// end, as on Vision Pro ("We need end arrows to show that there's more to scroll to").
    @State private var scroll = ScrollPosition()
    @State private var room = GlassOrbDockRoom()
    /// The dock's size and its orbs' have held a moment: the end arrows show only then. Growing to an orb that had
    /// come, the dock briefly showed less than its orbs, and an arrow flashed below them (the VM, 2026-11-02).
    @State private var roomSettled = true
    /// An orb just docked, scrolled into sight once it has its place.
    @State private var arrived: String?
    /// The pushes each orb has had as windows dock and leave: a wave of wobble along the line.
    @State private var jelly = GlassOrbJellyField()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(GlassOrbDock.lookKey, store: GlassUITestRun.settingsDefaults) private var lookData = Data()
    @AppStorage(GlassOrbDockOrientation.key, store: GlassUITestRun.settingsDefaults)
    private var orientationSetting = GlassOrbDockOrientation.horizontal.rawValue
    /// A row or a column, as Settings ▸ Appearance ▸ Orbs says (the owner, 2026-11-05).
    private var orientation: GlassOrbDockOrientation { GlassOrbDockOrientation(rawValue: orientationSetting) ?? .horizontal }
    /// The longest a drag left a row and a column at (`GlassOrbDockLongest`); 0 until one has.
    @AppStorage(GlassOrbDockLongest.key(.horizontal), store: GlassUITestRun.settingsDefaults) private var keptRow = 0.0
    @AppStorage(GlassOrbDockLongest.key(.vertical), store: GlassUITestRun.settingsDefaults) private var keptColumn = 0.0
    private var keptLongest: CGFloat? {
        let kept = orientation == .horizontal ? keptRow : keptColumn
        return kept > 0 ? CGFloat(kept) : nil
    }

    /// Around each orb's farthest dot, so neighbours' dots stand apart. With `inset`, the dock's edge is
    /// the same distance from the orbs on every side (the owner, 2026-11-02: "Seems like this takes up a
    /// lot more space than it should. Let's remove that bottom tab and keep the edges of the dock the same
    /// distance from the windows"): no room is kept for names, which show above the dock.
    static let pad: CGFloat = 6
    static let inset: CGFloat = 10
    static let connectionsScale: CGFloat = 4.0 / 3
    /// How long the dock's size holds before its end arrows show: past its own growing (`GlassOrbDockPanel.fitDuration`).
    static let settling: Duration = .milliseconds(450)
    static let connectionsGap: CGFloat = 8
    /// An orb's cell: as far as its dots reach from its middle, the same each way so its middle is its cell's;
    /// the orb alone with no dots. Two tabs, above and below, leave it as narrow as the orb.
    static func size(ring count: Int) -> CGSize {
        let dot = GlassMacSessionOrbView.dotDiameter / 2
        var reach = CGSize(width: GlassOrbMetrics.orbDiameter / 2, height: GlassOrbMetrics.orbDiameter / 2)
        for index in 0..<count {
            let at = GlassOrbRing.center(of: index, count: count, radius: GlassMacSessionOrbView.ringRadius)
            reach.width = max(reach.width, abs(at.x) + dot)
            reach.height = max(reach.height, abs(at.y) + dot)
        }
        return CGSize(width: (2 * (reach.width + pad)).rounded(.up), height: (2 * (reach.height + pad)).rounded(.up))
    }
    /// A whole ring's height: a row's tallest.
    static var ringedHeight: CGFloat { size(ring: 4).height }
    /// A row's longest until a drag sets one, about seven orbs with rings; past it, it scrolls. A column's is the
    /// screen's room.
    static let widest: CGFloat = 1100
    static var narrowest: CGFloat { connectionsSize.width + 2 * inset }
    static var lowest: CGFloat { connectionsSize.height + 2 * inset }
    static let row = "orb-dock-row"
    static let connectionsCell = "connections"

    var body: some View {
        // Each second: the pictures, and the faces the windows keep current.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            dockContent
        }
        .modifier(GlassMacOrbDockLook(look: GlassOrbDock.look(from: lookData)))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { shape = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orb-dock")
    }

    private var dockContent: some View {
        let open = model.registry.openSessions()
        let cells = cells(open: open)
        let sizes = [Self.connectionsSize] + cells.map(Self.size(of:))
        let orientation = orientation
        let fit = Self.fit(sizes, orientation: orientation, tallest: GlassOrbDockPanel.shared.tallest, longest: keptLongest)
        return VStack(spacing: 0) {
            ScrollView(orientation.axis) {
            // Each drop's glass on its own, not drawn together in a `GlassEffectContainer`: there, what isn't glass
            // lay under the glass (Connections' count), a drop drawn again grew back from nothing, scaling went
            // unseen, and Connections alone stood in the middle of a dock still growing (the VM, 2026-11-02; the
            // owner: "The icons animate on hover, but up and to the left?").
            GlassOrbLineLayout(orientation: orientation, gapAfterFirst: Self.connectionsGap) {
                GlassMacConnectionsOrb(model: model, scale: Self.connectionsScale, point: point(at: Self.connectionsCell)) {
                    if !dock.bringBackConnections() { GlassWindowOpener.shared.perform { $0.openConnections() } }
                } menu: {
                    connectionsMenu
                }
                .frame(width: Self.connectionsSize.width, height: Self.connectionsSize.height)
                .environment(\.glassOrbKicks, jelly.kicks(for: Self.connectionsCell))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.row)) } action: {
                    frames[Self.connectionsCell] = $0
                }
                ForEach(cells) { cell in
                    movable(cell, among: cells)
                        .environment(\.glassOrbKicks, jelly.kicks(for: cell.id))
                }
            }
            // The rest slide over to make room or close a gap, with a spring's snap.
            .animation(reduceMotion ? nil : GlassOrbJellyMotion.slide, value: cells.map(\.id))
            .padding(Self.inset)
            // Any empty part of the dock moves it; the orbs are carried, not the dock.
            .background { GlassOrbDockMover().accessibilityHidden(true) }
            .coordinateSpace(.named(Self.row))
            }
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: GlassOrbDockRoom.self) { geometry in
                orientation.room(geometry)
            } action: { _, room in self.room = room }
            // Never, not hidden: with a mouse attached, the Mac shows a hidden scroller anyway, which took
            // its width from the orbs while the dock was still Connections' width as an orb came, so they
            // stayed wrapped into a column below a scroll bar once the dock had grown (the VM, 2026-11-02).
            // The end arrows say there's more.
            .scrollIndicators(.never)
            .scrollDisabled(held != nil)
            // More along the line: an arrow at that end, which a click scrolls an orb that way.
            .overlay(alignment: orientation.arrowAlignment(back: true)) { if roomSettled, room.above > 1 { moreArrow(back: true) } }
            .overlay(alignment: orientation.arrowAlignment(back: false)) { if roomSettled, room.below > 1 { moreArrow(back: false) } }
            .task(id: CGSize(width: room.shown, height: room.content)) {
                roomSettled = false
                try? await Task.sleep(for: Self.settling)
                if !Task.isCancelled { roomSettled = true }
            }
        }
        // Under the panel's clear title bar too: the dock is all orbs.
        .ignoresSafeArea()
        // The orbs too, as where Connections is among them can change with the dock's size the same.
        .onChange(of: Fitted(size: fit, orbs: sizes), initial: true) { _, fitted in
            GlassOrbDockPanel.shared.fit(to: fitted.size, orbs: fitted.orbs)
        }
        .onChange(of: pointed) { _, pointed in name(pointed) }
        // Orbs there as the dock opens land in it, as they fall into it (`GlassOrbDropArrival`).
        .onAppear {
            jelly.changed(from: [Self.connectionsCell], to: [Self.connectionsCell] + cells.map(\.id), along: orientation)
        }
        .onDisappear { GlassOrbDockPanel.shared.hideName() }
        // An orb docked past what the dock shows at its longest: scrolled to.
        .onChange(of: cells.map(\.id)) { old, new in
            GlassOrbDock.logger.info("dock holds \(new.joined(separator: ","), privacy: .public)")
            jelly.changed(from: [Self.connectionsCell] + old, to: [Self.connectionsCell] + new, along: orientation)
            guard let id = new.last(where: { !old.contains($0) }) else { return }
            arrived = id
        }
        .task(id: arrived) {
            guard let id = arrived else { return }
            // Its place, and the dock's new size.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let frame = frames[id] else { return }
            arrived = nil
            let start = orientation.start(of: frame) - Self.inset, end = orientation.end(of: frame) + Self.inset
            if start < room.offset - 1 || end > room.offset + room.shown + 1 {
                let to = min(start, room.content - room.shown)
                withAnimation(.smooth) { orientation == .horizontal ? scroll.scrollTo(x: to) : scroll.scrollTo(y: to) }
            }
        }
    }

    /// An arrow at the dock's start (`back`) or end where there is more; a click scrolls an orb that way.
    private func moreArrow(back: Bool) -> some View {
        let arrow = orientation.moreArrow(back: back)
        let horizontal = orientation == .horizontal
        return Button {
            let starts = Set(frames.values.map { (orientation.start(of: $0) - Self.inset).rounded() }).sorted()
            let end = max(room.content - room.shown, 0)
            let next = back ? starts.last { $0 < room.offset - 1 } ?? 0 : starts.first { $0 > room.offset + 1 } ?? end
            let to = min(max(next, 0), end)
            withAnimation(.smooth) { horizontal ? scroll.scrollTo(x: to) : scroll.scrollTo(y: to) }
        } label: {
            Label(arrow.title, systemImage: arrow.symbol)
                .labelStyle(.iconOnly)
                .font(.callout.weight(.semibold))
                .frame(width: horizontal ? 18 : 36, height: horizontal ? 36 : 18)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(4)
        .help(arrow.title)
        .accessibilityIdentifier(arrow.id)
    }

    // MARK: Orbs

    private enum Cell: Identifiable {
        /// A docked window drawn from its own face: a terminal window.
        case window(id: String, face: GlassSessionOrbFace)
        case machine(DockedMachine)

        var id: String {
            switch self {
            case .window(let id, _): id
            case .machine(let machine): "machine-" + machine.id
            }
        }

        /// How many dots stand around its orb.
        var dots: Int {
            switch self {
            case .window(_, let face): face.ringTabs.count
            case .machine(let machine): min(machine.sessions.count, GlassOrbMetrics.maximumTabs)
            }
        }
    }

    /// The docked windows drawn from their faces, then a machine for each with a database, a desktop
    /// or an editor open, in the order the person set.
    private func cells(open: [GlassOpenSession]) -> [Cell] {
        let windows = dock.docked.filter { !Self.isMachineService($0) }.compactMap { id -> Cell? in
            dock.face(of: id).map { .window(id: id, face: $0) }
        }
        let machines = machines(of: open.filter { Self.isMachineService($0.id) }).map(Cell.machine)
        return dock.order.arranged(windows + machines, id: \.id)
    }

    /// A database, a desktop or an editor: on its machine's orb, docked or not.
    static func isMachineService(_ id: String) -> Bool {
        ["database", "desktop", "editor"].contains(id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "")
    }

    @ViewBuilder
    private func orb(_ cell: Cell) -> some View {
        switch cell {
        case .window(let id, let face):
            GlassMacSessionOrbView(face: face, point: point(at: cell.id)) {
                clicked { dock.bringBack(id) }
            } choose: { tab in
                clicked { dock.bringBack(id, first: tab.select) }
            }
        case .machine(let machine):
            GlassMacSessionOrbView(face: face(of: machine), point: point(at: cell.id)) {
                clicked { for session in machine.sessions { bringBack(session) } }
            } choose: { tab in
                clicked { if let session = machine.sessions.first(where: { $0.id == tab.id }) { bringBack(session) } }
            }
        }
    }

    /// A docked window's own: shown again. One that is open: forward, as Active brings it.
    private func bringBack(_ session: GlassOpenSession) {
        if !dock.bringBack(session.id) { session.activate() }
    }

    private func face(of machine: DockedMachine) -> GlassSessionOrbFace {
        let desktop = machine.sessions.first { GlassShowAllWindows.kind(of: $0) == "desktop" }
        return GlassSessionOrbFace(
            title: machine.name, symbolName: "server.rack",
            tabs: machine.sessions.map { session in
                GlassSessionOrbTab(
                    id: session.id, title: session.title, symbolName: session.symbolName,
                    tint: session.connectedEndpointIDs.isEmpty && !session.endpointIDs.isEmpty ? .secondary : .primary,
                    icon: session.icon.map { draw in draw(GlassSessionOrbTab.iconSize) },
                    growsWindow: false,
                    picture: { session.snapshot?() },
                    select: {})
            },
            showsButton: false, showsSingleTab: true
        ) { desktop?.snapshot?() }
    }

    // MARK: Carrying

    private struct HeldOrb: Equatable {
        var id: String
        var by: CGSize
    }

    /// An orb a drag carries, in any direction; let go on another, it takes that one's place, as on
    /// Vision Pro ("pinch/click and hold on a docked window to move its order so muscle memory can
    /// land"); over Connections it goes first, past the last, last. The one under it steps back.
    private func movable(_ cell: Cell, among cells: [Cell]) -> some View {
        let lifted = held?.id == cell.id
        let under = held.flatMap { landing(of: $0, among: cells) }.flatMap { landing -> String? in
            if case .on(let index) = landing, cells[index].id != held?.id { return cells[index].id }
            return nil
        } == cell.id
        return orb(cell)
            .frame(width: Self.size(of: cell).width, height: Self.size(of: cell).height)
            .modifier(GlassOrbDropArrival())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.row)) } action: { frames[cell.id] = $0 }
            .scaleEffect(lifted ? 1.08 : under ? 0.88 : 1)
            .opacity(under ? 0.6 : 1)
            .offset(lifted ? held?.by ?? .zero : .zero)
            .zIndex(lifted || pointed?.cell == cell.id ? 1 : 0)
            .animation(.snappy(duration: 0.2), value: under)
            .animation(.snappy(duration: 0.2), value: lifted)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.row))
                    .onChanged { drag in held = HeldOrb(id: cell.id, by: drag.translation) }
                    .onEnded { drag in
                        letGo = .now
                        put(HeldOrb(id: cell.id, by: drag.translation), among: cells)
                        held = nil
                    }
            )
    }

    private func landing(of orb: HeldOrb, among cells: [Cell]) -> GlassOrbDockOrder.Landing? {
        guard let start = frames[orb.id] else { return nil }
        let point = CGPoint(x: start.midX + orb.by.width, y: start.midY + orb.by.height)
        return GlassOrbDockOrder.landing(at: point, frames: cells.map { frames[$0.id] ?? .null },
                                         before: frames[Self.connectionsCell])
    }

    private func put(_ orb: HeldOrb, among cells: [Cell]) {
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
        }
    }

    /// What a click does, unless it is the end of a drag that carried the orb.
    private func clicked(_ action: @MainActor () -> Void) {
        if held != nil { return }
        if let letGo, ContinuousClock.now - letGo < .milliseconds(400) { return }
        action()
    }

    // MARK: Connections' menu

    /// Right-click on Connections: connect to a favorite machine or one used lately, or the dock's
    /// settings — Vision Pro's pinch and hold.
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
            Button("Dock Settings…", systemImage: "gearshape") { GlassOrbDockPanel.openSettings() }
                .accessibilityIdentifier("orb-dock-settings")
        }
    }

    private func services(of host: GlassShellHost) -> [HostServiceLink] {
        let available = Set(model.registry.registeredKinds)
        return host.services.filter { available.contains($0.kind) }
    }

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
            NSApp.activate()
            model.connect(hostID: host.id, endpointID: service.endpointID)
        } label: {
            Label { Text(title) } icon: { GlassServiceIcon(GlassServicePresentation.symbol(for: service.kind)) }
        }
    }

    // MARK: Its shape

    /// Connections' circle, with its count hanging below the rim and the same room above, so its middle is
    /// on the line through the other orbs' middles.
    static var connectionsSize: CGSize {
        let diameter = GlassOrbMetrics.orbDiameter * connectionsScale
        return CGSize(width: diameter + 2 * pad, height: diameter + 2 * GlassMacConnectionsOrb<EmptyView>.badgeDrop + 2 * pad)
    }

    private static func size(of cell: Cell) -> CGSize { size(ring: cell.dots) }

    /// The dock's size around these orbs in a row or a column, whatever size it was dragged to (the owner,
    /// 2026-11-02: "it should also spring back to the shape that shows all of the orbs"; 2026-11-05: horizontal or
    /// vertical, honoured as orbs come and go): every orb, or the whole orbs that fit in a row `widest` long or a
    /// column `tallest` long (the screen's room), the rest scrolled to.
    static func fit(_ sizes: [CGSize], orientation: GlassOrbDockOrientation = .horizontal,
                    tallest: CGFloat = .greatestFiniteMagnitude, longest kept: CGFloat? = nil) -> CGSize {
        let own = orientation == .horizontal ? widest : tallest
        return GlassOrbLine.fitted(sizes, orientation, inset: inset, gapAfterFirst: connectionsGap,
                                   longest: orientation == .horizontal ? kept ?? own : min(kept ?? own, tallest),
                                   minimum: CGSize(width: narrowest, height: lowest))
    }

    /// Connections' middle, from the top left of a dock around orbs of `sizes` (Connections first), as the dock lays
    /// them out: the point the dock grows from (`GlassOrbDockPanel`).
    static func root(of sizes: [CGSize], orientation: GlassOrbDockOrientation = .horizontal) -> CGPoint {
        let first = GlassOrbLine.frames(of: sizes, orientation, gapAfterFirst: connectionsGap).first ?? .zero
        return CGPoint(x: inset + first.midX, y: inset + first.midY)
    }

    /// The dock's size and its orbs' cells, as the panel is asked to fit them.
    private struct Fitted: Equatable {
        var size: CGSize
        var orbs: [CGSize]
    }

    // MARK: Names

    /// What is under the pointer: an orb or one of its dots, its name, its cell, and where it is from
    /// its cell's middle.
    private struct Pointed: Equatable {
        var key: String
        var title: String
        var cell: String
        var offset: CGPoint
    }

    /// What an orb in `cell` says as the pointer comes onto one of its parts (`key`), with its name, or
    /// leaves it, with none. Leaving one part after coming onto the next changes nothing.
    private func point(at cell: String) -> @MainActor (_ key: String, _ title: String?, _ offset: CGPoint) -> Void {
        { key, title, offset in
            let key = cell + "/" + key
            if let title {
                pointed = Pointed(key: key, title: title, cell: cell, offset: offset)
            } else if pointed?.key == key {
                pointed = nil
            }
        }
    }

    /// The name above the dock, over what it names: from the dock's top left, the middle of it.
    private func name(_ pointed: Pointed?) {
        guard let pointed, held == nil, let frame = frames[pointed.cell] else {
            GlassOrbDockPanel.shared.hideName()
            return
        }
        GlassOrbDockPanel.shared.showName(pointed.title, at: CGPoint(x: frame.midX + pointed.offset.x,
                                                                    y: frame.midY + pointed.offset.y - room.offset))
    }

    /// Sessions by the machine each is on, machines in the order their first came: Active's grouping.
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
}

/// A machine with a database, a desktop or an editor open.
private struct DockedMachine: Identifiable {
    let id: String
    let name: String
    var sessions: [GlassOpenSession]
}

/// The dock's own Glass, Material and Opacity over Appearance, as Apple's Liquid Glass (`GlassLiquidSurface`):
/// a slab its orbs float on, as drops of the same glass. It was a presented panel's frost, which on an even
/// wallpaper was a flat grey card (the owner, 2026-11-02: "It's as flat as flat is", beside Control Center's
/// Clear look). Not a window's title bar either: that kept a title bar's full material, a band across the dock's
/// top (his screenshot, 2026-11-02).
private struct GlassMacOrbDockLook: ViewModifier {
    let look: GlassWindowOverrides
    @Environment(\.glassLayers) private var layers
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Control Center's modules' corners, near enough.
    static let cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let state = GlassLayerResolution.resolve(layers.state, window: look, reduceTransparency: reduceTransparency)
        let liquid = GlassLiquidLook(state)
        content
            .background { GlassLiquidSurface(liquid, cornerRadius: Self.cornerRadius) }
            .environment(\.glassLiquidKind, liquid.kind)
            // To the panel's top edge: its clear title bar is the dock's too.
            .ignoresSafeArea()
            .glassWindowOverrides(look)
            // Drawn as the active window, which it never is. macOS draws Liquid Glass clear, as Control Center's,
            // only in the key window of the app in front, and frosted in every other window; neither 26.6 (the VM)
            // nor 27.2 (the owner's Mac, 0.4.588) takes this for glass, and other developers report no public way
            // (D98). It still draws the dock's controls as active.
            .environment(\.appearsActive, true)
    }
}

/// Behind the orbs: a drag on any empty part of the dock moves it (the owner, 2026-11-02, asking for the bar
/// under it to go). Only here: moved by the panel's whole background, a drag on an orb moved the dock rather
/// than the orb.
private struct GlassOrbDockMover: NSViewRepresentable {
    func makeNSView(context: Context) -> MoverView { MoverView() }
    func updateNSView(_ view: MoverView, context: Context) {}

    final class MoverView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: The orbs

/// An orb in the dock: the window's picture in a glass sphere, pulsing while it is busy; its tabs on a
/// ring around it. Pointing at the orb or a dot names it above the dock (`point`), and a dot shows its
/// tab's picture in the orb. A click on the orb brings the window back; on a dot, on that tab.
struct GlassMacSessionOrbView: View {
    let face: GlassSessionOrbFace
    /// Says what the pointer is on, by a key, with its name and its place from the orb's middle; with
    /// no name as it leaves.
    let point: @MainActor (_ key: String, _ title: String?, _ offset: CGPoint) -> Void
    let bringBack: () -> Void
    let choose: (GlassSessionOrbTab) -> Void
    @State private var overOrb = false
    @State private var overTab: String?
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.glassLiquidKind) private var glass

    static let dotDiameter: CGFloat = 24
    static let gap: CGFloat = 10
    static var ringRadius: CGFloat { GlassOrbMetrics.orbDiameter / 2 + gap + dotDiameter / 2 }
    /// The glass around the window's picture: the drop's edge, which bends what lies behind it.
    static let rim: CGFloat = 4

    var body: some View {
        let tabs = face.ringTabs
        ZStack {
            orb(tabs)
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let at = GlassOrbRing.center(of: index, count: tabs.count, radius: Self.ringRadius)
                let x = layoutDirection == .rightToLeft ? -at.x : at.x
                dot(tab, at: CGPoint(x: x, y: at.y))
                    .modifier(GlassOrbBud(to: CGSize(width: x, height: at.y), order: index))
                    .zIndex(overTab == tab.id ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: overOrb)
        .animation(.easeOut(duration: 0.15), value: overTab)
    }

    /// A drop of glass with the window's picture inside it, rounded as a sphere is; Apple's glass makes its rim,
    /// bending what lies behind the drop. It was the picture on glass that its picture hid, so the orb showed no
    /// glass but a thin grey ring (the owner, 2026-11-02: "make the icons liquid drops like buttons vs the gray
    /// background").
    private func orb(_ tabs: [GlassSessionOrbTab]) -> some View {
        let diameter = GlassOrbMetrics.orbDiameter
        let inner = diameter - 2 * Self.rim
        let shownTab = tabs.first { $0.id == overTab }
        return Button(action: bringBack) {
            ZStack {
                if let backdrop = face.backdrop { backdrop }
                picture((shownTab?.picture()).flatMap { $0 } ?? face.picture(), symbolName: shownTab?.symbolName ?? face.symbolName,
                        diameter: inner)
            }
            .frame(width: inner, height: inner)
            .clipShape(.circle)
            // Stretched with the drop's rim and rippled while busy (`GlassOrbLiquid`).
            .modifier(GlassOrbLiquidWarp(diameter: inner))
            .frame(width: diameter, height: diameter)
            // The sphere's light, the cut and the glass in the drop's shape, wobbling with it.
            .modifier(GlassOrbLiquidRim(diameter: diameter, inner: inner, glass: glass.glass.interactive()))
            .overlay { if busy { GlassSessionOrbPulse() } }
            .overlay { if face.rimsBell { GlassSessionOrbBellRim() } }
            .scaleEffect(overOrb ? 1.06 : 1)
            .contentShape(.circle)
        }
        .buttonStyle(GlassMacOrbPressStyle())
        .modifier(GlassOrbLiquidSource(busy: busy))
        .onHover { inside in
            overOrb = inside
            point("orb", inside ? face.title : nil, .zero)
        }
        .accessibilityLabel(face.title)
        .accessibilityHint("Brings the window back")
        .accessibilityIdentifier("session-orb")
    }

    /// Busy: its session prints, where its window asked to show that.
    private var busy: Bool {
        #if DEBUG
        face.pulses || GlassOrbLiquid.demoBusy
        #else
        face.pulses
        #endif
    }

    private func dot(_ tab: GlassSessionOrbTab, at place: CGPoint) -> some View {
        let side = Self.dotDiameter
        return Button { choose(tab) } label: {
            dotIcon(tab)
                .frame(width: side, height: side)
                // A drop of the dock's glass, as Control Center's round buttons are: clear, not grey.
                .glassEffect(glass.glass.interactive(), in: .circle)
                .scaleEffect(overTab == tab.id ? 1.15 : 1)
                .contentShape(.circle)
        }
        .buttonStyle(GlassMacOrbPressStyle())
        .onHover { inside in
            if inside { overTab = tab.id } else if overTab == tab.id { overTab = nil }
            point("tab-" + tab.id, inside ? tab.title : nil, place)
        }
        .accessibilityLabel("Open \(tab.title)")
        .accessibilityIdentifier("session-orb-tab-\(tab.id)")
    }

    @ViewBuilder
    private func dotIcon(_ tab: GlassSessionOrbTab) -> some View {
        if let icon = tab.icon {
            icon
        } else {
            Image(systemName: tab.symbolName)
                .font(.system(size: GlassOrbMetrics.iconSize - 2, weight: .semibold))
                .foregroundStyle(tab.tint)
        }
    }

    @ViewBuilder
    private func picture(_ image: Image?, symbolName: String, diameter: CGFloat) -> some View {
        if let image {
            image.resizable().aspectRatio(contentMode: .fill)
                .frame(width: diameter, height: diameter)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: diameter, height: diameter)
        }
    }
}

/// A dot budding out of its orb as a drop does, as the orb first shows (the owner, 2026-11-02: the dock didn't
/// "really have any actual liquid feel"): from the orb's rim out to its place on the ring, swelling as it goes, each
/// in turn around it. In place at once with Reduce Motion.
struct GlassOrbBud: ViewModifier {
    /// Its place on the ring, from the orb's middle.
    let to: CGSize
    let order: Int
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far along the way out a dot starts: its edge on the orb's rim.
    static func start(of offset: CGSize) -> CGFloat {
        let length = hypot(offset.width, offset.height)
        guard length > 0 else { return 0 }
        return max(0, GlassOrbMetrics.orbDiameter / 2 - GlassMacSessionOrbView.dotDiameter / 2) / length
    }

    func body(content: Content) -> some View {
        let along = out || reduceMotion ? 1 : Self.start(of: to)
        content
            .scaleEffect(out || reduceMotion ? 1 : 0.6)
            .offset(x: to.width * along, y: to.height * along)
            .onAppear {
                guard !out, !reduceMotion else { return }
                withAnimation(.spring(duration: 0.6, bounce: 0.38).delay(0.2 + 0.035 * Double(order))) { out = true }
            }
    }
}

/// A name above the dock, as the Mac's Dock names an icon: its own little window, so it takes no room
/// in the dock (the owner chose "Above the dock", 2026-11-02).
struct GlassOrbDockNameTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            // As wide as its words, up to the limit, then shortened in the middle.
            .frame(maxWidth: 280)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.thickMaterial, in: .capsule)
            .overlay { Capsule().strokeBorder(.separator) }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            // Room for the shadow inside its window.
            .padding(6)
    }
}

/// Connections in the dock: the app's icon floating in a drop of the dock's glass, as every orb is one, and
/// Active's count on its rim with Active's bolt; named above the dock while the pointer is on it, as every orb is.
/// First, and larger; its middle on the line the other orbs' middles are on. It was Vision Pro's white circle
/// (the owner, 2026-11-02: "follow the vision model (all white circle, connection count and centered with the
/// other orbs"), until the dock became Liquid Glass ("Give the Connections orb the same liquid glass treatment?"):
/// the icon's own layers (`GlassPowerToolsMark`), without the white they stand on in the app's icon.
struct GlassMacConnectionsOrb<Items: View>: View {
    let model: GlassShellModel
    let scale: CGFloat
    /// Says the pointer is on it, with its name, or has left it (`GlassMacSessionOrbView.point`).
    let point: @MainActor (_ key: String, _ title: String?, _ offset: CGPoint) -> Void
    let restore: () -> Void
    @ViewBuilder let menu: Items
    @State private var over = false
    @Environment(\.glassLiquidKind) private var glass

    init(model: GlassShellModel, scale: CGFloat,
         point: @escaping @MainActor (_ key: String, _ title: String?, _ offset: CGPoint) -> Void,
         restore: @escaping () -> Void, @ViewBuilder menu: () -> Items) {
        self.model = model
        self.scale = scale
        self.point = point
        self.restore = restore
        self.menu = menu()
    }

    /// How far the count hangs below the circle's rim: half its height, so it straddles the rim.
    static var badgeDrop: CGFloat { 9 }

    var body: some View {
        let diameter = GlassOrbMetrics.orbDiameter * scale
        // The library's own number, the Active row's; nothing until the library has loaded.
        let count = model.isLoaded ? model.activeSessionCount() : 0
        Button(action: restore) {
            Image("GlassPowerToolsMark")
                .resizable()
                .scaledToFit()
                .padding(diameter * 0.17)
                .frame(width: diameter, height: diameter)
                // A drop of glass that wobbles with the rest of the line (`GlassOrbJellyField`).
                .modifier(GlassOrbLiquidRim(diameter: diameter, shading: false, clips: false, glass: glass.glass.interactive()))
                .scaleEffect(over ? 1.06 : 1)
                .contentShape(.circle)
        }
        .buttonStyle(GlassMacOrbPressStyle())
        .modifier(GlassOrbLiquidSource())
        // Over the circle, after it grows, so it is never clipped by it.
        .overlay(alignment: .bottom) {
            if count > 0 {
                GlassMacConnectionsOrbBadge(count: count)
                    .alignmentGuide(.bottom) { $0[.bottom] - Self.badgeDrop }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        // Named above the dock, on the same line as every other orb's name.
        .onHover { inside in
            over = inside
            point("orb", inside ? "Connections" : nil, .zero)
        }
        .contextMenu { menu }
        .accessibilityLabel(count > 0 ? "Open Connections, \(count) active" : "Open Connections")
        .accessibilityIdentifier("orb-dock-connections")
        .animation(.smooth, value: count)
        .animation(.easeOut(duration: 0.15), value: over)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // What runs on the machines, asked as the library asks as it appears: at most once in its
        // time, as on Vision Pro. Nothing more polls.
        .task { await model.refreshRunningSessionsIfDue() }
    }
}

/// Active's count on the Connections orb's rim, in glass, with Active's bolt: what the library's Active row
/// would say, as on Vision Pro.
private struct GlassMacConnectionsOrbBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill").imageScale(.small)
            Text(count, format: .number)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        // Solid, with an edge: half on Connections' drop and half on the dock, a clear glass capsule read as
        // cut in two on either (the VM, 2026-11-02, dark and light, on the white circle it had then).
        .background(.thickMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(.separator) }
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// Pressed, an orb or a dot shrinks a little.
private struct GlassMacOrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
#endif
