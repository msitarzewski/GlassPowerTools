//
//  GlassConnectionsIdleWatcher.swift
//  Glass Power Tools — GlassShell
//
//  The headset's Connections window watching itself for idle, and shrinking into its orb (W29).
//  The rule is `GlassConnectionsIdleClock`; this is what feeds it, and what acts on its answer.
//
//  **What counts as using the window**, observed in UIKit because SwiftUI has no single place that
//  sees every tap, drag and scroll in a window without taking part in them:
//  - a touch (on the headset, a pinch aimed at the window) beginning or moving anywhere in it —
//    a recogniser on the window that never recognises, so it blocks, delays and cancels nothing;
//  - an indirect scroll (a trackpad's two fingers) over it — a pan recogniser that accepts only
//    scroll events and runs beside every other;
//  - a text field in it changing, beginning or ending editing (the keyboard is a window of its
//    own, so its keys never reach this one as touches).
//  Each of those only moves a timestamp; nothing runs per frame and nothing polls.
//
//  **The window becomes its orb** (W39). It pushed a second window, the orb, which hid Connections
//  in the simulator and on the owner's headset until a relaunch; after `devicectl` relaunched the
//  app at every install, both stayed on screen (owner, 2026-10-11: "The orb always appears as it
//  should. The All Connections window never minimizes"), which developers report of `pushWindow`
//  after a force quit or with a pinned window. So no second window: the Connections window shows
//  the orb in the library's place and asks visionOS for the orb's size
//  (`UIWindowScene.requestGeometryUpdate`, as W38 holds a desktop to its display's shape), and a
//  pinch on the orb, or "Open Connections" from anywhere, grows it back to the size it had.
//
//  **Nothing is torn down.** The library stays in the window, laid out at the size it had, with
//  no opacity, no hit testing and nothing for VoiceOver, so its selection, search, tab, sidebar
//  and scroll position are exactly as they were when it grows back. Its glass and Opacity paint
//  are its own and go out of sight with it; the orb is the icon in its own glass circle, on no
//  panel, as it was as a window of its own.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import os
#if os(visionOS)
import UIKit
#endif

#if os(visionOS)
public extension View {
    /// Makes the Connections window its own orb after the idle time chosen in Settings ▸ General,
    /// and the library again on a pinch on the orb or any "Open Connections". Attach to the
    /// window's whole content: what it wraps is what goes out of sight while the window is its orb.
    func glassConnectionsIdleShrink(model: GlassShellModel, recovery: GlassWindowRecoveryManager) -> some View {
        modifier(GlassConnectionsIdleShrinkModifier(model: model, recovery: recovery))
    }
}

private struct GlassConnectionsIdleShrinkModifier: ViewModifier {
    let model: GlassShellModel
    let recovery: GlassWindowRecoveryManager
    @AppStorage(GlassConnectionsIdleShrink.settingKey, store: GlassUITestRun.settingsDefaults) private var storedSeconds = GlassConnectionsIdleShrink.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var probe = GlassConnectionsWindowProbe()
    /// The library's size while the window is its orb, to grow back to; nil while it is the library.
    @State private var orbOver: CGSize?
    /// This window, among Connections windows: there is one orb (`anotherConnectionsWindowIsOrb`).
    @State private var token = UUID()
    /// The library's size while the window is its orb, kept with the window's scene, so a launch
    /// that restores the window at the orb's size grows it back to its own. Empty otherwise.
    @SceneStorage("connections.librarySize") private var keptLibrarySize = ""

    init(model: GlassShellModel, recovery: GlassWindowRecoveryManager) {
        self.model = model
        self.recovery = recovery
        // Opened to be the orb (Connections closed last): the orb from the first frame, so the
        // window opens at the orb's size rather than as the library and then shrinking. Read, not
        // taken: the window takes it as it appears.
        _orbOver = State(initialValue: recovery.connectionsParkIsPending ? GlassConnectionsWindowSize.standard : nil)
    }

    private var setting: GlassConnectionsIdleShrink { GlassConnectionsIdleShrink(storedSeconds: storedSeconds) }

    private var interval: Duration? {
        #if DEBUG
        if let demo = GlassConnectionsIdleDemo.interval { return demo }
        #endif
        return setting.interval
    }

