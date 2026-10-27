//
//  GlassHeadTracker.swift
//  Glass Power Tools — GlassShell
//
//  Where the person's head is and which way it faces, from ARKit's world tracking, which asks no
//  permission (`WorldTrackingProvider.requiredAuthorizations` is empty, measured 2026-10-26) but
//  answers only in a Full Space: "ARKit data is available only when your app presents a Full Space
//  and other apps are hidden" (Apple, "Setting up access to ARKit data"). Focus Mode moves its world
//  by it (`FocusWalking`, D89); the orb dock asks the one running there which way the head is turned
//  as an orb is pinched, to bring a window back on the side away from a tall dock (D88).
//

#if os(visionOS)
import ARKit
import OSLog
import QuartzCore

@MainActor
public final class GlassHeadTracker {
    /// A session and its provider for each run: ARKit asserts when a provider it stopped is run
    /// again (`ARKitSession.run(_:)`), and the app crashed as the dock, which ran one while tall,
    /// went tall, wide and tall again (the owner, 2026-10-27: "the first time I tried to resize
    /// vertically the app crashed").
    private var session: ARKitSession?
    private var tracking: WorldTrackingProvider?
    private let purpose: String
    nonisolated private static let log = Logger(subsystem: "com.glasspowertools", category: "head-tracking")

    /// The tracker running now, if any: Focus Mode's, the only place ARKit answers.
    public private(set) static weak var current: GlassHeadTracker?

    /// - Parameter purpose: who asks, for the log.
    public init(purpose: String) { self.purpose = purpose }

    public func run() async {
        guard session == nil else { return }
        Self.log.info("World tracking for \(self.purpose, privacy: .public): supported \(WorldTrackingProvider.isSupported, privacy: .public), needs \(String(describing: WorldTrackingProvider.requiredAuthorizations), privacy: .public)")
        // Only without a question to the person: one that asked would need its reason in Info.plist.
        guard WorldTrackingProvider.isSupported, WorldTrackingProvider.requiredAuthorizations.isEmpty else { return }
        let session = ARKitSession()
        let tracking = WorldTrackingProvider()
        self.session = session
        self.tracking = tracking
        do {
            try await session.run([tracking])
            // Stopped while it started: nothing more to do.
            if self.session === session { Self.current = self }
        } catch {
            Self.log.error("World tracking for \(self.purpose, privacy: .public) couldn't start: \(String(describing: error), privacy: .public)")
            if self.session === session { stop() }
        }
    }

    public func stop() {
        guard let session else { return }
        session.stop()
        self.session = nil
        tracking = nil
        if Self.current === self { Self.current = nil }
    }

    /// The head around the person: where it is, and the way it looks. Nil until tracking runs.
    public func pose() -> (position: SIMD3<Float>, forward: SIMD3<Float>)? {
        guard let tracking, tracking.state == .running,
              let anchor = tracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        let matrix = anchor.originFromAnchorTransform
        let position = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        let forward = -SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        return (position, simd_normalize(forward))
    }

    /// Which way the head is turned: 0 straight down −z, positive to the left (`GlassOrbDockSide`).
    public func heading() -> Double? {
        pose().map { GlassOrbDockSide.heading(forwardX: Double($0.forward.x), forwardZ: Double($0.forward.z)) }
    }
}
#endif
