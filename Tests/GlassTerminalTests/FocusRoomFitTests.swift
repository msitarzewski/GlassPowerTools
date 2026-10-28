import Foundation
import Testing
@testable import GlassTerminal

/// Fitting a 3D environment to the person and moving about inside it (the owner, 2026-10-26: a "try
/// out" room with sliders for scale, and the Mirador gallery's locomotion once the size is right).
/// The headings and numbers are Mirador's (`teleport.js`, `floorTarget.js`), checked here against
/// places worked out by hand.
@Suite("Fitting a room and moving about in it")
struct FocusRoomFitTests {
    private func close(_ a: Double, _ b: Double, within tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
    private func close(_ a: FocusSpot, _ b: FocusSpot) -> Bool {
        close(a.x, b.x) && close(a.y, b.y) && close(a.z, b.z) && close(FocusLocomotion.angleBetween(a.yaw, b.yaw), 0)
    }

    // MARK: - Size

    @Test("The file's own units stand until the person says otherwise; a file in centimetres read as metres is a hundred times too big")
    func unitsChangeTheScale() {
        var fit = FocusRoomFit()
        #expect(fit.scale(fileMetresPerUnit: 0.01) == 1, "believed, RealityKit has applied the file's units")
        fit.units = .metres
        #expect(close(fit.scale(fileMetresPerUnit: 0.01), 100), "numbers in metres, file said centimetres")
        fit.units = .centimetres
        #expect(close(fit.scale(fileMetresPerUnit: 1), 0.01), "numbers in centimetres, file said metres")
        fit.units = .inches
        #expect(close(fit.scale(fileMetresPerUnit: 1), 0.0254))
        fit.size = 2
        #expect(close(fit.scale(fileMetresPerUnit: 1), 0.0508), "the size goes on top of the units")
        fit = FocusRoomFit(units: nil, size: 2)
        #expect(close(fit.scale(fileMetresPerUnit: .nan), 2), "a file whose units can't be read counts as metres")
    }

    @Test("A file's metersPerUnit is named when it is a unit people use")
    func namesTheFilesUnits() {
        #expect(FocusRoomUnits(metresPerUnit: 0.01) == .centimetres)
        #expect(FocusRoomUnits(metresPerUnit: 1) == .metres)
        #expect(FocusRoomUnits(metresPerUnit: 0.0254) == .inches)
        #expect(FocusRoomUnits(metresPerUnit: 0.5) == nil)
    }

    @Test("The size slider doubles in even steps, with as-is in the middle")
    func sizeSlider() {
        #expect(close(FocusRoomFit.sliderValue(forSize: 1), 0.5))
        #expect(close(FocusRoomFit.size(forSliderValue: 0), FocusRoomFit.sizes.lowerBound))
        #expect(close(FocusRoomFit.size(forSliderValue: 1), FocusRoomFit.sizes.upperBound))
        #expect(close(FocusRoomFit.size(forSliderValue: 0.75), 2))
        for size in [0.3, 0.8, 1.7, 3.9] {
            #expect(close(FocusRoomFit.size(forSliderValue: FocusRoomFit.sliderValue(forSize: size)), size, within: 1e-9))
        }
    }

    @Test("A stored fit is read back, kept to its ranges; anything else isn't a fit")
    func storedFits() throws {
        let fit = FocusRoomFit(units: .feet, size: 1.5, floor: -0.4, start: FocusSpot(x: 1, y: 0, z: -2, yaw: 0.5))
        #expect(FocusRoomFit.decoded(from: try #require(fit.encoded())) == fit)
        let wild = Data(#"{"size": 90, "floor": -40, "start": {"x": 1, "y": 0, "z": 0, "yaw": 0}}"#.utf8)
        let kept = try #require(FocusRoomFit.decoded(from: wild))
        #expect(kept.size == FocusRoomFit.sizes.upperBound)
        #expect(kept.floor == FocusRoomFit.floors.lowerBound)
        #expect(FocusRoomFit.decoded(from: Data("not a fit".utf8)) == nil)
        #expect(FocusRoomFit.decoded(from: Data(#"{"units": "furlongs"}"#.utf8)) == nil)
    }

    // MARK: - Placing

    @Test("The room goes up and down a centimetre at a time, to the centimetre, within its range")
    func roomHeightSteps() {
        var fit = FocusRoomFit()
        for _ in 0..<3 { fit = fit.raised(by: FocusRoomFit.floorStep) }
        #expect(fit.floor == 0.03, "three steps are 3 cm, not 3.0000000000000002")
        fit = fit.raised(by: -FocusRoomFit.floorStep)
        #expect(fit.floor == 0.02)
        #expect(FocusRoomFit(floor: 4.995).raised(by: 0.01).floor == FocusRoomFit.floors.upperBound)
        #expect(FocusRoomFit(floor: -5).raised(by: -0.01).floor == FocusRoomFit.floors.lowerBound)
    }

    @Test("A room raised to line its desk up stays raised where the person starts and lands; a start kept there brings them back")
    func aRaisedRoomStaysRaised() throws {
        // The loft's measure: a sky round it reaching 6 km below its floor, its camera on the floor.
        let pose = FocusRoomPose(min: [-6000, -5998.4, -7000], max: [6000, 6001.6, 6000], fit: FocusRoomFit(floor: 0.03),
                                 fileMetresPerUnit: 1)
        let camera = FocusSpot(x: 0, y: 0, z: 0, yaw: 0)
        let head = FocusSpot(x: 0.1, y: 0, z: -0.2, yaw: 0.6)
        let world = pose.pose(startingAt: camera, under: head)
        let floor = world.around(pose.inWorld(camera))
        #expect(close(floor.x, head.x, within: 1e-9) && close(floor.z, head.z, within: 1e-9), "started at the camera")
        #expect(close(floor.y, 0.03, within: 1e-9), "the room's floor 3 cm above the person's, not at their feet")
        #expect(FocusLocomotion.canLand(normalY: 1, height: floor.y, floor: pose.raise),
                "and it is the floor a pinch may land on, not the bottom of the sky 6 km down")

        // Kept where they stand, and opened again: the same place, the same height.
        let kept = pose.start(standingIn: world, head: head)
        #expect(close(kept.y, 0, within: 1e-9), "kept on the room's floor, not 3 cm under it")
        let again = pose.pose(startingAt: kept, under: head)
        #expect(close(again.x, world.x, within: 1e-9) && close(again.y, world.y, within: 1e-9)
                && close(again.z, world.z, within: 1e-9) && close(again.yaw, world.yaw, within: 1e-9))

        // Landing on the room's floor elsewhere keeps it raised.
        let there = pose.inWorld(FocusSpot(x: 2, y: 0, z: -1, yaw: 1))
        let landed = FocusWorldPose(placing: there, under: head, raised: pose.raise)
        #expect(close(landed.around(there).y, 0.03, within: 1e-9))
    }

