//
//  FocusEnvironmentWalking.swift
//  Glass Power Tools — GlassTerminal
//
//  Moving about inside Focus Mode's environment on Vision Pro, as in the owner's Mirador XR gallery
//  (the owner, 2026-10-26: "Could we allow that interaction to move around once the sizing is
//  right?"). Look down and a ring shows where the head is aimed. Pinch the floor where you look: a
//  green target. Move the pinching hand the way you want to face — left to face left, away to face
//  on, back to turn round — and let go to go; raise it to cancel. Pinch the sky or a wall and swing
//  the hand to turn 45°. Only the floor can be landed on: a pinch on a desk, a shelf or a step shows
//  the target greyed and goes nowhere (the owner, 2026-10-28: "we need to enforce a 'floor only'
//  locomotion").
//
//  The person never moves: the world does (`FocusWorldPose`), through a moment of dark. visionOS
//  fades a fully immersive space for anyone who walks about 1.5 m from where they began, so this is
//  how a room is crossed. The math is `FocusRoomFit.swift`'s, tested there.
//

import SwiftUI
import OSLog

#if os(visionOS)
import RealityKit
import QuartzCore
import GlassShell

/// Everything that walks: the world that moves, the floor and sky that catch pinches, the ring and
/// target that show where they lead, and the head they are measured from.
@MainActor
final class FocusWalking {
    /// Everything that moves when the person does: the environment and its floor.
    let world = Entity()
    /// The environment's own content: a sky, a floor, a room. Swapped as it changes.
    let content = Entity()
    /// What a room is placed in: scaled and moved by its fit (`FocusRoomPose`).
    private let roomHolder = Entity()

    /// The floor forced under every environment (the owner: "We'd need to force a 'floor'"): unseen,
    /// in the world at the height its environment stands on, there to be pinched.
    private let ground = Entity()
    /// A floor that can be seen under a room or an object, which may have none: dark, fading out.
    private var groundLook: Entity?
    /// Far walls and a ceiling around the person, there to be pinched and swung to turn.
    private let sky = Entity()
    private var ring = Entity()
    private var target = Entity()
    private var arrow = Entity()
    private var targetMaterial = UnlitMaterial()

    private let head = GlassHeadTracker(purpose: "Focus Mode")
    private(set) var pose = FocusWorldPose.identity
    private var room: FocusEnvironmentScenes.LoadedRoom?
    private var roomPose: FocusRoomPose?
    /// Whether this environment has somewhere to walk: not the dimmed room, not a photo.
    private var walks = false
    private var press: Press?
    private var swing: Double?
    private var moving = false
    private var updates: EventSubscription?
    /// Counts environments shown, so surfaces made for one aren't put on the next.
    private var shown = 0
    /// A room's own life (`FocusRoomLife.swift`): its motion playing, its clock, its sounds.
    private var motion: [AnimationPlaybackController] = []
    private var clock: FocusRoomClockHands?
    private var soundscape: FocusRoomSoundscape?
    private var happenings: FocusRoomHappenings?
    /// The digital clock and date panel, made by the space's view (an attachment), placed in a room
    /// that has a `clock_digital`.
    var digitalClock: Entity?
    /// Settings' Room Sound, 0 to 1.
    var soundLevel: Double = 0.7 {
        didSet { soundscape?.setLevel(soundLevel) }
    }

    static let groundGroup = CollisionGroup(rawValue: 1 << 20)
    static let roomGroup = CollisionGroup(rawValue: 1 << 21)
    static let skyGroup = CollisionGroup(rawValue: 1 << 22)
    private static let standable: CollisionGroup = [groundGroup, roomGroup]
    private static let targetColour = UIColor(red: 0x3e / 255, green: 0xc4 / 255, blue: 0x6d / 255, alpha: 1)
    private static let cancelColour = UIColor(white: 0x8a / 255, alpha: 1)
    nonisolated fileprivate static let log = Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")

