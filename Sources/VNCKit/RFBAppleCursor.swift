import Foundation

// Apple Screen Sharing's pointer (RFB 003.889), W38. The owner, on the Vision Pro with a
// two-display Mac (2026-10-11): "the mouse cursor is insanely small on the main display (when
// visible, it disappears) and simply isn't visible on the second, though I can activate the dock
// and it works."
//
// Apple documents none of it. The forms follow remotex's notes and code, measured against macOS 26
// (https://github.com/andrewtheguy/remotex — docs/apple-vnc-889.md, "The record layer" ¶ "The
// cursor cache", "Which encodings make the Mac report its displays", and src/vnc.rs
// `read_cursor_image`, src/vnc_apple.rs `CursorCache`):
//
// - **CursorPos (0x44c, 1100)**: the pointer's position in the rectangle header's x and y, and no
//   payload. remotex advertises it and ignores it; this client draws the pointer there, so a pointer
//   moved at the Mac, or onto a display with a window of its own, is drawn where it is.
// - **The cursor cache (0x450, 1104)**: the rectangle's x and y are the hotspot and its width and
//   height the shape's size; the body is a `u32` cache id and a `u32` compressed length, then that
//   many bytes. A non-zero length *stores* a shape: an independent zlib stream (a fresh inflater
//   each time) of `w·h·4` bytes of BGRX pixels — the fourth byte is not the alpha — followed by a
//   separate `w·h` alpha plane. A zero length *selects* a stored shape, its geometry zeroed. A
//   select for an id never stored leaves the pointer as it is. Shapes are in the Mac's points, not
//   the picture's pixels: the same pixmap whatever the density of the display.
//
// Not yet seen by this project on a real Mac, and not measured by remotex: what space CursorPos is
// in once the Mac renders at a server-side scale, or sends one display (`SetDisplay`).
// `RFBCursorPositionSpace` works it out from the Mac's own answers to this client's pointer events.

/// What arrived about the pointer, as it arrived: for the log and the live probe.
public enum VNCCursorMessage: Sendable, Equatable {
    /// The standard Cursor pseudo-encoding (−239): a shape in the session's pixel format.
    case richCursor(width: Int, height: Int, hotSpotX: Int, hotSpotY: Int)
    /// The standard Cursor pseudo-encoding with an empty rectangle: the server hid its pointer.
    case richCursorHidden
    /// A shape stored in Apple's cursor cache (1104), and whether it decoded.
    case appleStored(id: UInt32, width: Int, height: Int, hotSpotX: Int, hotSpotY: Int, compressedBytes: Int, decoded: Bool)
    /// A stored shape selected by its id; `known` is false for an id never stored.
    case appleSelected(id: UInt32, known: Bool)
    /// Apple's CursorPos (1100), as sent, before any scale is undone.
    case applePosition(x: Int, y: Int)
    /// The standard PointerPos (−232), as sent.
    case pointerPosition(x: Int, y: Int)
}

/// Apple's cursor cache (encoding 1104): shapes stored once under an id, then selected by it.
final class RFBAppleCursorCache {
    /// remotex's `MAX_CURSOR_DIM`.
    static let maximumEdge = 256
    /// remotex's `MAX_CURSOR_BYTES`: a compressed shape's length is not implied by its size.
    static let maximumCompressedBytes = 1 << 20
    /// More shapes than a Mac uses; the oldest goes first.
    static let maximumShapes = 64

    private var shapes: [UInt32: VNCCursorImage] = [:]
    private var order: [UInt32] = []

    /// One rectangle's body: the cache id and the compressed bytes, empty for a select. The whole
    /// body is read before anything is decided, so a shape that will not decode costs the stream
    /// nothing.
    static func readBody(from source: any RFBByteSource) async throws -> (id: UInt32, deflated: [UInt8]) {
        let id = try await source.u32()
        let length = Int(try await source.u32())
        guard length <= maximumCompressedBytes else {
            throw RFBError.resourceLimit("The Mac's pointer shape claims \(length) compressed bytes.")
        }
        return (id, length == 0 ? [] : try await source.read(length))
    }

    enum Outcome: Equatable {
        /// Draw this shape: one just stored, or a stored one selected.
        case shape(VNCCursorImage)
        /// A select for an id never stored: leave the pointer as it is.
        case unknown
        /// A store that did not decode; the stream is still in step and the cache unchanged.
        case unreadable(String)
    }

