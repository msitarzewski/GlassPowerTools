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
// It drives `VNCClient` with the configuration and callbacks `GlassVNCSession` gives it, so what it
// prints is what the app reads; the displays are mapped by the session's own `remoteScreens`.
// The password never appears in a command line or a process list: it is read from a file, or with
// `-` asked for at the terminal with echo off and kept nowhere. A VNC-auth server takes no user
// name; pass "" for it. It sends no input.
//
// Build it in Release, as the app ships, so the sign-in time is the app's:
//   swift build -c release --disable-keychain --product GlassVNCProbe
//
// Usage: GlassVNCProbe <host> <port> <username-or-empty> <password-file | -> [--scale <factor>] [--quality <level>]

let usage = """
usage: GlassVNCProbe <host> <port> <username-or-empty> <password-file | -> [--scale <factor>] [--quality <level>]
  --scale <factor>   ask a Mac to render at this factor, in (0, 1], once it has sent a layout
  --quality <level>  automatic, best, balanced (default), dataSaver or lowest

"""

/// What the client reported, from its connection task.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _info: VNCServerInfo?
    private var _connectedAt: Date?
    private var _firstFrameAt: Date?
    private var _frames = 0
    private var _frameSize: (width: Int, height: Int)?
    private var _metadata: [(at: Date, value: RFBAppleDisplayMetadata)] = []
    private var _screens: [VNCScreen]?
    private var _statistics: VNCLinkStatistics?

    var info: VNCServerInfo? { lock.withLock { _info } }
    var connectedAt: Date? { lock.withLock { _connectedAt } }
    var firstFrameAt: Date? { lock.withLock { _firstFrameAt } }
    var frames: Int { lock.withLock { _frames } }
    var frameSize: (width: Int, height: Int)? { lock.withLock { _frameSize } }
    var metadata: [(at: Date, value: RFBAppleDisplayMetadata)] { lock.withLock { _metadata } }
    var screens: [VNCScreen]? { lock.withLock { _screens } }
    var statistics: VNCLinkStatistics? { lock.withLock { _statistics } }

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
        callbacks.screens = { screens in self.lock.withLock { self._screens = screens } }
        callbacks.appleDisplayMetadata = { value in self.lock.withLock { self._metadata.append((Date(), value)) } }
        callbacks.statistics = { value in self.lock.withLock { self._statistics = value } }
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

func printMetadata(_ entries: ArraySlice<(at: Date, value: RFBAppleDisplayMetadata)>, since started: Date, numbering first: Int) {
    for (offset, entry) in entries.enumerated() {
        let when = seconds(started, entry.at)
        switch entry.value {
        case .layout(let layout):
            print("layout #\(first + offset)      : at \(when), \(layout.payload.count) bytes after its length")
            print("  header       : \(fields(Array(layout.payload.prefix(RFBAppleDisplayLayout.headerBytes)), [2, 2, 2, 2, 2, 4, 4, 2]))")
            print("  decoded      : version \(layout.version), desktop \(layout.pointsWidth) x \(layout.pointsHeight) points, "
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
                print("  record \(index + 1)     : \(fields(raw, [8, 8, 4, 8, 8, 4, 16]))")
                print("    id \(record.id), density \(record.density), scale \(record.scale), flags 0x\(String(record.flags, radix: 16))"
                      + (flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))"))
                print("    points     : \(describe(record.logical))")
                print("    pixels     : \(describe(record.backing))")
            }
            if layout.payload.count > RFBAppleDisplayLayout.headerBytes + layout.records.count * RFBAppleDisplayLayout.recordBytes {
                print("  after records: \(hex(layout.payload[(RFBAppleDisplayLayout.headerBytes + layout.records.count * RFBAppleDisplayLayout.recordBytes)...]))")
            }
        case .unreadableLayout(let payload):
            print("layout #\(first + offset)      : at \(when), UNREADABLE, \(payload.count) bytes after its length")
            print("  bytes        : \(hex(payload))")
        case .displayInfo(let info):
            print("DisplayInfo    : at \(when), width \(info.width), height \(info.height), flags 0x\(String(info.flags, radix: 16)), \(info.records.count) display(s)")
            for (index, record) in info.records.enumerated() { print("  record \(index + 1)     : \(hex(record))") }
        }
    }
}

func printDisplays(_ recorder: Recorder) {
    guard let screens = recorder.screens else {
        print("displays       : none published")
        return
    }
    print("displays       : \(screens.count) published; as the app is given them:")
    for screen in GlassVNCSession.remoteScreens(screens) {
        print("  display \(screen.id)    : \(screen.width) x \(screen.height) at (\(screen.x), \(screen.y))\(screen.isPrimary ? ", main" : "")")
    }
}

