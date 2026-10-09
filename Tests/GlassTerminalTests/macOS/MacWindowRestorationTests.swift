#if os(macOS)
import AppKit
import Testing
@testable import GlassTerminal

/// D54: the app reopens its windows from its own records. AppKit's saved window state is neither
/// written nor replayed — a leftover state was restored at every launch as empty terminal windows
/// (2026-10-09).
@MainActor
@Suite("Window restoration")
struct MacWindowRestorationTests {
    @Test("AppKit neither saves nor restores the app's window state")
    func appKitStateIsOff() {
        let delegate = MacTerminalAppDelegate()
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        #expect(delegate.applicationSupportsSecureRestorableState(NSApplication.shared))
        #expect(!delegate.application(NSApplication.shared, shouldSaveSecureApplicationState: coder))
        #expect(!delegate.application(NSApplication.shared, shouldRestoreSecureApplicationState: coder))
    }
}
#endif
