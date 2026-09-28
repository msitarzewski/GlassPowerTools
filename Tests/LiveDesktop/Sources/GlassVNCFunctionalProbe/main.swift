import Darwin
import Foundation
import VNCKit

/// Usage: GlassVNCFunctionalProbe host port username artifactDir seconds [fixture-container]
/// The password is read from standard input (a pipe or a terminal with echo disabled) and is
/// never printed or written. Output is one JSON object per line: sanitized metadata only.
///
/// Without a container name the probe only reports what a server does (usable against any VNC
/// server). With the disposable Docker fixture's container name (Docker/tigervnc/run.sh passes it)
/// it also asserts the side effects inside the fixture: the pointer position, a keyboard command
/// that writes a unique marker, cut text in both directions and the SetDesktopSize result. Any
/// failed assertion makes the run fail.
let arguments = CommandLine.arguments
guard arguments.count >= 6, let port = UInt16(arguments[2]), let seconds = Int(arguments[5]) else {
    FileHandle.standardError.write(Data("usage: GlassVNCFunctionalProbe host port username artifactDir seconds < password\n".utf8))
    exit(2)
}
let host = arguments[1], username = arguments[3], artifactDirectory = URL(fileURLWithPath: arguments[4], isDirectory: true)
let fixtureContainer: String? = arguments.count >= 7 && !arguments[6].isEmpty ? arguments[6] : nil

struct ProbeFailure: Error, CustomStringConvertible { let description: String }

/// Runs a command inside the disposable fixture as its unprivileged user on the VNC display.
func fixture(_ command: [String]) -> String? {
    guard let container = fixtureContainer else { return nil }
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKER_BIN"] ?? "/opt/homebrew/bin/docker")
    process.arguments = ["exec", "--user", "glassfixture", "--env", "DISPLAY=:1", container] + command
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

/// Polls `condition` for up to `seconds`; true as soon as it holds.
func eventually(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(200))
    }
    return condition()
}

func readPassword() -> String {
    if isatty(STDIN_FILENO) != 0 {
        var terminal = termios()
        tcgetattr(STDIN_FILENO, &terminal)
        var quiet = terminal
        quiet.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &quiet)
        defer { tcsetattr(STDIN_FILENO, TCSANOW, &terminal) }
        FileHandle.standardError.write(Data("Password: ".utf8))
        let line = readLine(strippingNewline: true) ?? ""
        FileHandle.standardError.write(Data("\n".utf8))
        return line
    }
    return readLine(strippingNewline: true) ?? ""
}

let password = readPassword()
final class Emitter: @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let output = FileHandle.standardOutput
    private let start = Date()
    private let lock = NSLock()
    init() { encoder.outputFormatting = [.sortedKeys] }
    func emit(_ fields: [String: String]) {
        var record = fields
        record["t"] = String(format: "%.3f", Date().timeIntervalSince(start))
        if let data = try? encoder.encode(record) {
            lock.lock(); output.write(data); output.write(Data("\n".utf8)); lock.unlock()
        }
    }
}
let emitter = Emitter()
@Sendable func emit(_ fields: [String: String]) { emitter.emit(fields) }

