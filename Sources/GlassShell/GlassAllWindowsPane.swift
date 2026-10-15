//
//  GlassAllWindowsPane.swift
//  Glass Power Tools — GlassShell
//
//  All Windows on iPhone and iPad as a pane pulled down from the top bar (the owner, 2026-10-14:
//  "what about drag down from an empty space in the toolbar? Every iOS service has one, right?
//  Then it could slide in like a separate transparent pane?"). Holding the ⚡ brings the same pane.
//
//  - The pull: one pan gesture per app window that begins only for a downward drag starting on a
//    top bar's empty space — not on a control, a search field or a text field — so no screen has
//    to add anything. The system's own pulls (Notification Center, Control Center) start at the
//    screen's top edge, above the bar, and are not taken.
//  - The pane: the app's layered glass (`GlassLayeredPanel`, Opacity and Reduce Transparency as
//    every window), following the finger down and back up, in a window of its own above the
//    app's, so it covers a desktop's or an editor's full-screen cover as well as the library.
//  - The way out: a card leaves the screen underneath before it opens its session, as the ⚡'s tap
//    does. A pull has no ⚡ to ask, so each screen whose ⚡ leaves it says how while it is shown
//    (`GlassActiveConnectionsToolbarModifier`), and the latest is the one on screen.
//

#if os(iOS)
import SwiftUI
import UIKit
import GlassLayers

public extension GlassShowAllWindows {
    /// Opens the pane over whatever is on screen, all the way. `dismissCurrent` leaves the screen
    /// underneath before a card opens another; nil takes the screen's own way out, if it has one.
    static func presentOverview(dismissCurrent: (@MainActor () -> Void)? = nil) {
        guard let window = GlassAllWindowsPull.activeWindow() else { return }
        GlassAllWindowsPaneController.shared.show(over: window, dismissCurrent: dismissCurrent)
    }

    /// Pulling down on a top bar opens the pane, in every window the app shows from now on.
    /// Called once, by the composition root.
    static func installPullDown() {
        GlassAllWindowsPull.shared.install()
    }

    /// A screen whose ⚡ leaves it (a terminal, a database, a desktop, an editor on iPhone) says
    /// how, while it is shown. Returns what `forgetScreen` takes back.
    static func noteScreen(leaving dismiss: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        screens.append((token, dismiss))
        return token
    }

    static func forgetScreen(_ token: UUID) {
        screens.removeAll { $0.token == token }
    }

    /// The way out of the screen on top: the latest shown that is still shown.
    internal static var currentScreenExit: (@MainActor () -> Void)? { screens.last?.dismiss }

    private static var screens: [(token: UUID, dismiss: @MainActor () -> Void)] = []
}

// MARK: - The pull

/// The pan on each app window that turns a pull on a top bar into the pane.
@MainActor
final class GlassAllWindowsPull: NSObject, UIGestureRecognizerDelegate {
    static let shared = GlassAllWindowsPull()
    static let gestureName = "glass.allWindows.pull"
    static let holdName = "glass.allWindows.hold"

    /// The hold is UIKit's, on the window, not SwiftUI's on the button: a SwiftUI gesture on a
    /// terminal's ⚡ never began (2026-10-14, measured on the simulator), because iOS 26 draws a
    /// toolbar's plain button as a native bar button, without the SwiftUI view's gestures or
    /// backgrounds. A ⚡ is told two ways, because it is drawn two ways: a native bar button by
    /// its accessibility identifier, which it keeps; one SwiftUI keeps drawing — the library's,
    /// among other items — by a view of its own behind it (`GlassBoltProbe`), since on iOS 27.2
    /// the view a touch lands on there does not carry the identifier (the owner's iPhone: "nothing
    /// on hold"; reproduced on the 27.2 simulator).
    private var heldBolt = false
    private let probes = NSHashTable<UIView>.weakObjects()

    func noteProbe(_ view: UIView) { probes.add(view) }
    func forgetProbe(_ view: UIView) { probes.remove(view) }

