//
//  TrackpadPointerTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/TrackpadPointerTests.swift` on 2026-09-27.
//  Adapted: glassDT's `GlassDesktopCore` and `GlassDesktopUI` are one module here, `GlassDesktop`,
//  so the two imports became one. Every test and assertion is unchanged.
//

import CoreGraphics
import Foundation
import Testing
@testable import GlassDesktop

@Suite("Trackpad pointer")
struct TrackpadPointerTests {
    private func controller() -> TrackpadPointerController {
        TrackpadPointerController(region: .whole(width: 1000, height: 800), viewSize: CGSize(width: 500, height: 400))
    }

    @Test func startsAtTheCentreAndMovesRelativeToTheFinger() {
        var pointer = controller()
        #expect(pointer.position == DesktopPoint(x: 500, y: 400))
        _ = pointer.began(at: CGPoint(x: 10, y: 10), time: 0)
        // The view is half the remote size, so a point of finger travel is two remote pixels.
        let actions = pointer.moved(to: CGPoint(x: 20, y: 10), time: 1)
        #expect(actions == [.move(DesktopPoint(x: 520, y: 400))])
        #expect(pointer.position == DesktopPoint(x: 520, y: 400))
    }

    @Test func quickStationaryTouchClicksWhereTheCursorAlreadyIs() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 100, y: 100), time: 0)
        let actions = pointer.ended(time: 0.1)
        // The click lands at the cursor, not at the point the finger touched.
        #expect(actions == [.move(DesktopPoint(x: 500, y: 400)), .press(.left), .release(.left)])
    }

    @Test func slowOrLongTouchesDoNotClick() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 100, y: 100), time: 0)
        #expect(pointer.ended(time: 1).isEmpty)

        var moved = controller()
        _ = moved.began(at: CGPoint(x: 100, y: 100), time: 0)
        _ = moved.moved(to: CGPoint(x: 140, y: 100), time: 0.05)
        #expect(moved.ended(time: 0.1).isEmpty)
    }

    @Test func touchingAgainRightAfterATapDragsAndReleases() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 100, y: 100), time: 0)
        _ = pointer.ended(time: 0.1)
        let began = pointer.began(at: CGPoint(x: 100, y: 100), time: 0.2)
        #expect(began == [.move(DesktopPoint(x: 500, y: 400)), .press(.left)])
        #expect(pointer.isDragging)
        _ = pointer.moved(to: CGPoint(x: 110, y: 100), time: 0.3)
        #expect(pointer.ended(time: 0.4) == [.release(.left)])
        #expect(!pointer.isDragging)
    }

    @Test func aLaterTouchStartsAFreshClickInsteadOfADrag() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 100, y: 100), time: 0)
        _ = pointer.ended(time: 0.1)
        #expect(pointer.began(at: CGPoint(x: 100, y: 100), time: 5).isEmpty)
        #expect(!pointer.isDragging)
    }

    @Test func twoFingerTapIsTheRightButtonAtTheCursor() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 10, y: 10), time: 0)
        _ = pointer.moved(to: CGPoint(x: 30, y: 30), time: 1)
        let position = pointer.position
        #expect(pointer.secondaryTap() == [.move(position), .press(.right), .release(.right)])
    }

    @Test func theCursorCannotLeaveTheVisibleDisplay() {
        var pointer = TrackpadPointerController(region: DesktopRegion(origin: .init(x: 2000, y: 0),
                                                                      size: DesktopSize(width: 1000, height: 600)),
                                                viewSize: CGSize(width: 500, height: 300))
        #expect(pointer.position == DesktopPoint(x: 2500, y: 300))
        _ = pointer.began(at: CGPoint(x: 250, y: 150), time: 0)
        _ = pointer.moved(to: CGPoint(x: -10000, y: -10000), time: 10)
        #expect(pointer.position == DesktopPoint(x: 2000, y: 0))
        _ = pointer.moved(to: CGPoint(x: 10000, y: 10000), time: 20)
        #expect(pointer.position == DesktopPoint(x: 2999, y: 599))
    }

    @Test func fastMovementIsAmplifiedButBounded() {
        var slow = controller()
        _ = slow.began(at: .zero, time: 0)
        _ = slow.moved(to: CGPoint(x: 10, y: 0), time: 1)
        let slowTravel = slow.position.x - 500

        var fast = controller()
        _ = fast.began(at: .zero, time: 0)
        _ = fast.moved(to: CGPoint(x: 10, y: 0), time: 0.001)
        let fastTravel = fast.position.x - 500

        #expect(fastTravel > slowTravel)
        #expect(Double(fastTravel) <= Double(slowTravel) * TrackpadPointerController.maximumAcceleration + 1)
    }

    @Test func cancellingReleasesAHeldDrag() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 10, y: 10), time: 0)
        _ = pointer.ended(time: 0.05)
        _ = pointer.began(at: CGPoint(x: 10, y: 10), time: 0.1)
        #expect(pointer.cancelled() == [.release(.left)])
        var idle = controller()
        #expect(idle.cancelled().isEmpty)
    }

    /// When a second finger arrives the view cancels pointing. Movement reported after that, before a
    /// finger is deliberately placed again, must not shift the cursor, which is what made it jump.
    @Test func movementIsIgnoredUntilAFingerIsPlacedAgain() {
        var pointer = controller()
        _ = pointer.began(at: CGPoint(x: 100, y: 100), time: 0)
        _ = pointer.moved(to: CGPoint(x: 120, y: 100), time: 1)
        let settled = pointer.position
        #expect(settled.x > 500)

        _ = pointer.cancelled()
        #expect(pointer.moved(to: CGPoint(x: 400, y: 400), time: 2).isEmpty)
        #expect(pointer.position == settled)

        // Placing a finger again continues from where the cursor was left, not from the finger.
        _ = pointer.began(at: CGPoint(x: 300, y: 300), time: 3)
        _ = pointer.moved(to: CGPoint(x: 310, y: 300), time: 4)
        #expect(pointer.position.y == settled.y)
        #expect(pointer.position.x > settled.x)
        #expect(pointer.position.x - settled.x < 30)
    }

    @Test func changingDisplayKeepsTheCursorInsideIt() {
        var pointer = controller()
        _ = pointer.began(at: .zero, time: 0)
        _ = pointer.moved(to: CGPoint(x: 250, y: 200), time: 1)
        pointer.update(region: DesktopRegion(origin: .init(x: 0, y: 0), size: DesktopSize(width: 400, height: 300)),
                       viewSize: CGSize(width: 400, height: 300))
        #expect(pointer.position.x <= 399 && pointer.position.y <= 299)
    }

    @Test func pointerModeDefaultsToTheScreenSize() {
        #expect(DesktopPointerMode.standard(forCompactScreen: true) == .trackpad)
        #expect(DesktopPointerMode.standard(forCompactScreen: false) == .directTouch)
        #expect(DesktopPointerMode.trackpad.title == "Trackpad")
        #expect(DesktopPointerMode.allCases.count == 2)
    }
}