    func accept(id: UInt32, hotSpotX: Int, hotSpotY: Int, width: Int, height: Int, deflated: [UInt8]) -> Outcome {
        if deflated.isEmpty {
            return shapes[id].map(Outcome.shape) ?? .unknown
        }
        guard width > 0, height > 0, width <= Self.maximumEdge, height <= Self.maximumEdge else {
            return .unreadable("a \(width)×\(height) shape")
        }
        let pixels = width * height
        let raw: [UInt8]
        do {
            // An independent stream each time: Apple does not carry the window from one shape to
            // the next (remotex, "Each store is an independent zlib stream").
            raw = try ZlibInflater().inflate(deflated, expectedOutput: pixels * 5)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        var bgra = Data(count: pixels * 4), mask = Data(count: pixels)
        for pixel in 0..<pixels {
            let alpha = raw[pixels * 4 + pixel]
            bgra[pixel * 4] = raw[pixel * 4]
            bgra[pixel * 4 + 1] = raw[pixel * 4 + 1]
            bgra[pixel * 4 + 2] = raw[pixel * 4 + 2]
            bgra[pixel * 4 + 3] = alpha
            mask[pixel] = alpha == 0 ? 0 : 1
        }
        let shape = VNCCursorImage(width: width, height: height, hotSpotX: min(max(0, hotSpotX), width - 1),
                                   hotSpotY: min(max(0, hotSpotY), height - 1), bgra: bgra, mask: mask, isPointSized: true)
        if shapes[id] == nil {
            order.append(id)
            if order.count > Self.maximumShapes { shapes.removeValue(forKey: order.removeFirst()) }
        }
        shapes[id] = shape
        return .shape(shape)
    }
}

/// Where Apple's CursorPos puts the pointer in the picture this client shows (W38).
///
/// Pointer *events* reach a scaled Mac in its unscaled framebuffer's pixels (remotex's notes,
/// "Server-side scaling in Standard mode"), which says the Mac's own coordinate mapping does not know
/// the viewer's scale. So CursorPos is taken to be unscaled too, until the Mac's own answers say
/// otherwise: after this client moves the pointer, the Mac reports where it went, and a report at the
/// position sent (unscaled) or at the picture's (scaled) settles which. Reports that match neither,
/// over and over — a space this client does not know, such as the whole desktop's while one display
/// is sent — stop the positions being used at all, and the pointer is drawn where it was last put.
struct RFBCursorPositionSpace: Sendable {
    enum Space: Sendable, Equatable { case unknown, unscaled, scaled, untrusted }

    private(set) var space = Space.unknown
    private var sent: [(picture: (x: Int, y: Int), wire: (x: Int, y: Int), at: ContinuousClock.Instant)] = []
    private var misses = 0

    static let window: Duration = .milliseconds(1500)
    /// How long after this client moves the pointer it stays where this client put it.
    static let localAuthority: Duration = .seconds(1)
    static let tolerance = 2
    static let missesBeforeDistrust = 8

    /// This client sent the pointer to `wire`, which is `picture` in the picture it shows.
    mutating func pointerSent(picture: (x: Int, y: Int), wire: (x: Int, y: Int), at now: ContinuousClock.Instant) {
        sent.removeAll { now - $0.at > Self.window }
        sent.append((picture, wire, now))
        if sent.count > 32 { sent.removeFirst(sent.count - 32) }
    }

    /// A reported position in the picture's pixels; nil when it is not in this picture (another
    /// display's, say) or the space is not one this client knows.
    mutating func map(x: Int, y: Int, scale: Double, width: Int, height: Int,
                      at now: ContinuousClock.Instant) -> (x: Int, y: Int)? {
        learn(x: x, y: y, scale: scale, at: now)
        // While this client moves the pointer, it is drawn where this client put it. A Mac busy
        // pushing pictures reads the moves late and reports them late, and each late report dragged
        // the drawn pointer back along its path: real time one moment, far behind the next (the
        // owner on a Vision Pro, 2026-10-11). A report still teaches the space; a position this
        // client did not send — the Mac moving its own pointer — moves it once the client is still.
        if let last = sent.last, now - last.at < Self.localAuthority { return nil }
        let factor = scale.isFinite && scale > 0 && scale < 1 ? scale : 1
        let picture: (x: Int, y: Int)
        switch space {
        case .untrusted: return nil
        case .scaled: picture = (x, y)
        case .unknown, .unscaled:
            picture = (Int((Double(x) * factor).rounded(.down)), Int((Double(y) * factor).rounded(.down)))
        }
        guard picture.x >= 0, picture.y >= 0, picture.x < width, picture.y < height else { return nil }
        return picture
    }

    private mutating func learn(x: Int, y: Int, scale: Double, at now: ContinuousClock.Instant) {
        sent.removeAll { now - $0.at > Self.window }
        guard !sent.isEmpty else { return }
        func near(_ point: (x: Int, y: Int)) -> Bool {
            abs(point.x - x) <= Self.tolerance && abs(point.y - y) <= Self.tolerance
        }
        let wire = sent.contains { near($0.wire) }, picture = sent.contains { near($0.picture) }
        if wire || picture {
            misses = 0
            // At scale 1 both agree, and neither space is told apart; nor does it matter.
            if wire && !picture { space = .unscaled } else if picture && !wire { space = .scaled }
            else if space == .untrusted { space = .unknown }
        } else {
            misses += 1
            if misses >= Self.missesBeforeDistrust { space = .untrusted }
        }
    }
}