    @Test("Fitted, a room still stands around the person with its floor at their feet, then raised by the fit's floor")
    func fittedRoomStandsAroundThePerson() {
        // A 6 × 3 × 4 m room as the file says, its corner at the origin.
        let pose = FocusRoomPose(min: [0, 0, 0], max: [6, 3, 4], fit: FocusRoomFit(size: 0.5, floor: 0.2), fileMetresPerUnit: 1)
        #expect(close(pose.scale, 0.5))
        // Halved: 3 × 1.5 × 2, so its middle (1.5, -, 1) comes to the person, its floor to 0, then up 0.2.
        #expect(close(pose.offset.x, -1.5) && close(pose.offset.y, 0.2, within: 1e-6) && close(pose.offset.z, -1))
        let corner = pose.inWorld(FocusSpot(x: 6, y: 0, z: 4))
        #expect(close(corner.x, 1.5) && close(corner.z, 1) && close(corner.y, 0.2, within: 1e-6))
        #expect(close(pose.inFile(corner), FocusSpot(x: 6, y: 0, z: 4)))
    }

    @Test("Made bigger, a small model becomes a room around the person instead of an object ahead")
    func growingAnObjectMakesARoom() {
        let small = FocusRoomPose(min: [-0.5, 0, -0.5], max: [0.5, 1, 0.5], fit: FocusRoomFit(), fileMetresPerUnit: 1)
        #expect(small.offset.z < -1, "a metre across stands ahead")
        let grown = FocusRoomPose(min: [-0.5, 0, -0.5], max: [0.5, 1, 0.5], fit: FocusRoomFit(size: 4), fileMetresPerUnit: 1)
        #expect(close(grown.offset.z, 0), "four metres across is around the person")
    }

