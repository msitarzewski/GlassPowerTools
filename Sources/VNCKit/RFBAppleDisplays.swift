import Foundation

// Apple Screen Sharing's display metadata and server-side scaling (RFB 003.889). Apple documents
// none of it. The forms here follow remotex's protocol notes, measured against macOS 26:
// https://github.com/andrewtheguy/remotex/blob/main/docs/apple-vnc-889.md — "Which encodings make
// the Mac report its displays", "The display layout", "A layout's length counts what follows it",
// "A display record, as sent" and "Server-side scaling in Standard mode".
//
// What this client relies on from them:
// - A Mac reports its displays only when SetEncodings lists both `AppleDisplayLayout` (1105) and
//   `DisplayInfo` (1101). The layout alone gets nothing; `DisplayInfo` alone gets the older list.
//   Every SetEncodings that lists `DisplayInfo` brings another report, and so does every login,
//   lock, user switch and display change.
// - With `DisplayInfo` listed a Mac sends no DesktopSize: the layout's header is where the
//   framebuffer's size comes from.
// - `SetServerScaling` asks the Mac to render the framebuffer smaller before encoding it. The next
//   layout states the factor, and only a layout confirms it. Pointer events stay in the *unscaled*
//   framebuffer's pixels.
// - `SetDisplay` (0x0d) narrows the framebuffer to one display's own pixels, or puts every display
//   back in it; the next layout names the display being sent, which is the only confirmation
//   ("Picking a physical screen in Standard mode"; remotex's `set_display_message`). W38 sends it on
//   a display window's own connection, so a Retina display and a 1x one can each come at 1x.
//
// Not checked against a Mac by this project yet: `GlassVNCProbe` prints every field so it can be.

/// Apple's display layout (encoding 1105): a Mac's screens, where each sits in the framebuffer, the
/// framebuffer's size and the server-side scale in force. A one-rectangle framebuffer update whose
/// payload is a `u16` counting the bytes after itself (0x14 + displays × 0x38), a 0x14-byte header,
/// then a 0x38-byte record per display.
public struct RFBAppleDisplayLayout: Sendable, Equatable {
    /// Edges, not an origin and a size: a size is a difference of edges.
    public struct Edges: Sendable, Equatable {
        public let top: Int
        public let left: Int
        public let bottom: Int
        public let right: Int
        public var width: Int { right - left }
        public var height: Int { bottom - top }

        public init(top: Int, left: Int, bottom: Int, right: Int) {
            self.top = top; self.left = left; self.bottom = bottom; self.right = right
        }
    }

    /// One display, as the Mac sends it.
    public struct Record: Sendable, Equatable {
        /// The display's native density, 1 or 2; 0 when the Mac could not look its mode up (+0x00).
        public let density: Double
        /// The server-side scale applied to it, 1 unless a client asked for scaling (+0x08).
        public let scale: Double
        /// The display id (+0x10).
        public let id: UInt32
        /// In points, in the Mac's own arrangement (+0x14). Signed: a display left of or above the
        /// main one can have negative edges.
        public let logical: Edges
        /// In framebuffer pixels (+0x1c): where this display's picture is.
        public let backing: Edges
        /// Bit 0 main, bit 1 in a mirror set, bit 2 a dynamic virtual display (+0x24).
        public let flags: UInt32
        /// The display's own pixel format, 16 bytes (+0x28); read only to be shown.
        public let pixelFormat: [UInt8]

        public var isMain: Bool { flags & 0x1 != 0 }
        public var isMirrored: Bool { flags & 0x2 != 0 }
        public var isVirtual: Bool { flags & 0x4 != 0 }

        /// The native density, or, where the Mac sent 0, the one its two rectangles give once the
        /// scale is undone. Nil when neither says.
        public var nativeDensity: Double? {
            if density.isFinite, density > 0 { return density }
            guard logical.width > 0, backing.width > 0 else { return nil }
            return Double(backing.width) / Double(logical.width) / RFBAppleDisplayLayout.validScale(scale)
        }
    }

    /// The header's version (+0x00); 5 on macOS 26.
    public let version: Int
    /// The whole desktop's size in points (+0x02).
    public let pointsWidth: Int
    public let pointsHeight: Int
    /// The framebuffer's size in pixels (+0x06), which changes with the selection and the scale.
    public let framebufferWidth: Int
    public let framebufferHeight: Int
    /// The display being sent, or nil for all of them (`0xffffffff`, +0x0a).
    public let currentDisplay: UInt32?
    /// Session state: on console, obscured, locked, login pending (+0x0e).
    public let sessionState: UInt32
    public let records: [Record]
    /// The payload as it arrived, after the length: for the live probe.
    public let payload: [UInt8]

    public static let headerBytes = 0x14
    public static let recordBytes = 0x38
    public static let maximumDisplays = 25

