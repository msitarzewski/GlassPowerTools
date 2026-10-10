import Darwin
import Foundation
import GlassDesktop
import VNCKit

/// W30: a host with two displays, against the disposable TigerVNC fixture only
/// (Docker/tigervnc-displays/run.sh). Usage:
///
///     GlassVNCDisplaysProbe host port artifactDir fixture-container < password
///
/// It asks Xvnc for a two-screen layout (SetDesktopSize with two screens, the way TigerVNC's own
/// viewer asks for several monitors), starts a picture workload on each screen inside the fixture,
/// and then proves, with the app's own code:
///
/// - `two_screens_reported`: the server's ExtendedDesktopSize layout lists both screens.
/// - `region_request_one_display`: asking for one display's rectangle brings only rectangles inside it.
/// - `input_to_display_two`: a click in the middle of a window showing display 2, mapped by the
///   app's `DesktopCoordinates`, lands at the right framebuffer point (read back with xdotool).
/// - `quality_switches_decode`: every quality level, including changes of colour depth mid-session,
///   keeps decoding (the session survives and frames keep coming).
/// - bytes per second for the whole framebuffer, one display, and each level, measured.
/// - Automatic over a rate-limited local proxy (a slow mobile link), and the level it settles on.
///
/// The password is read from standard input and never printed. Output: one JSON object per line.
let arguments = CommandLine.arguments
guard arguments.count >= 5, let port = UInt16(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: GlassVNCDisplaysProbe host port artifactDir container < password\n".utf8))
    exit(2)
}
let host = arguments[1], artifactDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true), container = arguments[4]
let password = readLine(strippingNewline: true) ?? ""

final class Emitter: @unchecked Sendable {
    private let lock = NSLock(), start = Date()
    private var failures: [String] = []
    func emit(_ fields: [String: String]) {
        var record = fields
        record["t"] = String(format: "%.3f", Date().timeIntervalSince(start))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(record) {
            lock.withLock { FileHandle.standardOutput.write(data + Data("\n".utf8)) }
        }
    }
    func check(_ name: String, _ passed: Bool, _ fields: [String: String] = [:]) {
        var record = fields
        record["check"] = name; record["result"] = passed ? "passed" : "failed"
        emit(record)
        if !passed { lock.withLock { failures.append(name) } }
    }
    var failed: [String] { lock.withLock { failures } }
}
let out = Emitter()

/// Runs a command in the fixture as its unprivileged user on the VNC display.
@discardableResult
func fixture(_ command: [String], detach: Bool = false) -> String? {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKER_BIN"] ?? "/opt/homebrew/bin/docker")
    process.arguments = ["exec"] + (detach ? ["--detach"] : []) + ["--user", "glassfixture", "--env", "DISPLAY=:1", container] + command
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

@MainActor func eventually(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(200))
    }
    return condition()
}

// MARK: - A slow link

/// A local TCP proxy that carries the server's bytes no faster than `kilobitsPerSecond`: a mobile
/// link, roughly, for the client on the other side of it. Client-to-server bytes pass untouched.
final class ThrottledProxy: @unchecked Sendable {
    let port: UInt16
    private let listener: Int32

    init(targetPort: UInt16, kilobitsPerSecond: Double) throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        port = UInt16(bigEndian: address.sin_port)
        self.listener = listener
        Thread.detachNewThread {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                let server = socket(AF_INET, SOCK_STREAM, 0)
                var target = sockaddr_in()
                target.sin_family = sa_family_t(AF_INET)
                target.sin_addr.s_addr = inet_addr("127.0.0.1")
                target.sin_port = targetPort.bigEndian
                let connected = withUnsafePointer(to: &target) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                guard connected == 0 else { close(client); close(server); continue }
                Thread.detachNewThread { Self.pump(from: client, to: server, kilobitsPerSecond: nil) }
                Thread.detachNewThread { Self.pump(from: server, to: client, kilobitsPerSecond: kilobitsPerSecond) }
            }
        }
    }

    private static func pump(from source: Int32, to destination: Int32, kilobitsPerSecond: Double?) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let start = Date()
        var sent = 0
        while true {
            let count = read(source, &buffer, buffer.count)
            guard count > 0 else { break }
            var offset = 0
            while offset < count {
                let written = buffer[offset..<count].withUnsafeBytes { write(destination, $0.baseAddress, count - offset) }
                guard written > 0 else { shutdown(source, SHUT_RDWR); shutdown(destination, SHUT_RDWR); return }
                offset += written
            }
            sent += count
            if let kilobitsPerSecond {
                let due = Double(sent) * 8 / (kilobitsPerSecond * 1000)
                let elapsed = Date().timeIntervalSince(start)
                if due > elapsed { usleep(useconds_t((due - elapsed) * 1_000_000)) }
            }
        }
        shutdown(source, SHUT_RDWR); shutdown(destination, SHUT_RDWR)
    }

    func stop() { close(listener) }
}

// MARK: - A session

