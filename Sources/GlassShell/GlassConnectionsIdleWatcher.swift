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
//  **Shrinking pushes the orb, it does not close the window.** `pushWindow` hides Connections and
//  opens the orb centred where it was; dismissing the orb brings the same window back, at its size
//  and place, with its selection, scroll position, tab and search exactly as they were — no state
//  needs saving, because nothing was torn down.
//

import SwiftUI
import os
#if os(visionOS)
import UIKit
#endif

#if os(visionOS)
public extension View {
    /// Shrinks the Connections window into its orb after the idle time chosen in Settings ▸
    /// General, and puts the orb away when the window is back. Attach to the window's content.
    func glassConnectionsIdleShrink(model: GlassShellModel, recovery: GlassWindowRecoveryManager) -> some View {
        modifier(GlassConnectionsIdleShrinkModifier(model: model, recovery: recovery))
    }
}

private struct GlassConnectionsIdleShrinkModifier: ViewModifier {
    let model: GlassShellModel
    let recovery: GlassWindowRecoveryManager
    @AppStorage(GlassConnectionsIdleShrink.settingKey) private var storedSeconds = GlassConnectionsIdleShrink.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var probe = GlassConnectionsWindowProbe()

    private var setting: GlassConnectionsIdleShrink { GlassConnectionsIdleShrink(storedSeconds: storedSeconds) }

    private var interval: Duration? {
        #if DEBUG
        if let demo = GlassConnectionsIdleDemo.interval { return demo }
        #endif
        return setting.interval
    }

    func body(content: Content) -> some View {
        content
            .background { GlassConnectionsWindowProbeView(probe: probe).accessibilityHidden(true) }
            // One wait at a time, started again whenever the setting or the window's phase changes.
            .task(id: WatchKey(setting: setting, isActive: scenePhase == .active)) { await watch() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                probe.clock.interaction()
                // Back on screen — from the orb, from ⚡, from "Open Connections" anywhere — is a
                // fresh start, and an orb has nothing left to stand in for. Asked for from
                // elsewhere while it waits behind the orb, the window itself comes back:
                // `openConnections()` names its value, so visionOS brings it forward rather than
                // opening a second one (W29b).
                recovery.connectionsWindowIsBack()
                if recovery.visibleWindowKeys.contains(GlassConnectionsOrb.windowID) {
                    dismissWindow(id: GlassConnectionsOrb.windowID)
                }
            }
    }

    private func watch() async {
        guard scenePhase == .active else { return }
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
                // One orb: another Connections window may already stand behind it.
                if recovery.visibleWindowKeys.contains(GlassConnectionsOrb.windowID) {
                    probe.clock.interaction()
                    continue
                }
                Logger.idle.info("Connections idle for \(String(describing: interval), privacy: .public): shrinking into the orb")
                recovery.connectionsWillShrink()
                pushWindow(id: GlassConnectionsOrb.windowID)
                return
            }
        }
    }

    /// A sleep can end a hair early; without this the clock answers "wait 2 ms" once more.
    private static let slack: Duration = .milliseconds(50)

    private struct WatchKey: Equatable {
        let setting: GlassConnectionsIdleShrink
        let isActive: Bool
    }
}

/// What the Connections window knows about itself in UIKit: when it was last used, and what is
/// open over it right now.
@MainActor
final class GlassConnectionsWindowProbe: NSObject {
    var clock = GlassConnectionsIdleClock()
    private weak var window: UIWindow?
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
}
#endif

extension Logger {
    static let idle = Logger(subsystem: "com.glasspowertools", category: "connections-idle")
}
