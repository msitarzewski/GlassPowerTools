import Foundation

/// Remote Framebuffer protocol constants and models. References: RFC 6143 (RFB 3.8),
/// https://www.rfc-editor.org/rfc/rfc6143 and the community RFB protocol registry,
/// https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst
public enum RFBLimits {
    public static let maximumDimension = 8192
    public static let maximumPixels = 33_554_432
    public static let maximumNameBytes = 4096
    public static let maximumCutTextBytes = 1_048_576
    public static let maximumReasonBytes = 4096
    public static let maximumEncodedRectangleBytes = 64 * 1024 * 1024
    public static let maximumSecurityTypes = 255
    public static let maximumDiffieHellmanKeyBytes = 1024
    public static let minimumDiffieHellmanKeyBytes = 16
}

public struct RFBProtocolVersion: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public init(major: Int, minor: Int) { self.major = major; self.minor = minor }

    /// Apple Screen Sharing announces `RFB 003.889`; every 3.x server at or beyond 3.8 is
    /// negotiated as 3.8, matching common clients (TigerVNC, gtk-vnc, libvncclient).
    public var negotiated: RFBProtocolVersion {
        guard major == 3 else { return RFBProtocolVersion(major: 3, minor: 8) }
        if minor >= 8 { return RFBProtocolVersion(major: 3, minor: 8) }
        if minor >= 7 { return RFBProtocolVersion(major: 3, minor: 7) }
        return RFBProtocolVersion(major: 3, minor: 3)
    }

    var wireBytes: [UInt8] { Array(String(format: "RFB %03d.%03d\n", major, minor).utf8) }

    /// Apple's own revision, which a Mac announces and Apple's viewer answers.
    public static let apple = RFBProtocolVersion(major: 3, minor: 889)

    static func parse(_ bytes: [UInt8]) throws -> RFBProtocolVersion {
        guard bytes.count == 12, bytes[0...3].elementsEqual("RFB ".utf8), bytes[7] == UInt8(ascii: "."), bytes[11] == 10,
              let major = Int(String(decoding: bytes[4...6], as: UTF8.self)),
              let minor = Int(String(decoding: bytes[8...10], as: UTF8.self)) else {
            throw RFBError.protocolViolation("The server did not send a valid RFB protocol version.")
        }
        guard major == 3, minor >= 3 else {
            throw RFBError.unsupported("RFB protocol version \(major).\(minor) is not supported.")
        }
        return RFBProtocolVersion(major: major, minor: minor)
    }
}

public enum RFBSecurityType: UInt8, Sendable, Equatable {
    case invalid = 0
    case none = 1
    case vncAuthentication = 2
    case appleRemoteDesktop = 30

    public var displayName: String {
        switch self {
        case .invalid: "invalid"
        case .none: "no authentication"
        case .vncAuthentication: "VNC password"
        case .appleRemoteDesktop: "Apple Remote Desktop user account"
        }
    }
}

public enum RFBEncoding: Int32, Sendable {
    case raw = 0
    case copyRect = 1
    case rre = 2
    case hextile = 5
    case zlib = 6
    case tight = 7
    case zrle = 16
    case cursor = -239
    case desktopSize = -223
    case lastRect = -224
    case extendedDesktopSize = -308
    /// The standard PointerPos pseudo-encoding (−232, libvncserver's `rfbEncodingPointerPos`): where
    /// the server's pointer is, in the rectangle's x and y, with no payload. libvncserver, TigerVNC
    /// and KasmVNC send it for moves this client did not make. Asked for only to try a Mac (2026-10-11).
    case pointerPosition = -232
    /// Apple's older display list (0x44d), asked for only from Apple's server, and always beside the
    /// layout: a Mac reports its displays only to a client listing both (`RFBAppleDisplays.swift`).
    /// Stepped over: it arrives only from a Mac that does not send the layout.
    case appleDisplayInfo = 1101
    /// Apple's own display layout (0x451), asked for only from Apple's server (`RFBServerDialect`).
    /// Apple does not document it; its form is from remotex's measurements (`RFBAppleDisplayLayout`).
    /// It is how a Mac tells a client where each display sits, how large the framebuffer is, and at
    /// what server-side scale.
    case appleDisplayLayout = 1105
    /// Apple's CursorPos (0x44c): where the Mac's pointer is, in the rectangle's x and y, with no
    /// payload (remotex's notes, "Which encodings make the Mac report its displays"). Asked for only
    /// from Apple's server (W38), so a pointer moved at the Mac, or onto another display, is drawn
    /// where it is.
    case appleCursorPosition = 1100
    /// Apple's cursor cache (0x450): a shape stored once under an id, then selected by that id
    /// (`RFBAppleCursorCache`). How Apple's own viewer gets the pointer's shape. Asked for only from
    /// Apple's server (W38).
    case appleCursorImage = 1104

