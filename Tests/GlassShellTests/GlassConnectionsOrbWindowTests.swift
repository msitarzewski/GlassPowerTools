//
//  GlassConnectionsOrbWindowTests.swift
//  Glass Power Tools — GlassShellTests
//
//  The headset's Connections window becoming its own orb (W39): the sizes it goes between, what
//  happens when it is the last window to close, and the one-orb rule. The window doing it is
//  driven on the visionOS simulator by `GlassConnectionsOrbUITests`.
//

import CoreGraphics
import Foundation
import Testing
@testable import GlassShell

@Suite("Connections becomes its own orb")
struct GlassConnectionsWindowSizeTests {
    // MARK: The sizes

    /// The Mac's Connections width (the owner, 2026-10-14: "it should be wider by default").
    @Test func theLibraryOpensAt1180By700() {
        #expect(GlassConnectionsWindowSize.standard == CGSize(width: 1180, height: 700))
    }

    /// The orb is 184 points square; its window is as narrow as visionOS makes one, 320 points
    /// (measured: asked for 184 × 184, the window came out 320 × 184), and the orb's height.
    @Test func theOrbsWindowIsTheNarrowestVisionOSMakesAndTheOrbsHeight() {
        #expect(GlassConnectionsWindowSize.orbSide == 184)
        #expect(GlassConnectionsWindowSize.orb == CGSize(width: 320, height: 184))
    }

    @Test func onlyAWindowAboutTheOrbsSizeCountsAsOrbSized() {
        #expect(GlassConnectionsWindowSize.isOrbSized(GlassConnectionsWindowSize.orb))
        #expect(GlassConnectionsWindowSize.isOrbSized(CGSize(width: 184, height: 184)))
        #expect(GlassConnectionsWindowSize.isOrbSized(CGSize(width: 400, height: 230)))
        #expect(!GlassConnectionsWindowSize.isOrbSized(CGSize(width: 401, height: 230)))
        #expect(!GlassConnectionsWindowSize.isOrbSized(CGSize(width: 320, height: 231)))
        #expect(!GlassConnectionsWindowSize.isOrbSized(CGSize(width: 320, height: 600)),
                "a narrow but tall library is someone's choice, not an orb left behind")
        #expect(!GlassConnectionsWindowSize.isOrbSized(GlassConnectionsWindowSize.standard))
    }

    /// The library grows back to the size it had, whatever that was, and never to the orb's.
    @Test func theLibraryGrowsBackToTheSizeItHad() {
        let had = CGSize(width: 1240, height: 810)
        #expect(GlassConnectionsWindowSize.returning(to: had) == had)
        #expect(GlassConnectionsWindowSize.returning(to: CGSize(width: 520, height: 400)) == CGSize(width: 520, height: 400))
    }

    @Test(arguments: [
        nil,
        CGSize(width: 184, height: 184),
        CGSize(width: 0, height: 700),
        CGSize(width: -960, height: 700),
        CGSize(width: CGFloat.nan, height: 700),
        CGSize(width: CGFloat.infinity, height: 700),
        CGSize(width: 50_000, height: 700),
    ])
    func withoutAUsableSizeTheLibraryComesBackAtItsFirstSize(remembered: CGSize?) {
        #expect(GlassConnectionsWindowSize.returning(to: remembered) == GlassConnectionsWindowSize.standard)
    }

    // MARK: Kept with the scene

    @Test func aKeptSizeReadsBackInWholePoints() {
        let text = GlassConnectionsWindowSize.stored(CGSize(width: 1200.4, height: 799.6))
        #expect(text == "1200x800")
        #expect(GlassConnectionsWindowSize.stored(text) == CGSize(width: 1200, height: 800))
    }

    @Test func nothingKeptIsEmpty() {
        #expect(GlassConnectionsWindowSize.stored(nil as CGSize?) == "")
        #expect(GlassConnectionsWindowSize.stored(CGSize(width: CGFloat.nan, height: 1)) == "")
        #expect(GlassConnectionsWindowSize.stored("") == nil)
    }

    @Test(arguments: ["960", "960x", "x700", "960x700x1", "960 x 700", "0x700", "-960x700", "abcx700", "99999x700"])
    func anythingThisBuildDidNotWriteReadsAsNothing(text: String) {
        #expect(GlassConnectionsWindowSize.stored(text) == nil)
    }

    // MARK: The scene's limits

    @Test func aSizeInsideTheLimitsIsAdmitted() {
        let orb = GlassConnectionsWindowSize.orb
        #expect(GlassConnectionsWindowSize.admits(orb, minimum: orb, maximum: orb))
        #expect(GlassConnectionsWindowSize.admits(CGSize(width: orb.width + 0.4, height: orb.height - 0.4),
                                                  minimum: orb, maximum: orb),
                "half a point either way is the same size")
    }

    /// A size the old limits still forbid waits for SwiftUI to hand the scene the new ones:
    /// growing back while the scene is still held to the orb's size would be held to it.
    @Test func aSizeOutsideTheLimitsWaits() {
        let orb = GlassConnectionsWindowSize.orb
        #expect(!GlassConnectionsWindowSize.admits(GlassConnectionsWindowSize.standard, minimum: orb, maximum: orb))
        let library = CGSize(width: 400, height: 300)
        #expect(!GlassConnectionsWindowSize.admits(orb, minimum: library, maximum: CGSize(width: 4000, height: 4000)))
    }

    @Test func aLimitOfZeroOrInfinityIsNoLimit() {
        let open = [CGSize.zero, CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
                    CGSize(width: -1, height: -1)]
        for minimum in open {
            for maximum in open {
                #expect(GlassConnectionsWindowSize.admits(GlassConnectionsWindowSize.orb, minimum: minimum, maximum: maximum))
                #expect(GlassConnectionsWindowSize.admits(CGSize(width: 3000, height: 2000), minimum: minimum, maximum: maximum))
            }
        }
    }
}