final class Stats: @unchecked Sendable {
    let lock = NSLock()
    var frames = 0, cursors = 0, texts = 0, bells = 0, resizeSupported = false
    var lastSize = (0, 0)
    var firstFrameAt: Date?
    var lastFrame: Data?
    var lastCutText: String?
    var failedChecks: [String] = []
}
let stats = Stats()
final class Finished: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    var value: Bool { lock.withLock { done } }
    func set() { lock.withLock { done = true } }
}
var callbacks = VNCClientCallbacks()
callbacks.connected = { info in
    emit(["event": "connected", "name": String(info.name.prefix(64)), "width": String(info.width), "height": String(info.height),
          "serverVersion": "\(info.serverVersion.major).\(info.serverVersion.minor)",
          "negotiated": "\(info.negotiatedVersion.major).\(info.negotiatedVersion.minor)",
          "security": String(info.securityType.rawValue), "serverBitsPerPixel": String(info.serverPixelFormat.bitsPerPixel)])
}
callbacks.frame = { width, height, data in
    stats.lock.lock()
    stats.frames += 1
    if stats.firstFrameAt == nil { stats.firstFrameAt = Date(); emit(["event": "first-frame", "width": String(width), "height": String(height)]) }
    if (width, height) != stats.lastSize { stats.lastSize = (width, height); emit(["event": "frame-size", "width": String(width), "height": String(height)]) }
    stats.lastFrame = data
    stats.lock.unlock()
}
callbacks.cursor = { cursor in
    stats.lock.lock(); stats.cursors += 1; stats.lock.unlock()
    emit(["event": "cursor", "width": String(cursor?.width ?? 0), "height": String(cursor?.height ?? 0)])
}
callbacks.cutText = { text in
    stats.lock.lock(); stats.texts += 1; stats.lastCutText = text; stats.lock.unlock()
    emit(["event": "cut-text", "length": String(text.count)])
}
callbacks.screens = { screens in
    emit(["event": "screens", "count": String(screens.count),
          "layout": screens.map { "\($0.id)@\($0.x),\($0.y) \($0.width)x\($0.height)" }.joined(separator: "; ")])
}
callbacks.desktopResizeSupported = { stats.lock.lock(); stats.resizeSupported = true; stats.lock.unlock(); emit(["event": "desktop-resize-supported"]) }
callbacks.bell = { stats.lock.lock(); stats.bells += 1; stats.lock.unlock(); emit(["event": "bell"]) }

let client = try VNCClient(configuration: VNCConfiguration(host: host, port: port, username: username, password: password,
                                                           clipboardEnabled: true), callbacks: callbacks)
emit(["event": "start", "host": host, "port": String(port), "username": username.isEmpty ? "(none)" : "(set)"])
let finished = Finished()
let runner = Task { () -> String? in
    defer { finished.set() }
    do { try await client.run(); return nil } catch { return (error as? RFBError).map { String(describing: $0) } ?? error.localizedDescription }
}
let driver = Task {
    var waited = 0
    while !client.isReady, waited < 400, !finished.value { try? await Task.sleep(for: .milliseconds(50)); waited += 1 }
    guard client.isReady else { return }
    try? await Task.sleep(for: .seconds(1))
    let size = stats.lock.withLock { stats.lastSize }
    do {
        try await client.sendPointer(buttonMask: 0, x: size.0 / 2, y: size.1 / 2)
        try await client.sendPointer(buttonMask: 1, x: size.0 / 2, y: size.1 / 2)
        try await client.sendPointer(buttonMask: 0, x: size.0 / 2, y: size.1 / 2)
        for scalar in "echo glasspowertools\n".unicodeScalars {
            if let keysym = RFBKeysym.keysym(for: scalar) {
                try await client.sendKey(keysym: keysym, down: true)
                try await client.sendKey(keysym: keysym, down: false)
            }
        }
        emit(["event": "input-sent"])
        try await client.sendCutText("glass probe")
        if stats.lock.withLock({ stats.resizeSupported }) {
            try await client.requestDesktopSize(width: 800, height: 500)
            emit(["event": "resize-requested", "width": "800", "height": "500"])
        }
    } catch {
        emit(["event": "input-error", "error": String(describing: error)])
        stats.lock.withLock { stats.failedChecks.append("input") }
    }
    if fixtureContainer != nil { await verifyFixtureSideEffects(size: size) }
    try? await Task.sleep(for: .seconds(Double(seconds)))
    client.cancel()
}
/// Asserts that what the probe sent actually happened inside the disposable fixture.
func verifyFixtureSideEffects(size: (Int, Int)) async {
    func record(_ name: String, _ passed: Bool) {
        emit(["check": name, "result": passed ? "passed" : "failed"])
        if !passed { stats.lock.withLock { stats.failedChecks.append(name) } }
    }
    do {
        // Pointer: move to a distinctive position and read it back from the X server.
        let target = (size.0 / 2 + 37, size.1 / 2 + 23)
        try await client.sendPointer(buttonMask: 0, x: target.0, y: target.1)
        record("pointer_position", await eventually(5) {
            fixture(["xdotool", "getmouselocation"])?.hasPrefix("x:\(target.0) y:\(target.1) ") == true
        })

        // Keyboard: type a command into the focused xterm that writes a unique marker to a file.
        let marker = "GLASS_VNC_INPUT_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for scalar in "printf '%s' '\(marker)' > /tmp/glass-vnc-input-proof\n".unicodeScalars {
            guard let keysym = RFBKeysym.keysym(for: scalar) else { throw ProbeFailure(description: "no keysym for an input character") }
            try await client.sendKey(keysym: keysym, down: true)
            try await client.sendKey(keysym: keysym, down: false)
        }
        record("keyboard_input", await eventually(10) { fixture(["cat", "/tmp/glass-vnc-input-proof"]) == marker })

        // Client cut text reaches the server's clipboard.
        let clientText = "GLASS_CLIENT_CLIPBOARD_" + UUID().uuidString.prefix(8)
        try await client.sendCutText(clientText)
        record("cut_text_client_to_server", await eventually(10) {
            fixture(["timeout", "3", "xclip", "-selection", "clipboard", "-o"]) == clientText
        })

        // Server clipboard reaches the client as ServerCutText.
        let serverText = "GLASS_SERVER_CLIPBOARD_" + UUID().uuidString.prefix(8)
        _ = fixture(["sh", "-c", "printf '%s' '\(serverText)' | xclip -selection clipboard -i >/dev/null 2>&1"])
        record("cut_text_server_to_client", await eventually(10) { stats.lock.withLock { stats.lastCutText } == serverText })

        // SetDesktopSize: the fixture accepts it, so the framebuffer must become the requested size.
        let resizeSupported = stats.lock.withLock { stats.resizeSupported }
        let resized = await eventually(10) { stats.lock.withLock { stats.lastSize } == (800, 500) }
        record("set_desktop_size", resizeSupported && resized)
    } catch {
        emit(["check": "fixture_input", "result": "failed", "error": String(describing: error)])
        stats.lock.withLock { stats.failedChecks.append("fixture_input") }
    }
}