    /// Reads the length and exactly the bytes it counts, so the stream stays in step whatever they
    /// hold. At most 64 KB by construction.
    public static func readPayload(from source: any RFBByteSource) async throws -> [UInt8] {
        let length = Int(try await source.u16())
        return try await source.read(length)
    }

    /// Nil when the payload is not a layout: too short for its header, or a display count outside
    /// 1–25, or fewer bytes than its records need. Bytes past the last record are allowed, as
    /// Apple's viewer allows them.
    public init?(payload: [UInt8]) {
        guard payload.count >= Self.headerBytes else { return nil }
        var header = ByteReader(payload)
        guard let version = try? header.u16(), let pointsWidth = try? header.u16(), let pointsHeight = try? header.u16(),
              let framebufferWidth = try? header.u16(), let framebufferHeight = try? header.u16(),
              let current = try? header.u32(), let state = try? header.u32(), let count = try? header.u16(),
              (1...Self.maximumDisplays).contains(Int(count)),
              payload.count >= Self.headerBytes + Int(count) * Self.recordBytes else { return nil }
        var records: [Record] = []
        for index in 0..<Int(count) {
            var reader = ByteReader(payload, offset: Self.headerBytes + index * Self.recordBytes)
            guard let density = try? reader.u64(), let scale = try? reader.u64(), let id = try? reader.u32(),
                  let logical = try? Self.edges(&reader, signed: true), let backing = try? Self.edges(&reader, signed: false),
                  let flags = try? reader.u32(), let format = try? reader.bytes(16) else { return nil }
            records.append(Record(density: Double(bitPattern: density), scale: Double(bitPattern: scale), id: id,
                                  logical: logical, backing: backing, flags: flags, pixelFormat: Array(format)))
        }
        self.version = Int(version)
        self.pointsWidth = Int(pointsWidth); self.pointsHeight = Int(pointsHeight)
        self.framebufferWidth = Int(framebufferWidth); self.framebufferHeight = Int(framebufferHeight)
        self.currentDisplay = current == .max ? nil : current
        self.sessionState = state
        self.records = records
        self.payload = payload
    }

    private static func edges(_ reader: inout ByteReader, signed: Bool) throws -> Edges {
        func value() throws -> Int {
            let raw = try reader.u16()
            return signed ? Int(Int16(bitPattern: raw)) : Int(raw)
        }
        let top = try value(), left = try value(), bottom = try value(), right = try value()
        return Edges(top: top, left: left, bottom: bottom, right: right)
    }

    /// The framebuffer size the header gives, when it gives one.
    public var framebufferSize: (width: Int, height: Int)? {
        framebufferWidth > 0 && framebufferHeight > 0 ? (framebufferWidth, framebufferHeight) : nil
    }

    /// The server-side scale in force. `SetServerScaling` is connection-wide, so every record states
    /// the same factor; the first is taken, and a value outside (0, 1] reads as unscaled.
    public var serverScale: Double { Self.validScale(records.first?.scale ?? 1) }

    static func validScale(_ value: Double) -> Double {
        value.isFinite && value > 0 && value <= 1 ? value : 1
    }

    /// The displays a person can be offered, in framebuffer pixels: the first of a mirror set (its
    /// members share an origin and one picture), and none whose rectangles or density do not hold
    /// up — one odd record costs that display, not the whole list.
    ///
    /// The backing rectangles are the framebuffer's pixels after scaling (remotex checks each against
    /// density × scale). Should a Mac send them unscaled instead, they would not fit the scaled
    /// framebuffer while their scaled forms would, and then the scaled forms are used.
    public func screens(inFramebufferWidth width: Int, height: Int) -> [VNCScreen] {
        // One display selected (`SetDisplay`, sent on a display window's own connection, W38): the framebuffer is
        // that display's own pixels, while the records keep their places among all of them
        // (remotex's notes, "Picking a physical screen in Standard mode").
        if let current = currentDisplay {
            guard let record = records.first(where: { $0.id == current }) else { return [] }
            return [VNCScreen(id: current, x: 0, y: 0, width: width, height: height, flags: record.flags, isMain: record.isMain,
                              density: record.nativeDensity)]
        }
        var offered: [VNCScreen] = []
        var origins: [Edges] = []
        for record in records {
            if record.isMirrored, origins.contains(where: { $0.left == record.logical.left && $0.top == record.logical.top }) {
                continue
            }
            guard record.backing.width > 0, record.backing.height > 0, record.logical.width > 0, record.logical.height > 0,
                  let density = record.nativeDensity, (1.0...4.0).contains(density) else { continue }
            origins.append(record.logical)
            offered.append(VNCScreen(id: record.id, x: record.backing.left, y: record.backing.top,
                                     width: record.backing.width, height: record.backing.height,
                                     flags: record.flags, isMain: record.isMain, density: density))
        }
        let fits = { (screen: VNCScreen) in screen.validated(inFramebufferWidth: width, height: height) != nil }
        let factor = serverScale
        if factor < 1, !offered.allSatisfy(fits) {
            let scaled = offered.map { $0.scaled(by: factor) }
            if scaled.allSatisfy(fits) { return scaled }
        }
        return offered.filter(fits)
    }

