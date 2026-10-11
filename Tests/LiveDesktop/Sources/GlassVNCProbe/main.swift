import Foundation
import GlassRDPTransport
import GlassVNCTransport
import VNCKit

// A live VNC/RFB probe against a real server. Reports how long signing in took, whether real pixels
// arrived, everything a Mac said about its displays (each layout's header and records, raw and
// decoded), the displays the app would be given, and what the link carried. With `--scale` it asks a
// Mac to render smaller and reports whether a layout confirmed it, the framebuffer's new size, and
// the link before and after.
//
// W38 adds what a display window's own connection and the pointer need checking on a real Mac:
// `--display` (SetDisplay: one display's own pixels), `--retina-1x` (the factor a Retina display
// needs for 1x), `--second-session` (a second connection beside the first, as a display window opens
// one), `--cursor` (every pointer message, as it arrives) and `--pointer-check` (which space the
// Mac's CursorPos is in).
//
// `--as-app` (2026-10-11) does what the app did when a headset lost its second display: a second
// connection for the display that is not the main one, the first narrowed to the rest, Retina at
// 1x. It prints the client's own diagnostic lines as they happen, and keeps the inflated bytes of
// any ZRLE rectangle read with bytes left over in `zrle-anomaly-<session>-<n>.bin` in the current
// folder (ignored by git: they hold a little of the Mac's picture).
//
// It drives `VNCClient` with the configuration and callbacks `GlassVNCSession` gives it, so what it
// prints is what the app reads; the displays are mapped by the session's own `remoteScreens`.
// The password never appears in a command line or a process list: it is read from a file, or with
// `-` asked for at the terminal with echo off and kept nowhere. A VNC-auth server takes no user
// name; pass "" for it. It sends no input, except with `--pointer-check`, which moves the pointer
// (no clicks, no keys).
//
// Build it in Release, as the app ships, so the sign-in time is the app's:
//   swift build -c release --disable-keychain --product GlassVNCProbe
//
// Usage: GlassVNCProbe <host> <port> <username-or-empty> <password-file | -> [options]

let usage = """
usage: GlassVNCProbe <host> <port> <username-or-empty> <password-file | -> [options]
  --scale <factor>         ask a Mac to render at this factor, in (0, 1], once it has sent a layout
  --quality <level>        automatic, best, balanced (default), dataSaver or lowest
  --display <id>           ask a Mac to send only this display (SetDisplay), as a display window's own
                           connection does; the id is a layout record's
  --retina-1x              ask a Mac for its Retina displays at 1x (the app's Send at 1x), times the
                           quality level's factor
  --second-session [<id>]  open a second connection beside the first, with the same sign-in, sending
                           display <id> alone (default: a display the first does not send, the main one
                           last), and report both
  --cursor <seconds>       print every pointer message for this long: move the Mac's mouse meanwhile
  --pointer-check          move the Mac's pointer (no clicks) and report where the Mac says it went
  --apple                  answer a Mac in its own revision, RFB 003.889, with its record layer: the
                           session encrypted after sign-in (2026-10-11)
  --no-arm                 do not arm the Mac's pushes (AutoFrameBufferUpdate), as before 2026-10-11, to
                           compare: armed, a Mac should send its pointer's position and shapes
  --compare                with something moving on every display (a video, a clock with seconds), connect
                           four times — Apple's revision armed and not, plain 3.8 armed and not — and
                           report how often each display was repainted (2026-10-11)
  --compare2               the same, four other ways: Apple's revision armed at 33 ms and at 0 (as Apple's
                           viewer arms), without ViewerInfo, and plain 3.8 armed — with pointer messages
  --as-app [<seconds>]     as the app with a display window per display: a second connection for the
                           display that is not the main one, the first narrowed to the rest, Retina at
                           1x; run this long (default 30) printing the client's own log lines

"""

