//
//  FocusEnvironmentView.swift
//  Glass Power Tools — GlassTerminal
//
//  Focus Mode's immersive space on Vision Pro: the room dimmed, as it always was, and around the
//  person the environment their window chose (`FocusEnvironments.swift`) — a built-in, a 360° photo
//  or a 3D room, fitted as the person fitted it (`FocusRoomFit`). The Digital Crown still dials it
//  in. Changing the environment while it is open changes it in place; one that can't be shown says
//  why, in front of the person. Inside one with a floor, the person moves about by pinching it
//  (`FocusEnvironmentWalking.swift`).
//

import SwiftUI
import OSLog

#if os(visionOS)
import RealityKit
import ImageIO
import Metal
import UniformTypeIdentifiers

/// What Focus Mode shows, set by the window that opens it, or changes it while it is open. One
/// space is open at a time, so one stage.
@Observable
final class FocusEnvironmentStage {
    static let shared = FocusEnvironmentStage()
    var environmentID = FocusEnvironment.defaultID
    /// What's being fetched or made, or why it couldn't be shown: on the window that opened Focus
    /// Mode, where it is seen (placed in the space, it stood behind the window).
    var note: String?
    /// The 3D environment being tried out and fitted from Settings (`FocusEnvironmentFitView`), which
    /// opens all the way round.
    var tryingOut: String?
    /// The room on show's fit: read from beside its file, changed as it is tried out.
    var fit = FocusRoomFit()
    /// What the room on show says of itself, once it has loaded; nil for anything else.
    var room: RoomFacts?
    var isOpen = false
    /// The open space's walking, for Try Out's Start Here and Fine Position.
    @ObservationIgnored weak var walking: FocusWalking?
    /// Counts the person's moves, so Fine Position reads again how far they are from their start.
    var moves = 0

    struct RoomFacts: Equatable {
        /// The file's own `metersPerUnit`.
        var fileMetresPerUnit: Double
        /// Its size, metres, as the file says.
        var size: SIMD3<Double>
        /// Whether the file has a camera of its own to start at.
        var hasCamera: Bool
    }

    /// How Focus Mode opens: partway, as it always did, or all the way round (Open Immersed). Only
    /// the top of the range and the start are set, so the Digital Crown keeps the system's own
    /// lowest amount (undocumented; developers report it near half).
    static func immersion(opensImmersed: Bool) -> ProgressiveImmersionStyle {
        opensImmersed ? .progressive(...1.0, initialAmount: 1.0) : .progressive
    }
}

struct FocusEnvironmentView: View {
    private let stage = FocusEnvironmentStage.shared
    private let library = FocusEnvironmentLibrary.shared
    /// The space's origin, on the floor where the person stood as it opened.
    @State private var root = Entity()
    /// The world the environment is in, which moves as the person does, and what moves it.
    @State private var walking = FocusWalking()
    @Environment(SettingsManager.self) private var settings

    private static let log = Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")

    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            walking.install(in: root, content: content)
            walking.digitalClock = attachments.entity(for: FocusRoomDigitalClockView.attachmentID)
        } update: { _, _ in
        } attachments: {
            // Placed by a room that has a `clock_digital` (`FocusRoomLife`).
            Attachment(id: FocusRoomDigitalClockView.attachmentID) { FocusRoomDigitalClockView() }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .onChanged { walking.changed($0) }
            .onEnded { walking.ended($0) })
        .preferredSurroundingsEffect(.systemDark)
        .task(id: stage.environmentID) { await show(stage.environmentID) }
        .task { await walking.trackHead() }
        .onChange(of: stage.fit) { _, fit in walking.place(fit) }
        .onChange(of: settings.focusEnvironmentSound, initial: true) { _, level in walking.soundLevel = level }
        .onAppear {
            library.start()
            stage.isOpen = true
            stage.walking = walking
            walking.moved = { [stage] in stage.moves &+= 1 }
        }
        .onDisappear {
            stage.note = nil
            stage.isOpen = false
            stage.room = nil
            stage.walking = nil
            walking.stopTrackingHead()
            walking.endLife()
        }
    }

    private func show(_ id: String) async {
        stage.note = nil
        let environment: FocusEnvironment
        /// What stays said once it is shown.
        var lasting: String?
        if library.environment(withID: id) == nil, FocusEnvironmentFiles.fileName(fromID: id) != nil {
            // Focus Mode opened as the app starts: the library may not have listed its files yet.
            await library.ready()
        }
        if let found = library.environment(withID: id) {
            environment = found
        } else {
            environment = FocusEnvironment(builtIn: .dimmed)
            if id != FocusEnvironment.defaultID {
                lasting = "“\(library.name(ofID: id))” isn't in your environments on this Vision Pro, so the room is dimmed instead."
            }
        }
        do {
            if !environment.isDownloaded {
                stage.note = "Downloading “\(environment.name)” from iCloud…"
                library.download(environment)
                try await waitForDownload(environment)
            }
            if case .builtIn(let builtIn) = environment.kind, builtIn != .dimmed {
                stage.note = "Making \(builtIn.title)…"
            } else if case .room = environment.kind {
                stage.note = "Opening “\(environment.name)”…"
            }
            if case .room = environment.kind, let file = environment.file {
                let loaded = try await FocusEnvironmentScenes.room(file)
                let fit = await library.fit(for: environment) ?? FocusRoomFit()
                try Task.checkCancellation()
                stage.room = .init(fileMetresPerUnit: loaded.fileMetresPerUnit, size: SIMD3<Double>(loaded.max - loaded.min),
                                   hasCamera: loaded.camera != nil)
                stage.fit = fit
                walking.show(nil, room: loaded, fit: fit, walks: true)
                stage.note = lasting
                let scale = Float(fit.scale(fileMetresPerUnit: loaded.fileMetresPerUnit))
                if stage.tryingOut != environment.id,
                   let objectNote = FocusRoomPlacement.objectNote(name: environment.name, min: loaded.min * scale, max: loaded.max * scale) {
                    stage.note = objectNote
                    try await Task.sleep(for: .seconds(10))
                    stage.note = nil
                }
            } else {
                let scene = try await FocusEnvironmentScenes.scene(for: environment)
                try Task.checkCancellation()
                stage.room = nil
                stage.fit = FocusRoomFit()
                var walks = scene != nil
                if case .photo = environment.kind { walks = false }
                walking.show(scene, room: nil, fit: FocusRoomFit(), walks: walks)
                stage.note = lasting
            }
        } catch is CancellationError {
            return
        } catch {
            Self.log.error("Focus environment \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            stage.room = nil
            walking.show(nil, room: nil, fit: FocusRoomFit(), walks: false)
            stage.note = FocusEnvironmentScenes.message(for: error, name: environment.name)
        }
    }

    /// Until iCloud has brought the file; given up only when the environment changes or Focus Mode ends.
    private func waitForDownload(_ environment: FocusEnvironment) async throws {
        while true {
            try await Task.sleep(for: .milliseconds(500))
            library.refresh()
            if library.environment(withID: environment.id)?.isDownloaded == true { return }
        }
    }
}

