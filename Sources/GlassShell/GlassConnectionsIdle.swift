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
//  a headset, and so are the sizes it goes between (`GlassConnectionsWindowSize`, W39). What the
//  window reports to it, and how it becomes its orb, is `GlassConnectionsIdleWatcher` (visionOS
//  only); the orb is `GlassConnectionsOrb`.
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

// MARK: - The window's sizes

/// The headset Connections window's sizes, in points, and the rules for going between the
/// library's and the orb's (W39). Idle, the window becomes its own orb — the same window, made
/// orb-sized — rather than pushing a second window over itself, which visionOS showed beside the
/// window it should have hidden on the owner's headset after a relaunch (2026-10-11: "The orb
/// always appears as it should. The All Connections window never minimizes").
public enum GlassConnectionsWindowSize {
    /// The library's first size: the Mac's Connections width, the 360-point list column beside an
    /// 820-point detail. W29 had made it 960, a quarter narrower than the system's 1280 (the
    /// owner, 2026-10-10: "pretty large"); at 960 the detail was 600, and the owner
    /// asked for it wider (2026-10-14: "it should be wider by default"). Tall enough that a host
    /// with two services shows every row and Edit without scrolling; 620 cut it off.
    public static let width: CGFloat = 1180
    public static let height: CGFloat = 700
    public static var standard: CGSize { CGSize(width: width, height: height) }

    /// The orb's side: the 112-point icon, grown a little on a look, its count's badge hanging
    /// below the rim, and the name shown beneath.
    public static let orbSide: CGFloat = 184

    /// The narrowest window visionOS makes. Asked for 184 × 184, with the scene's own limits at
    /// exactly that, the orb's window came out 320 × 184 (visionOS 27.2 simulator, W39).
    public static let narrowestWindow: CGFloat = 320

    /// The window while it is its orb: the orb, centred in the narrowest window visionOS makes, so
    /// what the content asks for and what visionOS gives are the same.
    public static var orb: CGSize { CGSize(width: max(orbSide, narrowestWindow), height: orbSide) }

    /// About the orb's window, which nobody gives the library on purpose. A Connections window
    /// that comes back from a launch this small was quit as its orb, and visionOS kept its size.
    public static func isOrbSized(_ size: CGSize) -> Bool {
        size.width <= orb.width * 1.25 && size.height <= orb.height * 1.25
    }

    /// The size the library grows back to: the one it had before it became its orb, or its first
    /// size when that is unknown, unusable, or no bigger than the orb itself.
    public static func returning(to remembered: CGSize?) -> CGSize {
        guard let remembered, usable(remembered), !isOrbSized(remembered) else { return standard }
        return remembered
    }

    /// The library's size as the window's scene keeps it (`SceneStorage` keeps strings), so a
    /// launch that restores the window at the orb's size can bring the library back at its own:
    /// "1180x700", or empty for none.
    public static func stored(_ size: CGSize?) -> String {
        guard let size, usable(size) else { return "" }
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    /// A kept size read back; nil for none, or for anything this build did not write.
    public static func stored(_ text: String) -> CGSize? {
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
        let size = CGSize(width: width, height: height)
        return usable(size) ? size : nil
    }

    /// Whether a scene held between `minimum` and `maximum` can take `size`. A limit that is zero,
    /// negative or not finite on an axis is no limit there.
    public static func admits(_ size: CGSize, minimum: CGSize, maximum: CGSize) -> Bool {
        func fits(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Bool {
            let slack: CGFloat = 0.5
            if low.isFinite, low > 0, value < low - slack { return false }
            if high.isFinite, high > 0, value > high + slack { return false }
            return true
        }
        return fits(size.width, minimum.width, maximum.width) && fits(size.height, minimum.height, maximum.height)
    }

    /// A size a window can have: finite, positive, and not absurd.
    private static func usable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= 20_000 && size.height <= 20_000
    }
}