/// What the client reported, from its connection task.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _info: VNCServerInfo?
    private var _connectedAt: Date?
    private var _firstFrameAt: Date?
    private var _frames = 0
    private var _updates = 0
    private var _frameSize: (width: Int, height: Int)?
    private var _metadata: [(at: Date, value: RFBAppleDisplayMetadata)] = []
    private var _screens: [VNCScreen]?
    private var _statistics: VNCLinkStatistics?
    private var _cursor: [(at: Date, value: VNCCursorMessage)] = []
    private var _positions: [(at: Date, x: Int, y: Int)] = []
    private var _anomalies: [RFBZRLETrailingData] = []
    /// Called as each pointer message arrives, for `--cursor`'s live log.
    var onCursor: (@Sendable (Date, VNCCursorMessage) -> Void)?

    var info: VNCServerInfo? { lock.withLock { _info } }
    var connectedAt: Date? { lock.withLock { _connectedAt } }
    var firstFrameAt: Date? { lock.withLock { _firstFrameAt } }
    var frames: Int { lock.withLock { _frames } }
    var updates: Int { lock.withLock { _updates } }
    var frameSize: (width: Int, height: Int)? { lock.withLock { _frameSize } }
    var metadata: [(at: Date, value: RFBAppleDisplayMetadata)] { lock.withLock { _metadata } }
    var screens: [VNCScreen]? { lock.withLock { _screens } }
    var statistics: VNCLinkStatistics? { lock.withLock { _statistics } }
    var cursor: [(at: Date, value: VNCCursorMessage)] { lock.withLock { _cursor } }
    var positions: [(at: Date, x: Int, y: Int)] { lock.withLock { _positions } }
    var anomalies: [RFBZRLETrailingData] { lock.withLock { _anomalies } }

    func callbacks() -> VNCClientCallbacks {
        var callbacks = VNCClientCallbacks()
        callbacks.connected = { info in self.lock.withLock { self._info = info; self._connectedAt = Date() } }
        callbacks.frame = { width, height, _ in
            self.lock.withLock {
                self._frames += 1
                self._frameSize = (width, height)
                if self._firstFrameAt == nil { self._firstFrameAt = Date() }
            }
        }
        callbacks.update = { _ in self.lock.withLock { self._updates += 1 } }
        callbacks.screens = { screens in self.lock.withLock { self._screens = screens } }
        callbacks.appleDisplayMetadata = { value in self.lock.withLock { self._metadata.append((Date(), value)) } }
        callbacks.statistics = { value in self.lock.withLock { self._statistics = value } }
        callbacks.cursorMessage = { value in
            let now = Date()
            let live = self.lock.withLock { () -> (@Sendable (Date, VNCCursorMessage) -> Void)? in
                self._cursor.append((now, value))
                return self.onCursor
            }
            live?(now, value)
        }
        callbacks.cursorPosition = { x, y in self.lock.withLock { self._positions.append((Date(), x, y)) } }
        callbacks.zrleTrailingData = { value in self.lock.withLock { self._anomalies.append(value) } }
        return callbacks
    }
}

/// The run's outcome, once it ends.
final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (any Error)??
    var ended: (any Error)?? { lock.withLock { value } }
    func end(_ error: (any Error)?) { lock.withLock { value = .some(error) } }
}

// MARK: Formatting

func seconds(_ from: Date, _ to: Date) -> String { String(format: "%.2f s", to.timeIntervalSince(from)) }