    /// A pinch on the floor under way: where it lands, the way the person will face, and whether the
    /// raised hand has cancelled it.
    fileprivate struct Press {
        var spot: SIMD3<Float>
        var yaw: Double
        var handStart: SIMD3<Float>
        var cancelled = false
        /// On something that isn't the floor: shown, and never gone to.
        var offFloor = false
    }

    /// Where a pinch would take the person.
    fileprivate enum Landing {
        /// The floor, there.
        case floor(SIMD3<Float>)
        /// Level, but not the floor: a desk's top, a shelf, a step.
        case offFloor(SIMD3<Float>)
        /// A wall or a ceiling, which turns instead.
        case wall
    }

    init() {
        world.name = "focus-world"
        world.addChild(content)
        world.addChild(ground)
        ground.components.set(CollisionComponent(shapes: [.generateBox(width: 400, height: 0.02, depth: 400)],
                                                 isStatic: true,
                                                 filter: CollisionFilter(group: Self.groundGroup, mask: .all)))
        ground.position = [0, -0.01, 0]
        // Walls 16 round, 60 m off, and a ceiling: a pinch on the sky lands on one.
        for index in 0..<16 {
            let angle = Float(index) / 16 * 2 * .pi
            let wall = Entity()
            wall.components.set(CollisionComponent(shapes: [.generateBox(width: 26, height: 200, depth: 1)],
                                                   isStatic: true,
                                                   filter: CollisionFilter(group: Self.skyGroup, mask: .all)))
            wall.position = [60 * sin(angle), 50, -60 * cos(angle)]
            wall.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            sky.addChild(wall)
        }
        let ceiling = Entity()
        ceiling.components.set(CollisionComponent(shapes: [.generateBox(width: 130, height: 1, depth: 130)],
                                                  isStatic: true,
                                                  filter: CollisionFilter(group: Self.skyGroup, mask: .all)))
        ceiling.position = [0, 120, 0]
        sky.addChild(ceiling)
        setWalks(false)
    }

