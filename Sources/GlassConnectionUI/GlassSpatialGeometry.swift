import Foundation
import simd

public enum GlassSpatialPointerPhase: Sendable { case began, moved, ended, cancelled }

/// A cylindrical display in meters. Geometry and inverse input mapping share
/// the same surface definition; remote pixels remain independent of its pose.
public struct GlassSpatialGeometry: Sendable, Equatable {
    public let width: Float
    public let height: Float
    public let curvature: Float
    public let pitch: Float
    public let yaw: Float

    public init(width: Float, height: Float, curvatureDegrees: Double, pitchDegrees: Double, yawDegrees: Double) {
        self.width = width.isFinite ? min(10, max(0.01, width)) : 1
        self.height = height.isFinite ? min(10, max(0.01, height)) : 1
        self.curvature = Float(Self.bounded(curvatureDegrees, in: 0...120)) * .pi / 180
        self.pitch = Float(Self.bounded(pitchDegrees, in: -60...60)) * .pi / 180
        self.yaw = Float(Self.bounded(yawDegrees, in: -60...60)) * .pi / 180
    }

    public static func bounded(_ value: Double, in range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 0
    }

    public var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    public func position(uv: SIMD2<Float>) -> SIMD3<Float> {
        let x = (uv.x - 0.5) * width
        let y = (0.5 - uv.y) * height
        guard curvature > 0.0001 else { return [x, y, 0] }
        let radius = width / curvature
        let theta = (uv.x - 0.5) * curvature
        // The edges come toward the viewer; the center remains at z = 0.
        return [radius * sin(theta), y, radius * (1 - cos(theta))]
    }

    public func coordinates(at position: SIMD3<Float>, clamp: Bool = false) -> SIMD2<Float>? {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        let u: Float
        if curvature > 0.0001 {
            let radius = width / curvature
            u = atan2(position.x, radius - position.z) / curvature + 0.5
        } else { u = position.x / width + 0.5 }
        let v = 0.5 - position.y / height
        if !clamp && (u < -0.0001 || u > 1.0001 || v < -0.0001 || v > 1.0001) { return nil }
        return [min(1, max(0, u)), min(1, max(0, v))]
    }

    public var vertices: [SIMD3<Float>] {
        (0...96).flatMap { i in [position(uv: [Float(i) / 96, 0]), position(uv: [Float(i) / 96, 1])] }
    }
    public var textureCoordinates: [SIMD2<Float>] {
        (0...96).flatMap { i in [[Float(i) / 96, 1], [Float(i) / 96, 0]] }
    }
    public var indices: [UInt32] {
        (0..<96).flatMap { i -> [UInt32] in
            let n = UInt32(i * 2)
            return [n, n + 1, n + 2, n + 2, n + 1, n + 3]
        }
    }

    /// Fit all rotated vertices inside the interactive volume, never merely
    /// request noninteractive clipping margins for parts of the desktop.
    public func placement(in extent: SIMD3<Float>, scale requested: Float = 1) -> (scale: Float, offset: SIMD3<Float>) {
        let transformed = vertices.map { rotation.act($0) }
        var low = transformed[0], high = transformed[0]
        for point in transformed { low = simd_min(low, point); high = simd_max(high, point) }
        let size = simd_max(high - low, SIMD3<Float>(repeating: 0.0001))
        let room = simd_max(extent * 0.94, SIMD3<Float>(repeating: 0.0001))
        let fit = min(room.x / size.x, min(room.y / size.y, room.z / size.z))
        let scale = min(max(0.1, requested.isFinite ? requested : 1), fit)
        return (scale, -(low + high) * 0.5 * scale)
    }
}
