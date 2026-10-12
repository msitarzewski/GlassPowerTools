import Foundation
import OSLog

// What this client asks a server to send, and how often: the levers that move bytes on the wire.
//
// RFB has no bandwidth setting. A client changes what arrives in four ways, and every one of them is
// a message this file composes (RFC 6143 §7.5, and the community registry for the pseudo-encodings,
// https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst):
//
// - **Colour depth** — SetPixelFormat. Every encoding that carries pixels shrinks with it, so it is
//   the one lever that works on a server that never sends Tight.
// - **Encodings** — SetEncodings: their order, Tight's JPEG quality (pseudo-encodings −32…−23) and
//   compression level (−256…−247). A server that does not implement Tight ignores both.
// - **How often** — an incremental FramebufferUpdateRequest is the only thing that lets a server
//   send; pacing them caps the update rate, so a region that changes constantly is sent at most that
//   often, its changes merged in between.
// - **Where** — the request's rectangle. Only the displays that are on screen are asked for
//   (`VNCClient.setRequestedRegions`).
// - **How large** — on a Mac only, `SetServerScaling`: the Mac renders its framebuffer smaller
//   before encoding it (`RFBAppleDisplays.swift`). Every encoding shrinks with the pixel count. A
//   Retina display is asked for at 1x — half its pixels each way, a quarter of the bytes — unless
//   the person chose its native pixels (W38).
// - **Which display** — on a Mac only, `SetDisplay`: one display's own pixels, on a connection of
//   its own (W38).
//
// Scaling the image on this device saves nothing: the server sends its own pixels either way. Only
// a Mac can be asked to send fewer.

/// How a session trades picture for bytes. Automatic measures the link and chooses a level; the
/// others are fixed.
public enum VNCQuality: String, Sendable, CaseIterable, Codable {
    case automatic, best, balanced, dataSaver, lowest

    /// The levels Automatic moves between, lowest first.
    static let ladder: [VNCQuality] = [.lowest, .dataSaver, .balanced, .best]
}

/// One level's messages: what SetPixelFormat and SetEncodings say, how often updates are asked for,
/// and, of a Mac, at what scale it renders.
public struct VNCStreamProfile: Sendable, Equatable {
    public let level: VNCQuality
    public let colourDepth: RFBColourDepth
    /// Tight's JPEG quality, 0–9; nil keeps Tight lossless.
    public let jpegQuality: Int?
    /// Tight's (and TigerVNC's ZRLE's) zlib effort, 0–9; nil leaves the server's default.
    public let compressionLevel: Int?
    /// Nil asks for the next update as soon as one arrives.
    public let maximumUpdatesPerSecond: Int?
    /// The factor a Mac is asked to render its framebuffer at, in (0, 1]; 1 is its own size. Only
    /// Apple's server is asked (`SetServerScaling`); every other server ignores this.
    public let serverScale: Double

    public init(level: VNCQuality, colourDepth: RFBColourDepth, jpegQuality: Int?, compressionLevel: Int?,
                maximumUpdatesPerSecond: Int?, serverScale: Double = 1) {
        self.level = level; self.colourDepth = colourDepth; self.jpegQuality = jpegQuality
        self.compressionLevel = compressionLevel; self.maximumUpdatesPerSecond = maximumUpdatesPerSecond
        self.serverScale = serverScale
    }

    /// Lossless, full colour, as fast as the link allows.
    public static let best = VNCStreamProfile(level: .best, colourDepth: .full, jpegQuality: nil,
                                              compressionLevel: nil, maximumUpdatesPerSecond: nil)
    /// Full colour with JPEG for photographic areas where the server offers Tight. What every
    /// session asked for before quality could be chosen.
    public static let balanced = VNCStreamProfile(level: .balanced, colourDepth: .full, jpegQuality: 8,
                                                  compressionLevel: nil, maximumUpdatesPerSecond: nil)
    /// Thousands of colours, stronger JPEG and compression, 15 updates a second; a Mac renders at
    /// three quarters of its size (56% of the pixels).
    public static let dataSaver = VNCStreamProfile(level: .dataSaver, colourDepth: .thousands, jpegQuality: 5,
                                                   compressionLevel: 6, maximumUpdatesPerSecond: 15, serverScale: 0.75)
    /// 256 colours, the strongest JPEG and compression, 8 updates a second; a Mac renders at half
    /// its size (a quarter of the pixels). A server that sends Tight keeps 16 bits, where its JPEG
    /// still works, and so does a Mac (`RFBStreamPlanner.wantedProfile`).
    public static let lowest = VNCStreamProfile(level: .lowest, colourDepth: .colours256, jpegQuality: 2,
                                                compressionLevel: 9, maximumUpdatesPerSecond: 8, serverScale: 0.5)

    /// A fixed level's profile; Automatic starts at Balanced.
    public static func profile(for level: VNCQuality) -> VNCStreamProfile {
        switch level {
        case .best: .best
        case .automatic, .balanced: .balanced
        case .dataSaver: .dataSaver
        case .lowest: .lowest
        }
    }
}

/// What the link is doing now, for the person looking at it.
public struct VNCLinkStatistics: Sendable, Equatable {
    /// Everything received from the server, per second, over the last couple of seconds.
    public var bytesPerSecond: Double
    /// Framebuffer updates that changed the picture, per second.
    public var updatesPerSecond: Double
    /// The level whose messages are in effect: Automatic's choice, or the fixed level.
    public var profile: VNCStreamProfile
    /// What was asked for.
    public var quality: VNCQuality
    /// The encoding that carried most of the recent bytes; nil when nothing arrived.
    public var encoding: RFBEncoding?
    /// The link's speed as Automatic last measured it, from an update large enough to say.
    public var measuredKilobitsPerSecond: Double?
    /// Only part of the framebuffer is asked for: the displays on screen.
    public var regionLimited: Bool
    /// Nothing is on screen, so no picture is asked for.
    public var paused: Bool
    public var totalBytes: Int
    /// The scale a Mac has confirmed it renders at, from its last display layout; nil for a server
    /// that sends no layout.
    public var serverScale: Double?
    /// The connection's round trip as its transport last measured it, in seconds; nil before a
    /// reading, and for a connection that has none.
    public var roundTrip: Double?
    /// How much of the round trip is data waiting in the network, in seconds (`RFBRoundTrips`).
    public var queued: Double?

