//
//  GlassConnectionsIdle.swift
//  Glass Power Tools — GlassShell
//
//  When the headset's Connections window shrinks into its orb (W29). The owner, on the Vision Pro
//  (2026-10-10): the window "is pretty large … It would be super cool to have it detect idle and
//  minimize itself into an orb of some kind … that activates when looked at — restores to the full
//  window size."
//
//  The rule is here and pure, so what shrinks the window and what holds it open are tested without
//  a headset. What the window reports to it is `GlassConnectionsIdleWatcher` (visionOS only), and
//  the orb is `GlassConnectionsOrb`.
//
//  **Looking is not interacting, and cannot be.** visionOS does not tell an app where a person is
//  looking: hover effects are drawn by the system, out of the app's process, and `onHover` reports
//  a pointer, not the eyes. So "idle" means no tap, drag, scroll or typing in the window — a person
//  reading the window without touching it for the whole interval sees it shrink, and a pinch on
//  the orb brings it straight back where it was.
//

import Foundation

/// Settings ▸ General ▸ **Shrink Connections when idle**, on Vision Pro.
public enum GlassConnectionsIdleShrink: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600

    /// Seconds, in this device's defaults. Not synced: how long a window waits is about the room
    /// and the device it is in, like the window's own size.
    public static let settingKey = "com.glasspowertools.library.idleShrinkSeconds"

    /// Long enough to read a host's details or a page of Active without touching anything, short
    /// enough that a window left behind while working elsewhere gets out of the way.
    public static let standard: Self = .twoMinutes

    /// A stored value this build does not offer — a hand-edited default, or one a later build
    /// wrote — reads as the standard, never as Never: the feature does not switch itself off.
    public init(storedSeconds: Int?) {
        self = storedSeconds.flatMap(Self.init(rawValue:)) ?? .standard
    }

    public var id: Int { rawValue }

    /// How long the window waits; nil when it never shrinks.
    public var interval: Duration? { self == .never ? nil : .seconds(rawValue) }

    public var title: String {
        switch self {
        case .never: "Never"
        case .oneMinute: "1 Minute"
        case .twoMinutes: "2 Minutes"
        case .fiveMinutes: "5 Minutes"
        case .tenMinutes: "10 Minutes"
        }
    }
}

/// What holds Connections at full size whatever the clock says, in the order they are checked.
public enum GlassConnectionsIdleHold: String, Sendable, Equatable {
    /// The window is not on screen: closed, behind the orb already, or its scene in the background.
    case notOnScreen
    /// Nothing else of the app is open. Connections is then the app; it stays put.
    case onlyWindow
    /// A sheet, alert, dialog, popover or menu is up over the window.
    case presenting
    /// A text field in the window is being edited — the search field, a form in a sheet.
    case editingText
    /// A pinch or touch is held on the window: the start of a drag, a scroll in progress.
    case touching
    /// A drag is over the window.
    case dragging
    /// A connection the library started has not answered yet.
    case connecting
}

/// What the window reports at the moment the rule is asked.
public struct GlassConnectionsIdleState: Sendable, Equatable {
    public var isOnScreen: Bool
    /// The app's other windows on screen: terminals, databases, desktops, editors, Settings.
    public var otherWindows: Int
    public var isPresenting: Bool
    public var isEditingText: Bool
    public var isTouching: Bool
    public var isDragging: Bool
    /// When the oldest connection the library asked for and has not heard back about began.
    public var connectingSince: ContinuousClock.Instant?

    public init(isOnScreen: Bool = true, otherWindows: Int = 1, isPresenting: Bool = false,
                isEditingText: Bool = false, isTouching: Bool = false, isDragging: Bool = false,
                connectingSince: ContinuousClock.Instant? = nil) {
        self.isOnScreen = isOnScreen
        self.otherWindows = otherWindows
        self.isPresenting = isPresenting
        self.isEditingText = isEditingText
        self.isTouching = isTouching
        self.isDragging = isDragging
        self.connectingSince = connectingSince
    }

    /// The first thing holding the window open, or nil when nothing does.
    func hold(now: ContinuousClock.Instant) -> GlassConnectionsIdleHold? {
        if !isOnScreen { return .notOnScreen }
        if otherWindows <= 0 { return .onlyWindow }
        if isPresenting { return .presenting }
        if isEditingText { return .editingText }
        if isTouching { return .touching }
        if isDragging { return .dragging }
        if let since = connectingSince, now - since < GlassConnectionsIdleClock.connectingLimit { return .connecting }
        return nil
    }
}

/// What the window does next.
public enum GlassConnectionsIdleDecision: Sendable, Equatable {
    /// The setting is Never: stop watching.
    case off
    /// Something holds the window open. The clock starts again from now, so the window waits a
    /// whole interval after the hold ends rather than shrinking the moment a sheet closes.
    case held(GlassConnectionsIdleHold, recheck: Duration)
    /// Not idle long enough yet: ask again after this long.
    case wait(Duration)
    /// Idle for the whole interval, nothing holding it: shrink into the orb.
    case shrink
}

/// The window's idle clock: when it was last used, and the rule that turns that into a decision.
public struct GlassConnectionsIdleClock: Sendable, Equatable {
    /// A connection that has not answered in this long no longer holds the window. A capability
    /// reports every attempt once, but a report that never comes must not keep Connections at full
    /// size for the rest of the day; a prompt still waiting for an answer is a sheet, which holds
    /// the window on its own.
    public static let connectingLimit: Duration = .seconds(600)

    /// When the window was last used, or last held open.
    public private(set) var idleSince: ContinuousClock.Instant

    public init(now: ContinuousClock.Instant = .now) { idleSince = now }

    /// A tap, drag, scroll or keystroke in the window, or the window coming back on screen.
    public mutating func interaction(at instant: ContinuousClock.Instant = .now) {
        if instant > idleSince { idleSince = instant }
    }

    public mutating func decide(_ setting: GlassConnectionsIdleShrink, _ state: GlassConnectionsIdleState,
                                now: ContinuousClock.Instant = .now) -> GlassConnectionsIdleDecision {
        decide(interval: setting.interval, state, now: now)
    }

    /// The same rule for an interval the setting does not offer: a screenshot's few seconds.
    public mutating func decide(interval: Duration?, _ state: GlassConnectionsIdleState,
                                now: ContinuousClock.Instant = .now) -> GlassConnectionsIdleDecision {
        guard let interval else { return .off }
        if let hold = state.hold(now: now) {
            interaction(at: now)
            return .held(hold, recheck: interval)
        }
        let idle = now - idleSince
        return idle >= interval ? .shrink : .wait(interval - idle)
    }
}
