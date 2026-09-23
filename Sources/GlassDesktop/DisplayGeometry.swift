import Foundation
import CoreGraphics
import RDPKit

public struct DesktopSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public static let maximumPixels = 16_777_216
    public static let standard = DesktopSize(width: 1920, height: 1080)

    public init(width: Int, height: Int) { self.width = width; self.height = height }

    public func validate() throws {
        guard (200...8192).contains(width), (200...8192).contains(height), width.isMultiple(of: 2),
              width <= Self.maximumPixels / height else { throw DesktopError.invalidDesktop }
    }

    /// Normalizes requested source geometry independently of the local view's spatial pose.
    public static func fitting(width: Double, height: Double, scale: Double = 1) -> Self {
        guard width.isFinite, height.isFinite, scale.isFinite, scale > 0 else { return .standard }
        var w = min(8192.0, max(200.0, width * min(scale, 4)))
        var h = min(8192.0, max(200.0, height * min(scale, 4)))
        let ratio = sqrt(min(1, Double(maximumPixels) / (w * h)))
        w = max(200, floor(w * ratio / 2) * 2)
        h = max(200, floor(h * ratio))
        return Self(width: Int(w), height: Int(h))
    }
}

public struct DesktopPoint: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public enum DesktopCoordinates {
    /// `origin` is the top-left of the visible region inside the remote framebuffer. It is the zero
    /// point unless a single display is being shown out of a larger multi-display framebuffer.
    public static func map(x: Double, y: Double, viewWidth: Double, viewHeight: Double,
                           desktop: DesktopSize, origin: DesktopPoint = .init(x: 0, y: 0),
                           clamp: Bool = false) -> DesktopPoint? {
        guard [x, y, viewWidth, viewHeight].allSatisfy(\.isFinite), viewWidth > 0, viewHeight > 0,
              desktop.width > 0, desktop.height > 0 else { return nil }
        let viewport = RDPRemoteDisplayViewport(
            remotePixelSize: CGSize(width: desktop.width, height: desktop.height),
            bounds: CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight), coordinateOrigin: .topLeft)
        var point = CGPoint(x: x, y: y)
        if clamp {
            let content = viewport.contentRect
            point.x = min(content.maxX.nextDown, max(content.minX, point.x))
            point.y = min(content.maxY.nextDown, max(content.minY, point.y))
        }
        guard let result = viewport.remotePoint(from: point) else { return nil }
        return .init(x: origin.x + min(desktop.width - 1, Int(result.x)),
                     y: origin.y + min(desktop.height - 1, Int(result.y)))
    }
}

/// How a touch screen drives the remote pointer.
public enum DesktopPointerMode: String, Codable, CaseIterable, Sendable {
    /// A finger moves the cursor relative to where it is, and a tap clicks there. Suits a phone,
    /// where a fingertip hides the target and is far larger than most controls.
    case trackpad
    /// A touch presses the button wherever the finger lands. Suits a large screen or a stylus.
    case directTouch

    public var title: String { self == .trackpad ? "Trackpad" : "Direct Touch" }

    /// A phone is too small for a fingertip to be an honest pointer; a tablet is not.
    public static func standard(forCompactScreen compact: Bool) -> DesktopPointerMode {
        compact ? .trackpad : .directTouch
    }
}

/// Local zoom bounds. The image is already fitted to the window, so 100% is the smallest useful
/// size: below it the desktop would simply pull away from the window's tallest or widest edge and
/// leave empty space. Zooming in from there is what the control is for.
public enum DesktopZoomLimits {
    public static let minimum = 1.0
    public static let maximum = 2.0
}

/// How many remote pixels to ask for per point of this window, so a high-resolution display can be
/// given a matching desktop instead of a stretched one.
///
/// This is an RDP capability. The monitor layout carries the size together with a desktop scale
/// factor, so the server renders more pixels while keeping the same layout and physical text size
/// (MS-RDPEDISP 2.2.2.2.1). VNC has no equivalent: the host decides its own resolution.
public enum DesktopSourceScale: String, Codable, CaseIterable, Sendable {
    case automatic, standard, oneAndAHalf, double

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .standard: "100%"
        case .oneAndAHalf: "150%"
        case .double: "200%"
        }
    }

    /// Remote pixels per local point. Automatic follows this display, capped at the range the
    /// display control channel accepts.
    public func factor(displayScale: Double) -> Double {
        let value: Double = switch self {
        case .automatic: displayScale.isFinite ? displayScale : 1
        case .standard: 1
        case .oneAndAHalf: 1.5
        case .double: 2
        }
        return min(5, max(1, value))
    }

    /// The desktop scale factor to send alongside the size. MS-RDPEDISP accepts 100 through 500.
    public func desktopScaleFactor(displayScale: Double) -> Int {
        min(500, max(100, Int((factor(displayScale: displayScale) * 100).rounded())))
    }
}

/// The window a new desktop session opens in, on a Mac.
///
/// macOS gives a new window in a group the frame the last one had, and a desktop window that was
/// once a thumbnail stays one for every desktop after it (2026-09-22: *"opens in essentially a
/// thumbnail"* — 640 × 400 remote pixels for a 320-point window). So a window found at the floor
/// is given the configured desktop, one point per pixel, no larger than the screen it is on.
public enum DesktopWindowSizing {
    /// The smallest content a desktop window can be, in points. Below it the toolbar collapses
    /// into a chevron and the desktop is a postage stamp; nobody wants a session there.
    public static let floor = CGSize(width: 640, height: 400)