    static let advertised: [RFBEncoding] = [.tight, .zrle, .hextile, .zlib, .copyRect, .rre, .raw,
                                            .cursor, .desktopSize, .extendedDesktopSize, .lastRect]

    /// The SetEncodings list for the whole framebuffer at Tight's JPEG quality level (-32 + 0…9).
    /// Without a quality level a server keeps Tight lossless. `setEncodingsValues(profile:copyRect:)`
    /// is the full form (`VNCStreaming.swift`).
    static func setEncodingsValues(jpegQuality: Int?) -> [Int32] {
        let profile = VNCStreamProfile(level: .balanced, colourDepth: .full, jpegQuality: jpegQuality,
                                       compressionLevel: nil, maximumUpdatesPerSecond: nil)
        return setEncodingsValues(profile: profile, copyRect: true)
    }
}

public struct RFBRectangle: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width == 0 || height == 0 }

    func validated(in framebufferWidth: Int, _ framebufferHeight: Int) throws -> RFBRectangle {
        guard x >= 0, y >= 0, width >= 0, height >= 0,
              maxX <= framebufferWidth, maxY <= framebufferHeight else {
            throw RFBError.protocolViolation("The server sent a rectangle outside the framebuffer.")
        }
        return self
    }
}

/// The pixel format this client always requests: 32 bits per pixel, 24-bit depth, little-endian,
/// true colour with red in bits 16–23, green in 8–15 and blue in 0–7. In memory each pixel is
/// therefore B, G, R, X, which the presentation layer consumes as BGRA8.
public struct RFBPixelFormat: Equatable, Sendable {
    public let bitsPerPixel: UInt8
    public let depth: UInt8
    public let bigEndian: Bool
    public let trueColour: Bool
    public let redMax: UInt16
    public let greenMax: UInt16
    public let blueMax: UInt16
    public let redShift: UInt8
    public let greenShift: UInt8
    public let blueShift: UInt8

    public static let client = RFBPixelFormat(bitsPerPixel: 32, depth: 24, bigEndian: false, trueColour: true,
                                              redMax: 255, greenMax: 255, blueMax: 255,
                                              redShift: 16, greenShift: 8, blueShift: 0)

    public var wireBytes: [UInt8] {
        var bytes: [UInt8] = [bitsPerPixel, depth, bigEndian ? 1 : 0, trueColour ? 1 : 0]
        bytes += redMax.bigEndianBytes + greenMax.bigEndianBytes + blueMax.bigEndianBytes
        bytes += [redShift, greenShift, blueShift, 0, 0, 0]
        return bytes
    }

    static func parse(_ reader: inout ByteReader) throws -> RFBPixelFormat {
        let bitsPerPixel = try reader.u8(), depth = try reader.u8(), bigEndian = try reader.u8(), trueColour = try reader.u8()
        let redMax = try reader.u16(), greenMax = try reader.u16(), blueMax = try reader.u16()
        let redShift = try reader.u8(), greenShift = try reader.u8(), blueShift = try reader.u8()
        _ = try reader.bytes(3)
        return RFBPixelFormat(bitsPerPixel: bitsPerPixel, depth: depth, bigEndian: bigEndian != 0, trueColour: trueColour != 0,
                              redMax: redMax, greenMax: greenMax, blueMax: blueMax,
                              redShift: redShift, greenShift: greenShift, blueShift: blueShift)
    }
}