@Suite("When the last window closes")
struct GlassLastWindowTests {
    /// On the headset, closing the library as the last window leaves its orb in its place.
    @Test func theLibraryClosedLastIsParkedAsItsOrb() {
        #expect(GlassWindowRecoveryManager.actionAfterLastWindow(closed: "main", connectionsWasOrb: false, parksAsOrb: true)
                == .parkConnectionsAsOrb)
    }

    /// Closing the orb too leaves nothing: the quit gesture.
    @Test func theOrbClosedLastLeavesTheSpaceEmpty() {
        #expect(GlassWindowRecoveryManager.actionAfterLastWindow(closed: "main", connectionsWasOrb: true, parksAsOrb: true)
                == .leaveEmpty)
    }

    /// The Mac, iPad and iPhone have no orb: the library closed last stays closed.
    @Test func offTheHeadsetTheLibraryClosedLastStaysClosed() {
        #expect(GlassWindowRecoveryManager.actionAfterLastWindow(closed: "main", connectionsWasOrb: false, parksAsOrb: false)
                == .leaveEmpty)
    }

    @Test(arguments: ["terminal", "sftp", "html-preview-1", "desktop-session", "minimized"])
    func anyOtherWindowClosedLastBringsTheLibraryBack(key: String) {
        #expect(GlassWindowRecoveryManager.actionAfterLastWindow(closed: key, connectionsWasOrb: false, parksAsOrb: true)
                == .openConnections)
        #expect(GlassWindowRecoveryManager.actionAfterLastWindow(closed: key, connectionsWasOrb: true, parksAsOrb: false)
                == .openConnections)
    }
}

@MainActor
@Suite("One orb")
struct GlassOneOrbTests {
    @Test func aSecondConnectionsWindowSeesTheFirstStandingAsTheOrb() {
        let recovery = GlassWindowRecoveryManager()
        let first = UUID(), second = UUID()
        #expect(!recovery.anotherConnectionsWindowIsOrb(than: second))

        recovery.connectionsBecameOrb(first)
        #expect(recovery.anotherConnectionsWindowIsOrb(than: second))
        #expect(!recovery.anotherConnectionsWindowIsOrb(than: first), "a window is not another to itself")

        recovery.connectionsBecameLibrary(first)
        #expect(!recovery.anotherConnectionsWindowIsOrb(than: second))
    }

    /// An orb that closes is no longer one, so it cannot make a later window close itself.
    @Test func aClosedOrbStandsForNothing() {
        let recovery = GlassWindowRecoveryManager()
        let orb = UUID()
        recovery.connectionsBecameOrb(orb)
        recovery.connectionsWindowClosed(orb)
        #expect(recovery.orbConnectionsWindows.isEmpty)
        #expect(!recovery.anotherConnectionsWindowIsOrb(than: UUID()))
    }

    /// Nothing asks for an orb off the headset, and a park nobody made is never taken.
    @Test func withNoParkAWindowOpensAsTheLibrary() {
        let recovery = GlassWindowRecoveryManager()
        #expect(!recovery.connectionsParkIsPending)
        #expect(!recovery.takeConnectionsPark())
    }
}
