//
//  FocusRoomFit.swift
//  Glass Power Tools — GlassTerminal
//
//  Fitting a 3D environment to the person, and moving about inside it (the owner, 2026-10-26:
//  "random people's 3D files ... don't always set the default camera or size to be human scale", a
//  "try out" room with sliders, and the Mirador gallery's locomotion "once the sizing is right").
//
//  A file says only one thing about its size: the units its numbers are in (`metersPerUnit`), which
//  RealityKit applies and which is often wrong. So a fit says what they are really in, a size on top,
//  how far the model is raised or lowered, and where the person starts; it is kept beside the file
//  (`FocusEnvironmentLibrary`), so every Vision Pro that has the file fits it the same.
//
//  Moving is a teleport, as in the owner's Mirador XR gallery (github.com/msitarzewski/miradorxr,
//  `src/xr/lib/teleport.js` and `floorTarget.js`, `components/FloorTeleport.jsx`): the same
//  headings, the same numbers. The person never moves; the world does, by `FocusWorldPose`.
//

import Foundation

/// What a 3D file's numbers are in, when the person says so.
nonisolated enum FocusRoomUnits: String, Codable, CaseIterable, Sendable {
    case metres, centimetres, millimetres, inches, feet

    var metresPerUnit: Double {
        switch self {
        case .metres: 1
        case .centimetres: 0.01
        case .millimetres: 0.001
        case .inches: 0.0254
        case .feet: 0.3048
        }
    }

    var title: String {
        switch self {
        case .metres: "Metres"
        case .centimetres: "Centimetres"
        case .millimetres: "Millimetres"
        case .inches: "Inches"
        case .feet: "Feet"
        }
    }

    /// The units a file's own `metersPerUnit` names, if it is one of these.
    init?(metresPerUnit: Double) {
        guard let match = Self.allCases.first(where: { abs($0.metresPerUnit - metresPerUnit) <= $0.metresPerUnit * 1e-4 }) else {
            return nil
        }
        self = match
    }
}

/// A place to stand and the way to face: metres, and a heading where 0 looks down −z and a positive
/// one turns left (RealityKit's, and three.js's in Mirador). `y` is the floor's height there.
nonisolated struct FocusSpot: Codable, Equatable, Sendable {
    var x: Double
    var y: Double = 0
    var z: Double
    var yaw: Double = 0

    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && yaw.isFinite }
}

/// How one 3D environment is fitted to the person.
nonisolated struct FocusRoomFit: Codable, Equatable, Sendable {
    /// What the file's numbers are really in; nil believes the file.
    var units: FocusRoomUnits?
    /// On top of the units: 1 as they say.
    var size: Double = 1
    /// Metres the model is raised (below zero, lowered) from standing on the person's floor.
    var floor: Double = 0
    /// Where the person starts, in the file's own coordinates (its units, before the fit); nil for
    /// the file's own camera if it has one, else the middle of a room or before an object.
    var start: FocusSpot?

    static let sizes: ClosedRange<Double> = 0.25...4
    static let floors: ClosedRange<Double> = -5...5

    /// The scale on the model as RealityKit read it, the file's own units already applied.
    func scale(fileMetresPerUnit: Double) -> Double {
        let file = fileMetresPerUnit.isFinite && fileMetresPerUnit > 0 ? fileMetresPerUnit : 1
        let chosen = units?.metresPerUnit ?? file
        return chosen / file * min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound)
    }

    /// A fit as stored, kept to its ranges; nil if it isn't one.
    static func decoded(from data: Data) -> FocusRoomFit? {
        guard var fit = try? JSONDecoder().decode(FocusRoomFit.self, from: data),
              fit.size.isFinite, fit.floor.isFinite else { return nil }
        fit.size = min(max(fit.size, sizes.lowerBound), sizes.upperBound)
        fit.floor = min(max(fit.floor, floors.lowerBound), floors.upperBound)
        if let start = fit.start, !start.isFinite { fit.start = nil }
        return fit
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    /// A slider's place, 0...1, for a size: even steps of doubling, so 1 is in the middle.
    static func sliderValue(forSize size: Double) -> Double {
        let span = log2(sizes.upperBound / sizes.lowerBound)
        return min(max(log2(max(size, sizes.lowerBound) / sizes.lowerBound) / span, 0), 1)
    }

    static func size(forSliderValue value: Double) -> Double {
        let span = log2(sizes.upperBound / sizes.lowerBound)
        return sizes.lowerBound * pow(2, min(max(value, 0), 1) * span)
    }
}

/// Where the model stands once fitted: its scale, and its origin's place around the person.
nonisolated struct FocusRoomPose: Equatable, Sendable {
    var scale: Double
    var offset: SIMD3<Double>

    /// A model with these bounds (metres, the file's units applied), placed as `FocusRoomPlacement`
    /// places it at its fitted size, then raised by the fit's floor.
    init(min: SIMD3<Float>, max: SIMD3<Float>, fit: FocusRoomFit, fileMetresPerUnit: Double) {
        let scale = fit.scale(fileMetresPerUnit: fileMetresPerUnit)
        let placed = FocusRoomPlacement.offset(min: min * Float(scale), max: max * Float(scale))
        self.scale = scale
        offset = SIMD3<Double>(placed) + [0, fit.floor, 0]
    }

    /// A spot in the file's coordinates, where it is in the world.
    func inWorld(_ spot: FocusSpot) -> FocusSpot {
        FocusSpot(x: spot.x * scale + offset.x, y: spot.y * scale + offset.y, z: spot.z * scale + offset.z, yaw: spot.yaw)
    }

    /// A spot in the world, in the file's coordinates.
    func inFile(_ spot: FocusSpot) -> FocusSpot {
        guard scale > 0 else { return spot }
        return FocusSpot(x: (spot.x - offset.x) / scale, y: (spot.y - offset.y) / scale,
                         z: (spot.z - offset.z) / scale, yaw: spot.yaw)
    }
}