public struct VNCServerInfo: Equatable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int
    public let serverVersion: RFBProtocolVersion
    public let negotiatedVersion: RFBProtocolVersion
    public let securityType: RFBSecurityType
    public let serverPixelFormat: RFBPixelFormat
    /// How long this device took to compute Apple Remote Desktop's Diffie-Hellman exchange (security
    /// type 30); nil for other security types. For the log and the live probe.
    public let keyExchangeDuration: Duration?
    /// The client messages a Mac accepts, one bit each, from its enhanced ServerInit (003.889); nil
    /// from every other server. Most significant bit first: type `t` is bit `7 − t % 8` of byte `t / 8`.
    public var appleCommands: [UInt8]? = nil
    /// The session travels in Apple's record layer (`RFBAppleRecordLayer`).
    public var encrypted = false

    /// Whether the Mac accepts client message `type`, by its enhanced ServerInit.
    public func appleAccepts(_ type: UInt8) -> Bool {
        guard let appleCommands, Int(type / 8) < appleCommands.count else { return false }
        return appleCommands[Int(type / 8)] & (0x80 >> (type % 8)) != 0
    }

    /// Apple's Screen Sharing, which announces RFB 003.889 (`RFBServerDialect`).
    public var isAppleScreenSharing: Bool { RFBServerDialect(version: serverVersion) == .apple }
}

/// One display inside the shared framebuffer, from the ExtendedDesktopSize pseudo-encoding.
/// A server with several displays publishes one framebuffer covering them all, and this list gives
/// each display's place inside it. See the RFB protocol registry, "ExtendedDesktopSize".
public struct VNCScreen: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let flags: UInt32

    /// Whether the server marks this the main display; nil when the protocol has no such mark
    /// (ExtendedDesktopSize does not; Apple's layout does).
    public let isMain: Bool?
    /// The display's own pixels per point, 1 or 2 (a Retina display), from Apple's layout; nil where
    /// the server does not say (W38).
    public let density: Double?

    public init(id: UInt32, x: Int, y: Int, width: Int, height: Int, flags: UInt32, isMain: Bool? = nil,
                density: Double? = nil) {
        self.id = id; self.x = x; self.y = y; self.width = width; self.height = height; self.flags = flags
        self.isMain = isMain; self.density = density
    }

    /// Screens outside the framebuffer, or with no area, cannot be shown and are discarded.
    func validated(inFramebufferWidth framebufferWidth: Int, height framebufferHeight: Int) -> VNCScreen? {
        guard width > 0, height > 0, x >= 0, y >= 0,
              x + width <= framebufferWidth, y + height <= framebufferHeight else { return nil }
        return self
    }
}

/// Top-down BGRA cursor pixels with a one-byte-per-pixel opacity mask (1 = opaque). The fourth
/// byte of each pixel is its alpha: 0 or 255 for the standard Cursor encoding, and the shape's own
/// soft edges and shadow for Apple's cursor cache.
public struct VNCCursorImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let hotSpotX: Int
    public let hotSpotY: Int
    public let bgra: Data
    public let mask: Data
    /// The shape is measured in the Mac's points, not the picture's pixels (W38): a Mac sends the
    /// same shape whatever the density of the display the pointer is on, so on a Retina display
    /// sent at its own pixels it is drawn twice as large as its pixel count (remotex's
    /// `CursorUnit::Points`; the owner, 2026-10-11: "the mouse cursor is insanely small on the main
    /// display").
    public let isPointSized: Bool

    public init(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, bgra: Data, mask: Data, isPointSized: Bool = false) {
        self.width = width; self.height = height; self.hotSpotX = hotSpotX; self.hotSpotY = hotSpotY
        self.bgra = bgra; self.mask = mask; self.isPointSized = isPointSized
    }
}

public enum RFBError: Error, Sendable, Equatable, LocalizedError {
    case connectionClosed
    case cancelled
    case protocolViolation(String)
    case unsupported(String)
    case authenticationFailed(String)
    case connectionFailed(String)
    case invalidConfiguration(String)
    case resourceLimit(String)

    public var errorDescription: String? {
        switch self {
        case .connectionClosed: "The server closed the connection."
        case .cancelled: "The connection was cancelled."
        case let .protocolViolation(message), let .unsupported(message), let .authenticationFailed(message),
             let .connectionFailed(message), let .invalidConfiguration(message), let .resourceLimit(message):
            message
        }
    }
}

public extension UInt16 {
    var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xFF)] }
}

public extension UInt32 {
    var bigEndianBytes: [UInt8] { [UInt8(self >> 24), UInt8((self >> 16) & 0xFF), UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)] }
}

public extension Int32 {
    var bigEndianBytes: [UInt8] { UInt32(bitPattern: self).bigEndianBytes }
}