    /// The configured desktop at one point per pixel, held inside `available` and never below the
    /// floor. The floor wins over a screen smaller than it: the window cannot be smaller anyway.
    public static func contentSize(desktop: DesktopSize, available: CGSize, floor: CGSize = floor) -> CGSize {
        guard available.width.isFinite, available.height.isFinite else { return floor }
        return CGSize(width: max(floor.width, min(Double(desktop.width), available.width)),
                      height: max(floor.height, min(Double(desktop.height), available.height)))
    }

    /// Whether a window this size is the thumbnail case: at (or under) the floor on either side.
    public static func isAtFloor(_ content: CGSize, floor: CGSize = floor) -> Bool {
        content.width <= floor.width + 1 || content.height <= floor.height + 1
    }
}

/// The part of the remote framebuffer currently on screen. The whole framebuffer unless one display
/// has been selected out of a multi-display host.
public struct DesktopRegion: Equatable, Sendable {
    public let origin: DesktopPoint
    public let size: DesktopSize
    public init(origin: DesktopPoint, size: DesktopSize) { self.origin = origin; self.size = size }

    public static func whole(width: Int, height: Int) -> DesktopRegion {
        .init(origin: .init(x: 0, y: 0), size: DesktopSize(width: width, height: height))
    }

    /// Normalized texture coordinates for the region inside a framebuffer of the given size.
    public func normalized(inWidth width: Int, height: Int) -> (originX: Double, originY: Double, extentX: Double, extentY: Double)? {
        guard width > 0, height > 0, size.width > 0, size.height > 0,
              origin.x >= 0, origin.y >= 0,
              origin.x + size.width <= width, origin.y + size.height <= height else { return nil }
        return (Double(origin.x) / Double(width), Double(origin.y) / Double(height),
                Double(size.width) / Double(width), Double(size.height) / Double(height))
    }
}

public enum TransparencyMode: String, Codable, CaseIterable, Sendable {
    case original, removeBlack, removeWallpaper, removeColor
    public var title: String {
        switch self { case .original: "Original"; case .removeBlack: "Remove Black"; case .removeWallpaper: "Remove Wallpaper"; case .removeColor: "Remove Background Color" }
    }
}

public struct PresentationSettings: Equatable, Sendable {
    public var mode: TransparencyMode = .original
    /// Presentation-only coverage of the remote image, independent of masking and frost.
    public var opacity: Double = 1 {
        didSet { opacity = opacity.isFinite ? min(1, max(0, opacity)) : 1 }
    }
    public var threshold: Float = 0.04
    public var feather: Float = 0.02
    public var keyColor: SIMD3<Float> = [1, 0, 1] {
        didSet { keyColor = Self.normalizedKeyColor(keyColor) }
    }
    public var pitch: Double = 0
    public var yaw: Double = 0
    public var zoom: Double = 1
    /// Local pan of the zoomed image, in points, applied after `zoom`. Zero re-centres it.
    public var panX: Double = 0
    public var panY: Double = 0

    /// Keeps the panned image overlapping the window instead of being dragged out of sight.
    public static func clampedPan(x: Double, y: Double, zoom: Double, viewport: CGSize) -> (x: Double, y: Double) {
        guard zoom.isFinite, viewport.width.isFinite, viewport.height.isFinite else { return (0, 0) }
        let overflowX = max(0, viewport.width * (zoom - 1) / 2)
        let overflowY = max(0, viewport.height * (zoom - 1) / 2)
        let clamp: (Double, Double) -> Double = { value, limit in
            value.isFinite ? min(limit, max(-limit, value)) : 0
        }
        return (clamp(x, overflowX), clamp(y, overflowY))
    }
    public init() {}

    public static func alpha(red: Float, green: Float, blue: Float, reference: SIMD3<Float>?,
                             mode: TransparencyMode, threshold: Float, feather: Float,
                             keyColor: SIMD3<Float> = [1, 0, 1]) -> Float {
        guard mode != .original else { return 1 }
        guard red.isFinite, green.isFinite, blue.isFinite else { return 1 }
        let rgb = SIMD3(min(1, max(0, red)), min(1, max(0, green)), min(1, max(0, blue)))
        let distance: Float
        switch mode {
        case .original: return 1
        case .removeBlack: distance = max(rgb.x, rgb.y, rgb.z)
        case .removeColor:
            let key = normalizedKeyColor(keyColor)
            distance = max(abs(rgb.x - key.x), abs(rgb.y - key.y), abs(rgb.z - key.z))
        case .removeWallpaper:
            guard let reference, reference.x.isFinite, reference.y.isFinite, reference.z.isFinite else { return 1 }
            distance = max(abs(rgb.x - min(1, max(0, reference.x))),
                           abs(rgb.y - min(1, max(0, reference.y))),
                           abs(rgb.z - min(1, max(0, reference.z))))
        }
        let threshold = threshold.isFinite ? min(1, max(0, threshold)) : 0.04
        let feather = feather.isFinite ? min(1, max(0.0001, feather)) : 0.02
        let t = min(1, max(0, (distance - threshold) / feather))
        return t * t * (3 - 2 * t)
    }

    private static func normalizedKeyColor(_ color: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(color.x.isFinite ? min(1, max(0, color.x)) : 1,
              color.y.isFinite ? min(1, max(0, color.y)) : 0,
              color.z.isFinite ? min(1, max(0, color.z)) : 1)
    }
}