    /// Puts the walking into the space, and follows the head every frame for the ring.
    func install(in root: Entity, content realityContent: RealityViewContent) {
        root.addChild(world)
        root.addChild(sky)
        ring = Self.ringEntity()
        root.addChild(ring)
        (target, arrow, targetMaterial) = Self.targetEntity()
        root.addChild(target)
        updates = realityContent.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followHead()
                self?.clock?.tick(now: .now)
            }
        }
    }

    /// Head tracking while the space is open: given up when it closes.
    func trackHead() async {
        await head.run()
    }

    func stopTrackingHead() {
        head.stop()
    }

    // MARK: - What's shown

    /// A new environment: its content, walkable or not, and where the person starts in it.
    func show(_ scene: Entity?, room loaded: FocusEnvironmentScenes.LoadedRoom?, fit: FocusRoomFit, walks: Bool) {
        endLife()
        content.children.removeAll()
        roomHolder.children.removeAll()
        groundLook?.removeFromParent()
        room = loaded
        roomPose = nil
        shown += 1
        if let scene { content.addChild(scene) }
        if let loaded {
            roomHolder.addChild(loaded.model)
            content.addChild(roomHolder)
            if groundLook == nil { groundLook = Self.groundLookEntity() }
            if let groundLook { world.addChild(groundLook) }
            place(fit)
            startLife(loaded)
            let showing = shown
            Task { await self.makeStandable(loaded.model, showing: showing) }
        }
        setWalks(walks)
        pose = startingPose(fit: fit)
        apply(pose)
    }

    /// The room placed by a fit: called again as Try Out changes it, the person staying put.
    func place(_ fit: FocusRoomFit) {
        guard let room else { return }
        let placed = FocusRoomPose(min: room.min, max: room.max, fit: fit, fileMetresPerUnit: room.fileMetresPerUnit)
        roomPose = placed
        roomHolder.scale = SIMD3(repeating: Float(placed.scale))
        roomHolder.position = SIMD3<Float>(placed.offset)
    }

    /// Where the person stands now, in the room file's own coordinates (Start Here); nil without a room.
    func placeInFile() -> FocusSpot? {
        guard let roomPose else { return nil }
        return roomPose.inFile(pose.inWorld(headSpot()))
    }

    /// The fitted room's size, metres, for Try Out's readout.
    var roomSize: SIMD3<Double>? {
        guard let room, let roomPose else { return nil }
        return SIMD3<Double>(room.max - room.min) * roomPose.scale
    }

    private func startingPose(fit: FocusRoomFit) -> FocusWorldPose {
        guard let roomPose, let start = fit.start ?? room?.camera else { return .identity }
        return FocusWorldPose(placing: roomPose.inWorld(start), under: headSpot())
    }

    private func setWalks(_ walks: Bool) {
        self.walks = walks
        for wall in [ground] + Array(sky.children) {
            if walks { wall.components.set(InputTargetComponent()) } else { wall.components.remove(InputTargetComponent.self) }
        }
        if !walks {
            ring.isEnabled = false
            target.isEnabled = false
            press = nil
            swing = nil
        }
    }

    /// A room's life, once it is in the scene: the motion it carries playing round and round from
    /// somewhere in its loop, so each visit starts elsewhere and its birds and aircraft come when
    /// they will (still with Reduce Motion); its clock on the headset's time; its sounds.
    private func startLife(_ loaded: FocusEnvironmentScenes.LoadedRoom) {
        let still = UIAccessibility.isReduceMotionEnabled
        if !still {
            for animation in loaded.model.availableAnimations {
                let loop = animation.definition.duration
                let controller = loaded.model.playAnimation(animation.repeat(), transitionDuration: 0, startsPaused: false)
                if loop.isFinite, loop > 0 { controller.time = .random(in: 0..<loop) }
                motion.append(controller)
            }
        }
        clock = FocusRoomClockHands(in: loaded.model)
        if let sounds = loaded.sounds, let folder = loaded.file.map(FocusRoomSounds.folder(beside:)) {
            soundscape = FocusRoomSoundscape(sounds, folder: folder, in: loaded.model, level: soundLevel)
        }
        var panel = false
        if let digitalClock {
            panel = FocusRoomLife.placeDigitalClock(digitalClock, panelWidth: digitalClock.visualBounds(relativeTo: digitalClock).extents.x,
                                                    in: loaded.model)
        }
        // What happens now and then is motion too.
        if !still, let events = loaded.events, let folder = loaded.file.map(FocusRoomEvents.folder(beside:)) {
            happenings = FocusRoomHappenings(events, folder: folder, in: loaded.model)
        }
        Self.log.info("Room life: \(self.motion.count, privacy: .public) animations, clock \(self.clock != nil, privacy: .public), digital clock \(panel, privacy: .public), \(loaded.sounds?.sounds.count ?? 0, privacy: .public) sounds, \(still ? 0 : loaded.events?.events.count ?? 0, privacy: .public) events")
    }

    /// Before the next environment, or as the space closes: silent and still.
    func endLife() {
        happenings?.stop()
        happenings = nil
        digitalClock?.removeFromParent()
        soundscape?.stop()
        soundscape = nil
        motion.forEach { $0.stop() }
        motion = []
        clock = nil
    }

    /// A room's surfaces, made somewhere to stand and to pinch: its floors, stairs and landings to
    /// land on, its walls and ceilings to turn by. Made after it shows, as a big room takes a moment.
    /// Not what moves in it (`FocusRoomLife.standableDescendants`): no standing on a car.
    private func makeStandable(_ model: Entity, showing: Int) async {
        var made = 0
        for entity in FocusRoomLife.standableDescendants(of: model) {
            guard let mesh = entity.components[ModelComponent.self]?.mesh else { continue }
            do {
                let shape = try await ShapeResource.generateStaticMesh(from: mesh)
                guard showing == shown else { return }
                entity.components.set(CollisionComponent(shapes: [shape], isStatic: true,
                                                         filter: CollisionFilter(group: Self.roomGroup, mask: .all)))
                entity.components.set(InputTargetComponent())
                made += 1
            } catch {
                Self.log.error("A room surface couldn't be made to stand on: \(String(describing: error), privacy: .public)")
            }
        }
        Self.log.info("Room surfaces to stand on: \(made, privacy: .public)")
    }

    // MARK: - Pinches

    /// A pinch on the floor, a room or the sky, as it goes.
    func changed(_ value: EntityTargetValue<DragGesture.Value>) {
        guard walks, !moving else { return }
        let hand = handPosition(value)
        if let press {
            let movement = hand - press.handStart
            var next = press
            next.yaw = FocusLocomotion.handHeading(dx: Double(movement.x), dz: Double(movement.z), current: press.yaw)
            next.cancelled = press.offFloor || Double(movement.y) > FocusLocomotion.liftToCancel
            self.press = next
            showTarget(next)
            return
        }
        guard swing == nil else { return }
        let group = value.entity.components[CollisionComponent.self]?.filter.group ?? []
        let pinched = value.convert(value.startLocation3D, from: .local, to: .scene)
        let landing: Landing = group.isDisjoint(with: Self.standable) ? .wall : landing(at: pinched)
        switch landing {
        case .floor(let spot), .offFloor(let spot):
            var started = Press(spot: spot, yaw: headSpot().yaw, handStart: handStart(value) ?? hand)
            if case .offFloor = landing { started.offFloor = true; started.cancelled = true }
            press = started
            ring.isEnabled = false
            showTarget(started)
        case .wall:
            swing = heading(to: handStart(value) ?? pinched)
        }
    }

    /// Let go: go there, or turn.
    func ended(_ value: EntityTargetValue<DragGesture.Value>) {
        defer { press = nil; swing = nil; target.isEnabled = false }
        guard walks, !moving else { return }
        if let press {
            guard !press.cancelled else { return }
            let landing = pose.inWorld(FocusSpot(x: Double(press.spot.x), y: Double(press.spot.y),
                                                 z: Double(press.spot.z), yaw: press.yaw))
            move(to: FocusWorldPose(placing: landing, under: headSpot()))
        } else if let swing, let turn = FocusLocomotion.turn(swingFrom: swing, to: heading(to: handPosition(value))) {
            move(to: FocusLocomotion.turning(pose, by: turn, head: headSpot()))
        }
    }

    /// Where a pinch at `point` (around the person) lands: the floor it was on; a level surface that
    /// isn't the floor, where it won't go; or a wall or a ceiling, which turn instead.
    fileprivate func landing(at point: SIMD3<Float>) -> Landing {
        let floor = Double(floorHeight)
        guard let scene = world.scene else { return .floor(point) }
        let eye = headPosition()
        let toward = point - eye
        let distance = simd_length(toward)
        guard distance > 0.01 else { return .wall }
        let hit = scene.raycast(origin: eye, direction: toward / distance, length: distance + 0.05,
                                query: .nearest, mask: Self.standable).first
        guard let hit else {
            return FocusLocomotion.canLand(normalY: 1, height: Double(point.y), floor: floor) ? .floor(point) : .offFloor(point)
        }
        guard Double(hit.normal.y) >= FocusLocomotion.levelEnough else { return .wall }
        return FocusLocomotion.canLand(normalY: Double(hit.normal.y), height: Double(hit.position.y), floor: floor)
            ? .floor(hit.position) : .offFloor(hit.position)
    }

    /// The floor's height around the person: the top of the floor forced under every environment.
    private var floorHeight: Float {
        ground.position(relativeTo: nil).y + 0.01
    }

    // MARK: - Moving

    /// Through a moment of dark, as Mirador's curtain: out, move, in. One move at a time.
    fileprivate func move(to next: FocusWorldPose) {
        guard !moving else { return }
        moving = true
        Task {
            await fade(to: 0)
            pose = next
            apply(next)
            await fade(to: 1)
            moving = false
        }
    }

    private func fade(to opacity: Float) async {
        let from = world.components[OpacityComponent.self]?.opacity ?? 1
        let steps = 9
        for step in 1...steps {
            let amount = from + (opacity - from) * Float(step) / Float(steps)
            world.components.set(OpacityComponent(opacity: amount))
            try? await Task.sleep(for: .seconds(FocusLocomotion.fadeSeconds / Double(steps)))
        }
        if opacity >= 1 { world.components.remove(OpacityComponent.self) }
    }

    private func apply(_ pose: FocusWorldPose) {
        world.transform = Transform(scale: .one,
                                    rotation: simd_quatf(angle: Float(pose.yaw), axis: [0, 1, 0]),
                                    translation: [Float(pose.x), Float(pose.y), Float(pose.z)])
    }

    // MARK: - The ring and the target

    /// Looking down, a ring where the head is aimed, on whatever can be stood on there.
    private func followHead() {
        guard walks, press == nil, swing == nil, !moving, let scene = world.scene,
              let aim = head.pose(), Double(aim.forward.y) < FocusLocomotion.lookingDown,
              let hit = scene.raycast(origin: aim.position, direction: aim.forward, length: Float(FocusLocomotion.reach),
                                      query: .nearest, mask: Self.standable).first,
              FocusLocomotion.canLand(normalY: Double(hit.normal.y), height: Double(hit.position.y), floor: Double(floorHeight)) else {
            if ring.isEnabled { ring.isEnabled = false }
            return
        }
        ring.position = hit.position + [0, 0.004, 0]
        ring.isEnabled = true
    }

    fileprivate func showTarget(_ press: Press) {
        target.position = press.spot + [0, 0.006, 0]
        arrow.orientation = simd_quatf(angle: Float(press.yaw), axis: [0, 1, 0])
        targetMaterial.color = .init(tint: (press.cancelled ? Self.cancelColour : Self.targetColour).withAlphaComponent(0.5))
        if var model = target.components[ModelComponent.self] {
            model.materials = [targetMaterial]
            target.components.set(model)
        }
        target.isEnabled = true
    }

    // MARK: - The head and the hand

    private func headPosition() -> SIMD3<Float> {
        head.pose()?.position ?? [0, Float(FocusEnvironmentArt.eyeHeight), 0]
    }

    /// The head's place on the floor and the way it faces, around the person.
    fileprivate func headSpot() -> FocusSpot {
        guard let aim = head.pose() else { return FocusSpot(x: 0, z: 0) }
        return FocusSpot(x: Double(aim.position.x), y: 0, z: Double(aim.position.z),
                         yaw: FocusLocomotion.heading(dx: Double(aim.forward.x), dz: Double(aim.forward.z)))
    }

    /// The heading from the head to a point, for a swing.
    private func heading(to point: SIMD3<Float>) -> Double {
        let eye = headPosition()
        return FocusLocomotion.heading(dx: Double(point.x - eye.x), dz: Double(point.z - eye.z))
    }

    /// The pinching hand, around the person: its own pose where the system gives one (Mirador
    /// followed the fingers, not the pinch's ray: the ray pivots between the eyes), else the pinch.
    private func handPosition(_ value: EntityTargetValue<DragGesture.Value>) -> SIMD3<Float> {
        if let pose = value.inputDevicePose3D {
            return value.convert(pose.position, from: .local, to: .scene)
        }
        return value.convert(value.location3D, from: .local, to: .scene)
    }

    private func handStart(_ value: EntityTargetValue<DragGesture.Value>) -> SIMD3<Float>? {
        value.startInputDevicePose3D.map { value.convert($0.position, from: .local, to: .scene) }
    }

    // MARK: - Pieces

    /// Mirador's ring: 20 to 24 cm, white, a little see-through.
    private static func ringEntity() -> Entity {
        let segments = 48
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            positions.append([0.20 * cos(angle), 0, 0.20 * sin(angle)])
            positions.append([0.24 * cos(angle), 0, 0.24 * sin(angle)])
        }
        for index in 0..<segments {
            let (inner, outer) = (UInt32(index * 2), UInt32(index * 2 + 1))
            let (nextInner, nextOuter) = (UInt32((index + 1) % segments * 2), UInt32((index + 1) % segments * 2 + 1))
            indices += [inner, nextOuter, outer, inner, nextInner, nextOuter]
        }
        var material = UnlitMaterial(color: UIColor(white: 1, alpha: 0.7))
        material.blending = .transparent(opacity: 0.7)
        material.faceCulling = .none
        let entity = ModelEntity(mesh: mesh(positions, indices), materials: [material])
        entity.isEnabled = false
        return entity
    }

    /// Mirador's target: a see-through disc 32 cm across the middle, and an arrow on it pointing the
    /// way the person will face.
    private static func targetEntity() -> (Entity, Entity, UnlitMaterial) {
        let segments = 48
        var positions: [SIMD3<Float>] = [[0, 0, 0]]
        var indices: [UInt32] = []
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            positions.append([0.32 * cos(angle), 0, 0.32 * sin(angle)])
            indices += [0, UInt32(1 + (index + 1) % segments), UInt32(1 + index)]
        }
        var disc = UnlitMaterial(color: targetColour.withAlphaComponent(0.5))
        disc.blending = .transparent(opacity: 0.5)
        disc.faceCulling = .none
        let target = ModelEntity(mesh: mesh(positions, indices), materials: [disc])
        // Pointing down −z: the tip, then the stem.
        let shape: [SIMD3<Float>] = [[0, 0, -0.34], [0.14, 0, -0.08], [-0.14, 0, -0.08],
                                     [0.05, 0, -0.08], [0.05, 0, 0.16], [-0.05, 0, 0.16], [-0.05, 0, -0.08]]
        var white = UnlitMaterial(color: .white)
        white.faceCulling = .none
        let arrow = ModelEntity(mesh: mesh(shape, [0, 1, 2, 3, 4, 5, 3, 5, 6]), materials: [white])
        arrow.position = [0, 0.002, 0]
        target.addChild(arrow)
        target.isEnabled = false
        return (target, arrow, disc)
    }

    /// The floor seen under a room or an object: dark, fading out over 30 m.
    private static func groundLookEntity() -> Entity? {
        let side = 256
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(gray: 0.16, alpha: 0.95), CGColor(gray: 0.12, alpha: 0.6),
                                                 CGColor(gray: 0.1, alpha: 0)] as CFArray,
                                        locations: [0, 0.6, 1]) else { return nil }
        let middle = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                   endRadius: CGFloat(side) / 2, options: [])
        guard let image = context.makeImage(),
              let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        let entity = ModelEntity(mesh: .generatePlane(width: 60, depth: 60), materials: [material])
        // Just under a room's own floor, which stands at 0.
        entity.position = [0, -0.003, 0]
        return entity
    }

    private static func mesh(_ positions: [SIMD3<Float>], _ indices: [UInt32]) -> MeshResource {
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generatePlane(width: 0.01, depth: 0.01)
    }
}