    public init(bytesPerSecond: Double, updatesPerSecond: Double, profile: VNCStreamProfile, quality: VNCQuality,
                encoding: RFBEncoding?, measuredKilobitsPerSecond: Double?, roundTrip: Double? = nil, queued: Double? = nil,
                regionLimited: Bool, paused: Bool, totalBytes: Int, serverScale: Double? = nil) {
        self.bytesPerSecond = bytesPerSecond; self.updatesPerSecond = updatesPerSecond; self.profile = profile
        self.quality = quality; self.encoding = encoding; self.measuredKilobitsPerSecond = measuredKilobitsPerSecond
        self.roundTrip = roundTrip; self.queued = queued
        self.regionLimited = regionLimited; self.paused = paused; self.totalBytes = totalBytes
        self.serverScale = serverScale
    }
}

/// One framebuffer update as it arrived: for diagnostics and the live probe.
public struct VNCUpdateSummary: Sendable, Equatable {
    public let rectangles: [RFBRectangle]
    public let encodings: [RFBEncoding]
    /// Bytes read from the connection for this update, header included.
    public let bytes: Int
    public let colourDepth: RFBColourDepth
}

public extension RFBEncoding {
    var name: String {
        switch self {
        case .raw: "Raw"
        case .copyRect: "CopyRect"
        case .rre: "RRE"
        case .hextile: "Hextile"
        case .zlib: "Zlib"
        case .tight: "Tight"
        case .zrle: "ZRLE"
        case .cursor: "Cursor"
        case .desktopSize: "DesktopSize"
        case .lastRect: "LastRect"
        case .extendedDesktopSize: "ExtendedDesktopSize"
        case .pointerPosition: "PointerPos"
        case .appleDisplayInfo: "AppleDisplayInfo"
        case .appleDisplayLayout: "AppleDisplayLayout"
        case .appleCursorPosition: "CursorPos"
        case .appleCursorImage: "CursorImage"
        }
    }
}

/// Which server this is, where it changes what to ask for. Apple's announces RFB 003.889.
///
/// What is known of Apple's server, from others' measurements (Apple documents none of it):
/// asked for Tight it answers with Raw, and it uses ZRLE when offered; it reports its displays only
/// through its own layout, never ExtendedDesktopSize, and only to a client listing both its layout
/// and `DisplayInfo`; it can render its framebuffer smaller (`RFBAppleDisplays.swift`); it says
/// where its pointer is and sends the pointer's shapes through a cache of its own
/// (`RFBAppleCursor.swift`); and older macOS versions ended the session when a client asked for
/// fewer than 15 bits of colour. So for Apple: ZRLE first, both display encodings, its pointer's
/// two, server-side scaling, and colour no lower than 16 bits.
enum RFBServerDialect: Sendable, Equatable {
    case standard, apple

    init(version: RFBProtocolVersion) {
        self = version.major == 3 && version.minor == 889 ? .apple : .standard
    }

    var minimumColourDepth: RFBColourDepth { self == .apple ? .thousands : .colours256 }
}

// MARK: - The link governor

/// Chooses Automatic's level from how fast update data arrives and how late it arrives, measured
/// at the connection for every encoding — so a server that never sends Tight still has its colour
/// depth and update rate stepped down on a slow link, not only a JPEG quality it ignores.
///
/// **Speed.** A measurement is one update of at least 16 KB: its bytes over the time they took to
/// arrive. Smaller updates say more about latency than speed and are ignored. Going down takes three
/// measurements in a row below the current level; going up takes five in a row at least 25% above
/// the next level's floor, one level at a time, so a burst does not flip the picture back and forth
/// and a level that only just fits is not chosen. The floors are TigerVNC's viewer's (16 Mbit/s for
/// full colour).
///
/// **Lateness (2026-10-11).** Speed alone chose the wrong level on a phone's hotspot: a Mac sent
/// 64–74 Mbit/s, which reads as Best, and the picture ran seconds behind the hand. Two measures
/// of lateness now count as well:
/// - An update that takes a quarter of a second or more to arrive is a measurement one level down,
///   however fast its bytes came: the picture waited that long, and a Mac reads no input while it
///   sends one (remotex's notes, "Other messages"). Going up also needs the update to have arrived
///   in time at the next level's size, about two and a half times its bytes.
/// - Data waiting in the network (`observeQueueing`): the connection's smoothed round trip over
///   the shortest lately, as TCP Vegas and TigerVNC's server judge congestion by delay over the
///   base round trip (TigerVNC `common/rfb/Congestion.cxx`). Two readings in a row with 200 ms or
///   more waiting step down a level; the next reading counts once the queue has had four seconds
///   to drain; and nothing steps up for thirty seconds after, or while more than 100 ms waits.
struct RFBLinkQualityGovernor: Sendable {
    /// Never `.automatic`.
    private(set) var level: VNCQuality = .balanced
    private(set) var lastKilobitsPerSecond: Double?
    /// The highest level worth choosing. Balanced on a Mac, which sends no Tight and so the same
    /// bytes at Best.
    var highest: VNCQuality = .best {
        didSet { if Self.rank(level) > Self.rank(highest) { level = highest } }
    }
    private var downward: [VNCQuality] = []
    private var upward = 0
    /// How long data waited in the network at the last reading; nil before one.
    private var queued: Double?
    private var lateReadings = 0
    /// Late readings are not counted before this: the queue a step down left is still draining.
    private var drainingUntil: ContinuousClock.Instant?
    /// Nothing steps up before this.
    private var holdingUntil: ContinuousClock.Instant?

    static let minimumBytes = 16 * 1024
    static let measurementsToStepDown = 3
    static let measurementsToStepUp = 5
    static let upwardMargin = 1.25
    /// An update this late, in seconds, held the picture back.
    static let slowUpdate = 0.25
    /// About how many times the bytes the next level up sends for the same picture: a Mac's 16-bit
    /// colour against its 24 (in ZRLE's three-byte pixels), and three quarters of the size against
    /// all of it, is 2.7; half against three quarters is 2.25.
    static let levelCost = 2.5
    /// Seconds waiting in the network that make a reading late, and that let a level step up.
    static let congestedQueue = 0.2
    static let calmQueue = 0.1
    static let lateReadingsToStepDown = 2
    static let drainAfterStep: Duration = .seconds(4)
    static let holdAfterLateStep: Duration = .seconds(30)

    /// Tight's JPEG quality at the current level.
    var jpegQuality: Int? { VNCStreamProfile.profile(for: level).jpegQuality }

    /// The slowest link each level is for, in kilobits per second.
    static func floor(of level: VNCQuality) -> Double {
        switch level {
        case .best: 16_000
        case .automatic, .balanced: 4_000
        case .dataSaver: 750
        case .lowest: 0
        }
    }

    static func level(forKilobitsPerSecond rate: Double) -> VNCQuality {
        VNCQuality.ladder.last { rate >= floor(of: $0) } ?? .lowest
    }

    private static func rank(_ level: VNCQuality) -> Int { VNCQuality.ladder.firstIndex(of: level) ?? 2 }

