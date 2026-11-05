//
//  GlassSystemKeyboardTests.swift
//  Glass Power Tools — GlassShellTests
//
//  The system keyboard put away while a hardware keyboard is connected (the owner, 2026-11-05: "yes, hide the mini
//  keyboard ... The only tension I'm going to have is voice dictation and emoji selection"). What must hold: with no
//  hardware keyboard, the system's is the way to type and stays; one connecting puts it away; asking for it brings it
//  back, and putting it away again hides it; the hardware keyboard going brings it back and ends the asking, so the
//  next keyboard to connect hides it again.
//

import Foundation
import GameController
import Testing
@testable import GlassShell

@MainActor
@Suite("The system keyboard is put away while a hardware keyboard is connected")
struct GlassSystemKeyboardTests {
    /// Waits for a notification's handler, delivered on the main queue.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Settings of their own, so a test's choice is never the next's.
    private func defaults() -> UserDefaults {
        let name = "GlassSystemKeyboardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("With no hardware keyboard, the system's stays")
    func noHardwareKeyboardKeepsTheSystems() {
        let keyboard = GlassSystemKeyboard(connected: false, center: NotificationCenter(), defaults: defaults())
        #expect(keyboard.choice == .automatic, "Automatic until chosen")
        #expect(!keyboard.hidesSystemKeyboard)
    }

    @Test("Only When Asked holds the system's back with no hardware keyboard too, until asked for; kept on the device")
    func onlyWhenAskedHoldsItBack() {
        // The owner, 2026-11-05: "can we hide this keyboard until i reques it?" His headset reported no hardware keyboard.
        let settings = defaults()
        let keyboard = GlassSystemKeyboard(connected: false, center: NotificationCenter(), defaults: settings)
        keyboard.choice = .onlyWhenAsked
        #expect(keyboard.holdsBack && keyboard.hidesSystemKeyboard)
        keyboard.shownAnyway = true
        #expect(!keyboard.hidesSystemKeyboard, "Keys > Show Keyboard")
        keyboard.shownAnyway = false
        #expect(keyboard.hidesSystemKeyboard, "Keys > Hide Keyboard")
        let next = GlassSystemKeyboard(connected: false, center: NotificationCenter(), defaults: settings)
        #expect(next.choice == .onlyWhenAsked && next.hidesSystemKeyboard, "the next launch keeps it")
    }

    @Test("A hardware keyboard connecting puts the system's away; asked for, it comes back, and goes again")
    func connectingHidesAndAskingShows() async {
        let center = NotificationCenter()
        let keyboard = GlassSystemKeyboard(connected: false, center: center, defaults: defaults())
        center.post(name: .GCKeyboardDidConnect, object: nil)
        await settle { keyboard.hardwareKeyboardConnected }
        #expect(keyboard.hidesSystemKeyboard)
        keyboard.shownAnyway = true
        #expect(!keyboard.hidesSystemKeyboard, "asked for, for dictation or emoji")
        keyboard.shownAnyway = false
        #expect(keyboard.hidesSystemKeyboard)
    }

    @Test("The hardware keyboard going brings the system's back and ends the asking")
    func disconnectingShowsAndForgetsTheAsking() async {
        let center = NotificationCenter()
        let keyboard = GlassSystemKeyboard(connected: true, center: center, defaults: defaults())
        keyboard.shownAnyway = true
        center.post(name: .GCKeyboardDidDisconnect, object: nil)
        await settle { !keyboard.hardwareKeyboardConnected }
        #expect(!keyboard.hidesSystemKeyboard)
        #expect(!keyboard.shownAnyway)
        center.post(name: .GCKeyboardDidConnect, object: nil)
        await settle { keyboard.hardwareKeyboardConnected }
        #expect(keyboard.hidesSystemKeyboard, "the next keyboard puts it away again")
    }
}