/// The environments as RealityKit content: each a sky around the person, a floor under them, or a
/// room placed with its floor at their feet. The space's origin is on the floor beneath the person.
enum FocusEnvironmentScenes {
    enum Problem: Error {
        case unreadablePicture
        case notA360Photo(width: Int, height: Int)
    }

    /// How far the sky stands: far enough that walking about doesn't move it.
    static let skyRadius: Float = 900

    /// Turns the sphere so its picture's middle is ahead of the person: RealityKit's sphere puts it on
    /// their right (measured in the simulator, 2026-10-26, with a picture marked ahead, left, right
    /// and above: a quarter turn put each where it belongs, and not mirrored).
    static var skyTurn: Float {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--demo-sky-turn"), arguments.indices.contains(index + 1),
           let degrees = Float(arguments[index + 1]) {
            return degrees * .pi / 180
        }
        #endif
        return .pi / 2
    }

    static func scene(for environment: FocusEnvironment) async throws -> Entity? {
        switch environment.kind {
        case .builtIn(let builtIn):
            return try await builtInScene(builtIn)
        case .photo:
            guard let file = environment.file else { return nil }
            let image = try await Task.detached(priority: .userInitiated) { try photo(file) }.value
            return try await sky(image)
        case .room:
            // Placed with its fit by `FocusWalking`, from `room(_:)`.
            return nil
        }
    }

    static func message(for error: Error, name: String) -> String {
        switch error {
        case Problem.notA360Photo(let width, let height):
            "“\(name)” isn't a 360° photo: it's \(width) × \(height), and a 360° photo is twice as wide as it is tall."
        case Problem.unreadablePicture:
            "“\(name)” couldn't be read as a picture. Add it again from Settings ▸ Terminal ▸ Focus Mode."
        default:
            "“\(name)” couldn't be shown. If it's a 3D room, export it again as USDZ and add it again."
        }
    }

    // MARK: - Built-ins

    private static func builtInScene(_ builtIn: FocusBuiltInEnvironment) async throws -> Entity? {
        guard builtIn != .dimmed else { return nil }
        let images = try await Task.detached(priority: .userInitiated) { () throws -> (CGImage, CGImage?, CGImage?) in
            guard let sky = cachedSky(builtIn) else { throw Problem.unreadablePicture }
            return (sky, builtIn == .grid ? nil : FocusEnvironmentArt.floor(builtIn),
                    builtIn == .grid ? FocusEnvironmentArt.gridTile() : nil)
        }.value
        let scene = Entity()
        scene.addChild(try await sky(images.0))
        if let floor = images.1 {
            scene.addChild(try await plane(floor, halfWidth: FocusEnvironmentArt.floorHalfWidth, repeats: 1))
        }
        if let tile = images.2 {
            let half = FocusEnvironmentArt.gridHalfWidth
            scene.addChild(try await plane(tile, halfWidth: half, repeats: half * 2 / FocusEnvironmentArt.gridSpacing))
        }
        return scene
    }