    private static func lower(_ a: VNCQuality, _ b: VNCQuality) -> VNCQuality { rank(a) <= rank(b) ? a : b }

    /// One update: its bytes and how long they took to arrive. Returns the new level when it changes.
    mutating func observe(bytes: Int, seconds: Double, at now: ContinuousClock.Instant = .now) -> VNCQuality? {
        guard bytes >= Self.minimumBytes, seconds > 0.001, seconds.isFinite else { return nil }
        let rate = Double(bytes) * 8 / 1000 / seconds
        lastKilobitsPerSecond = rate
        let current = Self.rank(level)
        var measured = Self.lower(Self.level(forKilobitsPerSecond: rate), highest)
        if seconds >= Self.slowUpdate { measured = Self.lower(measured, VNCQuality.ladder[max(0, current - 1)]) }
        if Self.rank(measured) < current {
            upward = 0
            downward.append(measured)
            guard downward.count >= Self.measurementsToStepDown else { return nil }
            // The least drastic of the levels the run asked for.
            let chosen = downward.max { Self.rank($0) < Self.rank($1) } ?? measured
            downward = []
            level = chosen
            return chosen
        }
        downward = []
        guard current < Self.rank(highest) else { upward = 0; return nil }
        let next = VNCQuality.ladder[current + 1]
        let inTime = seconds * Self.levelCost < Self.slowUpdate
        let calm = queued.map { $0 < Self.calmQueue } ?? true
        let held = holdingUntil.map { now < $0 } ?? false
        guard rate >= Self.floor(of: next) * Self.upwardMargin, inTime, calm, !held else { upward = 0; return nil }
        upward += 1
        guard upward >= Self.measurementsToStepUp else { return nil }
        upward = 0
        level = next
        return next
    }

    /// How long data waits in the network now, in seconds (`RFBRoundTrips`), every couple of
    /// seconds. Returns the new level when it changes.
    mutating func observeQueueing(_ seconds: Double, at now: ContinuousClock.Instant) -> VNCQuality? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        queued = seconds
        if seconds >= Self.calmQueue { upward = 0 }
        if let draining = drainingUntil, now < draining { return nil }
        guard seconds >= Self.congestedQueue else { lateReadings = 0; return nil }
        lateReadings += 1
        let current = Self.rank(level)
        guard lateReadings >= Self.lateReadingsToStepDown, current > 0 else { return nil }
        lateReadings = 0; downward = []
        level = VNCQuality.ladder[current - 1]
        drainingUntil = now + Self.drainAfterStep
        holdingUntil = now + Self.holdAfterLateStep
        return level
    }
}

/// The connection's round trip as the transport measures it, and how much of it is data waiting in
/// the network: the smoothed round trip over the shortest of the last two minutes. The shortest
/// takes the transport's own minimum too, which includes the handshake's, measured before any
/// picture queued. Two minutes lets a longer route (a hotspot after Wi-Fi, a relay) become the
/// new base.
struct RFBRoundTrips: Sendable {
    private var shortest: [(at: ContinuousClock.Instant, seconds: Double)] = []
    private(set) var smoothed: Double?
    private(set) var queued: Double?

    static let baseWindow: Duration = .seconds(120)

    /// Returns how long data waits in the network now, in seconds; nil for a reading with no
    /// round trip in it.
    mutating func observe(_ reading: RFBTransportRoundTrip, at now: ContinuousClock.Instant) -> Double? {
        guard reading.smoothed.isFinite, reading.smoothed > 0 else { return nil }
        let least = reading.shortest.isFinite && reading.shortest > 0 ? min(reading.shortest, reading.smoothed) : reading.smoothed
        shortest.append((now, least))
        shortest.removeAll { now - $0.at > Self.baseWindow }
        let base = shortest.map(\.seconds).min() ?? least
        smoothed = reading.smoothed
        queued = max(0, reading.smoothed - base)
        return queued
    }
}

// MARK: - Counting what arrives

/// Counts every byte the client reads, whatever the encoding or message: the link's measure, and
/// the readout's.
final class RFBCountingByteSource: RFBByteSource, @unchecked Sendable {
    private let base: any RFBByteSource
    private let lock = NSLock()
    private var total = 0

    init(_ base: any RFBByteSource) { self.base = base }

    var totalBytes: Int { lock.withLock { total } }

    func read(_ count: Int) async throws -> [UInt8] {
        let bytes = try await base.read(count)
        lock.withLock { total += bytes.count }
        return bytes
    }
}

// MARK: - Messages

extension RFBEncoding {
    /// SetEncodings' list for a profile: Tight first, then the lossless encodings, the
    /// pseudo-encodings, and Tight's JPEG quality and compression level when the profile has them.
    /// CopyRect is left out while only part of the framebuffer is asked for: a copy's source could
    /// lie in a display this client is not keeping current.
    static func setEncodingsValues(profile: VNCStreamProfile, copyRect: Bool,
                                   dialect: RFBServerDialect = .standard, appleDisplayLayout: Bool = true,
                                   appleCursor: Bool = true) -> [Int32] {
        var order = advertised
        if dialect == .apple {
            // Apple's server answers a Tight preference with Raw; ZRLE first. It reports its
            // displays only to a client listing both of its display encodings (`RFBAppleDisplays.swift`).
            order.removeAll { $0 == .zrle }
            order.insert(.zrle, at: 0)
            if appleDisplayLayout { order += [.appleDisplayInfo, .appleDisplayLayout] }
            // Where its pointer is and its shapes, as Apple's viewer gets them (W38). The standard
            // Cursor stays listed: whichever the Mac sends is drawn.
            if appleCursor { order += [.appleCursorPosition, .appleCursorImage] }
        }
        var values = order.filter { copyRect || $0 != .copyRect }.map(\.rawValue)
        if let quality = profile.jpegQuality { values.append(-32 + Int32(min(9, max(0, quality)))) }
        if let level = profile.compressionLevel { values.append(-256 + Int32(min(9, max(0, level)))) }
        return values
    }

    static func setEncodingsMessage(_ values: [Int32]) -> [UInt8] {
        var message: [UInt8] = [2, 0] + UInt16(values.count).bigEndianBytes
        for value in values { message += value.bigEndianBytes }
        return message
    }
}

extension RFBPixelFormat {
    var setPixelFormatMessage: [UInt8] { [0, 0, 0, 0] + wireBytes }
}

extension RFBRectangle {
    func updateRequest(incremental: Bool) -> [UInt8] {
        [3, incremental ? 1 : 0] + UInt16(x).bigEndianBytes + UInt16(y).bigEndianBytes
            + UInt16(width).bigEndianBytes + UInt16(height).bigEndianBytes
    }