    /// Every display's own density, by id, whether or not it is in the framebuffer now: what a
    /// display's picture would need to be scaled by to arrive at 1x (W38). A record whose density
    /// cannot be told is left out.
    public var densities: [UInt32: Double] {
        var byID: [UInt32: Double] = [:]
        for record in records {
            if let density = record.nativeDensity, (1.0...4.0).contains(density) { byID[record.id] = density }
        }
        return byID
    }

    // MARK: Scaling

    /// `SetServerScaling`: type 8, a reserved zero, then the factor as a big-endian `f64`, in
    /// (0, 1]. Ten bytes.
    public static func setServerScalingMessage(_ factor: Double) -> [UInt8] {
        let value = validScale(factor)
        return [8, 0] + value.bitPattern.bigEndianBytes
    }

    // MARK: Choosing a display

    /// `SetDisplay`: type 0x0d, a byte that is 1 to combine every display and 0 to send one, a
    /// reserved `u16`, then the display's id as a big-endian `u32` (0 when combining, which the Mac
    /// ignores). Eight bytes, as remotex's `set_display_message` writes them, measured against
    /// macOS 26.
    public static func setDisplayMessage(_ display: UInt32?) -> [UInt8] {
        [0x0d, display == nil ? 1 : 0, 0, 0] + (display ?? 0).bigEndianBytes
    }
}

/// Which of a Mac's displays a connection asks to be sent (`SetDisplay`).
public enum RFBDisplaySelection: Sendable, Equatable {
    /// One display, its own pixels the whole framebuffer.
    case display(UInt32)
    /// Every display in one framebuffer, as a Mac sends them until asked otherwise.
    case allDisplays

    /// The id `SetDisplay` carries; nil combines.
    public var id: UInt32? {
        if case .display(let id) = self { id } else { nil }
    }

    /// Whether a layout sending `current` (nil for all displays) is this selection.
    func matches(_ current: UInt32?) -> Bool { id == current }
}

/// `DisplayInfo` (encoding 1101), the older display list a Mac sends a client that lists it without
/// the layout. A 10-byte header — `u16` width and height, `u32` flags, `u16` display count — then
/// 0x1c bytes per display (remotex's `src/vnc.rs` steps it the same way). The records' form is not
/// published, so they are kept as bytes, and nothing here takes a display list or a size from them.
public struct RFBAppleDisplayInfo: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let flags: UInt32
    public let records: [[UInt8]]

    public static let headerBytes = 10
    public static let recordBytes = 0x1c
    /// More than a Mac can drive; a larger count means the stream is out of step.
    public static let maximumDisplays = 64

    public init(width: Int, height: Int, flags: UInt32, records: [[UInt8]]) {
        self.width = width; self.height = height; self.flags = flags; self.records = records
    }

    public static func read(from source: any RFBByteSource) async throws -> RFBAppleDisplayInfo {
        var header = ByteReader(try await source.read(headerBytes))
        let width = Int(try header.u16()), height = Int(try header.u16()), flags = try header.u32()
        let count = Int(try header.u16())
        guard count <= maximumDisplays else {
            throw RFBError.protocolViolation("The Mac's display list names \(count) displays.")
        }
        let body = try await source.read(count * recordBytes)
        let records = (0..<count).map { Array(body[($0 * recordBytes)..<(($0 + 1) * recordBytes)]) }
        return RFBAppleDisplayInfo(width: width, height: height, flags: flags, records: records)
    }
}

/// What a Mac said about its displays, as it said it: for the log and the live probe.
public enum RFBAppleDisplayMetadata: Sendable, Equatable {
    case layout(RFBAppleDisplayLayout)
    /// A layout payload that did not hold up; the stream stayed in step past it.
    case unreadableLayout([UInt8])
    case displayInfo(RFBAppleDisplayInfo)
}

extension VNCScreen {
    /// This screen at a server-side scale: the origin rounded down and the far edges up, so the
    /// picture it covers stays inside.
    func scaled(by factor: Double) -> VNCScreen {
        let left = Int((Double(x) * factor).rounded(.down)), top = Int((Double(y) * factor).rounded(.down))
        let right = Int((Double(x + width) * factor).rounded(.up)), bottom = Int((Double(y + height) * factor).rounded(.up))
        return VNCScreen(id: id, x: left, y: top, width: right - left, height: bottom - top, flags: flags, isMain: isMain,
                         density: density)
    }
}

extension UInt64 {
    var bigEndianBytes: [UInt8] { (0..<8).map { UInt8((self >> UInt64(56 - 8 * $0)) & 0xFF) } }
}

extension ByteReader {
    mutating func u64() throws -> UInt64 {
        let high = try u32(), low = try u32()
        return UInt64(high) << 32 | UInt64(low)
    }
}