func printLink(_ recorder: Recorder, label: String) {
    guard let stats = recorder.statistics else { print("link\(label): no figures yet"); return }
    let kilobits = Int(stats.bytesPerSecond * 8 / 1000)
    let scale = stats.serverScale.map { ", scale \($0)" } ?? ""
    print("link\(label): \(kilobits) kbit/s, \(String(format: "%.1f", stats.updatesPerSecond)) updates/s, colour \(stats.profile.colourDepth.rawValue)-bit, "
          + "encoding \(stats.encoding?.name ?? "none yet"), level \(stats.profile.level.rawValue)\(scale)")
}

func layoutCount(_ entries: [(at: Date, value: RFBAppleDisplayMetadata)]) -> Int {
    entries.filter { if case .layout = $0.value { true } else { false } }.count
}

@main struct Main {
    static func main() async {
        // MARK: Arguments
        var arguments = Array(CommandLine.arguments.dropFirst())
        var scale: Double?
        var quality = VNCQuality.balanced
        while let index = arguments.firstIndex(where: { $0.hasPrefix("--") }) {
            guard index + 1 < arguments.count else { FileHandle.standardError.write(Data(usage.utf8)); exit(2) }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--scale":
                guard let factor = Double(value), factor > 0, factor <= 1 else { FileHandle.standardError.write(Data(usage.utf8)); exit(2) }
                scale = factor
            case "--quality":
                guard let level = VNCQuality(rawValue: value) else { FileHandle.standardError.write(Data(usage.utf8)); exit(2) }
                quality = level
            default:
                FileHandle.standardError.write(Data(usage.utf8)); exit(2)
            }
            arguments.removeSubrange(index...(index + 1))
        }
        guard arguments.count == 4, let port = UInt16(arguments[1]) else {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(2)
        }
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

        // MARK: The run
        let recorder = Recorder()
        let outcome = Outcome()
        let client: VNCClient
        do {
            // As `GlassVNCSession` configures it for a host it has not been refused by.
            client = try VNCClient(configuration: VNCConfiguration(host: host, port: port, username: username, password: password,
                                                                   sharedSession: true, clipboardEnabled: false),
                                   callbacks: recorder.callbacks())
        } catch {
            print("FAILED: \(error.localizedDescription)")
            exit(1)
        }
        client.setQuality(quality)
        #if DEBUG
        print("build          : Debug — the sign-in time is not the app's; build with -c release")
        #else
        print("build          : Release")
        #endif
        let started = Date()
        Task.detached {
            do { try await client.run(); outcome.end(nil) } catch { outcome.end(error) }
        }

        func wait(upTo limit: TimeInterval, until condition: () -> Bool) async -> Bool {
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

        guard await wait(upTo: 90, until: { recorder.connectedAt != nil }), let info = recorder.info,
              let connectedAt = recorder.connectedAt else {
            fail("not signed in within 90 s")
        }
        let keyExchange = info.keyExchangeDuration.map {
            String(format: ", of which the key exchange %.3f s", Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18)
        } ?? ""
        print("signed in      : \(seconds(started, connectedAt)) after connecting\(keyExchange)")
        print("server         : RFB \(info.serverVersion.major).\(String(format: "%03d", info.serverVersion.minor)), negotiated "
              + "\(info.negotiatedVersion.major).\(info.negotiatedVersion.minor), security \(info.securityType.rawValue) "
              + "(\(info.securityType.displayName))" + (info.isAppleScreenSharing ? ", Apple Screen Sharing" : ""))
        print("framebuffer    : \(info.width) x \(info.height) at sign-in")

        guard await wait(upTo: 45, until: { recorder.firstFrameAt != nil }), let firstFrame = recorder.firstFrameAt else {
            fail("no frame within 45 s of signing in")
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
                let confirmed = await wait(upTo: 12, until: {
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
                if let size = recorder.frameSize { print("framebuffer    : \(size.width) x \(size.height) now") }
                printDisplays(recorder)
                let wire = (x: Int((100 / client.serverScale).rounded()), y: Int((100 / client.serverScale).rounded()))
                print("pointer        : (100, 100) in the picture goes to the Mac as (\(wire.x), \(wire.y)); this probe sends none")
                printLink(recorder, label: " at scale  ")
                print("                 move a window or play a video on the Mac during the run to compare the two rates")
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