    /// The overlap with a framebuffer of this size; nil when there is none.
    func clipped(width framebufferWidth: Int, height framebufferHeight: Int) -> RFBRectangle? {
        let left = max(0, x), top = max(0, y)
        let right = min(framebufferWidth, maxX), bottom = min(framebufferHeight, maxY)
        guard right > left, bottom > top else { return nil }
        return RFBRectangle(x: left, y: top, width: right - left, height: bottom - top)
    }

    func contains(_ other: RFBRectangle) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }

    func intersects(_ other: RFBRectangle) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }

    /// The same area in a framebuffer rendered `factor` times as large: origin rounded down, far
    /// edges up.
    func scaled(by factor: Double) -> RFBRectangle {
        let left = Int((Double(x) * factor).rounded(.down)), top = Int((Double(y) * factor).rounded(.down))
        let right = Int((Double(maxX) * factor).rounded(.up)), bottom = Int((Double(maxY) * factor).rounded(.up))
        return RFBRectangle(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func bounding(_ rectangles: [RFBRectangle]) -> RFBRectangle? {
        guard let first = rectangles.first else { return nil }
        let left = rectangles.map(\.x).min() ?? first.x, top = rectangles.map(\.y).min() ?? first.y
        let right = rectangles.map(\.maxX).max() ?? first.maxX, bottom = rectangles.map(\.maxY).max() ?? first.maxY
        return RFBRectangle(x: left, y: top, width: right - left, height: bottom - top)
    }
}

// MARK: - The planner

/// Everything that decides what the client sends besides input, under one lock: the level in
/// effect and the one wanted, the area asked for, how many requests the server holds, and when the
/// next may go. `decide` turns that into bytes; the client writes them in the order decided.
///
/// **Requests.** One request is kept at the server: the next is asked for as soon as an update
/// begins to arrive (pipelining, 2026-09-30), unless the level caps the rate, in which case it
/// waits until a cap's interval has passed since the last. An area newly on screen is asked for
/// at once and in full (non-incremental), even with a request already held, so a display window
/// that opens shows its display without waiting for the other one to change.
///
/// **Colour depth.** The protocol cannot say which format an update is in, so a client must not
/// hold an outstanding request when it sends SetPixelFormat (the community specification says so in
/// as many words). A change of depth therefore stops asking, lets the held request be answered
/// (decoded in the old format), and sends SetPixelFormat with a full request once none is held.
/// A server that answers two held requests with one update leaves the count high; then, after two
/// seconds with nothing arriving and the client waiting between messages, the change is sent
/// anyway — with nothing arriving, the server is holding a request for a region that has not
/// changed, and it will answer that in the new format.
///
/// **A Mac's scale.** `SetServerScaling` is sent only once a Mac has sent a display layout, since
/// only a layout can confirm a factor and carry the framebuffer's new size (a Mac listing
/// `DisplayInfo` sends no DesktopSize). One factor is asked for at a time. The factor in force is
/// the last layout's, whatever was asked: pointer positions are divided by it (`VNCClient`). A
/// request no layout confirms within ten seconds is given up, and that factor is not asked for
/// again until the level wants another (remotex's notes, "Server-side scaling in Standard mode").
/// Requests carry on meanwhile, as remotex's do: the layout arrives before any picture in the new
/// size.
///
/// **Retina displays at 1x (W38).** With density scaling on, the factor asked for is the level's
/// times one over the density of the displays being fetched: a 2x display alone, or several 2x ones,
/// at 0.5 × the level's — the same picture Apple's viewer asks for on a 1x screen (remotex's
/// `server_scale_for`). Which displays are being fetched is what the windows on screen ask for (the
/// requested regions), or the one display `SetDisplay` names. A 2x display beside a 1x one in the
/// same request has no one factor that suits both: they come at their own pixels, as Apple's viewer
/// shows a mixed Combined Display (remotex's notes, "Combined Display over mixed densities"); a
/// display window then takes a connection of its own (`DesktopDisplayConnection`). A change the
/// windows cause is asked for once it has held for a second, so windows opening one after another
/// do not make the Mac re-render the desktop at each.
///
/// **One display (W38).** `SetDisplay` is sent once a layout shows the Mac sends them, before the
/// scale that display wants, with a request for the whole picture after both (remotex: "Queue the
/// repaint while the selection is still the message in front of the Mac"). The next layout naming
/// the display confirms it; one unconfirmed in ten seconds is given up, and the client ends the
/// session (`VNCClient`). Until a layout says the display is being sent, only a single pixel is
/// asked for, every two seconds — enough for the Mac to send its layout — and no picture is handed
/// on: the whole desktop at its own pixels is what this connection exists not to fetch.
final class RFBStreamPlanner: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "planner")
    private let lock = NSLock()

    // The level.
    private var quality: VNCQuality = .automatic
    private var governor = RFBLinkQualityGovernor()
    private var roundTrips = RFBRoundTrips()
    private var active = VNCStreamProfile.balanced
    private var decoder = RFBPixelDecoder.native
    private var advertisedEncodings: [Int32] = []

    // Requests.
    private var started = false
    private var dialect = RFBServerDialect.standard
    private var appleDisplayLayout = true
    private var appleCursor = true
    /// The server has sent Tight: it can send JPEG, which it does only at 16 bits or more.
    private var serverSendsTight = false
    private var width = 0, height = 0
    /// Nil asks for the whole framebuffer; empty asks for nothing (no display on screen).
    private var regions: [RFBRectangle]?
    private var outstanding = 0
    private var owed = false
    private var refresh = true
    private var urgent = true
    private var lastRequestAt: ContinuousClock.Instant?
    private var waitingSince: ContinuousClock.Instant?
    private var wakeAt: ContinuousClock.Instant?

    // A Mac's scale.
    private var serverScaling = true
    /// A Mac has sent a display layout this session.
    private var layoutSeen = false
    private var scaleInForce = 1.0
    private var scaleAsked: (factor: Double, at: ContinuousClock.Instant)?
    /// A factor the Mac did not confirm in time: not asked for again until another is wanted.
    private var scaleDeclined: Double?
    private var scaleOverride: Double?

    // A Mac's pushes.
    private var arming = true
    private var asksForPointerPosition = false
    func setAsksForPointerPosition(_ on: Bool) { lock.withLock { asksForPointerPosition = on } }
    private var armingInterval = RFBStreamPlanner.pushInterval
    /// The interval and size the Mac was last armed with; nil once a layout dropped the arming.
    private var armed: (interval: UInt32, width: Int, height: Int)?

    // A Mac's displays (W38).
    private var densityScaling = false
    /// The displays in the framebuffer now, with their densities, in its current pixels.
    private var displays: [VNCScreen] = []
    /// Every display's density by id, from the last layout's records.
    private var densities: [UInt32: Double] = [:]
    /// The display the last layout says is being sent; nil for all of them.
    private var displayInForce: UInt32?
    private var displayWanted: RFBDisplaySelection?
    private var displayAsked: (selection: RFBDisplaySelection, at: ContinuousClock.Instant)?
    private var displayDeclined: RFBDisplaySelection?
    /// The request to send with SetDisplay: the whole framebuffer as it is before the switch.
    private var displaySwitchRequest: RFBRectangle?
    private var startedAt: ContinuousClock.Instant?
    /// The density factor the scale is asked with, and one waiting to have held long enough.
    private var densityFactorInUse = 1.0
    private var densityDecided = false
    private var densityPending: (factor: Double, since: ContinuousClock.Instant)?

    // The readout.
    private struct Sample { let at: ContinuousClock.Instant; let changed: Bool; let encodingBytes: [Int32: Int] }
    private var samples: [Sample] = []
    private var readings: [(at: ContinuousClock.Instant, total: Int)] = []

    static let quietBeforeForcedFormatChange: Duration = .seconds(2)
    static let pausedRequestInterval: Duration = .seconds(2)
    static let statisticsWindow: Duration = .seconds(2)
    static let scaleAnswerTimeout: Duration = .seconds(10)
    static let displayAnswerTimeout: Duration = .seconds(10)
    static let densitySettle: Duration = .seconds(1)
    /// As fast as the Mac captures: 0, as Apple's viewer arms a running session. On 003.889 a Mac
    /// sends pictures only by its pushes, and on the owner's Mac (a Retina display beside a 1x one,
    /// both changing) remotex's one push per video frame (33,333) starved or blackened the second
    /// display — 1,032 repaints to 32 one run, 130 to 131 with it black the next — where 0 repainted
    /// both evenly with their pictures (probe `--compare`, `--compare2`, 2026-10-11). remotex's cost
    /// of 0: a Mac reads nothing while it pushes, so a viewer that drains slowly has its input left
    /// unread; it measured that with a gateway held to 15% of a core. A Mac also throttles itself by
    /// what the connection drains (the notes, "Other messages").
    static let pushInterval: UInt32 = 0
    /// The all-ones interval: a Mac pushes nothing while it is armed with it.
    static let pushesOff: UInt32 = .max

    /// Two factors the Mac would treat as one.
    static func sameScale(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.005 }

    // MARK: Inputs

    func setQuality(_ value: VNCQuality) {
        lock.withLock {
            guard quality != value else { return }
            quality = value
        }
    }

    /// Nil: the whole framebuffer. Empty: nothing on screen.
    func setRegions(_ value: [RFBRectangle]?) {
        lock.withLock {
            let before = requestRectangle()
            regions = value.map { $0.filter { !$0.isEmpty } }
            let after = requestRectangle()
            // A display coming on screen (or the first after nothing was) is asked for in full, now.
            if let after, before.map({ !$0.contains(after) }) ?? true, started {
                refresh = true; urgent = true
            }
        }
    }

    func start(width: Int, height: Int, dialect: RFBServerDialect = .standard, appleDisplayLayout: Bool = true,
               serverScaling: Bool = true, appleCursor: Bool = true) {
        lock.withLock {
            self.width = width; self.height = height; self.dialect = dialect
            self.appleDisplayLayout = appleDisplayLayout
            self.serverScaling = serverScaling
            self.appleCursor = appleCursor
            // A Mac sends no Tight: Best would send it the same bytes as Balanced.
            governor.highest = dialect == .apple ? .balanced : .best
            startedAt = .now
        }
    }

    /// Which server this is, once the session has started.
    var serverDialect: RFBServerDialect { lock.withLock { dialect } }

    /// A factor to ask a Mac for whatever the level says, in (0, 1]; nil follows the level.
    func setServerScaleOverride(_ value: Double?) {
        lock.withLock {
            scaleOverride = value.flatMap { $0.isFinite && $0 > 0 && $0 <= 1 ? $0 : nil }
        }
    }

    /// Retina displays at 1x (W38): the factor asked of a Mac is divided by the density of the
    /// displays being fetched, where they share one.
    func setDensityScaling(_ value: Bool) {
        lock.withLock {
            guard densityScaling != value else { return }
            densityScaling = value
            // A choice the person made is asked for at once.
            densityDecided = false
        }
    }

    /// The display a Mac is asked to send (`SetDisplay`); nil asks nothing of it.
    func setDisplay(_ value: RFBDisplaySelection?) {
        lock.withLock {
            guard displayWanted != value else { return }
            displayWanted = value
            displayDeclined = nil
        }
    }

    /// A Mac's display layout arrived, stating the scale it renders at and the framebuffer's size
    /// now. Its picture is asked for again in full: the layout may have changed the framebuffer, and
    /// a Mac sends one at every login, lock and user switch. `displays` are the displays in the
    /// framebuffer, `densities` every display's, and `current` the one being sent (nil for all).
    func appleLayoutArrived(serverScale: Double, width: Int, height: Int, displays: [VNCScreen] = [],
                            densities: [UInt32: Double] = [:], current: UInt32? = nil) {
        lock.withLock {
            let previous = scaleInForce
            layoutSeen = true
            scaleInForce = serverScale
            if let asked = scaleAsked, Self.sameScale(asked.factor, serverScale) {
                VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=server-scale confirmed=\(serverScale) width=\(width) height=\(height)")
                scaleAsked = nil
                scaleDeclined = nil
            }
            if !displays.isEmpty { self.displays = displays }
            if !densities.isEmpty { self.densities = densities }
            displayInForce = current
            if let asked = displayAsked, asked.selection.matches(current) {
                VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=display confirmed=\(current.map(String.init) ?? "all")")
                displayAsked = nil
                displayDeclined = nil
            }
            // The windows' regions were in the old scale's pixels; until they say again, ask for the
            // same parts of the picture in the new one.
            if !Self.sameScale(previous, serverScale), let current = regions, previous > 0 {
                regions = current.map { $0.scaled(by: serverScale / previous) }
            }
            self.width = width; self.height = height
            refresh = true; urgent = true
            // A layout drops the Mac's arming: armed again, at the size the layout states.
            armed = nil
        }
    }

    /// The factor a Mac has confirmed it renders at: pointer positions are divided by it. 1 on
    /// every other server, and on a Mac until a layout says otherwise.
    var serverScaleInForce: Double { lock.withLock { scaleInForce } }

    /// The displays in the framebuffer now, for the log.
    var currentDisplays: [VNCScreen] { lock.withLock { displays } }

    /// The area requests ask for now, for the log.
    var requestedArea: RFBRectangle? { lock.withLock { requestRectangle() } }

    /// Requests the server holds, how long since the last went and how long the client has
    /// waited for a message: for the log's flow line.
    func flow(at now: ContinuousClock.Instant) -> (outstanding: Int, sinceRequest: Duration?, waiting: Duration?) {
        lock.withLock { (outstanding, lastRequestAt.map { now - $0 }, waitingSince.map { now - $0 }) }
    }

    /// A factor was asked for and no layout has confirmed it yet.
    var awaitingServerScale: Bool { lock.withLock { scaleAsked != nil } }

    /// The display the last layout said is being sent; nil for all of them, or no layout.
    var currentDisplay: UInt32? { lock.withLock { displayInForce } }

    /// A display was asked for and no layout has confirmed it yet.
    var awaitingDisplay: Bool { lock.withLock { displayAsked != nil } }

    /// A display is wanted and not yet being sent: nothing but a pixel is asked for, and no picture
    /// is handed on.
    var holdingForDisplay: Bool { lock.withLock { holding } }

    /// A display was asked for and no layout confirmed it in time, or a Mac sent no layout at all
    /// within that time, so it could not be asked.
    func displayRefused(at now: ContinuousClock.Instant) -> Bool {
        lock.withLock {
            guard let wanted = displayWanted, wanted.id != nil, dialect == .apple else { return false }
            if displayDeclined == wanted { return true }
            return !layoutSeen && startedAt.map { now - $0 >= Self.displayAnswerTimeout } == true
        }
    }

    /// Waiting for a Mac to send the display wanted alone.
    private var holding: Bool {
        guard let wanted = displayWanted, wanted.id != nil, dialect == .apple, appleDisplayLayout else { return false }
        return !wanted.matches(displayInForce) || !layoutSeen
    }

    /// The messages that open the session: SetPixelFormat and SetEncodings for the level wanted.
    /// The first request follows from `decide` once the client is streaming.
    func openingMessages() -> (pixelFormat: [UInt8], encodings: [UInt8]) {
        lock.withLock {
            active = wantedProfile()
            decoder = (try? RFBPixelDecoder(format: active.colourDepth.pixelFormat)) ?? .native
            advertisedEncodings = RFBEncoding.setEncodingsValues(profile: active, copyRect: wholeFramebufferRequested(), dialect: dialect,
                                                             appleDisplayLayout: appleDisplayLayout, appleCursor: appleCursor)
            started = true
            refresh = true; urgent = true
            return (active.colourDepth.pixelFormat.setPixelFormatMessage, RFBEncoding.setEncodingsMessage(advertisedEncodings))
        }
    }

    func waitingForMessage(at now: ContinuousClock.Instant) {
        lock.withLock { waitingSince = now }
    }

    func messageArrived() {
        lock.withLock { waitingSince = nil }
    }

    /// An update began: the server answered a request. Returns the format its pixels are in.
    func updateBegan() -> RFBPixelDecoder {
        lock.withLock {
            outstanding = max(0, outstanding - 1)
            owed = true
            return decoder
        }
    }

    func framebufferResized(width: Int, height: Int) {
        lock.withLock {
            self.width = width; self.height = height
            refresh = true; urgent = true
        }
    }

    /// An update finished: what it measured, for Automatic and the readout.
    func updateEnded(bytes: Int, seconds: Double, changed: Bool, encodingBytes: [Int32: Int], at now: ContinuousClock.Instant) {
        lock.withLock {
            if encodingBytes[RFBEncoding.tight.rawValue] != nil { serverSendsTight = true }
            samples.append(Sample(at: now, changed: changed, encodingBytes: encodingBytes))
            samples.removeAll { now - $0.at > Self.statisticsWindow }
            if quality == .automatic, let level = governor.observe(bytes: bytes, seconds: seconds, at: now) {
                VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=automatic level=\(level.rawValue) bytes=\(bytes) seconds=\(String(format: "%.3f", seconds))")
            }
        }
    }

    /// A reading of the connection's round trip, every couple of seconds: for Automatic and the
    /// readout.
    func roundTripMeasured(_ reading: RFBTransportRoundTrip, at now: ContinuousClock.Instant) {
        lock.withLock {
            guard let queued = roundTrips.observe(reading, at: now), quality == .automatic,
                  let level = governor.observeQueueing(queued, at: now) else { return }
            VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=automatic level=\(level.rawValue) queued=\(String(format: "%.3f", queued)) roundTrip=\(String(format: "%.3f", reading.smoothed))")
        }
    }

    /// The round trip and the part of it waiting in the network, in seconds, and the level in
    /// effect: for the log's flow line.
    var lateness: (roundTrip: Double?, queued: Double?, level: VNCQuality) {
        lock.withLock { (roundTrips.smoothed, roundTrips.queued, active.level) }
    }

    func currentDecoder() -> RFBPixelDecoder { lock.withLock { decoder } }

    // MARK: Decisions

    /// What to send now, handed to `emit` a message at a time while still deciding, so writes reach
    /// the wire in the order they were decided; and when to look again if something waits on time.
    func decide(at now: ContinuousClock.Instant, emit: ([UInt8]) -> Void) -> ContinuousClock.Instant? {
        lock.withLock {
            guard started else { return nil }
            let (messages, wake) = plan(at: now)
            // One message at a time: on a Mac's record layer each goes in a record of its own.
            for message in messages { emit(message) }
            // One timer at a time: a wake already due no later than this one will look again.
            if let wake, let pending = wakeAt, pending > now, pending <= wake { return nil }
            wakeAt = wake ?? wakeAt
            return wake
        }
    }

    private func plan(at now: ContinuousClock.Instant) -> (messages: [[UInt8]], wake: ContinuousClock.Instant?) {
        do {
            var out: [[UInt8]] = []
            let wanted = wantedProfile()
            if wanted.colourDepth != active.colourDepth {
                let quiet = waitingSince.map { now - $0 >= Self.quietBeforeForcedFormatChange } ?? false
                guard waitingSince != nil, outstanding == 0 || quiet else {
                    // Stop asking until the held request is answered; look again for a quiet line.
                    return ([], now + .milliseconds(500))
                }
                out.append(wanted.colourDepth.pixelFormat.setPixelFormatMessage)
                decoder = (try? RFBPixelDecoder(format: wanted.colourDepth.pixelFormat)) ?? .native
                active = wanted
                refresh = true; urgent = true
            } else if wanted != active {
                active = wanted
            }
            let paused = regions?.isEmpty == true || holding
            // Paused, CopyRect stays as it was: whether it is offered is settled when something is
            // on screen again.
            let copyRect = paused ? advertisedEncodings.contains(RFBEncoding.copyRect.rawValue) : wholeFramebufferRequested()
            var encodings = RFBEncoding.setEncodingsValues(profile: active, copyRect: copyRect, dialect: dialect,
                                                           appleDisplayLayout: appleDisplayLayout, appleCursor: appleCursor)
            if asksForPointerPosition { encodings.append(RFBEncoding.pointerPosition.rawValue) }
            if encodings != advertisedEncodings {
                advertisedEncodings = encodings
                out.append(RFBEncoding.setEncodingsMessage(encodings))
            }
            // The display before the scale it wants, and the request after both.
            let displayWake = planDisplay(at: now, into: &out)
            let scaleWake = planScale(at: now, into: &out)
            planArming(paused: paused, into: &out)

            var wake: ContinuousClock.Instant?
            if let bounds = displaySwitchRequest {
                // With SetDisplay, the whole picture in the bounds the Mac has now: it answers it
                // for the display it switches to (remotex, `set_display_message`'s caller).
                displaySwitchRequest = nil
                out.append(bounds.updateRequest(incremental: false))
                sent(at: now)
            } else if urgent, !paused, let rectangle = requestRectangle() {
                out.append(rectangle.updateRequest(incremental: !refresh))
                sent(at: now)
            } else if holding, urgent || owed {
                // Waiting for a layout that names the display: a pixel at a time, enough to carry it.
                let due = urgent ? now : (lastRequestAt.map { $0 + Self.pausedRequestInterval } ?? now)
                if due <= now {
                    out.append(RFBRectangle(x: 0, y: 0, width: min(1, width), height: min(1, height)).updateRequest(incremental: !refresh))
                    sent(at: now)
                } else {
                    wake = due
                }
            } else if owed {
                let interval = paused ? Self.pausedRequestInterval : active.maximumUpdatesPerSecond.map { .seconds(1) / $0 } ?? .zero
                let due = lastRequestAt.map { $0 + interval } ?? now
                if due <= now {
                    // Nothing on screen: keep one request for a single pixel, so the server can still
                    // say the desktop changed size or the cursor changed, at almost no cost.
                    let rectangle = paused ? RFBRectangle(x: 0, y: 0, width: min(1, width), height: min(1, height))
                                           : requestRectangle()
                    if let rectangle, !rectangle.isEmpty {
                        out.append(rectangle.updateRequest(incremental: paused || !refresh))
                        sent(at: now)
                    }
                } else {
                    wake = due
                }
            }
            if urgent, paused { urgent = false }
            return (out, [wake, scaleWake, displayWake].compactMap { $0 }.min())
        }
    }

    /// Arms a Mac's pushes (`AutoFrameBufferUpdate`) once it has sent a layout, and again after each
    /// one, for the whole framebuffer: without them it sends no pointer position or shape, and a
    /// physical display's changes come late (remotex's notes, "Other messages"). Never while a
    /// display or a scale is waiting for its layout: arming is a read of the picture, and one sized
    /// for a picture that is about to shrink is what crashes the Mac's capture agent (the notes,
    /// "Resizing"). Nothing on screen arms them off.
    private func planArming(paused: Bool, into out: inout [[UInt8]]) {
        guard dialect == .apple, arming, appleDisplayLayout, layoutSeen, width > 0, height > 0,
              scaleAsked == nil, displayAsked == nil, !holding else { return }
        let interval = paused ? Self.pushesOff : armingInterval
        if let armed, armed.interval == interval, armed.width == width, armed.height == height { return }
        out.append(RFBAppleDisplayLayout.autoFramebufferUpdateMessage(interval: interval, width: width, height: height))
        armed = (interval, width, height)
    }

    /// Whether a Mac is armed to push (`AutoFrameBufferUpdate`). On unless a probe compares.
    func setArming(_ on: Bool, interval: UInt32 = RFBStreamPlanner.pushInterval) {
        lock.withLock { arming = on; armingInterval = interval; armed = nil }
    }

    /// Asks a Mac for the display wanted, once it has shown it sends layouts; returns when to look
    /// again at an unanswered request.
    private func planDisplay(at now: ContinuousClock.Instant, into out: inout [[UInt8]]) -> ContinuousClock.Instant? {
        guard dialect == .apple, appleDisplayLayout, layoutSeen, let wanted = displayWanted else { return nil }
        if let asked = displayAsked, now - asked.at >= Self.displayAnswerTimeout {
            VNCDiagnostics.note(Self.logger, .error, category: "planner", "event=display unconfirmed=\(asked.selection.id.map(String.init) ?? "all")")
            displayDeclined = asked.selection
            displayAsked = nil
        }
        if displayAsked == nil, !wanted.matches(displayInForce), displayDeclined != wanted {
            out.append(RFBAppleDisplayLayout.setDisplayMessage(wanted.id))
            displayAsked = (wanted, now)
            // The whole picture after it: the Mac answers it for the display it switches to.
            displaySwitchRequest = RFBRectangle(x: 0, y: 0, width: width, height: height)
            refresh = true
            VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=display asked=\(wanted.id.map(String.init) ?? "all")")
        }
        return displayAsked.map { $0.at + Self.displayAnswerTimeout }
    }

    /// Asks a Mac for the scale the level and the displays' density want, once it has shown it sends
    /// layouts; returns when to look again at an unanswered request, or at a density change waiting
    /// to settle.
    private func planScale(at now: ContinuousClock.Instant, into out: inout [[UInt8]]) -> ContinuousClock.Instant? {
        guard dialect == .apple, appleDisplayLayout, serverScaling, layoutSeen else { return nil }
        if let asked = scaleAsked, now - asked.at >= Self.scaleAnswerTimeout {
            VNCDiagnostics.note(Self.logger, .error, category: "planner", "event=server-scale unconfirmed=\(asked.factor) inForce=\(self.scaleInForce)")
            scaleDeclined = asked.factor
            scaleAsked = nil
        }
        let settleWake = settleDensity(at: now)
        let want = scaleOverride ?? Self.combined(active.serverScale, densityFactorInUse)
        if scaleAsked == nil, !Self.sameScale(want, scaleInForce), !(scaleDeclined.map { Self.sameScale($0, want) } ?? false) {
            out.append(RFBAppleDisplayLayout.setServerScalingMessage(want))
            scaleAsked = (want, now)
            VNCDiagnostics.note(Self.logger, .default, category: "planner", "event=server-scale asked=\(want) inForce=\(self.scaleInForce) density=\(self.densityFactorInUse)")
        }
        return [scaleAsked.map { $0.at + Self.scaleAnswerTimeout }, settleWake].compactMap { $0 }.min()
    }

    /// The level's factor times the density's, kept in (0, 1].
    static func combined(_ level: Double, _ density: Double) -> Double {
        let value = level * density
        return value.isFinite && value > 0 ? min(1, value) : 1
    }

    /// Takes the density factor the displays being fetched want: at once the first time, and for a
    /// display chosen with `SetDisplay`; otherwise once it has held for `densitySettle`.
    private func settleDensity(at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        guard let wanted = densityFactor() else { densityPending = nil; return nil }
        if densityDecided, Self.sameScale(wanted, densityFactorInUse) { densityPending = nil; return nil }
        if !densityDecided || selectedDisplay != nil {
            densityFactorInUse = wanted; densityDecided = true; densityPending = nil
            return nil
        }
        if let pending = densityPending, Self.sameScale(pending.factor, wanted) {
            guard now - pending.since >= Self.densitySettle else { return pending.since + Self.densitySettle }
            densityFactorInUse = wanted; densityPending = nil
            return nil
        }
        densityPending = (wanted, now)
        return now + Self.densitySettle
    }

    /// The display a Mac is sending, or about to: the one asked for until a layout answers.
    private var selectedDisplay: UInt32? {
        if let asked = displayAsked { return asked.selection.id }
        return displayInForce
    }

    /// One over the density of the displays being fetched, where they share one; 1 for a mix of 1x
    /// and Retina displays, as Apple's viewer treats it, and with density scaling off. Nil when there
    /// is nothing to say: no displays known, or nothing on screen (the factor stays as it is).
    private func densityFactor() -> Double? {
        guard densityScaling, dialect == .apple else { return 1 }
        let fetched: [Double]
        if let id = selectedDisplay {
            guard let density = densities[id] ?? displays.first(where: { $0.id == id })?.density else { return nil }
            fetched = [density]
        } else if let regions {
            guard !regions.isEmpty else { return nil }
            fetched = displays.filter { display in
                let rectangle = RFBRectangle(x: display.x, y: display.y, width: display.width, height: display.height)
                return regions.contains { $0.intersects(rectangle) }
            }.compactMap(\.density)
        } else {
            fetched = displays.compactMap(\.density)
        }
        guard !fetched.isEmpty else { return nil }
        return Self.densityFactor(fetched)
    }

    /// Apple's viewer's rule (remotex's `mixed_density`): "mixed" is at least one 1x display and at
    /// least one that is not. Mixed, or all 1x, is 1; otherwise one over the highest density.
    static func densityFactor(_ densities: [Double]) -> Double {
        let oneX = densities.filter { abs($0 - 1) <= 0.005 }.count
        guard oneX == 0, let highest = densities.max(), highest > 1 else { return 1 }
        return 1 / highest
    }

    private func sent(at now: ContinuousClock.Instant) {
        outstanding += 1
        owed = false; urgent = false; refresh = false
        lastRequestAt = now
    }

    private func wantedProfile() -> VNCStreamProfile {
        let profile = VNCStreamProfile.profile(for: quality == .automatic ? governor.level : quality)
        var depth = max(profile.colourDepth, dialect.minimumColourDepth)
        // A server sending Tight sends photographic areas as JPEG only at 16 bits or more
        // (TigerVNC's TightJPEGEncoder refuses below); at 8 the same picture goes lossless and
        // costs more — measured on the fixture, 128 KB a frame against 53 KB at Data Saver. So 256
        // colours is only asked of a server that does not send Tight.
        if depth < .thousands, serverSendsTight { depth = .thousands }
        guard depth != profile.colourDepth else { return profile }
        return VNCStreamProfile(level: profile.level, colourDepth: depth, jpegQuality: profile.jpegQuality,
                                compressionLevel: profile.compressionLevel,
                                maximumUpdatesPerSecond: profile.maximumUpdatesPerSecond, serverScale: profile.serverScale)
    }

    /// The bounding rectangle of what is on screen, inside the framebuffer; the whole framebuffer
    /// when everything is; nil when nothing is. A single pixel while waiting for a display.
    private func requestRectangle() -> RFBRectangle? {
        guard width > 0, height > 0 else { return nil }
        if holding { return RFBRectangle(x: 0, y: 0, width: 1, height: 1) }
        let whole = RFBRectangle(x: 0, y: 0, width: width, height: height)
        guard let regions else { return whole }
        // A Mac rendering at a scale other than 1 is asked for the whole picture, never part of it.
        // Asked for one display beside another at half size, it trimmed the area at the seam
        // ("adjust right 2057 2056"), its agent failed to read the scaled part back
        // ("ReadBackResizedScreenData err -30", once a request) and it sent nothing more to any
        // viewer, while input still worked (2026-10-11, the Mac's own log). The whole picture at
        // half size streamed for 606 frames. The scale is still the windows' displays' to decide.
        if dialect == .apple, !Self.sameScale(scaleInForce, 1), !regions.isEmpty { return whole }
        return RFBRectangle.bounding(regions.compactMap { $0.clipped(width: width, height: height) })
    }

    private func wholeFramebufferRequested() -> Bool {
        // Waiting for a display, the pixel asked for is not a region kept current: what decides
        // CopyRect is what will be asked for once the display is being sent, so the encodings, and
        // the layout a Mac sends for each SetEncodings, are not sent twice.
        if holding { return regions == nil }
        guard let rectangle = requestRectangle() else { return regions == nil }
        return rectangle.x == 0 && rectangle.y == 0 && rectangle.width == width && rectangle.height == height
    }

    // MARK: The readout

    func statistics(totalBytes: Int, at now: ContinuousClock.Instant) -> VNCLinkStatistics {
        lock.withLock {
            readings.append((now, totalBytes))
            readings.removeAll { now - $0.at > Self.statisticsWindow + .milliseconds(500) }
            samples.removeAll { now - $0.at > Self.statisticsWindow }
            var rate = 0.0
            if let first = readings.first, let last = readings.last, last.at > first.at {
                let elapsed = last.at - first.at
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                rate = Double(last.total - first.total) / seconds
            }
            let window = Double(Self.statisticsWindow.components.seconds)
            var byEncoding: [Int32: Int] = [:]
            for sample in samples { byEncoding.merge(sample.encodingBytes, uniquingKeysWith: +) }
            let dominant = byEncoding.max { $0.value < $1.value }.flatMap { RFBEncoding(rawValue: $0.key) }
            let rectangle = requestRectangle()
            return VNCLinkStatistics(
                bytesPerSecond: rate,
                updatesPerSecond: Double(samples.filter(\.changed).count) / window,
                profile: active, quality: quality, encoding: dominant,
                measuredKilobitsPerSecond: governor.lastKilobitsPerSecond,
                roundTrip: roundTrips.smoothed, queued: roundTrips.queued,
                regionLimited: regions != nil && !(rectangle.map { $0.width == width && $0.height == height } ?? false),
                paused: regions?.isEmpty == true,
                totalBytes: totalBytes,
                serverScale: dialect == .apple && layoutSeen ? scaleInForce : nil)
        }
    }
}
