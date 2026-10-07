//
//  DesktopPinchProbe.swift
//  Glass Power Tools — GlassDesktop
//
//  A measuring aid, not a feature (2026-10-06). The owner asked for "palm up click-drag =
//  scrollwheel". Whether a window can tell palm up from palm away depends on the pinch's pose
//  (SpatialEventCollection.Event.inputDevicePose), which Apple does not document as palm
//  direction — so it is read on the headset first. Shown only when the app is launched with
//  GLASS_PINCH_PROBE=1; otherwise nothing is attached and input is untouched.
//

#if os(visionOS)
import SwiftUI
import Spatial

struct DesktopPinchProbe: ViewModifier {
    static let isEnabled = ProcessInfo.processInfo.environment["GLASS_PINCH_PROBE"] == "1"
    @State private var reading = "Pinch anywhere on the desktop."

    func body(content: Content) -> some View {
        if Self.isEnabled {
            content
                .simultaneousGesture(SpatialEventGesture().onChanged { events in
                    guard let event = events.first(where: { $0.kind == .indirectPinch || $0.kind == .directPinch }) else { return }
                    reading = Self.describe(event)
                })
                .overlay(alignment: .topLeading) {
                    Text(reading)
                        .font(.system(size: 20, design: .monospaced))
                        .padding(12)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .padding(16)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }

    private static func describe(_ event: SpatialEventCollection.Event) -> String {
        let hand = event.chirality.map { $0 == .left ? "left" : "right" } ?? "unknown"
        guard let pose = event.inputDevicePose?.pose3D else { return "hand: \(hand)\nno pose" }
        let q = pose.rotation.quaternion
        func axis(_ v: SIMD3<Double>) -> String {
            let r = q.act(v)
            return String(format: "x %+.2f  y %+.2f  z %+.2f", r.x, r.y, r.z)
        }
        return """
        hand: \(hand)   kind: \(event.kind == .indirectPinch ? "indirect" : "direct")
        quat: \(String(format: "%+.2f %+.2f %+.2f %+.2f", q.vector.x, q.vector.y, q.vector.z, q.vector.w))
        up:   \(axis([0, 1, 0]))
        right:\(axis([1, 0, 0]))
        fwd:  \(axis([0, 0, -1]))
        """
    }
}
#endif