#if DEBUG
extension FocusWalking {
    /// The simulator can't pinch the floor: a teleport toward a point around the person, landing as
    /// a pinch there would (`--demo-teleport x,y,z,heading°`).
    func demoTeleport(toward point: SIMD3<Float>, yaw: Double) {
        guard case .floor(let landing) = landing(at: point) else {
            Self.log.info("demo teleport toward \(point, privacy: .public): not the floor, no landing")
            return
        }
        Self.log.info("demo teleport lands at \(landing, privacy: .public)")
        let spot = pose.inWorld(FocusSpot(x: Double(landing.x), y: Double(landing.y), z: Double(landing.z), yaw: yaw))
        move(to: FocusWorldPose(placing: spot, under: headSpot()))
    }

    /// The target as a pinch shows it (`--demo-walk-target x,y,z,heading°`).
    func demoShowTarget(at point: SIMD3<Float>, yaw: Double, cancelled: Bool = false) {
        switch landing(at: point) {
        case .floor(let landing):
            showTarget(Press(spot: landing, yaw: yaw, handStart: .zero, cancelled: cancelled))
        case .offFloor(let spot):
            showTarget(Press(spot: spot, yaw: yaw, handStart: .zero, cancelled: true, offFloor: true))
        case .wall:
            return
        }
    }
}

