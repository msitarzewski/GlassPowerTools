import CoreGraphics
import Foundation

/// Which button a touch gesture is asking for. Mapped to the transport's button type at the call site.
enum TrackpadButton: Equatable { case left, right }

/// What a touch gesture asks the remote pointer to do.
enum TrackpadAction: Equatable {
    case move(DesktopPoint)
    case press(TrackpadButton)
    case release(TrackpadButton)
}

/// Relative pointing for touch screens, the way a trackpad works: a finger moves the remote cursor
/// rather than jumping it to wherever the finger landed. That matters on a phone, where a fingertip
/// covers the thing being aimed at and is far larger than most controls.
///
/// A quick tap clicks wherever the cursor already is. Touching again straight after a tap and moving
/// drags, which is the usual trackpad tap-drag. All timing is supplied by the caller so the rules can
/// be tested without a running clock.
struct TrackpadPointerController {
    /// A touch shorter than this, that barely moved, is a click rather than a drag.
    static let tapDuration: TimeInterval = 0.3
    static let tapMovement: Double = 12
    /// A touch starting this soon after a tap begins a drag instead of a new click.
    static let dragChainDelay: TimeInterval = 0.35
    /// Fast movement is amplified so the cursor can cross the desktop without several swipes.
    static let accelerationThreshold: Double = 900
    static let maximumAcceleration: Double = 2.5

    private(set) var position: DesktopPoint
    private var region: DesktopRegion
    private var viewSize: CGSize
    private var touchStart: (location: CGPoint, time: TimeInterval)?
    private var lastLocation: CGPoint?
    private var lastMoveTime: TimeInterval?
    private var movedFar = false
    private var lastTapEnded: TimeInterval?
    private(set) var isDragging = false

    init(region: DesktopRegion, viewSize: CGSize, position: DesktopPoint? = nil) {
        self.region = region
        self.viewSize = viewSize
        self.position = position ?? DesktopPoint(x: region.origin.x + region.size.width / 2,
                                                 y: region.origin.y + region.size.height / 2)
    }

    /// Keeps the cursor inside the display being shown when the window or selected display changes.
    mutating func update(region: DesktopRegion, viewSize: CGSize) {
        self.region = region
        self.viewSize = viewSize
        position = clamped(position)
    }

    mutating func began(at location: CGPoint, time: TimeInterval) -> [TrackpadAction] {
        touchStart = (location, time)
        lastLocation = location
        lastMoveTime = time
        movedFar = false
        // A touch that arrives straight after a tap continues it as a drag.
        if let ended = lastTapEnded, time - ended <= Self.dragChainDelay {
            isDragging = true
            lastTapEnded = nil
            return [.move(position), .press(.left)]
        }
        return []
    }

    mutating func moved(to location: CGPoint, time: TimeInterval) -> [TrackpadAction] {
        guard let previous = lastLocation else { return [] }
        let dx = Double(location.x - previous.x), dy = Double(location.y - previous.y)
        lastLocation = location
        let elapsed = max(0.001, time - (lastMoveTime ?? time))
        lastMoveTime = time
        if let start = touchStart {
            let travelled = hypot(Double(location.x - start.location.x), Double(location.y - start.location.y))
            if travelled > Self.tapMovement { movedFar = true }
        }
        guard dx != 0 || dy != 0, viewSize.width > 0, viewSize.height > 0 else { return [] }
        let scale = Double(region.size.width) / Double(viewSize.width)
        let speed = hypot(dx, dy) / elapsed
        let acceleration = min(Self.maximumAcceleration, max(1, speed / Self.accelerationThreshold + 1))
        let moved = DesktopPoint(x: position.x + Int((dx * scale * acceleration).rounded()),
                                 y: position.y + Int((dy * scale * acceleration).rounded()))
        position = clamped(moved)
        return [.move(position)]
    }

    mutating func ended(time: TimeInterval) -> [TrackpadAction] {
        defer {
            touchStart = nil
            lastLocation = nil
            lastMoveTime = nil
            movedFar = false
        }
        if isDragging {
            isDragging = false
            return [.release(.left)]
        }
        guard let start = touchStart else { return [] }
        let quick = time - start.time <= Self.tapDuration
        guard quick, !movedFar else { return [] }
        lastTapEnded = time
        return [.move(position), .press(.left), .release(.left)]
    }

    mutating func cancelled() -> [TrackpadAction] {
        let wasDragging = isDragging
        isDragging = false
        touchStart = nil
        lastLocation = nil
        movedFar = false
        return wasDragging ? [.release(.left)] : []
    }

    /// Two fingers tapped together, which is the right button at the cursor's own position.
    mutating func secondaryTap() -> [TrackpadAction] {
        lastTapEnded = nil
        return [.move(position), .press(.right), .release(.right)]
    }

    private func clamped(_ point: DesktopPoint) -> DesktopPoint {
        let maxX = region.origin.x + max(0, region.size.width - 1)
        let maxY = region.origin.y + max(0, region.size.height - 1)
        return DesktopPoint(x: min(maxX, max(region.origin.x, point.x)),
                            y: min(maxY, max(region.origin.y, point.y)))
    }
}