    // MARK: - Moving

    @Test("Placing a spot under the person: the spot comes to their feet, and its heading to the way they face")
    func placingPutsTheSpotUnderThePerson() {
        let head = FocusSpot(x: 0.3, y: 0, z: -0.2, yaw: 0.4)
        let spot = FocusSpot(x: 5, y: 2.5, z: -7, yaw: -1.2)
        let world = FocusWorldPose(placing: spot, under: head)
        let there = world.around(spot)
        #expect(close(there.x, head.x) && close(there.z, head.z), "the spot is where they stand")
        #expect(close(there.y, 0), "its floor is at theirs: an upper floor comes down to them")
        #expect(close(FocusLocomotion.angleBetween(there.yaw, head.yaw), 0), "they face the spot's heading")
        #expect(close(world.inWorld(head), FocusSpot(x: spot.x, y: -world.y, z: spot.z, yaw: spot.yaw)))
        #expect(close(FocusWorldPose(placing: spot, under: head, raised: 0.05).around(spot).y, 0.05),
                "or raised above theirs")
    }

    @Test("Mirador's origin for a spot, worked by hand: turned a quarter, the world swings round the person")
    func aQuarterTurnByHand() {
        // Standing at the origin facing −z; going to (2, 0, 0) facing left (+π/2).
        let world = FocusWorldPose(placing: FocusSpot(x: 2, y: 0, z: 0, yaw: .pi / 2), under: FocusSpot(x: 0, y: 0, z: 0, yaw: 0))
        #expect(close(world.yaw, -.pi / 2))
        // A point a metre further along the heading (−x from the spot: (1, 0, 0)) is a metre ahead (−z).
        let ahead = world.around(FocusSpot(x: 1, y: 0, z: 0))
        #expect(close(ahead.x, 0, within: 1e-12) && close(ahead.z, -1))
    }

    @Test("Around and back are each other's undoing")
    func aroundAndBack() {
        let world = FocusWorldPose(x: 1.5, y: -0.7, z: 3, yaw: 2.1)
        let spot = FocusSpot(x: -4, y: 1, z: 0.5, yaw: 0.3)
        #expect(close(world.inWorld(world.around(spot)), spot))
        #expect(close(world.around(world.inWorld(spot)), spot))
    }

    @Test("The hand's way across the floor sets the heading; within the dead zone it keeps the one there was; pulled back, it turns round")
    func handHeading() {
        #expect(FocusLocomotion.handHeading(dx: 0.01, dz: 0.01, current: 1) == 1)
        #expect(close(FocusLocomotion.handHeading(dx: 0, dz: -0.2, current: 1), 0), "away from the person: on")
        #expect(close(FocusLocomotion.handHeading(dx: -0.2, dz: 0, current: 0), .pi / 2), "to the left: left")
        #expect(close(abs(FocusLocomotion.handHeading(dx: 0, dz: 0.2, current: 0)), .pi), "towards them: round")
    }

    @Test("Only the floor is landed on: a rug or a threshold is; a desk's top, a step and a wall are not")
    func floorOnly() {
        #expect(FocusLocomotion.canLand(normalY: 1, height: 0, floor: 0), "the floor")
        #expect(FocusLocomotion.canLand(normalY: 1, height: 0.04, floor: 0), "a rug")
        #expect(FocusLocomotion.canLand(normalY: 1, height: 1.2, floor: 1.2), "a floor that stands higher in the scene")
        #expect(!FocusLocomotion.canLand(normalY: 1, height: 0.75, floor: 0), "a desk's top")
        #expect(!FocusLocomotion.canLand(normalY: 1, height: 0.18, floor: 0), "a step")
        #expect(!FocusLocomotion.canLand(normalY: 0.1, height: 0, floor: 0), "a wall at floor height")
    }

    @Test("A swing past eight degrees on the sky turns 45° its way; less turns nothing")
    func flickTurns() {
        let degree = Double.pi / 180
        #expect(FocusLocomotion.turn(swingFrom: 0, to: 5 * degree) == nil)
        #expect(FocusLocomotion.turn(swingFrom: 0, to: 10 * degree) == .pi / 4, "swung left, turned left")
        #expect(FocusLocomotion.turn(swingFrom: 0.1, to: 0.1 - 10 * degree) == -.pi / 4)
        #expect(FocusLocomotion.turn(swingFrom: .pi - 2 * degree, to: -.pi + 8 * degree) == .pi / 4, "across ±180°")
    }

    @Test("A nudge steps the person 2 cm the way they face or to their right, by hand: the world moves the other way")
    func aNudgeByHand() {
        // Standing at the origin facing −z: forward is −z, right is +x.
        let stepped = FocusLocomotion.nudging(.identity, forward: 0.02, right: 0.03, turn: 0, head: FocusSpot(x: 0, z: 0))
        #expect(close(stepped.x, -0.03) && close(stepped.z, 0.02) && close(stepped.y, 0) && close(stepped.yaw, 0))
        // Facing −x (a quarter turn left): forward is −x, right is −z.
        let turned = FocusLocomotion.nudging(.identity, forward: 0.02, right: 0.03, turn: 0,
                                             head: FocusSpot(x: 0, z: 0, yaw: .pi / 2))
        let here = turned.inWorld(FocusSpot(x: 0, z: 0, yaw: .pi / 2))
        #expect(close(here.x, -0.02) && close(here.z, -0.03))
    }

    @Test("Nudges in a world already moved go the way the person faces in it, keep their floor, and are read back as steps from where they began")
    func nudgesAreReadBack() {
        let head = FocusSpot(x: 0.2, y: 0, z: 0.1, yaw: 0.3)
        let world = FocusWorldPose(placing: FocusSpot(x: 4, y: 3, z: -2, yaw: 1), under: head)
        let before = world.inWorld(head)
        var moved = world
        moved = FocusLocomotion.nudging(moved, forward: FocusLocomotion.nudgeStep, right: 0, turn: 0, head: head)
        moved = FocusLocomotion.nudging(moved, forward: FocusLocomotion.nudgeStep, right: 0, turn: 0, head: head)
        moved = FocusLocomotion.nudging(moved, forward: 0, right: -FocusLocomotion.nudgeStep, turn: 0, head: head)
        moved = FocusLocomotion.nudging(moved, forward: 0, right: 0, turn: FocusLocomotion.nudgeTurn, head: head)
        let after = moved.inWorld(head)
        #expect(close(after.y, before.y), "on the floor they were on")
        #expect(close(after.x - before.x, -sin(1) * 0.04 - cos(1) * 0.02) && close(after.z - before.z, -cos(1) * 0.04 + sin(1) * 0.02),
                "4 cm the way they face in the world (1 rad), 2 cm to its left")
        let offset = FocusOffset(from: before, to: after, scale: 1)
        #expect(close(offset.ahead, 0.04) && close(offset.right, -0.02) && close(offset.turn, .pi / 180))
    }

    @Test("How far from a start, in its own frame and the room's size, by hand")
    func offsetByHand() {
        // Facing −x, a room at twice its file's size: −0.1 in x is 10 cm ahead, −0.06 in z is 6 cm right.
        let offset = FocusOffset(from: FocusSpot(x: 0, z: 0, yaw: .pi / 2), to: FocusSpot(x: -0.05, z: -0.03, yaw: .pi / 2 - 0.1),
                                 scale: 2)
        #expect(close(offset.ahead, 0.1) && close(offset.right, 0.06) && close(offset.turn, -0.1))
    }

    @Test("A snap turn keeps the person where they stand and on the floor they're on")
    func snapTurnStaysPut() {
        let head = FocusSpot(x: 0.2, y: 0, z: 0.1, yaw: 0.3)
        let world = FocusWorldPose(placing: FocusSpot(x: 4, y: 3, z: -2, yaw: 1), under: head)
        let turned = FocusLocomotion.turning(world, by: .pi / 4, head: head)
        let before = world.inWorld(head), after = turned.inWorld(head)
        #expect(close(before.x, after.x) && close(before.z, after.z) && close(before.y, after.y))
        #expect(close(FocusLocomotion.angleBetween(before.yaw, after.yaw), .pi / 4))
    }
}
