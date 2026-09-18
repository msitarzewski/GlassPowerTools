//
//  WindowPresentationTests.swift
//  Glass Power Tools — GlassShellTests
//
//  The one question every capability that opens a window has to ask.
//
//  Run on an iPhone (simulator or device) this is a real check of the platform's own answer, which
//  is the only thing that matters: `openWindow` does nothing there, silently, so a capability that
//  believes otherwise answers the user's tap by doing nothing at all. The editor's Projects panel
//  and the desktop's session both shipped with that belief.
//

import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import GlassShell

@MainActor
@Suite("Whether this device can open a window")
struct WindowPresentationTests {

    @Test("an iPhone says no, and everything else says yes")
    func theDeviceAnswersHonestly() {
        #if os(iOS)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        if isPhone {
            #expect(!GlassWindowPresentation.canOpenWindows,
                    "an iPhone reported that it can open windows — every capability that believes it answers a tap by doing nothing")
        } else {
            #expect(GlassWindowPresentation.canOpenWindows,
                    "an iPad reported that it cannot open windows, so every session would be forced into a cover")
        }
        #else
        // macOS and visionOS both have real windows.
        #expect(GlassWindowPresentation.canOpenWindows)
        #endif
    }
}