    private func isOnProbe(_ point: CGPoint, in window: UIWindow) -> Bool {
        probes.allObjects.contains { view in
            view.window === window && view.convert(view.bounds, to: window).contains(point)
        }
    }

    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        // UIKit posts both on the main thread.
        for name in [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowAppeared(_:)), name: name, object: nil)
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach(attach)
        }
    }

    @objc private func windowAppeared(_ note: Notification) {
        if let window = note.object as? UIWindow { attach(to: window) }
    }

    private func attach(to window: UIWindow) {
        guard !(window is GlassAllWindowsPaneWindow), window.windowScene != nil,
              window.gestureRecognizers?.contains(where: { $0.name == Self.gestureName }) != true else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))
        pan.name = Self.gestureName
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        window.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.name = Self.holdName
        hold.minimumPressDuration = 0.45
        hold.delegate = self
        window.addGestureRecognizer(hold)
    }

    /// A finger rested on a ⚡: All Windows. UIKit cancels the touch for the button, so the
    /// release is not also a tap.
    @objc private func held(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began, heldBolt else { return }
        heldAt = .now
        // The screen the ⚡ is on leaves the way its own ⚡ would (`GlassScreenExit`).
        GlassShowAllWindows.presentOverview()
    }

    static let boltIdentifier = "active-connections-bolt"

    /// Whether `view` is a ⚡, or inside one.
    static func isBolt(_ view: UIView?) -> Bool {
        var view = view
        while let current = view {
            if current.accessibilityIdentifier == boltIdentifier { return true }
            if current is UINavigationBar || current is UIWindow { return false }
            view = current.superview
        }
        return false
    }

    /// When a hold last opened All Windows: the button's own gesture runs alongside the hold and
    /// sees a tap on release, which must not also go to Active.
    private var heldAt: ContinuousClock.Instant?

    /// Whether the tap a ⚡ just saw ended a hold, which then counts for nothing.
    func tapEndsHold() -> Bool {
        defer { heldAt = nil }
        guard let heldAt else { return false }
        return ContinuousClock.now - heldAt < .seconds(3)
    }

    /// The hold runs alongside the button's own gesture, which begins at the touch and would
    /// otherwise keep any other from beginning (measured on the simulator, 2026-10-14: the hold
    /// was given the touch, inside the bolt, and never began).
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture.name == Self.holdName
    }

    /// The window in front, for the ⚡'s hold.
    static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow && !($0 is GlassAllWindowsPaneWindow) }
            ?? scene?.windows.first { !($0 is GlassAllWindowsPaneWindow) }
    }

    @objc private func pulled(_ pan: UIPanGestureRecognizer) {
        guard let window = pan.view as? UIWindow else { return }
        let controller = GlassAllWindowsPaneController.shared
        switch pan.state {
        case .began:
            controller.beginPull(over: window)
        case .changed:
            controller.pull(to: pan.translation(in: window).y)
        case .ended:
            controller.endPull(velocity: pan.velocity(in: window).y)
        case .cancelled, .failed:
            controller.endPull(velocity: -1)
        default:
            break
        }
    }

    /// Whether the touch now on the window began on a top bar's empty space. Judged by where the
    /// bars are, not by which view the touch landed on: on iOS 26 a touch in a bar's empty part,
    /// a large title's among them, can go through to the list underneath, which then began its
    /// own scroll first (found driving the pull on the simulator, 2026-10-14).
    private var startedOnTopBar = false

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = gesture.view as? UIWindow else { return false }
        let point = touch.location(in: window)
        if gesture.name == Self.holdName {
            heldBolt = Self.isBolt(window.hitTest(point, with: nil)) || isOnProbe(point, in: window)
            return heldBolt && GlassShowAllWindows.model != nil
        }
        startedOnTopBar = point.y > window.safeAreaInsets.top
            && Self.topBars(in: window).contains { $0.contains(point) }
            && !Self.isControl(window.hitTest(point, with: nil))
        return startedOnTopBar
    }

    // A pull, and only one that starts on a top bar's empty space.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if gesture.name == Self.holdName { return heldBolt && !GlassAllWindowsPaneController.shared.isShowing }
        guard startedOnTopBar, GlassShowAllWindows.model != nil, !GlassAllWindowsPaneController.shared.isShowing,
              let pan = gesture as? UIPanGestureRecognizer, let window = pan.view as? UIWindow else { return false }
        let velocity = pan.velocity(in: window)
        return velocity.y > 0 && velocity.y > abs(velocity.x) * 1.5
    }

    /// A drag that starts on a top bar is the pull's to decide first: a list's scrolling under a
    /// large title waits for it, and has the touch the moment the pull declines (sideways, or
    /// upward). Only scrolling: a tap or a hold on the bar's buttons goes at once — when every
    /// gesture waited, a finger held still on a terminal's ⚡ was only released when it lifted,
    /// as a tap, and All Windows never opened (found on the iPhone simulator, 2026-10-14).
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        gesture.name == Self.gestureName && startedOnTopBar && other is UIPanGestureRecognizer && other.view !== gesture.view
    }

    /// The window's top bars, in its coordinates. Not inside scrolling content, a web page or a
    /// Metal surface, where no bar is.
    static func topBars(in window: UIWindow) -> [CGRect] {
        var bars: [CGRect] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let bar = view as? UINavigationBar {
                bars.append(bar.convert(bar.bounds, to: window))
                return
            }
            if view is UIScrollView { return }
            view.subviews.forEach(visit)
        }
        visit(window)
        return bars
    }

    /// Whether a touch on `view` is on something in the bar that takes a touch itself.
    static func isControl(_ view: UIView?) -> Bool {
        var view = view
        while let current = view {
            if current is UIControl || current is UISearchBar || current is UITextField { return true }
            if current is UINavigationBar || current is UIWindow { return false }
            view = current.superview
        }
        return false
    }
}

// MARK: - The pane