    func body(content: Content) -> some View {
        let isOrb = orbOver != nil
        GlassConnectionsWindowLayout(library: orbOver) {
            content
                // Its ornaments go with it — the tab bar beside the window, the toolbar below — and
                // inside each tab, what VoiceOver could find and a pinch could reach.
                .environment(\.glassLibraryOutOfSight, isOrb)
                // Out of sight, its glass and Opacity paint with it, and out of reach.
                .animation(.easeInOut(duration: 0.2)) { $0.opacity(isOrb ? 0 : 1) }
                .allowsHitTesting(!isOrb)
                .accessibilityHidden(isOrb)
            if isOrb {
                GlassConnectionsOrb(model: model) { becomeLibrary(why: "orb") }
            }
        }
        .background { GlassConnectionsWindowProbeView(probe: probe).accessibilityHidden(true) }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if GlassConnectionsIdleDemo.reportsScenePhase {
                ZStack(alignment: .topLeading) {
                    GlassConnectionsScenePhaseMarker(phase: scenePhase)
                    GlassConnectionsWindowStateMarker(probe: probe, isOrb: isOrb, token: token)
                }
            }
        }
        #endif
        // One wait at a time, started again whenever the setting, the window's phase or what it
        // is changes. As its orb there is nothing to wait for.
        .task(id: WatchKey(setting: setting, isActive: scenePhase == .active, isOrb: isOrb)) { await watch() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            probe.clock.interaction()
        }
        // "Open Connections" from anywhere — ⚡, a terminal's Connections control, the database's
        // way back to its machine — while the window is its orb: visionOS brings forward a window
        // already on screen and does nothing more, so the window grows back by itself.
        .onChange(of: GlassConnectionsRequests.shared.count) { _, _ in
            becomeLibrary(why: "asked")
        }
        .onAppear {
            let parked = recovery.takeConnectionsPark()
            if parked || orbOver != nil {
                Logger.idle.info("Connections opened as its orb: it was closed as the last window")
                becomeOrb(library: orbOver, why: "parked")
            }
        }
        .onDisappear { recovery.connectionsWindowClosed(token) }
        .task { await growIfRestoredAtTheOrbsSize() }
    }

    /// The window becomes its orb: the library kept, out of sight, at `library` — the window's
    /// size now when nil, as it is for idle — and the window made the orb's size.
    private func becomeOrb(library: CGSize?, why: String) {
        let size = GlassConnectionsWindowSize.returning(to: library ?? probe.windowSize)
        orbOver = size
        keptLibrarySize = GlassConnectionsWindowSize.stored(size)
        recovery.connectionsBecameOrb(token)
        probe.keepLibraryAway(true)
        probe.resize(to: GlassConnectionsWindowSize.orb, event: "orb-\(why)")
        // In front of the windows opened over it since, as the pushed orb was, being a new
        // window: left behind a terminal, the orb was hidden by it and out of reach (visionOS
        // 27.2 simulator: the runner's pinch landed on the terminal). Asked of visionOS directly,
        // not through `openConnections()`, which would count as asking for the library and grow
        // it straight back. A window opened as its orb is in front already.
        if library == nil {
            openWindow(id: GlassConnectionsWindow.sceneID, value: GlassConnectionsWindow())
        }
    }

    /// The window is the library again, at the size it had, and its idle clock starts over.
    private func becomeLibrary(why: String) {
        guard let library = orbOver else { return }
        orbOver = nil
        keptLibrarySize = ""
        recovery.connectionsBecameLibrary(token)
        probe.keepLibraryAway(false)
        probe.clock.interaction()
        probe.resize(to: library, event: "library-\(why)")
    }

    /// A launch can bring this window back at the orb's size: quit while it was the orb, visionOS
    /// keeps the window's size but not what it showed. It shows the library, so it grows back to
    /// the library's size kept with the scene, or to its first size.
    private func growIfRestoredAtTheOrbsSize() async {
        var waited = 0
        while probe.windowSize == nil, waited < 30, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard orbOver == nil, let size = probe.windowSize else { return }
        if GlassConnectionsWindowSize.isOrbSized(size) {
            Logger.idle.info("Connections came back at the orb's size: growing it to the library's")
            let library = GlassConnectionsWindowSize.returning(to: GlassConnectionsWindowSize.stored(keptLibrarySize))
            probe.resize(to: library, event: "library-relaunch")
        }
        keptLibrarySize = ""
        #if DEBUG
        // UI tests: a size of the test's own, so growing back to "the size it had" is told apart
        // from growing back to the first size.
        if let demo = GlassConnectionsIdleDemo.librarySize {
            probe.resize(to: demo, event: "library-demo")
        }
        #endif
    }

    private func watch() async {
        guard scenePhase == .active, orbOver == nil else { return }
        probe.clock.interaction()
        while !Task.isCancelled {
            let state = probe.state(connectingSince: model.connectingSince)
            switch probe.clock.decide(interval: interval, state) {
            case .off:
                return
            case .wait(let remaining):
                try? await Task.sleep(for: remaining + Self.slack)
            case .held(let hold, let recheck):
                Logger.idle.debug("Connections held open: \(hold.rawValue, privacy: .public)")
                try? await Task.sleep(for: recheck + Self.slack)
            case .shrink:
                guard !Task.isCancelled else { return }
                // **A second Connections window does not stand beside the orb** (W34; the owner,
                // 2026-10-11: "The icon shows as expected, but the connections window remains,
                // too"). One orb stands for the library: a second window, idle as long, goes
                // rather than become another, and the pinch brings back the first. There should
                // never be a second (`openConnections()`); this is for one that exists anyway — a
                // display window's ⚡ opened one until W34, and visionOS can bring a window back
                // with the app's others.
                if recovery.anotherConnectionsWindowIsOrb(than: token) {
                    Logger.idle.info("A second Connections window idle beside the orb: closing it")
                    dismissWindow()
                    return
                }
                Logger.idle.info("Connections idle for \(String(describing: interval), privacy: .public): becoming its orb")
                becomeOrb(library: nil, why: "idle")
                return
            }
        }
    }

    /// A sleep can end a hair early; without this the clock answers "wait 2 ms" once more.
    private static let slack: Duration = .milliseconds(50)

    private struct WatchKey: Equatable {
        let setting: GlassConnectionsIdleShrink
        let isActive: Bool
        let isOrb: Bool
    }
}