let failure = await runner.value
_ = await driver.result
let summary = stats.lock.withLock { (stats.frames, stats.cursors, stats.texts, stats.bells, stats.resizeSupported, stats.lastSize, stats.lastFrame) }
let failedChecks = stats.lock.withLock { stats.failedChecks }
if let frame = summary.6, summary.5.0 > 0 {
    // A PPM snapshot of the final framebuffer for visual review; contains remote pixels of a disposable fixture only.
    var ppm = Data("P6\n\(summary.5.0) \(summary.5.1)\n255\n".utf8)
    var rgb = [UInt8](repeating: 0, count: summary.5.0 * summary.5.1 * 3)
    for pixel in 0..<(summary.5.0 * summary.5.1) {
        rgb[pixel * 3] = frame[pixel * 4 + 2]; rgb[pixel * 3 + 1] = frame[pixel * 4 + 1]; rgb[pixel * 3 + 2] = frame[pixel * 4]
    }
    ppm.append(contentsOf: rgb)
    try? ppm.write(to: artifactDirectory.appendingPathComponent("final-frame.ppm"))
    var nonBlack = 0
    for pixel in stride(from: 0, to: frame.count, by: 4) where frame[pixel] != 0 || frame[pixel + 1] != 0 || frame[pixel + 2] != 0 { nonBlack += 1 }
    emit(["event": "snapshot", "nonBlackPixels": String(nonBlack), "totalPixels": String(frame.count / 4)])
}
// A session that ended on its own (not cancelled by the driver), showed no frame, or failed an
// assertion is a failure.
let passed = (failure == nil || failure == "cancelled") && summary.0 > 0 && failedChecks.isEmpty
emit(["event": "finished", "frames": String(summary.0), "cursors": String(summary.1), "cutTexts": String(summary.2), "bells": String(summary.3),
      "resizeSupported": String(summary.4), "width": String(summary.5.0), "height": String(summary.5.1),
      "failedChecks": failedChecks.joined(separator: ","),
      "status": passed ? "success" : "failure", "error": failure ?? ""])
exit(passed ? 0 : 1)