func hex(_ bytes: some Collection<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// Bytes split at the given field sizes, each field in hex.
func fields(_ bytes: [UInt8], _ sizes: [Int]) -> String {
    var parts: [String] = [], index = 0
    for size in sizes where index < bytes.count {
        parts.append(hex(bytes[index..<min(bytes.count, index + size)]))
        index += size
    }
    if index < bytes.count { parts.append("+" + hex(bytes[index...])) }
    return parts.joined(separator: " ")
}

func describe(_ edges: RFBAppleDisplayLayout.Edges) -> String {
    "(top \(edges.top), left \(edges.left), bottom \(edges.bottom), right \(edges.right)) = \(edges.width) x \(edges.height) at (\(edges.left), \(edges.top))"
}

func printMetadata(_ entries: ArraySlice<(at: Date, value: RFBAppleDisplayMetadata)>, since started: Date, numbering first: Int,
                   prefix: String = "") {
    for (offset, entry) in entries.enumerated() {
        let when = seconds(started, entry.at)
        switch entry.value {
        case .layout(let layout):
            print("\(prefix)layout #\(first + offset)      : at \(when), \(layout.payload.count) bytes after its length")
            print("\(prefix)  header       : \(fields(Array(layout.payload.prefix(RFBAppleDisplayLayout.headerBytes)), [2, 2, 2, 2, 2, 4, 4, 2]))")
            print("\(prefix)  decoded      : version \(layout.version), desktop \(layout.pointsWidth) x \(layout.pointsHeight) points, "
                  + "framebuffer \(layout.framebufferWidth) x \(layout.framebufferHeight) pixels, "
                  + "sending \(layout.currentDisplay.map { "display \($0)" } ?? "all displays (ffffffff)"), "
                  + "state 0x\(String(layout.sessionState, radix: 16)), \(layout.records.count) display(s), scale in force \(layout.serverScale)")
            for (index, record) in layout.records.enumerated() {
                let start = RFBAppleDisplayLayout.headerBytes + index * RFBAppleDisplayLayout.recordBytes
                let raw = Array(layout.payload[start..<(start + RFBAppleDisplayLayout.recordBytes)])
                var flags: [String] = []
                if record.isMain { flags.append("main") }
                if record.isMirrored { flags.append("mirror set") }
                if record.isVirtual { flags.append("virtual") }
                print("\(prefix)  record \(index + 1)     : \(fields(raw, [8, 8, 4, 8, 8, 4, 16]))")
                print("\(prefix)    id \(record.id), density \(record.density), scale \(record.scale), flags 0x\(String(record.flags, radix: 16))"
                      + (flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))"))
                print("\(prefix)    points     : \(describe(record.logical))")
                print("\(prefix)    pixels     : \(describe(record.backing))")
            }
            if layout.payload.count > RFBAppleDisplayLayout.headerBytes + layout.records.count * RFBAppleDisplayLayout.recordBytes {
                print("\(prefix)  after records: \(hex(layout.payload[(RFBAppleDisplayLayout.headerBytes + layout.records.count * RFBAppleDisplayLayout.recordBytes)...]))")
            }
        case .unreadableLayout(let payload):
            print("\(prefix)layout #\(first + offset)      : at \(when), UNREADABLE, \(payload.count) bytes after its length")
            print("\(prefix)  bytes        : \(hex(payload))")
        case .displayInfo(let info):
            print("\(prefix)DisplayInfo    : at \(when), width \(info.width), height \(info.height), flags 0x\(String(info.flags, radix: 16)), \(info.records.count) display(s)")
            for (index, record) in info.records.enumerated() { print("\(prefix)  record \(index + 1)     : \(hex(record))") }
        }
    }
}

func printDisplays(_ recorder: Recorder, prefix: String = "") {
    guard let screens = recorder.screens else {
        print("\(prefix)displays       : none published")
        return
    }
    print("\(prefix)displays       : \(screens.count) published; as the app is given them:")
    for screen in GlassVNCSession.remoteScreens(screens) {
        let density = screen.density.map { ", density \($0)" } ?? ""
        print("\(prefix)  display \(screen.id)    : \(screen.width) x \(screen.height) at (\(screen.x), \(screen.y))\(screen.isPrimary ? ", main" : "")\(density)")
    }
}

func printLink(_ recorder: Recorder, label: String) {
    guard let stats = recorder.statistics else { print("link\(label): no figures yet"); return }
    let kilobits = Int(stats.bytesPerSecond * 8 / 1000)
    let scale = stats.serverScale.map { ", scale \($0)" } ?? ""
    print("link\(label): \(kilobits) kbit/s, \(String(format: "%.1f", stats.updatesPerSecond)) updates/s, colour \(stats.profile.colourDepth.rawValue)-bit, "
          + "encoding \(stats.encoding?.name ?? "none yet"), level \(stats.profile.level.rawValue)\(scale)")
}

func describe(_ message: VNCCursorMessage) -> String {
    switch message {
    case let .richCursor(width, height, x, y):
        "Cursor (-239)          shape \(width) x \(height), hotspot (\(x), \(y))"
    case .richCursorHidden:
        "Cursor (-239)          empty: the Mac hid its pointer"
    case let .appleStored(id, width, height, x, y, bytes, decoded):
        "CursorImage (1104)     stored id \(id), shape \(width) x \(height), hotspot (\(x), \(y)), \(bytes) bytes compressed, "
            + (decoded ? "decoded" : "DID NOT DECODE")
    case let .appleSelected(id, known):
        "CursorImage (1104)     selected id \(id)" + (known ? "" : " — never stored")
    case let .applePosition(x, y):
        "CursorPos (1100)       at (\(x), \(y)) as sent"
    }
}

func layoutCount(_ entries: [(at: Date, value: RFBAppleDisplayMetadata)]) -> Int {
    entries.filter { if case .layout = $0.value { true } else { false } }.count
}

func lastLayout(_ entries: [(at: Date, value: RFBAppleDisplayMetadata)]) -> RFBAppleDisplayLayout? {
    for entry in entries.reversed() { if case .layout(let layout) = entry.value { return layout } }
    return nil
}

/// The factor a Mac would be asked for (the app's rule, `RFBStreamPlanner`): the level's, times one
/// over the density of the displays sent where they share one.
func expectedScale(layout: RFBAppleDisplayLayout?, display: UInt32?, quality: VNCQuality, retina: Bool) -> Double? {
    let level = VNCStreamProfile.profile(for: quality).serverScale
    guard retina, let layout else { return level }
    let densities = layout.densities
    let sent: [Double] = display.map { [densities[$0]].compactMap { $0 } } ?? Array(densities.values)
    guard !sent.isEmpty else { return nil }
    let oneX = sent.filter { abs($0 - 1) <= 0.005 }.count
    let factor = oneX == 0 ? 1 / (sent.max() ?? 1) : 1
    return min(1, level * factor)
}

@main struct Main {
    static func main() async {
        // MARK: Arguments
        var arguments = Array(CommandLine.arguments.dropFirst())
        var scale: Double?
        var quality = VNCQuality.balanced
        var display: UInt32?
        var retina = false
        var secondSession = false
        var secondDisplay: UInt32?
        var cursorSeconds: Double?
        var pointerCheck = false
        var asAppSeconds: Double?
        var arms = true
        var appleProtocol = false
        var compare = false
        var compareSecond = false
        func bad() -> Never { FileHandle.standardError.write(Data(usage.utf8)); exit(2) }
        while let index = arguments.firstIndex(where: { $0.hasPrefix("--") }) {
            let option = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            var consumed = 1
            switch option {
            case "--scale":
                guard let value, let factor = Double(value), factor > 0, factor <= 1 else { bad() }
                scale = factor; consumed = 2
            case "--quality":
                guard let value, let level = VNCQuality(rawValue: value) else { bad() }
                quality = level; consumed = 2
            case "--display":
                guard let value, let id = UInt32(value) else { bad() }
                display = id; consumed = 2
            case "--retina-1x":
                retina = true
            case "--second-session":
                secondSession = true
                if let value, let id = UInt32(value) { secondDisplay = id; consumed = 2 }
            case "--cursor":
                guard let value, let length = Double(value), length > 0, length <= 600 else { bad() }
                cursorSeconds = length; consumed = 2
            case "--pointer-check":
                pointerCheck = true
            case "--compare":
                compare = true
            case "--compare2":
                compare = true; compareSecond = true
            case "--apple":
                appleProtocol = true
            case "--no-arm":
                arms = false
            case "--as-app":
                asAppSeconds = 30
                if let value, let length = Double(value) {
                    guard length > 0, length <= 600 else { bad() }
                    asAppSeconds = length; consumed = 2
                }
                retina = true
            default:
                bad()
            }
            arguments.removeSubrange(index..<(index + consumed))
        }
        guard arguments.count == 4, let port = UInt16(arguments[1]) else { bad() }
        let host = arguments[0], username = arguments[2]
        let password: String
        if arguments[3] == "-" {
            // Asked at the terminal, echo off, and held only in this process.
            var buffer = [CChar](repeating: 0, count: 1024)
            guard let read = readpassphrase("Password: ", &buffer, buffer.count, RPP_REQUIRE_TTY) else {
                FileHandle.standardError.write(Data("could not read a password from the terminal\n".utf8))
                exit(2)
            }
            password = String(cString: read)
            buffer.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        } else {
            guard let stored = try? String(contentsOfFile: arguments[3], encoding: .utf8) else {
                FileHandle.standardError.write(Data("could not read the password file\n".utf8))
                exit(2)
            }
            password = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // MARK: Four connections compared
        if compare {
            print("compare        : four connections, 20 s each; keep something moving on every display")
            let setups: [(name: String, apple: Bool, arms: Bool, interval: UInt32, viewerInfo: Bool)] = compareSecond
                ? [("Apple's revision, armed at 33 ms   ", true, true, 33_333, true),
                   ("Apple's revision, armed at 0       ", true, true, 0, true),
                   ("Apple's revision, no ViewerInfo    ", true, true, 33_333, false),
                   ("plain 3.8, armed at 33 ms          ", false, true, 33_333, true)]
                : [("Apple's revision, armed    ", true, true, 33_333, true), ("Apple's revision, not armed", true, false, 33_333, true),
                   ("plain 3.8, armed           ", false, true, 33_333, true), ("plain 3.8, not armed       ", false, false, 33_333, true)]
            for setup in setups {
                let recorder = Recorder(), outcome = Outcome()
                let client: VNCClient
                do {
                    client = try VNCClient(configuration: VNCConfiguration(host: host, port: port, username: username, password: password,
                                                                           sharedSession: true, clipboardEnabled: false,
                                                                           appleProtocol: setup.apple),
                                           callbacks: recorder.callbacks())
                } catch { print("\(setup.name): FAILED to start: \(error.localizedDescription)"); continue }
                client.setQuality(quality)
                client.setAppleUpdateArming(setup.arms, interval: setup.interval)
                client.setAppleViewerInfo(setup.viewerInfo)
                Task.detached { do { try await client.run(); outcome.end(nil) } catch { outcome.end(error) } }
                let deadline = Date().addingTimeInterval(30)
                while Date() < deadline, recorder.firstFrameAt == nil { if case .some = outcome.ended { break }; try? await Task.sleep(for: .milliseconds(50)) }
                let before = client.rectanglesPainted, updatesBefore = recorder.updates
                try? await Task.sleep(for: .seconds(20))
                let after = client.rectanglesPainted
                let ids = Set(before.keys).union(after.keys).sorted()
                let painted = ids.map { "display \($0): \((after[$0] ?? 0) - (before[$0] ?? 0))" }.joined(separator: ", ")
                var ending = ""
                if case .some(.some(let error)) = outcome.ended { ending = " — ENDED: \(error.localizedDescription)" }
                let shapes = recorder.cursor.filter { if case .appleStored = $0.value { return true }; if case .appleSelected = $0.value { return true }; return false }.count
                let positions = recorder.cursor.filter { if case .applePosition = $0.value { return true }; return false }.count
                print("\(setup.name): \(recorder.updates - updatesBefore) updates in 20 s; rectangles \(painted.isEmpty ? "none" : painted); "
                      + "picture \(client.displayContent ?? "unknown"); pointer shapes \(shapes), positions \(positions)"
                      + "\(client.isEncrypted ? ", encrypted" : "")\(ending)")
                client.cancel()
                try? await Task.sleep(for: .seconds(2))
            }
            exit(0)
        }

        // MARK: The run
        if asAppSeconds != nil {
            let launched = Date()
            VNCDiagnostics.echo { line in print("  log \(String(format: "%6.2f", Date().timeIntervalSince(launched))) s  \(line.split(separator: " ", maxSplits: 1).last ?? "")") }
        }
        let recorder = Recorder()
        let outcome = Outcome()
        /// As `GlassVNCSession` configures it for a host it has not been refused by.
        func makeClient(_ recorder: Recorder, display: UInt32?) throws -> VNCClient {
            let client = try VNCClient(configuration: VNCConfiguration(host: host, port: port, username: username, password: password,
                                                                       sharedSession: true, clipboardEnabled: false, display: display,
                                                                       appleProtocol: appleProtocol),
                                       callbacks: recorder.callbacks())
            client.setQuality(quality)
            client.setDensityScaling(retina)
            client.setAppleUpdateArming(arms)
            return client
        }
        let client: VNCClient
        do { client = try makeClient(recorder, display: display) } catch {
            print("FAILED: \(error.localizedDescription)")
            exit(1)
        }
        #if DEBUG
        print("build          : Debug — the sign-in time is not the app's; build with -c release")
        #else
        print("build          : Release")
        #endif
        print("pushes         : " + (arms ? "armed after each layout (AutoFrameBufferUpdate, as fast as the Mac captures)" : "not armed (--no-arm)"))
        print("asking for     : \(display.map { "display \($0) alone (SetDisplay)" } ?? "every display, as the Mac sends them")"
              + ", quality \(quality.rawValue)" + (retina ? ", Retina displays at 1x" : ", displays at their own pixels"))
        let started = Date()
        Task.detached {
            do { try await client.run(); outcome.end(nil) } catch { outcome.end(error) }
        }

        func wait(upTo limit: TimeInterval, for outcome: Outcome, until condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(limit)
            while Date() < deadline {
                if condition() { return true }
                if case .some = outcome.ended { return condition() }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return condition()
        }

        func fail(_ message: String) -> Never {
            if case .some(.some(let error)) = outcome.ended {
                print("FAILED after \(seconds(started, Date())): \(error.localizedDescription)")
            } else {
                print("FAILED: \(message)")
            }
            printMetadata(recorder.metadata[...], since: started, numbering: 1)
            client.cancel()
            print("RESULT: FAIL")
            exit(1)
        }

        guard await wait(upTo: 90, for: outcome, until: { recorder.connectedAt != nil }), let info = recorder.info,
              let connectedAt = recorder.connectedAt else {
            fail("not signed in within 90 s")
        }
        let keyExchange = info.keyExchangeDuration.map {
            String(format: ", of which the key exchange %.3f s", Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18)
        } ?? ""
        print("signed in      : \(seconds(started, connectedAt)) after connecting\(keyExchange)")
        let answered = "\(info.negotiatedVersion.major).\(info.negotiatedVersion.minor)"
        let encryption = client.isEncrypted ? ", the session encrypted (Apple's record layer)" : ", the session NOT encrypted after sign-in"
        let interesting: [UInt8] = [0x09, 0x0a, 0x12, 0x17, 0x1c, 0x1d, 0x21]
        let accepted = interesting.filter { info.appleAccepts($0) }.map { String(format: "0x%02x", $0) }.joined(separator: " ")
        let commands: String = info.appleCommands == nil ? "" : " — the Mac accepts: " + accepted
        print("protocol       : answered " + answered + encryption + commands)
        print("server         : RFB \(info.serverVersion.major).\(String(format: "%03d", info.serverVersion.minor)), negotiated "
              + "\(info.negotiatedVersion.major).\(info.negotiatedVersion.minor), security \(info.securityType.rawValue) "
              + "(\(info.securityType.displayName))" + (info.isAppleScreenSharing ? ", Apple Screen Sharing" : ""))
        print("framebuffer    : \(info.width) x \(info.height) at sign-in")

        guard await wait(upTo: 45, for: outcome, until: { recorder.firstFrameAt != nil }), let firstFrame = recorder.firstFrameAt else {
            fail(display == nil ? "no frame within 45 s of signing in"
                 : "no frame of display \(display!) within 45 s of signing in (a picture is handed on only once a layout says the display is being sent)")
        }
        print("first frame    : \(seconds(started, firstFrame)) after connecting")

        // A Mac's layout, and the link's figures, come after the first frame: wait a few seconds.
        try? await Task.sleep(for: .seconds(6))
        var printed = recorder.metadata.count
        if printed == 0 {
            print("display info   : none arrived" + (info.isAppleScreenSharing
                  ? " — the Mac sent neither AppleDisplayLayout nor DisplayInfo, though both were asked for" : ""))
        } else {
            printMetadata(recorder.metadata[...], since: started, numbering: 1)
        }
        printDisplays(recorder)
        if let size = recorder.frameSize { print("framebuffer    : \(size.width) x \(size.height) now") }
        printLink(recorder, label: "           ")

        var passed = true
        if let display {
            let current = client.currentDisplay
            if current == display {
                print("selection      : display \(display) — a layout says it is being sent; the framebuffer is its own pixels")
            } else {
                print("selection      : display \(display) NOT confirmed — the last layout sends \(current.map { "display \($0)" } ?? "all displays")")
                passed = false
            }
        }
        if info.isAppleScreenSharing {
            let layout = lastLayout(recorder.metadata)
            let expected = expectedScale(layout: layout, display: display, quality: quality, retina: retina)
            let inForce = client.serverScale
            let agrees = expected.map { abs($0 - inForce) < 0.005 } ?? false
            print("scale          : \(inForce) in force; the app's rule asks for \(expected.map { "\($0)" } ?? "nothing (no densities)")"
                  + (retina ? " (Retina at 1x × quality \(VNCStreamProfile.profile(for: quality).serverScale))" : " (quality only)")
                  + (agrees ? "" : " — NOT what is in force"))
            if scale == nil, !agrees, expected != nil { passed = false }
        }

        if let factor = scale {
            print("")
            let layoutsBefore = layoutCount(recorder.metadata)
            if layoutsBefore == 0 {
                print("scale          : not asked — a Mac is asked only once it has sent a layout, and none arrived")
                passed = false
            } else if abs(client.serverScale - factor) < 0.005 && !client.awaitingServerScaling {
                print("scale          : \(factor) is already in force; nothing to ask")
                printLink(recorder, label: " at scale  ")
            } else {
                let asked = Date()
                client.setServerScaling(factor)
                let confirmed = await wait(upTo: 12, for: outcome, until: {
                    abs(client.serverScale - factor) < 0.005 && !client.awaitingServerScaling
                })
                let newer = recorder.metadata
                printMetadata(newer[printed...], since: started, numbering: layoutCount(Array(newer[..<printed])) + 1)
                printed = newer.count
                if confirmed {
                    print("scale          : asked \(factor), confirmed \(client.serverScale) by a layout after \(seconds(asked, Date()))")
                } else {
                    print("scale          : asked \(factor); no layout confirmed it within 12 s; in force \(client.serverScale)")
                    passed = false
                }
                // Pictures in the new size, and the link's figures over them.
                try? await Task.sleep(for: .seconds(6))
                let latest = recorder.metadata
                printMetadata(latest[printed...], since: started, numbering: layoutCount(Array(latest[..<printed])) + 1)
                printed = latest.count
                if let size = recorder.frameSize { print("framebuffer    : \(size.width) x \(size.height) now") }
                printDisplays(recorder)
                let wire = (x: Int((100 / client.serverScale).rounded()), y: Int((100 / client.serverScale).rounded()))
                print("pointer        : (100, 100) in the picture goes to the Mac as (\(wire.x), \(wire.y)); this probe sends none")
                printLink(recorder, label: " at scale  ")
                print("                 move a window or play a video on the Mac during the run to compare the two rates")
            }
        }

        // MARK: Which space CursorPos is in
        if pointerCheck {
            print("")
            if let size = recorder.frameSize, client.isReady {
                let inForce = client.serverScale
                let targets = [(size.width / 2, size.height / 2), (size.width / 4, size.height / 4), (size.width * 3 / 4, size.height * 3 / 4)]
                var lines: [String] = []
                for target in targets {
                    let before = recorder.cursor.count
                    try? await client.sendPointer(buttonMask: 0, x: target.0, y: target.1)
                    try? await Task.sleep(for: .milliseconds(1200))
                    let wire = (x: Int((Double(target.0) / (inForce < 1 ? inForce : 1)).rounded()),
                                y: Int((Double(target.1) / (inForce < 1 ? inForce : 1)).rounded()))
                    let reported = recorder.cursor[before...].compactMap { entry -> (Int, Int)? in
                        if case .applePosition(let x, let y) = entry.value { return (x, y) } else { return nil }
                    }.last
                    var verdict = "no CursorPos arrived"
                    if let reported {
                        let nearWire = abs(reported.0 - wire.x) <= 2 && abs(reported.1 - wire.y) <= 2
                        let nearPicture = abs(reported.0 - target.0) <= 2 && abs(reported.1 - target.1) <= 2
                        verdict = "CursorPos (\(reported.0), \(reported.1)): "
                            + (nearWire && nearPicture ? "the picture's and the Mac's pixels agree at this scale"
                               : nearWire ? "the Mac's own (unscaled) pixels"
                               : nearPicture ? "the picture's (scaled) pixels" : "NEITHER — another space")
                    }
                    lines.append("pointer check  : sent picture (\(target.0), \(target.1)) = Mac pixels (\(wire.x), \(wire.y)); \(verdict)")
                }
                lines.forEach { print($0) }
                let mapped = recorder.positions.last.map { "(\($0.x), \($0.y))" } ?? "none"
                print("pointer check  : the app would draw the pointer at \(mapped) in a \(size.width) x \(size.height) picture")
            } else {
                print("pointer check  : not run — no picture yet")
                passed = false
            }
        }

        // MARK: The pointer's messages, live
        if let length = cursorSeconds {
            print("")
            print("cursor         : printing every pointer message for \(Int(length)) s — move the Mac's mouse across each display,")
            print("                 into a text field (the I-beam) and over a link (the hand), and type something to hide it")
            let earlier = recorder.cursor.count
            if earlier > 0 {
                print("cursor         : \(earlier) arrived before now:")
                for entry in recorder.cursor { print("  \(seconds(started, entry.at))  \(describe(entry.value))") }
            }
            recorder.onCursor = { at, value in print("  \(seconds(started, at))  \(describe(value))") }
            try? await Task.sleep(for: .seconds(length))
            recorder.onCursor = nil
            let all = recorder.cursor
            var counts: [String: Int] = [:]
            for entry in all {
                let key: String = switch entry.value {
                case .richCursor: "Cursor (-239) shapes"
                case .richCursorHidden: "Cursor (-239) hides"
                case .appleStored: "CursorImage stores"
                case .appleSelected: "CursorImage selects"
                case .applePosition: "CursorPos"
                }
                counts[key, default: 0] += 1
            }
            print("cursor         : " + (counts.isEmpty ? "nothing arrived" : counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")))
            if let size = recorder.frameSize {
                print("cursor         : the picture is \(size.width) x \(size.height) at scale \(client.serverScale); "
                      + "positions the app would use: \(recorder.positions.count), last \(recorder.positions.last.map { "(\($0.x), \($0.y))" } ?? "none")")
            }
        }

        // MARK: As the app does it, with a display window per display
        if let length = asAppSeconds {
            print("")
            let layout = lastLayout(recorder.metadata)
            let main = layout?.records.first { $0.isMain }?.id
            if let layout, layout.records.count >= 2, let target = layout.records.map(\.id).first(where: { $0 != main }) {
                let second = Recorder()
                let secondOutcome = Outcome()
                let secondClient: VNCClient
                do { secondClient = try makeClient(second, display: target) } catch {
                    print("as the app     : the second connection did not start: \(error.localizedDescription)")
                    exit(1)
                }
                let begun = Date()
                print("as the app     : a second connection for display \(target) alone, as its window's")
                Task.detached {
                    do { try await secondClient.run(); secondOutcome.end(nil) } catch { secondOutcome.end(error) }
                }
                let pictured = await wait(upTo: 60, for: secondOutcome, until: { second.firstFrameAt != nil })
                print("as the app     : " + (pictured ? "its first picture after \(seconds(begun, Date()))" : "NO picture from it within 60 s"))
                // The first is narrowed to the displays the second does not send, in the first's own
                // pixels, and again whenever its displays move (a scale changes every rectangle).
                var narrowedTo: [VNCScreen]?
                func narrow() {
                    guard let screens = recorder.screens else { return }
                    let rest = screens.filter { $0.id != target }
                    guard rest != narrowedTo, !rest.isEmpty else { return }
                    narrowedTo = rest
                    let regions = rest.map { RFBRectangle(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
                    client.setRequestedRegions(regions)
                    print("as the app     : the first asks for " + regions.map { "\($0.x),\($0.y) \($0.width)x\($0.height)" }.joined(separator: " and "))
                }
                let until = Date().addingTimeInterval(length)
                let updatesBefore = recorder.updates
                while Date() < until {
                    narrow()
                    if case .some = outcome.ended { break }
                    if case .some = secondOutcome.ended { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let firstAlive: Bool = if case .some = outcome.ended { false } else { true }
                let secondAlive: Bool = if case .some = secondOutcome.ended { false } else { true }
                print("as the app     : the first " + (firstAlive ? "still connected" : "ENDED")
                      + ", \(recorder.updates - updatesBefore) updates, scale \(client.serverScale), "
                      + "sending \(client.currentDisplay.map { "display \($0)" } ?? "all displays")")
                if case .some(.some(let error)) = outcome.ended { print("                 it ended: \(error.localizedDescription)") }
                print("as the app     : the second " + (secondAlive ? "still connected" : "ENDED")
                      + ", \(second.updates) updates, scale \(secondClient.serverScale), "
                      + "sending \(secondClient.currentDisplay.map { "display \($0)" } ?? "all displays")")
                if case .some(.some(let error)) = secondOutcome.ended { print("                 it ended: \(error.localizedDescription)") }
                for (label, found) in [("first", recorder.anomalies), ("second", second.anomalies)] {
                    for (index, anomaly) in found.enumerated() {
                        let name = "zrle-anomaly-\(label)-\(index + 1).bin"
                        let kept = FileManager.default.createFile(atPath: name, contents: Data(anomaly.inflated))
                        print("ZRLE anomaly   : \(label) #\(index + 1) \(anomaly.summary)" + (kept ? " — kept in \(name)" : ""))
                    }
                }
                if !firstAlive || !secondAlive || !recorder.anomalies.isEmpty || !second.anomalies.isEmpty { passed = false }
                secondClient.cancel()
            } else {
                print("as the app     : nothing to do — the Mac reported \(layout?.records.count ?? 0) display(s); this needs two")
                passed = false
            }
        }

        // MARK: A second connection beside the first
        if secondSession {
            print("")
            let layout = lastLayout(recorder.metadata)
            let target = secondDisplay ?? layout.flatMap { layout in
                let ids = layout.records.map(\.id)
                let notFirst = ids.filter { $0 != display }
                return notFirst.first { id in !(layout.records.first { $0.id == id }?.isMain ?? false) } ?? notFirst.first
            }
            if let target {
                let second = Recorder()
                let secondOutcome = Outcome()
                let firstUpdatesBefore = recorder.updates, firstFramesBefore = recorder.frames
                let secondClient: VNCClient
                do { secondClient = try makeClient(second, display: target) } catch {
                    print("second session : FAILED to start: \(error.localizedDescription)")
                    client.cancel()
                    print("RESULT: FAIL")
                    exit(1)
                }
                let secondStarted = Date()
                print("second session : opening, the same sign-in, asking for display \(target) alone")
                Task.detached {
                    do { try await secondClient.run(); secondOutcome.end(nil) } catch { secondOutcome.end(error) }
                }
                let signedIn = await wait(upTo: 60, for: secondOutcome, until: { second.connectedAt != nil })
                if signedIn, let at = second.connectedAt {
                    print("second session : signed in \(seconds(secondStarted, at)) after connecting")
                    let pictured = await wait(upTo: 20, for: secondOutcome, until: { second.firstFrameAt != nil })
                    try? await Task.sleep(for: .seconds(6))
                    printMetadata(second.metadata[...], since: secondStarted, numbering: 1, prefix: "  2: ")
                    printDisplays(second, prefix: "  2: ")
                    if pictured, let size = second.frameSize {
                        print("second session : framebuffer \(size.width) x \(size.height), display \(secondClient.currentDisplay.map(String.init) ?? "all") "
                              + "being sent, scale \(secondClient.serverScale) in force, \(second.frames) frames")
                        let expected = expectedScale(layout: lastLayout(second.metadata), display: target, quality: quality, retina: retina)
                        print("second session : the app's rule asks for scale \(expected.map { "\($0)" } ?? "nothing")"
                              + ((expected.map { abs($0 - secondClient.serverScale) < 0.005 } ?? false) ? "; in force" : "; NOT in force"))
                        if secondClient.currentDisplay != target { passed = false }
                    } else if case .some(.some(let error)) = secondOutcome.ended {
                        print("second session : ENDED with no picture: \(error.localizedDescription)")
                        passed = false
                    } else {
                        print("second session : no picture of display \(target) within 20 s")
                        passed = false
                    }
                    printLink(second, label: " (second)  ")
                } else if case .some(.some(let error)) = secondOutcome.ended {
                    print("second session : REFUSED or failed: \(error.localizedDescription)")
                    passed = false
                } else {
                    print("second session : not signed in within 60 s")
                    passed = false
                }
                // The first session, while the second ran.
                let firstAlive: Bool = if case .some = outcome.ended { false } else { true }
                print("first session  : " + (firstAlive ? "still connected" : "ENDED while the second ran")
                      + ", \(recorder.updates - firstUpdatesBefore) updates and \(recorder.frames - firstFramesBefore) frames meanwhile, "
                      + "sending \(client.currentDisplay.map { "display \($0)" } ?? "all displays") at scale \(client.serverScale)")
                if !firstAlive { passed = false }
                printLink(recorder, label: " (first)   ")
                secondClient.cancel()
                try? await Task.sleep(for: .seconds(3))
                let stillAlive: Bool = if case .some = outcome.ended { false } else { true }
                print("first session  : " + (stillAlive ? "still connected after the second closed" : "ENDED when the second closed"))
                if !stillAlive { passed = false }
            } else {
                print("second session : not opened — no display to ask for (no layout arrived, or the Mac has one display)")
                passed = false
            }
        }

        if case .some(.some(let error)) = outcome.ended {
            print("ended early    : \(error.localizedDescription)")
            passed = false
        }
        print("frames seen    : \(recorder.frames)")
        client.cancel()
        try? await Task.sleep(for: .milliseconds(200))
        print(passed ? "RESULT: PASS" : "RESULT: FAIL")
        exit(passed ? 0 : 1)
    }
}
