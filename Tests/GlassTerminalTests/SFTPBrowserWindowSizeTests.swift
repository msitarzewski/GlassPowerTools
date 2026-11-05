//
//  SFTPBrowserWindowSizeTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A Files window on Vision Pro opens at the size the last one was left at (the owner, 2026-11-05: "it should also
//  remember the user's preference for sizing. It opens a little too wide now"). What must hold: with nothing kept, the
//  standard size, wide enough for every column and the name; a size kept is the next window's; a size no window can
//  have (zero, as a window has before it is laid out) leaves what was kept alone.
//

import CoreGraphics
import Foundation
import Testing
@testable import GlassTerminal

@Suite("A Files window opens at the size the last one was left at")
struct SFTPBrowserWindowSizeTests {
    private func freshDefaults() -> UserDefaults {
        let name = "SFTPBrowserWindowSizeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("With nothing kept, the standard size: every column and the name, and no wider than that needs")
    func standardFitsEveryColumn() {
        let defaults = freshDefaults()
        #expect(SFTPBrowserWindowSize.opening(in: defaults) == SFTPBrowserWindowSize.standard)
        let rowWidth = SFTPBrowserWindowSize.standard.width - SFTPBrowserView.spatialRowChrome
        #expect(SFTPFileRowLayout.fitting(width: rowWidth) == .full)
        #expect(SFTPBrowserWindowSize.standard.width < 1100, "1100 was a little too wide")
    }

    @Test("The size a window is left at is where the next one opens")
    func keptSizeIsTheNext() {
        let defaults = freshDefaults()
        SFTPBrowserWindowSize.keep(CGSize(width: 812.4, height: 640), in: defaults)
        #expect(SFTPBrowserWindowSize.opening(in: defaults) == CGSize(width: 812, height: 640))
        SFTPBrowserWindowSize.keep(CGSize(width: 1300, height: 700), in: defaults)
        #expect(SFTPBrowserWindowSize.opening(in: defaults) == CGSize(width: 1300, height: 700))
    }

    @Test("A size no window has leaves the kept one alone")
    func zeroSizeIsNotKept() {
        let defaults = freshDefaults()
        SFTPBrowserWindowSize.keep(CGSize(width: 900, height: 600), in: defaults)
        SFTPBrowserWindowSize.keep(.zero, in: defaults)
        #expect(SFTPBrowserWindowSize.opening(in: defaults) == CGSize(width: 900, height: 600))
    }
}