/// A room for the simulator, which has no iCloud to bring one (`--demo-environment-room`): 6 × 3 × 6
/// m, a doorway behind the person, a platform 1.2 m up with steps to it, a desk, and a camera by the
/// door looking in. A living room's host parts too (2026-10-27): a `clock_digital` on the far wall,
/// and an orb that shows at `event_left` or `event_right` every few seconds (`Test Room.events/`).
/// Made again at each launch that asks for it, so it carries what the host has learnt since.
@MainActor
enum FocusDemoRoom {
    static let fileName = "Test Room.reality"

    static func make(in folder: URL) async {
        let file = folder.appendingPathComponent(fileName)
        let room = Entity()
        func add(_ mesh: MeshResource, at position: SIMD3<Float>, _ colour: UIColor) {
            let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: colour, roughness: 0.8, isMetallic: false)])
            entity.position = position
            room.addChild(entity)
        }
        let wall = UIColor(white: 0.78, alpha: 1), wood = UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
        add(.generatePlane(width: 6, depth: 6), at: [0, 0, 0], UIColor(red: 0.42, green: 0.3, blue: 0.2, alpha: 1))
        add(.generateBox(size: [6, 3, 0.1]), at: [0, 1.5, -3], wall)
        add(.generateBox(size: [0.1, 3, 6]), at: [-3, 1.5, 0], wall)
        add(.generateBox(size: [0.1, 3, 6]), at: [3, 1.5, 0], UIColor(red: 0.45, green: 0.55, blue: 0.7, alpha: 1))
        add(.generateBox(size: [2.4, 3, 0.1]), at: [-1.8, 1.5, 3], wall)
        add(.generateBox(size: [2.4, 3, 0.1]), at: [1.8, 1.5, 3], wall)
        add(.generateBox(size: [2, 1.2, 2]), at: [1.9, 0.6, -1.9], wood)
        add(.generateBox(size: [0.5, 0.4, 1]), at: [0.65, 0.2, -1.4], wood)
        add(.generateBox(size: [0.5, 0.8, 1]), at: [0.65, 0.4, -2.4], wood)
        add(.generateBox(size: [1.4, 0.05, 0.7]), at: [-1.5, 0.75, -2.2], wood)
        let camera = PerspectiveCamera()
        camera.position = [0, 1.6, 2.4]
        room.addChild(camera)
        let anchors: [(String, SIMD3<Float>)] = [(FocusRoomLife.digitalClockName, [0, 2.1, -2.94]),
                                                 ("event_left", [-1.6, 1.5, -1.2]), ("event_right", [1.6, 1.5, 0.6])]
        for (name, position) in anchors {
            let anchor = Entity()
            anchor.name = name
            anchor.position = position
            room.addChild(anchor)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: file)
            try await room.write(to: file)
            let events = FocusRoomEvents.folder(beside: file)
            try? FileManager.default.removeItem(at: events)
            try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
            var glow = UnlitMaterial(color: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1))
            glow.faceCulling = .none
            try await ModelEntity(mesh: .generateSphere(radius: 0.15), materials: [glow])
                .write(to: events.appendingPathComponent("Orb.reality"))
            try Data(#"{"version": 1, "events": [{"id": "orb", "file": "Orb.reality", "anchors": ["event_left", "event_right"], "every": [3, 6], "seconds": 4}]}"#.utf8)
                .write(to: events.appendingPathComponent("events.json"))
        } catch {
            Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")
                .error("The demo room couldn't be written: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif

#endif