/// How far down the pane is, 0 to 1, and how tall.
@MainActor @Observable
final class GlassAllWindowsPaneState {
    var progress: CGFloat = 0
    var height: CGFloat = 600
}

/// The pane's own window, above the app's.
final class GlassAllWindowsPaneWindow: UIWindow {}

@MainActor
final class GlassAllWindowsPaneController {
    static let shared = GlassAllWindowsPaneController()

    private var window: GlassAllWindowsPaneWindow?
    private weak var previousKey: UIWindow?
    private let state = GlassAllWindowsPaneState()
    private var dismissCurrent: (@MainActor () -> Void)?

    var isShowing: Bool { window != nil }

    /// The ⚡'s hold: in, all the way.
    func show(over host: UIWindow, dismissCurrent: (@MainActor () -> Void)?) {
        guard window == nil else { return }
        guard prepare(over: host, dismissCurrent: dismissCurrent) else { return }
        settle(open: true)
    }

    func beginPull(over host: UIWindow) {
        guard window == nil else { return }
        _ = prepare(over: host, dismissCurrent: nil)
    }

    func pull(to translation: CGFloat) {
        guard window != nil else { return }
        state.progress = min(1, max(0, translation / state.height))
    }

    func endPull(velocity: CGFloat) {
        guard window != nil else { return }
        settle(open: velocity > 500 || (velocity > -200 && state.progress > 0.35))
    }

    private func prepare(over host: UIWindow, dismissCurrent: (@MainActor () -> Void)?) -> Bool {
        guard let model = GlassShowAllWindows.model, let scene = host.windowScene else { return false }
        self.dismissCurrent = dismissCurrent ?? GlassShowAllWindows.currentScreenExit
        previousKey = host
        state.height = min(host.bounds.height * 0.86, host.bounds.height - 60)
        state.progress = 0
        let pane = GlassAllWindowsPaneView(state: state, model: model,
                                           close: { [weak self] chosen in self?.close(then: chosen) },
                                           drag: { [weak self] in self?.dragPane(by: $0) },
                                           endDrag: { [weak self] in self?.endPaneDrag(by: $0) })
            .glassLayers(model.layers)
        let host = UIHostingController(rootView: pane)
        host.view.backgroundColor = .clear
        let window = GlassAllWindowsPaneWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        return true
    }

    private func settle(open: Bool) {
        withAnimation(.spring(duration: 0.35, bounce: open ? 0.12 : 0)) {
            state.progress = open ? 1 : 0
        } completion: { [weak self] in
            guard let self else { return }
            if open { window?.makeKey() } else { tearDown() }
        }
    }

    /// Up and away; then, when a card was chosen, the screen underneath is left and the card's
    /// session brought back.
    private func close(then chosen: (@MainActor () -> Void)?) {
        guard window != nil else { return }
        let leave = dismissCurrent
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            state.progress = 0
        } completion: { [weak self] in
            self?.tearDown()
            guard let chosen else { return }
            leave?()
            chosen()
        }
    }

    private func dragPane(by translation: CGFloat) {
        state.progress = min(1, max(0, 1 + translation / state.height))
    }

    private func endPaneDrag(by translation: CGFloat) {
        if translation < -state.height * 0.2 { close(then: nil) } else { settle(open: true) }
    }

    private func tearDown() {
        window?.isHidden = true
        window = nil
        dismissCurrent = nil
        previousKey?.makeKey()
    }
}

/// The scrim and the pane: everything open as cards, on the app's glass, with a grabber to push
/// it back up.
struct GlassAllWindowsPaneView: View {
    let state: GlassAllWindowsPaneState
    let model: GlassShellModel
    let close: (_ chosen: (@MainActor () -> Void)?) -> Void
    let drag: (CGFloat) -> Void
    let endDrag: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                Color.black.opacity(0.28 * state.progress)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { close(nil) }
                    .accessibilityHidden(true)
                GlassLayeredPanel(cornerRadius: 30) {
                    VStack(spacing: 0) {
                        GlassShowAllWindowsOverview(model: model, done: { close(nil) }, open: { close($0) })
                            .containerBackground(.clear, for: .navigation)
                            .padding(.top, top)
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 44, height: 5)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(.rect)
                            .gesture(DragGesture(minimumDistance: 4)
                                .onChanged { drag($0.translation.height) }
                                .onEnded { endDrag($0.predictedEndTranslation.height) })
                            .accessibilityLabel("Close All Windows")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { close(nil) }
                    }
                }
                .frame(height: state.height + top)
                .offset(y: -(state.height + top + 24) * (1 - state.progress))
                .shadow(color: .black.opacity(0.25 * state.progress), radius: 24, y: 8)
            }
            .ignoresSafeArea(edges: .top)
        }
        .accessibilityAction(.escape) { close(nil) }
    }
}
/// The view behind a ⚡ SwiftUI draws itself, by which the window's hold knows it is there.
struct GlassBoltProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        GlassAllWindowsPull.shared.noteProbe(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        GlassAllWindowsPull.shared.forgetProbe(view)
    }
}
#endif