final class Observed: @unchecked Sendable {
    let lock = NSLock()
    var screens: [VNCScreen] = []
    var resizeSupported = false
    var frames = 0
    var updates: [(at: Date, summary: VNCUpdateSummary)] = []
    var statistics: VNCLinkStatistics?
    var levels: [String] = []
    var lastFrame: (width: Int, height: Int, pixels: Data)?
}

func session(host: String, port: UInt16, quality: VNCQuality = .automatic) throws -> (VNCClient, Observed, Task<String?, Never>) {
    let observed = Observed()
    var callbacks = VNCClientCallbacks()
    callbacks.screens = { screens in observed.lock.withLock { observed.screens = screens } }
    callbacks.desktopResizeSupported = { observed.lock.withLock { observed.resizeSupported = true } }
    callbacks.frame = { width, height, pixels in observed.lock.withLock { observed.frames += 1; observed.lastFrame = (width, height, pixels) } }
    callbacks.update = { summary in observed.lock.withLock { observed.updates.append((Date(), summary)) } }
    callbacks.statistics = { statistics in
        observed.lock.withLock {
            observed.statistics = statistics
            let level = statistics.profile.level.rawValue
            if observed.levels.last != level { observed.levels.append(level) }
        }
    }
    let client = try VNCClient(configuration: VNCConfiguration(host: host, port: port, password: password), callbacks: callbacks)
    client.setQuality(quality)
    let runner = Task { () -> String? in
        do { try await client.run(); return nil } catch { return String(describing: error) }
    }
    return (client, observed, runner)
}

/// Bytes per second while `seconds` pass, with what the link readout says at the end.
@MainActor func measure(_ client: VNCClient, _ observed: Observed, seconds: Double) async -> [String: String] {
    let before = client.totalBytesReceived, framesBefore = observed.lock.withLock { observed.frames }, start = Date()
    try? await Task.sleep(for: .seconds(seconds))
    let elapsed = Date().timeIntervalSince(start)
    let bytes = client.totalBytesReceived - before, frames = observed.lock.withLock { observed.frames } - framesBefore
    let statistics = client.statistics
    return ["bytesPerSecond": String(format: "%.0f", Double(bytes) / elapsed),
            "kilobitsPerSecond": String(format: "%.0f", Double(bytes) * 8 / 1000 / elapsed),
            "framesPerSecond": String(format: "%.1f", Double(frames) / elapsed),
            "level": statistics.profile.level.rawValue, "colourDepth": String(statistics.profile.colourDepth.rawValue),
            "encoding": statistics.encoding?.name ?? "-", "regionLimited": String(statistics.regionLimited)]
}

// MARK: - The run

let layout = [VNCScreen(id: 1, x: 0, y: 0, width: 1280, height: 800, flags: 0),
              VNCScreen(id: 2, x: 1280, y: 32, width: 1024, height: 768, flags: 0)]
let displayOne = RFBRectangle(x: 0, y: 0, width: 1280, height: 800)
let displayTwo = RFBRectangle(x: 1280, y: 32, width: 1024, height: 768)

let (client, observed, runner) = try session(host: host, port: port)
out.emit(["event": "start", "host": host, "port": String(port)])
_ = await eventually(20) { client.isReady && observed.lock.withLock { observed.resizeSupported } }
guard client.isReady else {
    out.check("connected", false, ["error": await runner.value ?? "not ready"])
    exit(1)
}

// Two screens, asked for as TigerVNC's viewer asks for several monitors.
try await client.requestDesktopLayout(width: 2304, height: 800, screens: layout)
let twoScreens = await eventually(15) { observed.lock.withLock { observed.screens.count == 2 } }
let reported = observed.lock.withLock { observed.screens }
out.check("two_screens_reported", twoScreens && reported.map(\.id).sorted() == [1, 2]
          && reported.contains { $0.x == 1280 && $0.y == 32 && $0.width == 1024 && $0.height == 768 },
          ["layout": reported.map { "\($0.id)@\($0.x),\($0.y) \($0.width)x\($0.height)" }.joined(separator: "; ")])

// A picture workload on each display.
fixture(["glass-animate", "60", "60", "1100", "700", "1"], detach: true)
fixture(["glass-animate", "1340", "92", "900", "640", "2"], detach: true)
try? await Task.sleep(for: .seconds(10))

// Only display 2 asked for: every rectangle that arrives lies inside it.
client.setRequestedRegions([displayTwo])
try? await Task.sleep(for: .seconds(2))
let windowStart = Date()
try? await Task.sleep(for: .seconds(4))
let pictureRectangles = observed.lock.withLock {
    observed.updates.filter { $0.at >= windowStart }.flatMap { update in
        zip(update.summary.rectangles, update.summary.encodings)
            .filter { ![.cursor, .lastRect, .desktopSize, .extendedDesktopSize, .appleDisplayLayout].contains($0.1) && !$0.0.isEmpty }
            .map(\.0)
    }
}
let outside = pictureRectangles.filter { !(displayTwo.x <= $0.x && displayTwo.y <= $0.y && $0.maxX <= displayTwo.maxX && $0.maxY <= displayTwo.maxY) }
out.check("region_request_one_display", !pictureRectangles.isEmpty && outside.isEmpty,
          ["rectangles": String(pictureRectangles.count), "outside": String(outside.count)])

