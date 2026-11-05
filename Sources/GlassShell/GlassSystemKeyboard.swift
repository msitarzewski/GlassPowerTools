//
//  GlassSystemKeyboard.swift
//  Glass Power Tools — GlassShell
//
//  The system keyboard on Vision Pro while a hardware keyboard is connected (the owner, 2026-11-05: "yes, hide the
//  mini keyboard. F that thing. I've had to hide/move it a dozen times. The only tension I'm going to have is voice
//  dictation and emoji selection").
//
//  With a Magic Keyboard connected, visionOS still floats its small keyboard (suggestions, the dictation microphone, a
//  way to the full keyboard) by the window whenever a terminal or a remote desktop takes the keys. Apple offers no
//  switch for it, and on visionOS the bar's buttons can't be emptied (`inputAssistantItem`'s groups are unavailable).
//  The standard way does work: a view that takes the keys gives an empty `inputView` in place of the system's keyboard,
//  and keeps the keys (the visionOS simulator, 2026-11-03; the remote desktop has done so on iPhone and iPad since D93).
//
//  So while a hardware keyboard is connected, terminals and remote desktops give an empty one. Without one, the system
//  keyboard as before, as it is then the only way to type. For dictation and emoji the person can ask for the system
//  keyboard anyway (`shownAnyway`: Show Keyboard in a terminal's Keys menu) until they put it away again or the
//  hardware keyboard goes.
//

import Foundation
import Observation
import GameController

@MainActor
@Observable
public final class GlassSystemKeyboard {
    public static let shared = GlassSystemKeyboard()

    /// A hardware keyboard is connected (GameController's keyboard, which stands for every one connected).
    public private(set) var hardwareKeyboardConnected: Bool

    /// The person asked for the system keyboard anyway, for dictation or emoji. Not kept between launches.
    public var shownAnyway = false

    /// Whether a view that takes the keys gives an empty keyboard in place of the system's.
    public var hidesSystemKeyboard: Bool { hardwareKeyboardConnected && !shownAnyway }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(connected: Bool = GCKeyboard.coalesced != nil, center: NotificationCenter = .default) {
        hardwareKeyboardConnected = connected
        observers = [
            center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardConnected(true) }
            },
            center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardConnected(false) }
            },
        ]
    }

    /// A hardware keyboard came or went. With none, the system keyboard is the way to type, and asking for it is over.
    func keyboardConnected(_ connected: Bool) {
        hardwareKeyboardConnected = connected
        if !connected { shownAnyway = false }
    }
}