    /// A built-in's sky, drawn once per device and kept in Caches after.
    nonisolated private static func cachedSky(_ builtIn: FocusBuiltInEnvironment) -> CGImage? {
        let width = FocusEnvironmentArt.skyWidth
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.glasspowertools/Focus Environments", isDirectory: true)
        // The version changes when a sky's drawing does, so an old picture isn't kept.
        let file = folder?.appendingPathComponent("\(builtIn.rawValue)-2-\(width).png")
        if let file, let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        guard let image = FocusEnvironmentArt.sky(builtIn, width: width) else { return nil }
        if let folder, let file {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
        }
        return image
    }

    // MARK: - Pieces

    /// A picture wrapped around the person, its middle ahead of them.
    private static func sky(_ image: CGImage) async throws -> Entity {
        let texture = try await TextureResource(image: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.faceCulling = .none
        let sphere = ModelEntity(mesh: .generateSphere(radius: skyRadius), materials: [material])
        // Seen from inside: turned inside out, so the picture isn't mirrored.
        sphere.scale = [-1, 1, 1]
        sphere.orientation = simd_quatf(angle: skyTurn, axis: [0, 1, 0])
        sphere.position = [0, Float(FocusEnvironmentArt.eyeHeight), 0]
        return sphere
    }

    /// A floor `halfWidth` metres from the person to each edge, its picture repeated `repeats` times
    /// across.
    private static func plane(_ image: CGImage, halfWidth: Float, repeats: Float) async throws -> Entity {
        let texture = try await TextureResource(image: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        var mesh = MeshDescriptor(name: "floor")
        mesh.positions = MeshBuffers.Positions([[-halfWidth, 0, -halfWidth], [halfWidth, 0, -halfWidth],
                                                [halfWidth, 0, halfWidth], [-halfWidth, 0, halfWidth]])
        mesh.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: 4))
        mesh.textureCoordinates = MeshBuffers.TextureCoordinates([[0, repeats], [repeats, repeats], [repeats, 0], [0, 0]])
        mesh.primitives = .triangles([0, 3, 2, 0, 2, 1])
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        sampler.maxAnisotropy = 16
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture, sampler: .init(sampler)))
        material.faceCulling = .none
        return ModelEntity(mesh: try MeshResource.generate(from: [mesh]), materials: [material])
    }

    /// A 360° photo, no wider than a texture can be.
    nonisolated private static func photo(_ file: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Problem.unreadablePicture }
        guard FocusEnvironmentFiles.isEquirectangular(width: width, height: height) else {
            throw Problem.notA360Photo(width: width, height: height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(width, 8192),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Problem.unreadablePicture
        }
        return image
    }

    /// A 3D file as it came: its bounds, its units, its own camera, and the sounds beside it.
    struct LoadedRoom {
        let model: Entity
        /// The file it came from; nil for a room made in code.
        var file: URL? = nil
        /// Its `<Room>.sounds` folder's list, when it has one on this device (`FocusRoomSounds`).
        var sounds: FocusRoomSounds? = nil
        /// Its `<Room>.events` folder's list, likewise (`FocusRoomEvents`).
        var events: FocusRoomEvents? = nil
        /// Metres, the file's units applied, in its own coordinates.
        let min: SIMD3<Float>
        let max: SIMD3<Float>
        let fileMetresPerUnit: Double
        /// Where its camera stands, as a place to start, in its own coordinates.
        let camera: FocusSpot?
    }

    /// A 3D file, loaded. RealityKit applies its `metersPerUnit` as the scale of the entity it
    /// returns, and stands a Z-up file upright itself (measured on the Mac, 2026-10-26: Apple's iMac
    /// model, in centimetres, came back at 0.01; a Z-up box, turned upright), and brings a USD
    /// camera in as a `PerspectiveCamera` at its own place.
    static func room(_ file: URL) async throws -> LoadedRoom {
        let model = try await Entity(contentsOf: file)
        let bounds = model.visualBounds(relativeTo: nil)
        let unit = Double(model.scale.x)
        // Read off the main thread, as iCloud may fetch it.
        let (sounds, events) = await Task.detached(priority: .userInitiated) {
            (FocusRoomSounds.read(beside: file), FocusRoomEvents.read(beside: file))
        }.value
        return LoadedRoom(model: model, file: file, sounds: sounds, events: events, min: bounds.min, max: bounds.max,
                          fileMetresPerUnit: unit.isFinite && unit > 0 ? unit : 1,
                          camera: camera(in: model, floor: bounds.min.y))
    }

    /// The first camera in a file, as a place to stand: under it, at about eye height, never below
    /// the model, facing as it faces.
    private static func camera(in model: Entity, floor: Float) -> FocusSpot? {
        var queue = [model]
        while !queue.isEmpty {
            let entity = queue.removeFirst()
            if entity is PerspectiveCamera {
                let place = entity.position(relativeTo: nil)
                let forward = entity.orientation(relativeTo: nil).act([0, 0, -1])
                return FocusSpot(x: Double(place.x), y: Double(Swift.max(floor, place.y - Float(FocusEnvironmentArt.eyeHeight))),
                                 z: Double(place.z), yaw: FocusLocomotion.heading(dx: Double(forward.x), dz: Double(forward.z)))
            }
            queue += entity.children
        }
        return nil
    }
}
#endif
