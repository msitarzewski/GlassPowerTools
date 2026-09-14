import Testing
import simd
@testable import GlassConnectionUI

struct GlassSpatialGeometryTests {
    @Test func flatDisplayPreservesPixelCoordinates() throws {
        let shape = GlassSpatialGeometry(width: 1.4, height: 0.9, curvatureDegrees: 0, pitchDegrees: 0, yawDegrees: 0)
        #expect(shape.position(uv: [0, 0]) == [-0.7, 0.45, 0])
        #expect(shape.position(uv: [1, 1]) == [0.7, -0.45, 0])
        #expect(shape.coordinates(at: [0, 0, 0]) == [0.5, 0.5])
    }
    @Test func curvedSurfaceBringsEdgesForwardWithoutMovingCenter() {
        let shape = GlassSpatialGeometry(width: 1.4, height: 0.9, curvatureDegrees: 90, pitchDegrees: 0, yawDegrees: 0)
        #expect(shape.position(uv: [0.5, 0.5]) == .zero)
        #expect(shape.position(uv: [0, 0.5]).z > 0.25)
        #expect(abs(shape.position(uv: [0, 0.5]).z - shape.position(uv: [1, 0.5]).z) < 0.00001)
    }
    @Test func inverseMappingMatchesSurfaceAtEveryCurve() throws {
        for curve in [0.0, 0.001, 30, 60, 90, 120] {
            let shape = GlassSpatialGeometry(width: 1.4, height: 0.9, curvatureDegrees: curve, pitchDegrees: 35, yawDegrees: -20)
            for x in 0...20 { for y in 0...10 {
                let uv = SIMD2<Float>(Float(x) / 20, Float(y) / 10)
                let world = shape.rotation.act(shape.position(uv: uv))
                let local = shape.rotation.inverse.act(world)
                let result = try #require(shape.coordinates(at: local))
                #expect(simd_distance(result, uv) < 0.0001)
            } }
        }
    }
    @Test func entireMonitorFitsInteractiveVolumeAtExtremeAngles() {
        let bounds = SIMD3<Float>(1.4, 0.9, 0.6)
        for curve in [0.0, 60, 120] { for tilt in [-60.0, 0, 60] { for angle in [-60.0, 0, 60] {
            let shape = GlassSpatialGeometry(width: 1.4, height: 0.9, curvatureDegrees: curve, pitchDegrees: tilt, yawDegrees: angle)
            let placement = shape.placement(in: bounds, scale: 2)
            for vertex in shape.vertices {
                let p = shape.rotation.act(vertex) * placement.scale + placement.offset
                #expect(abs(p.x) <= bounds.x / 2 && abs(p.y) <= bounds.y / 2 && abs(p.z) <= bounds.z / 2)
            }
        } } }
    }
    @Test func malformedPreferencesStayFiniteAndBounded() {
        let shape = GlassSpatialGeometry(width: .nan, height: -.infinity, curvatureDegrees: 1e20, pitchDegrees: .nan, yawDegrees: -.infinity)
        #expect(shape.width == 1 && shape.height == 1)
        #expect(shape.pitch == 0 && shape.yaw == 0)
        #expect(abs(shape.curvature - 2 * .pi / 3) < 0.0001)
        #expect(shape.coordinates(at: [.nan, 0, 0]) == nil)
        #expect(shape.coordinates(at: [0, 100, 0]) == nil)
        #expect(shape.coordinates(at: [0, 100, 0], clamp: true)?.y == 0)
    }
    @Test func meshWindingFacesViewerAndIndicesStayInBounds() {
        let shape = GlassSpatialGeometry(width: 1.4, height: 0.9, curvatureDegrees: 120, pitchDegrees: 0, yawDegrees: 0)
        let vertices = shape.vertices
        #expect(vertices.count == shape.textureCoordinates.count)
        for triangle in stride(from: 0, to: shape.indices.count, by: 3) {
            let indices = Array(shape.indices[triangle..<triangle + 3]).map(Int.init)
            #expect(indices.allSatisfy { vertices.indices.contains($0) })
            let normal = simd_cross(vertices[indices[1]] - vertices[indices[0]], vertices[indices[2]] - vertices[indices[0]])
            #expect(normal.z > 0)
        }
    }
}