/// Where the world stands around the person: a turn of `yaw` about the vertical, then a move, so a
/// point `p` of the world is at `R(yaw)·p + (x, y, z)` around them.
nonisolated struct FocusWorldPose: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var yaw: Double = 0

    static let identity = FocusWorldPose()

    /// The pose that puts `spot`, a place in the world, under the person's head, which is at `head`
    /// around them (its `y` unused), turned so they face the spot's heading. Its floor comes up to
    /// theirs. Mirador's `originForSpot`, for a world that moves instead of the person.
    init(placing spot: FocusSpot, under head: FocusSpot) {
        let turn = head.yaw - spot.yaw
        let (cos, sin) = (Foundation.cos(turn), Foundation.sin(turn))
        x = head.x - (cos * spot.x + sin * spot.z)
        y = -spot.y
        z = head.z - (-sin * spot.x + cos * spot.z)
        yaw = turn
    }

    init(x: Double = 0, y: Double = 0, z: Double = 0, yaw: Double = 0) {
        (self.x, self.y, self.z, self.yaw) = (x, y, z, yaw)
    }

    /// A place in the world, around the person.
    func around(_ spot: FocusSpot) -> FocusSpot {
        let (cos, sin) = (Foundation.cos(yaw), Foundation.sin(yaw))
        return FocusSpot(x: cos * spot.x + sin * spot.z + x, y: spot.y + y, z: -sin * spot.x + cos * spot.z + z,
                         yaw: spot.yaw + yaw)
    }

    /// A place around the person, in the world.
    func inWorld(_ spot: FocusSpot) -> FocusSpot {
        let (dx, dz) = (spot.x - x, spot.z - z)
        let (cos, sin) = (Foundation.cos(-yaw), Foundation.sin(-yaw))
        return FocusSpot(x: cos * dx + sin * dz, y: spot.y - y, z: -sin * dx + cos * dz, yaw: spot.yaw - yaw)
    }
}

/// Mirador's teleport, its numbers and headings.
nonisolated enum FocusLocomotion {
    /// Looking more than about 20 degrees below level shows where the head is aimed.
    static let lookingDown = -0.35
    /// Raising the pinching hand this far (metres) cancels.
    static let liftToCancel = 0.12
    /// The hand moving less than this (metres) keeps the heading the person has.
    static let deadZone = 0.03
    /// A pinch on the sky or a wall swung this far turns the person.
    static let flickAngle = 8 * Double.pi / 180
    static let snapTurn = Double.pi / 4
    static let fadeSeconds = 0.15
    /// As far as the head's aim is followed to the floor.
    static let reach = 20.0
    /// A surface this level or more can be stood on.
    static let levelEnough = 0.6
    /// How far above or below the floor a surface may be and still be the floor: a rug, a threshold.
    static let floorTolerance = 0.12

    /// Whether a pinch may land on a surface: level, and the floor — never a desk's top, a shelf, a
    /// bed or a step (the owner, 2026-10-28: "we need to enforce a 'floor only' locomotion.
    /// Sometimes I get moved to the top of the desk surface"). `height` and `floor` in the same
    /// frame, metres.
    static func canLand(normalY: Double, height: Double, floor: Double) -> Bool {
        normalY >= levelEnough && abs(height - floor) <= floorTolerance
    }

    /// The heading of a horizontal direction.
    static func heading(dx: Double, dz: Double) -> Double { atan2(-dx, -dz) }

    /// The smallest signed difference between two headings, in (−π, π].
    static func angleBetween(_ from: Double, _ to: Double) -> Double {
        atan2(sin(to - from), cos(to - from))
    }

    /// The facing chosen by the pinching hand: the way it has moved across the floor since the pinch
    /// began, once past the dead zone; until then, the heading the person had. Pulled back towards
    /// them, it turns them round.
    static func handHeading(dx: Double, dz: Double, current: Double) -> Double {
        hypot(dx, dz) > deadZone ? heading(dx: dx, dz: dz) : current
    }

    /// The turn a pinch on the sky or a wall makes: its swing from where it began to where it ended,
    /// seen from the head; a swing to the left turns left. Nil for a pinch that didn't swing.
    static func turn(swingFrom start: Double, to end: Double) -> Double? {
        let swing = angleBetween(start, end)
        return abs(swing) > flickAngle ? (swing > 0 ? snapTurn : -snapTurn) : nil
    }

    /// The pose the world takes to turn the person by `angle` where they stand.
    static func turning(_ world: FocusWorldPose, by angle: Double, head: FocusSpot) -> FocusWorldPose {
        var here = world.inWorld(head)
        here.yaw += angle
        here.y = -world.y
        return FocusWorldPose(placing: here, under: head)
    }
}
