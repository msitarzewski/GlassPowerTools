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
//   before encoding it (`RFBAppleDisplays.swift`). Every encoding shrinks with the pixel count.
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

    public init(bytesPerSecond: Double, updatesPerSecond: Double, profile: VNCStreamProfile, quality: VNCQuality,
                encoding: RFBEncoding?, measuredKilobitsPerSecond: Double?, regionLimited: Bool, paused: Bool,
                totalBytes: Int, serverScale: Double? = nil) {
        self.bytesPerSecond = bytesPerSecond; self.updatesPerSecond = updatesPerSecond; self.profile = profile
        self.quality = quality; self.encoding = encoding; self.measuredKilobitsPerSecond = measuredKilobitsPerSecond
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
        case .appleDisplayInfo: "AppleDisplayInfo"
        case .appleDisplayLayout: "AppleDisplayLayout"
        }
    }
}

/// Which server this is, where it changes what to ask for. Apple's announces RFB 003.889.
///
/// What is known of Apple's server, from others' measurements (Apple documents none of it):
/// asked for Tight it answers with Raw, and it uses ZRLE when offered; it reports its displays only
/// through its own layout, never ExtendedDesktopSize, and only to a client listing both its layout
/// and `DisplayInfo`; it can render its framebuffer smaller (`RFBAppleDisplays.swift`); and older
/// macOS versions ended the session when a client asked for fewer than 15 bits of colour. So for
/// Apple: ZRLE first, both display encodings, server-side scaling in the lower levels, and colour no
/// lower than 16 bits.
enum RFBServerDialect: Sendable, Equatable {
    case standard, apple

    init(version: RFBProtocolVersion) {
        self = version.major == 3 && version.minor == 889 ? .apple : .standard
    }

    var minimumColourDepth: RFBColourDepth { self == .apple ? .thousands : .colours256 }
}

// MARK: - The link governor

/// Chooses Automatic's level from how fast update data actually arrives, measured at the connection
/// for every encoding — so a server that never sends Tight still has its colour depth and update
/// rate stepped down on a slow link, not only a JPEG quality it ignores.
///
/// A measurement is one update of at least 16 KB: its bytes over the time they took to arrive.
/// Smaller updates say more about latency than speed and are ignored. Going down takes three
/// measurements in a row below the current level; going up takes five in a row at least 25% above
/// the next level's floor, one level at a time, so a burst does not flip the picture back and forth
/// and a level that only just fits is not chosen.
struct RFBLinkQualityGovernor: Sendable {
    /// Never `.automatic`.
    private(set) var level: VNCQuality = .balanced
    private(set) var lastKilobitsPerSecond: Double?
    private var downward: [VNCQuality] = []
    private var upward = 0

    static let minimumBytes = 16 * 1024
    static let measurementsToStepDown = 3
    static let measurementsToStepUp = 5
    static let upwardMargin = 1.25

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