/// The Connections window as its library or as its orb (W39). As its orb it is exactly the orb's
/// window (`GlassConnectionsWindowSize.orb`, the orb centred in it), and the scene takes its size
/// from its content (`.windowResizability(.contentSize)` on the Connections scene), so it can be
/// made that small and no larger. As the library it takes any size, as before. The library is always the
/// first view, in the same place in the tree whichever the window is; as the orb it is laid out
/// at the size it had, centred behind the orb and out of sight, so nothing in it is rebuilt or
/// squeezed.
/// Also a session window's while it is its orb (`glassSessionOrb`, 2026-10-15).
struct GlassConnectionsWindowLayout: Layout {
    /// The library's size while the window is its orb; nil while it is the library.
    let library: CGSize?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if library != nil { return GlassConnectionsWindowSize.orb }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let orbSide = GlassConnectionsWindowSize.orbSide
        for (index, subview) in subviews.enumerated() {
            if index > 0 {
                subview.place(at: center, anchor: .center, proposal: ProposedViewSize(width: orbSide, height: orbSide))
            } else if let library {
                subview.place(at: center, anchor: .center, proposal: ProposedViewSize(library))
            } else {
                subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
            }
        }
    }
}

/// What the Connections window knows about itself in UIKit: when it was last used, and what is
/// open over it right now.
@MainActor
final class GlassConnectionsWindowProbe: NSObject {
    var clock = GlassConnectionsIdleClock()
    private weak var window: UIWindow?
    /// Asks visionOS for the window's sizes (`GlassWindowSizer`, which a session window's orb uses too).
    private let sizer = GlassWindowSizer()
    private var recognizers: [UIGestureRecognizer] = []
    private var dropInteraction: UIDropInteraction?
    private var observers: [NSObjectProtocol] = []
    /// Text views in this window that began editing and have not ended. Weak: a field removed
    /// with its sheet must not hold the window open forever.
    private let editing = NSHashTable<UIView>.weakObjects()
    private var touchesDown = 0
    private var dragsOver = 0