// A click in the middle of a 640 × 384-point window showing display 2.
let screenTwo = DesktopRegion(origin: DesktopPoint(x: displayTwo.x, y: displayTwo.y),
                              size: DesktopSize(width: displayTwo.width, height: displayTwo.height))
if let mapped = DesktopCoordinates.map(x: 320, y: 192, viewWidth: 640, viewHeight: 384,
                                       desktop: screenTwo.size, origin: screenTwo.origin) {
    try await client.sendPointer(buttonMask: 0, x: mapped.x, y: mapped.y)
    let landed = await eventually(5) {
        fixture(["xdotool", "getmouselocation"])?.hasPrefix("x:\(mapped.x) y:\(mapped.y) ") == true
    }
    out.check("input_to_display_two", landed && mapped == DesktopPoint(x: 1792, y: 416),
              ["mapped": "\(mapped.x),\(mapped.y)", "xdotool": fixture(["xdotool", "getmouselocation"])?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""])
} else {
    out.check("input_to_display_two", false)
}

// Bytes per second: the whole framebuffer and one display, at each level.
let modes: [(String, [RFBRectangle]?, VNCQuality)] = [
    ("whole, Best", nil, .best), ("display 2 only, Best", [displayTwo], .best),
    ("whole, Balanced", nil, .balanced), ("display 2 only, Balanced", [displayTwo], .balanced),
    ("whole, Data Saver", nil, .dataSaver), ("whole, Lowest", nil, .lowest),
    ("display 1 only, Data Saver", [displayOne], .dataSaver), ("nothing on screen", [], .balanced),
]
var survived = true
for (name, regions, quality) in modes {
    client.setQuality(quality)
    client.setRequestedRegions(regions)
    try? await Task.sleep(for: .seconds(4))
    var fields = await measure(client, observed, seconds: 6)
    fields["event"] = "measurement"; fields["mode"] = name; fields["link"] = "direct"
    out.emit(fields)
    if !client.isReady { survived = false; break }
}
out.check("quality_switches_decode", survived && client.isReady, ["levels": observed.lock.withLock { observed.levels.joined(separator: ">") }])
client.setRequestedRegions(nil)
client.setQuality(.best)
try? await Task.sleep(for: .seconds(3))
if let frame = observed.lock.withLock({ observed.lastFrame }) {
    // A PPM of the final framebuffer: the fixture's own generated picture, for review.
    var ppm = Data("P6\n\(frame.width) \(frame.height)\n255\n".utf8)
    var rgb = [UInt8](repeating: 0, count: frame.width * frame.height * 3)
    frame.pixels.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for pixel in 0..<(frame.width * frame.height) {
            rgb[pixel * 3] = bytes[pixel * 4 + 2]; rgb[pixel * 3 + 1] = bytes[pixel * 4 + 1]; rgb[pixel * 3 + 2] = bytes[pixel * 4]
        }
    }
    ppm.append(contentsOf: rgb)
    try? ppm.write(to: artifactDirectory.appendingPathComponent("two-displays.ppm"))
}
client.cancel()
_ = await runner.value

// Automatic over a slow link.
for kilobits in [2_000.0, 600.0] {
    let proxy = try ThrottledProxy(targetPort: port, kilobitsPerSecond: kilobits)
    let (slow, seen, slowRunner) = try session(host: "127.0.0.1", port: proxy.port, quality: .automatic)
    _ = await eventually(30) { slow.isReady }
    try? await Task.sleep(for: .seconds(20))
    var fields = await measure(slow, seen, seconds: 8)
    fields["event"] = "measurement"; fields["mode"] = "whole, Automatic"
    fields["link"] = String(format: "proxy %.0f kbit/s", kilobits)
    fields["levels"] = seen.lock.withLock { seen.levels.joined(separator: ">") }
    fields["measuredKilobitsPerSecond"] = slow.statistics.measuredKilobitsPerSecond.map { String(format: "%.0f", $0) } ?? "-"
    out.emit(fields)
    let expected: VNCQuality = kilobits >= 750 ? .dataSaver : .lowest
    out.check("automatic_on_\(Int(kilobits))_kbps", slow.isReady && slow.statistics.profile.level == expected,
              ["level": slow.statistics.profile.level.rawValue, "expected": expected.rawValue])
    slow.cancel()
    _ = await slowRunner.value
    proxy.stop()
}

out.emit(["event": "finished", "failedChecks": out.failed.joined(separator: ","), "status": out.failed.isEmpty ? "success" : "failure"])
exit(out.failed.isEmpty ? 0 : 1)