    /// One update: its bytes and how long they took to arrive. Returns the new level when it changes.
    mutating func observe(bytes: Int, seconds: Double) -> VNCQuality? {
        guard bytes >= Self.minimumBytes, seconds > 0.001, seconds.isFinite else { return nil }
        let rate = Double(bytes) * 8 / 1000 / seconds
        lastKilobitsPerSecond = rate
        let measured = Self.level(forKilobitsPerSecond: rate), current = Self.rank(level)
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
        guard current + 1 < VNCQuality.ladder.count else { upward = 0; return nil }
        let next = VNCQuality.ladder[current + 1]
        guard rate >= Self.floor(of: next) * Self.upwardMargin else { upward = 0; return nil }
        upward += 1
        guard upward >= Self.measurementsToStepUp else { return nil }
        upward = 0
        level = next
        return next
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
                                   dialect: RFBServerDialect = .standard, appleDisplayLayout: Bool = true) -> [Int32] {
        var order = advertised
        if dialect == .apple {
            // Apple's server answers a Tight preference with Raw; ZRLE first. It reports its
            // displays only to a client listing both of its display encodings (`RFBAppleDisplays.swift`).
            order.removeAll { $0 == .zrle }
            order.insert(.zrle, at: 0)
            if appleDisplayLayout { order += [.appleDisplayInfo, .appleDisplayLayout] }
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
final class RFBStreamPlanner: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.glassdt.vnc", category: "planner")
    private let lock = NSLock()

    // The level.
    private var quality: VNCQuality = .automatic
    private var governor = RFBLinkQualityGovernor()
    private var active = VNCStreamProfile.balanced
    private var decoder = RFBPixelDecoder.native
    private var advertisedEncodings: [Int32] = []

    // Requests.
    private var started = false
    private var dialect = RFBServerDialect.standard
    private var appleDisplayLayout = true
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

    // The readout.
    private struct Sample { let at: ContinuousClock.Instant; let changed: Bool; let encodingBytes: [Int32: Int] }
    private var samples: [Sample] = []
    private var readings: [(at: ContinuousClock.Instant, total: Int)] = []

    static let quietBeforeForcedFormatChange: Duration = .seconds(2)
    static let pausedRequestInterval: Duration = .seconds(2)
    static let statisticsWindow: Duration = .seconds(2)
    static let scaleAnswerTimeout: Duration = .seconds(10)

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
               serverScaling: Bool = true) {
        lock.withLock {
            self.width = width; self.height = height; self.dialect = dialect
            self.appleDisplayLayout = appleDisplayLayout
            self.serverScaling = serverScaling
        }
    }

    /// A factor to ask a Mac for whatever the level says, in (0, 1]; nil follows the level.
    func setServerScaleOverride(_ value: Double?) {
        lock.withLock {
            scaleOverride = value.flatMap { $0.isFinite && $0 > 0 && $0 <= 1 ? $0 : nil }
        }
    }

    /// A Mac's display layout arrived, stating the scale it renders at and the framebuffer's size
    /// now. Its picture is asked for again in full: the layout may have changed the framebuffer, and
    /// a Mac sends one at every login, lock and user switch.
    func appleLayoutArrived(serverScale: Double, width: Int, height: Int) {
        lock.withLock {
            let previous = scaleInForce
            layoutSeen = true
            scaleInForce = serverScale
            if let asked = scaleAsked, Self.sameScale(asked.factor, serverScale) {
                Self.logger.notice("event=server-scale confirmed=\(serverScale) width=\(width) height=\(height)")
                scaleAsked = nil
                scaleDeclined = nil
            }
            // The windows' regions were in the old scale's pixels; until they say again, ask for the
            // same parts of the picture in the new one.
            if !Self.sameScale(previous, serverScale), let current = regions, previous > 0 {
                regions = current.map { $0.scaled(by: serverScale / previous) }
            }
            self.width = width; self.height = height
            refresh = true; urgent = true
        }
    }

    /// The factor a Mac has confirmed it renders at: pointer positions are divided by it. 1 on
    /// every other server, and on a Mac until a layout says otherwise.
    var serverScaleInForce: Double { lock.withLock { scaleInForce } }

    /// A factor was asked for and no layout has confirmed it yet.
    var awaitingServerScale: Bool { lock.withLock { scaleAsked != nil } }

    /// The messages that open the session: SetPixelFormat and SetEncodings for the level wanted.
    /// The first request follows from `decide` once the client is streaming.
    func openingMessages() -> (pixelFormat: [UInt8], encodings: [UInt8]) {
        lock.withLock {
            active = wantedProfile()
            decoder = (try? RFBPixelDecoder(format: active.colourDepth.pixelFormat)) ?? .native
            advertisedEncodings = RFBEncoding.setEncodingsValues(profile: active, copyRect: wholeFramebufferRequested(), dialect: dialect,
                                                             appleDisplayLayout: appleDisplayLayout)
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
            if quality == .automatic { _ = governor.observe(bytes: bytes, seconds: seconds) }
        }
    }

    func currentDecoder() -> RFBPixelDecoder { lock.withLock { decoder } }

    // MARK: Decisions

    /// What to send now, handed to `emit` as one write while still deciding, so writes reach the
    /// wire in the order they were decided; and when to look again if something waits on time.
    func decide(at now: ContinuousClock.Instant, emit: ([UInt8]) -> Void) -> ContinuousClock.Instant? {
        lock.withLock {
            guard started else { return nil }
            let (bytes, wake) = plan(at: now)
            if !bytes.isEmpty { emit(bytes) }
            // One timer at a time: a wake already due no later than this one will look again.
            if let wake, let pending = wakeAt, pending > now, pending <= wake { return nil }
            wakeAt = wake ?? wakeAt
            return wake
        }
    }

    private func plan(at now: ContinuousClock.Instant) -> (bytes: [UInt8], wake: ContinuousClock.Instant?) {
        do {
            var out: [UInt8] = []
            let wanted = wantedProfile()
            if wanted.colourDepth != active.colourDepth {
                let quiet = waitingSince.map { now - $0 >= Self.quietBeforeForcedFormatChange } ?? false
                guard waitingSince != nil, outstanding == 0 || quiet else {
                    // Stop asking until the held request is answered; look again for a quiet line.
                    return ([], now + .milliseconds(500))
                }
                out += wanted.colourDepth.pixelFormat.setPixelFormatMessage
                decoder = (try? RFBPixelDecoder(format: wanted.colourDepth.pixelFormat)) ?? .native
                active = wanted
                refresh = true; urgent = true
            } else if wanted != active {
                active = wanted
            }
            let paused = regions?.isEmpty == true
            // Paused, CopyRect stays as it was: whether it is offered is settled when something is
            // on screen again.
            let copyRect = paused ? advertisedEncodings.contains(RFBEncoding.copyRect.rawValue) : wholeFramebufferRequested()
            let encodings = RFBEncoding.setEncodingsValues(profile: active, copyRect: copyRect, dialect: dialect,
                                                           appleDisplayLayout: appleDisplayLayout)
            if encodings != advertisedEncodings {
                advertisedEncodings = encodings
                out += RFBEncoding.setEncodingsMessage(encodings)
            }
            let scaleWake = planScale(at: now, into: &out)

            var wake: ContinuousClock.Instant?
            if urgent, !paused, let rectangle = requestRectangle() {
                out += rectangle.updateRequest(incremental: !refresh)
                sent(at: now)
            } else if owed {
                let interval = paused ? Self.pausedRequestInterval : active.maximumUpdatesPerSecond.map { .seconds(1) / $0 } ?? .zero
                let due = lastRequestAt.map { $0 + interval } ?? now
                if due <= now {
                    // Nothing on screen: keep one request for a single pixel, so the server can still
                    // say the desktop changed size or the cursor changed, at almost no cost.
                    let rectangle = paused ? RFBRectangle(x: 0, y: 0, width: min(1, width), height: min(1, height))
                                           : requestRectangle()
                    if let rectangle, !rectangle.isEmpty {
                        out += rectangle.updateRequest(incremental: paused || !refresh)
                        sent(at: now)
                    }
                } else {
                    wake = due
                }
            }
            if urgent, paused { urgent = false }
            return (out, [wake, scaleWake].compactMap { $0 }.min())
        }
    }

    /// Asks a Mac for the scale the level wants, once it has shown it sends layouts; returns when
    /// to look again at an unanswered request.
    private func planScale(at now: ContinuousClock.Instant, into out: inout [UInt8]) -> ContinuousClock.Instant? {
        guard dialect == .apple, appleDisplayLayout, serverScaling, layoutSeen else { return nil }
        if let asked = scaleAsked, now - asked.at >= Self.scaleAnswerTimeout {
            Self.logger.error("event=server-scale unconfirmed=\(asked.factor) inForce=\(self.scaleInForce)")
            scaleDeclined = asked.factor
            scaleAsked = nil
        }
        let want = scaleOverride ?? active.serverScale
        if scaleAsked == nil, !Self.sameScale(want, scaleInForce), !(scaleDeclined.map { Self.sameScale($0, want) } ?? false) {
            out += RFBAppleDisplayLayout.setServerScalingMessage(want)
            scaleAsked = (want, now)
            Self.logger.notice("event=server-scale asked=\(want) inForce=\(self.scaleInForce)")
        }
        return scaleAsked.map { $0.at + Self.scaleAnswerTimeout }
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
    /// when everything is; nil when nothing is.
    private func requestRectangle() -> RFBRectangle? {
        guard width > 0, height > 0 else { return nil }
        let whole = RFBRectangle(x: 0, y: 0, width: width, height: height)
        guard let regions else { return whole }
        return RFBRectangle.bounding(regions.compactMap { $0.clipped(width: width, height: height) })
    }

    private func wholeFramebufferRequested() -> Bool {
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
                regionLimited: regions != nil && !(rectangle.map { $0.width == width && $0.height == height } ?? false),
                paused: regions?.isEmpty == true,
                totalBytes: totalBytes,
                serverScale: dialect == .apple && layoutSeen ? scaleInForce : nil)
        }
    }
}