    func attach(to window: UIWindow?) {
        guard window !== self.window else { return }
        detach()
        guard let window else { return }
        self.window = window
        sizer.window = window

        let touches = InteractionRecognizer { [weak self] down, used in
            self?.touchesDown = down
            if used { self?.clock.interaction() }
        }
        let scrolls = UIPanGestureRecognizer(target: self, action: #selector(scrolled))
        scrolls.allowedScrollTypesMask = .all
        scrolls.allowedTouchTypes = []
        for recognizer in [touches, scrolls] {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
        }
        recognizers = [touches, scrolls]

        let drops = UIDropInteraction(delegate: self)
        window.addInteraction(drops)
        dropInteraction = drops

        let center = NotificationCenter.default
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let view = note.object as? UIView
                MainActor.assumeIsolated { self?.editingBegan(view) }
            })
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification,
                     UITextField.textDidChangeNotification, UITextView.textDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let view = note.object as? UIView
                MainActor.assumeIsolated { self?.editingChanged(view) }
            })
        }
        if libraryAway { applyLibraryAway() }
    }

    func detach() {
        for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizers = []
        if let dropInteraction { dropInteraction.view?.removeInteraction(dropInteraction) }
        dropInteraction = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        editing.removeAllObjects()
        touchesDown = 0
        dragsOver = 0
        window = nil
        sizer.window = nil
    }

    // MARK: The window's size (W39)

    /// The window's size now, from its scene; nil until the probe is in a window.
    var windowSize: CGSize? { sizer.windowSize }

    /// Asks visionOS to give the window `size`, once its scene's limits allow it
    /// (`GlassWindowSizer`). And the library's host once more, now the window has its new size: a
    /// window opened as its orb had no tab view to hide at first.
    func resize(to size: CGSize, event: String) {
        sizer.resize(to: size, event: event) { [weak self] in
            if self?.libraryAway == true { self?.applyLibraryAway() }
        }
    }

    // MARK: The library out of reach (W39)

    /// True while the window is its orb: the library is kept, and nothing in it can be found by
    /// VoiceOver or touched.
    private var libraryAway = false

    /// Keeps the library out of VoiceOver's reach and out of touch while the window is its orb, at
    /// its UIKit host as well: the tab view's controller, which hosts each tab on its own, whose
    /// list hosts each row on its own again. SwiftUI's `accessibilityHidden` and `allowsHitTesting`
    /// are set on the window's content and inside each tab; this is UIKit's own way of taking a
    /// subtree from VoiceOver (`accessibilityElementsHidden`) and from touch, for what those may
    /// not reach. The UI test runner lists the rows either way (visionOS 27.2 simulator), so
    /// neither is proven by it. The orb is not inside the tab view, so it stays reachable.
    func keepLibraryAway(_ away: Bool) {
        libraryAway = away
        applyLibraryAway()
    }

    private func applyLibraryAway() {
        guard let window else { return }
        let hosts = Self.tabBarControllers(in: window)
        for host in hosts {
            host.view.accessibilityElementsHidden = libraryAway
            host.view.isUserInteractionEnabled = !libraryAway
        }
        if libraryAway {
            Logger.idle.notice("event=library-away hosts=\(hosts.count)")
        }
    }

    private static func tabBarControllers(in view: UIView) -> [UITabBarController] {
        if let controller = view.next as? UITabBarController { return [controller] }
        return view.subviews.flatMap { tabBarControllers(in: $0) }
    }

    /// The window's state for the rule, read now.
    func state(connectingSince: ContinuousClock.Instant?) -> GlassConnectionsIdleState {
        guard let window, let scene = window.windowScene else {
            return GlassConnectionsIdleState(isOnScreen: false)
        }
        return GlassConnectionsIdleState(
            isOnScreen: scene.activationState == .foregroundActive,
            otherWindows: Self.otherWindows(than: scene),
            isPresenting: Self.isPresenting(over: window),
            isEditingText: editing.allObjects.contains { $0.window === window && $0.isFirstResponder },
            isTouching: touchesDown > 0,
            isDragging: dragsOver > 0,
            connectingSince: connectingSince)
    }

    /// The app's other windows and volumes on screen. An immersive space is not a window, and a
    /// window behind the orb or closed is not on screen.
    private static func otherWindows(than scene: UIWindowScene) -> Int {
        UIApplication.shared.connectedScenes.filter { other in
            other !== scene
                && (other.activationState == .foregroundActive || other.activationState == .foregroundInactive)
                && (other.session.role == .windowApplication || other.session.role == .windowApplicationVolumetric)
        }.count
    }

    /// A sheet, alert, confirmation dialog, popover or menu presented from anything in the
    /// window. On visionOS a `Menu`'s list and a context menu are presented controllers too
    /// (`_UIContextMenuActionsOnlyViewController`, read from the simulator on visionOS 27.2), so
    /// one question covers all of them.
    private static func isPresenting(over window: UIWindow) -> Bool {
        guard let root = window.rootViewController else { return false }
        func presents(_ controller: UIViewController) -> Bool {
            if controller.presentedViewController != nil { return true }
            return controller.children.contains(where: presents)
        }
        return presents(root)
    }

    private func editingBegan(_ view: UIView?) {
        guard let view, view.window === window else { return }
        editing.add(view)
        clock.interaction()
    }

    private func editingChanged(_ view: UIView?) {
        guard let view, editing.contains(view) || view.window === window else { return }
        clock.interaction()
    }

    @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
        clock.interaction()
    }

    /// Counts its touches and never recognises: it sees every touch the window receives and
    /// takes none of them from anything else.
    private final class InteractionRecognizer: UIGestureRecognizer {
        /// The touches held now, and whether this was the person using the window.
        private let report: (_ down: Int, _ used: Bool) -> Void
        private var down = 0

        init(report: @escaping (_ down: Int, _ used: Bool) -> Void) {
            self.report = report
            super.init(target: nil, action: nil)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            down += touches.count
            report(down, true)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            report(down, true)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            down = max(0, down - touches.count)
            report(down, true)
            if down == 0 { state = .failed }
        }

        override func reset() {
            super.reset()
            down = 0
            report(0, false)
        }
    }
}

