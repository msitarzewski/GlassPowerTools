import Foundation

/// How a desktop session trades picture for bytes on the network. A VNC session acts on it
/// (`GlassVNCSession`); an RDP session negotiates its own codecs with the server and ignores it.
public enum GlassDesktopStreamQuality: String, Codable, CaseIterable, Sendable {
    /// Measures the link and moves between the levels below.
    case automatic
    /// Lossless, full colour, as fast as the link allows.
    case best
    /// Full colour, JPEG for photographic areas where the server offers it.
    case balanced
    /// Thousands of colours, stronger compression, 15 updates a second; a Mac renders at three
    /// quarters of its size.
    case dataSaver
    /// The strongest compression, 8 updates a second; 256 colours where the server sends no JPEG; a
    /// Mac renders at half its size.
    case lowest

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .best: "Best"
        case .balanced: "Balanced"
        case .dataSaver: "Data Saver"
        case .lowest: "Lowest"
        }
    }
}

/// What a Mac's Retina displays are sent at (W38; the owner, 2026-10-11: "can we have the Mac chill
/// on the 2x retina resolution when screen sharing?"). A VNC session to a Mac acts on it
/// (`GlassVNCSession`); every other session ignores it.
public enum GlassDesktopRetinaDisplays: String, Codable, CaseIterable, Sendable {
    /// One pixel per point: a Retina display's picture at half its pixels each way, a quarter of the
    /// bytes, with the quality level's own reduction on top.
    case oneX
    /// The display's own pixels.
    case native

    public var title: String {
        switch self {
        case .oneX: "Send at 1x (Recommended)"
        case .native: "Native 2x"
        }
    }
}

/// A rectangle of the remote framebuffer, in its pixels.
public struct GlassRemoteRegion: Sendable, Hashable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// What a session's link is doing, about once a second.
public struct GlassDesktopLinkStatistics: Sendable, Equatable {
    /// Everything received from the server, per second.
    public var bytesPerSecond: Double
    /// Picture updates per second.
    public var updatesPerSecond: Double
    /// What was asked for.
    public var quality: GlassDesktopStreamQuality
    /// The level in effect: Automatic's current choice, or the fixed level.
    public var level: GlassDesktopStreamQuality
    /// Bits of colour per pixel on the wire's format: 24, 16 or 8.
    public var colourDepth: Int
    /// The encoding carrying most of the recent bytes, by its protocol name.
    public var encoding: String?
    /// The link's speed when Automatic last measured it.
    public var measuredKilobitsPerSecond: Double?
    /// Only the displays on screen are being asked for.
    public var regionLimited: Bool
    /// Nothing is on screen, so no picture is being asked for.
    public var paused: Bool
    /// The size a Mac renders its picture at, as a fraction of its own (1 is its own size), as the
    /// Mac last confirmed it; nil for a server that cannot be asked.
    public var serverScale: Double?
    /// The connection's round trip, in seconds, and how much of it is data waiting in the network;
    /// nil where the transport does not say.
    public var roundTrip: Double?
    public var queued: Double?

    public init(bytesPerSecond: Double, updatesPerSecond: Double, quality: GlassDesktopStreamQuality,
                level: GlassDesktopStreamQuality, colourDepth: Int, encoding: String?,
                measuredKilobitsPerSecond: Double?, regionLimited: Bool, paused: Bool, serverScale: Double? = nil,
                roundTrip: Double? = nil, queued: Double? = nil) {
        self.bytesPerSecond = bytesPerSecond; self.updatesPerSecond = updatesPerSecond
        self.quality = quality; self.level = level; self.colourDepth = colourDepth; self.encoding = encoding
        self.measuredKilobitsPerSecond = measuredKilobitsPerSecond
        self.regionLimited = regionLimited; self.paused = paused; self.serverScale = serverScale
        self.roundTrip = roundTrip; self.queued = queued
    }
}
