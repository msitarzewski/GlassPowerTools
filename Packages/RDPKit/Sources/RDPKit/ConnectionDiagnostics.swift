import Foundation
import OSLog

/// Metadata only: never pass reports, raw PDUs, credentials, input or decoded pixels here.
/// Unified logging supplies the UTC timestamp and process ID for correlation with the server.
final class RDPConnectionDiagnostics: @unchecked Sendable {
    static let logger = Logger(subsystem: "org.rdpkit", category: "connection")
    static let graphics = Logger(subsystem: "org.rdpkit", category: "graphics")
    let id = UUID().uuidString
    private let lock = NSLock()
    private var sampleCount = 0
    private var lastSample = Date.distantPast

    func milestone(_ event: String, hop: Int) {
        Self.logger.notice("attempt=\(self.id, privacy: .public) hop=\(hop) event=\(event, privacy: .public)")
    }

    func frame(_ frame: RDPGraphicsFrameSnapshot, hop: Int, failed: Bool = false) {
        let shouldRecord = lock.withLock {
            sampleCount += 1
            let now = Date()
            guard failed || sampleCount <= 32 || now.timeIntervalSince(lastSample) >= 1 else { return false }
            lastSample = now
            return true
        }
        guard shouldRecord else { return }
        let metadata = Self.frameMetadata(frame)
        if failed {
            Self.graphics.error("attempt=\(self.id, privacy: .public) hop=\(hop) event=frame-failed \(metadata, privacy: .public)")
        } else {
            Self.graphics.debug("attempt=\(self.id, privacy: .public) hop=\(hop) event=frame-received \(metadata, privacy: .public)")
        }
    }

    static func frameMetadata(_ frame: RDPGraphicsFrameSnapshot) -> String {
        func rect(_ value: RDPFrameRect?) -> String {
            guard let value else { return "none" }
            return "\(value.left),\(value.top),\(value.right),\(value.bottom)"
        }
        // Numeric fields are safe even for an untrusted server. Avoid codecName and report strings.
        let layout: Int = switch frame.avc444SubframeLayout {
        case .yuv420AndChroma420: 0
        case .yuv420Only: 1
        case .chroma420Only: 2
        case nil: -1
        }
        let regions = frame.regionRects.prefix(4).map { rect($0) }.joined(separator: ";")
        let auxiliary = frame.auxiliaryRegionRects.prefix(4).map { rect($0) }.joined(separator: ";")
        return "frame=\(frame.frameID.map(String.init) ?? "none") surface=\(frame.surfaceID) codec=\(frame.codecID) lc=\(layout) bounds=\(rect(frame.destinationRect)) surfaceRect=\(rect(frame.surfaceRect)) output=\(rect(frame.graphicsOutputRect)) regions=\(frame.regionRects.count):\(regions) auxiliaryRegions=\(frame.auxiliaryRegionRects.count):\(auxiliary) bytes=\(frame.encodedVideoData.count) auxiliaryBytes=\(frame.auxiliaryEncodedVideoData?.count ?? 0)"
    }
}