extension GlassConnectionsWindowProbe: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Watches drags over the window and accepts none: every proposal is `.cancel`, which is what a
/// window with no drop target gives, and any view inside with a drop target of its own is asked
/// first.
extension GlassConnectionsWindowProbe: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool { true }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        dragsOver += 1
        clock.interaction()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        dragsOver = max(0, dragsOver - 1)
        clock.interaction()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        dragsOver = 0
        clock.interaction()
    }
}

/// Zero-size and not hit-testable: hands the probe the window it is in, and nothing else.
private struct GlassConnectionsWindowProbeView: UIViewRepresentable {
    let probe: GlassConnectionsWindowProbe

    func makeUIView(context: Context) -> ProbeView { ProbeView(probe: probe) }
    func updateUIView(_ view: ProbeView, context: Context) {}
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.probe.detach() }

    final class ProbeView: UIView {
        let probe: GlassConnectionsWindowProbe

        init(probe: GlassConnectionsWindowProbe) {
            self.probe = probe
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Next turn, not inside SwiftUI's update (rule 64): adding recognisers and an
            // interaction to the window is UIKit work.
            let probe = probe
            DispatchQueue.main.async { [weak self] in probe.attach(to: self?.window) }
        }
    }
}
#endif

#if DEBUG
/// Screenshots only: `--demo-idle-seconds <n>` in a `--ui-testing` run puts a few seconds in place
/// of the setting's minutes, so the real idle path shrinks the window while a capture waits
/// (`Tools/Screenshots/shoot.sh`, surface `orb`). Read from the launch arguments, so it is there
/// before the window's first wait begins.
enum GlassConnectionsIdleDemo {
    static var interval: Duration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--demo-idle-seconds"), arguments.indices.contains(index + 1),
              let seconds = Int(arguments[index + 1]), seconds > 0 else { return nil }
        return .seconds(seconds)
    }

    /// UI tests only: `--demo-library-size <width>x<height>` in a `--ui-testing` run gives the
    /// Connections window that size as it opens (W39).
    static var librarySize: CGSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--demo-library-size"), arguments.indices.contains(index + 1)
        else { return nil }
        return GlassConnectionsWindowSize.stored(arguments[index + 1])
    }

    /// UI tests only: every `--ui-testing` run marks each Connections window with its scene phase,
    /// and with what it is (library or orb) and its scene's size.
    static var reportsScenePhase: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
}

#if os(visionOS)
/// UI tests only: the Connections window's scene phase, where the runner can read it
/// (`connections-scene-phase`). A window pushed aside stays in the tree the runner sees, rows and
/// all, and reports them hittable (measured on the visionOS 27.0 and 27.2 simulators, W34), so
/// only the window can say whether it is on screen; one marker per window also counts them.
private struct GlassConnectionsScenePhaseMarker: View {
    let phase: ScenePhase

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier("connections-scene-phase")
            .accessibilityValue(name)
    }

    private var name: String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// UI tests only: what the Connections window is and how big its scene is, where the runner can
/// read it (`connections-window-state`): "library 960x700 1A2B3C4D" or "orb 184x184 1A2B3C4D",
/// the last part naming the window, so a test can tell the orb is the same window (W39). The size
/// is the scene's own, not the content's, so it says whether visionOS really made the window
/// small. Read twice a second: nothing tells SwiftUI when a scene's size changes.
private struct GlassConnectionsWindowStateMarker: View {
    let probe: GlassConnectionsWindowProbe
    let isOrb: Bool
    let token: UUID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("connections-window-state")
                .accessibilityValue(value)
        }
    }

    private var value: String {
        let size = probe.windowSize.map { "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "unknown"
        return "\(isOrb ? "orb" : "library") \(size) \(token.uuidString.prefix(8))"
    }
}
#endif
#endif

extension Logger {
    static let idle = Logger(subsystem: "com.glasspowertools", category: "connections-idle")
}
