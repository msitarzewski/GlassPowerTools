import Foundation

public struct GlassRDPConfiguration: Sendable {
    public var host: String
    public var port: UInt16
    public var username: String
    public var domain: String?
    public var password: String
    public var width: Int
    public var height: Int
    public var requiresNLA: Bool
    public var approvedCertificateSHA256: String?
    public var clipboardEnabled: Bool
    public var audioEnabled: Bool
    /// The scale the server should lay the first desktop out at, 100–500 percent
    /// (MS-RDPBCGR 2.2.1.3.2 desktopScaleFactor). The display channel's layouts carry their own.
    public var desktopScaleFactor: Int

    public init(host: String, port: UInt16 = 3389, username: String, domain: String? = nil,
                password: String, width: Int = 1440, height: Int = 900, requiresNLA: Bool = true,
                approvedCertificateSHA256: String? = nil, clipboardEnabled: Bool = false,
                audioEnabled: Bool = false, desktopScaleFactor: Int = 100) {
        self.host = host; self.port = port; self.username = username; self.domain = domain
        self.password = password; self.width = width; self.height = height
        self.requiresNLA = requiresNLA; self.approvedCertificateSHA256 = approvedCertificateSHA256
        self.clipboardEnabled = clipboardEnabled; self.audioEnabled = audioEnabled
        self.desktopScaleFactor = min(500, max(100, desktopScaleFactor))
    }
}

/// Immutable, fully reconstructed remote pixels. Local transparency must not mutate this data.
public struct GlassRDPFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: Data
    public let sequence: UInt64
    public let receivedAt: Date
    public let decodedAt: Date
    public let usesHardwareAcceleration: Bool?

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: Data, sequence: UInt64,
                receivedAt: Date = Date(), decodedAt: Date = Date(), usesHardwareAcceleration: Bool? = nil) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              bytesPerRow >= width * 4, bytesPerRow <= 8192 * 4 + 4096,
              pixels.count == bytesPerRow * height else { throw GlassRDPError.invalidFrame }
        self.width = width; self.height = height; self.bytesPerRow = bytesPerRow; self.pixels = pixels
        self.sequence = sequence; self.receivedAt = receivedAt; self.decodedAt = decodedAt
        self.usesHardwareAcceleration = usesHardwareAcceleration
    }
}

public enum GlassRDPState: Sendable, Equatable {
    case connecting, connected, disconnected
    case failed(String)
}

public struct GlassRDPCertificate: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public let sha256: String?
    public let systemTrusted: Bool
    public let isAccepted: Bool
}

public struct GlassRDPDisplayCapabilities: Sendable, Equatable {
    public let maximumMonitors: UInt32
    public let maximumArea: UInt64

    public init(maximumMonitors: UInt32, maximumArea: UInt64) {
        self.maximumMonitors = maximumMonitors; self.maximumArea = maximumArea
    }

    public func supports(width: Int, height: Int) -> Bool {
        maximumMonitors > 0 && (200...8192).contains(width) && (200...8192).contains(height)
            && width.isMultiple(of: 2) && UInt64(width) * UInt64(height) <= maximumArea
    }
}

/// One display inside the remote framebuffer. A host with several displays sends a single image
/// covering them all; this says where each display sits inside it, so one can be shown on its own.
public struct GlassRemoteScreen: Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let isPrimary: Bool
    /// The display's own pixels per point — 2 for a Retina display — where the host says (a Mac's
    /// layout); nil otherwise (W38).
    public let density: Double?

    public init(id: UInt32, x: Int, y: Int, width: Int, height: Int, isPrimary: Bool, density: Double? = nil) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.height = height; self.isPrimary = isPrimary
        self.density = density
    }
}

public enum GlassRDPPointerButton: Sendable { case left, right, middle, back, forward }

public struct GlassRDPCursorImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let hotSpotX: Int
    public let hotSpotY: Int
    public let xorBitsPerPixel: Int
    public let xorMask: Data
    public let andMask: Data
    /// RGB palette triplets for 4/8-bit indexed cursors, when sent by the server.
    public let paletteEntries: Data?
    /// Measured in the host's points rather than the picture's pixels: a Mac's pointer, the same
    /// shape on a Retina display as on a 1x one (W38). Drawn at the display's pixels per point.
    public let isPointSized: Bool

    public init(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, xorBitsPerPixel: Int,
                xorMask: Data, andMask: Data, paletteEntries: Data?, isPointSized: Bool = false) {
        self.width = width; self.height = height; self.hotSpotX = hotSpotX; self.hotSpotY = hotSpotY
        self.xorBitsPerPixel = xorBitsPerPixel; self.xorMask = xorMask; self.andMask = andMask
        self.paletteEntries = paletteEntries; self.isPointSized = isPointSized
    }
}

public enum GlassRDPCursor: Sendable, Equatable {
    case position(x: Int, y: Int)
    case hidden, systemDefault
    case image(GlassRDPCursorImage)
}

/// Interleaved PCM16LE audio received on the negotiated RDP audio channel.
public struct GlassRDPAudioSample: Sendable, Equatable {
    public let sampleRate: Double
    public let channels: Int
    public let data: Data
}

/// One copy, in every form the source had (D42a): text, and where present HTML, RTF and an image as
/// PNG. RDP carries all of them; VNC carries the text.
public struct GlassClipboardContent: Sendable, Equatable, ExpressibleByStringLiteral {
    public var text: String?
    public var html: String?
    public var rtf: Data?
    public var png: Data?

    public init(text: String? = nil, html: String? = nil, rtf: Data? = nil, png: Data? = nil) {
        self.text = text; self.html = html; self.rtf = rtf; self.png = png
    }

    public init(stringLiteral value: String) { self.init(text: value) }

    public var isEmpty: Bool { text == nil && html == nil && rtf == nil && png == nil }
}

public enum GlassRDPEvent: Sendable, Equatable {
    case state(GlassRDPState)
    case certificate(GlassRDPCertificate)
    case displayCapabilities(GlassRDPDisplayCapabilities)
    case cursor(GlassRDPCursor)
    case clipboard(GlassClipboardContent)
    case audio(GlassRDPAudioSample)
    /// The displays inside the remote framebuffer. Empty means the host published no layout.
    case screens([GlassRemoteScreen])
    /// What the link is doing, about once a second (VNC).
    case linkStatistics(GlassDesktopLinkStatistics)
}

public enum GlassRDPError: Error, Sendable, Equatable, LocalizedError {
    case alreadyConnected, notConnected, invalidConfiguration, invalidFrame
    case unsupported(String)
    case protocolFailure(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyConnected: "A remote session is already active."
        case .notConnected: "The remote session is not ready."
        case .invalidConfiguration: "The host, account, port, or desktop dimensions are invalid."
        case .invalidFrame: "The server produced an invalid desktop image."
        case let .unsupported(message), let .protocolFailure(message): message
        }
    }
}
