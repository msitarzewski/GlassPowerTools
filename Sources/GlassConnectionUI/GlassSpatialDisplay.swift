#if os(visionOS)
import SwiftUI
import RealityKit

/// Protocol-neutral textured curved display, reusable by Glass consumers.
public struct GlassSpatialDisplay: View {
    public typealias PointerPhase = GlassSpatialPointerPhase
    private let texture: TextureResource?
    private let aspectRatio: Float
    private let curvature: Double
    private let pitch: Double
    private let yaw: Double
    private let scale: Double
    private let pointer: (@MainActor (PointerPhase, SIMD2<Float>) -> Void)
    private let onError: (@MainActor (String) -> Void)
    @State private var state = SpatialDisplayState()
    @State private var dragging = false

    public init(texture: TextureResource?, aspectRatio: Float, curvature: Double, pitch: Double, yaw: Double,
                scale: Double = 1, pointer: @escaping @MainActor (PointerPhase, SIMD2<Float>) -> Void,
                onError: @escaping @MainActor (String) -> Void) {
        self.texture = texture; self.aspectRatio = aspectRatio; self.curvature = curvature
        self.pitch = pitch; self.yaw = yaw; self.scale = scale; self.pointer = pointer; self.onError = onError
    }

    public var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                content.add(state.root)
            } update: { content in
                let bounds = content.convert(geometry.frame(in: .local), from: .local, to: .scene)
                state.update(texture: texture, aspect: aspectRatio, curvature: curvature, pitch: pitch, yaw: yaw,
                             scale: scale, bounds: bounds, onError: onError)
            }
            .gesture(DragGesture(minimumDistance: 0).targetedToEntity(state.screen)
                .onChanged { value in
                    let point = value.convert(value.location3D, from: .local, to: state.screen)
                    guard let uv = state.geometry?.coordinates(at: point, clamp: dragging) else { return }
                    pointer(dragging ? .moved : .began, uv)
                    dragging = true
                }
                .onEnded { value in
                    let point = value.convert(value.location3D, from: .local, to: state.screen)
                    let uv = state.geometry?.coordinates(at: point, clamp: true) ?? SIMD2<Float>(repeating: 0.5)
                    pointer(.ended, uv); dragging = false
                })
            .onDisappear {
                if dragging { pointer(.cancelled, .zero); dragging = false }
                state.stop()
            }
            .accessibilityLabel("Remote desktop")
        }
    }
}

@MainActor private final class SpatialDisplayState {
    let root = Entity()
    let screen = ModelEntity()
    var geometry: GlassSpatialGeometry?
    private var texture: TextureResource?
    private var meshTask: Task<Void, Never>?
    private var revision = UUID()

    init() {
        screen.name = "Glass Curved Display"
        screen.components.set(InputTargetComponent())
        root.addChild(screen)
    }
    func update(texture: TextureResource?, aspect: Float, curvature: Double, pitch: Double, yaw: Double,
                scale: Double, bounds: BoundingBox, onError: @escaping @MainActor (String) -> Void) {
        guard let texture else { screen.isEnabled = false; return }
        screen.isEnabled = true
        let width = bounds.extents.x
        guard width > 0, bounds.extents.y > 0, bounds.extents.z > 0 else { return }
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 16 / 9
        let next = GlassSpatialGeometry(width: width, height: width / ratio,
                                       curvatureDegrees: curvature, pitchDegrees: pitch, yawDegrees: yaw)
        let placement = next.placement(in: bounds.extents, scale: Float(scale))
        root.position = bounds.center + placement.offset
        root.scale = SIMD3<Float>(repeating: placement.scale)
        root.orientation = next.rotation
        if self.texture !== texture {
            self.texture = texture
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            material.faceCulling = .none
            if var model = screen.model { model.materials = [material]; screen.model = model }
        }
        let rebuild = geometry?.width != next.width || geometry?.height != next.height || geometry?.curvature != next.curvature
        geometry = next
        guard rebuild else { return }
        screen.components.remove(InputTargetComponent.self)
        meshTask?.cancel()
        let token = UUID(); revision = token
        meshTask = Task {
            do {
                var descriptor = MeshDescriptor(name: "Glass Curved Display")
                descriptor.positions = MeshBuffers.Positions(next.vertices)
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(next.textureCoordinates)
                descriptor.primitives = .triangles(next.indices)
                let mesh = try MeshResource.generate(from: [descriptor])
                let shape = try await ShapeResource.generateStaticMesh(from: mesh)
                guard !Task.isCancelled, revision == token, let currentTexture = self.texture else { return }
                var material = UnlitMaterial(applyPostProcessToneMap: false)
                material.color = .init(tint: .white, texture: .init(currentTexture))
                material.blending = .transparent(opacity: .init(floatLiteral: 1))
                material.faceCulling = .none
                screen.model = ModelComponent(mesh: mesh, materials: [material])
                screen.components.set(CollisionComponent(shapes: [shape], mode: .trigger))
                screen.components.set(InputTargetComponent())
            } catch {
                guard !Task.isCancelled, revision == token else { return }
                screen.isEnabled = false
                geometry = nil
                onError(error.localizedDescription)
            }
        }
    }
    func stop() { revision = UUID(); meshTask?.cancel(); meshTask = nil; geometry = nil }
}
#endif
